import Foundation
import Security

/// The Claude Code sign-in, as far as QuotaBar needs it. Held in memory only.
struct ClaudeCredential: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date?

    func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

protocol ClaudeCredentialProviding: Sendable {
    func claudeCredential() async throws -> ClaudeCredential
}

/// Reads Claude Code's own Keychain item, read-only.
///
/// Used only when the user turns on the account usage source. macOS asks the
/// user to approve the access, because the item belongs to Claude Code.
/// The token is never written to disk, logged, or refreshed by QuotaBar.
struct KeychainReader: ClaudeCredentialProviding {
    static let claudeCodeService = "Claude Code-credentials"

    func claudeCredential() async throws -> ClaudeCredential {
        // SecItemCopyMatching blocks while the consent dialog is on screen.
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.genericPassword(service: Self.claudeCodeService) })
            }
        }
        return try Self.parseCredential(data)
    }

    static func genericPassword(service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw ProviderError.unsupportedResponse("Keychain item has no data")
            }
            return data
        case errSecItemNotFound:
            throw ProviderError.authenticationRequired(tool: "Claude Code")
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw ProviderError.permissionDenied(path: "Keychain")
        default:
            throw ProviderError.unknown("Keychain error \(status)")
        }
    }

    /// Claude Code stores `{"claudeAiOauth":{"accessToken":…,"expiresAt":<ms>,…}}`.
    static func parseCredential(_ data: Data) throws -> ClaudeCredential {
        struct Stored: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: LenientDate?

                enum CodingKeys: String, CodingKey {
                    case accessToken
                    case expiresAt
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    accessToken = try container.decode(String.self, forKey: .accessToken)
                    expiresAt = container.decodeLossy(LenientDate.self, forKey: .expiresAt)
                }
            }

            let claudeAiOauth: OAuth
        }

        guard let stored = try? JSONDecoder().decode(Stored.self, from: data),
              !stored.claudeAiOauth.accessToken.isEmpty
        else {
            // Never include the payload in the error: it contains the token.
            throw ProviderError.authenticationRequired(tool: "Claude Code")
        }
        return ClaudeCredential(accessToken: stored.claudeAiOauth.accessToken, expiresAt: stored.claudeAiOauth.expiresAt?.value)
    }
}
