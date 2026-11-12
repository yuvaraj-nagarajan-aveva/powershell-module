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

### Build and release

1. Update `ModuleVersion` in `UVModule.psd1`, commit the change, and push it.
   Each release needs a new version; published versions are immutable.
2. Create and push a matching tag, for example:

   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. The GitHub Actions workflow runs the tests, checks that the tag matches the
   manifest, builds the package, and publishes it using `GITHUB_TOKEN` with
   package write permission. Check the workflow result and package visibility
   before installing. Repository or organization policies may need to permit
   Actions to publish packages. For an existing package, grant the workflow
   repository package access if needed.

After the first release, check the package's visibility in GitHub Package
settings. If it is private, change it to public there. GitHub warns that once a
package is public, it cannot be made private again. Public GitHub Packages still
require authentication to install; this is not a PowerShell Gallery release.

To build without publishing, run the following from the repository root with
PSResourceGet 1.1.0 or later installed:

```powershell
New-Item -ItemType Directory -Path .\package -Force | Out-Null
.\scripts\Build-ModulePackage.ps1 -DestinationPath .\package
```

If publication fails before the version exists, rerun the workflow after
correcting the cause. If the package version was already published, verify it
before deciding whether to publish a new version. To roll back, install a
known-good version explicitly with `Install-PSResource -Version <version>`.

The package installation/update integration test is intended for a disposable
environment with no existing `UVModule` installation, because it temporarily
installs and removes test versions for the current user.

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

## Worktree

The worktree functions in `Functions\Worktree-Functions.ps1` are loaded by the module.

### Task and user story worktrees

Supply a positive numeric task or user story ID:

```powershell
New-Worktree -TaskId 12345
New-Worktree -UserStoryId 67890 -BaseBranch develop
Remove-Worktree -TaskId 12345
Remove-Worktree -UserStoryId 67890
```

`-WorkItemId` (or the first positional argument) accepts either kind of ID.
Creation fetches `origin/main` by default. `-BranchName` adds an optional
suffix to the local and remote branch names and the worktree folder:

```powershell
New-Worktree -TaskId 12345 -BranchName add-search
Remove-Worktree -TaskId 12345 -BranchName add-search
```

This creates local branch and sibling folder `feat-12345-add-search`, publishes
`origin/feat-12345-add-search`, and sets it as the upstream. `-BranchName` is
optional; without it the local and remote branch names are `feat-12345`.
Branch suffixes must form valid Git branch names. Supply the same suffix when
removing the worktree.

Use `-BaseBranch` to start from another origin branch. Existing local branches,
remote branches, and folders are never overwritten. If publishing fails, the
new local branch and worktree are preserved and the error explains the partial
result.

Both functions default to the current repository. Use the same `-RepositoryPath`
for creation and removal. For bare repositories the worktree folder is created
inside the repository directory instead of beside it.

Removal prompts for confirmation and deletes only the worktree and local branch;
the remote branch is preserved. It refuses uncommitted changes and fetches the
remote feature branch to check for unpushed commits before deleting anything.
Push work you want to keep before removal. If the remote branch was deleted or
cannot be fetched, normal cleanup stops. `-Force` skips this check and explicitly
discards uncommitted files and unpushed commits, but does not bypass Git locks
or repository/branch identity checks. Both commands support `-WhatIf`.

### Bug worktrees

Bug worktrees use `bug-` instead of `feat-` and have the same suffix, base
branch, cleanup, and preview options:

```powershell
New-BugWorktree -BugId 54321 -BranchName fix-login
Remove-BugWorktree -BugId 54321 -BranchName fix-login
```

The local branch and sibling folder are `bug-54321-fix-login`; the remote
branch is `origin/bug-54321-fix-login`. `-BugId` is an alias for
`-WorkItemId`.

### Preview changes

All six worktree commands support `-WhatIf`. Creation and removal return a
plan containing the repository path, local branch, remote branch, source branch
when creating, worktree folder, and remote action:

```powershell
New-Worktree -TaskId 12345 -BranchName add-search -WhatIf | Format-List
Remove-Worktree -TaskId 12345 -BranchName add-search -WhatIf | Format-List
New-BugWorktree -BugId 54321 -BranchName fix-login -WhatIf | Format-List
New-ReviewWorktree -BranchName feature/test -WhatIf | Format-List
```

Previews do not contact the remote, fetch, publish, modify Git configuration,
or create or delete branches and folders. Removal previews do not require the
worktree to exist. Remote availability and removal safety checks still apply
when executing the command without `-WhatIf`.

### Review worktrees

Supply the PR source branch name without `origin/` or `refs/heads/` prefixes:

```powershell
New-ReviewWorktree -BranchName '12345-feature'
Remove-ReviewWorktree -BranchName '12345-feature'
```

Creation fetches the exact branch from `origin`, creates local branch
`review/12345-feature` tracking `origin/12345-feature`, and checks it out in
`review-12345-feature` beside the repository directory. Slashes and characters
invalid in Windows folder names are replaced with hyphens in the folder name.
Existing branches or folders are never overwritten. Creation returns the
repository path, local branch name, and worktree path.

Both functions default to the current repository. Use `-RepositoryPath` to
target another checkout; use the same checkout when creating and removing a
review worktree. Two branch names that map to the same folder cannot have
review worktrees at the same time.

Removal prompts for confirmation and deletes only the review worktree and its
local branch, not the PR branch on `origin`. It refuses uncommitted changes
(including untracked files) and commits not present in the locally fetched
`origin/<branch>` reference. A PR does not need to be merged into its target
branch for cleanup. Commit and push changes you want to keep, then fetch the
updated PR branch before retrying cleanup:

```powershell
git fetch origin
Remove-ReviewWorktree -BranchName '12345-feature'
```

To explicitly discard uncommitted files and local-only commits instead:

```powershell
Remove-ReviewWorktree -BranchName '12345-feature' -Force
```

Both functions support `-WhatIf`. Git errors are surfaced without continuing
to subsequent cleanup steps. Locked worktrees and worktrees containing
submodules remain subject to Git's removal safeguards.

Run the worktree integration tests with Pester (they use temporary local Git
repositories and do not access the real remote):

```powershell
Invoke-Pester .\Tests\Worktree-Functions.Tests.ps1
```