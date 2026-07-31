//
//  SableLibraryNamingPolicy.swift
//  Sable's Library
//

import Foundation

struct SableLibraryNamingPolicy: Sendable {
    func safePreferredTitle(_ title: String) -> String {
        sanitizeFilename(
            title
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ":", with: "")
        )
    }

    func canonicalFolderName(preferredTitle: String, mediaType: String) -> String {
        let safeTitle = safePreferredTitle(preferredTitle)
        let safeType = normalizedMediaType(mediaType)
        return "\(safeTitle) - \(safeType)"
    }

    func canonicalReadingFolderName(preferredTitle: String, year: Int?, sourceID: SableLibrarySourceID?, mediaType: String) -> String {
        canonicalReadingFolderName(
            preferredTitle: preferredTitle,
            year: year,
            sourceIDs: [sourceID].compactMap { $0 },
            mediaType: mediaType
        )
    }

    func canonicalReadingFolderName(preferredTitle: String, year: Int?, sourceIDs: [SableLibrarySourceID], mediaType: String) -> String {
        let tokens = readingFolderSourceTokens(from: sourceIDs)
        if !tokens.isEmpty {
            let title = safePreferredTitle(preferredTitle)
            let yearText = year.map { " (\($0))" } ?? ""
            return "\(title)\(yearText) \(tokens.joined(separator: " "))"
        }

        if let year {
            return "\(safePreferredTitle(preferredTitle)) (\(year))"
        }

        return canonicalFolderName(preferredTitle: preferredTitle, mediaType: mediaType)
    }

    func canonicalReadingSeriesPath(preferredTitle: String, year: Int?, sourceID: SableLibrarySourceID?, mediaType: String) -> String {
        canonicalReadingSeriesPath(
            preferredTitle: preferredTitle,
            year: year,
            sourceIDs: [sourceID].compactMap { $0 },
            mediaType: mediaType
        )
    }

    func canonicalReadingSeriesPath(preferredTitle: String, year: Int?, sourceIDs: [SableLibrarySourceID], mediaType: String) -> String {
        let folder = canonicalReadingFolderName(
            preferredTitle: preferredTitle,
            year: year,
            sourceIDs: sourceIDs,
            mediaType: mediaType
        )
        return "\(readingRootFolder(for: mediaType))/\(folder)"
    }

    func canonicalWatchingFolderName(preferredTitle: String, year: Int?, sourceID: SableLibrarySourceID?) -> String {
        if let sourceID, isPlexSupportedWatchingSourceID(sourceID) {
            return canonicalPlexStyleName(preferredTitle: preferredTitle, year: year, sourceID: sourceID)
        }
        if let year {
            return "\(safePreferredTitle(preferredTitle)) (\(year))"
        }
        return safePreferredTitle(preferredTitle)
    }

    func canonicalWatchingSeriesPath(preferredTitle: String, year: Int?, sourceID: SableLibrarySourceID?, mediaType: String) -> String {
        let plexSourceID = sourceID.flatMap {
            isPlexSupportedWatchingSourceID($0, mediaType: mediaType) ? $0 : nil
        }
        let folder = canonicalWatchingFolderName(preferredTitle: preferredTitle, year: year, sourceID: plexSourceID)
        return "\(watchingRootFolder(for: mediaType))/\(folder)"
    }

    func canonicalReadingFileName(preferredTitle: String, year: Int?, suffix: String?, fileExtension: String) -> String {
        canonicalReadingFileName(
            preferredTitle: preferredTitle,
            year: year,
            sourceIDs: [],
            suffix: suffix,
            fileExtension: fileExtension
        )
    }

    func canonicalReadingFileName(
        preferredTitle: String,
        year: Int?,
        sourceIDs: [SableLibrarySourceID],
        suffix: String?,
        fileExtension: String
    ) -> String {
        let title = safePreferredTitle(readingTitleForFileName(preferredTitle, suffix: suffix))
        let yearText = year.map { " (\($0))" } ?? ""
        let tokens = readingFolderSourceTokens(from: sourceIDs)
        let tokenText = tokens.isEmpty ? "" : " \(tokens.joined(separator: " "))"
        let cleanExtension = fileExtension.hasPrefix(".") ? fileExtension : ".\(fileExtension)"
        if let suffix, !suffix.isEmpty {
            return "\(title)\(yearText)\(tokenText) - \(suffix)\(cleanExtension)"
        }
        return "\(title)\(yearText)\(tokenText)\(cleanExtension)"
    }

    func canonicalFileName(preferredTitle: String, suffix: String?, fileExtension: String) -> String {
        let safeTitle = safePreferredTitle(preferredTitle)
        let cleanExtension = fileExtension.hasPrefix(".") ? fileExtension : ".\(fileExtension)"
        if let suffix, !suffix.isEmpty {
            return "\(safeTitle) - \(suffix)\(cleanExtension)"
        }
        return "\(safeTitle)\(cleanExtension)"
    }

    private func readingTitleForFileName(_ preferredTitle: String, suffix: String?) -> String {
        guard let suffixVolume = volumeNumber(from: suffix) else {
            return preferredTitle
        }
        let pattern = #"(?i)\s*[,:\-–—]?\s*(?:vol(?:ume)?\.?|book)\s*0*\#(suffixVolume)(?:\b|$)(?:\s*[:\-–—]\s*.+)?\s*$"#
        let stripped = preferredTitle
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:-–—")))
        return stripped.isEmpty ? preferredTitle : stripped
    }

    private func volumeNumber(from suffix: String?) -> Int? {
        guard let suffix,
              let range = suffix.range(of: #"(?i)\bvol(?:ume)?\.?\s*0*(\d{1,4})\b"#, options: .regularExpression) else {
            return nil
        }
        let match = String(suffix[range])
        guard let digitRange = match.range(of: #"\d{1,4}"#, options: .regularExpression) else {
            return nil
        }
        return Int(match[digitRange])
    }

    func canonicalWatchingMovieFileName(preferredTitle: String, year: Int?, fileExtension: String) -> String {
        canonicalWatchingMovieFileName(preferredTitle: preferredTitle, year: year, sourceID: nil, fileExtension: fileExtension)
    }

    func canonicalWatchingMovieFileName(preferredTitle: String, year: Int?, sourceID: SableLibrarySourceID?, fileExtension: String) -> String {
        let baseName: String
        if let sourceID, isPlexSupportedMovieSourceID(sourceID) {
            baseName = canonicalPlexStyleName(preferredTitle: preferredTitle, year: year, sourceID: sourceID)
        } else {
            baseName = titleWithYear(preferredTitle, year: year)
        }
        return "\(baseName)\(cleanExtension(fileExtension))"
    }

    func canonicalWatchingEpisodeFileName(
        preferredTitle: String,
        year: Int?,
        season: Int,
        episode: Int,
        episodeTitle: String?,
        fileExtension: String
    ) -> String {
        canonicalWatchingEpisodeFileName(
            preferredTitle: preferredTitle,
            year: year,
            season: season,
            episode: episode,
            endSeason: nil,
            endEpisode: nil,
            episodeTitle: episodeTitle,
            fileExtension: fileExtension
        )
    }

    func canonicalWatchingEpisodeFileName(
        preferredTitle: String,
        year: Int?,
        season: Int,
        episode: Int,
        endSeason: Int?,
        endEpisode: Int?,
        episodeTitle: String?,
        fileExtension: String
    ) -> String {
        let episodeCode = watchingEpisodeCode(
            season: season,
            episode: episode,
            endSeason: endSeason,
            endEpisode: endEpisode
        )
        let titleSuffix = episodeTitle
            .map(safePreferredTitle)
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { " - \($0)" } ?? ""
        return "\(titleWithYear(preferredTitle, year: year)) - \(episodeCode)\(titleSuffix)\(cleanExtension(fileExtension))"
    }

    func plexSeasonFolderName(season: Int) -> String {
        "Season \(paddedSeasonEpisode(max(0, season)))"
    }

    func normalizedMediaType(_ mediaType: String) -> String {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manga":
            "Manga"
        case "manhwa":
            "Manhwa"
        case "manhua":
            "Manhua"
        case "novel", "light novel", "light novels", "lightnovel":
            "Novel"
        case "book", "books":
            "Book"
        case "oel", "original english language":
            "OEL"
        case "other":
            "Other"
        default:
            "Unknown"
        }
    }

    func readingRootFolder(for mediaType: String) -> String {
        switch normalizedMediaType(mediaType) {
        case "Manga": "Manga"
        case "Manhwa": "Manhwa"
        case "Manhua": "Manhua"
        case "OEL": "OEL"
        case "Novel": "Light Novels"
        case "Book": "Books"
        case "Other": "Other Reading"
        default: "Books"
        }
    }

    func watchingRootFolder(for mediaType: String) -> String {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "animemovie", "anime movie", "movie":
            "Movies"
        case "animetv", "anime tv", "ova", "ona", "special", "specials",
             "tvshow", "tv show", "tv":
            "TV"
        default:
            "Other Videos"
        }
    }

    func canonicalPlexStyleName(preferredTitle: String, year: Int?, sourceID: SableLibrarySourceID) -> String {
        let title = safePreferredTitle(preferredTitle)
        let yearText = year.map { " (\($0))" } ?? ""
        return "\(title)\(yearText) {\(sourcePrefix(for: sourceID.provider))-\(sourceID.value)}"
    }

    private func titleWithYear(_ title: String, year: Int?) -> String {
        let safeTitle = safePreferredTitle(title)
        guard let year else { return safeTitle }
        return "\(safeTitle) (\(year))"
    }

    private func cleanExtension(_ fileExtension: String) -> String {
        guard !fileExtension.isEmpty else { return "" }
        return fileExtension.hasPrefix(".") ? fileExtension.lowercased() : ".\(fileExtension.lowercased())"
    }

    private func paddedSeasonEpisode(_ value: Int) -> String {
        String(format: "%02d", max(0, value))
    }

    private func watchingEpisodeCode(season: Int, episode: Int, endSeason: Int?, endEpisode: Int?) -> String {
        let startCode = "S\(paddedSeasonEpisode(season))E\(paddedSeasonEpisode(episode))"
        guard let endEpisode else { return startCode }
        if let endSeason, endSeason != season {
            return "\(startCode)-S\(paddedSeasonEpisode(endSeason))E\(paddedSeasonEpisode(endEpisode))"
        }
        return "\(startCode)-E\(paddedSeasonEpisode(endEpisode))"
    }

    private func sourcePrefix(for provider: SableLibraryMetadataProvider) -> String {
        switch provider {
        case .mangabaka: "mb"
        case .ranobedb: "rdb"
        case .openLibrary: "ol"
        case .myAnimeList: "mal"
        case .anilist: "al"
        case .tvmaze: "tvmaze"
        case .wikidata: "wd"
        case .tmdb: "tmdb"
        case .tvdb: "tvdb"
        case .imdb: "imdb"
        case .local: "local"
        }
    }

    private func readingFolderSourceTokens(from sourceIDs: [SableLibrarySourceID]) -> [String] {
        var selected: [SableLibrarySourceID] = []
        var seen = Set<String>()

        func append(_ sourceID: SableLibrarySourceID?) {
            guard let sourceID else { return }
            let key = "\(sourceID.provider.rawValue):\(sourceID.value)"
            guard seen.insert(key).inserted else { return }
            selected.append(sourceID)
        }

        // Reading folders prefer local reading anchors. MB/RDB can come from trusted
        // sidecars; MAL/AniList are preserved when the local folder already carries them.
        append(sourceIDs.first { $0.provider == .mangabaka })
        append(sourceIDs.first { $0.provider == .ranobedb })
        append(sourceIDs.first { $0.provider == .myAnimeList })
        append(sourceIDs.first { $0.provider == .anilist })

        return selected.map { "{\(sourcePrefix(for: $0.provider))-\($0.value)}" }
    }

    private func isPlexSupportedWatchingSourceID(_ sourceID: SableLibrarySourceID) -> Bool {
        switch sourceID.provider {
        case .tmdb, .tvdb, .imdb:
            true
        case .mangabaka, .ranobedb, .openLibrary, .myAnimeList, .anilist, .tvmaze, .wikidata, .local:
            false
        }
    }

    private func isPlexSupportedWatchingSourceID(_ sourceID: SableLibrarySourceID, mediaType: String) -> Bool {
        if isMovieMediaType(mediaType) {
            return isPlexSupportedMovieSourceID(sourceID)
        }
        return isPlexSupportedWatchingSourceID(sourceID)
    }

    private func isPlexSupportedMovieSourceID(_ sourceID: SableLibrarySourceID) -> Bool {
        switch sourceID.provider {
        case .tmdb, .imdb:
            true
        case .mangabaka, .ranobedb, .openLibrary, .myAnimeList, .anilist, .tvmaze, .wikidata, .tvdb, .local:
            false
        }
    }

    private func isMovieMediaType(_ mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie":
            true
        default:
            false
        }
    }

    func mediaTypeHint(in name: String) -> String? {
        let pattern = #"(?i)(?:\s+-\s+|\s+the\s+|\s+|\()(light\s+novel|novel|manga|manhwa|manhua|oel|other|comic|comics)\)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
              let range = Range(match.range(at: 1), in: name) else {
            return nil
        }
        let rawType = String(name[range])
        let type = rawType.lowercased().contains("comic") ? "Manga" : normalizedMediaType(rawType)
        return type == "Unknown" ? nil : type
    }

    private func sanitizeFilename(_ value: String) -> String {
        var result = value
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*")
        result = String(result.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*-\s*-\s*"#, with: " - ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*-\s*$"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^\s*-\s*"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))
        return result.isEmpty ? "Untitled" : result
    }
}
