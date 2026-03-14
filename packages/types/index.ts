// =============================================================================
// MidnightCEO — Shared Type Definitions
// =============================================================================

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type CompanyStatus =
  | "bootstrapping"
  | "active"
  | "paused"
  | "archived";

export type NamingStyle =
  | "invented"
  | "descriptive"
  | "metaphorical"
  | "founder-chosen";

export type AgentRole =
  | "ceo"
  | "cto"
  | "archiver"
  | "supervisor"
  | "engineer"
  | "designer"
  | "marketer"
  | "analyst";

export type AgentStatus =
  | "idle"
  | "working"
  | "waiting"
  | "error"
  | "disabled";

export type MessageType =
  | "directive"
  | "report"
  | "question"
  | "answer"
  | "broadcast"
  | "system";

export type DocumentStatus =
  | "draft"
  | "review"
  | "approved"
  | "archived";

export type RelevanceHorizon =
  | "SHORT"
  | "MEDIUM"
  | "LONG"
  | "PERMANENT";

export type TaskStatus =
  | "pending"
  | "running"
  | "completed"
  | "failed"
  | "cancelled";

export type ConfidenceLabel =
  | "high"
  | "medium"
  | "low"
  | "uncertain";

export type OverallRating =
  | "exceptional"
  | "strong"
  | "meets_expectations"
  | "needs_improvement"
  | "critical";

export type Trajectory =
  | "improving"
  | "stable"
  | "declining";

export type FounderDecision =
  | "approved"
  | "rejected"
  | "deferred"
  | "modified";

export type ProposalType =
  | "hire"
  | "fire"
  | "restructure"
  | "role_change"
  | "budget_change";

export type PerformanceTier =
  | "exceptional"
  | "strong"
  | "developing"
  | "underperforming";

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface Company {
  id: string;
  name: string;
  founder_id: string;
  idea_text: string;
  target_market: string | null;
  founder_background: string | null;
  budget_cap_usd: number | null;
  status: CompanyStatus;
  naming_style: NamingStyle;
  created_at: string;
}

export interface Agent {
  id: string;
  company_id: string;
  role: AgentRole;
  persona_prompt: string | null;
  status: AgentStatus;
  manager_id: string | null;
  created_at: string;
}

export interface AgentIdentity {
  id: string;
  agent_id: string;
  first_name: string;
  last_name: string;
  full_name: string;
  naming_style: string | null;
  communication_style: string | null;
  problem_solving: string | null;
  uncertainty_handling: string | null;
  peer_orientation: string | null;
  career_level: number;
  career_level_since: string | null;
  performance_tier: PerformanceTier;
  updated_at: string;
}

export interface Message {
  id: string;
  company_id: string;
  from_agent_id: string | null;
  to_agent_id: string | null;
  content: string;
  message_type: MessageType;
  created_at: string;
}

export interface Document {
  id: string;
  company_id: string;
  producing_agent_id: string;
  name: string;
  content: string;
  version: number;
  status: DocumentStatus;
  created_at: string;
  updated_at: string;
}

export interface ArchiverEntry {
  id: string;
  company_id: string;
  tag: string;
  summary: string;
  full_context: Record<string, unknown> | null;
  source_agent_id: string;
  confidence: number;
  relevance_horizon: RelevanceHorizon;
  reassess_at: string | null;
  dismissed_at: string | null;
  superseded_by: string | null;
  related_entries: Record<string, unknown> | null;
  is_sensitive: boolean;
  created_at: string;
  embedding: number[] | null;
}

export interface ContextVersion {
  id: string;
  company_id: string;
  version_number: number;
  snapshot: Record<string, unknown>;
  trigger_event: string | null;
  created_at: string;
}

export interface AgentTask {
  id: string;
  company_id: string;
  agent_id: string;
  task_type: string;
  task_content: Record<string, unknown>;
  status: TaskStatus;
  result: Record<string, unknown> | null;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
}

export interface AgentConfidenceLog {
  id: string;
  agent_id: string;
  task_id: string;
  score: number;
  label: ConfidenceLabel;
  inputs: Record<string, unknown> | null;
  flagged_to: string | null;
  flagged_at: string | null;
  created_at: string;
}

export interface SupervisorReview {
  id: string;
  company_id: string;
  agent_id: string;
  review_type: string;
  period_start: string;
  period_end: string;
  overall_rating: OverallRating;
  trajectory: Trajectory | null;
  content: Record<string, unknown>;
  recommendations: Record<string, unknown> | null;
  default_action_plan: Record<string, unknown> | null;
  founder_decision: FounderDecision | null;
  founder_note: string | null;
  acknowledged_at: string | null;
  created_at: string;
}

export interface PromotionReport {
  id: string;
  company_id: string;
  agent_id: string;
  from_level: number;
  to_level: number;
  rationale: string;
  what_changes: Record<string, unknown> | null;
  supervisor_id: string;
  founder_decision: FounderDecision | null;
  founder_note: string | null;
  decided_at: string | null;
  effective_at: string | null;
  created_at: string;
}

export interface PeerRecognition {
  id: string;
  company_id: string;
  from_agent_id: string;
  to_agent_id: string;
  reason: string;
  acknowledged_by_supervisor: boolean;
  surfaced_in_review: string | null;
  created_at: string;
}

export interface OrgProposal {
  id: string;
  company_id: string;
  proposed_by: string;
  proposal_type: ProposalType;
  summary: string;
  rationale: string;
  proposed_changes: Record<string, unknown>;
  archiver_context: string | null;
  founder_decision: FounderDecision | null;
  founder_note: string | null;
  decided_at: string | null;
  created_at: string;
}

// ---------------------------------------------------------------------------
// Request / Response Types
// ---------------------------------------------------------------------------

export interface CreateCompanyRequest {
  name: string;
  idea_text: string;
  target_market?: string;
  founder_background?: string;
  budget_cap_usd?: number;
  naming_style?: NamingStyle;
}

export interface SendMessageRequest {
  company_id: string;
  from_agent_id?: string;
  to_agent_id?: string;
  content: string;
  message_type: MessageType;
}

export interface ApiResponse<T = unknown> {
  success: boolean;
  data: T | null;
  error: string | null;
  timestamp: string;
}
