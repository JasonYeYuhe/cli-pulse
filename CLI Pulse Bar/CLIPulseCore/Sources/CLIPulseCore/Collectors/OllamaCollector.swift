#if os(macOS)
import Foundation

/// Checks local Ollama server for running models and status.
///
/// Data source: `GET http://localhost:11434/api/tags` (model list)
///              `GET http://localhost:11434/api/ps`   (running models)
/// Auth: none required — local server only.
///
/// This is status-only collection: Ollama has no quota model.
/// Returns model count and running status, not quota/remaining data.
public struct OllamaCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.ollama

    public func isAvailable(config: ProviderConfig) -> Bool {
        // Quick check: see if the Ollama port is listening via a TCP connect.
        // Avoids noisy connection-refused errors when Ollama isn't running.
        let host = ProcessInfo.processInfo.environment["OLLAMA_HOST"]
            ?? "http://localhost:11434"
        guard let url = URL(string: host),
              let hostName = url.host else {
            return false
        }
        let port = url.port ?? 11434

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Set a short timeout via SO_SNDTIMEO (connect inherits this)
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, hostName == "localhost" ? "127.0.0.1" : hostName, &addr.sin_addr)

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        let baseURL = ProcessInfo.processInfo.environment["OLLAMA_HOST"]
            ?? "http://localhost:11434"

        let models = try await fetchTags(baseURL: baseURL)
        let running = (try? await fetchRunning(baseURL: baseURL)) ?? []

        return buildResult(models: models, running: running)
    }

    // MARK: - API calls

    struct OllamaModel: Sendable {
        let name: String
        let size: Int64  // bytes
    }

    private func fetchTags(baseURL: String) async throws -> [OllamaModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw CollectorError.invalidURL("\(baseURL)/api/tags")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Ollama")
        }

        return try OllamaCollector.parseTags(data)
    }

    private func fetchRunning(baseURL: String) async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/ps") else {
            throw CollectorError.invalidURL("\(baseURL)/api/ps")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }

        return try OllamaCollector.parseRunning(data)
    }

    // MARK: - Parsing (internal for testing)

    static func parseTags(_ data: Data) throws -> [OllamaModel] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw CollectorError.parseFailed("Ollama tags: no models array")
        }
        return models.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            let size = (m["size"] as? NSNumber)?.int64Value ?? 0
            return OllamaModel(name: name, size: size)
        }
    }

    static func parseRunning(_ data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }
    }

    // MARK: - Result building

    private func buildResult(models: [OllamaModel], running: [String]) -> CollectorResult {
        let statusText = running.isEmpty
            ? "\(models.count) models installed"
            : "\(running.count) running, \(models.count) installed"

        let usage = ProviderUsage(
            provider: ProviderKind.ollama.rawValue,
            today_usage: running.count,
            week_usage: models.count,
            estimated_cost_today: 0,
            estimated_cost_week: 0,
            cost_status_today: "Exact",  // Ollama is free/local
            cost_status_week: "Exact",
            quota: nil,       // No quota model
            remaining: nil,   // No quota model
            plan_type: "Local",
            reset_time: nil,
            tiers: [],        // No tiers — status only
            status_text: statusText,
            trend: [],
            recent_sessions: running,
            recent_errors: [],
            metadata: ProviderMetadata(
                display_name: "Ollama",
                category: "local",
                supports_exact_cost: false,
                supports_quota: false
            )
        )

        return CollectorResult(usage: usage, dataKind: .statusOnly)
    }
}
#endif
