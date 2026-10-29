. "$PSScriptRoot\..\Functions\Worktree-Functions.ps1"

function Assert-ReviewFailure {
    param ([scriptblock] $Action, [string] $ExpectedMessage)

    # Pester 3's Should Throw does not recognize exceptions under PowerShell 7.
    $message = $null
    try {
        & $Action
    }
    catch {
        $message = $_.Exception.Message
    }
    $message | Should Not BeNullOrEmpty
    $message | Should Match ([regex]::Escape($ExpectedMessage))
}

Describe 'Review worktrees' {
    BeforeEach {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("review-" + [Guid]::NewGuid().ToString('N'))
        $repository = Join-Path $testRoot 'checkout'
        $remote = Join-Path $testRoot 'origin.git'
        $reviewPath = Join-Path $testRoot 'review-feature-test'
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & $script:InvokeReviewGit $testRoot @('init', '--bare', $remote) | Out-Null
        & $script:InvokeReviewGit $repository @('init', '--initial-branch=main') | Out-Null
        & $script:InvokeReviewGit $repository @('config', 'user.name', 'Worktree Tests') | Out-Null
        & $script:InvokeReviewGit $repository @('config', 'user.email', 'worktree-tests@example.invalid') | Out-Null
        & $script:InvokeReviewGit $repository @('config', 'commit.gpgsign', 'false') | Out-Null
        & $script:InvokeReviewGit $repository @('commit', '--allow-empty', '-m', 'Initial commit') | Out-Null
        & $script:InvokeReviewGit $repository @('remote', 'add', 'origin', $remote) | Out-Null
        & $script:InvokeReviewGit $repository @('push', 'origin', 'main') | Out-Null
        & $script:InvokeReviewGit $repository @('checkout', '-b', 'feature/test') | Out-Null
        & $script:InvokeReviewGit $repository @('commit', '--allow-empty', '-m', 'PR commit') | Out-Null
        & $script:InvokeReviewGit $repository @('push', 'origin', 'feature/test') | Out-Null
        & $script:InvokeReviewGit $repository @('checkout', 'main') | Out-Null
    }

    AfterEach {
        # Each test owns only this uniquely named temporary repository tree.
        if ($testRoot -and (Test-Path -LiteralPath $testRoot)) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }

    It 'NewWorktree_RemoteBranchPrefix_PublishesNamespacedBranchAndSetsUpstream' {
        $result = New-Worktree 12345 -BranchName add-search -RemoteBranchPrefix users/uv -RepositoryPath $repository
        $result.BranchName | Should Be 'feat-12345-add-search'
        $result.RemoteBranchName | Should Be 'origin/users/uv/feat-12345-add-search'
        $result.WorktreePath | Should Be (Join-Path $testRoot 'feat-12345-add-search')
        (& $script:InvokeReviewGit $result.WorktreePath @('rev-parse', '--abbrev-ref', '@{upstream}')) |
        Should Be 'origin/users/uv/feat-12345-add-search'
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'refs/heads/users/uv/feat-12345-add-search')) |
        Should Not BeNullOrEmpty
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'refs/heads/feat-12345-add-search')) |
        Should BeNullOrEmpty
        Remove-Worktree 12345 -BranchName add-search -RemoteBranchPrefix users/uv -RepositoryPath $repository -Confirm:$false
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'refs/heads/users/uv/feat-12345-add-search')) |
        Should Not BeNullOrEmpty
    }

    It 'NewBugWorktree_BugIdAndSuffix_CreatesAndRemovesBugBranch' {
        $result = New-BugWorktree -BugId 54321 -BranchName fix-login -RepositoryPath $repository
        $result.BranchName | Should Be 'bug-54321-fix-login'
        $result.RemoteBranchName | Should Be 'origin/bug-54321-fix-login'
        $result.WorktreePath | Should Be (Join-Path $testRoot 'bug-54321-fix-login')
        (& $script:InvokeReviewGit $result.WorktreePath @('rev-parse', '--abbrev-ref', '@{upstream}')) |
        Should Be 'origin/bug-54321-fix-login'
        Remove-BugWorktree -BugId 54321 -BranchName fix-login -RepositoryPath $repository -Confirm:$false
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $false
    }

    It 'NewBugWorktree_WhatIf_ReturnsPlanWithoutRemoteAccess' {
        & $script:InvokeReviewGit $repository @('remote', 'remove', 'origin') | Out-Null
        $before = & $script:InvokeReviewGit $repository @('show-ref')
        $plan = New-BugWorktree -BugId 54321 -BranchName fix-login -RemoteBranchPrefix users/uv -RepositoryPath $repository -WhatIf
        $plan.LocalBranchName | Should Be 'bug-54321-fix-login'
        $plan.RemoteBranchName | Should Be 'origin/users/uv/bug-54321-fix-login'
        $plan.SourceBranchName | Should Be 'origin/main'
        $plan.WorktreePath | Should Be (Join-Path $testRoot 'bug-54321-fix-login')
        $plan.RemoteAction | Should Be 'Create'
        (Test-Path -LiteralPath $plan.WorktreePath) | Should Be $false
        ((& $script:InvokeReviewGit $repository @('show-ref')) -join "`n") | Should Be ($before -join "`n")
    }

    It 'NewWorktree_InvalidRemoteBranchPrefix_RefusesBeforeMutation' {
        Assert-ReviewFailure {
            New-Worktree 12345 -RemoteBranchPrefix '../users' -RepositoryPath $repository -WhatIf
        } 'check-ref-format'
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should BeNullOrEmpty
    }

    It 'NewWorktree_WorkItemId_CreatesAndPublishesTrackingBranchFromBase' {
        $result = New-Worktree -WorkItemId 12345 -RepositoryPath $repository
        $result.BranchName | Should Be 'feat-12345'
        $result.WorktreePath | Should Be (Join-Path $testRoot 'feat-12345')
        (& $script:InvokeReviewGit $result.WorktreePath @('rev-parse', '--abbrev-ref', '@{upstream}')) | Should Be 'origin/feat-12345'
        (& $script:InvokeReviewGit $result.WorktreePath @('rev-parse', 'HEAD')) |
        Should Be (& $script:InvokeReviewGit $repository @('rev-parse', 'refs/remotes/origin/main'))
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'feat-12345')) | Should Not BeNullOrEmpty
        (& $script:InvokeReviewGit $repository @('branch', '--show-current')) | Should Be 'main'
    }

    It 'NewWorktree_TaskIdAndCustomBase_UsesLatestRemoteCommit' {
        $result = New-Worktree -TaskId 12345 -BaseBranch 'feature/test' -RepositoryPath $repository
        (& $script:InvokeReviewGit $result.WorktreePath @('rev-parse', 'HEAD')) |
        Should Be (& $script:InvokeReviewGit $repository @('rev-parse', 'refs/remotes/origin/feature/test'))
    }

    It 'NewWorktree_UserStoryId_DefaultsToCurrentRepository' {
        Push-Location $repository
        try {
            $result = New-Worktree -UserStoryId 12345
            $result.RepositoryPath | Should Be ([IO.Path]::GetFullPath($repository))
        }
        finally {
            Pop-Location
        }
    }

    It 'NewWorktree_BareRepository_CreatesWorktreeInsideRepository' {
        $bareClone = Join-Path $testRoot 'clone.git'
        & $script:InvokeReviewGit $testRoot @('clone', '--bare', $remote, $bareClone) | Out-Null
        $result = New-Worktree 12345 -RepositoryPath $bareClone
        $result.WorktreePath | Should Be (Join-Path $bareClone 'feat-12345')
        (& $script:InvokeReviewGit $result.WorktreePath @('rev-parse', '--abbrev-ref', '@{upstream}')) | Should Be 'origin/feat-12345'
        Remove-Worktree 12345 -RepositoryPath $bareClone -Confirm:$false
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $false
    }

    It 'NewWorktree_WhatIf_DoesNotCreateLocalOrRemoteBranch' {
        New-Worktree 12345 -RepositoryPath $repository -WhatIf
        (Test-Path -LiteralPath (Join-Path $testRoot 'feat-12345')) | Should Be $false
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should BeNullOrEmpty
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'feat-12345')) | Should BeNullOrEmpty
    }

    It 'NewWorktree_ExistingRemoteBranch_RefusesWithoutCreatingLocalBranch' {
        & $script:InvokeReviewGit $repository @('push', 'origin', 'main:refs/heads/feat-12345') | Out-Null
        Assert-ReviewFailure { New-Worktree 12345 -RepositoryPath $repository } 'Remote branch'
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should BeNullOrEmpty
    }

    It 'NewWorktree_ExistingFolderOrLocalBranch_RefusesWithoutPublishing' {
        $featurePath = Join-Path $testRoot 'feat-12345'
        New-Item -ItemType Directory -Path $featurePath | Out-Null
        Assert-ReviewFailure { New-Worktree 12345 -RepositoryPath $repository } 'already exists'
        Remove-Item -LiteralPath $featurePath
        & $script:InvokeReviewGit $repository @('branch', 'feat-12345') | Out-Null
        Assert-ReviewFailure { New-Worktree 12345 -RepositoryPath $repository } 'Local branch'
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'feat-12345')) | Should BeNullOrEmpty
    }

    It 'NewWorktree_InvalidIdOrMissingBase_DoesNotCreateBranch' {
        Assert-ReviewFailure { New-Worktree '../invalid' -RepositoryPath $repository } 'WorkItemId'
        Assert-ReviewFailure { New-Worktree 0 -RepositoryPath $repository } 'WorkItemId'
        Assert-ReviewFailure { New-Worktree 12345 -BaseBranch missing -RepositoryPath $repository } 'failed'
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should BeNullOrEmpty
    }

    It 'RemoveWorktree_CleanBranch_RemovesOnlyLocalWorktreeAndBranch' {
        $result = New-Worktree -UserStoryId 12345 -RepositoryPath $repository
        Remove-Worktree -TaskId 12345 -RepositoryPath $repository -Confirm:$false
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $false
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should BeNullOrEmpty
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'feat-12345')) | Should Not BeNullOrEmpty
    }

    It 'RemoveWorktree_WhatIf_PreservesWorktreeAndBranch' {
        $result = New-Worktree 12345 -RepositoryPath $repository
        Remove-Worktree 12345 -RepositoryPath $repository -WhatIf
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $true
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should Not BeNullOrEmpty
    }

    It 'RemoveWorktree_UncommittedChanges_RefusesWithoutDiscarding' {
        $result = New-Worktree 12345 -RepositoryPath $repository
        $file = Join-Path $result.WorktreePath 'keep.txt'
        Set-Content -LiteralPath $file -Value 'Keep this change'
        Assert-ReviewFailure { Remove-Worktree 12345 -RepositoryPath $repository -Confirm:$false } 'uncommitted changes'
        (Test-Path -LiteralPath $file) | Should Be $true
        & $script:InvokeReviewGit $result.WorktreePath @('add', '--', 'keep.txt') | Out-Null
        Assert-ReviewFailure { Remove-Worktree 12345 -RepositoryPath $repository -Confirm:$false } 'uncommitted changes'
    }

    It 'RemoveWorktree_UnpushedCommit_RefusesUntilPushed' {
        $result = New-Worktree 12345 -RepositoryPath $repository
        & $script:InvokeReviewGit $result.WorktreePath @('commit', '--allow-empty', '-m', 'Feature work') | Out-Null
        Assert-ReviewFailure { Remove-Worktree 12345 -RepositoryPath $repository -Confirm:$false } 'local-only commit'
        & $script:InvokeReviewGit $result.WorktreePath @('push', 'origin', 'HEAD:refs/heads/feat-12345') | Out-Null
        Remove-Worktree 12345 -RepositoryPath $repository -Confirm:$false
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $false
    }

    It 'RemoveWorktree_Force_DiscardsLocalWorkButPreservesRemote' {
        $result = New-Worktree 12345 -RepositoryPath $repository
        & $script:InvokeReviewGit $result.WorktreePath @('commit', '--allow-empty', '-m', 'Disposable work') | Out-Null
        Set-Content -LiteralPath (Join-Path $result.WorktreePath 'discard.txt') -Value 'Disposable'
        Remove-Worktree 12345 -RepositoryPath $repository -Force -Confirm:$false
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $false
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'feat-12345')) | Should Not BeNullOrEmpty
    }

    It 'RemoveWorktree_WrongBranch_RefusesEvenWithForce' {
        $result = New-Worktree 12345 -RepositoryPath $repository
        & $script:InvokeReviewGit $result.WorktreePath @('checkout', '-b', 'unrelated') | Out-Null
        Assert-ReviewFailure { Remove-Worktree 12345 -RepositoryPath $repository -Force -Confirm:$false } 'not the expected feature worktree'
        (Test-Path -LiteralPath $result.WorktreePath) | Should Be $true
    }

    It 'RemoveWorktree_DifferentRepository_RefusesEvenWithForce' {
        $featurePath = Join-Path $testRoot 'feat-12345'
        & $script:InvokeReviewGit $testRoot @('init', '--initial-branch=feat-12345', $featurePath) | Out-Null
        Assert-ReviewFailure { Remove-Worktree 12345 -RepositoryPath $repository -Force -Confirm:$false } 'different repository'
        (Test-Path -LiteralPath $featurePath) | Should Be $true
    }

    It 'RemoveWorktree_LockedWorktree_PreservesBranchWhenRemovalFails' {
        $result = New-Worktree 12345 -RepositoryPath $repository
        & $script:InvokeReviewGit $repository @('worktree', 'lock', '--', $result.WorktreePath) | Out-Null
        Assert-ReviewFailure { Remove-Worktree 12345 -RepositoryPath $repository -Force -Confirm:$false } 'failed'
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'feat-12345')) | Should Not BeNullOrEmpty
    }

    It 'GetReviewTarget_BareRepository_UsesRepositoryFolderAsRoot' {
        $target = & $script:GetReviewTarget $remote 'feature/test'
        $target.RepositoryPath | Should Be ([IO.Path]::GetFullPath($remote))
        $target.WorktreePath | Should Be (Join-Path $remote 'review-feature-test')
    }

    It 'GetReviewTarget_NonBareRepository_UsesWorkingTreeRoot' {
        $target = & $script:GetReviewTarget $repository 'feature/test'
        $target.RepositoryPath | Should Be ([IO.Path]::GetFullPath($repository))
    }

    It 'NewReviewWorktree_RemoteBranch_CreatesTrackingBranchAndSiblingWorktree' {
        $result = New-ReviewWorktree 'feature/test' -RepositoryPath $repository
        $result.WorktreePath | Should Be $reviewPath
        $result.BranchName | Should Be 'review/feature/test'
        (Test-Path -LiteralPath (Join-Path $reviewPath '.git')) | Should Be $true
        (& $script:InvokeReviewGit $reviewPath @('rev-parse', '--abbrev-ref', '@{upstream}')) | Should Be 'origin/feature/test'
        (& $script:InvokeReviewGit $reviewPath @('rev-parse', 'HEAD')) |
        Should Be (& $script:InvokeReviewGit $repository @('rev-parse', 'refs/remotes/origin/feature/test'))
        (& $script:InvokeReviewGit $repository @('branch', '--show-current')) | Should Be 'main'
    }

    It 'NewReviewWorktree_DefaultRepositoryPath_UsesCurrentFolder' {
        Push-Location $repository
        try {
            $result = New-ReviewWorktree 'feature/test'
            $result.RepositoryPath | Should Be ([IO.Path]::GetFullPath($repository))
        }
        finally {
            Pop-Location
        }
    }

    It 'RemoveReviewWorktree_CleanUnmergedPR_RemovesOnlyReviewBranchAndWorktree' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        (Test-Path -LiteralPath $reviewPath) | Should Be $false
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/feature/test')) | Should BeNullOrEmpty
        (& $script:InvokeReviewGit $repository @('ls-remote', '--heads', 'origin', 'feature/test')) | Should Not BeNullOrEmpty
    }

    It 'NewReviewWorktree_WhatIf_DoesNotCreateBranchOrFolder' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository -WhatIf
        (Test-Path -LiteralPath $reviewPath) | Should Be $false
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/feature/test')) | Should BeNullOrEmpty
    }

    It 'RemoveReviewWorktree_WhatIf_PreservesBranchAndFolder' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -WhatIf
        (Test-Path -LiteralPath $reviewPath) | Should Be $true
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/feature/test')) | Should Not BeNullOrEmpty
    }

    It 'NewReviewWorktree_ExistingFolder_RefusesWithoutCreatingBranch' {
        New-Item -ItemType Directory -Path $reviewPath | Out-Null
        Assert-ReviewFailure { New-ReviewWorktree 'feature/test' -RepositoryPath $repository } 'already exists'
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/feature/test')) | Should BeNullOrEmpty
    }

    It 'NewReviewWorktree_ExistingReviewBranch_RefusesWithoutOverwriting' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        Assert-ReviewFailure { New-ReviewWorktree 'feature/test' -RepositoryPath $repository } 'already exists'
        (Test-Path -LiteralPath $reviewPath) | Should Be $true
    }

    It 'NewReviewWorktree_MissingRemoteBranch_ThrowsWithoutCreatingBranch' {
        Assert-ReviewFailure { New-ReviewWorktree 'missing' -RepositoryPath $repository } 'failed'
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/missing')) | Should BeNullOrEmpty
    }

    It 'NewReviewWorktree_InvalidBranch_ThrowsWithoutCreatingFolder' {
        Assert-ReviewFailure { New-ReviewWorktree '../invalid' -RepositoryPath $repository } 'check-ref-format'
        (Test-Path -LiteralPath (Join-Path $testRoot 'review-..-invalid')) | Should Be $false
    }

    It 'RemoveReviewWorktree_UntrackedChanges_RefusesUntilChangesAreDiscarded' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        $newFile = Join-Path $reviewPath 'review.txt'
        Set-Content -LiteralPath $newFile -Value 'Keep this review change'
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        } 'uncommitted changes'
        (Test-Path -LiteralPath $newFile) | Should Be $true
        Remove-Item -LiteralPath $newFile
        Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        (Test-Path -LiteralPath $reviewPath) | Should Be $false
    }

    It 'RemoveReviewWorktree_LocalCommit_RefusesUntilCommitIsPushedAndFetched' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        & $script:InvokeReviewGit $reviewPath @('commit', '--allow-empty', '-m', 'Review fix') | Out-Null
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        } 'local-only commit'
        & $script:InvokeReviewGit $reviewPath @('push', 'origin', 'HEAD:refs/heads/feature/test') | Out-Null
        & $script:InvokeReviewGit $repository @('fetch', 'origin') | Out-Null
        Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        (Test-Path -LiteralPath $reviewPath) | Should Be $false
    }

    It 'RemoveReviewWorktree_Force_DiscardsFilesAndLocalCommits' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        & $script:InvokeReviewGit $reviewPath @('commit', '--allow-empty', '-m', 'Disposable review fix') | Out-Null
        Set-Content -LiteralPath (Join-Path $reviewPath 'review.txt') -Value 'Disposable change'
        Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Force -Confirm:$false
        (Test-Path -LiteralPath $reviewPath) | Should Be $false
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/feature/test')) | Should BeNullOrEmpty
    }

    It 'RemoveReviewWorktree_WrongBranch_RefusesEvenWithForce' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        & $script:InvokeReviewGit $reviewPath @('checkout', '-b', 'unrelated') | Out-Null
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Force -Confirm:$false
        } 'not the expected review worktree'
        (Test-Path -LiteralPath $reviewPath) | Should Be $true
    }

    It 'RemoveReviewWorktree_LockedWorktree_PreservesBranchWhenRemovalFails' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        & $script:InvokeReviewGit $repository @('worktree', 'lock', '--', $reviewPath) | Out-Null
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Force -Confirm:$false
        } 'failed'
        (Test-Path -LiteralPath $reviewPath) | Should Be $true
        (& $script:InvokeReviewGit $repository @('branch', '--list', 'review/feature/test')) | Should Not BeNullOrEmpty
    }

    It 'NewReviewWorktree_RemoteHasAdvanced_FetchesLatestCommit' {
        & $script:InvokeReviewGit $repository @('checkout', 'feature/test') | Out-Null
        & $script:InvokeReviewGit $repository @('commit', '--allow-empty', '-m', 'New PR commit') | Out-Null
        & $script:InvokeReviewGit $repository @('push', 'origin', 'feature/test') | Out-Null
        $latest = & $script:InvokeReviewGit $repository @('rev-parse', 'HEAD')
        & $script:InvokeReviewGit $repository @('update-ref', 'refs/remotes/origin/feature/test', 'HEAD~1') | Out-Null
        & $script:InvokeReviewGit $repository @('checkout', 'main') | Out-Null
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        (& $script:InvokeReviewGit $reviewPath @('rev-parse', 'HEAD')) | Should Be $latest
    }

    It 'RemoveReviewWorktree_StagedAndTrackedChanges_RefusesWithoutDiscarding' {
        New-ReviewWorktree 'feature/test' -RepositoryPath $repository | Out-Null
        $file = Join-Path $reviewPath 'tracked.txt'
        Set-Content -LiteralPath $file -Value 'Original'
        & $script:InvokeReviewGit $reviewPath @('add', '--', 'tracked.txt') | Out-Null
        & $script:InvokeReviewGit $reviewPath @('commit', '-m', 'Add tracked file') | Out-Null
        Set-Content -LiteralPath $file -Value 'Modified'
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        } 'uncommitted changes'
        & $script:InvokeReviewGit $reviewPath @('add', '--', 'tracked.txt') | Out-Null
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Confirm:$false
        } 'uncommitted changes'
        (Get-Content -LiteralPath $file) | Should Be 'Modified'
    }

    It 'RemoveReviewWorktree_DifferentRepository_RefusesEvenWithForce' {
        & $script:InvokeReviewGit $testRoot @('init', '--initial-branch=main', $reviewPath) | Out-Null
        & $script:InvokeReviewGit $reviewPath @('symbolic-ref', 'HEAD', 'refs/heads/review/feature/test') | Out-Null
        Assert-ReviewFailure {
            Remove-ReviewWorktree 'feature/test' -RepositoryPath $repository -Force -Confirm:$false
        } 'different repository'
        (Test-Path -LiteralPath $reviewPath) | Should Be $true
    }
}
