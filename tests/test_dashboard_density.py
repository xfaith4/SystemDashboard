import contextlib
import functools
import http.server
import io
import json
import socketserver
import threading
from pathlib import Path
from urllib.parse import urlparse

import pytest

pytest.importorskip("playwright.sync_api")
from playwright.sync_api import sync_playwright


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        return


def start_static_server(root):
    handler = functools.partial(QuietHandler, directory=str(root))
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    host, port = httpd.server_address
    return httpd, thread, f"http://{host}:{port}/index.html"


@pytest.fixture(scope="session")
def static_server():
    root = Path(__file__).resolve().parents[1] / "wwwroot"
    httpd, thread, url = start_static_server(root)
    try:
        yield url
    finally:
        with contextlib.suppress(Exception):
            httpd.shutdown()
        with contextlib.suppress(Exception):
            thread.join(timeout=2)


def make_scenario(empty=False):
    counter = {"n": 0}

    def metrics():
        counter["n"] += 1
        cpu = 42 + (counter["n"] % 5)
        mem_pct = 0.48 + (counter["n"] % 3) * 0.01
        net_in = 200000 + counter["n"] * 1500
        net_out = 120000 + counter["n"] * 900
        return {
            "Time": "2026-01-04T00:00:00Z",
            "ComputerName": "MockHost",
            "CPU": {"Pct": cpu},
            "Memory": {"TotalGB": 16, "FreeGB": 8, "UsedGB": 8, "Pct": mem_pct},
            "Disk": [
                {"Drive": "C", "TotalGB": 500, "UsedGB": 350, "UsedPct": 0.7},
                {"Drive": "D", "TotalGB": 1000, "UsedGB": 450, "UsedPct": 0.45},
            ],
            "Uptime": {"Days": 2, "Hours": 3, "Minutes": 18},
            "Events": {"Warnings": [], "Errors": []},
            "Network": {
                "Usage": [
                    {
                        "Adapter": "Ethernet",
                        "BytesSentPerSec": net_out,
                        "BytesRecvPerSec": net_in,
                    }
                ],
                "LatencyMs": 14,
                "LatencyTarget": "1.1.1.1",
            },
            "Processes": [
                {
                    "Name": "chrome",
                    "CPU": 120.4,
                    "Id": 2340,
                    "WorkingSet64": 480 * 1024 * 1024,
                    "PrivateMemorySize64": 310 * 1024 * 1024,
                    "IOReadBytes": 120 * 1024 * 1024,
                    "IOWriteBytes": 42 * 1024 * 1024,
                },
                {
                    "Name": "svchost",
                    "CPU": 80.2,
                    "Id": 992,
                    "WorkingSet64": 160 * 1024 * 1024,
                    "PrivateMemorySize64": 110 * 1024 * 1024,
                    "IOReadBytes": 20 * 1024 * 1024,
                    "IOWriteBytes": 6 * 1024 * 1024,
                },
            ],
        }

    if empty:
        syslog_summary = {
            "total1h": 0,
            "total24h": 0,
            "topApps": [],
            "topHosts": [],
            "noisyHosts": 0,
            "bySeverity": [],
        }
        events_summary = {
            "total1h": 0,
            "total24h": 0,
            "topSources": [],
            "bySeverity": [],
        }
        syslog_recent = []
        events_recent = []
        devices_summary = []
        wifi_clients = []
    else:
        syslog_summary = {
            "total1h": 5,
            "total24h": 22,
            "topApps": [{"app": "dnsmasq", "total": 12}],
            "topHosts": [{"host": "router", "total": 9}],
            "noisyHosts": 2,
            "bySeverity": [
                {"severity": "error", "total": 6},
                {"severity": "warning", "total": 3},
                {"severity": "info", "total": 13},
            ],
        }
        events_summary = {
            "total1h": 3,
            "total24h": 11,
            "topSources": [{"source": "System", "total": 7}],
            "bySeverity": [
                {"severity": "error", "total": 4},
                {"severity": "warning", "total": 2},
                {"severity": "information", "total": 5},
            ],
        }
        syslog_recent = [
            {
                "received_utc": "2026-01-04T00:04:00Z",
                "source_host": "router",
                "app_name": "dnsmasq",
                "severity_label": "error",
                "category": "dns",
                "message": "DNS request failed",
            },
            {
                "received_utc": "2026-01-04T00:03:00Z",
                "source_host": "router",
                "app_name": "kernel",
                "severity_label": "warning",
                "category": "network",
                "message": "Transient drop detected",
            },
        ]
        events_recent = [
            {
                "occurred_at": "2026-01-04T00:02:30Z",
                "source": "System",
                "severity": "error",
                "category": "system",
                "subject": "Service Control Manager",
                "message": "Service stopped unexpectedly",
            }
        ]
        devices_summary = []
        wifi_clients = []

    router_kpis = {
        "updated_utc": "2026-01-04T00:05:00Z",
        "kpis": {
            "total_drop": 4,
            "igmp_drops": 1,
            "roam_kicks": 0,
            "rstats_errors": 0,
            "dnsmasq_sigterm": 0,
            "avahi_sigterm": 0,
            "upnp_shutdowns": 0,
        },
    }

    return {
        "metrics": metrics,
        "syslog_summary": syslog_summary,
        "events_summary": events_summary,
        "syslog_recent": syslog_recent,
        "events_recent": events_recent,
        "router_kpis": router_kpis,
        "devices_summary": devices_summary,
        "wifi_clients": wifi_clients,
    }


