import CryptoKit
import Foundation
import NIOCore
import NIOSSH
import Security

/// Minimal Keychain wrapper for passwords and the private key.
enum Keychain {
    static let service = "com.rashestlynx.rigpilot"

    static func passwordAccount(for host: Host) -> String { "password.\(host.id.uuidString)" }

    static func set(_ data: Data, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The app's one Ed25519 login key, created on demand and kept in the Keychain.
enum KeyManager {
    private static let account = "key.ed25519"

    static var privateKey: Curve25519.Signing.PrivateKey? {
        guard let raw = Keychain.get(account: account) else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }

    @discardableResult
    static func generate() -> Curve25519.Signing.PrivateKey {
        let key = Curve25519.Signing.PrivateKey()
        Keychain.set(key.rawRepresentation, account: account)
        return key
    }

    static func deleteKey() {
        Keychain.delete(account: account)
    }

    /// The public key as one OpenSSH line ("ssh-ed25519 AAAA... RigPilot-iPhone"),
    /// ready to paste into the server's authorized_keys file.
    static var publicKeyLine: String? {
        guard let key = privateKey else { return nil }
        var blob = Data()
        func appendString(_ bytes: Data) {
            var length = UInt32(bytes.count).bigEndian
            blob.append(Data(bytes: &length, count: 4))
            blob.append(bytes)
        }
        appendString(Data("ssh-ed25519".utf8))
        appendString(key.publicKey.rawRepresentation)
        return "ssh-ed25519 \(blob.base64EncodedString()) RigPilot-iPhone"
    }
}

/// Trust on first use: the first host key seen for a host is saved, and a different key later is refused.
enum HostKeyStore {
    private static func defaultsKey(_ host: Host) -> String { "hostkey.\(host.hostname):\(host.port)" }

    static func saved(for host: Host) -> String? {
        UserDefaults.standard.string(forKey: defaultsKey(host))
    }

    static func save(_ key: String, for host: Host) {
        UserDefaults.standard.set(key, forKey: defaultsKey(host))
    }

    static func forget(host: Host) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(host))
    }

    /// SHA256 fingerprint in the same form OpenSSH prints.
    static func fingerprint(_ openSSHLine: String) -> String {
        let parts = openSSHLine.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return openSSHLine }
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }
}

struct HostKeyChangedError: LocalizedError {
    let fingerprint: String
    var errorDescription: String? {
        "The computer's host key has CHANGED (now \(fingerprint)). This can mean someone is intercepting "
            + "the connection. If you reinstalled the SSH server, edit the host and tap \"Forget saved host key\"."
    }
}

final class TrustOnFirstUseValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let host: Host
    let onNewKey: (String) -> Void

    init(host: Host, onNewKey: @escaping (String) -> Void) {
        self.host = host
        self.onNewKey = onNewKey
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = String(openSSHPublicKey: hostKey)
        if let saved = HostKeyStore.saved(for: host) {
            if saved == line {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyChangedError(fingerprint: HostKeyStore.fingerprint(line)))
            }
        } else {
            HostKeyStore.save(line, for: host)
            onNewKey(HostKeyStore.fingerprint(line))
            validationCompletePromise.succeed(())
        }
    }
}
