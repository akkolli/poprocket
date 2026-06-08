import Foundation
import Security

public final class KeychainStore {
    public static let defaultService = "com.poprocket.app"

    private let service: String
    private let accessGroup: String?

    public convenience init(service: String = KeychainStore.defaultService) {
        self.init(service: service, accessGroup: Self.defaultAccessGroup())
    }

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try PopRocketCoding.encoder.encode(value)
        let query = baseQuery(account: account)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw KeychainError(status)
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(addStatus)
        }
    }

    public func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status)
        }
        return try PopRocketCoding.decoder.decode(type, from: data)
    }

    public func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func defaultAccessGroup() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "PopRocketKeychainAccessGroup") as? String
    }
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus

    public init(_ status: OSStatus) {
        self.status = status
    }

    public var description: String {
        "Keychain error \(status)"
    }
}
