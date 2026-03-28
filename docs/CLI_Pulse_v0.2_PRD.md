# CLI Pulse v0.2 PRD

## 1. Document Info

- Product Name: CLI Pulse
- Document Type: Product Requirements Document
- Version: v0.2
- Stage: Post-MVP
- Platforms: iPhone first, compatible with current backend and helper architecture
- Target Users: heavy AI CLI / Agent users, multi-provider developers, multi-device operators

## 2. Version Goal

CLI Pulse v0.2 focuses on turning the current MVP from a basic mobile dashboard into a reliable multi-provider observability product.

This version prioritizes five areas:

1. Provider Adapter Layer
2. Project-level aggregation
3. Cost estimation
4. Stronger alert rules
5. Better helper-side collection

The goal is not to expand into remote control or teamwork yet. The goal is to make the monitoring data more accurate, more actionable, and more extensible.

## 3. Problems To Solve

Current MVP already supports dashboard, devices, sessions, alerts, onboarding, helper sync, and live backend integration. The next major gaps are:

- provider support is still too narrow and partially hardcoded
- users cannot answer "which project is spending the most"
- usage numbers do not yet translate into cost
- alerts are useful but still too coarse
- helper data is still partly heuristic and can overcount subprocesses

## 4. Product Objectives

### 4.1 Primary Objectives

- Support more providers without redesigning the app each time
- Introduce project as a first-class entity in the data model and UI
- Let users understand both usage and estimated spend
- Detect abnormal states earlier and with less noise
- Improve trust in helper-collected session data

### 4.2 Non-Objectives

The following remain out of scope for v0.2:

- remote shell or code execution
- team workspace and RBAC
- billing and payment workflows
- plugin marketplace
- full data export suite beyond basic CSV

## 5. Scope

### 5.1 In Scope

- unified provider adapter layer
- initial support for Claude, OpenRouter, and Ollama in the model and sync path
- project aggregation pages and summary cards
- estimated cost metrics
- richer alert engine and thresholds
- helper process aggregation improvements
- history views for usage and cost
- push deep links into related entities

### 5.2 Out of Scope

- multi-user collaboration
- Slack / Telegram integrations
- widgets and live activities
- desktop or iPad-specific UX
- remote action controls

## 6. Core Requirements

### 6.1 Provider Adapter Layer

#### Goal

Move provider support from ad hoc hardcoding to a stable internal contract.

#### Requirements

- Add a provider adapter abstraction in backend and helper
- Normalize provider metadata into one schema:
  - provider key
  - display name
  - status
  - quota
  - remaining
  - request count
  - token or usage count
  - estimated cost
  - sync source
- Support these providers in v0.2:
  - Codex
  - Gemini
  - Claude
  - OpenRouter
  - Ollama
- Allow providers to report partial fields when quota or cost is unavailable
- Keep app UI provider-agnostic, so new providers can render without adding a new page type

#### Success Criteria

- adding a new provider should require only adapter and config work
- provider list and provider detail pages should render mixed capabilities cleanly

### 6.2 Project Aggregation

#### Goal

Let users understand usage and failures by project, not only by provider or device.

#### Requirements

- Add `Project` as a first-class model across backend and app
- Sessions must resolve to a project key
- Dashboard should show:
  - top projects today
  - project usage distribution
  - projects with active sessions
  - projects with alerts
- Add project list page with:
  - project name
  - total usage today
  - estimated cost today
  - active sessions
  - devices involved
  - primary provider
  - alert count
- Add project detail page with:
  - usage trend
  - cost trend
  - provider distribution
  - sessions
  - related devices
  - recent errors

#### Success Criteria

- user can identify highest-spend project within 10 seconds
- user can identify which project generated an alert without manual cross-checking

### 6.3 Cost Estimation

#### Goal

Convert raw usage into decision-useful cost signals.

#### Requirements

- Add per-provider cost estimation rules
- Store estimated unit cost and estimated total cost
- Support both:
  - session-level estimated cost
  - project-level estimated cost
  - provider-level estimated cost
  - daily and weekly totals
- Mark estimated cost clearly when based on heuristics
- Support provider-specific fallback states:
  - exact
  - estimated
  - unavailable

#### UI Requirements

- dashboard summary should include `today estimated cost`
- provider page should show `today`, `week`, and `average per request`
- project page should show `today cost` and `trend`
- session detail should show estimated cost breakdown when available

#### Success Criteria

- user can compare relative spend across providers and projects
- unavailable pricing data should not break charts or totals

### 6.4 Alert Engine Upgrade

#### Goal

Improve alert quality, coverage, and routing.

#### New Alert Types

- repeated sync failure
- session inactive too long
- session usage spike
- project budget exceeded
- provider quota below threshold
- provider auth expired
- helper stale heartbeat
- provider unavailable

#### Requirements

- Allow per-user thresholds for usage and budget rules
- Add alert suppression window to reduce duplicate pushes
- Group repeated alerts by source entity when possible
- Every alert must link to exactly one primary source:
  - provider
  - project
  - session
  - device
