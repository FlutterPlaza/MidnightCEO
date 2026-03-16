#!/usr/bin/env python3
"""
MidnightCEO — macOS Menu Bar Status App

A lightweight menu bar app built with rumps that monitors the local compute
stack (Docker containers, API health, tunnel status) and provides quick
actions for managing the MidnightCEO agent runtime.

Requirements: rumps, requests, psutil (see requirements.txt)
"""

import json
import os
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

import psutil
import requests
import rumps

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MCE_DIR = Path.home() / ".midnightceo"
MCE_COMPOSE_FILE = MCE_DIR / "docker-compose.local.yml"
MCE_ENV_FILE = MCE_DIR / ".env"
MCE_LOG_DIR = MCE_DIR / "logs"

API_HEALTH_URL = "http://127.0.0.1:8000/health"
CONSOLE_URL = "https://console.midnightceo.ai"

STATUS_CHECK_INTERVAL = 30  # seconds


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_env() -> dict:
    """Load key=value pairs from the .env file."""
    env = {}
    if MCE_ENV_FILE.exists():
        for line in MCE_ENV_FILE.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                env[key.strip()] = value.strip()
    return env


def run_cmd(args: list, timeout: int = 10) -> tuple:
    """Run a subprocess and return (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout, result.stderr
    except FileNotFoundError:
        return -1, "", "Command not found"
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"


def get_running_containers() -> list:
    """Return a list of running MidnightCEO container names."""
    rc, stdout, _ = run_cmd([
        "docker", "compose", "-f", str(MCE_COMPOSE_FILE),
        "ps", "--status", "running", "--format", "{{.Name}}",
    ])
    if rc != 0:
        return []
    return [name.strip() for name in stdout.strip().splitlines() if name.strip()]


def check_api_health() -> bool:
    """Return True if the local API is responding to health checks."""
    try:
        resp = requests.get(API_HEALTH_URL, timeout=5)
        return resp.status_code == 200
    except (requests.ConnectionError, requests.Timeout):
        return False


def check_tunnel_status() -> bool:
    """Return True if the tunnel container is running."""
    rc, stdout, _ = run_cmd([
        "docker", "ps", "--format", "{{.Names}}",
        "--filter", "name=mce-tunnel",
        "--filter", "status=running",
    ])
    return rc == 0 and "mce-tunnel" in stdout


def get_system_stats() -> dict:
    """Return current CPU and RAM usage."""
    mem = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.5)
    return {
        "cpu_percent": cpu,
        "ram_available_gb": round(mem.available / (1024 ** 3), 1),
        "ram_total_gb": round(mem.total / (1024 ** 3), 1),
    }


def report_health_to_supabase(
    company_id: str,
    supabase_url: str,
    supabase_key: str,
    containers: list,
    api_healthy: bool,
    tunnel_active: bool,
    stats: dict,
) -> None:
    """POST a health update to Supabase (fire and forget)."""
    if not all([company_id, supabase_url, supabase_key]):
        return

    url = f"{supabase_url}/rest/v1/companies?id=eq.{company_id}"
    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    payload = {
        "tunnel_active": tunnel_active,
        "local_machine_specs": {
            "cpu_percent": stats["cpu_percent"],
            "ram_available_gb": stats["ram_available_gb"],
            "ram_total_gb": stats["ram_total_gb"],
            "containers_running": len(containers),
            "api_healthy": api_healthy,
        },
    }
    try:
        requests.patch(url, headers=headers, json=payload, timeout=10)
    except Exception:
        pass  # Non-critical — will retry on next tick


# ---------------------------------------------------------------------------
# Menu bar app
# ---------------------------------------------------------------------------

class MidnightCEOApp(rumps.App):
    """macOS menu bar app for MidnightCEO Local Compute."""

    def __init__(self):
        super().__init__(
            name="MidnightCEO",
            title="\U0001f319",  # Moon icon
            quit_button=None,   # We provide our own Quit
        )

        self.env = load_env()
        self.caffeinate_proc = None

        # Menu items
        self.status_item = rumps.MenuItem("Status: checking...")
        self.agents_item = rumps.MenuItem("Agents: --")
        self.tunnel_item = rumps.MenuItem("Tunnel: --")
        self.stats_item = rumps.MenuItem("CPU: --% | RAM: --GB free")
        self.separator1 = rumps.separator
        self.open_console = rumps.MenuItem("Open Console", callback=self.on_open_console)
        self.view_logs = rumps.MenuItem("View Logs", callback=self.on_view_logs)
        self.separator2 = rumps.separator
        self.pause_item = rumps.MenuItem("Pause Agents", callback=self.on_pause)
        self.resume_item = rumps.MenuItem("Resume Agents", callback=self.on_resume)
        self.stop_item = rumps.MenuItem("Stop All", callback=self.on_stop)
        self.separator3 = rumps.separator
        self.quit_item = rumps.MenuItem("Quit MidnightCEO", callback=self.on_quit)

        self.menu = [
            self.status_item,
            self.agents_item,
            self.tunnel_item,
            self.stats_item,
            self.separator1,
            self.open_console,
            self.view_logs,
            self.separator2,
            self.pause_item,
            self.resume_item,
            self.stop_item,
            self.separator3,
            self.quit_item,
        ]

        # Start caffeinate to prevent sleep
        self._start_caffeinate()

    # ------------------------------------------------------------------
    # Caffeinate management
    # ------------------------------------------------------------------

    def _start_caffeinate(self):
        """Start caffeinate subprocess to prevent macOS from sleeping."""
        if self.caffeinate_proc is not None:
            return
        try:
            self.caffeinate_proc = subprocess.Popen(
                ["caffeinate", "-i", "-s", "-d"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

    def _stop_caffeinate(self):
        """Stop the caffeinate subprocess."""
        if self.caffeinate_proc is not None:
            try:
                self.caffeinate_proc.terminate()
                self.caffeinate_proc.wait(timeout=5)
            except Exception:
                try:
                    self.caffeinate_proc.kill()
                except Exception:
                    pass
            self.caffeinate_proc = None

    # ------------------------------------------------------------------
    # Periodic status check (every 30s)
    # ------------------------------------------------------------------

    @rumps.timer(STATUS_CHECK_INTERVAL)
    def on_tick(self, _):
        """Periodic status check — runs in background thread to avoid blocking."""
        thread = threading.Thread(target=self._update_status, daemon=True)
        thread.start()

    def _update_status(self):
        """Collect status from Docker, API, and system — update menu items."""
        try:
            containers = get_running_containers()
            api_healthy = check_api_health()
            tunnel_active = check_tunnel_status()
            stats = get_system_stats()

            container_count = len(containers)

            # Update menu items (rumps handles thread safety for title updates)
            if api_healthy and container_count > 0:
                self.status_item.title = "Status: Running"
                self.title = "\U0001f319"  # Moon
            elif container_count > 0:
                self.status_item.title = "Status: Degraded"
                self.title = "\U0001f319\u26a0"  # Moon + warning
            else:
                self.status_item.title = "Status: Stopped"
                self.title = "\U0001f319\u274c"  # Moon + X

            self.agents_item.title = f"{container_count} container(s) running"

            tunnel_label = "connected" if tunnel_active else "offline"
            self.tunnel_item.title = f"Tunnel: {tunnel_label}"

            self.stats_item.title = (
                f"CPU: {stats['cpu_percent']:.0f}% | "
                f"RAM: {stats['ram_available_gb']}GB free"
            )

            # Report health to Supabase
            report_health_to_supabase(
                company_id=self.env.get("COMPANY_ID", ""),
                supabase_url=self.env.get("SUPABASE_URL", ""),
                supabase_key=self.env.get("SUPABASE_SERVICE_ROLE_KEY", ""),
                containers=containers,
                api_healthy=api_healthy,
                tunnel_active=tunnel_active,
                stats=stats,
            )

        except Exception as exc:
            self.status_item.title = f"Status: Error ({exc})"

    # ------------------------------------------------------------------
    # Menu callbacks
    # ------------------------------------------------------------------

    def on_open_console(self, _):
        """Open the Founder Console in the default browser."""
        company_id = self.env.get("COMPANY_ID", "")
        if company_id:
            webbrowser.open(f"{CONSOLE_URL}/company/{company_id}")
        else:
            webbrowser.open(CONSOLE_URL)

    def on_view_logs(self, _):
        """Open the log directory in Finder and tail logs in Terminal."""
        log_dir = str(MCE_LOG_DIR)
        # Open log directory in Finder
        subprocess.Popen(["open", log_dir])
        # Also open Terminal with docker logs
        script = (
            f'tell application "Terminal" to do script '
            f'"docker compose -f {MCE_COMPOSE_FILE} logs -f --tail=50"'
        )
        subprocess.Popen(["osascript", "-e", script])

    def on_pause(self, _):
        """Pause agents by scaling down the API container."""
        run_cmd([
            "docker", "compose", "-f", str(MCE_COMPOSE_FILE),
            "pause", "api",
        ])
        rumps.notification(
            title="MidnightCEO",
            subtitle="Agents Paused",
            message="Agents have been paused. Use Resume to continue.",
        )

    def on_resume(self, _):
        """Resume paused agents."""
        run_cmd([
            "docker", "compose", "-f", str(MCE_COMPOSE_FILE),
            "unpause", "api",
        ])
        rumps.notification(
            title="MidnightCEO",
            subtitle="Agents Resumed",
            message="Agents are running again.",
        )

    def on_stop(self, _):
        """Stop all Docker containers."""
        run_cmd([
            "docker", "compose", "-f", str(MCE_COMPOSE_FILE),
            "down",
        ], timeout=30)
        rumps.notification(
            title="MidnightCEO",
            subtitle="Stopped",
            message="All services have been stopped.",
        )

    def on_quit(self, _):
        """Quit the menu bar app and stop caffeinate."""
        self._stop_caffeinate()
        rumps.quit_application()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app = MidnightCEOApp()
    app.run()
