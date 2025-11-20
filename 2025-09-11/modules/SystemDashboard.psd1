@{
    RootModule        = 'SystemDashboard.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a8f0eea6-0f3e-4d6b-8d5b-2b7d2f2b1e10'
    Author            = 'System Monitor WebApp'
    CompanyName       = 'Local'
    Copyright         = '(c) 2025'
    Description       = 'PowerShell 7 + Pode backend for System Monitor WebApp'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Start-SystemDashboard','Stop-SystemDashboard',
        'Initialize-Database','Invoke-AIAnalysis',
        'Get-RouterClients','Get-EventRows','Get-SyslogRows'
    )

    FormatsToProcess  = @()
    AliasesToExport   = @()
    PrivateData       = @{}
}
