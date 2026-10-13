import Foundation

/// Decodes a number that a provider may send as a number or a numeric string.
struct LenientNumber: Decodable, Sendable, Equatable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self),
                  let double = Double(string.trimmingCharacters(in: CharacterSet(charactersIn: "% ").union(.whitespaces))) {
            value = double
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a number")
        }
    }
}

/// Decodes a timestamp sent as Unix epoch seconds, epoch milliseconds, or ISO 8601.
struct LenientDate: Decodable, Sendable, Equatable {
    let value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self), let date = Self.date(fromEpoch: number) {
            value = date
        } else if let string = try? container.decode(String.self), let date = Self.date(from: string) {
            value = date
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a timestamp")
        }
    }

    static func date(fromEpoch number: Double) -> Date? {
        guard number.isFinite, number > 0 else { return nil }
        // Anything this large can only be milliseconds.
        return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
    }

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if let number = Double(trimmed) {
            return date(fromEpoch: number)
        }
        if let date = try? Date(trimmed, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(trimmed, strategy: Date.ISO8601FormatStyle())
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value if it is present and well-formed; a malformed value is
    /// treated as absent instead of failing the whole document.
    func decodeLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
