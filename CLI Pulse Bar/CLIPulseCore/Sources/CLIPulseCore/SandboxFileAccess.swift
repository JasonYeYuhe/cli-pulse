#if os(macOS)
import Foundation
import os

/// Provides sandboxed file access using Security-Scoped Bookmarks.
/// Replaces direct `FileManager.default.contents(atPath:)` calls in collectors.
///
/// Usage:
///   let data = SandboxFileAccess.read(path: "/Users/jason/.codex/auth.json")
public enum SandboxFileAccess {

    private static let logger = Logger(subsystem: "yyh.CLI-Pulse", category: "SandboxFileAccess")

    /// Read a file, resolving the parent directory's bookmark if needed.
    /// Returns nil if no bookmark access is available.
    public static func read(path: String) -> Data? {
        // First try direct read (works if not sandboxed or already accessing)
        if let data = FileManager.default.contents(atPath: path) {
            return data
        }

        // Try resolving a bookmark for the parent directory
        let parentDir = (path as NSString).deletingLastPathComponent
        if let _ = BookmarkManager.shared.resolveBookmark(for: parentDir) {
            // Bookmark resolved, try reading again
            let data = FileManager.default.contents(atPath: path)
            if data == nil {
                logger.debug("Bookmark resolved for \(parentDir) but file not found: \(path)")
            }
            return data
        }

        // Try walking up to find a matching bookmark
        var dir = parentDir
        while dir.count > 1 {
            if let _ = BookmarkManager.shared.resolveBookmark(for: dir) {
                return FileManager.default.contents(atPath: path)
            }
            dir = (dir as NSString).deletingLastPathComponent
        }

        logger.debug("No bookmark available for: \(path)")
        return nil
    }

    /// Write data to a file, resolving the parent directory's bookmark if needed.
    public static func write(data: Data, to path: String) -> Bool {
        let parentDir = (path as NSString).deletingLastPathComponent

        // Ensure parent directory bookmark is resolved
        let _ = BookmarkManager.shared.resolveBookmark(for: parentDir)

        // Try writing
        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            logger.error("Failed to write to \(path): \(error.localizedDescription)")
            return false
        }
    }

    /// Check if a file exists, resolving bookmarks if needed.
    public static func fileExists(at path: String) -> Bool {
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
        // Try with bookmark
        let parentDir = (path as NSString).deletingLastPathComponent
        if let _ = BookmarkManager.shared.resolveBookmark(for: parentDir) {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }
}
#endif
