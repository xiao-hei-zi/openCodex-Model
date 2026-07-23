Original project: https://github.com/lidge-jun/opencodex
I created this version because I was unable to bring up the model selector while using the original; I wanted to make things easier for others facing the same issue.
原项目：https://github.com/lidge-jun/opencodex
本项目只是本人使用时无法正常的调出模型选择器所以弄了一个方便有相同问题的人不用麻烦

免责声明：本项目是纯ai编写，出现任何问题与创建人无关
Disclaimer: This project was written entirely by AI; the creator bears no responsibility for any issues that may arise.
# Portable Codex Picker Scripts

These scripts dynamically read the local OpenCodex model cache and expose the
configured provider models in an already-patched Codex desktop model picker.

No usernames, access tokens, API keys, machine-specific absolute paths, or
model-name allowlists are included.

For configurable parameters and the full Chinese disclaimer, see:

```text
使用说明与免责声明.md
Config.example.ps1
```

## Required layout

Place the scripts in the same directory as the following folders:

```text
package-root/
├─ Launch-Codex-Picker.cmd
├─ Sync-And-Launch-Codex-Picker.ps1
├─ Codex-Picker/
│  ├─ ChatGPT.exe
│  └─ resources/app.asar
├─ app-unpacked/
│  └─ webview/assets/
└─ tools/
   └─ node_modules/@electron/asar/bin/asar.mjs
```

The unpacked frontend must already contain these patch markers:

```text
models:ocMerge(r)
models:ocMerge(b)
```

The script verifies both markers before changing or launching anything.

## Model source

The model cache is resolved in this order:

1. `%CODEX_HOME%\models_cache.json`
2. `%USERPROFILE%\.codex\models_cache.json`

Models are detected dynamically when:

```text
slug contains "/"
visibility is "list" or unset
```

Model names are never maintained in the scripts.

## Usage

Double-click:

```text
Launch-Codex-Picker.cmd
```

Validation without writing files, repacking, stopping processes, or launching:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Sync-And-Launch-Codex-Picker.ps1 -ValidateOnly
```

When the OpenCodex model list has changed, the script regenerates
`opencodex-models.js`, rebuilds `app.asar`, stops only processes whose executable
path is inside `Codex-Picker`, deploys the rebuilt archive, and launches the
portable application with a local `profile` directory.

When the model list has not changed, no rebuild or restart is performed.

