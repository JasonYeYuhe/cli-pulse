// This file re-exports the shared AppState from CLIPulseCore.
// The macOS target should depend on CLIPulseCore and use its public AppState directly.
// Using @_exported so all CLIPulseCore types are available without explicit import.

import CLIPulseCore

// No local AppState needed — use CLIPulseCore.AppState directly.
