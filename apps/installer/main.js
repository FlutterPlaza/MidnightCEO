/**
 * MidnightCEO Local Compute Mode — Electron Menu Bar Tray App
 *
 * This is NOT a windowed application.  It lives in the macOS menu bar as a
 * tray icon and provides quick access to agent status, controls, and the
 * Founder Console.
 *
 * On startup it:
 *  1. Reads config from ~/.midnightceo/.env
 *  2. Spawns `docker compose up -d` with the local compose file
 *  3. Starts a 60-second heartbeat loop to Supabase
 *  4. Monitors battery, CPU, RAM, and Docker health
 *  5. Provides compute mode toggling (local/cloud)
 *  6. Supports auto-start on login via macOS LaunchAgent
 */

const {
  app,
  Tray,
  Menu,
  nativeImage,
  nativeTheme,
  shell,
  dialog,
  Notification,
  ipcMain,
  systemPreferences,
} = require("electron");
const { spawn, execSync } = require("child_process");
const path = require("path");
const fs = require("fs");
const os = require("os");
const https = require("https");
const http = require("http");
const Store = require("electron-store");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CONFIG_DIR = path.join(os.homedir(), ".midnightceo");
const ENV_FILE = path.join(CONFIG_DIR, ".env");
const COMPOSE_FILE = path.join(CONFIG_DIR, "docker-compose.local.yml");
const LOG_FILE = path.join(CONFIG_DIR, "midnightceo.log");
const PLIST_NAME = "com.midnightceo.agents";
const PLIST_PATH = path.join(
  os.homedir(),
  "Library",
  "LaunchAgents",
  `${PLIST_NAME}.plist`
);
const CONSOLE_URL = "https://console.midnightceo.ai";
const HEARTBEAT_INTERVAL_MS = 60_000;
const HEALTH_CHECK_INTERVAL_MS = 30_000;
const BATTERY_WARN_THRESHOLD = 20;
const BATTERY_PAUSE_THRESHOLD = 10;

// Compute modes
const MODE_LOCAL = "local";
const MODE_CLOUD = "cloud";
const MODE_HYBRID = "hybrid";

// ---------------------------------------------------------------------------
// Persistent settings
// ---------------------------------------------------------------------------

const store = new Store({
  name: "midnightceo-settings",
  defaults: {
    computeMode: MODE_LOCAL,
    autoStartOnLogin: false,
    autoResumeOnPower: true,
    showHealthInMenu: true,
  },
});

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let tray = null;
let dockerProcess = null;
let heartbeatTimer = null;
let healthCheckTimer = null;
let startTime = null;
let agentStatus = "stopped"; // "running" | "paused" | "stopped"
let tasksCompletedToday = 0;
let agentCount = 0;
let batteryWarningShown = false;
let env = {};

// System health metrics (updated every 30 seconds)
let systemHealth = {
  cpuPercent: 0,
  ramTotalGb: 0,
  ramUsedPercent: 0,
  ramAvailableGb: 0,
  batteryLevel: null,
  isCharging: null,
  dockerStatus: "unknown",
};

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// Prevent the dock icon from appearing — we are a tray-only app
app.dock?.hide();

// Force dark mode for any UI elements (notifications, dialogs)
nativeTheme.themeSource = "dark";

app.whenReady().then(() => {
  loadEnv();
  createTray();
  startDocker();
  startHeartbeat();
  startHealthCheck();
  registerIpcHandlers();
  startTime = new Date();
  agentStatus = "running";

  // Sync auto-start setting with actual LaunchAgent state
  syncAutoStartSetting();

  log("MidnightCEO started");
});

app.on("window-all-closed", (e) => {
  // Prevent quit — tray apps have no windows
  e.preventDefault();
});

app.on("before-quit", () => {
  stopHeartbeat();
  stopHealthCheck();
  stopDocker();
  agentStatus = "stopped";
});

// ---------------------------------------------------------------------------
// Env / Config
// ---------------------------------------------------------------------------

