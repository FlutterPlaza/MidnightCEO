// =============================================================================
// MidnightCEO — Phase 3: Runtime Operations Type Definitions
// =============================================================================

import type { FounderDecision } from "./index";

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type GateType =
  | "spend"
  | "external_action"
  | "hire"
  | "data_access"
  | "escalation";

export type GateUrgency =
  | "low"
  | "medium"
  | "high"
  | "critical";

export type GateStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "expired";

export type ScheduleMode =
  | "scheduled"
  | "always_on"
  | "on_demand"
  | "paused";

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface PermissionGateRequest {
  id: string;
  company_id: string;
  agent_id: string;
  task_id: string | null;
  gate_type: GateType;
  gate_category: string | null;
  task_summary: string;
  archiver_context: string | null;
  urgency: GateUrgency;
  status: GateStatus;
  founder_decision: FounderDecision | null;
  founder_note: string | null;
  temporal_signal_id: string | null;
  created_at: string;
  decided_at: string | null;
}

export interface Digest {
  id: string;
  company_id: string;
  generated_by: string;
  period_start: string;
  period_end: string;
  needs_attention: Record<string, unknown>[];
  completed_items: Record<string, unknown>[];
  archiver_highlights: Record<string, unknown>[];
  arr_progress: Record<string, unknown> | null;
  read_at: string | null;
  created_at: string;
}

export interface ActiveHours {
  start: string;
  end: string;
  timezone: string;
}

export interface AgentSchedule {
  id: string;
  agent_id: string;
  company_id: string;
  mode: ScheduleMode;
  active_hours: ActiveHours;
  updated_at: string;
}

export interface TaskDependency {
  id: string;
  task_id: string;
  depends_on_task_id: string;
  depends_on_agent_id: string | null;
  description: string | null;
  resolved: boolean;
  resolved_at: string | null;
  created_at: string;
}
