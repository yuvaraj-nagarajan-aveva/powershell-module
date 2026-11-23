. "$PSScriptRoot\..\Functions\Worktree-Functions.ps1"
. "$PSScriptRoot\..\Functions\GitHub-Functions.ps1"
. "$PSScriptRoot\..\Functions\PullRequestAttention-Functions.ps1"

function New-FakeReview {
    param ([string] $Login, [string] $State)

    [PSCustomObject]@{ state = $State; author = [PSCustomObject]@{ login = $Login } }
}

function New-FakePullRequest {
    param (
        [int] $Number,
        [bool[]] $ThreadResolvedStates = @(),
        [string] $ReviewDecision,
        [object[]] $Reviews = @(),
        [bool] $IsDraft = $false,
        [string] $NextThreadCursor
    )

    [PSCustomObject]@{
        number                   = $Number
        title                    = "PR $Number"
        url                      = "https://github.com/contoso/web-app/pull/$Number"
        isDraft                  = $IsDraft
        headRefName              = "feature/$Number"
        baseRefName              = 'main'
        reviewDecision           = if ($ReviewDecision) { $ReviewDecision } else { $null }
        repository               = [PSCustomObject]@{ nameWithOwner = 'contoso/web-app' }
        latestOpinionatedReviews = [PSCustomObject]@{ nodes = $Reviews }
        reviewThreads            = [PSCustomObject]@{
            pageInfo = [PSCustomObject]@{ hasNextPage = [bool] $NextThreadCursor; endCursor = $NextThreadCursor }
            nodes    = @($ThreadResolvedStates | ForEach-Object { [PSCustomObject]@{ isResolved = $_ } })
        }
    }
}

function Invoke-AttentionCommand {
    param ([string] $CommandName, [hashtable] $ExtraParameters = @{})

    @(& $CommandName -Repository 'contoso/web-app' @ExtraParameters)
}

