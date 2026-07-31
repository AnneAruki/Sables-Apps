//
//  SableMangaBakaLibraryScanner.swift
//  Sable's Covers
//

import Foundation

nonisolated struct SableMangaBakaLibraryScanner: Sendable {
    private let bookExtensions = Set(["epub", "pdf", "cbz", "cbr"])
    private var fileManager: FileManager { .default }

    func scan(root: URL) throws -> [SableMangaBakaLocalLibrarySeries] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var results: [SableMangaBakaLocalLibrarySeries] = []
        for case let sidecarURL as URL in enumerator {
            guard sidecarURL.lastPathComponent.caseInsensitiveCompare("ComicInfo.json") == .orderedSame,
                  !isIgnored(sidecarURL, relativeTo: root),
                  let series = readSeries(from: sidecarURL) else {
                continue
            }
            results.append(series)
        }

        return results.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func coversThatBeatMangaBaka(
        localCovers: [SableMangaBakaLocalCoverImage],
        mangaBakaCovers: [SableMangaBakaPublicCoverImage]
    ) -> [SableMangaBakaLocalCoverImage] {
        localCovers.filter { localCover in
            let language = SableLibraryCoverDownloadPlanner.normalizedLanguage(
                localCover.language
            )
            let matches = mangaBakaCovers.filter {
                SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language) == language
                    && abs($0.indexNumeric - localCover.indexNumeric) < 0.001
            }
            guard let bestMangaBakaCover = matches.max(by: {
                $0.width * $0.height < $1.width * $1.height
            }) else {
                return false
            }
            return SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
                width: localCover.width,
                height: localCover.height,
                over: bestMangaBakaCover.width,
                baselineHeight: bestMangaBakaCover.height
            )
        }
    }

    private func readSeries(from sidecarURL: URL) -> SableMangaBakaLocalLibrarySeries? {
        guard let data = try? Data(contentsOf: sidecarURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let sidecar = object as? [String: Any] else {
            return nil
        }

        let folderURL = sidecarURL.deletingLastPathComponent()
        let title = text(sidecar["title"])
            ?? text(sidecar["series"])
            ?? folderTitle(folderURL.lastPathComponent)
        let mediaType = normalizedMediaType(
            text(sidecar["type"]),
            folderURL: folderURL
        )
        let mangaBakaSeriesBundle = SableLibraryMangaBakaSeriesBundleStore.load(
            from: sidecar
        )
        let mangaBakaID = mangaBakaID(in: sidecar)
            ?? mangaBakaID(inFolderName: folderURL.lastPathComponent)

        return SableMangaBakaLocalLibrarySeries(
            title: title,
            mediaType: mediaType,
            mangaBakaID: mangaBakaID,
            localBookCount: localBookCount(in: folderURL),
            localCovers: localCovers(in: folderURL),
            folderURL: folderURL,
            comicInfoURL: sidecarURL,
            ranobeDBID: ranobeDBID(in: sidecar),
            mangaBakaSeriesBundle: mangaBakaSeriesBundle
        )
    }

    private func localCovers(in folderURL: URL) -> [SableMangaBakaLocalCoverImage] {
        let manifestURL = folderURL
            .appendingPathComponent("_covers", isDirectory: true)
            .appendingPathComponent("cover-manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return []
        }

        return manifest.entries.flatMap { entry in
            entry.covers.compactMap { cover in
                guard cover.role == .normal,
                      let width = cover.width,
                      let height = cover.height,
                      width > 0,
                      height > 0,
                      let volume = cover.providerVolume ?? entry.volume else {
                    return nil
                }
                let path = folderURL.appendingPathComponent(cover.path)
                guard fileManager.fileExists(atPath: path.path(percentEncoded: false)) else {
                    return nil
                }
                return SableMangaBakaLocalCoverImage(
                    indexNumeric: volume,
                    language: SableLibraryCoverDownloadPlanner.normalizedLanguage(
                        cover.language
                    ),
                    path: cover.path,
                    width: width,
                    height: height
                )
            }
        }
    }

    private func mangaBakaID(in sidecar: [String: Any]) -> Int? {
        if let ids = sidecar["ids"] as? [String: Any],
           let value = positiveInteger(ids["mangabaka"] ?? ids["mb"]) {
            return value
        }
        if let value = positiveInteger(
            sidecar["mangabaka_id"]
                ?? sidecar["manga_baka_id"]
                ?? sidecar["mb_id"]
        ) {
            return value
        }
        if let graph = sidecar["identity_graph"] as? [String: Any],
           let sourceIDs = graph["source_ids"] as? [[String: Any]] {
            for sourceID in sourceIDs {
                let provider = text(sourceID["provider"])?.lowercased()
                if provider == "mangabaka" || provider == "mb",
                   let value = positiveInteger(sourceID["value"] ?? sourceID["id"]) {
                    return value
                }
            }
        }
        return nil
    }

    private func ranobeDBID(in sidecar: [String: Any]) -> String? {
        if let ids = sidecar["ids"] as? [String: Any],
           let value = text(ids["ranobedb"] ?? ids["rdb"]) {
            return value
        }
        if let sable = sidecar["_sable"] as? [String: Any],
           let ranobeDB = sable["ranobedb"] as? [String: Any],
           let value = text(ranobeDB["series_id"] ?? ranobeDB["seriesID"]) {
            return value
        }
        return nil
    }

    private func mangaBakaID(inFolderName name: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\{(?:mb|mangabaka)-(\d+)\}"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: name) else {
            return nil
        }
        return Int(name[valueRange])
    }

    private func localBookCount(in folderURL: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var identities = Set<String>()
        for case let fileURL as URL in enumerator {
            let relativeComponents = fileURL.pathComponents.dropFirst(folderURL.pathComponents.count)
            if relativeComponents.contains(where: {
                $0 == "_covers" || $0.hasPrefix("_Sable") || $0 == "_duplicates"
            }) {
                continue
            }
            guard bookExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            identities.insert(bookIdentity(fileURL.deletingPathExtension().lastPathComponent))
        }
        return identities.count
    }

    private func bookIdentity(_ filename: String) -> String {
        let patterns = [
            #"(?i)\b(?:vol(?:ume)?|v)\.?\s*0*(\d{1,4})(?:\.\d+)?\b"#,
            #"(?i)\bbook\s*0*(\d{1,4})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: filename,
                    range: NSRange(filename.startIndex..<filename.endIndex, in: filename)
                  ),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: filename) else {
                continue
            }
            return "volume-\(Int(filename[valueRange]) ?? 0)"
        }
        return filename
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func normalizedMediaType(_ value: String?, folderURL: URL) -> String {
        let candidate = value?.lowercased() ?? ""
        if candidate.contains("novel") || folderURL.pathComponents.contains("Light Novels") {
            return "novel"
        }
        if candidate.contains("manga")
            || candidate.contains("comic")
            || folderURL.pathComponents.contains("Manga") {
            return "manga"
        }
        return candidate.isEmpty ? "unknown" : candidate
    }

    private func folderTitle(_ name: String) -> String {
        name
            .replacingOccurrences(
                of: #"\s*\{(?:mb|mangabaka|rdb|ranobedb)-[^}]+\}"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"\s*\(\d{4}\)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func positiveInteger(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, number.intValue > 0 {
            return number.intValue
        }
        if let string = text(value), let number = Int(string), number > 0 {
            return number
        }
        return nil
    }

    private func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isIgnored(_ url: URL, relativeTo root: URL) -> Bool {
        let components = url.pathComponents.dropFirst(root.pathComponents.count)
        return components.contains {
            $0 == "_covers"
                || $0 == "_duplicates"
                || $0.hasPrefix("_Sable")
        }
    }
}
