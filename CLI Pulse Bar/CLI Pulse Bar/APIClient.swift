// This file re-exports the shared APIClient from CLIPulseCore.
// The macOS target should depend on CLIPulseCore and use its public API directly.
// This file provides typealias compatibility for any local references.

import CLIPulseCore

// No local APIClient needed — use CLIPulseCore.APIClient directly.
// If the macOS target previously used `APIClient` without module prefix,
// it will still resolve to CLIPulseCore.APIClient via the import.
