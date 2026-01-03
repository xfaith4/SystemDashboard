param(
    [Parameter(Mandatory)] 
    [string]$RouterIP,
    [string]$User = 'admin',
    [int]$Port = 22,
    [string]$OutDir = "$PWD\RouterBackup_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
)

# Create output directory
$null = New-Item -ItemType Directory -Force -Path $OutDir

# Remote file paths
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$remoteDir = "/tmp/backup_$timestamp"
$bundle = "$remoteDir/backup_$timestamp.tar.gz"
$nvram = "$remoteDir/nvram_$timestamp.txt"
$dmesg = "$remoteDir/dmesg_$timestamp.log"
$ipt4 = "$remoteDir/iptables_v4_$timestamp.rules"
$ipt6 = "$remoteDir/iptables_v6_$timestamp.rules"
$jffsls = "$remoteDir/jffs_list_$timestamp.txt"

# Get credentials
$cred = Get-Credential -UserName $User -Message "Enter router password for $($RouterIP):$($Port)"
$password = $cred.GetNetworkCredential().Password

# Create remote directory
$createDirCmd = "mkdir -p $remoteDir"
$null = plink -ssh -batch -P $Port -pw $password "$User@$RouterIP" $createDirCmd

# Prepare commands to run on router
$cmd = @"
nvram show | sort > "$nvram"
dmesg > "$dmesg" 2>/dev/null || true
iptables-save > "$ipt4" 2>/dev/null || true
ip6tables-save > "$ipt6" 2>/dev/null || true
find /jffs -maxdepth 4 -type f -printf '%p|%s|%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null > "$jffsls" || true
tar -czf "$bundle" /jffs /etc /rom/etc /var/log 2>/dev/null
"@

# Execute commands on router
Write-Host "Running backup commands on router..."
$null = plink -ssh -batch -P $Port -pw $($cred.GetNetworkCredential().Password) "$User@$RouterIP" $cmd

# Download files
$files = @($bundle, $nvram, $dmesg, $ipt4, $ipt6, $jffsls)
foreach ($file in $files) {
    $remotePath = "$User@$RouterIP`:""$file"""  # Properly escape the remote path
    $localPath = Join-Path -Path $OutDir -ChildPath (Split-Path -Leaf $file)
    Write-Host "Downloading $file to $localPath"
    & scp -P $Port $remotePath $localPath
}

# Show downloaded files
Write-Host "`nDownloaded files:"
Get-ChildItem $OutDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
