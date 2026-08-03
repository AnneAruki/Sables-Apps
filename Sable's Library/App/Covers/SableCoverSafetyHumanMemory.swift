//
//  SableCoverSafetyHumanMemory.swift
//  Sable's Covers
//

import CryptoKit
import Foundation

nonisolated final class SableCoverSafetyHumanMemory: @unchecked Sendable {
    static let shared = SableCoverSafetyHumanMemory()

    private final class BundleToken: NSObject {}

    private struct Memory: Codable {
        var schemaVersion: Int
        var items: [Item]
    }

    private struct Item: Codable {
        var seriesID: Int
        var imageID: Int?
        var sha256: String
        var sourceURL: String?
        var language: String?
        var type: String?
        var index: String?
        var rating: String
    }

    private struct SeriesImageKey: Hashable {
        var seriesID: Int
        var imageID: Int
    }

    private struct SeriesURLKey: Hashable {
        var seriesID: Int
        var sourceURL: String
    }

    private struct SeriesSlotKey: Hashable {
        var seriesID: Int
        var language: String
        var type: String
        var index: String
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var ratingsBySeriesImage: [SeriesImageKey: String] = [:]
    private var ratingsBySeriesURL: [SeriesURLKey: String] = [:]
    private var ratingsBySeriesSlot: [SeriesSlotKey: String] = [:]
    private var ratingsByHash: [String: String] = [:]
    private var overrideItems: [String: Item] = [:]

    private init() {
        defaults = .standard
        apply(Self.loadMemory()?.items ?? [])
        let overrides = Self.loadOverrides(from: defaults)
        overrideItems = Dictionary(
            overrides.map { (Self.overrideIdentity(for: $0), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        apply(overrides)
    }

    init(defaults: UserDefaults, bundledMemoryData: Data? = nil) {
        self.defaults = defaults
        if let bundledMemoryData,
           let memory = try? JSONDecoder().decode(
               Memory.self,
               from: bundledMemoryData
           ),
           memory.schemaVersion == 1 {
            apply(memory.items)
        }
        let overrides = Self.loadOverrides(from: defaults)
        overrideItems = Dictionary(
            overrides.map { (Self.overrideIdentity(for: $0), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        apply(overrides)
    }

    func rating(seriesID: Int, imageID: Int) -> String? {
        withLock {
            ratingsBySeriesImage[
                SeriesImageKey(seriesID: seriesID, imageID: imageID)
            ]
        }
    }

    func rating(seriesID: Int, sourceURL: String) -> String? {
        withLock {
            ratingsBySeriesURL[
                SeriesURLKey(seriesID: seriesID, sourceURL: sourceURL)
            ]
        }
    }

    func rating(
        seriesID: Int,
        language: String,
        type: String,
        indexNumeric: Double
    ) -> String? {
        guard let key = Self.slotKey(
            seriesID: seriesID,
            language: language,
            type: type,
            indexNumeric: indexNumeric
        ) else {
            return nil
        }
        return withLock { ratingsBySeriesSlot[key] }
    }

    func rating(for data: Data) -> String? {
        let digest = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        return withLock { ratingsByHash[digest] }
    }

    func record(
        seriesID: Int,
        imageID: Int?,
        sourceURL: String?,
        language: String,
        type: String,
        indexNumeric: Double,
        rating: String
    ) {
        guard Self.supportedRatings.contains(rating),
              indexNumeric.isFinite else {
            return
        }
        let trimmedSourceURL = sourceURL?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let item = Item(
            seriesID: seriesID,
            imageID: imageID,
            sha256: "",
            sourceURL: trimmedSourceURL?.isEmpty == false
                ? trimmedSourceURL
                : nil,
            language: language,
            type: type,
            index: Self.canonicalIndex(indexNumeric),
            rating: rating
        )
        withLock {
            overrideItems[Self.overrideIdentity(for: item)] = item
            apply(item)
            persistOverrides()
        }
    }

    private static func loadMemory() -> Memory? {
        var seenBundles = Set<String>()
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)].filter {
            seenBundles.insert($0.bundleURL.standardizedFileURL.path).inserted
        }
        for bundle in bundles {
            guard let url = bundle.url(
                forResource: "SableCoverSafetyHumanJudgments",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let memory = try? JSONDecoder().decode(Memory.self, from: data),
            memory.schemaVersion == 1 else {
                continue
            }
            return memory
        }
        return nil
    }

    private func apply(_ items: [Item]) {
        for item in items {
            apply(item)
        }
    }

    private func apply(_ item: Item) {
        guard Self.supportedRatings.contains(item.rating) else { return }
        if let imageID = item.imageID {
            ratingsBySeriesImage[
                SeriesImageKey(seriesID: item.seriesID, imageID: imageID)
            ] = item.rating
        }
        if let sourceURL = item.sourceURL,
           !sourceURL.isEmpty {
            ratingsBySeriesURL[
                SeriesURLKey(
                    seriesID: item.seriesID,
                    sourceURL: sourceURL
                )
            ] = item.rating
        }
        if let language = item.language,
           let type = item.type,
           let index = item.index.flatMap(Double.init),
           let key = Self.slotKey(
               seriesID: item.seriesID,
               language: language,
               type: type,
               indexNumeric: index
           ) {
            ratingsBySeriesSlot[key] = item.rating
        }
        if item.sha256.count == 64 {
            ratingsByHash[item.sha256.lowercased()] = item.rating
        }
    }

    private func persistOverrides() {
        let memory = Memory(
            schemaVersion: 1,
            items: overrideItems.values.sorted {
                Self.overrideIdentity(for: $0)
                    < Self.overrideIdentity(for: $1)
            }
        )
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: Self.overridesDefaultsKey)
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private static func loadOverrides(from defaults: UserDefaults) -> [Item] {
        guard let data = defaults.data(forKey: overridesDefaultsKey),
              let memory = try? JSONDecoder().decode(Memory.self, from: data),
              memory.schemaVersion == 1 else {
            return []
        }
        return memory.items
    }

    private static func overrideIdentity(for item: Item) -> String {
        if let imageID = item.imageID {
            return "image|\(item.seriesID)|\(imageID)"
        }
        if let sourceURL = item.sourceURL,
           !sourceURL.isEmpty {
            return "url|\(item.seriesID)|\(sourceURL)"
        }
        return [
            "slot",
            String(item.seriesID),
            normalizedLanguage(item.language ?? "unknown"),
            normalizedType(item.type ?? "other"),
            item.index.flatMap(Double.init).map(canonicalIndex) ?? "0",
        ].joined(separator: "|")
    }

    private static func slotKey(
        seriesID: Int,
        language: String,
        type: String,
        indexNumeric: Double
    ) -> SeriesSlotKey? {
        guard indexNumeric.isFinite else { return nil }
        return SeriesSlotKey(
            seriesID: seriesID,
            language: normalizedLanguage(language),
            type: normalizedType(type),
            index: canonicalIndex(indexNumeric)
        )
    }

    private static func normalizedLanguage(_ language: String) -> String {
        let normalized = language.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased().replacingOccurrences(of: "_", with: "-")
        return normalized == "jp" ? "ja" : normalized
    }

    private static func normalizedType(_ type: String) -> String {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "normal": "volume"
        case "back", "back_cover": "volume_back"
        default: type.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        }
    }

    private static func canonicalIndex(_ index: Double) -> String {
        if index.rounded() == index {
            return String(Int(index))
        }
        return String(index)
    }

    private static let overridesDefaultsKey =
        "SableCoverSafetyHumanOverrides.v1"
    private static let supportedRatings = Set([
        "safe", "suggestive", "erotica", "pornographic",
    ])
}
