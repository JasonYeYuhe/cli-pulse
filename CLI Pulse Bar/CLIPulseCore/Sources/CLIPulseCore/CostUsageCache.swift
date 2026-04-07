#if os(macOS)
import Foundation

// MARK: - Cache Types

struct CostUsageCache: Codable {
    var version: Int = 1
    var lastScanUnixMs: Int64 = 0
    /// filePath -> file usage
    var files: [String: CostUsageFileUsage] = [:]
    /// dayKey -> model -> packed usage [input, cached, output] for Codex, [input, cacheRead, cacheCreate, output, costNanos] for Claude
    var days: [String: [String: [Int]]] = [:]
}

struct CostUsageFileUsage: Codable {
    var mtimeUnixMs: Int64
    var size: Int64
    var days: [String: [String: [Int]]]
    var parsedBytes: Int64?
    var lastModel: String?
    var lastTotals: CostUsageCodexTotals?
    var sessionId: String?
}

struct CostUsageCodexTotals: Codable {
    var input: Int
    var cached: Int
    var output: Int
}

// MARK: - Cache IO

enum CostUsageCacheIO {
    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CLIPulse", isDirectory: true)
    }

    static func cacheFileURL(provider: String, cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? defaultCacheRoot()
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("\(provider.lowercased())-v2.json", isDirectory: false)
    }

    static func load(provider: String, cacheRoot: URL? = nil) -> CostUsageCache {
        let url = cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CostUsageCache.self, from: data),
              decoded.version == 1 else {
            return CostUsageCache()
        }
        return decoded
    }

    static func save(provider: String, cache: CostUsageCache, cacheRoot: URL? = nil) {
        let url = cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json")
        guard let data = try? JSONEncoder().encode(cache) else { return }
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

#endif
