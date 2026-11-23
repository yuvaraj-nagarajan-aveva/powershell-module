# Quickstart

```powershell
Import-Module .\UVModule.psd1 -Force
gh auth login
Set-Location C:\src\my-github-repo
Get-PullRequestNeedingAttention | Format-Table Number, Title, Reasons, Url
Get-PullRequestWithUnresolvedThread -ExcludeDraft
Get-ApprovedPullRequestNotMerged -Repository contoso/web-app
```

Verify: `Invoke-Pester .\Tests` passes, and `Test-ModuleManifest .\UVModule.psd1` lists the three commands.
