# Copy this file to Config.ps1 and edit only the values you need.
# Relative paths are resolved from the directory containing the scripts.

$CodexPickerConfig = @{
    # Portable Codex application directory.
    PortableDirectory = 'Codex-Picker'

    # Directory containing the unpacked and already-patched app.asar files.
    UnpackedDirectory = 'app-unpacked'

    # Relative or absolute path to the ASAR command-line entry point.
    AsarCliPath = 'tools\node_modules\@electron\asar\bin\asar.mjs'

    # Portable Electron profile directory.
    ProfileDirectory = 'profile'

    # Executable inside PortableDirectory.
    ExecutableName = 'ChatGPT.exe'

    # Window title assigned by the portable bootstrap patch.
    WindowTitle = 'Codex Picker Patched'

    # Optional explicit OpenCodex model cache path.
    # Leave empty to use:
    #   %CODEX_HOME%\models_cache.json
    # or
    #   %USERPROFILE%\.codex\models_cache.json
    ModelCachePath = ''

    # Optional explicit Node.js executable.
    # Leave empty to use automatic discovery.
    NodePath = ''
}
