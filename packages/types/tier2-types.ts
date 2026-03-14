// =============================================================================
// MidnightCEO — Tier 2: Autonomy Layer Type Definitions
// =============================================================================

import type { FounderDecision } from "./index";

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type SpendDecision =
  | "approved"
  | "rejected"
  | "auto_approved"
  | "deferred";

export type SpendCategory =
  | "infrastructure"
  | "tooling"
  | "marketing"
  | "freelancer"
  | "legal"
  | "other";

export type FreelancerStatus =
  | "pending_approval"
  | "sourcing"
  | "interviewing"
  | "engaged"
  | "completed"
  | "cancelled";

export type IncidentSeverity =
  | "critical"
  | "high"
  | "medium"
  | "low";

export type ComplianceFlagStatus =
  | "open"
  | "in_progress"
  | "resolved"
  | "dismissed";

export type ComplianceUrgency =
  | "low"
  | "medium"
  | "high"
  | "critical";

// ---------------------------------------------------------------------------
// Nested Types
// ---------------------------------------------------------------------------

export interface AlertThresholds {
  notify: number;
  pause: number;
  stop: number;
}

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface SpendRequest {
  id: string;
  company_id: string;
  agent_id: string;
  category: SpendCategory;
  amount_usd: number;
  description: string;
  vendor: string | null;
  recurring: boolean;
  justification: string | null;
  expected_roi: string | null;
  decision: SpendDecision | null;
  decided_by: string | null;
  decided_at: string | null;
  executed: boolean;
  executed_at: string | null;
  created_at: string;
}

export interface BudgetConfig {
  id: string;
  company_id: string;
  monthly_master_budget: number;
  category_budgets: Record<string, number>;
  auto_approve_thresholds: Record<string, number>;
  alert_thresholds: AlertThresholds;
  rollover: boolean;
  updated_at: string;
}

export interface FreelancerEngagement {
  id: string;
  company_id: string;
  requested_by: string;
  skill_required: string;
  task_description: string;
  budget_max_usd: number | null;
  deadline: string | null;
  platform: string | null;
  experience_requirements: string | null;
  status: FreelancerStatus;
  shortlist: Record<string, unknown>[];
  selected_candidate: Record<string, unknown> | null;
  quality_rating: string | null;
  total_cost: number | null;
  archiver_context: string | null;
  founder_decision: FounderDecision | null;
  created_at: string;
  completed_at: string | null;
}

export interface Incident {
  id: string;
  company_id: string;
  severity: IncidentSeverity;
  description: string;
  detected_at: string;
  classified_at: string | null;
  root_cause: string | null;
  fix_applied: string | null;
  resolved_at: string | null;
  escalated: boolean;
  escalated_at: string | null;
  postmortem_id: string | null;
  duration_minutes: number | null;
  created_at: string;
}

export interface LegalDocument {
  id: string;
  company_id: string;
  document_type: string;
  document_id: string | null;
  compliance_checks: Record<string, unknown>;
  valid_until: string | null;
  review_scheduled_at: string | null;
  created_at: string;
}

export interface ComplianceFlag {
  id: string;
  company_id: string;
  regulation: string;
  flag_type: string;
  description: string;
  urgency: ComplianceUrgency;
  status: ComplianceFlagStatus;
  resolution: string | null;
  resolved_at: string | null;
  reassess_at: string | null;
  created_at: string;
}
