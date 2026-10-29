$script:InvokeReviewGit = {
    param ([string] $RepositoryPath, [string[]] $GitArguments)

    $output = & git -C $RepositoryPath @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }

    $output
}

$script:GetWorktreeTarget = {
    param ([string] $RepositoryPath, [string] $BranchName, [string] $FolderName, [string] $RemoteBranchName)

    & $script:InvokeReviewGit $RepositoryPath @('check-ref-format', "refs/heads/$BranchName") | Out-Null
    & $script:InvokeReviewGit $RepositoryPath @('check-ref-format', "refs/heads/$RemoteBranchName") | Out-Null
    $isBareRepository = [string] (& $script:InvokeReviewGit $RepositoryPath @('rev-parse', '--is-bare-repository'))
    if ($isBareRepository -eq 'true') {
        $root = $RepositoryPath
    }
    else {
        $root = [string] (& $script:InvokeReviewGit $RepositoryPath @('rev-parse', '--show-toplevel'))
    }
    $root = [IO.Path]::GetFullPath($root)
    $worktreeParent = if ($isBareRepository -eq 'true') { $root } else { Split-Path $root -Parent }

    [PSCustomObject]@{
        RepositoryPath   = $root
        BranchName       = $BranchName
        RemoteBranch     = $RemoteBranchName
        RemoteBranchName = "origin/$RemoteBranchName"
        WorktreePath     = Join-Path $worktreeParent $FolderName
    }
}

$script:GetReviewTarget = {
    param ([string] $RepositoryPath, [string] $BranchName)

    $folderName = 'review-' + ($BranchName -replace '[\\/:*?"<>|]', '-')
    & $script:GetWorktreeTarget $RepositoryPath "review/$BranchName" $folderName $BranchName
}

$script:GetWorkItemTarget = {
    param ([string] $RepositoryPath, [string] $WorkItemId, [string] $BranchName, [string] $Prefix = 'feat', [string] $RemoteBranchPrefix)

    $featureBranch = "$Prefix-$WorkItemId"
    if ($BranchName) {
        $featureBranch += "-$BranchName"
    }
    $folderName = $featureBranch -replace '[\\/:*?"<>|]', '-'
    $remoteBranch = if ($RemoteBranchPrefix) { "$RemoteBranchPrefix/$featureBranch" } else { $featureBranch }
    & $script:GetWorktreeTarget $RepositoryPath $featureBranch $folderName $remoteBranch
}

$script:GetWorktreePlan = {
    param ($Target, [string] $Action, [string] $SourceBranch, [bool] $Force = $false)

    [PSCustomObject][ordered]@{
        Action           = $Action
        RepositoryPath   = $Target.RepositoryPath
        LocalBranchName  = $Target.BranchName
        RemoteBranchName = $Target.RemoteBranchName
        SourceBranchName = $SourceBranch
        WorktreePath     = $Target.WorktreePath
        DiscardLocalWork = $Force
        RemoteAction     = if ($Action -eq 'Remove' -or $Target.BranchName.StartsWith('review/')) { 'Preserve' } else { 'Create' }
    }
}

$script:AssertWorktreeRemovalTarget = {
    param ($Target, [string] $WorktreeType, [switch] $Force)

    if (-not (Test-Path -LiteralPath $Target.WorktreePath -PathType Container)) {
        throw "$WorktreeType worktree '$($Target.WorktreePath)' does not exist."
    }
    $worktreeRoot = [string] (& $script:InvokeReviewGit $Target.WorktreePath @('rev-parse', '--show-toplevel'))
    $checkedOutBranch = [string] (& $script:InvokeReviewGit $Target.WorktreePath @('symbolic-ref', '--quiet', 'HEAD'))
    if ([IO.Path]::GetFullPath($worktreeRoot) -ne $Target.WorktreePath -or
        $checkedOutBranch -cne "refs/heads/$($Target.BranchName)") {
        throw "Path '$($Target.WorktreePath)' is not the expected $WorktreeType worktree and branch. Nothing was removed."
    }

    $commonDirectory = [string] (& $script:InvokeReviewGit $Target.RepositoryPath @('rev-parse', '--path-format=absolute', '--git-common-dir'))
    $worktreeCommonDirectory = [string] (& $script:InvokeReviewGit $Target.WorktreePath @('rev-parse', '--path-format=absolute', '--git-common-dir'))
    if ([IO.Path]::GetFullPath($commonDirectory) -ne [IO.Path]::GetFullPath($worktreeCommonDirectory)) {
        throw "$WorktreeType worktree belongs to a different repository. Nothing was removed."
    }

    if (-not $Force) {
        $status = & $script:InvokeReviewGit $Target.WorktreePath @('status', '--porcelain', '--untracked-files=all')
        if ($status) {
            throw "$WorktreeType worktree contains uncommitted changes. Preserve them before retrying, or use -Force to discard them."
        }
    }
}

