param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$packageRoot = $PSScriptRoot
$configPath = Join-Path $packageRoot 'Config.ps1'
$CodexPickerConfig = @{}
if (Test-Path -LiteralPath $configPath) {
    . $configPath
    if ($CodexPickerConfig -isnot [hashtable]) {
        throw 'Config.ps1 must define a hashtable named $CodexPickerConfig.'
    }
}

function Get-ConfigValue {
    param(
        [string]$Name,
        [object]$DefaultValue
    )

    if (
        $CodexPickerConfig.ContainsKey($Name) -and
        $null -ne $CodexPickerConfig[$Name] -and
        -not (
            $CodexPickerConfig[$Name] -is [string] -and
            [string]::IsNullOrWhiteSpace($CodexPickerConfig[$Name])
        )
    ) {
        return $CodexPickerConfig[$Name]
    }

    return $DefaultValue
}

function Resolve-PackagePath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path $packageRoot $Path))
}

$portableRoot = Resolve-PackagePath (Get-ConfigValue 'PortableDirectory' 'Codex-Picker')
$unpackedRoot = Resolve-PackagePath (Get-ConfigValue 'UnpackedDirectory' 'app-unpacked')
$generatedModule = Join-Path $unpackedRoot 'webview\assets\opencodex-models.js'
$asarCli = Resolve-PackagePath (Get-ConfigValue 'AsarCliPath' 'tools\node_modules\@electron\asar\bin\asar.mjs')
$builtAsar = Join-Path $packageRoot 'app-patched.asar'
$deployedAsar = Join-Path $portableRoot 'resources\app.asar'
$profileRoot = Resolve-PackagePath (Get-ConfigValue 'ProfileDirectory' 'profile')
$executable = Join-Path $portableRoot (Get-ConfigValue 'ExecutableName' 'ChatGPT.exe')
$windowTitle = Get-ConfigValue 'WindowTitle' 'Codex Picker Patched'

$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $env:CODEX_HOME
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$configuredModelCache = Get-ConfigValue 'ModelCachePath' ''
$modelCache = if ([string]::IsNullOrWhiteSpace($configuredModelCache)) {
    Join-Path $codexHome 'models_cache.json'
} else {
    Resolve-PackagePath $configuredModelCache
}

function Find-NodeExecutable {
    $configuredNode = Get-ConfigValue 'NodePath' ''
    if (-not [string]::IsNullOrWhiteSpace($configuredNode)) {
        return Resolve-PackagePath $configuredNode
    }

    $relativeCandidates = @(
        (Join-Path $packageRoot 'tools\node.exe'),
        (Join-Path $packageRoot 'tools\node\node.exe')
    )

    foreach ($candidate in $relativeCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -ne $nodeCommand) {
        return $nodeCommand.Source
    }

    $runtimeRoot = Join-Path $env:USERPROFILE '.cache\codex-runtimes'
    if (Test-Path -LiteralPath $runtimeRoot) {
        $runtimeNode = Get-ChildItem -LiteralPath $runtimeRoot -Recurse -Filter node.exe -File |
            Where-Object { $_.FullName -like '*\dependencies\node\bin\node.exe' } |
            Select-Object -First 1
        if ($null -ne $runtimeNode) {
            return $runtimeNode.FullName
        }
    }

    throw 'Node.js was not found. Install Node.js or place node.exe under tools\.'
}

$node = Find-NodeExecutable

foreach ($requiredPath in @(
    $modelCache,
    $node,
    $asarCli,
    $unpackedRoot,
    $executable
)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path does not exist: $requiredPath"
    }
}

$queryAsset = Get-ChildItem `
    -LiteralPath (Join-Path $unpackedRoot 'webview\assets') `
    -Filter 'model-queries-*.js' `
    -File |
    Where-Object { (Get-Content -Raw -LiteralPath $_.FullName).Contains('models:ocMerge(r)') } |
    Select-Object -First 1

$composerAsset = Get-ChildItem `
    -LiteralPath (Join-Path $unpackedRoot 'webview\assets') `
    -Filter 'codex-composer-adapter-*.js' `
    -File |
    Where-Object { (Get-Content -Raw -LiteralPath $_.FullName).Contains('models:ocMerge(b)') } |
    Select-Object -First 1

if ($null -eq $queryAsset -or $null -eq $composerAsset) {
    throw 'The unpacked application does not contain the required model-picker patch markers.'
}

