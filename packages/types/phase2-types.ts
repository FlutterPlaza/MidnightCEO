// =============================================================================
// MidnightCEO — Phase 2: Hiring & Tool Permissions Type Definitions
// =============================================================================

import type { FounderDecision } from "./index";

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type HireRequestStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "deferred";

export type HireRequestPriority =
  | "low"
  | "medium"
  | "high"
  | "critical";

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface HireRequest {
  id: string;
  company_id: string;
  requested_by_agent_id: string;
  role_title: string;
  role_slug: string;
  reporting_to_agent_id: string | null;
  rationale: string;
  proposed_tool_access: string[] | null;
  proposed_persona_summary: string | null;
  first_task_queue: Record<string, unknown> | null;
  estimated_task_hours: number | null;
  priority: HireRequestPriority;
  archiver_context: string | null;
  status: HireRequestStatus;
  founder_decision: FounderDecision | null;
  founder_note: string | null;
  decided_at: string | null;
  created_at: string;
}

export interface AgentToolPermission {
  id: string;
  agent_id: string;
  company_id: string;
  tool_slug: string;
  scope: Record<string, unknown>;
  granted_at: string;
  revoked_at: string | null;
}
