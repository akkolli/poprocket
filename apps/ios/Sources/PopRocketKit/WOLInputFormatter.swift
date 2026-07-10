import Foundation

public enum WOLInputFormatter {
    public static func normalizedMACAddress(_ value: String) -> String? {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard compact.count == 12,
              compact.unicodeScalars.allSatisfy({ hex.contains($0) })
        else {
            return nil
        }
        let characters = Array(compact)
        let bytes = stride(from: 0, to: characters.count, by: 2).map { index in
            String(characters[index..<(index + 2)])
        }
        return bytes.joined(separator: ":")
    }

    public static func isValidIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard !part.isEmpty, let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(part) == String(number)
        }
    }

    public static func suggestedBroadcastIP(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidIPv4Address(trimmed) else {
            return nil
        }
        var parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            return nil
        }
        parts[3] = "255"
        return parts.joined(separator: ".")
    }
}
