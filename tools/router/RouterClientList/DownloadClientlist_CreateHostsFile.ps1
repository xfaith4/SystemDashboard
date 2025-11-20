$Path = "F:\Downloads\ClientList (1).csv"
$import = Import-Csv -Path $Path

$import | Export-Excel -Path "F:\Downloads\ClientList.xlsx" -Show -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
# Parse and format as Ansible hosts.ini
$hostsFile = @("[all]")  # Ansible inventory group
foreach ($client in $import) {
    if ($client.'Client IP address' -and $client.'Client Name') {
        $hostsFile += "$($client.'Client Name') ansible_host=$($client.'Client IP address')"
    }
}

# Write to hosts.ini
$hostsFilePath = "F:\temp\hosts.ini"
$hostsFile | Out-File -Encoding UTF8 -FilePath $hostsFilePath

Write-Host "Ansible hosts.ini file created: $hostsFilePath"
