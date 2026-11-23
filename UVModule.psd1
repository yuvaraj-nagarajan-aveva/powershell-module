@{
    RootModule           = 'UVModule.psm1'
    ModuleVersion        = '0.2.0'
    GUID                 = 'bd6a4799-e9b1-4f4b-8faa-113c376d07e1'
    Author               = 'Yuvaraj Nagarajan'
    Description          = 'Personal PowerShell utilities, including Git worktree commands and GitHub pull request attention commands.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'New-Worktree'
        'Remove-Worktree'
        'New-BugWorktree'
        'Remove-BugWorktree'
        'New-ReviewWorktree'
        'Remove-ReviewWorktree'
        'Get-PullRequestWithUnresolvedThread'
        'Get-ApprovedPullRequestNotMerged'
        'Get-PullRequestNeedingAttention'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
