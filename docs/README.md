# docs

User and maintainer documentation for the `UVModule` PowerShell module (PowerShell 7+, requires Git).

## Contents

| File | Purpose |
|---|---|
| [Installation.md](./Installation.md) | Install from the GitHub Packages feed with PSResourceGet, or import from a checkout and via a profile |
| [Worktree.md](./Worktree.md) | Usage of the worktree commands in `Functions\Worktree-Functions.ps1` (task, user story, bug, and review worktrees; `-WhatIf` previews; safe removal) |
| [PullRequestAttention.md](./PullRequestAttention.md) | Commands that list your open GitHub pull requests with unresolved review threads or approvals awaiting merge |
| [BuildRelease.md](./BuildRelease.md) | Versioning, tagging, the GitHub Actions publish workflow, and local builds with `scripts\Build-ModulePackage.ps1` |

## Where to start

- Installing the module: [Installation.md](./Installation.md)
- Using worktree commands: [Worktree.md](./Worktree.md)
- Finding pull requests that need attention: [PullRequestAttention.md](./PullRequestAttention.md)
- Publishing a release: [BuildRelease.md](./BuildRelease.md)

## Conventions

- One Markdown file per topic, named in PascalCase (for example `BuildRelease.md`).
- Top-level heading is the topic title; sections use `##` and `###`.
- Examples are fenced `powershell` code blocks, run from the repository root.
- Cross-links between docs use relative paths (`./BuildRelease.md`).
- Update the matching doc when changing behavior in `Functions\`, `scripts\`, or `UVModule.psd1`.

## Related

- Module entry points: `UVModule.psd1`, `UVModule.psm1`
- Source: `Functions\`
- Tests (Pester 3.4.0): `Tests\`, for example `Invoke-Pester .\Tests`
- Contribution guidance: `CONTRIBUTING.md` (listed as missing in the discovery report; verify it exists before relying on it)
