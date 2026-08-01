//
//  SableLibrarySharedContainer.swift
//  Sable's Library
//

import Foundation
import Security

nonisolated enum SableLibrarySharedContainer {
    private static let appGroupBaseIdentifier = "com.annearuki.Sables"
    private static let appGroupEntitlementKey = "com.apple.security.application-groups"

    static var appGroupIdentifier: String? {
        resolvedAppGroupIdentifier(entitlementIdentifiers: signedAppGroupIdentifiers)
    }

    static func resolvedAppGroupIdentifier(entitlementIdentifiers: [String]) -> String? {
        let requiredSuffix = ".\(appGroupBaseIdentifier)"
        return entitlementIdentifiers.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasSuffix(requiredSuffix) }
    }

    private static var signedAppGroupIdentifiers: [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        var error: Unmanaged<CFError>?
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            appGroupEntitlementKey as CFString,
            &error
        ) else {
            return []
        }
        return value as? [String] ?? []
    }

    static var appGroupURL: URL? {
        guard let appGroupIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var applicationSupportDirectory: URL {
        if let appGroupURL {
            return appGroupURL.appendingPathComponent("Application Support", isDirectory: true)
        }
        return legacyApplicationSupportDirectory
    }

    static var legacyApplicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sable's Library", isDirectory: true)
    }

    static func supportDirectory(named name: String) -> URL {
        applicationSupportDirectory.appendingPathComponent(name, isDirectory: true)
    }

    static func legacySupportDirectory(named name: String) -> URL {
        legacyApplicationSupportDirectory.appendingPathComponent(name, isDirectory: true)
    }

    @discardableResult
    static func migrateFileIfNeeded(from legacyURL: URL, to sharedURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard appGroupURL != nil,
              legacyURL.standardizedFileURL != sharedURL.standardizedFileURL,
              fileManager.fileExists(atPath: legacyURL.path(percentEncoded: false)),
              !fileManager.fileExists(atPath: sharedURL.path(percentEncoded: false)) else {
            return false
        }

        do {
            try fileManager.createDirectory(
                at: sharedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacyURL, to: sharedURL)
            return true
        } catch {
            return false
        }
    }
}
