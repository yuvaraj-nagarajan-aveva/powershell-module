# Research: Pull Request Attention Functions

## R1 Platform
- **Decision**: GitHub (clarified by the user on 2026-11-12). Supersedes the earlier Azure DevOps decision.

## R2 Transport and authentication
- **Decision**: `gh api graphql -f query=<query> -f <name>=<string> -F <name>=<int> [--hostname <host>]`, wrapped in `$script:InvokeGitHubGraphQL`. The `gh` executable name is held in `$script:GitHubCliCommand`.
- **Rationale**: Reuses the user's `gh auth login` (or `GH_TOKEN`) sign-in, so the module never handles tokens. One helper is the single seam replaced by tests, mirroring `$script:InvokeReviewGit`. GraphQL returns thread resolution and review decision in one call; REST has no review-thread resolution state.
- **Alternatives**: `gh pr list --json reviewDecision` (has no review-thread data); REST via `Invoke-RestMethod` (needs token handling and no `isResolved`).
- **Error handling**: non-zero `gh` exit → throw with `gh` output; a GraphQL `errors` array → throw with the messages; missing `gh` → throw with install and `gh auth login` guidance.
- **Not verified**: Postman API discovery could not run (CLI signed out). GitHub Docs search confirmed the GraphQL reference includes `reviewThreads`, `isResolved` and `reviewDecision`.

## R3 Queries
- PRs: `search(query: "repo:{owner}/{name} is:pr is:open author:@me", type: ISSUE, first: 50, after: $cursor)` returning `number title url isDraft headRefName baseRefName reviewDecision repository.nameWithOwner`, `latestOpinionatedReviews(first: 100) { state author.login }` and `reviewThreads(first: 100) { pageInfo, isResolved }`. Paged on `pageInfo.hasNextPage`.
- Extra threads: `repository(owner, name).pullRequest(number).reviewThreads(first: 100, after: $cursor)` while `hasNextPage`.

## R4 Repository inference
- **Decision**: Parse `origin` for `https://[user@]{host}/{owner}/{name}[.git]`, `git@{host}:{owner}/{name}[.git]` and `ssh://git@{host}[:port]/{owner}/{name}[.git]`. `-Repository owner/name` overrides and uses `github.com`. A non-`github.com` host is passed to `gh` as `--hostname` (GitHub Enterprise).

## R5 Unresolved thread rule
- **Decision**: Count threads with `isResolved = false`, including outdated threads.

## R6 Approval rule
- **Decision**: `reviewDecision = APPROVED` → approved. `CHANGES_REQUESTED` or `REVIEW_REQUIRED` → not approved. `null` (no review requirement) → approved when `latestOpinionatedReviews` has at least one `APPROVED` and no `CHANGES_REQUESTED`. Approvers are the logins of `APPROVED` latest reviews.

## R7 Shared evaluation
- **Decision**: One helper builds an attention item per PR; the three commands filter by reason. Thread data arrives with the search, so no extra call per PR unless a PR has more than 100 threads.

## Known limitations
- GitHub search returns at most 1,000 results.
- At most 100 latest reviews per PR are read for approvers.
- General PR conversation comments have no resolved state and are not counted.
