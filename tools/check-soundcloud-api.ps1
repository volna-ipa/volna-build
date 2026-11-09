<#
.SYNOPSIS
    Checks that the SoundCloud public API is reachable and that the supplied
    credentials can search tracks, find related artists and resolve streams.

.DESCRIPTION
    The script never prints or writes the client secret or OAuth tokens.
    It reads credentials from parameters, environment variables, or
    Config/Secrets.xcconfig (in that order).

    Without credentials it still checks the public documentation, confirms
    whether anonymous API access is allowed, and verifies the official oEmbed
    endpoint used by the Web-embed fallback.

.EXAMPLE
    pwsh -File tools/check-soundcloud-api.ps1

.EXAMPLE
    $env:SOUNDCLOUD_CLIENT_ID = '...'
    $env:SOUNDCLOUD_CLIENT_SECRET = '...'
    pwsh -File tools/check-soundcloud-api.ps1 -OutFile api-report.json
#>
[CmdletBinding()]
param(
    [string]$ClientId = $env:SOUNDCLOUD_CLIENT_ID,
    [string]$ClientSecret = $env:SOUNDCLOUD_CLIENT_SECRET,
    [string]$ConfigPath = '',
    [string]$OutFile = '',
    [string]$ProbeTrackUrl = 'https://soundcloud.com/seredok/kishlak-apnoe-speed-up'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir '..\Config\Secrets.xcconfig' }
if (-not $OutFile) { $OutFile = Join-Path $scriptDir '..\docs\soundcloud-api-report.json' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
$script:results = New-Object 'System.Collections.Generic.List[object]'
$apiBase = 'https://api.soundcloud.com'
$authBase = 'https://secure.soundcloud.com'
$accept = 'application/json; charset=utf-8'
$userAgent = 'VolnaApiCheck/1.0 (personal iOS SwiftUI app)'

function Read-XcconfigValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*?)\s*$") {
            $value = $Matches[1].Trim().Trim('"').Trim("'")
            if ($value -and $value -notmatch '^\$') { return $value }
        }
    }
    return $null
}

if (-not $ClientId) { $ClientId = Read-XcconfigValue -Path $ConfigPath -Key 'SOUNDCLOUD_CLIENT_ID' }
if (-not $ClientSecret) { $ClientSecret = Read-XcconfigValue -Path $ConfigPath -Key 'SOUNDCLOUD_CLIENT_SECRET' }

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail,
        [int]$HttpStatus = 0,
        [long]$Milliseconds = 0
    )
    $script:results.Add([pscustomobject]@{
        name         = $Name
        status       = $Status
        httpStatus   = $HttpStatus
        milliseconds = $Milliseconds
        detail       = $Detail
    })
    $color = switch ($Status) {
        'ok'      { 'Green' }
        'warning' { 'Yellow' }
        'failed'  { 'Red' }
        default   { 'Gray' }
    }
    $code = if ($HttpStatus -gt 0) { " [$HttpStatus]" } else { '' }
    Write-Host ("{0,-38} {1,-8}{2} {3} ms  {4}" -f $Name, $Status.ToUpperInvariant(), $code, $Milliseconds, $Detail) -ForegroundColor $color
}

function Invoke-Probe {
    param(
        [string]$Name,
        [string]$Method = 'GET',
        [string]$Url,
        [hashtable]$Headers = @{},
        [string]$RawBody = $null,
        [string]$ContentType = 'application/x-www-form-urlencoded'
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(25)
    $request = New-Object System.Net.Http.HttpRequestMessage -ArgumentList ([System.Net.Http.HttpMethod]::new($Method)), $Url

    foreach ($key in $Headers.Keys) {
        [void]$request.Headers.TryAddWithoutValidation($key, [string]$Headers[$key])
    }
    [void]$request.Headers.TryAddWithoutValidation('Accept', $accept)
    [void]$request.Headers.TryAddWithoutValidation('User-Agent', $userAgent)
    if ($RawBody) {
        $request.Content = New-Object System.Net.Http.StringContent -ArgumentList $RawBody, ([Text.Encoding]::UTF8), $ContentType
    }

    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $watch.Stop()
        $statusCode = [int]$response.StatusCode
        $json = $null
        if ($text) {
            try { $json = $text | ConvertFrom-Json } catch { }
        }
        $responseHeaders = @{}
        foreach ($header in $response.Headers) {
            $responseHeaders[$header.Key] = ($header.Value -join ', ')
        }
        return [pscustomobject]@{
            StatusCode   = $statusCode
            Json         = $json
            Text         = $text
            Milliseconds = $watch.ElapsedMilliseconds
            Error        = $null
            Headers      = $responseHeaders
        }
    }
    catch {
        $watch.Stop()
        return [pscustomobject]@{
            StatusCode   = 0
            Json         = $null
            Text         = $_.Exception.Message
            Milliseconds = $watch.ElapsedMilliseconds
            Error        = $_.Exception.Message
            Headers      = @{}
        }
    }
    finally {
        if ($request) { $request.Dispose() }
        if ($client) { $client.Dispose() }
    }
}

