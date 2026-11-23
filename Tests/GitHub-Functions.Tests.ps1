. "$PSScriptRoot\..\Functions\Worktree-Functions.ps1"
. "$PSScriptRoot\..\Functions\GitHub-Functions.ps1"

function Assert-GitHubFailure {
    param ([scriptblock] $Action, [string] $ExpectedMessage)

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

function Invoke-FakeGitHubCli {
    $script:CapturedGitHubCliArguments = @($args)
    $global:LASTEXITCODE = $script:FakeGitHubCliExitCode
    $script:FakeGitHubCliOutput
}

Describe 'GitHub remote parsing' {
    It 'GetGitHubRemoteInfo_SupportedRemoteFormats_ReturnHostnameOwnerAndName' {
        $cases = @(
            @{ Url = 'https://github.com/contoso/web-app.git'; Hostname = 'github.com' }
            @{ Url = 'https://github.com/contoso/web-app'; Hostname = 'github.com' }
            @{ Url = 'https://token@github.com/contoso/web-app.git'; Hostname = 'github.com' }
            @{ Url = 'git@github.com:contoso/web-app.git'; Hostname = 'github.com' }
            @{ Url = 'ssh://git@github.com/contoso/web-app.git'; Hostname = 'github.com' }
            @{ Url = 'https://github.contoso.com/contoso/web-app.git'; Hostname = 'github.contoso.com' }
            @{ Url = 'ssh://git@github.contoso.com:2222/contoso/web-app'; Hostname = 'github.contoso.com' }
        )
        foreach ($case in $cases) {
            $info = & $script:GetGitHubRemoteInfo $case.Url
            $info.Hostname | Should Be $case.Hostname
            $info.Owner | Should Be 'contoso'
            $info.Name | Should Be 'web-app'
        }
    }

    It 'GetGitHubRemoteInfo_AzureDevOpsOrLocalRemote_ReturnsNull' {
        (& $script:GetGitHubRemoteInfo 'https://dev.azure.com/contoso/Web/_git/web-app') | Should BeNullOrEmpty
        (& $script:GetGitHubRemoteInfo 'git@ssh.dev.azure.com:v3/contoso/Web/web-app') | Should BeNullOrEmpty
        (& $script:GetGitHubRemoteInfo 'C:\remotes\origin.git') | Should BeNullOrEmpty
    }
}

Describe 'GitHub repository resolution' {
    BeforeEach {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("github-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    }

    AfterEach {
        if ($testRoot -and (Test-Path -LiteralPath $testRoot)) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }

    It 'GetGitHubRepository_OriginIsGitHub_InfersRepository' {
        & $script:InvokeReviewGit $testRoot @('init') | Out-Null
        & $script:InvokeReviewGit $testRoot @('remote', 'add', 'origin', 'git@github.contoso.com:contoso/web-app.git') | Out-Null
        $repository = & $script:GetGitHubRepository '' $testRoot
        $repository.Hostname | Should Be 'github.contoso.com'
        $repository.Owner | Should Be 'contoso'
        $repository.Name | Should Be 'web-app'
    }

    It 'GetGitHubRepository_RepositorySupplied_OverridesOriginAndUsesGitHubDotCom' {
        & $script:InvokeReviewGit $testRoot @('init') | Out-Null
        & $script:InvokeReviewGit $testRoot @('remote', 'add', 'origin', 'https://github.com/contoso/web-app.git') | Out-Null
        $repository = & $script:GetGitHubRepository 'fabrikam/api' $testRoot
        $repository.Hostname | Should Be 'github.com'
        $repository.Owner | Should Be 'fabrikam'
        $repository.Name | Should Be 'api'
    }

    It 'GetGitHubRepository_NotAGitRepository_Throws' {
        Assert-GitHubFailure { & $script:GetGitHubRepository '' $testRoot } 'GitHub repository was not supplied and could not be inferred'
    }

    It 'GetGitHubRepository_NonGitHubOrigin_Throws' {
        & $script:InvokeReviewGit $testRoot @('init') | Out-Null
        & $script:InvokeReviewGit $testRoot @('remote', 'add', 'origin', 'https://dev.azure.com/contoso/Web/_git/web-app') | Out-Null
        Assert-GitHubFailure { & $script:GetGitHubRepository '' $testRoot } 'Use -Repository owner/name'
    }
}

Describe 'GitHub GraphQL invocation' {
    BeforeEach {
        $savedCliCommand = $script:GitHubCliCommand
        $script:GitHubCliCommand = 'Invoke-FakeGitHubCli'
        $script:FakeGitHubCliExitCode = 0
        $script:FakeGitHubCliOutput = '{"data":{"viewer":{"login":"me"}}}'
        $script:CapturedGitHubCliArguments = @()
    }

    AfterEach {
        $script:GitHubCliCommand = $savedCliCommand
        $global:LASTEXITCODE = 0
    }

    It 'InvokeGitHubGraphQL_StringIntegerAndNullVariables_BuildsReadOnlyGraphQLArguments' {
        $data = & $script:InvokeGitHubGraphQL 'query { viewer { login } }' @{ owner = 'contoso'; number = 7; cursor = $null } 'github.com'
        $data.viewer.login | Should Be 'me'
        $arguments = $script:CapturedGitHubCliArguments
        ($arguments[0..1] -join ' ') | Should Be 'api graphql'
        ($arguments -join ' ') | Should Match '-f query=query \{ viewer \{ login \} \}'
        ($arguments -join ' ') | Should Match '-f owner=contoso'
        ($arguments -join ' ') | Should Match '-F number=7'
        ($arguments -join ' ') | Should Not Match 'cursor='
        ($arguments -join ' ') | Should Not Match '--hostname'
        ($arguments -join ' ') | Should Not Match '(?i)mutation|--method|-X'
    }

    It 'InvokeGitHubGraphQL_EnterpriseHostname_PassesHostname' {
        & $script:InvokeGitHubGraphQL 'query { viewer { login } }' @{} 'github.contoso.com' | Out-Null
        ($script:CapturedGitHubCliArguments -join ' ') | Should Match '--hostname github\.contoso\.com'
    }

    It 'InvokeGitHubGraphQL_CliFails_ThrowsWithCliOutput' {
        $script:FakeGitHubCliExitCode = 1
        $script:FakeGitHubCliOutput = 'To get started with GitHub CLI, please run:  gh auth login'
        Assert-GitHubFailure { & $script:InvokeGitHubGraphQL 'query { viewer { login } }' @{} 'github.com' } 'GitHub GraphQL request failed: To get started with GitHub CLI'
    }

    It 'InvokeGitHubGraphQL_GraphQLErrors_ThrowsWithMessages' {
        $script:FakeGitHubCliOutput = '{"data":null,"errors":[{"message":"Could not resolve to a Repository"}]}'
        Assert-GitHubFailure { & $script:InvokeGitHubGraphQL 'query { viewer { login } }' @{} 'github.com' } 'GitHub GraphQL request failed: Could not resolve to a Repository'
    }

    It 'InvokeGitHubGraphQL_CliMissing_ThrowsInstallGuidance' {
        $script:GitHubCliCommand = 'gh-command-that-does-not-exist-' + [Guid]::NewGuid().ToString('N')
        Assert-GitHubFailure { & $script:InvokeGitHubGraphQL 'query { viewer { login } }' @{} 'github.com' } 'gh auth login'
    }
}

Describe 'GitHub pull request paging' {
    BeforeEach {
        $savedInvoke = $script:InvokeGitHubGraphQL
        $script:CapturedVariables = [Collections.Generic.List[hashtable]]::new()
        $repository = [PSCustomObject]@{ Hostname = 'github.com'; Owner = 'contoso'; Name = 'web-app' }
    }

    AfterEach {
        $script:InvokeGitHubGraphQL = $savedInvoke
    }

    It 'GetMyOpenPullRequests_TwoPages_ReturnsAllOpenPullRequestsAuthoredByMe' {
        $script:InvokeGitHubGraphQL = {
            param ([string] $Query, [hashtable] $Variables, [string] $Hostname)

            $script:CapturedVariables.Add($Variables)
            if (-not $Variables.cursor) {
                return [PSCustomObject]@{ search = [PSCustomObject]@{
                        pageInfo = [PSCustomObject]@{ hasNextPage = $true; endCursor = 'page-2' }
                        nodes    = @([PSCustomObject]@{ number = 1 }, [PSCustomObject]@{ number = 2 })
                    } }
            }
            [PSCustomObject]@{ search = [PSCustomObject]@{
                    pageInfo = [PSCustomObject]@{ hasNextPage = $false; endCursor = $null }
                    nodes    = @([PSCustomObject]@{ number = 3 })
                } }
        }
        $pullRequests = @(& $script:GetMyOpenPullRequests $repository)
        ($pullRequests.number -join ',') | Should Be '1,2,3'
        $script:CapturedVariables.Count | Should Be 2
        $script:CapturedVariables[0].searchQuery | Should Be 'repo:contoso/web-app is:pr is:open author:@me'
        $script:CapturedVariables[1].cursor | Should Be 'page-2'
    }

    It 'GetAllReviewThreads_MoreThanOnePage_ReturnsThreadsFromEveryPage' {
        $script:InvokeGitHubGraphQL = {
            param ([string] $Query, [hashtable] $Variables, [string] $Hostname)

            $script:CapturedVariables.Add($Variables)
            [PSCustomObject]@{ repository = [PSCustomObject]@{ pullRequest = [PSCustomObject]@{ reviewThreads = [PSCustomObject]@{
                            pageInfo = [PSCustomObject]@{ hasNextPage = $false; endCursor = $null }
                            nodes    = @([PSCustomObject]@{ isResolved = $false })
                        } } } }
        }
        $pullRequest = [PSCustomObject]@{
            number        = 9
            reviewThreads = [PSCustomObject]@{
                pageInfo = [PSCustomObject]@{ hasNextPage = $true; endCursor = 'threads-2' }
                nodes    = @([PSCustomObject]@{ isResolved = $true })
            }
        }
        $threads = @(& $script:GetAllReviewThreads $repository $pullRequest)
        $threads.Count | Should Be 2
        $script:CapturedVariables[0].owner | Should Be 'contoso'
        $script:CapturedVariables[0].name | Should Be 'web-app'
        $script:CapturedVariables[0].number | Should Be 9
        $script:CapturedVariables[0].cursor | Should Be 'threads-2'
    }
}