$script:RemoveLocalWorktree = {
    param ($Target, [switch] $Force)

    $arguments = @('worktree', 'remove')
    if ($Force) {
        $arguments += '--force'
    }
    $arguments += @('--', $Target.WorktreePath)
    & $script:InvokeReviewGit $Target.RepositoryPath $arguments | Out-Null
    & $script:InvokeReviewGit $Target.RepositoryPath @('branch', '-D', '--', $Target.BranchName) | Out-Null
}

$script:AssertWorktreeCreationTarget = {
    param ($Target)

    $existingBranch = & $script:InvokeReviewGit $Target.RepositoryPath @('branch', '--list', $Target.BranchName)
    if ($existingBranch) {
        throw "Local branch '$($Target.BranchName)' already exists. Nothing was changed."
    }
    if (Test-Path -LiteralPath $Target.WorktreePath) {
        throw "Path '$($Target.WorktreePath)' already exists. Nothing was changed."
    }
}

$script:FetchWorktreeBranch = {
    param ([string] $RepositoryPath, [string] $BranchName)

    & $script:InvokeReviewGit $RepositoryPath @(
        'fetch', '--no-tags', 'origin', "+refs/heads/${BranchName}:refs/remotes/origin/$BranchName"
    ) | Out-Null
}

$script:AssertWorktreePushed = {
    param ($Target, [string] $WorktreeType)

    $localCommits = & $script:InvokeReviewGit $Target.RepositoryPath @(
        'rev-list', '--count', "refs/remotes/$($Target.RemoteBranchName)..refs/heads/$($Target.BranchName)"
    )
    if ([int] $localCommits -gt 0) {
        throw "$WorktreeType branch contains $localCommits local-only commit(s) not in $($Target.RemoteBranchName). Push and fetch them before retrying, or use -Force to discard them."
    }
}

$script:NewPublishedWorktree = {
    param ($Target, [string] $BaseBranch, $Caller, [bool] $Preview)

    $root = $Target.RepositoryPath
    & $script:InvokeReviewGit $root @('check-ref-format', "refs/heads/$BaseBranch") | Out-Null
    & $script:AssertWorktreeCreationTarget $Target
    if ($Preview) {
        & $script:GetWorktreePlan $Target 'Create' "origin/$BaseBranch"
    }

    if ($Caller.ShouldProcess($Target.WorktreePath, "Create local branch '$($Target.BranchName)' from origin/$BaseBranch and publish '$($Target.RemoteBranchName)'")) {
        $remoteBranch = & $script:InvokeReviewGit $root @('ls-remote', '--heads', 'origin', "refs/heads/$($Target.RemoteBranch)")
        if ($remoteBranch) {
            throw "Remote branch '$($Target.RemoteBranchName)' already exists. Nothing was changed."
        }
        & $script:FetchWorktreeBranch $root $BaseBranch
        & $script:InvokeReviewGit $root @(
            'worktree', 'add', '--no-track', '-b', $Target.BranchName, '--',
            $Target.WorktreePath, "refs/remotes/origin/$BaseBranch"
        ) | Out-Null
        try {
            $fetchMappings = & $script:InvokeReviewGit $root @('config', '--get-regexp', '^remote\.origin\.') |
            Where-Object { $_ -match '^remote\.origin\.fetch\s' }
            if (-not $fetchMappings) {
                & $script:InvokeReviewGit $root @(
                    'config', '--add', 'remote.origin.fetch', '+refs/heads/*:refs/remotes/origin/*'
                ) | Out-Null
            }
            & $script:InvokeReviewGit $root @(
                'push', '--set-upstream', "--force-with-lease=refs/heads/$($Target.RemoteBranch):", 'origin',
                "refs/heads/$($Target.BranchName):refs/heads/$($Target.RemoteBranch)"
            ) | Out-Null
            & $script:FetchWorktreeBranch $root $Target.RemoteBranch
            & $script:InvokeReviewGit $Target.WorktreePath @(
                'branch', '--set-upstream-to', $Target.RemoteBranchName, $Target.BranchName
            ) | Out-Null
        }
        catch {
            throw "Worktree '$($Target.WorktreePath)' and local branch were created, but publishing failed. Both were preserved. $($_.Exception.Message)"
        }
        $Target
    }
}

