import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Ephemeral: no cookies, no disk cache.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.unsupportedResponse("Not an HTTP response")
        }
        return (data, http)
    }
}

/// Reads Claude usage from the Anthropic account endpoint that Claude Code's
/// own "Account & Usage" panel uses.
///
/// Opt-in. This is the only code path in QuotaBar that reads a credential or
/// uses the network: one GET to api.anthropic.com, authenticated with the
/// access token Claude Code keeps in the Keychain. The endpoint is not
/// publicly documented, so the parser accepts the shapes seen so far and
/// reports anything else as unsupported instead of guessing.
actor ClaudeAccountUsageSource {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: any ClaudeCredentialProviding
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    /// The endpoint is not meant for tight polling; never call it more often than this.
    private let minimumInterval: TimeInterval
    /// After the user declines Keychain access, do not ask again for this long.
    private let denialBackoff: TimeInterval

    private var credential: ClaudeCredential?
    private var lastUsage: ProviderUsage?
    private var lastFetch: Date?
    private var deniedUntil: Date?

    init(
        credentials: any ClaudeCredentialProviding = KeychainReader(),
        transport: any HTTPTransport = URLSessionTransport(),
        minimumInterval: TimeInterval = 120,
        denialBackoff: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.transport = transport
        self.minimumInterval = minimumInterval
        self.denialBackoff = denialBackoff
        self.now = now
    }

    /// Forgets the in-memory token and any back-off, e.g. when the user
    /// switches the source off and on again.
    func reset() {
        credential = nil
        lastUsage = nil
        lastFetch = nil
        deniedUntil = nil
    }

    func fetch() async throws -> ProviderUsage {
        let date = now()
        if let lastUsage, let lastFetch, date.timeIntervalSince(lastFetch) < minimumInterval {
            return lastUsage
        }
        if let deniedUntil, date < deniedUntil {
            throw ProviderError.permissionDenied(path: "Keychain")
        }

        let token = try await accessToken(at: date)
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200:
            let usage = try ClaudeUsageParser.parseAccountUsage(data, fetchedAt: date)
            lastUsage = usage
            lastFetch = date
            return usage
        case 401, 403:
            // Claude Code refreshes its own token; QuotaBar must not, because
            // rotating the refresh token would sign Claude Code out.
            credential = nil
            throw ProviderError.sessionExpired(tool: "Claude Code")
        case 429:
            throw ProviderError.noUsageData("Anthropic is limiting usage checks; retrying later")
        default:
            throw ProviderError.unsupportedResponse("Usage endpoint returned HTTP \(response.statusCode)")
        }
    }

    private func accessToken(at date: Date) async throws -> String {
        if let credential, !credential.isExpired(at: date) {
            return credential.accessToken
        }
        do {
            // Re-read: Claude Code may have refreshed the token since last time.
            let fresh = try await credentials.claudeCredential()
            guard !fresh.isExpired(at: date) else {
                credential = nil
                throw ProviderError.sessionExpired(tool: "Claude Code")
            }
            credential = fresh
            return fresh.accessToken
        } catch let error as ProviderError {
            if case .permissionDenied = error {
                deniedUntil = date.addingTimeInterval(denialBackoff)
            }
            throw error
        }
    }
}
