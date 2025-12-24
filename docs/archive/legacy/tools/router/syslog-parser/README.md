# Syslog-Parser

Purpose: ad-hoc ASUS/router syslog analyzer to extract DROP events, roam kicks, and SIGTERM indicators. Emits CSVs and a JSON summary for dashboards/plots.

## Usage
```powershell
cd SystemDashboard/tools/router/syslog-parser
pwsh -File .\Syslog-Parser.ps1 -Files @('C:\logs\syslog1.txt','C:\logs\syslog2.txt') -OutDir .\out -EmitSummaryJson
```

Outputs (under `-OutDir`):
- `KPIs.csv`
- `TopDropSources.csv`
- `TopDropDestinations.csv`
- `RoamAssistKicks.csv`
- `summary.json` (when `-EmitSummaryJson` is set)

Returned object (for chaining in PowerShell) includes KPIs, top drops, roam counts, and the files parsed. This can be hooked into the dashboard later for status/visuals.*** End Patch ***!
