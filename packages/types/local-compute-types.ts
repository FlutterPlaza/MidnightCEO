// =============================================================================
// MidnightCEO — Local Compute Mode Type Definitions
// =============================================================================

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type ComputeMode = "cloud" | "local";

export type ComputeStatus = "online" | "offline" | "degraded";

export type DockerStatus = "running" | "stopped" | "not_installed";

export type TunnelStatus = "active" | "inactive" | "error";

// ---------------------------------------------------------------------------
// Machine Specifications
// ---------------------------------------------------------------------------

/** Static information about the local machine. */
export interface LocalMachineSpecs {
  /** Processor brand string (e.g. "Apple M2 Pro"). */
  cpu_model: string;
  /** Total physical RAM in GB. */
  ram_total_gb: number;
  /** Currently available RAM in GB. */
  ram_available_gb: number;
  /** Free space on the root partition in GB. */
  disk_free_gb: number;
  /** macOS version string (e.g. "14.2.1"). */
  macos_version: string;
}

// ---------------------------------------------------------------------------
// Health Snapshot
// ---------------------------------------------------------------------------

/** A point-in-time health reading from the local machine. */
export interface LocalHealthSnapshot {
  id: string;
  company_id: string;
  /** CPU usage percentage (0-100). */
  cpu_percent: number | null;
  /** Memory usage percentage (0-100). */
  memory_percent: number | null;
  /** Available RAM in GB. */
  memory_available_gb: number | null;
  /** Root disk usage percentage (0-100). */
  disk_percent: number | null;
  /** Battery level (0-100), or null for desktops. */
  battery_level: number | null;
  /** Whether the machine is on AC power, or null if no battery. */
  is_plugged_in: boolean | null;
  /** Number of active agent containers. */
  agent_count: number | null;
  /** Dynamic maximum agents based on available resources. */
  max_agent_count: number | null;
  /** Docker daemon status. */
  docker_status: DockerStatus | null;
  /** Cloudflare tunnel status. */
  tunnel_status: TunnelStatus | null;
  /** ISO 8601 timestamp when this snapshot was recorded. */
  created_at: string;
}

// ---------------------------------------------------------------------------
// Compute Mode Configuration
// ---------------------------------------------------------------------------

/** Full compute mode configuration stored on the companies row. */
export interface ComputeModeConfig {
  /** Current compute mode for this company. */
  compute_mode: ComputeMode;
  /** Public URL of the Cloudflare tunnel (null if cloud or not set up). */
  local_tunnel_url: string | null;
  /** Whether the tunnel process is currently running. */
  tunnel_active: boolean;
  /** ISO 8601 timestamp of the last tunnel heartbeat. */
  tunnel_last_seen: string | null;
  /** Human-friendly machine name (e.g. "Loic's MacBook Pro"). */
  local_machine_name: string | null;
  /** Machine specs snapshot taken during setup. */
  local_machine_specs: LocalMachineSpecs | null;
}

// ---------------------------------------------------------------------------
// API Request / Response Types
// ---------------------------------------------------------------------------

/** Request to enable local compute mode for a company. */
export interface EnableLocalModeRequest {
  company_id: string;
  machine_name: string;
  specs: LocalMachineSpecs;
}

/** Request to disable local compute mode (switch back to cloud). */
export interface DisableLocalModeRequest {
  company_id: string;
}

/** Response for compute mode status queries. */
export interface ComputeModeStatusResponse {
  mode: ComputeMode;
  status: ComputeStatus;
  machine_name: string | null;
  specs: LocalMachineSpecs | null;
  tunnel_url: string | null;
  tunnel_last_seen: string | null;
  latest_health: LocalHealthSnapshot | null;
}
