/**
 * MidnightCEO Local Compute Mode — Electron Preload Script
 *
 * Exposes a safe subset of APIs to any renderer context via contextBridge.
 * Since the tray app has no renderer windows by default, this preload is
 * provided for the preferences window and any future embedded web views.
 *
 * All communication with the main process goes through ipcRenderer.invoke()
 * so that the renderer never has direct access to Node.js APIs.
 */

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("midnightceo", {
  // ---------------------------------------------------------------------------
  // Status & Info
  // ---------------------------------------------------------------------------

  /**
   * Get the current status of the local compute environment.
   * @returns {Promise<'running'|'paused'|'stopped'>}
   */
  getStatus: () => ipcRenderer.invoke("get-status"),

  /**
   * Get the number of active agent containers.
   * @returns {Promise<number>}
   */
  getAgentCount: () => ipcRenderer.invoke("get-agent-count"),

  /**
   * Get a human-readable uptime string.
   * @returns {Promise<string>}
   */
  getUptime: () => ipcRenderer.invoke("get-uptime"),

  /**
   * Get system health metrics (CPU, RAM, battery, Docker status).
   * @returns {Promise<{
   *   cpuPercent: number,
   *   ramTotalGb: number,
   *   ramUsedPercent: number,
   *   ramAvailableGb: number,
   *   batteryLevel: number|null,
   *   isCharging: boolean|null,
   *   dockerStatus: string
   * }>}
   */
  getSystemHealth: () => ipcRenderer.invoke("get-system-health"),

  // ---------------------------------------------------------------------------
  // Compute Mode
  // ---------------------------------------------------------------------------

  /**
   * Get the current compute mode.
   * @returns {Promise<'local'|'cloud'|'hybrid'>}
   */
  getComputeMode: () => ipcRenderer.invoke("get-compute-mode"),

  /**
   * Set the compute mode. Triggers container start/stop as needed.
   * @param {'local'|'cloud'|'hybrid'} mode
   * @returns {Promise<boolean>} true if mode was accepted
   */
  setComputeMode: (mode) => ipcRenderer.invoke("set-compute-mode", mode),

  // ---------------------------------------------------------------------------
  // Agent Control
  // ---------------------------------------------------------------------------

  /**
   * Open the Founder Console in the default browser.
   * @returns {Promise<void>}
   */
  openConsole: () => ipcRenderer.invoke("open-console"),

  /**
   * Start local agent containers (docker compose up).
   * @returns {Promise<void>}
   */
  startAgents: () => ipcRenderer.invoke("start-agents"),

  /**
   * Pause all running agents (docker compose pause).
   * @returns {Promise<void>}
   */
  pauseAgents: () => ipcRenderer.invoke("pause-agents"),

  /**
   * Resume paused agents (docker compose unpause).
   * @returns {Promise<void>}
   */
  resumeAgents: () => ipcRenderer.invoke("resume-agents"),

  /**
   * Stop all agents and shut down containers.
   * @returns {Promise<void>}
   */
  stopAll: () => ipcRenderer.invoke("stop-all"),

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /**
   * Check whether auto-start on login is enabled.
   * @returns {Promise<boolean>}
   */
  getAutoStart: () => ipcRenderer.invoke("get-auto-start"),

  /**
   * Enable or disable auto-start on login (installs/removes LaunchAgent).
   * @param {boolean} enabled
   * @returns {Promise<boolean>}
   */
  setAutoStart: (enabled) => ipcRenderer.invoke("set-auto-start", enabled),

  /**
   * Get all persistent settings as a plain object.
   * @returns {Promise<Record<string, any>>}
   */
  getSettings: () => ipcRenderer.invoke("get-settings"),

  /**
   * Set a single persistent setting by key.
   * @param {string} key
   * @param {any} value
   * @returns {Promise<boolean>}
   */
  setSetting: (key, value) => ipcRenderer.invoke("set-setting", key, value),

  // ---------------------------------------------------------------------------
  // Events (one-way, main -> renderer)
  // ---------------------------------------------------------------------------

  /**
   * Subscribe to status change events from the main process.
   * @param {(status: 'running'|'paused'|'stopped') => void} callback
   * @returns {() => void} Unsubscribe function
   */
  onStatusChange: (callback) => {
    const handler = (_event, status) => callback(status);
    ipcRenderer.on("status-changed", handler);
    return () => ipcRenderer.removeListener("status-changed", handler);
  },

  /**
   * Subscribe to system health update events.
   * @param {(health: object) => void} callback
   * @returns {() => void} Unsubscribe function
   */
  onHealthUpdate: (callback) => {
    const handler = (_event, health) => callback(health);
    ipcRenderer.on("health-updated", handler);
    return () => ipcRenderer.removeListener("health-updated", handler);
  },

  /**
   * Subscribe to notification events (title + body).
   * @param {(notification: {title: string, body: string}) => void} callback
   * @returns {() => void} Unsubscribe function
   */
  onNotification: (callback) => {
    const handler = (_event, notification) => callback(notification);
    ipcRenderer.on("notification", handler);
    return () => ipcRenderer.removeListener("notification", handler);
  },
});
