//
//  SableLibraryReports.swift
//  Sable's Library
//

import Foundation

extension SableLibraryService {
    func cleanupReport(title: String, moves: [PlannedMove]) -> String {
        var lines = [title, String(repeating: "=", count: title.count), "", "Planned moves: \(moves.count)"]
        if moves.isEmpty {
            lines.append("No changes suggested.")
        } else {
            for move in moves {
                lines.append("\n[\(move.reason)]")
                lines.append("from: \(move.fromPath)")
                lines.append("to:   \(move.toPath)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func restoreReport(createdAt: Date, restored: [PlannedMove], skipped: [PlannedMove]) -> String {
        var lines = [
            "Sable's Library restore",
            "======================",
            "",
            "Undo plan created: \(createdAt.formatted(.iso8601))",
            "Restored: \(restored.count)",
            "Skipped: \(skipped.count)"
        ]

        if !restored.isEmpty {
            lines.append("\nRestored moves")
            for move in restored {
                lines.append("\n[\(move.reason)]")
                lines.append("from: \(move.fromPath)")
                lines.append("to:   \(move.toPath)")
            }
        }

        if !skipped.isEmpty {
            lines.append("\nSkipped moves")
            lines.append("Skipped when the restore source was missing, the original path already existed, or the move was a no-op.")
            for move in skipped {
                lines.append("\n[\(move.reason)]")
                lines.append("from: \(move.toPath)")
                lines.append("to:   \(move.fromPath)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func writeReport(_ text: String, named name: String, root: URL, config: SableLibraryConfig) throws {
        try ensureReportDirectory(root: root, config: config)
        try text.write(to: reportDirectory(root: root, config: config).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @discardableResult
    func writeRootLibraryCatalog(
        inspection: LibraryInspection,
        root: URL,
        config: SableLibraryConfig
    ) throws -> URL {
        let catalogURL = root.appendingPathComponent(config.reports.rootCatalogCSV, isDirectory: false)
        let rows = rootLibraryCatalogRows(inspection: inspection)
        let headers = [
            "kind",
            "form",
            "series_title",
            "preferred_title",
            "local_title",
            "series_path",
            "file_name",
            "file_path",
            "file_extension",
            "file_count",
            "year",
            "source_provider",
            "source_id",
            "sidecar",
            "updated_at"
        ]
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var lines = [headers.map(csvEscapedField).joined(separator: ",")]
        for row in rows {
            var enriched = row
            enriched["updated_at"] = timestamp
            lines.append(headers.map { csvEscapedField(enriched[$0] ?? "") }.joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: catalogURL, atomically: true, encoding: .utf8)
        return catalogURL
    }

    func ensureReportDirectory(root: URL, config: SableLibraryConfig) throws {
        try fileManager.createDirectory(at: reportDirectory(root: root, config: config), withIntermediateDirectories: true)
    }

    func reportDirectory(root: URL, config: SableLibraryConfig) -> URL {
        root.appendingPathComponent(config.reportFolderName, isDirectory: true)
    }

    private func rootLibraryCatalogRows(inspection: LibraryInspection) -> [[String: String]] {
        let readingSeriesByPath = inspection.series.reduce(into: [String: LibrarySeriesSnapshot]()) { partialResult, series in
            partialResult[series.path] = series
        }
        let videoSeriesByPath = inspection.videoSeries.reduce(into: [String: LibraryVideoSeriesSnapshot]()) { partialResult, series in
            partialResult[series.path] = series
        }

        var rows: [[String: String]] = inspection.books
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { book in
                let series = book.seriesID.flatMap { readingSeriesByPath[$0] }
                let sourceID = series?.primarySourceID
                return [
                    "kind": "book",
                    "form": series.map(catalogReadingForm(for:)) ?? inferredCatalogForm(from: book.seriesID ?? book.path),
                    "series_title": series?.displayName ?? catalogSeriesTitle(from: book.seriesID ?? book.path),
                    "preferred_title": series?.preferredTitle ?? "",
                    "local_title": series?.localTitle ?? "",
                    "series_path": book.seriesID ?? "",
                    "file_name": book.fileName,
                    "file_path": book.path,
                    "file_extension": book.fileExtension.uppercased(),
                    "file_count": series.map { "\($0.localBookCount)" } ?? "",
                    "year": series?.year.map { "\($0)" } ?? "",
                    "source_provider": sourceID?.provider.rawValue ?? "",
                    "source_id": sourceID?.value ?? "",
                    "sidecar": catalogSidecarStatus(hasSidecar: series?.hasComicInfo, missingPaths: inspection.missingComicInfoSeriesPaths, seriesPath: book.seriesID)
                ]
            }

        rows += inspection.videos
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { video in
                let series = video.seriesID.flatMap { videoSeriesByPath[$0] }
                let sourceID = series?.primarySourceID
                return [
                    "kind": "video",
                    "form": series.map(catalogWatchingForm(for:)) ?? inferredCatalogForm(from: video.seriesID ?? video.path),
                    "series_title": series?.displayName ?? catalogSeriesTitle(from: video.seriesID ?? video.path),
                    "preferred_title": series?.preferredTitle ?? "",
                    "local_title": series?.localTitle ?? "",
                    "series_path": video.seriesID ?? "",
                    "file_name": video.fileName,
                    "file_path": video.path,
                    "file_extension": video.fileExtension.uppercased(),
                    "file_count": series.map { "\($0.localVideoCount)" } ?? "",
                    "year": series?.year.map { "\($0)" } ?? "",
                    "source_provider": sourceID?.provider.rawValue ?? "",
                    "source_id": sourceID?.value ?? "",
                    "sidecar": catalogSidecarStatus(hasSidecar: series?.hasAnimeInfo, missingPaths: inspection.missingAnimeInfoSeriesPaths, seriesPath: video.seriesID)
                ]
            }

        return rows
    }

    private func catalogSidecarStatus(hasSidecar: Bool?, missingPaths: [String], seriesPath: String?) -> String {
        if hasSidecar == true {
            return "present"
        }
        guard let seriesPath else {
            return hasSidecar == false ? "missing" : "unknown"
        }
        if missingPaths.contains(seriesPath) {
            return "missing"
        }
        return hasSidecar == false ? "missing" : "unknown"
    }

    private func inferredCatalogForm(from path: String) -> String {
        let first = path.split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        switch first {
        case "light novels": return "Light novels"
        case "manga": return "Manga"
        case "manhwa": return "Manhwa"
        case "manhua": return "Manhua"
        case "oel": return "OEL"
        case "tv", "tv shows", "anime tv": return "TV"
        case "movies", "anime movies": return "Movies"
        default: return first.isEmpty ? "Unknown" : first
        }
    }

    private func catalogReadingForm(for series: LibrarySeriesSnapshot) -> String {
        let candidates = [
            series.mediaType,
            inferredCatalogForm(from: series.path)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates where !candidate.isEmpty {
            switch candidate.lowercased() {
            case "novel", "light novel", "light novels":
                return "Light novels"
            case "manga":
                return "Manga"
            case "manhwa":
                return "Manhwa"
            case "manhua":
                return "Manhua"
            case "oel":
                return "OEL"
            default:
                continue
            }
        }
        return "Unknown"
    }

    private func catalogWatchingForm(for series: LibraryVideoSeriesSnapshot) -> String {
        let candidates = [
            series.mediaType,
            inferredCatalogForm(from: series.path)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates where !candidate.isEmpty {
            switch candidate.lowercased() {
            case "animetv", "anime tv", "ova", "ona", "special", "specials", "tvshow", "tv show", "tv", "tv shows":
                return "TV"
            case "animemovie", "anime movie", "movie", "movies":
                return "Movies"
            case "other videos":
                return "Other videos"
            default:
                continue
            }
        }
        return "Unknown"
    }

    private func catalogSeriesTitle(from path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return "" }
        return last.replacingOccurrences(
            of: #"\s+\(\d{4}\)(?:\s+\{[^}]+\})*\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    private func csvEscapedField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
