$script:GitHubCliCommand = 'gh'
$script:DefaultGitHubHostname = 'github.com'

$script:MyOpenPullRequestsQuery = @'
query ($searchQuery: String!, $cursor: String) {
  search(query: $searchQuery, type: ISSUE, first: 50, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number
        title
        url
        isDraft
        headRefName
        baseRefName
        reviewDecision
        repository { nameWithOwner }
        latestOpinionatedReviews(first: 100) { nodes { state author { login } } }
        reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { isResolved } }
      }
    }
  }
}
'@

$script:ReviewThreadsPageQuery = @'
query ($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { isResolved } }
    }
  }
}
'@

$script:GetGitHubRemoteInfo = {
    param ([string] $RemoteUrl)

    $remotePatterns = @(
        '^https?://(?:[^@/]+@)?(?<Hostname>[^/:@]+)(?::\d+)?/(?<Owner>[^/]+)/(?<Name>[^/]+?)(?:\.git)?/?$'
        '^ssh://(?:[^@/]+@)?(?<Hostname>[^/:@]+)(?::\d+)?/(?<Owner>[^/]+)/(?<Name>[^/]+?)(?:\.git)?/?$'
        '^[^@/:]+@(?<Hostname>[^/:@]+):(?<Owner>[^/]+)/(?<Name>[^/]+?)(?:\.git)?/?$'
    )
    foreach ($remotePattern in $remotePatterns) {
        $match = [regex]::Match($RemoteUrl, $remotePattern)
        if ($match.Success) {
            return [PSCustomObject]@{
                Hostname = $match.Groups['Hostname'].Value
                Owner    = $match.Groups['Owner'].Value
                Name     = $match.Groups['Name'].Value
            }
        }
    }
}

$script:GetGitHubRepository = {
    param ([string] $Repository, [string] $RepositoryPath)

    if ($Repository) {
        $owner, $name = $Repository -split '/', 2
        return [PSCustomObject]@{ Hostname = $script:DefaultGitHubHostname; Owner = $owner; Name = $name }
    }

    $remoteInfo = $null
    try {
        $originUrl = [string] (& $script:InvokeReviewGit $RepositoryPath @('remote', 'get-url', 'origin'))
        $remoteInfo = & $script:GetGitHubRemoteInfo $originUrl
    }
    catch {
        $remoteInfo = $null
    }
    if (-not $remoteInfo) {
        throw "GitHub repository was not supplied and could not be inferred from the origin remote of '$RepositoryPath'. Use -Repository owner/name."
    }
    $remoteInfo
}

$script:InvokeGitHubGraphQL = {
    param ([string] $Query, [hashtable] $Variables, [string] $Hostname)

    if (-not (Get-Command $script:GitHubCliCommand -ErrorAction SilentlyContinue)) {
        throw "The GitHub CLI ($script:GitHubCliCommand) was not found. Install it from https://cli.github.com and run 'gh auth login'."
    }

    $arguments = @('api', 'graphql', '-f', "query=$Query")
    foreach ($variableName in ($Variables.Keys | Sort-Object)) {
        $value = $Variables[$variableName]
        if ($null -eq $value) {
            continue
        }
        $flag = if ($value -is [int]) { '-F' } else { '-f' }
        $arguments += @($flag, "$variableName=$value")
    }
    if ($Hostname -and $Hostname -ne $script:DefaultGitHubHostname) {
        $arguments += @('--hostname', $Hostname)
    }

    $output = & $script:GitHubCliCommand @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub GraphQL request failed: $($output -join [Environment]::NewLine)"
    }
    $json = ($output | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join [Environment]::NewLine
    $response = $json | ConvertFrom-Json
    if ($response.errors) {
        throw "GitHub GraphQL request failed: $(($response.errors | ForEach-Object { $_.message }) -join '; ')"
    }
    $response.data
}

$script:GetMyOpenPullRequests = {
    param ($Repository)

    $variables = @{
        searchQuery = "repo:$($Repository.Owner)/$($Repository.Name) is:pr is:open author:@me"
        cursor      = $null
    }
    do {
        $search = (& $script:InvokeGitHubGraphQL $script:MyOpenPullRequestsQuery $variables.Clone() $Repository.Hostname).search
        $search.nodes | Where-Object { $_ -and $_.number }
        $variables.cursor = $search.pageInfo.endCursor
    } while ($search.pageInfo.hasNextPage)
}

$script:GetAllReviewThreads = {
    param ($Repository, $PullRequest)

    $PullRequest.reviewThreads.nodes | Where-Object { $_ }
    $pageInfo = $PullRequest.reviewThreads.pageInfo
    while ($pageInfo.hasNextPage) {
        $variables = @{
            owner  = $Repository.Owner
            name   = $Repository.Name
            number = [int] $PullRequest.number
            cursor = $pageInfo.endCursor
        }
        $reviewThreads = (& $script:InvokeGitHubGraphQL $script:ReviewThreadsPageQuery $variables $Repository.Hostname).repository.pullRequest.reviewThreads
        $reviewThreads.nodes | Where-Object { $_ }
        $pageInfo = $reviewThreads.pageInfo
    }
}
