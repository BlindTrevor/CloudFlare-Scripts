<#
.SYNOPSIS
  Set a DMARC TXT record exists (or is updated) for every Cloudflare zone.

.DESCRIPTION
  For each active Cloudflare zone:
    - Looks for TXT record at _dmarc.<zone>.
    - If exists and differs: updates content.
    - If missing: creates it.
    - Optionally deletes duplicate _dmarc TXT records (beyond the first).
    - Compatible with Windows PowerShell 5.1 (no PS7-only operators).

.PARAMETER ApiToken
  Cloudflare API token with Zone.DNS Edit permission. If not provided, uses $Env:CF_API_TOKEN.

.PARAMETER DmarcValue
  The DMARC policy to enforce. Defaults to strict reject with aggregate & forensic reports.

.PARAMETER RemoveDuplicates
  If set, remove duplicate _dmarc TXT records beyond the first.

.PARAMETER IncludeZones
  Array of zone names to include (whitelist). If provided, only these zones are processed.

.PARAMETER ExcludeZones
  Array of zone names to exclude (blacklist). Useful for parked/test domains.

.PARAMETER DryRun
  If set, no changes are made—actions are only printed.

.EXAMPLE
  .\Set-DmarcAllZones.ps1 -ApiToken $Env:CF_API_TOKEN -RemoveDuplicates

.EXAMPLE
  .\Set-DmarcAllZones.ps1 -DryRun -ExcludeZones "example.com","staging.example.com"
