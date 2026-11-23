# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

`UVModule` is a PowerShell module that provides git worktree helper functions and read-only GitHub pull request attention commands. The module is loaded through `UVModule.psm1`, which dot-sources every `*.ps1` file under `Functions/`. The module is packaged and published to GitHub Packages.

## Tech Stack

| Item | Value |
|---|---|
| Primary language | PowerShell |
| Language version | 7.0 (PowerShell Core only) |
| Build system | `scripts/Build-ModulePackage.ps1` |
| Package manager | PowerShell module / GitHub Packages |
| Test framework | Pester 3.4.0 |
| Key dependencies | `git`, Pester 3.4.0; GitHub CLI (`gh api graphql`) for the pull request commands |
| Manifest / entry points | `UVModule.psd1`, `UVModule.psm1` |

## Project Structure

```text
UVModule.psd1        Module manifest (version, exports)
UVModule.psm1        Entry point; dot-sources Functions/**/*.ps1
Functions/           Module source (Worktree, GitHub, PullRequestAttention)
Tests/               Pester tests and package integration test
scripts/             Build-ModulePackage.ps1
docs/                BuildRelease.md, Installation.md, Worktree.md, PullRequestAttention.md
.github/workflows/   module.yml (validate and release CI)
```

## Build, Test, and Validate

```powershell
# Validate manifest
Test-ModuleManifest .\UVModule.psd1

# Unit tests (Pester 3.4.0 required)
Import-Module Pester -RequiredVersion 3.4.0 -Force
Invoke-Pester .\Tests

# Package installation/update integration test
.\Tests\Package.Integration.ps1

# Build package
.\scripts\Build-ModulePackage.ps1 -DestinationPath .\package
```

CI (`.github/workflows/module.yml`) sets `safe.bareRepository=all` via `GIT_CONFIG_*` environment variables when running the Pester tests, and releases on `v*` tags. The tag must equal `v` plus the `ModuleVersion` in `UVModule.psd1`.

## Coding Conventions

- Source files are `*.ps1` placed in `Functions/`; they are loaded automatically, so no manifest edit is needed to load them (update the manifest if exports change).
- Internal helpers are script-scoped scriptblocks (e.g. `$script:InvokeReviewGit`) invoked with `&`.
- Use `param ( ... )` with typed parameters, PascalCase parameter names, and 4-space indentation.
- Call `git` through the existing wrapper helper so non-zero exit codes throw with a clear message.
- Call GitHub only through `$script:InvokeGitHubGraphQL` (read-only queries); tests replace it with a test double.
- Throw on errors rather than silently continuing.
- Test files are named `<Source>.Tests.ps1` in `Tests/`.

## Boundaries

- Do not commit secrets or tokens; the publish workflow uses `GITHUB_TOKEN` only.
- Do not change the Pester version (3.4.0) without updating CI.
- Keep the module compatible with PowerShell 7.0+.
- Do not expand or guess the meaning of "UV" in `UVModule`; the repository does not define it.

## Documentation

- `Readme.md`: overview
- `docs/Installation.md`, `docs/Worktree.md`, `docs/PullRequestAttention.md`, `docs/BuildRelease.md`: detailed guides
