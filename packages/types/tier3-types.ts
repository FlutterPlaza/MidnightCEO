// =============================================================================
// MidnightCEO — Tier 3: Experience Layer Type Definitions
// =============================================================================

// ---------------------------------------------------------------------------
// Enums / Literal Unions
// ---------------------------------------------------------------------------

export type DecisionType =
  | "strategic"
  | "operational"
  | "tactical"
  | "hiring"
  | "budget"
  | "technical";

export type EQMode =
  | "full"
  | "lite"
  | "minimal"
  | "away";

export type CustomerSignalSource =
  | "support_ticket"
  | "review"
  | "social_media"
  | "survey"
  | "churn_event"
  | "nps";

export type VoiceIntentType =
  | "query"
  | "directive"
  | "approval"
  | "status_check"
  | "escalation";

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface DecisionLedgerEntry {
  id: string;
  company_id: string;
  agent_id: string;
  decision_type: DecisionType;
  summary: string;
  full_reasoning: string | null;
  alternatives_considered: Record<string, unknown>[];
  confidence: number | null;
  context_version: number | null;
  artifacts_produced: Record<string, unknown>[];
  downstream_decisions: Record<string, unknown>[];
  still_valid: boolean;
  superseded_by: string | null;
  created_at: string;
}

export interface VoiceSession {
  id: string;
  company_id: string;
  transcript: string | null;
  intent_type: VoiceIntentType | null;
  parsed_intent: Record<string, unknown> | null;
  response_text: string | null;
  response_agent_id: string | null;
  audio_duration_seconds: number | null;
  created_at: string;
}

export interface CustomerSignal {
  id: string;
  company_id: string;
  source: CustomerSignalSource;
  tag: string;
  content: string;
  customer_id: string | null;
  churn_risk_score: number | null;
  clustered_theme: string | null;
  actioned: boolean;
  created_at: string;
}

export interface CustomerVoiceReport {
  id: string;
  company_id: string;
  period_start: string;
  period_end: string;
  themes: Record<string, unknown>;
  total_signals: number | null;
  churn_risks: number | null;
  document_id: string | null;
  created_at: string;
}

export interface EQState {
  id: string;
  company_id: string;
  opted_in: boolean;
  current_mode: EQMode;
  response_latency_avg_seconds: number | null;
  approval_speed_avg_seconds: number | null;
  last_login_hour: number | null;
  avg_session_length_seconds: number | null;
  skipped_digests: number;
  mode_changed_at: string | null;
  signals_updated_at: string | null;
  created_at: string;
}