#>
function Set-DmarcAllZones {
    [CmdletBinding()]
    param(
        [string]$ApiToken = $Env:CF_API_TOKEN,
        [string]$DmarcValue = 'v=DMARC1; p=reject; sp=reject; rua=mailto:dmarc@citywestcountry.co.uk; ruf=mailto:dmarc@citywestcountry.co.uk; fo=1',
        [switch]$RemoveDuplicates,
        [string[]]$IncludeZones,
        [string[]]$ExcludeZones,
        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($ApiToken)) {
        Write-Error "Cloudflare API token not provided. Set -ApiToken or `$Env:CF_API_TOKEN."
        exit 1
    }

    # Ensure TLS 1.2 for older Windows PowerShell HTTP stack
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $BaseUri = "https://api.cloudflare.com/client/v4"
    $Headers = @{
        "Authorization" = ("Bearer {0}" -f $ApiToken)
        "Content-Type"  = "application/json"
    }

    function Get-CloudflareZones {
        [CmdletBinding()]
        param([int]$PerPage = 50)

        $zones = @()
        $page = 1

        while ($true) {
            $url = "$BaseUri/zones?per_page=$PerPage&page=$page&status=active"
            try {
            $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method GET -TimeoutSec 30
            } catch {
            throw "Failed to list zones (page $page): $($_.Exception.Message)"
            }

            if (-not $resp.success) {
            $err = ($resp.errors | ConvertTo-Json -Compress)
            throw "Cloudflare API error listing zones (page $page): $err"
            }

            if ($resp.result) { $zones += $resp.result }
            $totalPages = $resp.result_info.total_pages
            if ($page -ge $totalPages) { break }
            $page++
        }

        return $zones
    }

    function Get-DmarcDnsRecords {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$ZoneId,
            [Parameter(Mandatory=$true)][string]$ZoneName
        )
        $name = "_dmarc.$ZoneName"
        $url  = "$BaseUri/zones/$ZoneId/dns_records?type=TXT&name=$name"

        $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method GET -TimeoutSec 30
        if (-not $resp.success) {
            $err = ($resp.errors | ConvertTo-Json -Compress)
            throw "Error retrieving DMARC records for $($ZoneName): $err"
        }
        return @($resp.result), $name
    }

    function New-DmarcRecord {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$ZoneId,
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][string]$Content,
            [switch]$DryRun
        )

        $payloadObj = @{
            type    = "TXT"
            name    = $Name
            content = $Content
            ttl     = 1  # 1 => Auto
        }
        $payload = $payloadObj | ConvertTo-Json

        if ($PSBoundParameters.ContainsKey('DryRun') -and $DryRun) {
            Write-Host "[DRY] Create TXT $Name = $Content"
            return $true
        }

        $url = "$BaseUri/zones/$ZoneId/dns_records"
        $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method POST -Body $payload -TimeoutSec 30
        return [bool]$resp.success
    }

    function Set-DmarcRecord {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$ZoneId,
            [Parameter(Mandatory=$true)][string]$RecordId,
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][string]$Content,
            [switch]$DryRun
        )

        $payloadObj = @{
            type    = "TXT"
            name    = $Name
            content = $Content
            ttl     = 1
        }
        $payload = $payloadObj | ConvertTo-Json

        if ($PSBoundParameters.ContainsKey('DryRun') -and $DryRun) {
            Write-Host ("[DRY] Update TXT {0} = {1} (id={2})" -f $Name, $Content, $RecordId)
            return $true
        }

        $url = "$BaseUri/zones/$ZoneId/dns_records/$RecordId"
        $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method PUT -Body $payload -TimeoutSec 30
        return [bool]$resp.success
    }

    function Remove-CFDnsRecord {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$ZoneId,
            [Parameter(Mandatory=$true)][string]$RecordId,
            [Parameter(Mandatory=$true)][string]$ZoneName,
            [switch]$DryRun
        )

        if ($PSBoundParameters.ContainsKey('DryRun') -and $DryRun) {
            Write-Host ("[DRY] Delete duplicate record id={0} for {1}" -f $RecordId, $ZoneName)
            return $true
        }

        $url = "$BaseUri/zones/$ZoneId/dns_records/$RecordId"
        $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method DELETE -TimeoutSec 30
        return [bool]$resp.success
    }

    try {
        $allZones = Get-CloudflareZones
        $zones = $allZones

        if ($IncludeZones -and $IncludeZones.Count -gt 0) {
            $zones = $zones | Where-Object { $IncludeZones -contains $_.name }
        }
        if ($ExcludeZones -and $ExcludeZones.Count -gt 0) {
            $zones = $zones | Where-Object { $ExcludeZones -notcontains $_.name }
        }

        Write-Host ("Found {0} active zones. Processing {1} zones." -f $allZones.Count, $zones.Count)

        foreach ($zone in $zones) {
            $zoneId = $zone.id
            $zoneName = $zone.name

            try {
            $result = Get-DmarcDnsRecords -ZoneId $zoneId -ZoneName $zoneName
            $records = $result[0]
            $name    = $result[1]

            if ($records.Count -eq 0) {
                $ok = New-DmarcRecord -ZoneId $zoneId -Name $name -Content $DmarcValue -DryRun:$DryRun
                Write-Host ("[+] {0}: created DMARC success={1}" -f $zoneName, $ok)
                continue
            }

            # Prefer the first record as primary
            $primary = $records[0]
            $currentContent = ""
            if ($null -ne $primary.content) {
                $currentContent = $primary.content.Trim()
            }

            if ($currentContent -eq $DmarcValue) {
                Write-Host "[=] $($zoneName): DMARC already matches"
            } else {
                $ok = Set-DmarcRecord -ZoneId $zoneId -RecordId $primary.id -Name $name -Content $DmarcValue -DryRun:$DryRun
                Write-Host ("[U] {0}: updated DMARC success={1}" -f $zoneName, $ok)
            }

            if ($RemoveDuplicates.IsPresent -and $records.Count -gt 1) {
                $duplicates = $records | Select-Object -Skip 1
                foreach ($dup in $duplicates) {
                $dok = Remove-CFDnsRecord -ZoneId $zoneId -RecordId $dup.id -ZoneName $zoneName -DryRun:$DryRun
                Write-Host ("[D] {0}: removed duplicate {1} success={2}" -f $zoneName, $dup.id, $dok)
                }
            }
            } catch {
            Write-Warning ("[{0}] Error: {1}" -f $zoneName, $_.Exception.Message)
            }
        }
    }
    catch {
    Write-Error ("Fatal: {0}" -f $_.Exception.Message)
    exit 1
    }
}