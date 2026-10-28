$script:InvokeReviewGit = {
    param ([string] $RepositoryPath, [string[]] $GitArguments)

    $output = & git -C $RepositoryPath @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }

    $output
}

$script:GetReviewTarget = {
    param ([string] $RepositoryPath, [string] $BranchName)

    & $script:InvokeReviewGit $RepositoryPath @('check-ref-format', "refs/heads/$BranchName") | Out-Null
    $isBareRepository = [string] (& $script:InvokeReviewGit $RepositoryPath @('rev-parse', '--is-bare-repository'))
    if ($isBareRepository -eq 'true') {
        $root = $RepositoryPath
    }
    else {
        $root = [string] (& $script:InvokeReviewGit $RepositoryPath @('rev-parse', '--show-toplevel'))
    }
    $root = [IO.Path]::GetFullPath($root)
    $folderName = 'review-' + ($BranchName -replace '[\\/:*?"<>|]', '-')
    $worktreeParent = if ($isBareRepository -eq 'true') { $root } else { Split-Path $root -Parent }

    [PSCustomObject]@{
        RepositoryPath = $root
        BranchName     = "review/$BranchName"
        WorktreePath   = Join-Path $worktreeParent $folderName
    }
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
    $existingBranch = & $script:InvokeReviewGit $root @('branch', '--list', $target.BranchName)
    if ($existingBranch) {
        throw "Local branch '$($target.BranchName)' already exists. Remove its review worktree before recreating it."
    }
    if (Test-Path -LiteralPath $target.WorktreePath) {
        throw "Path '$($target.WorktreePath)' already exists. No files have been changed."
    }

    if ($PSCmdlet.ShouldProcess($target.WorktreePath, "Fetch origin/$BranchName and create branch '$($target.BranchName)' and worktree")) {
        # Use an exact refspec so a stale remote-tracking ref cannot be reviewed.
        & $script:InvokeReviewGit $root @(
            'fetch', '--no-tags', 'origin', "+refs/heads/${BranchName}:refs/remotes/origin/$BranchName"
        ) | Out-Null
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
    $root = $target.RepositoryPath
    if (-not (Test-Path -LiteralPath $target.WorktreePath -PathType Container)) {
        throw "Review worktree '$($target.WorktreePath)' does not exist."
    }

    $worktreeRoot = [string] (& $script:InvokeReviewGit $target.WorktreePath @('rev-parse', '--show-toplevel'))
    $checkedOutBranch = [string] (& $script:InvokeReviewGit $target.WorktreePath @('symbolic-ref', '--quiet', 'HEAD'))
    if ([IO.Path]::GetFullPath($worktreeRoot) -ne $target.WorktreePath -or
        $checkedOutBranch -cne "refs/heads/$($target.BranchName)") {
        throw "Path '$($target.WorktreePath)' is not the expected review worktree and branch. Nothing was removed."
    }

    $commonDirectory = [string] (& $script:InvokeReviewGit $root @('rev-parse', '--path-format=absolute', '--git-common-dir'))
    $reviewCommonDirectory = [string] (& $script:InvokeReviewGit $target.WorktreePath @('rev-parse', '--path-format=absolute', '--git-common-dir'))
    if ([IO.Path]::GetFullPath($commonDirectory) -ne [IO.Path]::GetFullPath($reviewCommonDirectory)) {
        throw "Review worktree belongs to a different repository. Nothing was removed."
    }

    if (-not $Force) {
        $status = & $script:InvokeReviewGit $target.WorktreePath @('status', '--porcelain', '--untracked-files=all')
        if ($status) {
            throw "Review worktree contains uncommitted changes. Commit or discard them, then retry. Use -Force only to discard all review changes."
        }
        $localCommits = & $script:InvokeReviewGit $root @(
            'rev-list', '--count', "refs/remotes/origin/$BranchName..refs/heads/$($target.BranchName)"
        )
        if ([int] $localCommits -gt 0) {
            throw "Review branch contains $localCommits local-only commit(s) not in origin/$BranchName. Preserve them before retrying, or use -Force to discard them."
        }
    }

    if ($PSCmdlet.ShouldProcess($target.WorktreePath, "Remove review worktree and local branch '$($target.BranchName)' (discard local changes: $Force)")) {
        $arguments = @('worktree', 'remove')
        if ($Force) {
            $arguments += '--force'
        }
        $arguments += @('--', $target.WorktreePath)
        & $script:InvokeReviewGit $root $arguments | Out-Null
        # A PR need not be merged into the target branch to finish reviewing it.
        & $script:InvokeReviewGit $root @('branch', '-D', '--', $target.BranchName) | Out-Null
    }
}
