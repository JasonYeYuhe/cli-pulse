#if os(macOS)
import Foundation
import AppKit
import os

/// Manages Security-Scoped Bookmarks for accessing CLI tool credential files
/// outside the App Sandbox. Bookmarks are stored in the app group UserDefaults
/// so they persist across launches.
///
/// Usage:
///   1. Main app calls `requestAccess(directory:)` via NSOpenPanel
///   2. Bookmark data stored in app group
///   3. `resolveBookmark(for:)` restores access on subsequent launches
///   4. `SandboxFileAccess.read(path:)` uses this to read files
public final class BookmarkManager {
    public static let shared = BookmarkManager()

    private let logger = Logger(subsystem: "yyh.CLI-Pulse", category: "BookmarkManager")
    private let suiteName = "group.yyh.CLI-Pulse"
    private let bookmarksKey = "security_scoped_bookmarks"

    /// Currently active security-scoped resource URLs (need to be stopped when done)
    private var activeResources: [String: URL] = [:]

    /// Known directories that collectors need access to
    public struct KnownDirectory: Identifiable, Sendable {
        public let id: String
        public let path: String           // e.g. "~/.codex/"
        public let displayName: String    // e.g. "Codex CLI"
        public let detectionFile: String? // e.g. "auth.json" — nil = always show

        public var expandedPath: String {
            (realUserHome() as NSString).appendingPathComponent(
                String(path.dropFirst(2)) // drop "~/"
            )
        }

        /// Check if this directory exists on disk
        public var isInstalled: Bool {
            if let file = detectionFile {
                let filePath = (expandedPath as NSString).appendingPathComponent(file)
                return FileManager.default.fileExists(atPath: filePath)
            }
            return FileManager.default.fileExists(atPath: expandedPath)
        }
    }

    public static let knownDirectories: [KnownDirectory] = [
        KnownDirectory(id: "codex", path: "~/.codex/", displayName: "Codex CLI", detectionFile: "auth.json"),
        KnownDirectory(id: "gemini", path: "~/.gemini/", displayName: "Gemini CLI", detectionFile: "oauth_creds.json"),
        KnownDirectory(id: "claude", path: "~/.claude/", displayName: "Claude CLI", detectionFile: ".credentials.json"),
        KnownDirectory(id: "clipulse-config", path: "~/.config/clipulse/", displayName: "CLI Pulse Config", detectionFile: nil),
        KnownDirectory(id: "clipulse-data", path: "~/.clipulse/", displayName: "CLI Pulse Data", detectionFile: nil),
        KnownDirectory(id: "kilo", path: "~/.local/share/kilo/", displayName: "Kilo CLI", detectionFile: "auth.json"),
        KnownDirectory(id: "jetbrains", path: "~/Library/Application Support/JetBrains/", displayName: "JetBrains IDEs", detectionFile: nil),
    ]

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func appWillTerminate() {
        stopAccessingAll()
        logger.info("Stopped accessing all security-scoped resources on termination")
    }

    // MARK: - Bookmark Storage

    /// All stored bookmark data, keyed by directory path
    private func loadBookmarks() -> [String: Data] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: bookmarksKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        // Decode base64 bookmark data
        var result: [String: Data] = [:]
        for (key, b64) in dict {
            if let bookmarkData = Data(base64Encoded: b64) {
                result[key] = bookmarkData
            }
        }
        return result
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        var dict: [String: String] = [:]
        for (key, data) in bookmarks {
            dict[key] = data.base64EncodedString()
        }
        guard let defaults = UserDefaults(suiteName: suiteName),
              let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return }
        defaults.set(jsonData, forKey: bookmarksKey)
        defaults.synchronize()
    }

    // MARK: - Access Management

    /// Check if we have a bookmark for a directory
    public func hasAccess(to directoryPath: String) -> Bool {
        let bookmarks = loadBookmarks()
        return bookmarks[directoryPath] != nil
    }

    /// Store a bookmark after user grants access via NSOpenPanel
    public func storeBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadBookmarks()
            bookmarks[url.path] = bookmarkData
            saveBookmarks(bookmarks)
            logger.info("Stored bookmark for: \(url.path)")
        } catch {
            logger.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
        }
    }

    /// Resolve a stored bookmark and start accessing the security-scoped resource
    @discardableResult
    public func resolveBookmark(for directoryPath: String) -> URL? {
        // Already active?
        if let active = activeResources[directoryPath] {
            return active
        }

        let bookmarks = loadBookmarks()
        guard let bookmarkData = bookmarks[directoryPath] else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                logger.warning("Bookmark stale for: \(directoryPath), re-storing")
                storeBookmark(for: url)
            }

            if url.startAccessingSecurityScopedResource() {
                activeResources[directoryPath] = url
                return url
            } else {
                logger.error("Failed to start accessing security-scoped resource: \(directoryPath)")
                return nil
            }
        } catch {
            logger.error("Failed to resolve bookmark for \(directoryPath): \(error.localizedDescription)")
            // Remove invalid bookmark
            var bookmarks = loadBookmarks()
            bookmarks.removeValue(forKey: directoryPath)
            saveBookmarks(bookmarks)
            return nil
        }
    }

    /// Stop accessing all security-scoped resources
    public func stopAccessingAll() {
        for (_, url) in activeResources {
            url.stopAccessingSecurityScopedResource()
        }
        activeResources.removeAll()
    }

    /// Revoke a specific bookmark
    public func revokeAccess(for directoryPath: String) {
        if let url = activeResources.removeValue(forKey: directoryPath) {
            url.stopAccessingSecurityScopedResource()
        }
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: directoryPath)
        saveBookmarks(bookmarks)
        logger.info("Revoked bookmark for: \(directoryPath)")
    }

    /// Resolve all stored bookmarks (call on app launch)
    public func resolveAllBookmarks() {
        let bookmarks = loadBookmarks()
        for path in bookmarks.keys {
            resolveBookmark(for: path)
        }
        logger.info("Resolved \(self.activeResources.count)/\(bookmarks.count) bookmarks")
    }

    /// Get access status for all known directories
    public func accessStatus() -> [(directory: KnownDirectory, hasAccess: Bool, isInstalled: Bool)] {
        Self.knownDirectories.map { dir in
            (directory: dir, hasAccess: hasAccess(to: dir.expandedPath), isInstalled: dir.isInstalled)
        }
    }

    /// Present NSOpenPanel for user to grant access to a directory
    public func requestAccessViaPanel(directory: KnownDirectory) -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Grant CLI Pulse read access to \(directory.displayName) credentials"
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: directory.expandedPath)

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return false
        }

        storeBookmark(for: url)
        return true
    }
}

// MARK: - Real Home Directory Helper

/// Resolve the real user home directory, bypassing App Sandbox container path.
func realUserHome() -> String {
    if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
        return String(cString: home)
    }
    return NSHomeDirectory()
}
#endif
