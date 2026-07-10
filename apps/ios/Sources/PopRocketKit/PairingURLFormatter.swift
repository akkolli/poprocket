import Foundation

public enum PairingURLFormatter {
    public static func validationMessage(for rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Enter a bridge URL."
        }
        return normalizedDisplayURL(trimmed) == nil ? "Enter a local HTTP address or an HTTPS bridge URL." : nil
    }

    public static func normalizedDisplayURL(_ rawValue: String) -> String? {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard
            var components = URLComponents(string: withScheme),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url, (try? BridgeEndpointPolicy.validate(url)) != nil else {
            return nil
        }
        return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