$script:RemovePublishedWorktree = {
    param ($Target, $Caller, [bool] $Preview, [switch] $Force)

    if ($Preview) {
        & $script:GetWorktreePlan $Target 'Remove' '' ([bool] $Force)
    }
    else {
        $worktreeType = if ($Target.BranchName.StartsWith('bug-')) { 'bug' } else { 'feature' }
        & $script:AssertWorktreeRemovalTarget $Target $worktreeType -Force:$Force
    }

    if ($Caller.ShouldProcess($Target.WorktreePath, "Remove worktree and local branch '$($Target.BranchName)' (discard local changes: $Force); preserve remote branch '$($Target.RemoteBranchName)'")) {
        if (-not $Force) {
            & $script:FetchWorktreeBranch $Target.RepositoryPath $Target.RemoteBranch
            & $script:AssertWorktreePushed $Target $worktreeType
        }
        & $script:RemoveLocalWorktree $Target -Force:$Force
    }
}

function New-Worktree {
    <#
    .SYNOPSIS
        Creates a feat-<id> worktree and publishes its tracking branch to origin.
    .PARAMETER WorkItemId
        Positive numeric task or user story ID. Also accepts TaskId or UserStoryId.
    .PARAMETER BranchName
        Optional suffix combined with the ID as feat-<id>-<BranchName>.
    .PARAMETER RemoteBranchPrefix
        Optional remote-only namespace, such as users/uv. Supply it again for removal.
    .PARAMETER BaseBranch
        Origin branch to start from, without origin/ or refs/heads/. Defaults to main.
    .PARAMETER RepositoryPath
        Repository to use. Defaults to the current repository.
    .EXAMPLE
        New-Worktree -UserStoryId 12345 -BaseBranch develop
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, Position = 0)]
        [Alias('TaskId', 'UserStoryId')]
        [ValidatePattern('^[1-9][0-9]*$')]
        [string] $WorkItemId,

        [ValidateNotNullOrEmpty()]
        [string] $BaseBranch = 'main',

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [ValidateNotNullOrEmpty()]
        [string] $BranchName,

        [ValidateNotNullOrEmpty()]
        [string] $RemoteBranchPrefix
    )

    $target = & $script:GetWorkItemTarget $RepositoryPath $WorkItemId $BranchName 'feat' $RemoteBranchPrefix
    & $script:NewPublishedWorktree $target $BaseBranch $PSCmdlet ([bool] $WhatIfPreference)
}

function Remove-Worktree {
    <#
    .SYNOPSIS
        Removes a feat-<id> worktree and local branch, preserving the remote branch.
    .PARAMETER WorkItemId
        The task or user story ID passed to New-Worktree. Also accepts TaskId or UserStoryId.
    .PARAMETER BranchName
        The same optional suffix passed to New-Worktree.
    .PARAMETER RemoteBranchPrefix
        The same remote-only namespace passed to New-Worktree.
    .PARAMETER Force
        Discards uncommitted files and unpushed commits. Does not bypass Git locks.
    .PARAMETER RepositoryPath
        Repository used when creating the worktree. Defaults to the current repository.
    .EXAMPLE
        Remove-Worktree -TaskId 12345
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [Alias('TaskId', 'UserStoryId')]
        [ValidatePattern('^[1-9][0-9]*$')]
        [string] $WorkItemId,

        [switch] $Force,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [ValidateNotNullOrEmpty()]
        [string] $BranchName,

        [ValidateNotNullOrEmpty()]
        [string] $RemoteBranchPrefix
    )

    $target = & $script:GetWorkItemTarget $RepositoryPath $WorkItemId $BranchName 'feat' $RemoteBranchPrefix
    & $script:RemovePublishedWorktree $target $PSCmdlet ([bool] $WhatIfPreference) -Force:$Force
}

function New-BugWorktree {
    <#
    .SYNOPSIS
        Creates and publishes a bug-<id>[-<BranchName>] tracking worktree.
    .PARAMETER WorkItemId
        Positive numeric bug ID. Also accepts BugId.
    .PARAMETER BranchName
        Optional suffix combined with the ID as bug-<id>-<BranchName>.
    .PARAMETER RemoteBranchPrefix
        Optional remote-only namespace, such as users/uv. Supply it again for removal.
    .PARAMETER BaseBranch
        Origin branch to start from. Defaults to main.
    .PARAMETER RepositoryPath
        Repository to use. Defaults to the current repository.
    .EXAMPLE
        New-BugWorktree -BugId 12345 -BranchName fix-login -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, Position = 0)]
        [Alias('BugId')]
        [ValidatePattern('^[1-9][0-9]*$')]
        [string] $WorkItemId,

        [ValidateNotNullOrEmpty()]
        [string] $BaseBranch = 'main',

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [ValidateNotNullOrEmpty()]
        [string] $BranchName,

        [ValidateNotNullOrEmpty()]
        [string] $RemoteBranchPrefix
    )

    $target = & $script:GetWorkItemTarget $RepositoryPath $WorkItemId $BranchName 'bug' $RemoteBranchPrefix
    & $script:NewPublishedWorktree $target $BaseBranch $PSCmdlet ([bool] $WhatIfPreference)
}

