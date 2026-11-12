[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $DestinationPath,

    [string] $SourcePath = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$destination = (Resolve-Path -LiteralPath $DestinationPath).Path
$stage = Join-Path ([IO.Path]::GetTempPath()) ("uvmodule-build-" + [guid]::NewGuid().ToString('N'))

try {
    $modulePath = Join-Path $stage 'UVModule'
    New-Item -ItemType Directory -Path $modulePath | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'UVModule.psd1'), (Join-Path $source 'UVModule.psm1') -Destination $modulePath
    Copy-Item -LiteralPath (Join-Path $source 'Functions') -Destination $modulePath -Recurse
    Test-ModuleManifest -Path (Join-Path $modulePath 'UVModule.psd1') -ErrorAction Stop | Out-Null
    Compress-PSResource -Path $modulePath -DestinationPath $destination -PassThru -ErrorAction Stop
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
