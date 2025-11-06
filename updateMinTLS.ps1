#Zone Settings: Edit – to update the minimum TLS version for each zone.
#Edit zone DNS	Zone.Zone Settings	All zones

$apiToken = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}
function Get-Zones {
    $url = "https://api.cloudflare.com/client/v4/zones?per_page=50"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    return $response.result
}
function Update-TLS {
    param (
        [string]$zoneId,
        [string]$zoneName,
        [string]$zoneIndex
    )
    $url = "https://api.cloudflare.com/client/v4/zones/$zoneId/settings/min_tls_version"
    $body = @{ value = "1.2" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Patch -Body $body
    Write-Host "$($i): Updated TLS for $($zoneName): $($response.result.value)"
}
$zones = Get-Zones
$i=0
foreach ($zone in $zones) {
    $i++
    Update-TLS -zoneId $zone.id -zoneName $zone.name -zoneIndex $i
}
