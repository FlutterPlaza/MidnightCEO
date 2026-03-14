// =============================================================================
// MidnightCEO — Phase 4: Full-Stack Operations Type Definitions
// =============================================================================

import type { FounderDecision } from "./index";

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type OrgReviewStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "partially_approved";

export type OrgReviewTriggerType =
  | "milestone"
  | "periodic"
  | "manual"
  | "performance";

export type ToolIntegrationStatus =
  | "configured"
  | "connected"
  | "disconnected"
  | "error";

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface ARRMilestone {
  id: string;
  company_id: string;
  milestone_name: string;
  threshold_usd: number;
  achieved: boolean;
  achieved_at: string | null;
  arr_at_achievement: number | null;
  actions_triggered: Record<string, unknown> | null;
  org_review_id: string | null;
  created_at: string;
}

export interface ARRSnapshot {
  id: string;
  company_id: string;
  mrr: number;
  arr: number;
  growth_rate_wow: number | null;
  growth_rate_mom: number | null;
  churn_rate: number | null;
  net_revenue_retention: number | null;
  customer_count: number | null;
  snapshot_date: string;
  created_at: string;
}

export interface OrgReview {
  id: string;
  company_id: string;
  trigger_type: OrgReviewTriggerType;
  trigger_milestone: string | null;
  proposed_hires: Record<string, unknown>[];
  proposed_expansions: Record<string, unknown>[];
  proposed_retirements: Record<string, unknown>[];
  proposed_changes: Record<string, unknown>[];
  archiver_retrospective: string | null;
  ceo_analysis: string | null;
  status: OrgReviewStatus;
  founder_decision: FounderDecision | null;
  founder_note: string | null;
  decided_at: string | null;
  created_at: string;
}

export interface ToolIntegration {
  id: string;
  company_id: string;
  tool_slug: string;
  config: Record<string, unknown>;
  credentials_ref: string | null;
  status: ToolIntegrationStatus;
  connected_at: string | null;
  last_used_at: string | null;
  created_at: string;
}
