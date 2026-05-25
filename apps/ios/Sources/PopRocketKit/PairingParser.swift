import Foundation

public enum PairingParser {
    public enum ParseError: Error, Equatable {
        case invalidPayload
        case unsupportedVersion(Int)
        case expired
    }

    public static func parse(_ rawValue: String, now: Date = Date()) throws -> PairingPayload {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let data: Data
        if trimmed.hasPrefix("poprocket://pair?") {
            guard
                let components = URLComponents(string: trimmed),
                let encoded = components.queryItems?.first(where: { $0.name == "payload" })?.value,
                let decoded = Data(base64URLEncoded: encoded)
            else {
                throw ParseError.invalidPayload
            }
            data = decoded
        } else if let decoded = Data(base64URLEncoded: trimmed) {
            data = decoded
        } else if let direct = trimmed.data(using: .utf8) {
            data = direct
        } else {
            throw ParseError.invalidPayload
        }

        let payload = try PopRocketCoding.decoder.decode(PairingPayload.self, from: data)
        guard payload.version == 1 else {
            throw ParseError.unsupportedVersion(payload.version)
        }
        guard payload.expiresAt > now else {
            throw ParseError.expired
        }
        return payload
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }
        self.init(base64Encoded: base64)
    }
}