function Format-ApiError {
    param($Response)
    if ($Response.Json -and $Response.Json.message) { return [string]$Response.Json.message }
    if ($Response.Text) {
        $clean = ($Response.Text -replace '\s+', ' ').Trim()
        if ($clean.Length -gt 180) { return $clean.Substring(0, 180) + '...' }
        return $clean
    }
    return 'no response body'
}

function Get-RateLimitDetail {
    param($Headers)
    try {
        $limit = $Headers['X-Ratelimit-Limit']
        $remaining = $Headers['X-Ratelimit-Remaining']
        if ($limit) { return "rate-limit=$limit remaining=$remaining" }
    } catch { }
    return ''
}

Write-Host ''
Write-Host 'SoundCloud API availability check' -ForegroundColor Cyan
Write-Host "API base:  $apiBase" -ForegroundColor DarkGray
Write-Host "Auth base: $authBase" -ForegroundColor DarkGray
Write-Host ''

# 1. Public documentation / OpenAPI.
$openApi = Invoke-Probe -Name 'openapi' -Url 'https://developers.soundcloud.com/docs/api/explorer/api.json'
if ($openApi.StatusCode -eq 200 -and $openApi.Json -and $openApi.Json.openapi) {
    Add-Result -Name 'OpenAPI specification' -Status 'ok' -HttpStatus 200 -Milliseconds $openApi.Milliseconds -Detail "$($openApi.Json.info.title) $($openApi.Json.info.version)"
} else {
    Add-Result -Name 'OpenAPI specification' -Status 'failed' -HttpStatus $openApi.StatusCode -Milliseconds $openApi.Milliseconds -Detail (Format-ApiError $openApi)
}

# 2. Anonymous API access. The current API is expected to reject this with 401.
$anonymous = Invoke-Probe -Name 'anonymous-search' -Url "$apiBase/tracks?q=kishlak&access=playable&limit=1&linked_partitioning=true"
if ($anonymous.StatusCode -eq 401 -or $anonymous.StatusCode -eq 403) {
    Add-Result -Name 'Anonymous API search' -Status 'ok' -HttpStatus $anonymous.StatusCode -Milliseconds $anonymous.Milliseconds -Detail 'rejected as expected; OAuth token is required'
} elseif ($anonymous.StatusCode -eq 200) {
    Add-Result -Name 'Anonymous API search' -Status 'warning' -HttpStatus 200 -Milliseconds $anonymous.Milliseconds -Detail 'API answered without OAuth; do not rely on keyless access'
} else {
    Add-Result -Name 'Anonymous API search' -Status 'warning' -HttpStatus $anonymous.StatusCode -Milliseconds $anonymous.Milliseconds -Detail (Format-ApiError $anonymous)
}

# 3. Official oEmbed endpoint (no API key) used by the Web-embed plan B.
$probeUrl = [uri]::EscapeDataString($ProbeTrackUrl)
$oembed = Invoke-Probe -Name 'oembed' -Url "https://soundcloud.com/oembed?format=json&url=$probeUrl"
if ($oembed.StatusCode -eq 200 -and $oembed.Json -and $oembed.Json.html) {
    Add-Result -Name 'oEmbed (Web-embed fallback)' -Status 'ok' -HttpStatus 200 -Milliseconds $oembed.Milliseconds -Detail 'official iframe HTML returned without API credentials'
} else {
    Add-Result -Name 'oEmbed (Web-embed fallback)' -Status 'warning' -HttpStatus $oembed.StatusCode -Milliseconds $oembed.Milliseconds -Detail ('soundcloud.com/oembed unavailable from this network; widget host may still work: ' + (Format-ApiError $oembed))
}

# 3b. Widget host is separate from soundcloud.com and can remain reachable when the site is blocked.
$widget = Invoke-Probe -Name 'widget-script' -Url 'https://w.soundcloud.com/player/api.js'
if ($widget.StatusCode -eq 200) {
    Add-Result -Name 'Widget host (Web-embed fallback)' -Status 'ok' -HttpStatus 200 -Milliseconds $widget.Milliseconds -Detail 'official SoundCloud Widget API script is reachable'
} else {
    Add-Result -Name 'Widget host (Web-embed fallback)' -Status 'failed' -HttpStatus $widget.StatusCode -Milliseconds $widget.Milliseconds -Detail (Format-ApiError $widget)
}