Describe 'Pull request attention' {
    BeforeEach {
        $savedInvoke = $script:InvokeGitHubGraphQL
        $script:FakePullRequests = @()
        $script:FakeExtraThreadStates = @{}
        $script:GraphQLCalls = [Collections.Generic.List[object]]::new()
        $script:InvokeGitHubGraphQL = {
            param ([string] $Query, [hashtable] $Variables, [string] $Hostname)

            $script:GraphQLCalls.Add([PSCustomObject]@{ Query = $Query; Variables = $Variables; Hostname = $Hostname })
            if ($Variables.ContainsKey('searchQuery')) {
                return [PSCustomObject]@{ search = [PSCustomObject]@{
                        pageInfo = [PSCustomObject]@{ hasNextPage = $false; endCursor = $null }
                        nodes    = @($script:FakePullRequests)
                    } }
            }
            [PSCustomObject]@{ repository = [PSCustomObject]@{ pullRequest = [PSCustomObject]@{ reviewThreads = [PSCustomObject]@{
                            pageInfo = [PSCustomObject]@{ hasNextPage = $false; endCursor = $null }
                            nodes    = @($script:FakeExtraThreadStates[$Variables.number] | ForEach-Object { [PSCustomObject]@{ isResolved = $_ } })
                        } } } }
        }
    }

    AfterEach {
        $script:InvokeGitHubGraphQL = $savedInvoke
    }

    It 'GetPullRequestWithUnresolvedThread_UnresolvedThreads_ReturnsPullRequestWithCount' {
        $script:FakePullRequests = @(New-FakePullRequest 1 -ThreadResolvedStates @($false, $false, $true))
        $result = Invoke-AttentionCommand 'Get-PullRequestWithUnresolvedThread'
        $result.Count | Should Be 1
        $result[0].Number | Should Be 1
        $result[0].UnresolvedThreadCount | Should Be 2
        $result[0].Reasons -contains 'UnresolvedReviewThreads' | Should Be $true
    }

    It 'GetPullRequestWithUnresolvedThread_AllThreadsResolved_ReturnsNothing' {
        $script:FakePullRequests = @(
            New-FakePullRequest 2 -ThreadResolvedStates @($true, $true)
            New-FakePullRequest 3
        )
        (Invoke-AttentionCommand 'Get-PullRequestWithUnresolvedThread').Count | Should Be 0
    }

    It 'GetPullRequestWithUnresolvedThread_MoreThreadPages_CountsEveryPage' {
        $script:FakePullRequests = @(New-FakePullRequest 4 -ThreadResolvedStates @($true) -NextThreadCursor 'threads-2')
        $script:FakeExtraThreadStates[4] = @($false, $false, $true)
        $result = Invoke-AttentionCommand 'Get-PullRequestWithUnresolvedThread'
        $result[0].UnresolvedThreadCount | Should Be 2
    }

    It 'GetPullRequestWithUnresolvedThread_ReturnsDocumentedShape' {
        $script:FakePullRequests = @(New-FakePullRequest 5 -ThreadResolvedStates @($false) -IsDraft $true -ReviewDecision 'REVIEW_REQUIRED')
        $item = (Invoke-AttentionCommand 'Get-PullRequestWithUnresolvedThread')[0]
        $item.PSObject.TypeNames[0] | Should Be 'UVModule.PullRequestAttentionItem'
        $item.Title | Should Be 'PR 5'
        $item.Repository | Should Be 'contoso/web-app'
        $item.SourceBranch | Should Be 'feature/5'
        $item.TargetBranch | Should Be 'main'
        $item.IsDraft | Should Be $true
        $item.ReviewDecision | Should Be 'REVIEW_REQUIRED'
        $item.Url | Should Be 'https://github.com/contoso/web-app/pull/5'
    }

    It 'GetPullRequestWithUnresolvedThread_ExcludeDraft_SkipsDraftPullRequests' {
        $script:FakePullRequests = @(
            New-FakePullRequest 6 -ThreadResolvedStates @($false) -IsDraft $true
            New-FakePullRequest 7 -ThreadResolvedStates @($false)
        )
        $result = Invoke-AttentionCommand 'Get-PullRequestWithUnresolvedThread' @{ ExcludeDraft = $true }
        $result.Count | Should Be 1
        $result[0].Number | Should Be 7
    }

    It 'AttentionCommands_OnlySendReadOnlyQueries' {
        $script:FakePullRequests = @(New-FakePullRequest 8 -ThreadResolvedStates @($false) -NextThreadCursor 'threads-2')
        Invoke-AttentionCommand 'Get-PullRequestNeedingAttention' | Out-Null
        $script:GraphQLCalls.Count | Should Be 2
        foreach ($call in $script:GraphQLCalls) {
            $call.Query.TrimStart() | Should Match '^query '
            $call.Query | Should Not Match '(?i)mutation'
            $call.Hostname | Should Be 'github.com'
        }
    }

    It 'GetApprovedPullRequestNotMerged_ReviewDecisionApproved_ReturnsApprovers' {
        $script:FakePullRequests = @(
            New-FakePullRequest 10 -ReviewDecision 'APPROVED' -Reviews @((New-FakeReview 'ann' 'APPROVED'), (New-FakeReview 'bob' 'COMMENTED'), (New-FakeReview 'cy' 'APPROVED'))
        )
        $result = Invoke-AttentionCommand 'Get-ApprovedPullRequestNotMerged'
        $result.Count | Should Be 1
        ($result[0].Approvers -join ',') | Should Be 'ann,cy'
        $result[0].Reasons -contains 'ApprovedNotMerged' | Should Be $true
    }

    It 'GetApprovedPullRequestNotMerged_NoReviewDecision_UsesLatestReviews' {
        $script:FakePullRequests = @(
            New-FakePullRequest 11 -Reviews @(New-FakeReview 'ann' 'APPROVED')
            New-FakePullRequest 12 -Reviews @((New-FakeReview 'ann' 'APPROVED'), (New-FakeReview 'bob' 'CHANGES_REQUESTED'))
            New-FakePullRequest 13
        )
        $result = Invoke-AttentionCommand 'Get-ApprovedPullRequestNotMerged'
        ($result.Number -join ',') | Should Be '11'
    }

    It 'GetApprovedPullRequestNotMerged_ChangesRequestedOrReviewRequired_ReturnsNothing' {
        $script:FakePullRequests = @(
            New-FakePullRequest 14 -ReviewDecision 'CHANGES_REQUESTED' -Reviews @(New-FakeReview 'ann' 'APPROVED')
            New-FakePullRequest 15 -ReviewDecision 'REVIEW_REQUIRED' -Reviews @(New-FakeReview 'ann' 'APPROVED')
        )
        (Invoke-AttentionCommand 'Get-ApprovedPullRequestNotMerged').Count | Should Be 0
    }

    It 'GetPullRequestNeedingAttention_MixedPullRequests_ReturnsEachOnceWithReasons' {
        $script:FakePullRequests = @(
            New-FakePullRequest 20 -ThreadResolvedStates @($false)
            New-FakePullRequest 21 -ReviewDecision 'APPROVED'
            New-FakePullRequest 22 -ThreadResolvedStates @($false) -ReviewDecision 'APPROVED'
            New-FakePullRequest 23 -ThreadResolvedStates @($true) -ReviewDecision 'REVIEW_REQUIRED'
        )
        $result = Invoke-AttentionCommand 'Get-PullRequestNeedingAttention'
        ($result.Number -join ',') | Should Be '20,21,22'
        ($result[0].Reasons -join ',') | Should Be 'UnresolvedReviewThreads'
        ($result[1].Reasons -join ',') | Should Be 'ApprovedNotMerged'
        ($result[2].Reasons -join ',') | Should Be 'UnresolvedReviewThreads,ApprovedNotMerged'
    }

    It 'GetPullRequestNeedingAttention_NothingNeedsAttention_ReturnsNothing' {
        $script:FakePullRequests = @(New-FakePullRequest 30)
        (Invoke-AttentionCommand 'Get-PullRequestNeedingAttention').Count | Should Be 0
    }

    It 'AttentionCommands_ArePublishedWithSharedParameters' {
        foreach ($commandName in @('Get-PullRequestWithUnresolvedThread', 'Get-ApprovedPullRequestNotMerged', 'Get-PullRequestNeedingAttention')) {
            $parameters = (Get-Command $commandName).Parameters
            foreach ($parameterName in @('Repository', 'RepositoryPath', 'ExcludeDraft')) {
                $parameters.ContainsKey($parameterName) | Should Be $true
            }
        }
    }
}
