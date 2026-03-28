# CLI Pulse v0.2 Execution Plan

## Phase 1: Multi-Provider Foundation

Goal:

Make the app, backend, and helper provider-agnostic enough to support Claude, OpenRouter, and Ollama without special-case rewrites.

Tasks:

- expand provider enums and DTOs across backend and iOS
- remove hardcoded Codex/Gemini assumptions in helper sync path
- update seed and mock data for multi-provider rendering
- add provider capability placeholders
- verify backend tests, helper inspect, and iOS build

Deliverable:

- end-to-end sync and render support for at least 5 providers at the model level

## Phase 2: Project Aggregation

Goal:

Introduce project as a first-class entity.

Tasks:

- define project model in backend and iOS
- aggregate sessions by project
- add project list and project detail endpoints
- add Projects tab in iOS
- show top projects on dashboard

Deliverable:

- user can see top projects, project totals, and project-related alerts

## Phase 3: Cost Estimation

Goal:

Expose estimated cost across dashboard, providers, projects, and sessions.

Tasks:

- define cost model and precision states
- add provider pricing table or estimate rules
- aggregate session and project cost
- update app cards and charts to show cost

Deliverable:

- cost is visible and clearly labeled as exact, estimated, or unavailable

## Phase 4: Alert Engine Upgrade

Goal:

Make alerts more specific and less noisy.

Tasks:

- add rule definitions and thresholds
- add suppression or cooldown behavior
- attach source entity metadata
- update push payloads and in-app routing

Deliverable:

- alert opens directly into related provider, project, session, or device

## Phase 5: Helper Quality Upgrade

Goal:

Reduce duplicate sessions and expose collection confidence.

Tasks:

- process tree grouping
- confidence scoring
- collection metadata in sync payload
- device detail sync diagnostics

Deliverable:

- helper data is more explainable and less noisy

## Validation Checklist

- backend tests pass
- helper inspect works on local machine
- helper pair -> heartbeat -> sync smoke test passes
- iOS build succeeds
- iOS main pages render mixed-provider data
