$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'UVModule.psd1'
$version = (Import-PowerShellDataFile $manifestPath).ModuleVersion
$parsedVersion = [version] $version
$nextVersion = '{0}.{1}.{2}' -f $parsedVersion.Major, $parsedVersion.Minor, ($parsedVersion.Build + 1)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("uvmodule-test-" + [guid]::NewGuid().ToString('N'))
$repositoryName = 'UVModuleTest' + [guid]::NewGuid().ToString('N')
$userModuleRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
$registered = $false

if ((Get-Module -ListAvailable -Name UVModule) -or (Test-Path -LiteralPath (Join-Path $userModuleRoot 'UVModule'))) {
    throw 'Package integration test requires an environment without an existing UVModule installation.'
}

try {
    $env:PSModulePath = $userModuleRoot + [IO.Path]::PathSeparator + $env:PSModulePath
    $feed = Join-Path $testRoot 'feed'
    $nextSource = Join-Path $testRoot 'source'
    New-Item -ItemType Directory -Path $feed, $nextSource -Force | Out-Null
    & (Join-Path $root 'scripts\Build-ModulePackage.ps1') -DestinationPath $feed | Out-Null
    Register-PSResourceRepository -Name $repositoryName -Uri $feed -Trusted -ErrorAction Stop
    $registered = $true

    Install-PSResource -Name UVModule -Version $version -Repository $repositoryName -Scope CurrentUser -ErrorAction Stop
    Import-Module UVModule -RequiredVersion $version -Force -ErrorAction Stop
    $expected = @('New-Worktree', 'Remove-Worktree', 'New-BugWorktree', 'Remove-BugWorktree', 'New-ReviewWorktree', 'Remove-ReviewWorktree')
    foreach ($name in $expected) {
        if (-not (Get-Command -Name $name -Module UVModule -ErrorAction SilentlyContinue)) {
            throw "Installed module did not export $name."
        }
    }
    Remove-Module UVModule

    Copy-Item -LiteralPath $manifestPath, (Join-Path $root 'UVModule.psm1') -Destination $nextSource
    Copy-Item -LiteralPath (Join-Path $root 'Functions') -Destination $nextSource -Recurse
    Update-ModuleManifest -Path (Join-Path $nextSource 'UVModule.psd1') -ModuleVersion $nextVersion
    & (Join-Path $root 'scripts\Build-ModulePackage.ps1') -SourcePath $nextSource -DestinationPath $feed | Out-Null
    Update-PSResource -Name UVModule -Repository $repositoryName -Scope CurrentUser -ErrorAction Stop
    Import-Module UVModule -RequiredVersion $nextVersion -Force -ErrorAction Stop
    if ((Get-Module UVModule).Version -ne [version] $nextVersion) {
        throw "Module update did not install version $nextVersion."
    }
    Write-Host "Package installation and update passed: $version -> $nextVersion"
}
finally {
    Remove-Module UVModule -ErrorAction SilentlyContinue
    foreach ($installedVersion in @($version, $nextVersion)) {
        if (Get-PSResource -Name UVModule -Version $installedVersion -Scope CurrentUser -ErrorAction SilentlyContinue) {
            Uninstall-PSResource -Name UVModule -Version $installedVersion -Scope CurrentUser -ErrorAction Stop
        }
    }
    if ($registered) {
        Unregister-PSResourceRepository -Name $repositoryName -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
