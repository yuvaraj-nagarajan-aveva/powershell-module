# Contributing

Thanks for contributing to this PowerShell module (`UVModule`). This guide covers setup, conventions, testing, and the pull request process.

## Table of contents

- [Prerequisites](#prerequisites)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Coding style](#coding-style)
- [Testing](#testing)
- [Building](#building)
- [Submitting changes](#submitting-changes)
- [Releases](#releases)

## Prerequisites

- PowerShell 7.0 or later (PowerShell Core only)
- `git`
- Pester 3.4.0
- PSResourceGet 1.1.0 or later (only for building the package locally)

## Repository layout

| Path | Purpose |
|---|---|
| `Functions/` | Module source (`*.ps1`): `Worktree-Functions.ps1`, `GitHub-Functions.ps1`, `PullRequestAttention-Functions.ps1` |
| `Tests/` | Pester tests and the package integration test |
| `docs/` | Installation, worktree, and build/release documentation |
| `scripts/` | Build script (`Build-ModulePackage.ps1`) |
| `UVModule.psd1` | Module manifest (holds `ModuleVersion`) |
| `UVModule.psm1` | Entry point; dot-sources every `*.ps1` under `Functions/` |
| `.github/workflows/module.yml` | CI: test, build, publish |

## Getting started

1. Fork and clone the repository.
2. Create a branch from the default branch.
3. Add or change code under `Functions/`. New `.ps1` files there are loaded automatically by `UVModule.psm1`.

## Coding style

Follow the conventions in existing code:

- 4-space indentation; opening braces on the same line; `else`/`catch` on a new line after the closing brace.
- Typed `param ([string] $Name)` blocks with a space after `param`.
- Internal helpers are script-scoped script blocks (`$script:Name = { ... }`) invoked with `& $script:Name`.
- PascalCase for function, variable, and property names.
- Align `=` in multi-property `[PSCustomObject]@{ ... }` literals.
- Call `git` through the existing wrapper (`$script:InvokeReviewGit`), which throws on a non-zero exit code.
- Use brief comments only to explain non-obvious reasons.

## Testing

Tests use Pester 3.4.0 syntax (for example `Should Not BeNullOrEmpty`, `Should Match`), not Pester 5 syntax.

```powershell
Invoke-Pester .\Tests
```

- Add or update tests in `Tests/` for every behavior change.
- Never call GitHub from tests; replace `$script:InvokeGitHubGraphQL` or `$script:GitHubCliCommand` with a test double.
- Tests create temporary repositories under the system temp folder; do not depend on your own repositories.
- Pester 3 `Should Throw` does not work with PowerShell 7 exceptions; use the `Assert-ReviewFailure` helper in the test file.
- `Tests/Package.Integration.ps1` installs and removes test versions of `UVModule` for the current user. Run it only in a disposable environment with no existing installation.

## Building

```powershell
New-Item -ItemType Directory -Path .\package -Force | Out-Null
.\scripts\Build-ModulePackage.ps1 -DestinationPath .\package
```

## Submitting changes

1. Make sure the tests pass locally.
2. Update `Readme.md` or `docs/` if behavior or usage changes.
3. Open a pull request with a clear description of what changed and why.
4. Address review feedback; CI must pass before merge.

## Releases

Releases are tag-driven. See [docs/BuildRelease.md](docs/BuildRelease.md). Published package versions are immutable, so each release needs a new `ModuleVersion` in `UVModule.psd1`.
