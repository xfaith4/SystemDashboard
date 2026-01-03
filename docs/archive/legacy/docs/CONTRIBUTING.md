# Contributing to SystemDashboard

Thank you for your interest in contributing to SystemDashboard! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Environment Setup](#development-environment-setup)
- [Project Structure](#project-structure)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Pull Request Process](#pull-request-process)
- [Documentation](#documentation)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Community](#community)

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for all contributors. We expect all participants to:

- Use welcoming and inclusive language
- Respect differing viewpoints and experiences
- Accept constructive criticism gracefully
- Focus on what is best for the community
- Show empathy towards other community members

### Unacceptable Behavior

- Harassment, trolling, or discriminatory comments
- Personal attacks or political arguments
- Publishing others' private information
- Any conduct that could reasonably be considered inappropriate in a professional setting

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Windows 11** or Windows Server 2019+
- **PowerShell 7.3+**
- **Python 3.10+**
- **Git**
- Basic understanding of:
  - PowerShell scripting
  - Python/Flask development
  - SQLite database
  - HTML/CSS/JavaScript

### First-Time Setup

1. **Fork the repository** on GitHub
2. **Clone your fork**:
   ```powershell
   git clone https://github.com/YOUR_USERNAME/SystemDashboard.git
   cd SystemDashboard
   ```

3. **Add upstream remote**:
   ```powershell
   git remote add upstream https://github.com/your-username/SystemDashboard.git
   ```

4. **Set up development environment**:
   ```powershell
   .\scripts\Launch.ps1
   ```

5. **Create a development branch**:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

## Development Environment Setup

### Python Environment

```powershell
# Create virtual environment
python -m venv .venv

# Activate virtual environment
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Install development dependencies
pip install pytest pytest-cov flake8 black mypy
```

### PowerShell Module Development

```powershell
# Link module for development (instead of Install.ps1)
$modulePath = "$env:USERPROFILE\Documents\PowerShell\Modules\SystemDashboard"
New-Item -ItemType SymbolicLink -Path $modulePath -Target "$PWD\tools" -Force

# Test module import
Import-Module SystemDashboard -Force
```

### Database Setup

```powershell
# Initialize test database
python scripts/init_db.py

# Verify schema
python scripts/init_db.py --verify
```

## Project Structure

```
SystemDashboard/
├── app/                        # Flask web application
│   ├── app.py                  # Main Flask app
│   ├── db_manager.py           # Database connection pool
│   ├── validators.py           # Input validation
│   ├── auth.py                 # Authentication
│   ├── static/                 # Static assets (CSS, JS)
│   └── templates/              # Jinja2 templates
├── services/                   # PowerShell services
│   ├── SystemDashboardService.ps1
│   ├── LanCollectorService.ps1
│   └── SyslogCollectorService.ps1
├── tools/                      # PowerShell modules
│   ├── SystemDashboard.Telemetry.psm1
│   └── schema-sqlite.sql
├── scripts/                    # Utility scripts
│   ├── init_db.py
│   ├── Install.ps1
│   └── Launch.ps1
├── tests/                      # Test suites
│   ├── test_app.py
│   ├── test_db_manager.py
│   └── SystemDashboard.Tests.ps1
├── docs/                       # Documentation
│   ├── GETTING-STARTED.md
│   ├── API-REFERENCE.md
│   └── ...
├── var/                        # Runtime data (not in git)
│   ├── system_dashboard.db
│   └── log/
├── config.json                 # Configuration
├── requirements.txt            # Python dependencies
└── README.md                   # Project overview
```

## Coding Standards

### Python Code Style

We follow **PEP 8** with these specifics:

- **Line length**: 100 characters (not 79)
- **Indentation**: 4 spaces
- **String quotes**: Double quotes for user-facing strings, single for internal
- **Imports**: Grouped (standard library, third-party, local) and sorted alphabetically

**Use Black for formatting**:

```bash
black app/ scripts/
```

**Use Flake8 for linting**:

```bash
flake8 app/ scripts/ --max-line-length=100
```

**Example**:

```python
def get_devices(status: str = "all", limit: int = 100) -> List[Dict[str, Any]]:
    """Get list of devices filtered by status.
    
    Args:
        status: Filter by 'online', 'offline', or 'all' (default: 'all')
        limit: Maximum number of results (default: 100, max: 1000)
    
    Returns:
        List of device dictionaries with keys: mac_address, nickname, is_online, etc.
    
    Raises:
        ValueError: If status is invalid or limit exceeds maximum
    """
    if status not in ("online", "offline", "all"):
        raise ValueError(f"Invalid status: {status}")
    
    if limit > 1000:
        raise ValueError("Limit cannot exceed 1000")
    
    # Implementation...
    return devices
```

### PowerShell Code Style

- **Verb-Noun naming**: Use approved PowerShell verbs (Get-, Set-, New-, etc.)
- **PascalCase** for function names
- **camelCase** for variables
- **Comment-based help** for all functions
- **Error handling**: Use Try/Catch blocks
- **PSScriptAnalyzer**: Run and fix warnings

**Example**:

```powershell
function Get-DeviceSnapshot {
    <#
    .SYNOPSIS
        Retrieves device snapshot data from the router.
    
    .DESCRIPTION
        Queries the router API for current device list and returns
        parsed snapshot data including MAC, IP, RSSI, and rates.
    
    .PARAMETER RouterUri
        Router API endpoint URL.
    
    .PARAMETER Credential
        PSCredential object for router authentication.
    
    .EXAMPLE
        Get-DeviceSnapshot -RouterUri "https://192.168.1.1/api/devices"
    
    .OUTPUTS
        PSCustomObject with device snapshot properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouterUri,
        
        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )
    
    try {
        $response = Invoke-RestMethod -Uri $RouterUri -Credential $Credential
        # Process response...
        return $devices
    }
    catch {
        Write-Error "Failed to get device snapshot: $_"
        throw
    }
}
```

### JavaScript Code Style

- **ES6+ syntax** (const, let, arrow functions, template literals)
- **2-space indentation**
- **Semicolons optional** but be consistent
- **JSDoc comments** for functions
- **ESLint** for linting (if configured)

**Example**:

```javascript
/**
 * Fetches device data from the API
 * @param {string} status - Filter by status (online, offline, all)
 * @param {number} limit - Maximum results to return
 * @returns {Promise<Array>} Array of device objects
 */
async function fetchDevices(status = 'all', limit = 100) {
  const url = `/api/lan/devices?status=${status}&limit=${limit}`
  
  try {
    const response = await fetch(url)
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }
    
    const data = await response.json()
    return data.devices
  } catch (error) {
    console.error('Failed to fetch devices:', error)
    throw error
  }
}
```

### SQL Code Style

- **Uppercase keywords**: SELECT, FROM, WHERE, JOIN, etc.
- **Table/column names**: Lowercase with underscores
- **Indentation**: Align clauses
- **Comments**: Use `--` for single-line, `/* */` for multi-line

**Example**:

```sql
-- Get device uptime statistics for last 7 days
SELECT
  d.mac_address,
  d.nickname,
  COUNT(*) AS total_snapshots,
  SUM(CASE WHEN ds.is_online = 1 THEN 1 ELSE 0 END) AS online_snapshots,
  ROUND(100.0 * SUM(CASE WHEN ds.is_online = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS uptime_pct
FROM devices d
JOIN device_snapshots ds ON d.device_id = ds.device_id
WHERE ds.sample_time_utc >= datetime('now', '-7 days')
GROUP BY d.device_id
ORDER BY uptime_pct DESC;
```

## Testing Guidelines

### Python Tests

We use **pytest** for Python testing.

**Test file naming**: `test_<module>.py`

**Test function naming**: `test_<function>_<scenario>()`

**Run tests**:

```bash
# All tests
pytest

# With coverage
pytest --cov=app --cov-report=html

# Specific test file
pytest tests/test_db_manager.py

# Specific test
pytest tests/test_db_manager.py::test_connection_pool_limits
```

**Example test**:

```python
import pytest
from app.db_manager import DatabaseManager

def test_connection_pool_limits():
    """Test that connection pool respects max connections limit."""
    manager = DatabaseManager("test.db", max_connections=2)
    
    # Should succeed
    conn1 = manager.get_connection()
    conn2 = manager.get_connection()
    
    # Should raise error (pool exhausted)
    with pytest.raises(Exception):
        conn3 = manager.get_connection()
    
    # Release and try again
    manager.return_connection(conn1)
    conn3 = manager.get_connection()  # Should succeed now

def test_query_timeout():
    """Test that queries timeout after configured period."""
    manager = DatabaseManager("test.db", query_timeout=1)
    
    with pytest.raises(sqlite3.OperationalError):
        # Long-running query should timeout
        manager.execute("SELECT * FROM large_table WHERE 1 = (SELECT COUNT(*) FROM large_table)")
```

**Test coverage goal**: >80% for all new code

### PowerShell Tests

We use **Pester** for PowerShell testing.

**Test file naming**: `<Module>.Tests.ps1`

**Run tests**:

```powershell
# All tests
Invoke-Pester

# Specific test file
Invoke-Pester -Path tests/SystemDashboard.Tests.ps1

# With code coverage
Invoke-Pester -CodeCoverage "tools/*.psm1"
```

**Example test**:

```powershell
Describe "Get-DeviceSnapshot" {
    BeforeAll {
        Import-Module SystemDashboard -Force
    }
    
    Context "When router is reachable" {
        It "Returns device list" {
            $devices = Get-DeviceSnapshot -RouterUri "http://test-router/api"
            $devices | Should -Not -BeNullOrEmpty
            $devices[0].mac_address | Should -Match '^[0-9A-F:]{17}$'
        }
    }
    
    Context "When router is unreachable" {
        It "Throws error" {
            { Get-DeviceSnapshot -RouterUri "http://invalid-router" } | Should -Throw
        }
    }
}
```

### Integration Tests

Integration tests verify end-to-end functionality:

```python
def test_device_update_flow():
    """Test complete device update workflow."""
    # Create device
    device_id = create_test_device()
    
    # Update via API
    response = client.post(
        f'/api/lan/device/{device_id}/update',
        json={'nickname': 'Test Device', 'location': 'Lab'},
        headers={'X-API-Key': 'test_key'}
    )
    assert response.status_code == 200
    
    # Verify in database
    device = get_device_from_db(device_id)
    assert device['nickname'] == 'Test Device'
    assert device['location'] == 'Lab'
```

## Commit Message Guidelines

We follow **Conventional Commits** specification:

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring (no feature change)
- `perf`: Performance improvement
- `test`: Adding or updating tests
- `chore`: Maintenance tasks (dependencies, build scripts)
- `ci`: CI/CD changes

### Examples

```
feat(lan): add device nickname editing

Implement nickname and location editing for LAN devices.
Users can now assign friendly names via the dashboard.

Closes #123
```

```
fix(db): resolve database lock errors under high load

Switch from default journaling to WAL mode to allow
concurrent reads while writing. Increases connection
pool size to 10.

Fixes #456
```

```
docs(api): add API reference documentation

Create comprehensive API reference with all endpoints,
parameters, and examples.
```

### Subject Rules

- Use imperative mood ("add" not "added" or "adds")
- No period at the end
- Maximum 72 characters
- Capitalize first letter

### Body (Optional)

- Explain **what** and **why**, not **how**
- Wrap at 72 characters
- Separate from subject with blank line

### Footer (Optional)

- Reference issues: `Closes #123`, `Fixes #456`
- Breaking changes: `BREAKING CHANGE: <description>`

## Pull Request Process

### Before Submitting

1. **Sync with upstream**:
   ```powershell
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run tests**:
   ```bash
   pytest
   Invoke-Pester
   ```

3. **Run linters**:
   ```bash
   black app/ scripts/
   flake8 app/ scripts/
   ```

4. **Update documentation** if needed

5. **Add tests** for new features

### Submitting Pull Request

1. **Push to your fork**:
   ```powershell
   git push origin feature/your-feature-name
   ```

2. **Create Pull Request** on GitHub:
   - Use clear, descriptive title
   - Reference related issues
   - Describe changes and motivation
   - Add screenshots for UI changes
   - Check "Allow edits from maintainers"

3. **Pull Request Template**:

   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Performance improvement
   
   ## Testing
   - [ ] All tests pass
   - [ ] Added new tests
   - [ ] Manual testing completed
   
   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Documentation updated
   - [ ] No breaking changes (or documented)
   - [ ] Commits follow conventional commits
   
   ## Related Issues
   Closes #123
   ```

### Code Review Process

1. **Automated checks** must pass (if CI configured)
2. **Maintainer review** (usually within 48 hours)
3. **Address feedback** by pushing new commits
4. **Approval** and merge by maintainer

### After Merge

1. **Delete your branch**:
   ```powershell
   git branch -d feature/your-feature-name
   git push origin --delete feature/your-feature-name
   ```

2. **Sync your fork**:
   ```powershell
   git checkout main
   git fetch upstream
   git merge upstream/main
   git push origin main
   ```

## Documentation

### When to Update Documentation

- **New features**: Always document in relevant guides
- **API changes**: Update API-REFERENCE.md
- **Configuration changes**: Update config.json comments and SETUP.md
- **Database changes**: Update DATABASE-SCHEMA.md
- **Bug fixes**: Update TROUBLESHOOTING.md if applicable

### Documentation Standards

- **Markdown format** (GitHub-flavored)
- **Clear headings** with proper hierarchy
- **Code examples** for all technical content
- **Screenshots** for UI features (commit PNGs to docs/images/)
- **Links** to related documentation

### Building Documentation

Documentation is markdown-based and doesn't require building. For previewing:

```powershell
# Preview in browser (requires grip)
pip install grip
grip docs/GETTING-STARTED.md
```

## Reporting Bugs

### Before Reporting

1. **Search existing issues** to avoid duplicates
2. **Verify it's a bug** (not configuration issue)
3. **Test on latest version**

### Bug Report Template

```markdown
**Describe the bug**
Clear description of what's wrong

**To Reproduce**
Steps to reproduce:
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What should happen

**Actual behavior**
What actually happens

**Screenshots**
If applicable

**Environment**
- OS: Windows 11 23H2
- PowerShell: 7.4.0
- Python: 3.12.0
- SystemDashboard version: git commit hash

**Logs**
Relevant log snippets from var/log/

**Additional context**
Any other information
```

## Feature Requests

### Before Requesting

1. **Check roadmap** (ROADMAP.md) to see if already planned
2. **Search issues** for similar requests
3. **Consider workarounds** with existing features

### Feature Request Template

```markdown
**Feature Description**
Clear description of the feature

**Use Case**
Why is this feature needed? What problem does it solve?

**Proposed Solution**
How should it work?

**Alternatives Considered**
Other approaches you've thought of

**Additional Context**
Screenshots, mockups, examples from other tools
```

## Community

### Getting Help

- **Documentation**: Check docs/ directory first
- **FAQ**: See FAQ.md for common questions
- **GitHub Discussions**: For questions and general discussion
- **GitHub Issues**: For bug reports and feature requests only

### Stay Updated

- **Watch the repository** on GitHub for notifications
- **Read CHANGELOG.md** for release notes
- **Follow the roadmap** in ROADMAP.md

## Questions?

If you have questions about contributing:

1. Check this guide
2. Read existing documentation
3. Search GitHub Issues
4. Ask in GitHub Discussions
5. Open an issue with the "question" label

---

**Thank you for contributing to SystemDashboard!** Your efforts help make this project better for everyone.
