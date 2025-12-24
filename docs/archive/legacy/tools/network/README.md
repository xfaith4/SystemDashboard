# Network inventory tools

- `NetworkClientScan.ps1` – scans one or more /24s, resolves hostnames, collects MAC/manufacturer (OUI), optional nmap OS/port info, exports Excel/HTML/SQLite.
  ```powershell
  pwsh -File .\NetworkClientScan.ps1 `
    -Subnets @('192.168.50','192.168.101') `
    -Range (1..254) `
    -OutDir "$env:USERPROFILE\Desktop\SubnetScan" `
    -SkipDependencyCheck  # if modules already present
  ```
  Outputs in OutDir: `SubnetScan-*.xlsx`, `SubnetScan-Report.html`, `NetworkInventory.sqlite`.

Tests: `NetworkClientScan.Tests.ps1` (Pester).
