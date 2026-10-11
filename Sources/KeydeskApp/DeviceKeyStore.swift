import Foundation
import Security
import CryptoKit
import LocalAuthentication
import KeydeskCore

enum DeviceKeyStore {
    private static func query(_ id: UUID, epoch: UUID?) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: epoch == nil ? "com.keydesk.local.vault-key.v1" : "com.keydesk.local.vault-key.v2",
         kSecAttrAccount as String: (epoch.map { id.uuidString + "/" + $0.uuidString } ?? id.uuidString),
         kSecAttrSynchronizable as String: false]
    }
    static func save(_ key: SymmetricKey, id: UUID, epoch: UUID, cleanupPending: Bool = false) throws {
        var attributes = query(id, epoch: epoch)
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrLabel as String] = "Keydesk 로컬 금고"
        attributes[kSecAttrGeneric as String] = Data((cleanupPending ? "pending-legacy-cleanup" : "complete").utf8)
        attributes[kSecUseDataProtectionKeychain as String] = true
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &accessError) else { throw VaultError.accessDenied }
        attributes[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "보호된 Keychain 저장 실패 (\(status)). 이 앱 ID의 provisioning profile과 서명을 확인하세요. 약한 저장 방식으로 전환하지 않습니다."]) }
    }
    /// Pass the context already evaluated by `authenticate` so the user-presence item opens
    /// with that single OS prompt instead of asking a second time.
    static func load(envelope: VaultEnvelope, context: LAContext? = nil) throws -> SymmetricKey {
        let id = envelope.header.vaultID, epoch = envelope.header.keyEpoch
        var attributes = query(id, epoch: epoch)
        attributes[kSecUseDataProtectionKeychain as String] = true
        if let context { attributes[kSecUseAuthenticationContext as String] = context }
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound {
            var legacy = query(id, epoch: nil)
            legacy[kSecReturnData as String] = true
            status = SecItemCopyMatching(legacy as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data, data.count == 32 {
                let candidate = SymmetricKey(data: data)
                // Authenticate the entire file before changing or deleting any legacy item.
                _ = try VaultCrypto.open(envelope, key: candidate)
                try save(candidate, id: id, epoch: epoch, cleanupPending: true)
            }
        }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "기기 키를 열 수 없습니다. 백업과 복구 키로 복원할 수 있습니다."])
        }
        let key = SymmetricKey(data: data)
        _ = try VaultCrypto.open(envelope, key: key)
        var metadata = query(id, epoch: epoch)
        metadata[kSecUseDataProtectionKeychain as String] = true
        if let context { metadata[kSecUseAuthenticationContext as String] = context }
        metadata[kSecReturnAttributes as String] = true
        var copied: CFTypeRef?
        guard SecItemCopyMatching(metadata as CFDictionary, &copied) == errSecSuccess, let values = copied as? [String: Any] else { throw VaultError.accessDenied }
        if values[kSecAttrGeneric as String] as? Data != Data("complete".utf8) {
            // A crash or failed cleanup remains pending and is retried on the next unlock.
            let deleted = SecItemDelete(query(id, epoch: nil) as CFDictionary)
            guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw VaultError.accessDenied }
            metadata.removeValue(forKey: kSecReturnAttributes as String)
            let finished = [kSecAttrGeneric as String: Data("complete".utf8)]
            guard SecItemUpdate(metadata as CFDictionary, finished as CFDictionary) == errSecSuccess else { throw VaultError.accessDenied }
        }
        return key
    }
    static func remove(id: UUID, epoch: UUID) {
        var attributes = query(id, epoch: epoch); attributes[kSecUseDataProtectionKeychain as String] = true
        _ = SecItemDelete(attributes as CFDictionary)
    }
    private static func depositPublicQuery(_ vaultID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.keydesk.local.deposit-public.v1",
         kSecAttrAccount as String: vaultID.uuidString, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    static func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws {
        guard data.count == 64 else { throw VaultError.invalidData }
        let query = depositPublicQuery(vaultID)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw VaultError.accessDenied }
        var item = query; item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw VaultError.accessDenied }
    }
    static func loadDepositPublicKey(vaultID: UUID) throws -> Data {
        var query = depositPublicQuery(vaultID)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, data.count == 64 else { throw VaultError.accessDenied }
        return data
    }
    // Recovery keys sync through iCloud Keychain (end-to-end encrypted) so another Mac signed in to the
    // same Apple Account can open the iCloud Drive backup. Synchronizable items cannot carry the
    // device-only user-presence policy; the app asks for OS authentication before using them.
    private static let recoveryService = "com.keydesk.local.recovery-key.v1"
    private static func recoveryQuery(_ vaultID: UUID?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: recoveryService,
                                    kSecAttrSynchronizable as String: true,
                                    kSecUseDataProtectionKeychain as String: true]
        if let vaultID { query[kSecAttrAccount as String] = vaultID.uuidString }
        return query
    }
    static func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool {
        let data = key.withUnsafeBytes { Data($0) }
        let update = SecItemUpdate(recoveryQuery(vaultID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var attributes = recoveryQuery(vaultID)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        attributes[kSecAttrLabel as String] = "Keydesk 복구 키"
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
    static func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? {
        var attributes = recoveryQuery(vaultID)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess, let data = result as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
    static func knownRecoveryVaults() -> [UUID] {
        var attributes = recoveryQuery(nil)
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(UUID.init(uuidString:)) }
    }
    static func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext? = nil) throws {
        let attributes = [kSecValueData as String: key.withUnsafeBytes { Data($0) }, kSecAttrGeneric as String: Data("pending-legacy-cleanup".utf8)]
        var match = query(id, epoch: epoch); match[kSecUseDataProtectionKeychain as String] = true
        if let context { match[kSecUseAuthenticationContext as String] = context }
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { try save(key, id: id, epoch: epoch, cleanupPending: true) }
        else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "기기 키를 복구하지 못했습니다."]) }
    }
    // Disposable random fixture: validates entitlements and fail-closed user-presence policy,
    // without reading any existing vault item or asking for the user's password.
    static func probe() -> String {
        let id = UUID(), epoch = UUID()
        // A random synchronizable item checks that iCloud Keychain storage is permitted for this app.
        var sync: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.keydesk.local.sync-probe",
                                   kSecAttrAccount as String: UUID().uuidString, kSecAttrSynchronizable as String: true,
                                   kSecUseDataProtectionKeychain as String: true]
        var addSync = sync; addSync[kSecValueData as String] = Data(repeating: 0, count: 32); addSync[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let syncStatus = SecItemAdd(addSync as CFDictionary, nil)
        sync[kSecMatchLimit as String] = kSecMatchLimitOne
        _ = SecItemDelete(sync as CFDictionary)
        let syncLine = "synchronizable_item_add=\(syncStatus == errSecSuccess ? "success" : "failed_\(syncStatus)")\nauthentication_profile_found=\(configured)\n"
        do {
            try save(SymmetricKey(size: .bits256), id: id, epoch: epoch)
            defer { remove(id: id, epoch: epoch) }
            var attributes = query(id, epoch: epoch)
            attributes[kSecUseDataProtectionKeychain as String] = true
            attributes[kSecReturnData as String] = true
            let context = LAContext(); context.interactionNotAllowed = true
            attributes[kSecUseAuthenticationContext as String] = context
            var result: CFTypeRef?
            let status = SecItemCopyMatching(attributes as CFDictionary, &result)
            return "protected_item_add=success\nunauthenticated_read_status=\(status)\nuser_presence_enforced=\(status == errSecInteractionNotAllowed)\n" + syncLine
        } catch { return "protected_item_add=failed\nstatus=\((error as NSError).code)\n" + syncLine }
    }
    // macOS places the profile at Contents/embedded.provisionprofile, outside Contents/Resources,
    // so Bundle.url(forResource:) never finds it.
    static var configured: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile").path)
    }
    @discardableResult
    static func authenticate(reason: String) async throws -> LAContext {
        guard configured else { throw NSError(domain: "Keydesk", code: 1, userInfo: [NSLocalizedDescriptionKey: "보호된 Keychain에 필요한 이 앱의 서명 프로필이 없습니다. 설치 안내를 확인하세요. 운영 키 등록을 중단했습니다."]) }
        let context = LAContext()
        context.localizedCancelTitle = "취소"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? VaultError.locked as NSError
        }
        let accepted = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard accepted else { throw VaultError.locked }
        return context
    }
}
