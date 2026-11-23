$script:UnresolvedReviewThreadsReason = 'UnresolvedReviewThreads'
$script:ApprovedNotMergedReason = 'ApprovedNotMerged'

$script:GetApproverLogins = {
    param ($PullRequest)

    @($PullRequest.latestOpinionatedReviews.nodes |
        Where-Object { $_ -and $_.state -eq 'APPROVED' -and $_.author -and $_.author.login } |
        ForEach-Object { [string] $_.author.login })
}

$script:TestPullRequestApproved = {
    param ($PullRequest)

    if ($PullRequest.reviewDecision -eq 'APPROVED') {
        return $true
    }
    if ($PullRequest.reviewDecision) {
        return $false
    }
    $states = @($PullRequest.latestOpinionatedReviews.nodes | Where-Object { $_ } | ForEach-Object { $_.state })
    ($states -contains 'APPROVED') -and -not ($states -contains 'CHANGES_REQUESTED')
}

$script:ConvertToPullRequestAttentionItem = {
    param ($Repository, $PullRequest)

    $unresolvedThreadCount = @(& $script:GetAllReviewThreads $Repository $PullRequest | Where-Object { -not $_.isResolved }).Count
    $reasons = @()
    if ($unresolvedThreadCount -gt 0) {
        $reasons += $script:UnresolvedReviewThreadsReason
    }
    if (& $script:TestPullRequestApproved $PullRequest) {
        $reasons += $script:ApprovedNotMergedReason
    }

    [PSCustomObject]@{
        PSTypeName            = 'UVModule.PullRequestAttentionItem'
        Number                = [int] $PullRequest.number
        Title                 = [string] $PullRequest.title
        Repository            = [string] $PullRequest.repository.nameWithOwner
        SourceBranch          = [string] $PullRequest.headRefName
        TargetBranch          = [string] $PullRequest.baseRefName
        IsDraft               = [bool] $PullRequest.isDraft
        UnresolvedThreadCount = $unresolvedThreadCount
        ReviewDecision        = $PullRequest.reviewDecision
        Approvers             = [string[]] (& $script:GetApproverLogins $PullRequest)
        Reasons               = [string[]] $reasons
        Url                   = [string] $PullRequest.url
    }
}

$script:GetPullRequestAttentionItems = {
    param ([string] $Repository, [string] $RepositoryPath, [bool] $ExcludeDraft, [string] $Reason)

    $resolvedRepository = & $script:GetGitHubRepository $Repository $RepositoryPath
    & $script:GetMyOpenPullRequests $resolvedRepository |
        Where-Object { -not ($ExcludeDraft -and $_.isDraft) } |
        ForEach-Object { & $script:ConvertToPullRequestAttentionItem $resolvedRepository $_ } |
        Where-Object { if ($Reason) { $_.Reasons -contains $Reason } else { $_.Reasons.Count -gt 0 } }
}

function Get-PullRequestWithUnresolvedThread {
    <#
    .SYNOPSIS
        Lists your open GitHub pull requests that still have unresolved review threads.
    .PARAMETER Repository
        GitHub repository as owner/name. Defaults to the origin remote of RepositoryPath.
    .PARAMETER RepositoryPath
        Local repository used to infer the GitHub repository. Defaults to the current location.
    .PARAMETER ExcludeDraft
        Skips draft pull requests.
    .EXAMPLE
        Get-PullRequestWithUnresolvedThread -Repository contoso/web-app
    #>
    [CmdletBinding()]
    [OutputType('UVModule.PullRequestAttentionItem')]
    param (
        [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')]
        [string] $Repository,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [switch] $ExcludeDraft
    )

    & $script:GetPullRequestAttentionItems $Repository $RepositoryPath $ExcludeDraft.IsPresent $script:UnresolvedReviewThreadsReason
}

function Get-ApprovedPullRequestNotMerged {
    <#
    .SYNOPSIS
        Lists your open GitHub pull requests that are approved but not yet merged.
    .PARAMETER Repository
        GitHub repository as owner/name. Defaults to the origin remote of RepositoryPath.
    .PARAMETER RepositoryPath
        Local repository used to infer the GitHub repository. Defaults to the current location.
    .PARAMETER ExcludeDraft
        Skips draft pull requests.
    .EXAMPLE
        Get-ApprovedPullRequestNotMerged -ExcludeDraft
    #>
    [CmdletBinding()]
    [OutputType('UVModule.PullRequestAttentionItem')]
    param (
        [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')]
        [string] $Repository,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [switch] $ExcludeDraft
    )

    & $script:GetPullRequestAttentionItems $Repository $RepositoryPath $ExcludeDraft.IsPresent $script:ApprovedNotMergedReason
}

function Get-PullRequestNeedingAttention {
    <#
    .SYNOPSIS
        Lists your open GitHub pull requests that have unresolved review threads or are approved but not merged.
    .DESCRIPTION
        Returns each pull request once, with Reasons listing every condition that applies.
    .PARAMETER Repository
        GitHub repository as owner/name. Defaults to the origin remote of RepositoryPath.
    .PARAMETER RepositoryPath
        Local repository used to infer the GitHub repository. Defaults to the current location.
    .PARAMETER ExcludeDraft
        Skips draft pull requests.
    .EXAMPLE
        Get-PullRequestNeedingAttention | Format-Table Number, Title, Reasons
    #>
    [CmdletBinding()]
    [OutputType('UVModule.PullRequestAttentionItem')]
    param (
        [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')]
        [string] $Repository,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [switch] $ExcludeDraft
    )

    & $script:GetPullRequestAttentionItems $Repository $RepositoryPath $ExcludeDraft.IsPresent ''
}
