# Data Model

## PullRequestAttentionItem (output, `PSTypeName = 'UVModule.PullRequestAttentionItem'`)

| Property | Type | Source |
|---|---|---|
| Number | int | `number` |
| Title | string | `title` |
| Repository | string | `repository.nameWithOwner` |
| SourceBranch | string | `headRefName` |
| TargetBranch | string | `baseRefName` |
| IsDraft | bool | `isDraft` |
| UnresolvedThreadCount | int | threads with `isResolved = false` (all pages) |
| ReviewDecision | string or null | `reviewDecision` |
| Approvers | string[] | logins of `APPROVED` latest opinionated reviews |
| Reasons | string[] | subset of `UnresolvedReviewThreads`, `ApprovedNotMerged` |
| Url | string | `url` |

Rules: `UnresolvedReviewThreads` when UnresolvedThreadCount > 0; `ApprovedNotMerged` when research R6 holds.

## GitHubRepository (internal)

| Property | Type |
|---|---|
| Hostname | string (default `github.com`) |
| Owner | string |
| Name | string |
