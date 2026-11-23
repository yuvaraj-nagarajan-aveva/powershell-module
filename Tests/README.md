# Tests

Automated tests for the UVModule PowerShell module (PowerShell 7.0+, Pester 3.4.0, `git`).

## Contents

| File | Type | Purpose |
|---|---|---|
| `Worktree-Functions.Tests.ps1` | Pester unit/behavior tests | Dot-sources `..\Functions\Worktree-Functions.ps1` and tests the worktree functions (e.g. review worktrees) against temporary git repositories with a local bare remote. |
| `GitHub-Functions.Tests.ps1` | Pester unit tests | Tests GitHub remote parsing, repository inference, `gh api graphql` argument building and error handling, PR search paging and review-thread paging. `gh` is replaced by a fake command. |
| `PullRequestAttention-Functions.Tests.ps1` | Pester unit tests | Tests the unresolved-thread, approval and combined attention rules against fake GraphQL pull requests and review threads. |
| `Package.Integration.ps1` | Standalone integration script (not Pester) | Builds the module package with `scripts\Build-ModulePackage.ps1` into a temporary feed, registers it as a PSResource repository, installs and imports it, verifies the exported worktree commands, then builds a bumped version and verifies `Update-PSResource`. |

## Running

```powershell
# Pester tests (Pester 3.4.0)
Invoke-Pester .\Tests

# Package integration test
pwsh -File .\Tests\Package.Integration.ps1
```

The integration script throws if UVModule is already installed (or present in the user module folder), so run it in a clean environment. It modifies `PSModulePath` for its session and registers a temporary repository, which it uses for the run.

## Conventions

- Pester 3 syntax: `Should Not BeNullOrEmpty`, `Should Match` (no dashes). `Should Throw` is unreliable under PowerShell 7, so tests use helpers such as `Assert-ReviewFailure` that capture the exception message.
- Each test creates uniquely named temp directories (`[IO.Path]::GetTempPath()` plus a GUID) in `BeforeEach` and cleans them in `AfterEach`.
- Git repos are configured with local `user.name`, `user.email`, and `commit.gpgsign=false` so tests do not depend on global config.
- Test files are named `<Area>.Tests.ps1`; the integration script is `<Area>.Integration.ps1`.
- Use `$PSScriptRoot` for paths relative to the test files.

## Adding tests

1. Add a `*.Tests.ps1` file here and dot-source the function file under test from `..\Functions`.
2. Use temp directories and clean up afterward; never touch real repositories.
3. Keep Pester 3.4.0 assertion syntax.

## Related

- `..\Functions\` – module source under test
- `..\scripts\Build-ModulePackage.ps1` – package build used by the integration test
- `..\CONTRIBUTING.md` – contribution guidelines