$hasCredentials = [bool]$ClientId -and [bool]$ClientSecret
if (-not $hasCredentials) {
    Add-Result -Name 'OAuth client credentials' -Status 'warning' -Detail 'not configured; set SOUNDCLOUD_CLIENT_ID / SOUNDCLOUD_CLIENT_SECRET or edit Config/Secrets.xcconfig'
    Write-Host ''
    Write-Host 'No API credentials supplied.' -ForegroundColor Yellow
    Write-Host 'SoundCloud now requires an Artist Pro subscription to create credentials:' -ForegroundColor Yellow
    Write-Host '  https://developers.soundcloud.com/docs/api/register-app' -ForegroundColor DarkGray
    Write-Host 'The Web-embed fallback is reachable. See docs/SOUNDCLOUD_API_CHECK.md.' -ForegroundColor Yellow
} else {
    # 4. OAuth 2.1 client_credentials (confidential client; secret required).
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${ClientId}:${ClientSecret}"))
    $tokenResponse = Invoke-Probe -Name 'oauth-token' -Method 'POST' -Url "$authBase/oauth/token" `
        -Headers @{ Authorization = "Basic $basic" } `
        -RawBody 'grant_type=client_credentials'

    if ($tokenResponse.StatusCode -eq 200 -and $tokenResponse.Json -and $tokenResponse.Json.access_token) {
        $token = [string]$tokenResponse.Json.access_token
        $expires = $tokenResponse.Json.expires_in
        Add-Result -Name 'OAuth client credentials' -Status 'ok' -HttpStatus 200 -Milliseconds $tokenResponse.Milliseconds -Detail "token acquired; expires_in=${expires}s"
        $authHeaders = @{ Authorization = "OAuth $token" }

        # 5. Track search.
        $search = Invoke-Probe -Name 'track-search' -Url "$apiBase/tracks?q=kishlak&access=playable&limit=5&linked_partitioning=true" -Headers $authHeaders
        $tracks = @()
        if ($search.StatusCode -eq 200 -and $search.Json) {
            $tracks = @($search.Json.collection)
            $ccCount = @($tracks | Where-Object { $_.license -and $_.license -notmatch 'all-rights-reserved|all rights reserved' }).Count
            $rate = Get-RateLimitDetail $search.Headers
            Add-Result -Name 'Track search' -Status 'ok' -HttpStatus 200 -Milliseconds $search.Milliseconds -Detail "$($tracks.Count) tracks; $ccCount with CC/other license $rate"
        } else {
            Add-Result -Name 'Track search' -Status 'failed' -HttpStatus $search.StatusCode -Milliseconds $search.Milliseconds -Detail (Format-ApiError $search)
        }

        # 6. Artist search and related artists.
        $userSearch = Invoke-Probe -Name 'artist-search' -Url "$apiBase/users?q=kishlak&limit=5&linked_partitioning=true" -Headers $authHeaders
        $users = @()
        if ($userSearch.StatusCode -eq 200 -and $userSearch.Json) {
            $users = @($userSearch.Json.collection)
            Add-Result -Name 'Artist search' -Status 'ok' -HttpStatus 200 -Milliseconds $userSearch.Milliseconds -Detail "$($users.Count) artists returned"
        } else {
            Add-Result -Name 'Artist search' -Status 'failed' -HttpStatus $userSearch.StatusCode -Milliseconds $userSearch.Milliseconds -Detail (Format-ApiError $userSearch)
        }

        if ($users.Count -gt 0) {
            $artist = $users[0]
            $artistId = if ($artist.urn) { ([string]$artist.urn -split ':')[-1] } else { [string]$artist.id }
            $relatedUsers = Invoke-Probe -Name 'related-artists' -Url "$apiBase/users/$artistId/related?limit=5&linked_partitioning=true" -Headers $authHeaders
            if ($relatedUsers.StatusCode -eq 200 -and $relatedUsers.Json) {
                Add-Result -Name 'Related artists' -Status 'ok' -HttpStatus 200 -Milliseconds $relatedUsers.Milliseconds -Detail "$(@($relatedUsers.Json.collection).Count) related artists for '$($artist.username)'"
            } else {
                Add-Result -Name 'Related artists' -Status 'failed' -HttpStatus $relatedUsers.StatusCode -Milliseconds $relatedUsers.Milliseconds -Detail (Format-ApiError $relatedUsers)
            }
        }

        # 7. Related tracks and stream resolution for the first playable result.
        $first = $tracks | Where-Object { $_.access -eq 'playable' } | Select-Object -First 1
        if (-not $first -and $tracks.Count -gt 0) { $first = $tracks[0] }
        if ($first) {
            $trackId = if ($first.urn) { ([string]$first.urn -split ':')[-1] } else { [string]$first.id }
            $relatedTracks = Invoke-Probe -Name 'related-tracks' -Url "$apiBase/tracks/$trackId/related?access=playable&limit=5&linked_partitioning=true" -Headers $authHeaders
            if ($relatedTracks.StatusCode -eq 200 -and $relatedTracks.Json) {
                Add-Result -Name 'Related tracks' -Status 'ok' -HttpStatus 200 -Milliseconds $relatedTracks.Milliseconds -Detail "$(@($relatedTracks.Json.collection).Count) related tracks for '$($first.title)'"
            } else {
                Add-Result -Name 'Related tracks' -Status 'failed' -HttpStatus $relatedTracks.StatusCode -Milliseconds $relatedTracks.Milliseconds -Detail (Format-ApiError $relatedTracks)
            }

            if ($first.access -eq 'playable') {
                $streams = Invoke-Probe -Name 'streams' -Url "$apiBase/tracks/$trackId/streams" -Headers $authHeaders
                if ($streams.StatusCode -eq 200 -and $streams.Json -and $streams.Json.hls_aac_160_url) {
                    Add-Result -Name 'Stream descriptor' -Status 'ok' -HttpStatus 200 -Milliseconds $streams.Milliseconds -Detail 'HLS AAC descriptor available (playback needs Authorization header)'
                } else {
                    Add-Result -Name 'Stream descriptor' -Status 'failed' -HttpStatus $streams.StatusCode -Milliseconds $streams.Milliseconds -Detail (Format-ApiError $streams)
                }
            } else {
                Add-Result -Name 'Stream descriptor' -Status 'warning' -Detail "first result access=$($first.access); no stream probe performed"
            }
        }

        # 8. Read the actual rate-limit headers once more for the report.
        if ($search.Headers) {
            try {
                $script:rateLimit = [pscustomobject]@{
                    limit     = [string]$search.Headers['X-Ratelimit-Limit']
                    remaining = [string]$search.Headers['X-Ratelimit-Remaining']
                    resetUnix = [string]$search.Headers['X-Ratelimit-Reset']
                }
            } catch { }
        }
    } else {
        Add-Result -Name 'OAuth client credentials' -Status 'failed' -HttpStatus $tokenResponse.StatusCode -Milliseconds $tokenResponse.Milliseconds -Detail (Format-ApiError $tokenResponse)
        Write-Host ''
        Write-Host 'Token exchange failed. Check the key, the secret, and whether the app has Artist Pro access.' -ForegroundColor Red
    }
}

