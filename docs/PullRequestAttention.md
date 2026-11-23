# Pull Request Attention

The commands in `Functions\PullRequestAttention-Functions.ps1` list your open
GitHub pull requests that need your attention. They only read data through the
GitHub GraphQL API (via `gh api graphql`); they never change pull requests,
reviews or comments.

| Command | Lists open PRs you authored in the repository that... |
|---|---|
| `Get-PullRequestWithUnresolvedThread` | have at least one unresolved review thread |
| `Get-ApprovedPullRequestNotMerged` | are approved but not yet merged |
| `Get-PullRequestNeedingAttention` | match either rule; each PR appears once with the matching reasons |

## Prerequisites

- [GitHub CLI](https://cli.github.com) on `PATH`, signed in with `gh auth login`.

## Usage

Run from a clone whose `origin` remote is a GitHub repository and the owner and
name are inferred:

```powershell
Get-PullRequestNeedingAttention | Format-Table Number, Title, Reasons, Url
Get-PullRequestWithUnresolvedThread | Format-Table Number, Title, UnresolvedThreadCount
Get-ApprovedPullRequestNotMerged | Format-Table Number, Title, Approvers
```

Or name the repository explicitly and leave out drafts:

```powershell
Get-PullRequestNeedingAttention -Repository contoso/web-app -ExcludeDraft
```

Parameters shared by all three commands:

| Parameter | Default |
|---|---|
| `-Repository` | `owner/name` inferred from the `origin` remote of `-RepositoryPath`; an explicit value uses github.com |
| `-RepositoryPath` | Current location |
| `-ExcludeDraft` | Drafts are included |

Supported remote formats: `https://<host>/<owner>/<name>[.git]`,
`ssh://git@<host>/<owner>/<name>[.git]` and `git@<host>:<owner>/<name>[.git]`.
For a host other than github.com, the request is sent with `gh --hostname <host>`.

## Output

Each result is a `UVModule.PullRequestAttentionItem` with `Number`, `Title`,
`Repository`, `SourceBranch`, `TargetBranch`, `IsDraft`,
`UnresolvedThreadCount`, `ReviewDecision`, `Approvers`, `Reasons`
(`UnresolvedReviewThreads`, `ApprovedNotMerged`) and `Url`.

## Rules

- Only open pull requests authored by the signed-in user (`author:@me`) in the repository are checked.
- A review thread counts when `isResolved` is false, including outdated threads. All pages of review threads are read.
- Approved means `reviewDecision` is `APPROVED`. When the repository has no review requirement (`reviewDecision` is empty), a PR is approved when its latest reviews include an approval and no "changes requested".
- `Approvers` lists the logins whose latest review is an approval.
- A missing `gh`, failed sign-in, unknown repository or GraphQL error stops the command with a message.

## Limitations

- GitHub search returns at most 1,000 pull requests.
- Only the 100 latest reviews per pull request are read for approvers.
- General pull request conversation comments have no resolved state and are not counted.
