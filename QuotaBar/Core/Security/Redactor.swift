import Foundation

/// Scrubs anything that looks like a credential from text before it is logged
/// or exported. QuotaBar never reads credentials itself; this guards against
/// secrets appearing in third-party output such as CLI error messages.
enum Redactor {
    static let placeholder = "[REDACTED]"

    private static let patterns: [(pattern: String, template: String)] = [
        // JSON Web Tokens
        (#"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+"#, placeholder),
        // Provider API keys and OAuth tokens (sk-…, sk-ant-…, sess-…)
        (#"\b(sk|sess|rk|pk)-[A-Za-z0-9_-]{12,}"#, placeholder),
        // Authorization: Bearer …
        (#"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{8,}"#, "$1 \(placeholder)"),
        // key = value / "key": "value" for sensitive key names
        (#"(?i)("?[A-Za-z0-9_-]*(?:token|secret|password|passwd|api[_-]?key|cookie|authorization|session[_-]?id)[A-Za-z0-9_-]*"?\s*[:=]\s*)("[^"]*"|\S+)"#,
         "$1\(placeholder)"),
    ]

    static func redact(_ text: String) -> String {
        patterns.reduce(text) { result, entry in
            result.replacingOccurrences(of: entry.pattern, with: entry.template, options: .regularExpression)
        }
    }
}
