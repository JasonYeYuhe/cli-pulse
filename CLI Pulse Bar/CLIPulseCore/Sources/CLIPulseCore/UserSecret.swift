import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

/// Per-device 32-byte secret used to compute HMAC-SHA256 of project paths.
///
/// The secret is generated on first use and persisted to the macOS Keychain
/// (or, on iOS / sandboxed contexts, an `~/.cli_pulse/secret.bin` file with
/// 0600 permissions). It never leaves the device — only the resulting HMACs do.
///
/// **Cross-device note**: secrets are per-device, so a user with the Python
/// helper on Linux and the Swift helper on macOS will produce different
/// project_hashes for the same path. For v2.0 we accept that yield score
/// attribution works only within sessions/commits collected by the same
/// device. Run one helper per machine.
public enum UserSecret {

    private static let keychainService = "com.clipulse.helper"
    private static let keychainAccount = "project_hash_secret"
    private static let secretBytes = 32

    /// Returns the per-device secret, generating it on first call.
    /// Throws on macOS only if the Keychain is unreachable; falls back
    /// to a file write on other platforms.
    public static func loadOrCreate() throws -> Data {
        #if os(macOS)
        if let existing = try keychainRead() { return existing }
        let secret = generateSecret()
        try keychainWrite(secret)
        return secret
        #else
        if let data = try? Data(contentsOf: secretFileURL()), data.count == secretBytes {
            return data
        }
        let secret = generateSecret()
        try writeFileSecret(secret)
        return secret
        #endif
    }

    /// Compute HMAC-SHA256 hex digest of a path with the given secret.
    /// Determinism: same secret + same path string → same hex output, matching
    /// the Python `helper/user_secret.project_hash` implementation.
    public static func projectHash(secret: Data, absolutePath: String) -> String {
        #if canImport(CryptoKit)
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(absolutePath.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback for environments without CryptoKit (shouldn't happen on supported targets)
        return ""
        #endif
    }

    // MARK: - Internal

    private static func generateSecret() -> Data {
        var bytes = Data(count: secretBytes)
        let result = bytes.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecAllocate }
            #if canImport(Security)
            return SecRandomCopyBytes(kSecRandomDefault, secretBytes, base)
            #else
            // Pseudo-random fallback (not for production use)
            for i in 0..<secretBytes { (base.assumingMemoryBound(to: UInt8.self) + i).pointee = UInt8.random(in: 0...255) }
            return errSecSuccess
            #endif
        }
        precondition(result == errSecSuccess, "Failed to generate user secret")
        return bytes
    }

    #if os(macOS)
    private static func keychainRead() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func keychainWrite(_ data: Data) throws {
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    #endif

    private static func secretFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".cli_pulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("secret.bin")
    }

    private static func writeFileSecret(_ data: Data) throws {
        let url = secretFileURL()
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
