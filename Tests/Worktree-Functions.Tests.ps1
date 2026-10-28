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