def install_routes(page, scenario):
    def fulfill_json(route, payload):
        route.fulfill(
            status=200,
            content_type="application/json",
            body=json.dumps(payload),
        )

    def handle_api(route, request):
        path = urlparse(request.url).path
        if path.endswith("/api/syslog/summary"):
            return fulfill_json(route, scenario["syslog_summary"])
        if path.endswith("/api/events/summary"):
            return fulfill_json(route, scenario["events_summary"])
        if path.endswith("/api/syslog/recent"):
            return fulfill_json(route, scenario["syslog_recent"])
        if path.endswith("/api/events/recent"):
            return fulfill_json(route, scenario["events_recent"])
        if path.endswith("/api/router/kpis"):
            return fulfill_json(route, scenario["router_kpis"])
        if path.endswith("/api/devices/summary"):
            return fulfill_json(route, scenario["devices_summary"])
        if path.endswith("/api/lan/clients"):
            return fulfill_json(route, scenario["wifi_clients"])
        if path.endswith("/api/timeline"):
            return fulfill_json(route, [])
        if path.endswith("/api/syslog/timeline"):
            return fulfill_json(route, [])
        if path.endswith("/api/events/timeline"):
            return fulfill_json(route, [])
        if path.endswith("/api/health"):
            return fulfill_json(route, {"ok": True})
        if path.endswith("/api/status"):
            return fulfill_json(route, {"listener": {"prefix": "http://localhost:15000/", "uptime_seconds": 3600}})
        if path.endswith("/api/layouts"):
            if request.method == "POST":
                return fulfill_json(route, {"active": "Default", "layouts": {}})
            return fulfill_json(route, {"active": "Default", "layouts": {}})
        if path.startswith("/api/lan/"):
            return fulfill_json(route, {"devices": []})
        return route.fulfill(status=200, content_type="application/json", body="{}")

    def handle_metrics(route, request):
        return fulfill_json(route, scenario["metrics"]())

    page.route("**/metrics**", handle_metrics)
    page.route("**/api/**", handle_api)


def get_activity_ratio(png_bytes, threshold=12):
    from PIL import Image

    image = Image.open(io.BytesIO(png_bytes)).convert("L")
    pixels = image.load()
    width, height = image.size
    active = 0
    total = (width - 1) * (height - 1)
    for y in range(height - 1):
        for x in range(width - 1):
            diff = abs(pixels[x, y] - pixels[x + 1, y]) + abs(pixels[x, y] - pixels[x, y + 1])
            if diff > threshold:
                active += 1
    return active / total if total else 0


def test_kpi_count_above_fold(static_server):
    scenario = make_scenario(empty=False)
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch()
        except Exception as exc:  # pragma: no cover - env dependent
            pytest.skip(f"Playwright browser unavailable: {exc}")
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        install_routes(page, scenario)
        page.goto(static_server, wait_until="domcontentloaded")
        page.wait_for_function("document.querySelector('#kpi-cpu-value') && document.querySelector('#kpi-cpu-value').textContent !== '--'")
        tiles = page.query_selector_all(".kpi-tile")
        visible = 0
        for tile in tiles:
            box = tile.bounding_box()
            if box and box["y"] + box["height"] <= 1080:
                visible += 1
        assert visible >= 8
        browser.close()


def test_empty_panels_collapsed(static_server):
    scenario = make_scenario(empty=True)
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch()
        except Exception as exc:  # pragma: no cover - env dependent
            pytest.skip(f"Playwright browser unavailable: {exc}")
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        install_routes(page, scenario)
        page.goto(static_server, wait_until="domcontentloaded")
        page.wait_for_function("document.body.dataset.showEmpty === 'false'")
        page.wait_for_function("document.querySelector('[data-layout-id=\"wifi-clients\"]').classList.contains('is-empty')")
        wifi_card = page.locator('[data-layout-id="wifi-clients"]')
        box = wifi_card.bounding_box()
        assert box is None or box["height"] <= 40
        browser.close()


def test_density_activity_ratio(static_server):
    scenario = make_scenario(empty=False)
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch()
        except Exception as exc:  # pragma: no cover - env dependent
            pytest.skip(f"Playwright browser unavailable: {exc}")
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        install_routes(page, scenario)
        page.goto(static_server, wait_until="domcontentloaded")
        page.wait_for_function("document.querySelectorAll('#alerts-list li').length > 0")
        page.wait_for_timeout(6000)
        screenshot = page.screenshot(full_page=False)
        ratio = get_activity_ratio(screenshot, threshold=12)
        assert ratio >= 0.22
        browser.close()