function Remove-BugWorktree {
    <#
    .SYNOPSIS
        Removes a bug worktree and local branch, preserving its remote branch.
    .PARAMETER WorkItemId
        Positive numeric bug ID passed to New-BugWorktree. Also accepts BugId.
    .PARAMETER BranchName
        The same optional suffix passed to New-BugWorktree.
    .PARAMETER RemoteBranchPrefix
        The same remote-only namespace passed to New-BugWorktree.
    .PARAMETER Force
        Discards uncommitted files and unpushed commits. Does not bypass Git locks.
    .PARAMETER RepositoryPath
        Repository used when creating the worktree. Defaults to the current repository.
    .EXAMPLE
        Remove-BugWorktree -BugId 12345 -BranchName fix-login -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [Alias('BugId')]
        [ValidatePattern('^[1-9][0-9]*$')]
        [string] $WorkItemId,

        [switch] $Force,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path,

        [ValidateNotNullOrEmpty()]
        [string] $BranchName,

        [ValidateNotNullOrEmpty()]
        [string] $RemoteBranchPrefix
    )

    $target = & $script:GetWorkItemTarget $RepositoryPath $WorkItemId $BranchName 'bug' $RemoteBranchPrefix
    & $script:RemovePublishedWorktree $target $PSCmdlet ([bool] $WhatIfPreference) -Force:$Force
}

function New-ReviewWorktree {
    <#
    .SYNOPSIS
        Creates a review branch and sibling worktree from an origin PR branch.
    .PARAMETER BranchName
        PR source branch name, without origin/ or refs/heads/ prefixes.
    .PARAMETER RepositoryPath
        Repository to use. Defaults to the current repository.
    .EXAMPLE
        New-ReviewWorktree -BranchName '12345-feature'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $BranchName,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path
    )
    Write-Debug "Getting review target for branch '$BranchName' in repository '$RepositoryPath'"
    $target = & $script:GetReviewTarget $RepositoryPath $BranchName
    Write-Debug ($target | Format-List | Out-String)
    $root = $target.RepositoryPath
    & $script:AssertWorktreeCreationTarget $target
    if ($WhatIfPreference) {
        & $script:GetWorktreePlan $target 'Create' "origin/$BranchName"
    }

    if ($PSCmdlet.ShouldProcess($target.WorktreePath, "Fetch origin/$BranchName and create branch '$($target.BranchName)' and worktree")) {
        & $script:FetchWorktreeBranch $root $BranchName
        & $script:InvokeReviewGit $root @(
            'worktree', 'add', '--track', '-b', $target.BranchName, '--',
            $target.WorktreePath, "refs/remotes/origin/$BranchName"
        ) | Out-Null

        $target
    }
}

function Remove-ReviewWorktree {
    <#
    .SYNOPSIS
        Removes a review worktree and its local review branch, never the remote branch.
    .PARAMETER BranchName
        The same PR source branch name passed to New-ReviewWorktree.
    .PARAMETER Force
        Discards uncommitted files (including untracked files) and local-only commits.
        Locked worktrees and worktrees containing submodules are still protected by Git.
    .PARAMETER RepositoryPath
        Repository used when creating the review worktree.
    .EXAMPLE
        Remove-ReviewWorktree -BranchName '12345-feature'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $BranchName,

        [switch] $Force,

        [ValidateNotNullOrEmpty()]
        [string] $RepositoryPath = (Get-Location).Path
    )

    $target = & $script:GetReviewTarget $RepositoryPath $BranchName
    if ($WhatIfPreference) {
        & $script:GetWorktreePlan $target 'Remove' '' ([bool] $Force)
    }
    else {
        & $script:AssertWorktreeRemovalTarget $target 'review' -Force:$Force
        if (-not $Force) {
            & $script:AssertWorktreePushed $target 'Review'
        }
    }

    if ($PSCmdlet.ShouldProcess($target.WorktreePath, "Remove review worktree and local branch '$($target.BranchName)' (discard local changes: $Force)")) {
        & $script:RemoveLocalWorktree $target -Force:$Force
    }
}