function loadEnv() {
  try {
    if (!fs.existsSync(ENV_FILE)) {
      dialog.showErrorBox(
        "MidnightCEO",
        `Configuration not found at ${ENV_FILE}.\nPlease run the setup script first.`
      );
      app.quit();
      return;
    }

    const raw = fs.readFileSync(ENV_FILE, "utf-8");
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eqIdx = trimmed.indexOf("=");
      if (eqIdx === -1) continue;
      const key = trimmed.slice(0, eqIdx).trim();
      const value = trimmed
        .slice(eqIdx + 1)
        .trim()
        .replace(/^["']|["']$/g, "");
      env[key] = value;
    }

    log(`Loaded config: ${Object.keys(env).length} keys`);
  } catch (err) {
    log(`Failed to load env: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Tray
// ---------------------------------------------------------------------------

function createTray() {
  // Use a template image for macOS menu bar (16x16 or 18x18)
  const iconPath = path.join(__dirname, "assets", "icon.png");
  let icon;

  if (fs.existsSync(iconPath)) {
    icon = nativeImage
      .createFromPath(iconPath)
      .resize({ width: 18, height: 18 });
    icon.setTemplateImage(true);
  } else {
    // Fallback: create a tiny 18x18 empty template image
    icon = nativeImage.createEmpty();
  }

  tray = new Tray(icon);
  tray.setToolTip("MidnightCEO — Local Compute Mode");
  updateTrayMenu();
}

function updateTrayMenu() {
  if (!tray) return;

  const uptime = startTime ? formatUptime(Date.now() - startTime.getTime()) : "--";
  const currentMode = store.get("computeMode");
  const autoStart = store.get("autoStartOnLogin");
  const showHealth = store.get("showHealthInMenu");

  // Status label
  let statusLabel;
  switch (agentStatus) {
    case "running":
      statusLabel = "Running";
      break;
    case "paused":
      statusLabel = "Paused";
      break;
    default:
      statusLabel = "Stopped";
  }

  // Build the menu template
  const template = [
    // -- Header --
    {
      label: `MidnightCEO — ${statusLabel}`,
      enabled: false,
    },
    { type: "separator" },

    // -- Agent info --
    {
      label: `Agents: ${agentCount}`,
      enabled: false,
    },
    {
      label: `Uptime: ${uptime}`,
      enabled: false,
    },
    {
      label: `Tasks today: ${tasksCompletedToday}`,
      enabled: false,
    },
    { type: "separator" },
  ];

  // -- System health section --
  if (showHealth) {
    template.push({
      label: "System Health",
      enabled: false,
    });
    template.push({
      label: `  CPU:  ${systemHealth.cpuPercent.toFixed(1)}%`,
      enabled: false,
    });

    const ramUsed = systemHealth.ramTotalGb > 0
      ? (systemHealth.ramTotalGb * systemHealth.ramUsedPercent / 100).toFixed(1)
      : "?";
    template.push({
      label: `  RAM:  ${ramUsed} / ${systemHealth.ramTotalGb.toFixed(1)} GB (${systemHealth.ramUsedPercent.toFixed(0)}%)`,
      enabled: false,
    });

    if (systemHealth.batteryLevel !== null) {
      const chargingStr = systemHealth.isCharging ? " (charging)" : "";
      template.push({
        label: `  Battery: ${systemHealth.batteryLevel}%${chargingStr}`,
        enabled: false,
      });
    }

    template.push({
      label: `  Docker: ${systemHealth.dockerStatus}`,
      enabled: false,
    });

    template.push({ type: "separator" });
  }

  // -- Compute mode submenu --
  template.push({
    label: "Compute Mode",
    submenu: [
      {
        label: "Local",
        type: "radio",
        checked: currentMode === MODE_LOCAL,
        click: () => setComputeMode(MODE_LOCAL),
      },
      {
        label: "Cloud",
        type: "radio",
        checked: currentMode === MODE_CLOUD,
        click: () => setComputeMode(MODE_CLOUD),
      },
      {
        label: "Hybrid",
        type: "radio",
        checked: currentMode === MODE_HYBRID,
        click: () => setComputeMode(MODE_HYBRID),
      },
    ],
  });

  template.push({ type: "separator" });

  // -- Actions --
  template.push({
    label: "Open Founder Console",
    click: () => {
      const url = env.CONSOLE_URL || CONSOLE_URL;
      shell.openExternal(url);
    },
  });

  template.push({
    label: "View Logs",
    click: () => {
      shell.openPath(LOG_FILE);
    },
  });

  template.push({ type: "separator" });

  // -- Agent control --
  if (agentStatus === "stopped") {
    template.push({
      label: "Start Agents",
      click: () => {
        startDocker();
        agentStatus = "running";
        updateTrayMenu();
      },
    });
  } else {
    template.push({
      label: agentStatus === "paused" ? "Resume Agents" : "Pause Agents",
      click: () => {
        if (agentStatus === "paused") {
          resumeAgents();
        } else {
          pauseAgents();
        }
      },
    });

    template.push({
      label: "Stop Agents",
      click: () => {
        dialog
          .showMessageBox({
            type: "question",
            buttons: ["Cancel", "Stop"],
            defaultId: 0,
            title: "Stop MidnightCEO",
            message: "Are you sure you want to stop all agents?",
            detail:
              "Running tasks will be checkpointed and can resume later.",
          })
          .then(({ response }) => {
            if (response === 1) {
              stopDocker();
              agentStatus = "stopped";
              agentCount = 0;
              updateTrayMenu();
            }
          });
      },
    });
  }

  template.push({ type: "separator" });

  // -- Settings --
  template.push({
    label: "Start on Login",
    type: "checkbox",
    checked: autoStart,
    click: () => {
      const newVal = !autoStart;
      store.set("autoStartOnLogin", newVal);
      setAutoStart(newVal);
      updateTrayMenu();
    },
  });

  template.push({
    label: "Show Health in Menu",
    type: "checkbox",
    checked: showHealth,
    click: () => {
      store.set("showHealthInMenu", !showHealth);
      updateTrayMenu();
    },
  });

  template.push({
    label: "Preferences...",
    click: () => {
      shell.openPath(CONFIG_DIR);
    },
  });

  template.push({ type: "separator" });

  template.push({
    label: "Quit MidnightCEO",
    click: () => {
      app.quit();
    },
  });

  const contextMenu = Menu.buildFromTemplate(template);
  tray.setContextMenu(contextMenu);
}

// ---------------------------------------------------------------------------
// Compute mode management
// ---------------------------------------------------------------------------

function setComputeMode(mode) {
  const prev = store.get("computeMode");
  if (prev === mode) return;

  log(`Compute mode changed: ${prev} -> ${mode}`);
  store.set("computeMode", mode);

  // Notify Supabase of the mode change
  updateComputeModeInSupabase(mode);

  if (mode === MODE_CLOUD) {
    // Switching to cloud — stop local containers
    dialog
      .showMessageBox({
        type: "info",
        buttons: ["OK"],
        title: "Switching to Cloud Mode",
        message: "Agents are migrating to cloud compute.",
        detail:
          "Local containers will be stopped. Your agents will continue running in the cloud.",
      })
      .then(() => {
        stopDocker();
        agentStatus = "stopped";
        agentCount = 0;
        updateTrayMenu();
      });
  } else if (mode === MODE_LOCAL && agentStatus === "stopped") {
    // Switching to local — start containers
    startDocker();
    agentStatus = "running";
  }

  updateTrayMenu();
}

function updateComputeModeInSupabase(mode) {
  const supabaseUrl = env.SUPABASE_URL;
  const supabaseKey = env.SUPABASE_SERVICE_ROLE_KEY;
  const companyId = env.COMPANY_ID;

  if (!supabaseUrl || !supabaseKey || !companyId) {
    log("Compute mode update skipped — missing Supabase config");
    return;
  }

  const body = JSON.stringify({ compute_mode: mode });

  const url = new URL(
    `/rest/v1/companies?id=eq.${companyId}`,
    supabaseUrl
  );

  const options = {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      Prefer: "return=minimal",
    },
  };

  const protocol = url.protocol === "https:" ? https : http;
  const req = protocol.request(url, options, (res) => {
    if (res.statusCode >= 400) {
      log(`Compute mode update failed: HTTP ${res.statusCode}`);
    } else {
      log(`Compute mode updated to '${mode}' in Supabase`);
    }
    res.resume();
  });

  req.on("error", (err) => {
    log(`Compute mode update error: ${err.message}`);
  });

  req.write(body);
  req.end();
}

// ---------------------------------------------------------------------------
// Auto-start on login (macOS LaunchAgent)
// ---------------------------------------------------------------------------

function syncAutoStartSetting() {
  const plistExists = fs.existsSync(PLIST_PATH);
  store.set("autoStartOnLogin", plistExists);
}

function setAutoStart(enabled) {
  if (enabled) {
    installLaunchAgent();
  } else {
    uninstallLaunchAgent();
  }
}

function installLaunchAgent() {
  const appPath = process.execPath;
  const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${appPath}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>`;

  try {
    const launchAgentsDir = path.dirname(PLIST_PATH);
    fs.mkdirSync(launchAgentsDir, { recursive: true });
    fs.writeFileSync(PLIST_PATH, plistContent, "utf-8");
    execSync(`launchctl load "${PLIST_PATH}"`, { stdio: "ignore", timeout: 10_000 });
    log("LaunchAgent installed — MidnightCEO will start on login");
  } catch (err) {
    log(`Failed to install LaunchAgent: ${err.message}`);
  }
}

function uninstallLaunchAgent() {
  try {
    if (fs.existsSync(PLIST_PATH)) {
      execSync(`launchctl unload "${PLIST_PATH}"`, { stdio: "ignore", timeout: 10_000 });
      fs.unlinkSync(PLIST_PATH);
      log("LaunchAgent removed — MidnightCEO will no longer start on login");
    }
  } catch (err) {
    log(`Failed to remove LaunchAgent: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Docker management
// ---------------------------------------------------------------------------

function startDocker() {
  if (agentStatus === "paused") return;

  log("Starting Docker containers...");

  try {
    // Check if Docker is running
    execSync("docker info", { stdio: "ignore", timeout: 10_000 });
  } catch {
    log("Docker is not running. Please start Docker Desktop.");
    showNotification(
      "Docker Required",
      "Please start Docker Desktop to use MidnightCEO Local Compute Mode."
    );
    agentStatus = "stopped";
    return;
  }

  const composeFile = fs.existsSync(COMPOSE_FILE)
    ? COMPOSE_FILE
    : path.join(__dirname, "docker-compose.local.yml");

  dockerProcess = spawn(
    "docker",
    ["compose", "-f", composeFile, "up", "-d"],
    {
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, ...env },
    }
  );

  dockerProcess.stdout?.on("data", (data) => {
    log(`[docker] ${data.toString().trim()}`);
  });

  dockerProcess.stderr?.on("data", (data) => {
    log(`[docker] ${data.toString().trim()}`);
  });

  dockerProcess.on("close", (code) => {
    log(`Docker compose exited with code ${code}`);
    dockerProcess = null;
    if (code === 0) {
      log("Docker containers started successfully");
      agentStatus = "running";
      refreshAgentCount();
    } else {
      agentStatus = "stopped";
    }
    updateTrayMenu();
  });

  dockerProcess.on("error", (err) => {
    log(`Docker compose error: ${err.message}`);
    dockerProcess = null;
    agentStatus = "stopped";
    updateTrayMenu();
  });
}

function stopDocker() {
  log("Stopping Docker containers...");

  const composeFile = fs.existsSync(COMPOSE_FILE)
    ? COMPOSE_FILE
    : path.join(__dirname, "docker-compose.local.yml");

  try {
    execSync(`docker compose -f "${composeFile}" down`, {
      stdio: "ignore",
      timeout: 30_000,
      env: { ...process.env, ...env },
    });
    log("Docker containers stopped");
    agentStatus = "stopped";
  } catch (err) {
    log(`Failed to stop Docker: ${err.message}`);
  }
}

function pauseAgents() {
  log("Pausing agents...");

  const composeFile = fs.existsSync(COMPOSE_FILE)
    ? COMPOSE_FILE
    : path.join(__dirname, "docker-compose.local.yml");

  try {
    execSync(`docker compose -f "${composeFile}" pause`, {
      stdio: "ignore",
      timeout: 15_000,
      env: { ...process.env, ...env },
    });
    agentStatus = "paused";
    updateTrayMenu();
    log("Agents paused");
  } catch (err) {
    log(`Failed to pause agents: ${err.message}`);
  }
}

function resumeAgents() {
  log("Resuming agents...");

  const composeFile = fs.existsSync(COMPOSE_FILE)
    ? COMPOSE_FILE
    : path.join(__dirname, "docker-compose.local.yml");

  try {
    execSync(`docker compose -f "${composeFile}" unpause`, {
      stdio: "ignore",
      timeout: 15_000,
      env: { ...process.env, ...env },
    });
    agentStatus = "running";
    batteryWarningShown = false;
    updateTrayMenu();
    log("Agents resumed");
  } catch (err) {
    log(`Failed to resume agents: ${err.message}`);
  }
}

function refreshAgentCount() {
  try {
    const output = execSync(
      'docker ps --filter "name=midnightceo" --format "{{.Names}}"',
      { timeout: 10_000, encoding: "utf-8" }
    );
    agentCount = output.trim().split("\n").filter(Boolean).length;
    updateTrayMenu();
  } catch {
    agentCount = 0;
  }
}

// ---------------------------------------------------------------------------
// Heartbeat — keeps Supabase informed that this machine is alive
// ---------------------------------------------------------------------------

function startHeartbeat() {
  heartbeatTimer = setInterval(() => {
    sendHeartbeat();
    refreshAgentCount();
    updateTrayMenu();
  }, HEARTBEAT_INTERVAL_MS);

  // Send first heartbeat immediately
  sendHeartbeat();
}

function stopHeartbeat() {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
}

function sendHeartbeat() {
  const supabaseUrl = env.SUPABASE_URL;
  const supabaseKey = env.SUPABASE_SERVICE_ROLE_KEY;
  const companyId = env.COMPANY_ID;

  if (!supabaseUrl || !supabaseKey || !companyId) {
    log(
      "Heartbeat skipped — missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or COMPANY_ID"
    );
    return;
  }

  const now = new Date().toISOString();
  const body = JSON.stringify({
    tunnel_last_seen: now,
    tunnel_active: agentStatus === "running",
  });

  const url = new URL(
    `/rest/v1/companies?id=eq.${companyId}`,
    supabaseUrl
  );

  const options = {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      Prefer: "return=minimal",
    },
  };

  const protocol = url.protocol === "https:" ? https : http;
  const req = protocol.request(url, options, (res) => {
    if (res.statusCode >= 400) {
      log(`Heartbeat failed: HTTP ${res.statusCode}`);
    }
    res.resume(); // drain the response
  });

  req.on("error", (err) => {
    log(`Heartbeat error: ${err.message}`);
  });

  req.write(body);
  req.end();
}

// ---------------------------------------------------------------------------
// Health check — monitors Docker, CPU, RAM, and battery
// ---------------------------------------------------------------------------

function startHealthCheck() {
  healthCheckTimer = setInterval(() => {
    refreshSystemHealth();
    checkDockerHealth();
    checkBattery();
    updateTrayMenu();
  }, HEALTH_CHECK_INTERVAL_MS);

  // Run once immediately
  refreshSystemHealth();
}

function stopHealthCheck() {
  if (healthCheckTimer) {
    clearInterval(healthCheckTimer);
    healthCheckTimer = null;
  }
}

function refreshSystemHealth() {
  // CPU usage — take a quick snapshot via `top` on macOS
  try {
    const topOutput = execSync(
      "top -l 1 -n 0 -stats cpu",
      { timeout: 10_000, encoding: "utf-8" }
    );
    const cpuMatch = topOutput.match(/CPU usage:\s+([\d.]+)%\s+user,\s+([\d.]+)%\s+sys/);
    if (cpuMatch) {
      systemHealth.cpuPercent =
        parseFloat(cpuMatch[1]) + parseFloat(cpuMatch[2]);
    }
  } catch {
    // Fallback — cannot read CPU on this platform
  }

  // RAM usage via vm_stat (macOS) or fallback
  try {
    const totalBytes = os.totalmem();
    const freeBytes = os.freemem();
    systemHealth.ramTotalGb = totalBytes / (1024 ** 3);
    systemHealth.ramAvailableGb = freeBytes / (1024 ** 3);
    systemHealth.ramUsedPercent =
      ((totalBytes - freeBytes) / totalBytes) * 100;
  } catch {
    // os module should always work, but guard anyway
  }

  // Battery
  try {
    const output = execSync("pmset -g batt", {
      timeout: 5_000,
      encoding: "utf-8",
    });
    const match = output.match(/(\d+)%/);
    if (match) {
      systemHealth.batteryLevel = parseInt(match[1], 10);
    }
    systemHealth.isCharging =
      output.includes("AC Power") || output.includes("charging");
  } catch {
    systemHealth.batteryLevel = null;
    systemHealth.isCharging = null;
  }
}

function checkDockerHealth() {
  try {
    execSync("docker info", { stdio: "ignore", timeout: 5_000 });
    systemHealth.dockerStatus = "running";
  } catch {
    systemHealth.dockerStatus = "stopped";
    if (agentStatus === "running") {
      log("Docker is not responding — containers may be down");
      showNotification(
        "Docker Issue",
        "Docker is not responding. Your agents may have stopped."
      );
    }
  }
}

function checkBattery() {
  const batteryLevel = systemHealth.batteryLevel;
  const isCharging = systemHealth.isCharging;

  if (batteryLevel === null) return;

  if (
    !isCharging &&
    batteryLevel <= BATTERY_PAUSE_THRESHOLD &&
    agentStatus === "running"
  ) {
    log(`Battery critically low (${batteryLevel}%) — auto-pausing agents`);
    showNotification(
      "Battery Critical",
      `Battery at ${batteryLevel}%. Agents have been paused to conserve power.`
    );
    pauseAgents();
  } else if (
    !isCharging &&
    batteryLevel <= BATTERY_WARN_THRESHOLD &&
    !batteryWarningShown &&
    agentStatus === "running"
  ) {
    log(`Battery low (${batteryLevel}%) — warning`);
    showNotification(
      "Low Battery",
      `Battery at ${batteryLevel}%. Consider plugging in or agents will pause at ${BATTERY_PAUSE_THRESHOLD}%.`
    );
    batteryWarningShown = true;
  }

  // Auto-resume if plugged in and was auto-paused
  if (isCharging && agentStatus === "paused" && store.get("autoResumeOnPower")) {
    log("Power connected — resuming agents");
    resumeAgents();
  }
}

// ---------------------------------------------------------------------------
// IPC handlers — used by preload.js / renderer
// ---------------------------------------------------------------------------

function registerIpcHandlers() {
  ipcMain.handle("get-status", () => agentStatus);

  ipcMain.handle("get-agent-count", () => agentCount);

  ipcMain.handle("get-uptime", () => {
    return startTime ? formatUptime(Date.now() - startTime.getTime()) : "--";
  });

  ipcMain.handle("get-system-health", () => ({ ...systemHealth }));

  ipcMain.handle("get-compute-mode", () => store.get("computeMode"));

  ipcMain.handle("set-compute-mode", (_event, mode) => {
    if ([MODE_LOCAL, MODE_CLOUD, MODE_HYBRID].includes(mode)) {
      setComputeMode(mode);
      return true;
    }
    return false;
  });

  ipcMain.handle("open-console", () => {
    const url = env.CONSOLE_URL || CONSOLE_URL;
    shell.openExternal(url);
  });

  ipcMain.handle("pause-agents", () => pauseAgents());

  ipcMain.handle("resume-agents", () => resumeAgents());

  ipcMain.handle("start-agents", () => {
    startDocker();
    agentStatus = "running";
    updateTrayMenu();
  });

  ipcMain.handle("stop-all", () => {
    stopDocker();
    agentStatus = "stopped";
    agentCount = 0;
    updateTrayMenu();
  });

  ipcMain.handle("get-auto-start", () => store.get("autoStartOnLogin"));

  ipcMain.handle("set-auto-start", (_event, enabled) => {
    store.set("autoStartOnLogin", enabled);
    setAutoStart(enabled);
    return true;
  });

  ipcMain.handle("get-settings", () => store.store);

  ipcMain.handle("set-setting", (_event, key, value) => {
    store.set(key, value);
    updateTrayMenu();
    return true;
  });
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function formatUptime(ms) {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days}d ${hours % 24}h`;
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  if (minutes > 0) return `${minutes}m`;
  return `${seconds}s`;
}

function showNotification(title, body) {
  if (Notification.isSupported()) {
    new Notification({ title, body }).show();
  }
}

function log(message) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${message}\n`;

  // Write to log file
  try {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
    fs.appendFileSync(LOG_FILE, line);
  } catch {
    // Logging failure should not crash the app
  }

  // Also print to console for development
  if (process.env.NODE_ENV === "development") {
    process.stdout.write(line);
  }
}
