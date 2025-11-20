<# 
Parses ASUS/router syslog text files to surface DROP events, roam kicks, and SIGTERM-style events.
Outputs CSVs and returns a summary object for downstream use (e.g., dashboards).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Files,
    [string]$OutDir = (Join-Path $PSScriptRoot 'out'),
    [switch]$EmitSummaryJson,
    [string]$SummaryJsonPath
)

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$resolved = @()
foreach ($f in $Files) {
    try { $resolved += (Resolve-Path -LiteralPath $f -ErrorAction Stop).Path }
    catch { Write-Warning "File not found: $f"; }
}
if (-not $resolved) { throw "No readable input files supplied." }

$line   = '^(?<date>\d{2}\/\d{2})\s+(?<time>\d{2}:\d{2}:\d{2}\.\d{3})\s+(?<host>\d{1,3}(\.\d{1,3}){3})\s+(?<facility>\S+)\s+(?<router>\S+)\s+(?<msg>.+)$'
$drop   = 'kernel:\s+DROP\s+.*SRC=(?<src>\S+)\s+DST=(?<dst>\S+).*PROTO=(?<proto>\S+)(?:\s+SPT=(?<spt>\d+))?(?:\s+DPT=(?<dpt>\d+))?'
$roam   = 'roamast:.*(?:disconnect weak signal strength station|remove client)\s+\[(?<mac>[0-9a-f:]{17})\]'
$rstats = 'rstats\[\d+\]:\s+Problem loading\s+(?<file>\S+)'
$igmp   = 'kernel:\s+DROP\s+.*DST=224\.0\.0\.1.*PROTO=2'

$Drops = @()
$Roam  = @()
$Kpis  = [ordered]@{ TotalDrop = 0; IGMPDrops = 0; RstatsErrors = 0; RoamKicks = 0; DnsmasqSIGTERM = 0; AvahiSIGTERM = 0; UPnPShutdowns = 0 }

foreach ($f in $resolved) {
    Get-Content $f -ErrorAction Stop | ForEach-Object {
        $m = [regex]::Match($_, $line)
        if (-not $m.Success) { return }
        $msg = $m.Groups['msg'].Value

        $dropMatch = [regex]::Match($msg, $drop)
        if ($dropMatch.Success) {
            $Drops += [pscustomobject]@{
                Src   = $dropMatch.Groups['src'].Value
                Dst   = $dropMatch.Groups['dst'].Value
                Proto = $dropMatch.Groups['proto'].Value
                Spt   = $dropMatch.Groups['spt'].Value
                Dpt   = $dropMatch.Groups['dpt'].Value
                Raw   = $msg
            }
            $Kpis['TotalDrop']++
            if ($msg -match $igmp) { $Kpis['IGMPDrops']++ }
        }

        $roamMatch = [regex]::Match($msg, $roam)
        if ($roamMatch.Success) {
            $Roam += $roamMatch.Groups['mac'].Value.ToLower()
            $Kpis['RoamKicks']++
        }

        if ($msg -match $rstats) { $Kpis['RstatsErrors']++ }
        if ($msg -match 'dnsmasq\[\d+\]: exiting on receipt of SIGTERM') { $Kpis['DnsmasqSIGTERM']++ }
        if ($msg -match 'avahi-daemon\[\d+\]: Got SIGTERM') { $Kpis['AvahiSIGTERM']++ }
        if ($msg -match 'miniupnpd\[\d+\]: shutting down MiniUPnPd') { $Kpis['UPnPShutdowns']++ }
    }
}

$TopSrc = $Drops |
  Group-Object Src, Proto, Dpt |
  Sort-Object Count -Descending |
  Select-Object @{n='Src';e={$_.Group[0].Src}},
                @{n='Proto';e={$_.Group[0].Proto}},
                @{n='Dpt';e={$_.Group[0].Dpt}},
                Count

$TopDst = $Drops |
  Group-Object Dst, Proto, Dpt |
  Sort-Object Count -Descending |
  Select-Object @{n='Dst';e={$_.Group[0].Dst}},
                @{n='Proto';e={$_.Group[0].Proto}},
                @{n='Dpt';e={$_.Group[0].Dpt}},
                Count

$RoamCounts = $Roam | Group-Object | Sort-Object Count -Descending |
  Select-Object @{n='MAC';e={$_.Name}}, Count

$Kpis.GetEnumerator() | Sort-Object Name | Export-Csv (Join-Path $OutDir 'KPIs.csv') -NoTypeInformation
$TopSrc     | Export-Csv (Join-Path $OutDir 'TopDropSources.csv') -NoTypeInformation
$TopDst     | Export-Csv (Join-Path $OutDir 'TopDropDestinations.csv') -NoTypeInformation
$RoamCounts | Export-Csv (Join-Path $OutDir 'RoamAssistKicks.csv') -NoTypeInformation

$summary = [pscustomobject]@{
    KPIs       = $Kpis
    TopDropSrc = $TopSrc
    TopDropDst = $TopDst
    RoamKicks  = $RoamCounts
    Files      = $resolved
}

if ($EmitSummaryJson -or $SummaryJsonPath) {
    if (-not $SummaryJsonPath) { $SummaryJsonPath = Join-Path $OutDir 'summary.json' }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -Path $SummaryJsonPath -Encoding UTF8
}

"--- KPIs ---"
$Kpis
"`n--- Top DROP sources (src/proto/dpt) ---"
$TopSrc | Select-Object -First 20 | Format-Table -Auto
"`n--- Roam kicks (MAC) ---"
$RoamCounts | Select-Object -First 20 | Format-Table -Auto

return $summary
