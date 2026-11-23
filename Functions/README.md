# Functions

Source folder for the UVModule PowerShell module. Every `*.ps1` file here (searched recursively) is loaded by `UVModule.psm1` when the module is imported.

## Table of Contents

- [Contents](#contents)
- [Public Functions](#public-functions)
- [Private Helpers](#private-helpers)
- [Conventions](#conventions)
- [Adding a Function](#adding-a-function)
- [Related](#related)

## Contents

| File | Purpose |
|---|---|
| `Worktree-Functions.ps1` | Git worktree management for feature, bug and review branches |
| `GitHub-Functions.ps1` | Private GitHub helpers: remote parsing, `gh api graphql` calls, listing your open PRs and paging review threads |
| `PullRequestAttention-Functions.ps1` | Pull request attention rules and the three `Get-*PullRequest*` commands |

There are no subdirectories.

## Public Functions

| Function | Purpose |
|---|---|
| `New-Worktree` | Creates a `feat-<id>[-<BranchName>]` worktree and publishes its branch to `origin` |
| `Remove-Worktree` | Removes the feature worktree and local branch; the remote branch is preserved |
| `New-BugWorktree` | Same as `New-Worktree`, using the `bug-<id>[-<BranchName>]` prefix |
| `Remove-BugWorktree` | Removes a bug worktree and local branch; the remote branch is preserved |
| `New-ReviewWorktree` | Creates a `review/<branch>` local branch and sibling worktree from an origin branch |
| `Remove-ReviewWorktree` | Removes a review worktree and local branch; never touches the remote |
| `Get-PullRequestWithUnresolvedThread` | Lists your open GitHub PRs with unresolved review threads |
| `Get-ApprovedPullRequestNotMerged` | Lists your open GitHub PRs that are approved but not merged |
| `Get-PullRequestNeedingAttention` | Combines both lists; each PR once with its reasons |

See [../docs/PullRequestAttention.md](../docs/PullRequestAttention.md) for the pull request rules and prerequisites.

Behavior notes:

- Worktrees are created as siblings of the repository folder (or inside the root for bare repositories).
- `BaseBranch` defaults to `main`; `RepositoryPath` defaults to the current location.
- `WorkItemId` must match `^[1-9][0-9]*$`. Aliases: `TaskId`, `UserStoryId` (feature), `BugId` (bug).
- Removal refuses to proceed when there are uncommitted changes or unpushed commits unless `-Force` is given.
- All functions support `-WhatIf`/`-Confirm`. Removal functions use `ConfirmImpact = 'High'`.

## Private Helpers

Helpers are script-scoped scriptblocks (`$script:Name = { ... }`), invoked with `& $script:Name`. They are not exported functions. Examples: `InvokeReviewGit` (wraps `git -C` and throws on non-zero exit), `GetWorktreeTarget`, `GetWorktreePlan`, `AssertWorktreeRemovalTarget`, `NewPublishedWorktree`, `InvokeGitHubGraphQL` (wraps `gh api graphql` and throws on CLI or GraphQL errors), `GetGitHubRepository`, `GetMyOpenPullRequests`, `GetPullRequestAttentionItems`.

## Conventions

Inferred from existing code:

- Files use the `.ps1` extension and are named `<Topic>-Functions.ps1`.
- Public functions use `Verb-Noun` names with approved verbs (`New`, `Remove`).
- Each public function has comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) and `[CmdletBinding()]`.
- Mutating functions declare `SupportsShouldProcess` and call `$PSCmdlet.ShouldProcess`.
- Parameters use `[Validate*]` attributes; 4-space indentation; `PascalCase` for parameters and `camelCase` for locals.
- Git is called only through the `InvokeReviewGit` helper so failures surface as exceptions.
- Target: PowerShell 7.0 (PowerShell Core only). Tests use Pester 3.4.0.

## Adding a Function

1. Add the function to an existing `*.ps1` file here, or create a new one. It is picked up automatically by `UVModule.psm1`.
2. Add it to the exported functions in `UVModule.psd1` if the manifest lists exports explicitly.
3. Add Pester tests under `../Tests`.

## Related

- `../UVModule.psm1` – module loader
- `../UVModule.psd1` – module manifest
- `../Tests` – Pester tests
- `../scripts/Build-ModulePackage.ps1` – build script
- `../CONTRIBUTING.md` – contribution guidelines
