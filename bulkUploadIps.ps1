# Cloudflare credentials
$apiToken = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
$zoneName = "zonedomain.co.uk"
$baseDomain = "sites.zonedomain.co.uk"

# Get Zone ID
$zoneResponse = Invoke-RestMethod -Method GET -Uri "https://api.cloudflare.com/client/v4/zones?name=$zoneName" -Headers @{
    Authorization = "Bearer $apiToken"
    "Content-Type" = "application/json"
}

$zoneId = $zoneResponse.result[0].id

# List of IPs
$ips = @(
    "x.x.x.x","y.y.y.y","z.z.z.z"
)

# Loop through IPs and create A records
foreach ($ip in $ips) {
    $recordName = $baseDomain

    $body = @{
        type    = "A"
        name    = $recordName
        content = $ip
        ttl     = 3600
        proxied = $false
    } | ConvertTo-Json -Depth 3

    $response = Invoke-RestMethod -Method POST -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records" -Headers @{
        Authorization = "Bearer $apiToken"
        "Content-Type" = "application/json"
    } -Body $body

    if ($response.success) {
        Write-Host "✅ Created A record for $recordName ($ip)"
    } else {
        Write-Host "❌ Failed to create $recordName : $($response.errors[0].message)"
    }
}
