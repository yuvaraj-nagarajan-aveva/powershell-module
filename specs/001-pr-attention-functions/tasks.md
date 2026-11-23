# Tasks: Pull Request Attention Functions

**Input**: Design documents from `specs/001-pr-attention-functions/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/commands.md, quickstart.md

**Tests**: Required (constitution principle IV, test-first). Tests replace `gh` and the GraphQL helper with test doubles; no live PRs are queried.

**Revision**: 2026-11-12, retargeted from Azure DevOps to GitHub. The task list was regenerated.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Delete Functions/AzureDevOps-Functions.ps1 and Tests/AzureDevOps-Functions.Tests.ps1; create Functions/GitHub-Functions.ps1 and Tests/GitHub-Functions.Tests.ps1

## Phase 2: Foundational (GitHub access)

- [X] T002 Write failing tests in Tests/GitHub-Functions.Tests.ps1 for remote parsing (HTTPS, SSH, scp-style, Enterprise host, non-GitHub remote), origin inference and `-Repository` override, missing-repository error, `gh` argument construction (`-f`/`-F`/`--hostname`), `gh` failure, GraphQL `errors`, missing `gh`, PR search paging and review-thread paging
- [X] T003 Implement `$script:GetGitHubRemoteInfo`, `$script:GetGitHubRepository`, `$script:InvokeGitHubGraphQL`, `$script:GetMyOpenPullRequests` and `$script:GetAllReviewThreads` in Functions/GitHub-Functions.ps1 until T002 passes

**Checkpoint**: repository resolution, GraphQL invocation and paging work against test doubles.

## Phase 3: User Story 1 - Unresolved review threads (P1) MVP

**Independent test**: fake PRs with resolved, unresolved, outdated-unresolved and paged threads; only PRs with unresolved threads are returned with correct counts.

- [X] T004 [US1] Rewrite Tests/PullRequestAttention-Functions.Tests.ps1 with failing tests for `Get-PullRequestWithUnresolvedThread` (counts, all-resolved excluded, extra thread pages, ExcludeDraft, output shape)
- [X] T005 [US1] Rewrite Functions/PullRequestAttention-Functions.ps1 with `$script:ConvertToPullRequestAttentionItem`, `$script:GetPullRequestAttentionItems` and `Get-PullRequestWithUnresolvedThread` until T004 passes

## Phase 4: User Story 2 - Approved but not merged (P2)

**Independent test**: fake PRs with each review decision and with null decision plus approving or changes-requested latest reviews.

- [X] T006 [US2] Add failing tests for `Get-ApprovedPullRequestNotMerged` in Tests/PullRequestAttention-Functions.Tests.ps1
- [X] T007 [US2] Implement `$script:TestPullRequestApproved`, `$script:GetApproverLogins` and `Get-ApprovedPullRequestNotMerged` in Functions/PullRequestAttention-Functions.ps1 until T006 passes

## Phase 5: User Story 3 - Combined attention list (P3)

**Independent test**: PRs with only threads, only approval, both, and neither return three distinct items with correct reasons; nothing needing attention returns nothing.

- [X] T008 [US3] Add failing tests for `Get-PullRequestNeedingAttention` in Tests/PullRequestAttention-Functions.Tests.ps1
- [X] T009 [US3] Implement `Get-PullRequestNeedingAttention` in Functions/PullRequestAttention-Functions.ps1 until T008 passes

## Phase 6: Polish & Cross-Cutting

- [X] T010 Update exports and description in UVModule.psd1 (version stays 0.2.0)
- [X] T011 [P] Update expected exports in Tests/Package.Integration.ps1
- [X] T012 [P] Rewrite docs/PullRequestAttention.md for GitHub and replace the Azure DevOps wording added to Readme.md, docs/README.md, Functions/README.md, Tests/README.md, CONTRIBUTING.md and .github/AGENTS.md, keeping pre-existing user changes
- [X] T013 Confirm .github/workflows/module.yml runs all `Tests/*.Tests.ps1` without needing `gh` or network access
- [X] T014 Run `Test-ModuleManifest`, `Invoke-Pester .\Tests`, import the module, and search for leftover Azure DevOps references

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1 → US2 → US3 → Polish. US2 and US3 reuse the US1 item builder in the same file.
- T011 and T012 can run in parallel after T010.

## Parallel Example

```text
T011 Tests/Package.Integration.ps1
T012 docs/PullRequestAttention.md and README updates
```

## Implementation Strategy

MVP is US1 (Phases 1–3). Then US2 and US3, each verified by its own tests, then polish.