$failed = @($script:results | Where-Object { $_.status -eq 'failed' }).Count
$warnings = @($script:results | Where-Object { $_.status -eq 'warning' }).Count
$summary = [pscustomobject]@{
    generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    apiBase          = $apiBase
    credentialsSent  = $hasCredentials
    credentialsValid = [bool]($script:results | Where-Object { $_.name -eq 'OAuth client credentials' -and $_.status -eq 'ok' })
    passed           = @($script:results | Where-Object { $_.status -eq 'ok' }).Count
    warnings         = $warnings
    failed           = $failed
    rateLimit        = $script:rateLimit
    checks           = $script:results
    nextSteps        = @(
        'If credentials are absent: register an app at https://soundcloud.com/you/apps (Artist Pro required).',
        'Store Client ID + Secret in Config/Secrets.xcconfig locally or enter them in Volna Settings (Keychain).',
        'If API registration is unavailable: use the built-in official Web-embed mode and add SoundCloud track/playlist URLs manually.',
        'Never commit the Client Secret. A mobile binary cannot keep a secret, so this build is for personal sideloading only.'
    )
}

$report = [pscustomobject]@{
    summary = $summary
    checks  = $script:results
}

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutFile -Encoding UTF8

Write-Host ''
Write-Host ("Summary: {0} passed, {1} warnings, {2} failed" -f $summary.passed, $warnings, $failed) -ForegroundColor $(if ($failed -gt 0) { 'Red' } elseif ($warnings -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "Report: $OutFile" -ForegroundColor DarkGray
if ($failed -gt 0) { exit 2 }
