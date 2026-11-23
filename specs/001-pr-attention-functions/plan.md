# Implementation Plan: Pull Request Attention Functions

**Branch**: `001-pr-attention-functions` | **Date**: 2026-11-12 (revised for GitHub) | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-pr-attention-functions/spec.md`

## Summary

Add three read-only `UVModule` commands that list the signed-in user's open
GitHub pull requests in the current repository that need attention: PRs with
unresolved review threads (`Get-PullRequestWithUnresolvedThread`), PRs approved
but not merged (`Get-ApprovedPullRequestNotMerged`), and the distinct union with
reasons (`Get-PullRequestNeedingAttention`). The commands run GitHub GraphQL
queries through `gh api graphql`, which reuses the user's GitHub CLI sign-in.
The repository is inferred from the `origin` remote. See [research.md](./research.md).

This revision replaces the earlier Azure DevOps design; the Azure DevOps code,
tests and documentation are removed.

## Technical Context

**Language/Version**: PowerShell 7.0+ (PowerShell Core only)  
**Primary Dependencies**: GitHub CLI (`gh`) for GraphQL calls and authentication; `git` for remote inference  
**Storage**: N/A  
**Testing**: Pester 3.4.0; the GraphQL helper and the `gh` command are replaced by test doubles (no network)  
**Target Platform**: Windows, Linux, macOS with PowerShell 7  
**Project Type**: PowerShell module (library of commands)  
**Performance Goals**: One GraphQL call per 50 PRs, plus one per extra page of 100 review threads  
**Constraints**: Read-only (queries only); no credential handling in the module; Pester 3 syntax  
**Scale/Scope**: Tens of open PRs per user per repository

## Constitution Check

*Source: AVEVA Organisational Principles (no repository constitution).*

| Principle | Gate | Status |
|---|---|---|
| I. Research over speculation | GraphQL fields (`reviewThreads.isResolved`, `reviewDecision`, `latestOpinionatedReviews`) and `gh api graphql` flags confirmed in research.md | Pass |
| II. Plan-first | Plan and tasks revised before code changes | Pass |
| III. Deterministic validation | Pester tests and `Test-ModuleManifest` run in CI | Pass |
| IV. Test-driven | Tests rewritten first against GraphQL and `gh` test doubles; no live PRs | Pass |
| V. Coverage analysis | Existing tests cover worktrees only; the PR area keeps its two test files | Pass |
| VI. Single source of truth | Usage in `docs/PullRequestAttention.md`; other docs link to it | Pass |
| VII. Documentation verification | Docs reviewed against command signatures and tests | Pass |
| VIII. Clean code | No inline comments; GitHub access and attention rules in separate files; shared helpers; three commands instead of a mode flag | Pass |

Post-design re-check: Pass.

## Project Structure

### Documentation (this feature)

```text
specs/001-pr-attention-functions/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/commands.md
└── tasks.md
```

### Source Code (repository root)

```text
Functions/
├── GitHub-Functions.ps1               # remote parsing, gh GraphQL invocation, PR search and thread paging
├── PullRequestAttention-Functions.ps1 # attention rules and the three public commands
└── Worktree-Functions.ps1             # existing
Tests/
├── GitHub-Functions.Tests.ps1
├── PullRequestAttention-Functions.Tests.ps1
└── Package.Integration.ps1            # expected exports
docs/PullRequestAttention.md
UVModule.psd1                          # exports + version 0.2.0
.github/workflows/module.yml           # runs all *.Tests.ps1
```

Removed: `Functions/AzureDevOps-Functions.ps1`, `Tests/AzureDevOps-Functions.Tests.ps1`.

**Structure Decision**: Follow the existing `Functions/<Topic>-Functions.ps1`
pattern, splitting GitHub access from PR attention rules for single responsibility.

## Complexity Tracking

No violations.
