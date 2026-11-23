# Feature Specification: Pull Request Attention Functions

**Feature Branch**: `001-pr-attention-functions`  
**Created**: 2026-11-12  
**Updated**: 2026-11-12 (target changed from Azure DevOps to GitHub)  
**Status**: Draft  
**Input**: User description: "script functions to check my pull requests to list out ones having active comments still not resolved. And another to list out ones which have reviews approved but not completed and a final one that merges both to give me a list of PRs that need my attention"

## Clarifications

### Session 2026-11-12

- Q: Which platform hosts the pull requests? → A: GitHub. Scope is the current repository and pull requests authored by the signed-in user. The commands are read-only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - List my PRs with unresolved review threads (Priority: P1)

As a developer who authors pull requests, I want one command that lists my open
pull requests in the current repository that still have unresolved review
conversations, so I know which reviews are waiting on my reply or fix.

**Why this priority**: Unanswered review comments are the most common reason a
PR stalls; seeing them is the core value of the feature.

**Independent Test**: With a set of open PRs authored by me, some with
unresolved review threads and some with only resolved threads, running the
command returns exactly the PRs with at least one unresolved thread and the
number of such threads for each.

**Acceptance Scenarios**:

1. **Given** I have an open PR with two unresolved and one resolved review thread, **When** I run the command, **Then** the PR is listed with an unresolved thread count of 2.
2. **Given** I have an open PR whose review threads are all resolved, **When** I run the command, **Then** that PR is not listed.
3. **Given** an open PR has more review threads than one page of results, **When** I run the command, **Then** unresolved threads on every page are counted.
4. **Given** open PRs authored by other people or in other repositories, **When** I run the command, **Then** those PRs are not listed.

---

### User Story 2 - List my approved PRs not yet merged (Priority: P2)

As a PR author, I want one command that lists my open pull requests that have
been approved but are not yet merged, so I can merge them and avoid leaving
approved work idle.

**Why this priority**: Approved-but-idle PRs are easy to forget, but they are
less urgent than unanswered feedback.

**Independent Test**: With open PRs in different review states, running the
command returns only approved PRs.

**Acceptance Scenarios**:

1. **Given** my open PR has a review decision of "approved", **When** I run the command, **Then** the PR is listed with the approving reviewers' logins.
2. **Given** my open PR has a review decision of "changes requested" or "review required", **When** I run the command, **Then** the PR is not listed.
3. **Given** the repository does not require reviews (no review decision) and my PR has at least one approving latest review and no latest "changes requested" review, **When** I run the command, **Then** the PR is listed.
4. **Given** the repository does not require reviews and my PR has no approving review, or has a latest "changes requested" review, **When** I run the command, **Then** it is not listed.
5. **Given** my PR is merged or closed, **When** I run the command, **Then** it is not listed.

---

### User Story 3 - One list of PRs that need my attention (Priority: P3)

As a PR author, I want one command that combines both lists into a single list
of distinct PRs, each showing why it needs attention.

**Why this priority**: It is a convenience on top of stories 1 and 2.

**Independent Test**: With one PR that has only unresolved threads, one that is
only approved, and one that is both, running the command returns three distinct
entries, the last with both reasons.

**Acceptance Scenarios**:

1. **Given** a PR appears in both lists, **When** I run the combined command, **Then** it appears once with both reasons listed.
2. **Given** no PR needs attention, **When** I run the combined command, **Then** it returns nothing and does not fail.

---

### Edge Cases

- The current folder is not a Git repository, or its `origin` remote is not a GitHub repository, and no repository is given: the command fails with a clear message.
- The GitHub CLI is missing or not signed in: the command fails with a message explaining how to install it or sign in.
- GitHub returns an error: the command fails with GitHub's message rather than returning an empty list.
- Draft PRs are included by default but can be excluded on request.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a command that lists open PRs authored by the signed-in user in the target repository that have at least one unresolved review thread.
- **FR-002**: The module MUST provide a command that lists open PRs authored by the signed-in user in the target repository that are approved: review decision "approved", or, when the repository reports no review decision, at least one approving latest review and no latest "changes requested" review.
- **FR-003**: The module MUST provide a command that returns the distinct union of FR-001 and FR-002 results, each item carrying the list of reasons it needs attention.
- **FR-004**: Each result MUST include the PR number, title, repository, head and base branch, whether it is a draft, a web link, the unresolved thread count, the review decision, and the approving reviewers.
- **FR-005**: The target repository MUST default to the `origin` remote of the current Git repository, and users MUST be able to name a different `owner/name` repository.
- **FR-006**: The commands MUST use the user's existing GitHub CLI sign-in and MUST NOT store or prompt for credentials.
- **FR-007**: Users MUST be able to exclude draft PRs.
- **FR-008**: Configuration and service errors MUST surface as terminating errors with a clear message.
- **FR-009**: The commands MUST be read-only and never change PRs, reviews or threads.

### Key Entities

- **Pull request attention item**: one PR that needs attention; holds number, title, repository, branches, draft flag, link, unresolved thread count, review decision, approvers, and reasons (`UnresolvedReviewThreads`, `ApprovedNotMerged`).
- **Review thread**: a review conversation on a PR that is resolved or unresolved.
- **Review decision**: the repository's overall review state for a PR (approved, changes requested, review required, or none).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user gets the full list of PRs needing attention in the current repository with a single command and no manual browsing.
- **SC-002**: 100% of PRs with an unresolved review thread are reported, and 0 PRs with only resolved threads are reported, in the automated scenarios.
- **SC-003**: 100% of approved open PRs are reported, and 0 PRs with changes requested or missing approval are reported, in the automated scenarios.
- **SC-004**: Every PR appears at most once in the combined list.

## Assumptions

- "My pull requests" means open PRs authored by the signed-in user in one repository.
- "Active comments still not resolved" means unresolved review threads (review conversations). General PR conversation comments have no resolved state and are out of scope.
- "Not completed" means not merged; only open PRs are checked.
- Unresolved threads marked outdated still count, because they remain unresolved.
- PRs where the user is a reviewer (rather than the author) are out of scope.
- The user has the GitHub CLI installed and signed in to the repository's host.
- Results are returned as objects so users can sort, filter, or format them.
