#!/usr/bin/env python3
"""
Environment validation script for System Dashboard.
Checks if all required data sources are properly configured.
"""

import os
import sys
import platform
import subprocess
from pathlib import Path


def check_python_environment():
    """Check Python environment and dependencies."""
    print("🐍 Checking Python environment...")
    
    # Check Python version
    version = sys.version_info
    if version.major < 3 or (version.major == 3 and version.minor < 8):
        print("❌ Python 3.8+ required, found:", sys.version)
        return False
    else:
        print(f"✅ Python {version.major}.{version.minor}.{version.micro}")
    
    # Check required packages
    required_packages = ['flask', 'pytest', 'requests']
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package)
            print(f"✅ {package} installed")
        except ImportError:
            missing_packages.append(package)
            print(f"❌ {package} missing")
    
    if missing_packages:
        print(f"Install missing packages: pip install {' '.join(missing_packages)}")
        return False
    
    return True


def check_router_logs():
    """Check router log configuration."""
    print("\n📊 Checking router log configuration...")
    
    router_log_path = os.environ.get('ROUTER_LOG_PATH')
    if not router_log_path:
        print("⚠️  ROUTER_LOG_PATH environment variable not set")
        print("   You can set it to use router logs:")
        print("   export ROUTER_LOG_PATH='/path/to/router.log'")
        
        # Check for sample file
        sample_path = Path(__file__).parent / 'sample-router.log'
        if sample_path.exists():
            print(f"   Or use sample: export ROUTER_LOG_PATH='{sample_path}'")
        return False
    
    log_file = Path(router_log_path)
    if not log_file.exists():
        print(f"❌ Router log file not found: {router_log_path}")
        return False
    
    if not log_file.is_file():
        print(f"❌ Router log path is not a file: {router_log_path}")
        return False
    
    try:
        with open(log_file, 'r') as f:
            lines = f.readlines()
        print(f"✅ Router log file accessible: {len(lines)} lines")
        
        # Show sample of first few lines
        if lines:
            print("   Sample entries:")
            for i, line in enumerate(lines[:3]):
                print(f"     {line.strip()}")
                
    except Exception as e:
        print(f"❌ Cannot read router log file: {e}")
        return False
    
    return True


