## Install from GitHub Packages

The module is published to the GitHub Packages NuGet feed. It requires
PowerShell 7 and Git. PowerShell 7.4 and later include PSResourceGet; earlier
PowerShell 7 versions need `Microsoft.PowerShell.PSResourceGet` installed.

Even for public NuGet packages, GitHub requires authentication. Create a GitHub
personal access token (classic) with `read:packages`. Register the account-scoped
feed once per user:

```powershell
Register-PSResourceRepository -Name UVGitHub `
    -Uri 'https://nuget.pkg.github.com/yuvaraj-nagarajan-aveva/index.json'
```

After the first package version has been published, enter your GitHub username
and token when prompted and install the module:

```powershell
$credential = Get-Credential
Install-PSResource -Name UVModule -Repository UVGitHub -Scope CurrentUser -Credential $credential
Import-Module UVModule
```

If `Import-Module` cannot find the installed module, check that the current-user
module directory is in `$env:PSModulePath`. On Windows, the following adds it to
the current session; add the same lines to your PowerShell profile if needed:

```powershell
$userModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
if ($env:PSModulePath -split [IO.Path]::PathSeparator -notcontains $userModules) {
    $env:PSModulePath = $userModules + [IO.Path]::PathSeparator + $env:PSModulePath
}
```

Remove any old profile import that points directly to this checkout if you
want sessions to load the installed version instead.

Update it using the same credentials, then start a new PowerShell session to
load the new version:

```powershell
Update-PSResource -Name UVModule -Repository UVGitHub -Scope CurrentUser -Credential $credential
```

The repository registration does not save credentials. For repeated use, use a
secure credential vault or run `Get-Credential` again. The package must be
visible to your GitHub account. If the repository is untrusted, PowerShell
prompts for confirmation. `Register-PSRepository` and `Install-Module` are
PowerShellGet v2 commands; use the PSResourceGet commands above for this
GitHub Packages feed.

For publishing instructions, see [Build and release](./BuildRelease.md).

## Import from a checkout

Import the module in the current PowerShell session with the path to `UVModule.psm1`:

```powershell
Import-Module 'C:\path\to\powershell-module\UVModule.psm1'
```

To load the module automatically whenever PowerShell starts, add the import to
your current-user, all-hosts profile. This profile is used by PowerShell
terminals across hosts, including the VS Code integrated terminal.

Create the profile file if it does not exist, then open it for editing:

```powershell
$profilePath = $PROFILE.CurrentUserAllHosts
New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
if (-not (Test-Path -LiteralPath $profilePath)) {
	New-Item -ItemType File -Path $profilePath | Out-Null
}
notepad $profilePath
```

Add this line to the profile, replacing the path with the location of this
repository:

```powershell
Import-Module 'C:\path\to\powershell-module\UVModule.psm1'
```

Save the profile and open a new PowerShell terminal. Verify that the module
functions are available with `Get-Command *-ReviewWorktree`. The profile
only runs in PowerShell terminals, not in Command Prompt or other shells.
