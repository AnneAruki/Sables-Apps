//
//  SableLibraryUserSettings.swift
//  Sable's Library
//

import Foundation
#if canImport(Security)
import Security
#endif

nonisolated struct SableLibraryUserSettings {
    private enum Key {
        static let libraryBookmark = "sableLibrary.libraryBookmark"
        static let cleanupOptions = "sableLibrary.cleanupOptions"
        static let pipelineStageOptions = "sableLibrary.libraryAuditOptions"
        static let intelligenceOptions = "sableLibrary.intelligenceOptions"
        static let learningMemory = "sableLibrary.learningMemory"
        static let providerCredentialsFallback = "sableLibrary.providerCredentialsFallback"
        static let disabledCoverStorefrontProviders =
            "sableLibrary.disabledCoverStorefrontProviders"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadCleanupOptions() -> CleanupOptions {
        load(CleanupOptions.self, key: Key.cleanupOptions) ?? CleanupOptions()
    }

    func saveCleanupOptions(_ options: CleanupOptions) {
        save(options, key: Key.cleanupOptions)
    }

    func loadPipelineStageOptions() -> LibraryPipelineStageOptions {
        load(LibraryPipelineStageOptions.self, key: Key.pipelineStageOptions) ?? LibraryPipelineStageOptions()
    }

    func savePipelineStageOptions(_ options: LibraryPipelineStageOptions) {
        save(options, key: Key.pipelineStageOptions)
    }

    func loadIntelligenceOptions() -> SableLibraryIntelligenceOptions {
        load(SableLibraryIntelligenceOptions.self, key: Key.intelligenceOptions) ?? SableLibraryIntelligenceOptions()
    }

    func saveIntelligenceOptions(_ options: SableLibraryIntelligenceOptions) {
        save(options, key: Key.intelligenceOptions)
    }

    func loadProviderCredentials() -> SableLibraryProviderCredentials {
        var credentials = SableLibraryProviderCredentialStore().load()
        if let fallback = load(
            SableLibraryProviderCredentials.self,
            key: Key.providerCredentialsFallback
        ) {
            if credentials.tmdbAccessToken.isEmpty {
                credentials.tmdbAccessToken = fallback.tmdbAccessToken
            }
            if credentials.tvdbAccessToken.isEmpty {
                credentials.tvdbAccessToken = fallback.tvdbAccessToken
            }
            if credentials.mangaBakaPersonalAccessToken.isEmpty {
                credentials.mangaBakaPersonalAccessToken =
                    fallback.mangaBakaPersonalAccessToken
            }
        }
        return credentials
    }

    func saveProviderCredentials(_ credentials: SableLibraryProviderCredentials) {
        if SableLibraryProviderCredentialStore().save(credentials) {
            defaults.removeObject(forKey: Key.providerCredentialsFallback)
        } else {
            save(credentials, key: Key.providerCredentialsFallback)
        }
    }

    func clearProviderCredentials() {
        SableLibraryProviderCredentialStore().clear()
        defaults.removeObject(forKey: Key.providerCredentialsFallback)
    }

    func loadDisabledCoverStorefrontProviderIDs() -> Set<String> {
        Set(
            defaults.stringArray(
                forKey: Key.disabledCoverStorefrontProviders
            ) ?? []
        )
    }

    func saveDisabledCoverStorefrontProviderIDs(_ providerIDs: Set<String>) {
        defaults.set(
            providerIDs.sorted(),
            forKey: Key.disabledCoverStorefrontProviders
        )
    }

    func loadLearningMemory() -> SableLibraryLearningMemory {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return SableLibraryLearningMemory()
        }

        let sharedMemory = loadSharedLearningMemory()
        let legacyMemory = load(SableLibraryLearningMemory.self, key: Key.learningMemory)

        if var sharedMemory {
            if let legacyMemory,
               legacyMemory.learnedDecisionCount > 0,
               legacyMemory != sharedMemory {
                sharedMemory.mergeConservatively(legacyMemory)
                let prunedMemory = sharedMemory.prunedForLightweightStorage()
                if saveSharedLearningMemory(prunedMemory) {
                    clearLegacyLearningMemory()
                }
                return prunedMemory
            }

            clearLegacyLearningMemory()
            return sharedMemory.prunedForLightweightStorage()
        }

        if let legacyMemory {
            let prunedMemory = legacyMemory.prunedForLightweightStorage()
            if saveSharedLearningMemory(prunedMemory) {
                clearLegacyLearningMemory()
            }
            return prunedMemory
        }

        return SableLibraryLearningMemory()
    }

    func saveLearningMemory(_ memory: SableLibraryLearningMemory) {
        let prunedMemory = memory.prunedForLightweightStorage()
        if saveSharedLearningMemory(prunedMemory) {
            clearLegacyLearningMemory()
        } else {
            save(prunedMemory, key: Key.learningMemory)
        }
    }

    func clearLearningMemory() {
        try? FileManager.default.removeItem(at: sharedLearningMemoryURL)
        clearLegacyLearningMemory()
    }

    func hasLearningMemory() -> Bool {
        if FileManager.default.fileExists(atPath: sharedLearningMemoryURL.path(percentEncoded: false)) {
            return true
        }
        return defaults.data(forKey: Key.learningMemory) != nil
    }

    @discardableResult
    func saveLibraryFolder(_ url: URL) -> Bool {
        #if os(macOS)
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }
        defaults.set(bookmark, forKey: Key.libraryBookmark)
        return true
        #else
        return false
        #endif
    }

    func loadLibraryFolder() -> URL? {
        #if os(macOS)
        guard let data = defaults.data(forKey: Key.libraryBookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            defaults.removeObject(forKey: Key.libraryBookmark)
            return nil
        }
        if isStale {
            saveLibraryFolder(url)
        }
        return url
        #else
        return nil
        #endif
    }

    func clearLibraryFolder() {
        defaults.removeObject(forKey: Key.libraryBookmark)
    }

    func resetToolOptions() {
        defaults.removeObject(forKey: Key.cleanupOptions)
        defaults.removeObject(forKey: Key.pipelineStageOptions)
        defaults.removeObject(forKey: Key.intelligenceOptions)
    }

    private func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private var sharedLearningMemoryURL: URL {
        SableLibrarySharedContainer
            .supportDirectory(named: "Learning")
            .appendingPathComponent("SableLearningMemory.json")
    }

    private func loadSharedLearningMemory() -> SableLibraryLearningMemory? {
        guard let data = try? Data(contentsOf: sharedLearningMemoryURL) else { return nil }
        return try? decoder.decode(SableLibraryLearningMemory.self, from: data)
    }

    @discardableResult
    private func saveSharedLearningMemory(_ memory: SableLibraryLearningMemory) -> Bool {
        do {
            let url = sharedLearningMemoryURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(memory)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func clearLegacyLearningMemory() {
        defaults.removeObject(forKey: Key.learningMemory)
    }
}

private nonisolated struct SableLibraryProviderCredentialStore {
    private let service = "SableLibrary.MetadataProviderCredentials"
    private let legacyMALAccount = "myAnimeListClientID"
    private let legacyYenPressSearchTokenAccount = "yenPressSearchToken"

    private enum Account: String, CaseIterable {
        case tmdbAccessToken
        case tvdbAccessToken
        case mangaBakaPersonalAccessToken
        case rolerUserToken
        case rolerSessionID
    }

    func load() -> SableLibraryProviderCredentials {
        delete(accountName: legacyYenPressSearchTokenAccount)
        var credentials = SableLibraryProviderCredentials()
        credentials.tmdbAccessToken = read(.tmdbAccessToken) ?? ""
        credentials.tvdbAccessToken = read(.tvdbAccessToken) ?? ""
        credentials.mangaBakaPersonalAccessToken = read(.mangaBakaPersonalAccessToken) ?? ""
        credentials.rolerUserToken = read(.rolerUserToken) ?? ""
        credentials.rolerSessionID = read(.rolerSessionID) ?? ""
        return credentials
    }

    func save(_ credentials: SableLibraryProviderCredentials) -> Bool {
        delete(accountName: legacyMALAccount)
        delete(accountName: legacyYenPressSearchTokenAccount)
        let results = [
            write(credentials.tmdbAccessToken, account: .tmdbAccessToken),
            write(credentials.tvdbAccessToken, account: .tvdbAccessToken),
            write(credentials.mangaBakaPersonalAccessToken, account: .mangaBakaPersonalAccessToken),
            write(credentials.rolerUserToken, account: .rolerUserToken),
            write(credentials.rolerSessionID, account: .rolerSessionID)
        ]
        return results.allSatisfy { $0 }
    }

    func clear() {
        Account.allCases.forEach(delete)
        delete(accountName: legacyMALAccount)
        delete(accountName: legacyYenPressSearchTokenAccount)
    }

    private func read(_ account: Account) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
        #else
        return nil
        #endif
    }

    private func write(_ value: String, account: Account) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(account)
            return true
        }

        #if canImport(Security)
        guard let data = trimmed.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
        #else
        return false
        #endif
    }

    private func delete(_ account: Account) {
        delete(accountName: account.rawValue)
    }

    private func delete(accountName: String) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}