def check_windows_events():
    """Check Windows Event Log access."""
    print("\n📝 Checking Windows Event Log access...")
    
    if platform.system().lower() != 'windows':
        print("⚠️  Not running on Windows - Event Log access unavailable")
        return False
    
    try:
        # Test PowerShell access
        result = subprocess.run([
            'powershell', '-NoProfile', '-Command',
            'Get-WinEvent -ListLog Application | Select-Object -First 1'
        ], capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            print("✅ Windows Event Log access verified")
            return True
        else:
            print(f"❌ PowerShell Event Log access failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ PowerShell command timed out")
        return False
    except FileNotFoundError:
        print("❌ PowerShell not found")
        return False
    except Exception as e:
        print(f"❌ Error accessing Windows Event Logs: {e}")
        return False


def check_system_metrics():
    """Check system metrics collection capability."""
    print("\n⚡ Checking system metrics collection...")
    
    checks_passed = 0
    total_checks = 4
    
    # Check CPU metrics
    try:
        if platform.system().lower() == 'windows':
            result = subprocess.run([
                'powershell', '-NoProfile', '-Command',
                "Get-Counter '\\Processor(_Total)\\% Processor Time' -MaxSamples 1"
            ], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ CPU metrics accessible")
                checks_passed += 1
            else:
                print("❌ CPU metrics failed")
        else:
            # Try Linux tools
            result = subprocess.run(['uptime'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ CPU load info accessible")
                checks_passed += 1
            else:
                print("❌ CPU load info failed")
    except Exception as e:
        print(f"❌ CPU metrics error: {e}")
    
    # Check memory info
    try:
        if platform.system().lower() == 'windows':
            result = subprocess.run([
                'powershell', '-NoProfile', '-Command',
                "Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory"
            ], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ Memory metrics accessible")
                checks_passed += 1
            else:
                print("❌ Memory metrics failed")
        else:
            result = subprocess.run(['free', '-m'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ Memory info accessible")
                checks_passed += 1
            else:
                print("❌ Memory info failed")
    except Exception as e:
        print(f"❌ Memory metrics error: {e}")
    
    # Check disk info
    try:
        if platform.system().lower() == 'windows':
            result = subprocess.run([
                'powershell', '-NoProfile', '-Command',
                "Get-CimInstance Win32_LogicalDisk | Select-Object -First 1"
            ], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ Disk metrics accessible")
                checks_passed += 1
            else:
                print("❌ Disk metrics failed")
        else:
            result = subprocess.run(['df', '-h'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ Disk info accessible")
                checks_passed += 1
            else:
                print("❌ Disk info failed")
    except Exception as e:
        print(f"❌ Disk metrics error: {e}")
    
    # Check network info
    try:
        if platform.system().lower() == 'windows':
            result = subprocess.run([
                'powershell', '-NoProfile', '-Command',
                "Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1"
            ], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ Network info accessible")
                checks_passed += 1
            else:
                print("❌ Network info failed")
        else:
            result = subprocess.run(['ip', 'addr'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print("✅ Network info accessible")
                checks_passed += 1
            else:
                print("❌ Network info failed")
    except Exception as e:
        print(f"❌ Network metrics error: {e}")
    
    print(f"   System metrics: {checks_passed}/{total_checks} checks passed")
    return checks_passed >= total_checks // 2  # At least half should work


def check_flask_app():
    """Check Flask application setup."""
    print("\n🌐 Checking Flask application...")
    
    app_path = Path(__file__).parent / 'app' / 'app.py'
    if not app_path.exists():
        print(f"❌ Flask app not found: {app_path}")
        return False
    
    print(f"✅ Flask app found: {app_path}")
    
    # Check if we can import the app
    sys.path.insert(0, str(app_path.parent))
    try:
        import app
        print("✅ Flask app imports successfully")
        
        # Check if main routes are defined
        routes = [rule.rule for rule in app.app.url_map.iter_rules()]
        expected_routes = ['/', '/events', '/router', '/wifi', '/health']
        
        for route in expected_routes:
            if route in routes:
                print(f"✅ Route {route} defined")
            else:
                print(f"❌ Route {route} missing")
                
        return True
        
    except Exception as e:
        print(f"❌ Cannot import Flask app: {e}")
        return False


def check_powershell_module():
    """Check PowerShell module availability."""
    print("\n⚙️  Checking PowerShell module...")
    
    module_path = Path(__file__).parent / 'Start-SystemDashboard.psm1'
    if not module_path.exists():
        print(f"❌ PowerShell module not found: {module_path}")
        return False
    
    print(f"✅ PowerShell module found: {module_path}")
    
    if platform.system().lower() == 'windows':
        try:
            result = subprocess.run([
                'powershell', '-NoProfile', '-Command',
                f"Import-Module '{module_path}' -Force; Get-Command -Module Start-SystemDashboard"
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                print("✅ PowerShell module loads successfully")
                return True
            else:
                print(f"❌ PowerShell module load failed: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"❌ PowerShell module test error: {e}")
            return False
    else:
        print("⚠️  PowerShell module requires Windows to test fully")
        return True  # Assume OK on non-Windows


def main():
    """Run all validation checks."""
    print("🔍 System Dashboard Environment Validation")
    print("=" * 50)
    
    checks = [
        ("Python Environment", check_python_environment),
        ("Router Logs", check_router_logs),
        ("Windows Events", check_windows_events),
        ("System Metrics", check_system_metrics),
        ("Flask Application", check_flask_app),
        ("PowerShell Module", check_powershell_module),
    ]
    
    results = []
    for name, check_func in checks:
        try:
            result = check_func()
            results.append((name, result))
        except Exception as e:
            print(f"❌ {name} check failed with error: {e}")
            results.append((name, False))
    
    print("\n" + "=" * 50)
    print("📋 Validation Summary")
    print("=" * 50)
    
    passed = 0
    for name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status:<8} {name}")
        if result:
            passed += 1
    
    print(f"\nOverall: {passed}/{len(results)} checks passed")
    
    if passed == len(results):
        print("\n🎉 All validation checks passed! Your System Dashboard is ready to use.")
        return 0
    elif passed >= len(results) * 0.7:  # 70% pass rate
        print("\n⚠️  Most checks passed. Some optional features may not work.")
        return 0
    else:
        print("\n❌ Several validation checks failed. Please review the configuration.")
        return 1


if __name__ == '__main__':
    sys.exit(main())