- Push notification should deep link to the related page in app

#### Success Criteria

- duplicate alert noise decreases
- user can open a push and land on the correct detail page

### 6.5 Helper Collection Upgrade

#### Goal

Make helper-collected data more stable and more representative of real CLI or agent usage.

#### Requirements

- Collapse obvious subprocess noise into one logical session when possible
- Improve process matching for:
  - Codex
  - Gemini
  - Claude
  - OpenRouter clients
  - Ollama local model runs
- Keep a distinction between:
  - confirmed provider match
  - inferred provider match
- Add collection metadata:
  - collection method
  - confidence
  - raw command
- Track helper sync stats:
  - collection duration
  - sync duration
  - last error
  - retry count
- Allow future provider-specific collectors without changing top-level helper commands

#### Success Criteria

- helper reports fewer duplicate sessions
- device detail page exposes why collected data may be estimated or partial

## 7. UX Changes

### 7.1 Dashboard

Add:

- today estimated cost
- top projects card
- project budget risk card
- provider cost split
- stronger risk summary labels

### 7.2 Tabs

Recommended tab structure for v0.2:

- Home
- Projects
- Sessions
- Devices
- Alerts
- Settings

Provider detail remains accessible from Home or Projects, instead of requiring a top-level tab.

### 7.3 Alerts

Add:

- grouped alert rows
- source entity chips
- push deep link handling
- suppression / repeated alert indicators

## 8. Data Model Changes

### 8.1 New or Expanded Entities

- ProviderAdapterState
- ProjectRecord
- CostEstimate
- AlertRule
- HelperCollectionMetadata

### 8.2 Important Relationships

- one project has many sessions
- one session belongs to one provider and one project
- one device can host sessions from many projects
- one alert must point to one primary entity

## 9. API Requirements

### 9.1 New Endpoints

- `GET /v1/projects`
- `GET /v1/projects/{project_id}`
- `GET /v1/costs/summary`
- `GET /v1/providers/adapters`
- `PUT /v1/alerts/rules`

### 9.2 Updated Endpoints

- dashboard summary returns project and cost cards
- provider responses include cost fields and capability metadata
- session responses include collection confidence and cost
- device responses include helper sync stats
- alert responses include source entity link fields

## 10. Backend Requirements

- move provider-specific logic behind adapter interfaces
- keep user/device isolation intact
- support partial provider capability sets
- preserve current SQLite path for development
- design storage so a future move to normalized tables is possible without changing the app contract

## 11. iOS Requirements

- add Projects feature module
- update Dashboard cards for cost and project views
- support provider capability-dependent rendering
- add deep link routing for alerts
- expose data confidence and estimated labels in the UI

## 12. Helper Requirements

- retain current `pair`, `heartbeat`, `sync`, and `inspect` commands
- expand sync payload with:
  - provider capability data
  - project grouping data
  - cost estimate metadata
  - collection confidence
- keep helper install and onboarding flow simple enough for a sub-3-minute setup

## 13. Non-Functional Requirements

### 13.1 Performance

- dashboard load target remains under 2 seconds on normal network
- project list and provider list should render without visible lag at 1000+ records aggregated server-side
- helper collection should complete in under 5 seconds on a normal developer workstation

### 13.2 Reliability

- alert suppression must be deterministic
- partial provider failure should not break dashboard summary
- helper sync should tolerate one provider collector failing while others continue

### 13.3 Security

- no provider secret should be sent to the phone
- helper continues to use short-lived pairing and token-based auth
- all data returned by project, provider, session, and device APIs must remain owner-scoped

## 14. Metrics

### 14.1 Product Metrics

- project page adoption
- average alerts opened per weekly active user
- percentage of users who enable cost view
- percentage of users with 3+ providers connected

### 14.2 Technical Metrics

- helper session de-duplication rate
- alert duplication rate
- provider sync coverage rate
- cost estimation coverage rate
- deep link open success rate

## 15. Release Plan

### Phase 1

- provider adapter abstraction
- model expansion for Claude / OpenRouter / Ollama
- helper collection metadata

### Phase 2

- project aggregation backend and APIs
- cost estimation backend
- updated dashboard and project UI

### Phase 3

- alert engine upgrade
- push deep links
- helper aggregation improvements and stabilization

## 16. Recommended Build Order

1. Refactor provider and project models across backend, helper, and iOS
2. Introduce project and cost aggregation in backend
3. Upgrade helper collection and provider matching
4. Add alert rules and suppression
5. Ship iOS project views, cost cards, and deep link handling

## 17. Definition Of Done

CLI Pulse v0.2 is complete when:

- the product can display mixed-provider data including Claude
- project pages exist and are backed by real backend data
- estimated cost appears across dashboard, project, provider, and session views
- alerts can open directly into the relevant destination
- helper sync exposes collection confidence and fewer duplicate sessions than v0.1
