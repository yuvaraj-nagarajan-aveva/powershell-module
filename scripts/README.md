# scripts

Build and packaging scripts for the UVModule PowerShell module.

## Contents

| File | Purpose |
|---|---|
| `Build-ModulePackage.ps1` | Stages the module and packages it with `Compress-PSResource`. |

## Build-ModulePackage.ps1

Packages the module for distribution.

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `DestinationPath` | Yes | Existing directory where the package is written. |
| `SourcePath` | No | Module root. Defaults to the parent of the `scripts` folder. |

### What it does

1. Resolves the source and destination paths.
2. Creates a temporary staging folder containing a `UVModule` directory.
3. Copies `UVModule.psd1`, `UVModule.psm1` and the `Functions` folder into it.
4. Validates the manifest with `Test-ModuleManifest`.
5. Runs `Compress-PSResource` to create the package in `DestinationPath`.
6. Removes the staging folder, including when an error occurs.

### Usage

```powershell
./scripts/Build-ModulePackage.ps1 -DestinationPath ./out
```

The destination directory must already exist, because the script resolves it with `Resolve-Path`.

## Conventions

- PowerShell 7.0 or later (PowerShell Core only).
- `[CmdletBinding()]` with a typed `param` block.
- `$ErrorActionPreference = 'Stop'`.
- Verb-Noun file names in PascalCase (`Build-ModulePackage.ps1`).
- Temporary resources are cleaned up in `finally`.
- Use `-LiteralPath` for paths.

## Related

- `../UVModule.psd1`, `../UVModule.psm1`: module manifest and entry point
- `../Functions/`: module functions that get packaged
- `../CONTRIBUTING.md`: contribution guidelines
