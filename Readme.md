## Module usage

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

The two functions in `Functions\Worktree-Functions.ps1` are loaded by the module.

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

Both functions default to the repository containing the module, regardless of
the current directory. Use `-RepositoryPath` to target another checkout; use the
same checkout when creating and removing a review worktree. Two branch names
that map to the same folder cannot have review worktrees at the same time.

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