# CLI Pulse v0.2 Technical Design

## 1. Design Goal

v0.2 should establish a stable foundation for multi-provider observability without forcing a full architecture rewrite later.

This design focuses on:

- provider extensibility
- project-level aggregation
- estimated cost computation
- stronger alert routing
- helper data quality improvements

## 2. System Boundaries

### iOS App

- renders dashboard, projects, sessions, devices, alerts, settings
- consumes backend APIs only
- does not hold provider secrets
- handles deep links from push notifications

### Backend API

- remains the source of truth
- owns provider normalization, aggregation, cost rollups, alert evaluation
- persists user, device, session, provider, project, and alert state

### Device Helper

- collects local execution signals
- performs provider inference and lightweight metadata extraction
- sends normalized sync payloads
- never exposes raw secrets to the phone

## 3. Architecture Changes

## 3.1 Provider Adapter Layer

Introduce an adapter contract in backend and helper.

Recommended interface:

- `provider_key`
- `display_name`
- `capabilities`
- `collect_usage()`
- `collect_quota()`
- `collect_cost_inputs()`
- `collect_health()`

Initial providers:

- Codex
- Gemini
- Claude
- OpenRouter
- Ollama

Key rule:

The app must render provider data through shared view models and shared DTOs. No provider-specific page type should be required.

## 3.2 Domain Model

### ProviderRecord

- id
- provider_key
- display_name
- status
- quota
- remaining
- usage_today
- usage_week
- estimated_cost_today
- estimated_cost_week
- capability_flags

### ProjectRecord

- id
- name
- normalized_key
- usage_today
- usage_week
- estimated_cost_today
- estimated_cost_week
- active_session_count
- device_count
- top_provider
- unresolved_alert_count

### SessionRecord

Extend current session model with:

- project_id or normalized project key
- cost_estimate
- collection_method
- collection_confidence

### AlertRecord

Extend with:

- source_kind
- source_id
- grouping_key
- suppression_key

## 3.3 Data Flow

1. Helper collects process and device signals.
2. Helper tags sessions with provider and project hints.
3. Backend validates ownership and stores raw sync data.
4. Backend adapters normalize provider state.
5. Backend aggregates sessions into provider and project views.
6. Backend computes estimated cost.
7. Backend evaluates alert rules.
8. App fetches summary and detail endpoints.
9. Push deep link opens the source entity page.

## 4. Storage Strategy

Current backend uses SQLite with JSON blobs per user. v0.2 should stay compatible with that, but start separating aggregation responsibilities more cleanly.

Short-term strategy:

- keep SQLite for local development
- keep current user isolation model
- continue storing aggregate snapshots
- add fields for projects, cost, capability metadata, and alert routing

Preferred future direction:

- normalize sessions
- normalize alerts
- normalize project aggregates

## 5. API Design

## 5.1 New Endpoints

- `GET /v1/projects`
- `GET /v1/projects/{project_id}`
- `GET /v1/costs/summary`
- `GET /v1/providers/adapters`
- `PUT /v1/alerts/rules`

## 5.2 DTO Changes

### Provider DTO

Add:

- `estimated_cost_today`
- `estimated_cost_week`
- `capabilities`
- `data_confidence`

### Session DTO

Add:

- `project_id`
- `project_name`
- `estimated_cost`
- `collection_method`
- `collection_confidence`

### Device DTO

Add:

- `last_collection_duration_ms`
- `last_sync_duration_ms`
- `last_helper_error`
- `retry_count`

### Alert DTO

Add:

- `source_kind`
- `source_id`
- `deep_link`

## 6. Helper Design

## 6.1 Collector Layers

Split helper collection into:

- process collector
- provider matcher
- project resolver
- alert hint generator
- sync serializer

## 6.2 Session Confidence

Confidence levels:

- high: provider matched from explicit CLI invocation
- medium: provider inferred from process tree or command path
- low: provider guessed from partial command text

## 6.3 De-duplication

De-duplicate by:

- process tree relationship
- known helper subprocess signatures
- shared command roots

## 7. Cost Estimation Design

Cost estimation should be backend-owned.

For each provider:

- allow exact pricing if available
- allow estimated pricing table
- allow unavailable state

Recommended result shape:

- `amount`
- `currency`
- `precision`
- `source`

## 8. Alert Engine Design

Rules should run after aggregation.

Each rule should define:

- condition
- threshold
- cooldown window
- severity
- source_kind
- source_id

Example rules:

- provider quota below threshold
- session usage spike vs baseline
- project budget exceeded
- helper stale heartbeat
- repeated sync failures

## 9. iOS App Design

## 9.1 New Modules

- `Projects`
- `DeepLinking`

## 9.2 Updated Modules

- `Dashboard`
- `Providers`
- `Sessions`
- `Devices`
- `Alerts`

## 9.3 UI Rules

- estimated values must be labeled clearly
- unavailable values must degrade gracefully
- alerts should show source chips
- provider views should show capability-aware sections

## 10. Rollout Strategy

### Phase 1

- expand provider models and sync payloads
- introduce capability-ready DTOs

### Phase 2

- add project aggregation and cost rollups

### Phase 3

- add alert engine upgrades and deep links

## 11. Main Risks

- helper inference may still misclassify sessions
- provider data completeness will vary
- cost estimation can be misleading if unlabeled
- too much backend shape change can break current app views

## 12. Mitigations

- expose confidence and source fields
- keep DTO additions backward-compatible
- centralize provider normalization
- add smoke tests for sync payloads and project aggregation
