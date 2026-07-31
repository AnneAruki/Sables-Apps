//
//  SableLibraryTextCleaning.swift
//  Sable's Library
//

import Foundation

extension SableLibraryService {
    func addUnique(_ value: String?, to values: inout [String]) {
        guard let value, !value.isEmpty else { return }
        let key = normalizeTerm(value)
        if !values.contains(where: { normalizeTerm($0) == key }) {
            values.append(value)
        }
    }

    func textValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    func cleanSeriesTitle(_ title: String) -> String {
        sanitizeFilename(title.replacingOccurrences(of: "_", with: " "))
    }

    func safePreferredTitle(_ title: String) -> String {
        sanitizeFilename(
            title
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ":", with: "")
        )
    }

    func displayMetadataTerm(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return collapsed }

        let phraseKey = normalizeTerm(collapsed)
        let phraseOverrides: [String: String] = [
            "boys love": "Boys Love",
            "girls love": "Girls Love",
            "light novel": "Light Novel",
            "science fiction": "Science Fiction",
            "slice of life": "Slice of Life",
            "web novel": "Web Novel",
            "coming of age": "Coming of Age",
            "alternate history": "Alternate History",
            "virtual reality": "Virtual Reality"
        ]
        if let override = phraseOverrides[phraseKey] {
            return override
        }

        var wordIndex = 0
        return collapsed
            .components(separatedBy: " ")
            .map { word in
                defer { wordIndex += 1 }
                return displayMetadataWordGroup(word, isFirstWord: wordIndex == 0)
            }
            .joined(separator: " ")
    }

    func displayMetadataTerms(_ values: [String]) -> [String] {
        values.map(displayMetadataTerm)
    }

    private func displayMetadataWordGroup(_ value: String, isFirstWord: Bool) -> String {
        var result = ""
        var current = ""
        var isFirstSegment = true

        func flush() {
            guard !current.isEmpty else { return }
            result += displayMetadataWord(
                current,
                isFirstWord: isFirstWord && isFirstSegment
            )
            current = ""
            isFirstSegment = false
        }

        for character in value {
            if character == "-" || character == "/" {
                flush()
                result.append(character)
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }

    private func displayMetadataWord(_ value: String, isFirstWord: Bool) -> String {
        let characters = Array(value)
        guard let start = characters.firstIndex(where: metadataCharacterIsAlphaNumeric),
              let end = characters.lastIndex(where: metadataCharacterIsAlphaNumeric) else {
            return value
        }

        let prefix = String(characters[..<start])
        let core = String(characters[start...end])
        let suffix = end + 1 < characters.count ? String(characters[(end + 1)...]) : ""
        let acronymKey = core.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9+]+"#, with: "", options: .regularExpression)
        let acronymOverrides: [String: String] = [
            "ai": "AI",
            "bl": "BL",
            "bdsm": "BDSM",
            "cg": "CG",
            "epub": "EPUB",
            "gl": "GL",
            "isbn": "ISBN",
            "lgbt": "LGBT",
            "lgbtq": "LGBTQ",
            "oel": "OEL",
            "ona": "ONA",
            "ova": "OVA",
            "pdf": "PDF",
            "r18": "R18",
            "tv": "TV",
            "vr": "VR",
            "ya": "YA"
        ]
        if let override = acronymOverrides[acronymKey] {
            return prefix + override + suffix
        }

        let lowerCore = core.lowercased()
        let smallWords: Set<String> = [
            "a", "an", "and", "as", "at", "but", "by", "for", "from",
            "in", "into", "nor", "of", "on", "or", "the", "to", "via",
            "vs", "with", "without"
        ]
        if !isFirstWord, smallWords.contains(lowerCore) {
            return prefix + lowerCore + suffix
        }

        let hasLetters = core.contains(where: metadataCharacterIsLetter)
        let isAllUppercase = hasLetters && core == core.uppercased() && core != core.lowercased()
        let hasInternalUppercase = core.dropFirst().contains(where: metadataCharacterIsUppercase)
        if isAllUppercase || hasInternalUppercase {
            return value
        }

        guard let first = core.first else { return value }
        let titleCased = String(first).uppercased() + String(core.dropFirst()).lowercased()
        return prefix + titleCased + suffix
    }

    private func metadataCharacterIsAlphaNumeric(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private func metadataCharacterIsLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private func metadataCharacterIsUppercase(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    func bookNameParts(
        for rawName: String,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>? = nil
    ) -> BookNameParts {
        let cleaned = cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys)
        if isClockTitle(cleaned) {
            let title = filesystemClockTitle(cleaned)
            return BookNameParts(seriesTitle: title, fileTitle: title, needsManualReview: false)
        }

        if let yearTitle = titleByConvertingTrailingVolumeYear(from: cleaned) {
            let title = titleCasedSeriesName(yearTitle)
            let needsReview = compactTitleNeedsManualReview(raw: yearTitle, spaced: spacedSeriesName(yearTitle))
            return BookNameParts(seriesTitle: title, fileTitle: title, needsManualReview: needsReview)
        }

        if let suffix = volumeOrChapterSuffix(in: cleaned),
           let rawTitle = titleByRemovingTrailingSuffix(from: cleaned),
           !rawTitle.isEmpty {
            let seriesTitle = titleCasedSeriesName(rawTitle)
            let needsReview = compactTitleNeedsManualReview(raw: rawTitle, spaced: spacedSeriesName(rawTitle))
            return BookNameParts(
                seriesTitle: seriesTitle,
                fileTitle: bookFileTitle(seriesTitle: seriesTitle, suffix: suffix),
                needsManualReview: needsReview
            )
        }

        let title = titleCasedSeriesName(cleaned)
        let needsReview = compactTitleNeedsManualReview(raw: cleaned, spaced: spacedSeriesName(cleaned))
        return BookNameParts(seriesTitle: title, fileTitle: title, needsManualReview: needsReview)
    }

    func preferredBookFileTitle(
        rawName: String,
        parentFolderName: String?,
        requiresTitleMatch: Bool = true,
        maximumVolume: Int? = nil,
        bookCountInFolder: Int = 1,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>? = nil
    ) -> BookNameParts {
        let parsed = bookNameParts(for: rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys)
        guard let parentFolderName else { return parsed }

        let preferredSeriesTitle = safePreferredTitle(parentFolderName)
        guard !preferredSeriesTitle.isEmpty else { return parsed }

        let cleaned = cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys)
        guard let suffix = volumeOrChapterSuffix(in: cleaned) else {
            return parsed
        }

        let titleWithoutSuffix = titleByRemovingTrailingSuffix(from: cleaned) ?? cleaned
        let fileSeriesTitle = preferredSeriesTitleWithoutMatchingSuffix(
            preferredSeriesTitle: preferredSeriesTitle,
            titleWithoutSuffix: titleWithoutSuffix,
            suffix: suffix
        ) ?? preferredSeriesTitle

        let normalizedFileTitle = normalizeTerm(titleWithoutSuffix)
        let normalizedParentTitle = normalizeTerm(preferredSeriesTitle)
        if requiresTitleMatch {
            guard normalizedFileTitle == normalizedParentTitle || normalizedParentTitle.hasPrefix(normalizedFileTitle) || normalizedFileTitle.hasPrefix(normalizedParentTitle) else {
                return parsed
            }
        }

        if let maximumVolume,
           let volume = volumeNumber(in: suffix),
           volume > maximumVolume {
            return BookNameParts(
                seriesTitle: preferredSeriesTitle,
                fileTitle: bookFileTitle(seriesTitle: fileSeriesTitle, suffix: suffix),
                needsManualReview: true
            )
        }

        return BookNameParts(
            seriesTitle: fileSeriesTitle,
            fileTitle: bookFileTitle(seriesTitle: fileSeriesTitle, suffix: suffix),
            needsManualReview: parsed.needsManualReview
        )
    }

    private func preferredSeriesTitleWithoutMatchingSuffix(
        preferredSeriesTitle: String,
        titleWithoutSuffix: String,
        suffix: String
    ) -> String? {
        guard let parentTitle = titleByRemovingTrailingSuffix(from: preferredSeriesTitle),
              let parentSuffix = volumeOrChapterSuffix(in: preferredSeriesTitle),
              normalizeTerm(parentTitle) == normalizeTerm(titleWithoutSuffix),
              normalizeTerm(parentSuffix) == normalizeTerm(suffix) else {
            return nil
        }

        return parentTitle
    }

    func titleByRemovingTrailingSuffix(from name: String) -> String? {
        let normalizedName = normalizedReadingVolumeOCR(in: name)
        guard volumeOrChapterSuffix(in: normalizedName) != nil else {
            return nil
        }
        let title = normalizedName
            .replacingOccurrences(
                of: #"(?i)\s*(?:[-–—]\s*)?(?:vol(?:ume)?|v|chapter|ch)\.?\s*0*\d{1,4}(?:\.\d+)?(?:\s*[-–—]\s*0*\d{1,4})?(?:\s*[-–—:]\s*.+)?\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title == normalizedName ? nil : title
    }

    func bookFileTitle(seriesTitle: String, suffix: String) -> String {
        let cleanSuffix = suffix
            .replacingOccurrences(of: #"^\s*[-–—]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanSuffix.isEmpty ? seriesTitle : "\(seriesTitle) - \(cleanSuffix)"
    }

    func volumeNumber(in suffix: String) -> Int? {
        let suffix = normalizedReadingVolumeOCR(in: suffix)
        let pattern = #"(?i)^vol\s*(\d{1,4})(?:\.\d+)?(?:\s*[-–—:]\s*.+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)),
              let numberRange = matchedRange(at: 1, in: match, text: suffix) else {
            return nil
        }
        return Int(suffix[numberRange])
    }

    func compactTitleNeedsManualReview(raw: String, spaced: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let trustedCompactTitles = ["hitorijimemyhero", "whispermealovesong", "chasingafteraoikoshiba"]
        guard !trustedCompactTitles.contains(lowercased) else { return false }
        guard trimmed.count >= 12 else { return false }
        guard !trimmed.contains(" "), !trimmed.contains("_"), !trimmed.contains("-"), !trimmed.contains(".") else { return false }
        return spaced.contains(" ") && normalizeTerm(spaced) != normalizeTerm(trimmed)
    }

    func titleCasedSeriesName(_ value: String) -> String {
        if isClockTitle(value) {
            return filesystemClockTitle(value)
        }

        let spaced = spacedSeriesName(value)
        return spaced
            .split(separator: " ")
            .map { token in
                let lowercasedToken = token.lowercased()
                if lowercasedToken.range(of: #"^\d+(st|nd|rd|th)$"#, options: .regularExpression) != nil {
                    return lowercasedToken
                }
                return String(token.prefix(1)).uppercased() + String(token.dropFirst()).lowercased()
            }
            .joined(separator: " ")
    }

    func spacedSeriesName(_ value: String) -> String {
        if isClockTitle(value) {
            return filesystemClockTitle(value)
        }

        var result = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([A-Za-z])([0-9])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([0-9])([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b([0-9]+)\s+(st|nd|rd|th)\b"#, with: "$1$2", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.contains(" ") {
            return result
        }

        let knownCompactTitles = [
            "hitorijimemyhero": "hitorijime my hero",
            "whispermealovesong": "whisper me a love song",
            "chasingafteraoikoshiba": "chasing after aoi koshiba"
        ]
        if let knownTitle = knownCompactTitles[result.lowercased()] {
            return knownTitle
        }

        let compactWords = [
            "hitorijime", "whisper", "chasing", "after", "aoi", "koshiba",
            "hero", "love", "song", "me", "my", "a"
        ].sorted { $0.count > $1.count }

        var remaining = result.lowercased()
        var words: [String] = []
        while !remaining.isEmpty {
            if let word = compactWords.first(where: { remaining.hasPrefix($0) }) {
                words.append(word)
                remaining.removeFirst(word.count)
            } else {
                return result
            }
        }

        result = words.joined(separator: " ")
        return result
    }

    func volumeOrChapterSuffix(in name: String) -> String? {
        let name = normalizedReadingVolumeOCR(in: name)
        let pattern = #"(?i)\b((vol(?:ume)?|v|chapter|ch)\.?\s*(0*\d{1,4}(?:\.\d+)?)(?:\s*[-–—]\s*(0*\d{1,4}))?)(?:\s*[-–—:]\s*(.+?))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)).last,
              let markerRange = matchedRange(at: 2, in: match, text: name),
              let numberRange = matchedRange(at: 3, in: match, text: name) else {
            return nil
        }
        let lower = String(name[markerRange]).lowercased()
        let number = String(name[numberRange])
        let trimmedNumber = String(number.drop { $0 == "0" })
        let normalizedNumber = trimmedNumber.isEmpty ? "0" : trimmedNumber
        let rangeNumber = optionalRegexString(match, group: 4, in: name)
        let title = optionalRegexString(match, group: 5, in: name)
            .map(partTitleSuffix)
            .flatMap { $0?.isEmpty == false ? $0 : nil }
        if !lower.hasPrefix("ch"),
           rangeNumber == nil,
           title == nil,
           isLikelyYearDisguisedAsVolume(normalizedNumber) {
            return nil
        }
        let paddedVolume = normalizedNumber.count == 1 ? "0\(normalizedNumber)" : normalizedNumber

        let suffix: String
        if lower.hasPrefix("ch") || lower.hasPrefix("chapter") {
            let paddedChapter = paddedReadingChapter(normalizedNumber)
            if let rangeNumber {
                let trimmedRange = String(rangeNumber.drop { $0 == "0" })
                let normalizedRange = trimmedRange.isEmpty ? "0" : trimmedRange
                suffix = "Ch \(paddedChapter)-\(paddedReadingChapter(normalizedRange))"
            } else {
                suffix = "Ch \(paddedChapter)"
            }
        } else {
            suffix = "Vol \(paddedVolume)"
        }
        guard let title else { return suffix }
        return "\(suffix) - \(title)"
    }

    private func isLikelyYearDisguisedAsVolume(_ value: String) -> Bool {
        guard value.count == 4,
              let year = Int(value) else {
            return false
        }
        return (1800...2100).contains(year)
    }

    private func titleByConvertingTrailingVolumeYear(from name: String) -> String? {
        let normalizedName = normalizedReadingVolumeOCR(in: name)
        let trimmed = normalizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let yearRange = trailingVolumeYearRange(in: trimmed),
              let year = Int(trimmed[yearRange]),
              year <= 2100,
              let title = titleBeforeTrailingVolumeYear(in: trimmed, yearRange: yearRange) else {
            return nil
        }

        return "\(title) (\(year))"
    }

    private func trailingVolumeYearRange(in value: String) -> Range<String.Index>? {
        guard value.count >= 4 else { return nil }
        let end = value.endIndex
        let start = value.index(end, offsetBy: -4)
        let candidate = value[start..<end]
        guard candidate.allSatisfy(\.isNumber),
              let year = Int(candidate),
              (1800...2100).contains(year) else {
            return nil
        }
        return start..<end
    }

    private func titleBeforeTrailingVolumeYear(
        in value: String,
        yearRange: Range<String.Index>
    ) -> String? {
        var prefix = String(value[..<yearRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return nil }

        let lower = prefix.lowercased()
        let markers = ["volume.", "volume", "vol.", "vol"]
        guard let marker = markers.first(where: { lower.hasSuffix($0) }) else {
            return nil
        }

        let markerStart = prefix.index(prefix.endIndex, offsetBy: -marker.count)
        if markerStart > prefix.startIndex {
            let previous = prefix[prefix.index(before: markerStart)]
            guard previous.isWhitespace || "-–—".contains(previous) else {
                return nil
            }
        }

        prefix.removeSubrange(markerStart..<prefix.endIndex)
        let title = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
        return title.isEmpty ? nil : title
    }

    private func normalizedReadingVolumeOCR(in value: String) -> String {
        value.replacingOccurrences(
            of: #"(?i)\b(vol(?:ume)?|v)\.?\s+o[l1i]\s+(\d{1,4})(?=\b)"#,
            with: "$1 $2",
            options: .regularExpression
        )
    }

    private func paddedReadingChapter(_ value: String) -> String {
        String(repeating: "0", count: max(0, 4 - value.count)) + value
    }

    private func partTitleSuffix(_ value: String) -> String? {
        let title = sanitizeFilename(value)
            .replacingOccurrences(of: #"(?i)\s*\.(?:cbz|cbr|zip|rar|epub|pdf|mobi|azw3)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeTerm(title)
        let ignored = ["digital", "retail", "epub", "pdf", "cbz", "cbr", "raw", "scan", "official"]
        guard !title.isEmpty, !ignored.contains(normalized) else { return nil }
        return title
    }

    private func optionalRegexString(
        _ match: NSTextCheckingResult,
        group: Int,
        in source: String
    ) -> String? {
        let nsRange = match.range(at: group)
        guard nsRange.location != NSNotFound,
              let range = Range(nsRange, in: source) else {
            return nil
        }
        return String(source[range])
    }

    private func isClockTitle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^(?:[01]?\d|2[0-3])[-:.][0-5]\d$"#, options: .regularExpression) != nil
    }

    private func filesystemClockTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    func cleanedTitle(
        _ value: String,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>? = nil
    ) -> String {
        var title = value.replacingOccurrences(of: "_", with: " ")
        var knownTerms = Set(config.sourceMetadataTerms.map(normalizeTerm))
        if let sourceMetadataTermKeys {
            knownTerms.formUnion(sourceMetadataTermKeys)
        }
        let sourceNoteRanges = sourceNoteRangesToRemove(in: title, knownTerms: knownTerms)
        for range in sourceNoteRanges.reversed() {
            title.removeSubrange(range)
        }

        title = removingTrailingBracketSourceNotesAfterReadingSuffix(from: title, knownTerms: knownTerms)
        title = removingMalformedTrailingReadingSourceNotes(from: title, knownTerms: knownTerms)
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+-\s+$"#, with: "", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? value : title
    }

    private func sourceNoteRangesToRemove(
        in title: String,
        knownTerms: Set<String>
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = title.startIndex

        while index < title.endIndex {
            let opener = title[index]
            let closer: Character
            if opener == "[" {
                closer = "]"
            } else if opener == "(" {
                closer = ")"
            } else {
                index = title.index(after: index)
                continue
            }

            let contentStart = title.index(after: index)
            guard let closeIndex = title[contentStart...].firstIndex(of: closer) else {
                index = title.index(after: index)
                continue
            }

            let content = String(title[contentStart..<closeIndex])
            if sourceNoteShouldBeRemoved(content, knownTerms: knownTerms) {
                ranges.append(index..<title.index(after: closeIndex))
            }
            index = title.index(after: closeIndex)
        }

        return ranges
    }

    private func matchedRange(at index: Int, in match: NSTextCheckingResult, text: String) -> Range<String.Index>? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return Range(range, in: text)
    }

    private func sourceNoteShouldBeRemoved(_ value: String, knownTerms: Set<String>) -> Bool {
        let normalized = normalizeTerm(value)
        guard !normalized.isEmpty else { return false }
        guard normalized.range(of: #"^\d{4}$"#, options: .regularExpression) == nil else { return false }
        if knownTerms.contains(normalized) { return true }

        let parts = value
            .split(whereSeparator: { ",/|+;&".contains($0) })
            .map { normalizeTerm(String($0)) }
            .filter { !$0.isEmpty }
        return !parts.isEmpty && parts.allSatisfy { knownTerms.contains($0) }
    }

    private func removingTrailingBracketSourceNotesAfterReadingSuffix(
        from value: String,
        knownTerms: Set<String>
    ) -> String {
        var result = value
        if let stripped = removingReadingSuffixMetadataTail(from: result, knownTerms: knownTerms) {
            result = stripped
        }

        while true {
            guard let note = trailingBracketNote(in: result) else {
                return result
            }

            let prefix = String(result[..<note.fullRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard volumeOrChapterSuffix(in: prefix) != nil else {
                return result
            }

            if note.opener == "[" {
                result.removeSubrange(note.fullRange)
                continue
            }

            let normalized = normalizeTerm(note.content)
            let parentheticalLooksLikeSource = [
                "digital", "scan", "scans", "raw", "retail", "official", "upload", "uploaded"
            ].contains { normalized.contains($0) }
            guard parentheticalLooksLikeSource else {
                return result
            }
            result.removeSubrange(note.fullRange)
        }
    }

    private func removingReadingSuffixMetadataTail(
        from value: String,
        knownTerms: Set<String>
    ) -> String? {
        guard let tail = trailingBracketNotesTail(in: value) else {
            return nil
        }

        let prefix = tail.prefix
        guard !prefix.isEmpty,
              volumeOrChapterSuffix(in: prefix) != nil else {
            return nil
        }

        guard !tail.notes.isEmpty,
              tail.notes.allSatisfy({ readingSuffixMetadataNoteShouldBeRemoved($0, knownTerms: knownTerms) }) else {
            return nil
        }
        return prefix
    }

    private func removingMalformedTrailingReadingSourceNotes(
        from value: String,
        knownTerms: Set<String>
    ) -> String {
        let pattern = #"(?i)\b(?:vol(?:ume)?|v|chapter|ch)\.?\s*0*\d{1,4}(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ).last,
              let markerRange = Range(match.range, in: value) else {
            return value
        }

        let tail = String(value[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty,
              tail.contains(where: { "[]{}".contains($0) }) else {
            return value
        }

        let pieces = tail
            .replacingOccurrences(of: #"[\[\]{}]+"#, with: "|", options: .regularExpression)
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let isReleaseNoise = !pieces.isEmpty && pieces.allSatisfy { piece in
            let key = normalizeTerm(piece)
            return key == "r"
                || key == "premium"
                || key == "clean book guy"
                || key == "cleanbookguy"
                || sourceNoteShouldBeRemoved(piece, knownTerms: knownTerms)
        }
        guard isReleaseNoise else { return value }
        return String(value[..<markerRange.upperBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct TrailingBracketNote {
        var fullRange: Range<String.Index>
        var content: String
        var opener: Character
    }

    private func trailingBracketNotesTail(in value: String) -> (prefix: String, notes: [String])? {
        var scanEnd = value.endIndex
        var notes: [String] = []

        while let note = trailingBracketNote(in: value, before: scanEnd) {
            notes.insert(note.content, at: 0)
            scanEnd = note.fullRange.lowerBound
        }

        guard !notes.isEmpty else { return nil }
        let prefix = String(value[..<scanEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (prefix, notes)
    }

    private func trailingBracketNote(
        in value: String,
        before end: String.Index? = nil
    ) -> TrailingBracketNote? {
        let originalEnd = end ?? value.endIndex
        var contentEnd = originalEnd
        while contentEnd > value.startIndex {
            let previous = value.index(before: contentEnd)
            guard value[previous].isWhitespace else { break }
            contentEnd = previous
        }
        guard contentEnd > value.startIndex else { return nil }

        let closeIndex = value.index(before: contentEnd)
        let closer = value[closeIndex]
        let opener: Character
        switch closer {
        case "]": opener = "["
        case ")": opener = "("
        case "}": opener = "{"
        default: return nil
        }

        guard let openIndex = value[..<closeIndex].lastIndex(of: opener) else {
            return nil
        }

        var fullStart = openIndex
        while fullStart > value.startIndex {
            let previous = value.index(before: fullStart)
            guard value[previous].isWhitespace else { break }
            fullStart = previous
        }

        let contentStart = value.index(after: openIndex)
        let content = String(value[contentStart..<closeIndex])
        return TrailingBracketNote(
            fullRange: fullStart..<originalEnd,
            content: content,
            opener: opener
        )
    }

    private func readingSuffixMetadataNoteShouldBeRemoved(_ value: String, knownTerms: Set<String>) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeTerm(trimmed)
        guard !normalized.isEmpty else { return false }

        if sourceNoteShouldBeRemoved(trimmed, knownTerms: knownTerms) {
            return true
        }
        if normalized == "premium" {
            return true
        }
        if normalized.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return true
        }
        if normalized.range(of: #"^(?:v|vol|volume)\s*0*\d{1,4}$"#, options: .regularExpression) != nil {
            return true
        }
        if publisherLikeReadingMetadataNote(normalized) {
            return true
        }

        let protectedEditionWords: Set<String> = [
            "bonus",
            "complete",
            "deluxe",
            "edition",
            "extra",
            "hardcover",
            "limited",
            "omnibus",
            "paperback",
            "special",
            "uncensored"
        ]
        let words = normalized.split(separator: " ").map(String.init)
        guard words.allSatisfy({ !protectedEditionWords.contains($0) }) else {
            return false
        }

        // Short lowercase parentheticals after a volume marker are usually release groups,
        // e.g. "Given Vol 01 (2020) (shizu)".
        return trimmed.range(of: #"^[a-z0-9][a-z0-9_-]{1,23}$"#, options: .regularExpression) != nil
    }

    private func publisherLikeReadingMetadataNote(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ").map(String.init)
        guard (1...5).contains(words.count) else { return false }

        let trustedPhrases: Set<String> = [
            "j novel club",
            "kodansha",
            "kodansha comics",
            "seven seas",
            "seven seas entertainment",
            "tokyopop",
            "viz media",
            "yen on",
            "yen press"
        ]
        if trustedPhrases.contains(normalized) {
            return true
        }

        let sourceWords: Set<String> = [
            "bookwalker",
            "books",
            "comics",
            "jnovel",
            "kindle",
            "kobo",
            "kodansha",
            "manga",
            "media",
            "press",
            "publisher",
            "publishing",
            "seas",
            "tokyopop",
            "viz",
            "yen"
        ]
        return words.contains { sourceWords.contains($0) }
    }

    func sanitizeFilename(_ value: String) -> String {
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

    func normalizeTerm(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func uniqueURL(_ url: URL, root: URL, plannedDestinations: Set<String> = []) -> URL {
        var candidate = url
        let parent = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var index = 2

        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) || plannedDestinations.contains(relativePath(for: candidate, root: root)) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = parent.appendingPathComponent(name)
            index += 1
        }

        return candidate
    }

    func joinedRelativePath(_ components: String...) -> String {
        components
            .map(normalizedRelativePath)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    func normalizedRelativePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if path == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return normalizedRelativePath(String(path.dropFirst(prefix.count)))
        }
        return normalizedRelativePath(url.lastPathComponent)
    }
}
