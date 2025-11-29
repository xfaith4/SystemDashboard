# System Dashboard Project Cleanup Plan

## 🧹 Cleanup Status

### ✅ Safe to Remove (Test/Development Files)

These files were created during troubleshooting and are no longer needed:

**Services Directory:**
- `services/SystemDashboardService-Test.ps1` - Test service script
- `services/SystemDashboardService-Fixed.ps1` - Failed service wrapper attempt
- `services/service-wrapper.bat` - Batch file wrapper (not used)

**Root Directory:**
- `Start-SystemDashboard.ps1.tmp` - Temporary file

**Tools Directory:**
- `tools/SystemDashboard.Telemetry.psm1.backup` - Backup of original module
- `tools/schema-fixed.sql` - Fixed schema (functionality merged into schema.sql)

### ⚠️ Keep for Now (Need Decision)

**Documentation Files** (temporary development docs):
- `DATABASE-SETUP-COMPLETE.md` - Database setup completion guide
- `SERVICE-ISSUE-RESOLVED.md` - Service troubleshooting documentation
- `VALIDATION-FIXES.md` - Environment validation fixes

**Setup Scripts** (used for setup):
- `setup-database.ps1` - Local PostgreSQL setup
- `setup-database-docker.ps1` - Docker PostgreSQL setup ✅ (keep this one)
- `setup-scheduled-task.ps1` - Task scheduler setup
- `setup-environment.ps1` - Environment variables ✅ (keep this one)

**Module Files:**
- `tools/SystemDashboard.Telemetry-Minimal.psm1` - Currently used working module ⚠️
- `tools/SystemDashboard.Telemetry.psm1` - Original module with syntax errors

### 🔧 Action Required

1. **Fix Original Module**: The original `SystemDashboard.Telemetry.psm1` has syntax errors
2. **Switch Back**: Once fixed, update service to use original module
3. **Clean Minimal**: Remove minimal module after switch back

## 📝 Recommended Cleanup Actions

### Phase 1: Immediate Safe Cleanup
```powershell
# Remove clearly unnecessary test files
Remove-Item "services\SystemDashboardService-Test.ps1"
Remove-Item "services\SystemDashboardService-Fixed.ps1"
Remove-Item "services\service-wrapper.bat"
Remove-Item "Start-SystemDashboard.ps1.tmp"
Remove-Item "tools\SystemDashboard.Telemetry.psm1.backup"
Remove-Item "tools\schema-fixed.sql"
```

### Phase 2: Documentation Cleanup
```powershell
# Move troubleshooting docs to archive or remove
Remove-Item "DATABASE-SETUP-COMPLETE.md"
Remove-Item "SERVICE-ISSUE-RESOLVED.md"
Remove-Item "VALIDATION-FIXES.md"
```

### Phase 3: Setup Scripts
```powershell
# Keep only the Docker setup and environment setup
Remove-Item "setup-database.ps1"  # Local PostgreSQL version
Remove-Item "setup-scheduled-task.ps1"  # Already configured
```

### Phase 4: Module Consolidation (After fixing original)
```powershell
# After fixing SystemDashboard.Telemetry.psm1:
# 1. Test original module works
# 2. Update SystemDashboardService.ps1 to use original
# 3. Remove minimal module
Remove-Item "tools\SystemDashboard.Telemetry-Minimal.psm1"
```

## 🎯 Final Project Structure

After cleanup, the project should have:

```
SystemDashboard/
├── app/                          # Flask application
├── services/
│   └── SystemDashboardService.ps1   # Main service script
├── tools/
│   ├── schema.sql                   # Database schema
│   ├── SystemDashboard.Telemetry.psm1  # Main telemetry module
│   └── Invoke-SavedPrompt.ps1       # Utility script
├── var/                          # Runtime directories
├── wwwroot/                      # Static web files
├── config.json                   # Configuration
├── setup-environment.ps1         # Environment setup
├── setup-database-docker.ps1     # Database setup for Docker
├── Install.ps1                   # Main installation script
└── README.md                     # Documentation
```

This cleanup will remove ~10 temporary/development files and create a clean, production-ready project structure.
