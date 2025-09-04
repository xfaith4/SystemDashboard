@{
    RootModule        = 'Start-SystemDashboard.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '3dcb4906-6c6b-4eab-b2d3-29cbf39efee6'
    Author            = 'SystemDashboard Maintainers'
    Description       = 'System Dashboard PowerShell module'
    RequiredModules   = @()
    FunctionsToExport = @(
        'Start-SystemDashboardListener',
        'Ensure-UrlAcl',
        'Remove-UrlAcl',
        'Scan-ConnectedClients',
        'Get-RouterCredentials',
        'Get-SystemLogs'
    )
    AliasesToExport   = @()
    CmdletsToExport   = @()
    PrivateData       = @{}
}
