"""SystemDashboard Flask application package."""

from importlib import import_module, reload

# Load the actual implementation module once and delegate attribute access to it.
try:
    _app_module = import_module(".app", __name__)
    _app_module = reload(_app_module)
except (ImportError, ModuleNotFoundError) as exc:  # pragma: no cover - import failure path
    raise ImportError("Failed to import SystemDashboard app module") from exc


def __getattr__(name):
    try:
        return getattr(_app_module, name)
    except AttributeError as exc:
        raise AttributeError(f"module 'app' has no attribute '{name}' (delegated)") from exc


def __dir__():
    return sorted(dir(_app_module))


# Preserve any explicit export list defined in the implementation module
app = _app_module.app
__all__ = sorted(set(getattr(_app_module, "__all__", []) + ['app']))
