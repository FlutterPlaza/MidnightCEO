// =============================================================================
// MidnightCEO — Tier 1: Intelligence Layer Type Definitions
// =============================================================================

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type ImprovementCycleStatus =
  | "pending_review"
  | "approved"
  | "rejected"
  | "partially_approved";

export type ManagerDecision =
  | "approved"
  | "rejected"
  | "modified";

export type SignalType =
  | "performance_pattern"
  | "market_signal"
  | "operational_insight"
  | "growth_indicator";

export type CIReportType =
  | "competitive_landscape"
  | "market_trends"
  | "keyword_analysis"
  | "threat_assessment"
  | "opportunity_scan";

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface AgentPerformanceLog {
  id: string;
  agent_id: string;
  company_id: string;
  task_id: string | null;
  score: number;
  patterns: Record<string, unknown>[];
  feedback_signals: Record<string, unknown>;
  created_at: string;
}

export interface AgentAppendLayer {
  id: string;
  agent_id: string;
  company_id: string;
  rules: Record<string, unknown>[];
  last_cycle_at: string | null;
  manager_approved_at: string | null;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface SelfImprovementCycle {
  id: string;
  agent_id: string;
  company_id: string;
  self_review: string | null;
  proposed_revisions: Record<string, unknown>[];
  manager_id: string | null;
  manager_decision: ManagerDecision | null;
  manager_modifications: Record<string, unknown> | null;
  status: ImprovementCycleStatus;
  created_at: string;
  reviewed_at: string | null;
}

export interface GrowthProjection {
  id: string;
  company_id: string;
  horizon_days: number;
  projected_arr: number | null;
  projected_bottlenecks: Record<string, unknown>[];
  recommended_hires: Record<string, unknown>[];
  recommended_timing: Record<string, unknown>[];
  confidence: number | null;
  created_at: string;
}

export interface NetworkSignal {
  id: string;
  company_id: string;
  signal_type: SignalType;
  category: string | null;
  anonymized_value: Record<string, unknown>;
  submitted_at: string | null;
  created_at: string;
}

export interface CIReport {
  id: string;
  company_id: string;
  report_type: CIReportType;
  period_start: string | null;
  period_end: string | null;
  content: Record<string, unknown>;
  urgent_signals: Record<string, unknown>[];
  keyword_gaps: Record<string, unknown>[];
  created_at: string;
}