$cache = Get-Content -Raw -LiteralPath $modelCache | ConvertFrom-Json
$catalogModels = @(
    $cache.models |
        Where-Object {
            $_.slug -is [string] -and
            $_.slug.Contains('/') -and
            ($_.visibility -eq 'list' -or $null -eq $_.visibility)
        } |
        Sort-Object slug -Unique
)

if ($catalogModels.Count -eq 0) {
    throw "No configured provider models were found in: $modelCache"
}

$stableEfforts = @(
    [ordered]@{ reasoningEffort = 'low'; description = 'low reasoning effort' }
    [ordered]@{ reasoningEffort = 'medium'; description = 'medium reasoning effort' }
    [ordered]@{ reasoningEffort = 'high'; description = 'high reasoning effort' }
    [ordered]@{ reasoningEffort = 'xhigh'; description = 'xhigh reasoning effort' }
)

$customModels = @(
    for ($index = 0; $index -lt $catalogModels.Count; $index++) {
        $catalogModel = $catalogModels[$index]
        [pscustomobject][ordered]@{
            id = $catalogModel.slug
            model = $catalogModel.slug
            displayName = if ([string]::IsNullOrWhiteSpace($catalogModel.display_name)) {
                $catalogModel.slug
            } else {
                $catalogModel.display_name
            }
            description = if ([string]::IsNullOrWhiteSpace($catalogModel.description)) {
                "OpenCodex provider model: $($catalogModel.slug)"
            } else {
                $catalogModel.description
            }
            hidden = $false
            isDefault = $false
            priority = 1000 + $index
            defaultReasoningEffort = 'medium'
            supportedReasoningEfforts = $stableEfforts
            inputModalities = @('text', 'image')
            supportsPersonality = $false
            supportVerbosity = $true
        }
    }
)

$modelsJson = $customModels | ConvertTo-Json -Depth 8 -Compress
$moduleText = @"
// Generated from the local OpenCodex model cache.
// Do not maintain model names manually.
const models=$modelsJson;
function mergeOpenCodexModels(data){
  const existing=Array.isArray(data)?data:[];
  const ids=new Set(existing.map(item=>item?.model));
  return [...existing,...models.filter(item=>!ids.has(item.model))];
}
export{mergeOpenCodexModels as m};
"@

$currentModule = if (Test-Path -LiteralPath $generatedModule) {
    [IO.File]::ReadAllText($generatedModule)
} else {
    ''
}
$catalogChanged = $currentModule -cne $moduleText

Write-Host "OpenCodex models detected: $($customModels.Count)"
Write-Host "Catalog changed: $catalogChanged"
Write-Host "Model cache: $modelCache"

if ($ValidateOnly) {
    Write-Host 'Validation completed without modifying files or launching Codex.'
    exit 0
}

if ($catalogChanged) {
    [IO.File]::WriteAllText(
        $generatedModule,
        $moduleText,
        [Text.UTF8Encoding]::new($false)
    )

    & $node $asarCli pack $unpackedRoot $builtAsar
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to rebuild app.asar.'
    }

    $portablePrefix = ([IO.Path]::GetFullPath($portableRoot)).TrimEnd('\') + '\'
    $portableProcesses = Get-Process ChatGPT, codex -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -and
            ([IO.Path]::GetFullPath($_.Path)).StartsWith(
                $portablePrefix,
                [StringComparison]::OrdinalIgnoreCase
            )
        }

    foreach ($process in $portableProcesses) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }

    if ($portableProcesses) {
        Start-Sleep -Milliseconds 700
    }

    Copy-Item -LiteralPath $builtAsar -Destination $deployedAsar -Force
}

$env:CODEX_ELECTRON_USER_DATA_PATH = $profileRoot
$env:CODEX_PICKER_PORTABLE = '1'

$portablePrefix = ([IO.Path]::GetFullPath($portableRoot)).TrimEnd('\') + '\'
$runningWindow = Get-Process ChatGPT -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Path -and
        ([IO.Path]::GetFullPath($_.Path)).StartsWith(
            $portablePrefix,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $_.MainWindowTitle -eq $windowTitle
    } |
    Select-Object -First 1

if ($null -eq $runningWindow) {
    Start-Process `
        -FilePath $executable `
        -WorkingDirectory $portableRoot `
        -ArgumentList "--user-data-dir=$profileRoot" `
        -WindowStyle Normal
}
