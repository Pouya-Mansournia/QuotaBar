import Foundation

enum ConnectionState: String, Codable, Sendable {
    case connected
    case unavailable
    case authenticationRequired
    case unsupported
    case error

    var displayName: String {
        switch self {
        case .connected: "Connected"
        case .unavailable: "Unavailable"
        case .authenticationRequired: "Authentication Required"
        case .unsupported: "Unsupported"
        case .error: "Error"
        }
    }
}

/// Everything the UI needs to render one provider.
struct ProviderSnapshot: Sendable, Equatable {
    /// Latest successful reading. Kept across failed refreshes.
    var usage: ProviderUsage?
    var state: ConnectionState = .unavailable
    var lastError: ProviderError?
    var lastAttempt: Date?
    var lastSuccess: Date?

    /// True when a reading is on screen but the most recent refresh failed.
    var isStale: Bool { usage != nil && lastError != nil }
}

enum ProviderError: Error, Equatable, Sendable {
    case cliNotInstalled(tool: String)
    case notConfigured(String)
    case authenticationRequired(tool: String)
    /// Signed in, but the tool has to renew its own session.
    case sessionExpired(tool: String)
    case noUsageData(String)
    case permissionDenied(path: String)
    case networkUnavailable
    case unsupportedResponse(String)
    case timedOut
    case unknown(String)

    /// Short, user-facing explanation. Never contains stack traces.
    var userMessage: String {
        switch self {
        case .cliNotInstalled(let tool): "\(tool) not installed"
        case .notConfigured(let hint): hint
        case .authenticationRequired(let tool): "\(tool) authentication unavailable"
        case .sessionExpired(let tool): "\(tool) sign-in expired — open \(tool) to renew it"
        case .noUsageData(let hint): hint
        case .permissionDenied(let path): path == "Keychain" ? "Keychain access was not allowed" : "Permission denied"
        case .networkUnavailable: "Network unavailable"
        case .unsupportedResponse: "Unsupported provider response"
        case .timedOut: "Unable to read usage (timed out)"
        case .unknown: "Unable to read usage"
        }
    }

    /// Extra detail for the diagnostics report only.
    var technicalDetail: String {
        switch self {
        case .permissionDenied(let path): "Permission denied reading \(path)"
        case .unsupportedResponse(let detail): "Unsupported response: \(detail)"
        case .unknown(let detail): detail
        default: userMessage
        }
    }

    var connectionState: ConnectionState {
        switch self {
        case .cliNotInstalled, .notConfigured, .noUsageData: .unavailable
        case .authenticationRequired, .sessionExpired: .authenticationRequired
        case .unsupportedResponse: .unsupported
        case .permissionDenied, .networkUnavailable, .timedOut, .unknown: .error
        }
    }

    /// Maps anything a provider can throw onto a `ProviderError`.
    static func map(_ error: Error) -> ProviderError {
        if let error = error as? ProviderError { return error }
        if let error = error as? CLIError {
            switch error {
            case .timedOut: return .timedOut
            case .launchFailed(let detail): return .unknown(detail)
            }
        }
        if error is DecodingError {
            return .unsupportedResponse(String(describing: error))
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied(path: nsError.userInfo[NSFilePathErrorKey] as? String ?? "file")
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .noUsageData("Unable to read usage")
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            return .permissionDenied(path: "file")
        }
        if nsError.domain == NSURLErrorDomain {
            return .networkUnavailable
        }
        return .unknown(nsError.localizedDescription)
    }
}
