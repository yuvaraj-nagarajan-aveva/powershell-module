# Command Contracts

All three commands share these parameters and return `UVModule.PullRequestAttentionItem` objects (see data-model.md). All are read-only and use the GitHub CLI sign-in.

| Parameter | Type | Default | Notes |
|---|---|---|---|
| Repository | string | `origin` remote of RepositoryPath | `owner/name`, validated `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`; uses `github.com` |
| RepositoryPath | string | current location | Used only for inference |
| ExcludeDraft | switch | off | |

| Command | Returns |
|---|---|
| `Get-PullRequestWithUnresolvedThread` | Items whose Reasons contain `UnresolvedReviewThreads` |
| `Get-ApprovedPullRequestNotMerged` | Items whose Reasons contain `ApprovedNotMerged` |
| `Get-PullRequestNeedingAttention` | Items with at least one reason, each PR once |

Errors (terminating): repository not supplied and not inferable; `gh` missing; `gh` failure (`GitHub GraphQL request failed: ...`); GraphQL errors.
