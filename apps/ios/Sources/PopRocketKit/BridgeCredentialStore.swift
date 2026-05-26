import CryptoKit
import Foundation

public struct BridgeCredentialState: Codable, Equatable {
    public var activeBridgeID: String?
    public var bridges: [PairingCredential]

    public init(activeBridgeID: String? = nil, bridges: [PairingCredential] = []) {
        self.activeBridgeID = activeBridgeID
        self.bridges = bridges
        normalizeInPlace()
    }

    public var activeCredential: PairingCredential? {
        if let activeBridgeID, let credential = bridges.first(where: { $0.bridgeID == activeBridgeID }) {
            return credential
        }
        return bridges.first
    }

    public func credential(id bridgeID: String?) -> PairingCredential? {
        guard let bridgeID, !bridgeID.isEmpty else {
            return activeCredential
        }
        return bridges.first { $0.bridgeID == bridgeID }
    }

    public mutating func upsert(_ credential: PairingCredential) {
        if let index = bridges.firstIndex(where: { $0.bridgeID == credential.bridgeID }) {
            bridges[index] = credential
        } else {
            bridges.append(credential)
        }
        activeBridgeID = credential.bridgeID
        normalizeInPlace()
    }

    public mutating func activate(id bridgeID: String) throws {
        guard bridges.contains(where: { $0.bridgeID == bridgeID }) else {
            throw BridgeCredentialStoreError.unknownBridge(bridgeID)
        }
        activeBridgeID = bridgeID
    }

    public mutating func remove(id bridgeID: String) {
        bridges.removeAll { $0.bridgeID == bridgeID }
        if activeBridgeID == bridgeID {
            activeBridgeID = bridges.first?.bridgeID
        }
        normalizeInPlace()
    }

    public mutating func rename(id bridgeID: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BridgeCredentialStoreError.emptyName
        }
        guard let index = bridges.firstIndex(where: { $0.bridgeID == bridgeID }) else {
            throw BridgeCredentialStoreError.unknownBridge(bridgeID)
        }
        let bridge = bridges[index]
        bridges[index] = PairingCredential(
            bridgeID: bridge.bridgeID,
            bridgeName: trimmed,
            directURLs: bridge.directURLs,
            relayURL: bridge.relayURL,
            relayWebSocketURL: bridge.relayWebSocketURL,
            deviceID: bridge.deviceID,
            scopes: bridge.scopes,
            pairedAt: bridge.pairedAt
        )
    }

    public func normalized() -> BridgeCredentialState {
        var copy = self
        copy.normalizeInPlace()
        return copy
    }

    private mutating func normalizeInPlace() {
        var seen: Set<String> = []
        bridges = bridges.filter { credential in
            guard !credential.bridgeID.isEmpty, !seen.contains(credential.bridgeID) else {
                return false
            }
            seen.insert(credential.bridgeID)
            return true
        }

        if let activeBridgeID, !bridges.contains(where: { $0.bridgeID == activeBridgeID }) {
            self.activeBridgeID = bridges.first?.bridgeID
        } else if activeBridgeID == nil, !bridges.isEmpty {
            activeBridgeID = bridges.first?.bridgeID
        }
    }
}

public enum BridgeCredentialStoreError: Error, Equatable {
    case unknownBridge(String)
    case emptyName
}

public final class BridgeCredentialStore {
    public static let credentialsAccount = "bridge_credentials"
    public static let legacyActiveAccount = "active_pairing"
    public static let privateKeyAccount = "device_private_key"

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func load() throws -> BridgeCredentialState {
        if let stored = try keychain.load(BridgeCredentialState.self, account: Self.credentialsAccount) {
            let normalized = stored.normalized()
            if normalized != stored {
                try save(normalized)
            }
            return normalized
        }

        if let legacy = try keychain.load(PairingCredential.self, account: Self.legacyActiveAccount) {
            let migrated = BridgeCredentialState(activeBridgeID: legacy.bridgeID, bridges: [legacy])
            try save(migrated)
            return migrated
        }

        return BridgeCredentialState()
    }

    public func save(_ state: BridgeCredentialState) throws {
        let normalized = state.normalized()
        try keychain.save(normalized, account: Self.credentialsAccount)
        try syncLegacyActiveCredential(normalized)
    }

    public func upsert(_ credential: PairingCredential) throws -> BridgeCredentialState {
        var state = try load()
        state.upsert(credential)
        try save(state)
        return state
    }

    public func setActiveBridge(id bridgeID: String) throws -> BridgeCredentialState {
        var state = try load()
        try state.activate(id: bridgeID)
        try save(state)
        return state
    }

    public func removeBridge(id bridgeID: String) throws -> BridgeCredentialState {
        var state = try load()
        state.remove(id: bridgeID)
        try save(state)
        if state.bridges.isEmpty {
            try keychain.delete(account: Self.privateKeyAccount)
        }
        return state
    }

    public func renameBridge(id bridgeID: String, name: String) throws -> BridgeCredentialState {
        var state = try load()
        try state.rename(id: bridgeID, name: name)
        try save(state)
        return state
    }

    public func credential(id bridgeID: String? = nil) throws -> PairingCredential? {
        try load().credential(id: bridgeID)
    }

    public func devicePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let stored = try existingDevicePrivateKey() {
            return stored
        }
        let privateKey = ActionSigner.makePrivateKey()
        try keychain.save(privateKey.rawRepresentation, account: Self.privateKeyAccount)
        return privateKey
    }

    public func existingDevicePrivateKey() throws -> Curve25519.Signing.PrivateKey? {
        guard let data = try keychain.load(Data.self, account: Self.privateKeyAccount) else {
            return nil
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private func syncLegacyActiveCredential(_ state: BridgeCredentialState) throws {
        if let activeCredential = state.activeCredential {
            try keychain.save(activeCredential, account: Self.legacyActiveAccount)
        } else {
            try keychain.delete(account: Self.legacyActiveAccount)
        }
    }
}
