//
//  SableLibraryMangaBakaSeriesBundle.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryMangaBakaSeriesBundleMember: Codable, Sendable, Equatable, Identifiable {
    var seriesID: Int
    var title: String
    var mediaType: String
    var sourceVolumeStart: Int
    var sourceVolumeEnd: Int
    var libraryVolumeStart: Int

    var id: Int { seriesID }

    var volumeCount: Int {
        max(1, sourceVolumeEnd - sourceVolumeStart + 1)
    }

    var libraryVolumeEnd: Int {
        libraryVolumeStart + volumeCount - 1
    }

    func libraryVolume(for sourceVolume: Double) -> Double? {
        let lowerBound = Double(sourceVolumeStart)
        let upperBound = Double(sourceVolumeEnd)
        guard sourceVolume >= lowerBound - 0.001,
              sourceVolume <= upperBound + 0.001 else {
            return nil
        }
        return Double(libraryVolumeStart) + sourceVolume - lowerBound
    }

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case title
        case mediaType = "media_type"
        case sourceVolumeStart = "source_volume_start"
        case sourceVolumeEnd = "source_volume_end"
        case libraryVolumeStart = "library_volume_start"
    }
}

nonisolated struct SableLibraryMangaBakaSeriesBundle: Codable, Sendable, Equatable {
    var schemaVersion: Int = 1
    var canonicalProvider: String?
    var canonicalSeriesID: String?
    var mediaType: String
    var members: [SableLibraryMangaBakaSeriesBundleMember]

    var seriesIDs: [Int] {
        members.map(\.seriesID)
    }

    var nextLibraryVolumeStart: Int {
        (members.map(\.libraryVolumeEnd).max() ?? 0) + 1
    }

    var validationIssues: [String] {
        var issues: [String] = []
        if members.isEmpty {
            issues.append("Add at least one MangaBaka series.")
        }
        if Set(seriesIDs).count != seriesIDs.count {
            issues.append("Each MangaBaka series can appear only once.")
        }

        for member in members {
            if member.seriesID <= 0 {
                issues.append("Every MangaBaka series needs a valid ID.")
            }
            if member.sourceVolumeStart < 1
                || member.sourceVolumeEnd < member.sourceVolumeStart {
                issues.append("\(member.title) has an invalid source volume range.")
            }
            if member.libraryVolumeStart < 1 {
                issues.append("\(member.title) has an invalid library start volume.")
            }
            if !Self.mediaTypesMatch(mediaType, member.mediaType) {
                issues.append(
                    "\(member.title) is \(member.mediaType), not \(mediaType)."
                )
            }
        }

        let sorted = members.sorted {
            $0.libraryVolumeStart < $1.libraryVolumeStart
        }
        for pair in zip(sorted, sorted.dropFirst()) where
            pair.0.libraryVolumeEnd >= pair.1.libraryVolumeStart {
            issues.append(
                "\(pair.0.title) and \(pair.1.title) overlap in the library volume sequence."
            )
        }
        return Array(Set(issues)).sorted()
    }

    func normalized() -> Self {
        var normalized = self
        var nextLibraryVolume = 1
        normalized.members = members.map { member in
            var member = member
            member.sourceVolumeStart = max(1, member.sourceVolumeStart)
            member.sourceVolumeEnd = max(
                member.sourceVolumeStart,
                member.sourceVolumeEnd
            )
            member.libraryVolumeStart = nextLibraryVolume
            nextLibraryVolume = member.libraryVolumeEnd + 1
            return member
        }
        return normalized
    }

    func member(seriesID: String) -> SableLibraryMangaBakaSeriesBundleMember? {
        guard let value = Int(seriesID) else { return nil }
        return members.first { $0.seriesID == value }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case canonicalProvider = "canonical_provider"
        case canonicalSeriesID = "canonical_series_id"
        case mediaType = "media_type"
        case members
    }

    private static func mediaTypesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedMediaType(lhs) == normalizedMediaType(rhs)
    }

    private static func normalizedMediaType(_ value: String) -> String {
        let value = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if value.contains("novel") || value == "ranobe" {
            return "novel"
        }
        if value.contains("manga")
            || value.contains("comic")
            || value.contains("graphic") {
            return "manga"
        }
        return value
    }
}

nonisolated enum SableLibraryMangaBakaSeriesBundleStore {
    static let sidecarKey = "cover_series_bundle"

    static func load(from sidecar: [String: Any]) -> SableLibraryMangaBakaSeriesBundle? {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let rawBundle = sable[sidecarKey],
              JSONSerialization.isValidJSONObject(rawBundle),
              let data = try? JSONSerialization.data(withJSONObject: rawBundle) else {
            return nil
        }
        return try? JSONDecoder().decode(
            SableLibraryMangaBakaSeriesBundle.self,
            from: data
        )
    }

    static func load(from comicInfoURL: URL) -> SableLibraryMangaBakaSeriesBundle? {
        guard let data = try? Data(contentsOf: comicInfoURL),
              let sidecar = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return load(from: sidecar)
    }

    static func save(
        _ bundle: SableLibraryMangaBakaSeriesBundle,
        to comicInfoURL: URL
    ) throws {
        let normalized = bundle.normalized()
        guard normalized.validationIssues.isEmpty else {
            throw SableLibraryMangaBakaSeriesBundleError.invalidBundle(
                normalized.validationIssues.joined(separator: " ")
            )
        }

        let existingData = try Data(contentsOf: comicInfoURL)
        guard var sidecar = try JSONSerialization.jsonObject(
            with: existingData
        ) as? [String: Any] else {
            throw SableLibraryMangaBakaSeriesBundleError.invalidComicInfo
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bundleData = try encoder.encode(normalized)
        guard let bundleObject = try JSONSerialization.jsonObject(
            with: bundleData
        ) as? [String: Any] else {
            throw SableLibraryMangaBakaSeriesBundleError.invalidBundle(
                "The series bundle could not be encoded."
            )
        }

        var sable = sidecar["_sable"] as? [String: Any] ?? [:]
        sable[sidecarKey] = bundleObject
        sidecar["_sable"] = sable

        let output = try JSONSerialization.data(
            withJSONObject: sidecar,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try output.write(to: comicInfoURL, options: .atomic)
    }
}

nonisolated enum SableLibraryMangaBakaSeriesBundleError: LocalizedError {
    case invalidComicInfo
    case invalidBundle(String)

    var errorDescription: String? {
        switch self {
        case .invalidComicInfo:
            "ComicInfo.json is not a readable JSON object."
        case let .invalidBundle(message):
            message
        }
    }
}
