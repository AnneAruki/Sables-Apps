//
//  provider_dump_shelf_corpus.swift
//  Sable's Library
//
//  Compile with:
//  swiftc "Sable's Library/App/Core/SableLibraryShelfTagClassifier.swift" \
//      "Sable's Library/App/Core/SableLibraryShelfCatalog.swift" \
//      script/provider_dump_shelf_corpus.swift \
//      -o /tmp/provider_dump_shelf_corpus
//
//  MangaBaka JSONL:
//  tar -xOzf series.jsonl.tar.gz | /tmp/provider_dump_shelf_corpus \
//      --mangabaka-jsonl - \
//      --output-jsonl /tmp/sable-provider-sss-corpus.jsonl \
//      --output-csv /tmp/sable-provider-sss-training.csv \
//      --output-ml-csv /tmp/sable-provider-company-training.csv \
//      --output-workshop-dir /tmp/sable-provider-workshop
//
//  RanobeDB pg_dump:
//  gzip -dc rndb-db-public-latest.dump.gz | /tmp/provider_dump_shelf_corpus \
//      --ranobedb-pgdump - \
//      --output-jsonl /tmp/sable-ranobedb-sss-corpus.jsonl \
//      --output-csv /tmp/sable-ranobedb-sss-training.csv \
//      --output-ml-csv /tmp/sable-ranobedb-company-training.csv \
//      --output-workshop-dir /tmp/sable-ranobedb-workshop
//

import Foundation

@main
enum ProviderDumpShelfCorpus {
    static func main() {
        do {
            let options = try CorpusOptions.parse(CommandLine.arguments.dropFirst())
            if options.showHelp {
                print(CorpusOptions.helpText)
                return
            }

            let builder = CorpusBuilder(options: options)
            let report = try builder.run()
            print(report.render())
        } catch {
            fputs("Provider dump SSS corpus failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct CorpusOptions {
    var mangaBakaJSONL: String?
    var ranobeDBPGDump: String?
    var outputJSONL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sable-provider-sss-corpus.jsonl")
    var outputCSV = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sable-provider-sss-training.csv")
    var outputMLCSV = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sable-provider-company-training.csv")
    var outputWorkshopDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sable-provider-workshop", isDirectory: true)
    var limit: Int?
    var minimumTrainingConfidence = SableLibraryShelfConfidenceLevel.high
    var workshopLabelCap = 1200
    var tagRoleRowLimit: Int?
    var includeReviewRows = true
    var showHelp = false

    static let helpText = """
    Provider dump SSS corpus builder

    Options:
      --mangabaka-jsonl PATH   Read MangaBaka JSONL dump records. Use - for stdin.
      --ranobedb-pgdump PATH   Read RanobeDB plain PostgreSQL dump text. Use - for stdin.
      --output-jsonl PATH      Write all normalized SSS audit records.
      --output-csv PATH        Write SSS shelf text,label,source training rows.
      --output-ml-csv PATH     Write broader Sable company ML training rows.
      --output-workshop-dir    Write specialist lesson CSVs and meeting-note JSONL.
      --limit N                Stop after N normalized series.
      --min-confidence LEVEL   high, medium, low, or needsReview. Default: high.
      --workshop-label-cap N   Cap workshop lesson rows per label. Default: 1200. Use 0 for no cap.
      --tag-role-row-limit N   Only build tag-role lessons for the first N rows.
      --training-only          Do not include medium/low/review rows in JSONL.
      --help                   Show this help.

    Compressed dumps should be decompressed before this script:
      tar -xOzf series.jsonl.tar.gz | ... --mangabaka-jsonl -
      gzip -dc rndb-db-public-latest.dump.gz | ... --ranobedb-pgdump -
    """

    static func parse(_ rawArguments: ArraySlice<String>) throws -> CorpusOptions {
        var options = CorpusOptions()
        var arguments = Array(rawArguments)

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--help", "-h":
                options.showHelp = true
            case "--mangabaka-jsonl":
                options.mangaBakaJSONL = try nextValue(after: argument, from: &arguments)
            case "--ranobedb-pgdump":
                options.ranobeDBPGDump = try nextValue(after: argument, from: &arguments)
            case "--output-jsonl":
                options.outputJSONL = URL(fileURLWithPath: try nextValue(after: argument, from: &arguments))
            case "--output-csv":
                options.outputCSV = URL(fileURLWithPath: try nextValue(after: argument, from: &arguments))
            case "--output-ml-csv":
                options.outputMLCSV = URL(fileURLWithPath: try nextValue(after: argument, from: &arguments))
            case "--output-workshop-dir":
                options.outputWorkshopDirectory = URL(fileURLWithPath: try nextValue(after: argument, from: &arguments), isDirectory: true)
            case "--limit":
                let value = try nextValue(after: argument, from: &arguments)
                guard let intValue = Int(value), intValue > 0 else {
                    throw CorpusError.invalidValue(argument, value)
                }
                options.limit = intValue
            case "--min-confidence":
                let value = try nextValue(after: argument, from: &arguments)
                guard let level = SableLibraryShelfConfidenceLevel(argumentValue: value) else {
                    throw CorpusError.invalidValue(argument, value)
                }
                options.minimumTrainingConfidence = level
            case "--workshop-label-cap":
                let value = try nextValue(after: argument, from: &arguments)
                guard let intValue = Int(value), intValue >= 0 else {
                    throw CorpusError.invalidValue(argument, value)
                }
                options.workshopLabelCap = intValue
            case "--tag-role-row-limit":
                let value = try nextValue(after: argument, from: &arguments)
                guard let intValue = Int(value), intValue > 0 else {
                    throw CorpusError.invalidValue(argument, value)
                }
                options.tagRoleRowLimit = intValue
            case "--training-only":
                options.includeReviewRows = false
            default:
                throw CorpusError.invalidArgument(argument)
            }
        }

        if !options.showHelp,
           options.mangaBakaJSONL == nil,
           options.ranobeDBPGDump == nil {
            throw CorpusError.noInput
        }
        return options
    }

    private static func nextValue(after argument: String, from arguments: inout [String]) throws -> String {
        guard !arguments.isEmpty else { throw CorpusError.missingValue(argument) }
        return arguments.removeFirst()
    }
}

private struct CorpusBuilder {
    var options: CorpusOptions

    func run() throws -> CorpusReport {
        var rows: [ProviderDumpCorpusRecord] = []
        var failedRows: [String] = []

        if let mangaBakaJSONL = options.mangaBakaJSONL {
            let result = try readMangaBakaJSONL(path: mangaBakaJSONL, remainingLimit: remainingLimit(after: rows))
            rows.append(contentsOf: result.rows)
            failedRows.append(contentsOf: result.failures)
        }

        if let ranobeDBPGDump = options.ranobeDBPGDump,
           remainingLimit(after: rows) != 0 {
            let result = try readRanobeDBPGDump(path: ranobeDBPGDump, remainingLimit: remainingLimit(after: rows))
            rows.append(contentsOf: result.rows)
            failedRows.append(contentsOf: result.failures)
        }

        rows = Array(rows.prefix(options.limit ?? rows.count))
        let jsonRows = options.includeReviewRows
            ? rows
            : rows.filter { $0.isTrainingRow(minimum: options.minimumTrainingConfidence) }
        let trainingRows = rows.filter { $0.isTrainingRow(minimum: options.minimumTrainingConfidence) }
        let mlCompanyRows = rows.flatMap(\.mlCompanyTrainingRows)
        let workshop = ProviderDumpWorkshop(
            rows: rows,
            minimumTrainingConfidence: options.minimumTrainingConfidence,
            labelCap: options.workshopLabelCap,
            tagRoleRowLimit: options.tagRoleRowLimit
        )

        try writeJSONL(jsonRows, to: options.outputJSONL)
        try writeTrainingCSV(trainingRows, to: options.outputCSV)
        try writeMLCompanyCSV(mlCompanyRows, to: options.outputMLCSV)
        try writeWorkshop(workshop, to: options.outputWorkshopDirectory)

        return CorpusReport(
            rows: rows,
            jsonRows: jsonRows,
            trainingRows: trainingRows,
            mlCompanyRows: mlCompanyRows,
            workshop: workshop,
            failedRows: failedRows,
            outputJSONL: options.outputJSONL,
            outputCSV: options.outputCSV,
            outputMLCSV: options.outputMLCSV,
            outputWorkshopDirectory: options.outputWorkshopDirectory,
            minimumTrainingConfidence: options.minimumTrainingConfidence
        )
    }

    private func remainingLimit(after rows: [ProviderDumpCorpusRecord]) -> Int? {
        guard let limit = options.limit else { return nil }
        return max(0, limit - rows.count)
    }

    private func readMangaBakaJSONL(
        path: String,
        remainingLimit: Int?
    ) throws -> (rows: [ProviderDumpCorpusRecord], failures: [String]) {
        var rows: [ProviderDumpCorpusRecord] = []
        var failures: [String] = []
        let reader = try LineReader(path: path)
        defer { try? reader.close() }

        var lineNumber = 0
        while let line = try reader.nextLine() {
            lineNumber += 1
            if let remainingLimit, rows.count >= remainingLimit { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            do {
                let data = Data(trimmed.utf8)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    failures.append("MangaBaka line \(lineNumber): unreadable JSON object")
                    continue
                }
                guard let series = ProviderDumpSeries(mangaBakaObject: object) else {
                    failures.append("MangaBaka line \(lineNumber): missing title")
                    continue
                }
                rows.append(ProviderDumpCorpusRecord(series: series))
            } catch {
                failures.append("MangaBaka line \(lineNumber): \(error.localizedDescription)")
            }
        }
        return (rows, failures)
    }

    private func readRanobeDBPGDump(
        path: String,
        remainingLimit: Int?
    ) throws -> (rows: [ProviderDumpCorpusRecord], failures: [String]) {
        let reader = try LineReader(path: path)
        defer { try? reader.close() }

        let parsed = try RanobeDBDumpParser(reader: reader).parse()
        var rows: [ProviderDumpCorpusRecord] = []
        var failures: [String] = []

        for series in parsed.seriesRows.sorted(by: { $0.key < $1.key }) {
            if let remainingLimit, rows.count >= remainingLimit { break }
            guard let normalized = parsed.normalizedSeries(id: series.key) else {
                failures.append("RanobeDB series \(series.key): missing title")
                continue
            }
            rows.append(ProviderDumpCorpusRecord(series: normalized))
        }
        return (rows, failures)
    }

    private func writeJSONL(_ rows: [ProviderDumpCorpusRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for row in rows {
            data.append(try encoder.encode(row))
            data.append(contentsOf: Data("\n".utf8))
        }
        try data.write(to: url, options: .atomic)
    }

    private func writeTrainingCSV(_ rows: [ProviderDumpCorpusRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ["text,label,source,confidence,confidence_score,provider,provider_id"]
        lines.append(contentsOf: rows.map { row in
            [
                row.trainingText,
                row.trainingLabel,
                row.trainingSource,
                row.confidence,
                String(format: "%.4f", row.confidenceScore),
                row.provider,
                row.providerID
            ].map(csvEscaped).joined(separator: ",")
        })
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMLCompanyCSV(_ rows: [MLCompanyTrainingRow], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ["text,label,source"]
        lines.append(contentsOf: rows.map { row in
            [row.text, row.label, row.source].map(csvEscaped).joined(separator: ",")
        })
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeWorkshop(_ workshop: ProviderDumpWorkshop, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeLessonCSV(workshop.providerShapeRows, to: directory.appendingPathComponent("provider-shape.csv"))
        try writeLessonCSV(workshop.titleAliasRows, to: directory.appendingPathComponent("title-alias.csv"))
        try writeLessonCSV(workshop.mediaTypeRows, to: directory.appendingPathComponent("media-type.csv"))
        try writeLessonCSV(workshop.tagRoleRows, to: directory.appendingPathComponent("tag-role.csv"))
        try writeLessonCSV(workshop.descriptionRows, to: directory.appendingPathComponent("description-aboutness.csv"))
        try writeLessonCSV(workshop.workFamilyRows, to: directory.appendingPathComponent("work-family.csv"))
        try writeLessonCSV(workshop.managerRows, to: directory.appendingPathComponent("manager-meeting.csv"))
        try writeLessonCSV(workshop.allRows, to: directory.appendingPathComponent("all-lessons.csv"))
        try writeMeetingJSONL(workshop.meetingRecords, to: directory.appendingPathComponent("meeting-notes.jsonl"))
    }

    private func writeLessonCSV(_ rows: [WorkshopTrainingRow], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ["text,label,source"]
        lines.append(contentsOf: rows.map { row in
            [row.text, row.label, row.source].map(csvEscaped).joined(separator: ",")
        })
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMeetingJSONL(_ rows: [WorkshopMeetingRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for row in rows {
            data.append(try encoder.encode(row))
            data.append(contentsOf: Data("\n".utf8))
        }
        try data.write(to: url, options: .atomic)
    }
}

private struct ProviderDumpSeries {
    var provider: String
    var providerID: String
    var providerURL: String?
    var title: String
    var aliases: [String]
    var description: String?
    var genres: [String]
    var tags: [String]
    var contentWarnings: [String]
    var mediaType: String?
    var year: Int?

    init?(mangaBakaObject object: [String: Any]) {
        let row = (object["series"] as? [String: Any])
            ?? (object["data"] as? [String: Any])
            ?? object
        guard let candidateTitle = text(row["title"])
            ?? text(row["preferred_title"])
            ?? text(row["english_title"])
            ?? text(row["romaji"])
            ?? text(row["romanized_title"])
        else { return nil }
        let id = text(row["id"])
            ?? text(row["series_id"])
            ?? text(row["seriesId"])
            ?? stableProviderID(provider: "mangabaka", title: candidateTitle)
        let v2Genres = mangaBakaV2Names(from: row["genres_v2"], whereGenre: true)
        let v2Tags = mangaBakaV2Names(from: row["tags_v2"], whereGenre: false)
        let legacyTags = mangaBakaLegacyTags(from: row["tags"])
        let adultWarnings = boolAny(row["isAdult"]) == true || boolAny(row["adult"]) == true
            ? ["adult"]
            : []

        provider = "mangabaka"
        providerID = id
        providerURL = "https://mangabaka.org/\(id)"
        title = candidateTitle
        aliases = uniqueStrings(
            [
                text(row["native_title"]),
                text(row["romanized_title"]),
                text(row["romaji"]),
                text(row["title_romaji"])
            ].compactMap { $0 }
                + stringValues(from: row["alias"])
                + stringValues(from: row["aliases"])
                + namedValues(from: row["titles"])
        )
        description = text(row["description"])
            ?? text(row["synopsis"])
            ?? text(row["summary"])
            ?? text(row["description_en"])
        let genreValues = v2Genres
            + legacyTags.genres
            + namedValues(from: row["genres"])
            + stringValues(from: row["genre"])
        let tagValues = v2Tags
            + legacyTags.tags
            + namedValues(from: row["themes"])
            + namedValues(from: row["categories"])
        let warningValues = adultWarnings
            + mangaBakaContentWarningNames(from: row["tags_v2"])
            + namedValues(from: row["warnings"])
            + namedValues(from: row["content_warnings"])
            + namedValues(from: row["contentWarnings"])
        genres = uniqueStrings(genreValues)
        tags = uniqueStrings(tagValues)
        contentWarnings = uniqueStrings(warningValues)
        mediaType = text(row["type"]) ?? text(row["media_type"]) ?? text(row["format"])
        year = intAny(row["year"]) ?? packedYear(fromPackedDate: intAny(row["start_date"]))
    }

    init(
        provider: String,
        providerID: String,
        providerURL: String?,
        title: String,
        aliases: [String],
        description: String?,
        genres: [String],
        tags: [String],
        contentWarnings: [String],
        mediaType: String?,
        year: Int?
    ) {
        self.provider = provider
        self.providerID = providerID
        self.providerURL = providerURL
        self.title = title
        self.aliases = aliases
        self.description = description
        self.genres = genres
        self.tags = tags
        self.contentWarnings = contentWarnings
        self.mediaType = mediaType
        self.year = year
    }

    var catalogInput: SableLibraryShelfCatalogInput {
        let tagRecords = genres.map {
            SableLibraryShelfTagRecord(name: $0, isGenre: true, provider: provider)
        } + tags.map {
            SableLibraryShelfTagRecord(name: $0, isGenre: false, provider: provider)
        }

        return SableLibraryShelfCatalogInput(
            title: title,
            description: description,
            genres: genres,
            tags: tags,
            tagRecords: tagRecords,
            contentWarnings: contentWarnings,
            mediaType: mediaType
        )
    }
}

private struct MLCompanyTrainingRow {
    var text: String
    var label: String
    var source: String
}

private struct WorkshopTrainingRow {
    var text: String
    var label: String
    var source: String
}

private struct WorkshopMeetingRecord: Encodable {
    var provider: String
    var providerID: String
    var title: String
    var mediaType: String?
    var suggestedShelf: String
    var confidence: String
    var actionability: String
    var specialistNotes: [String: String]
    var trainingLabels: [String]
}

private struct ProviderDumpCorpusRecord: Encodable {
    struct Evidence: Encodable {
        var source: String
        var terms: [String]
        var score: Double
        var note: String
    }

    struct Alternative: Encodable {
        var shelfCode: String
        var subShelfCode: String
        var path: String
        var score: Double
    }

    var provider: String
    var providerID: String
    var providerURL: String?
    var title: String
    var aliases: [String]
    var description: String?
    var genres: [String]
    var tags: [String]
    var contentWarnings: [String]
    var mediaType: String?
    var year: Int?
    var suggestedShelfCode: String
    var suggestedSubShelfCode: String
    var suggestedPath: String
    var confidence: String
    var confidenceScore: Double
    var actionability: String
    var ruleChangeNeeded: Bool
    var evidence: [Evidence]
    var evidenceRoles: SableLibraryShelfEvidenceRoleLedger
    var alternatives: [Alternative]
    var facets: [String]
    var warnings: [String]
    var competingShelves: [String]
    var whyNotCompeting: [String]
    var neededEvidence: [String]
    var trainingLabel: String
    var trainingText: String
    var trainingSource: String

    init(series: ProviderDumpSeries) {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: series.catalogInput)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: series.catalogInput, suggestion: suggestion)

        provider = series.provider
        providerID = series.providerID
        providerURL = series.providerURL
        title = series.title
        aliases = series.aliases
        description = series.description
        genres = series.genres
        tags = series.tags
        contentWarnings = series.contentWarnings
        mediaType = series.mediaType
        year = series.year
        suggestedShelfCode = suggestion.shelf.code
        suggestedSubShelfCode = suggestion.subShelf.code
        suggestedPath = suggestion.displayPath
        confidence = suggestion.confidenceLevel.rawValue
        confidenceScore = suggestion.confidence
        actionability = ledger.actionability.rawValue
        ruleChangeNeeded = ledger.ruleChangeNeeded
        evidence = suggestion.evidence.map {
            Evidence(source: $0.source.rawValue, terms: $0.matchedTerms, score: $0.score, note: $0.note)
        }
        evidenceRoles = suggestion.evidenceRoles
        alternatives = suggestion.alternatives.map {
            Alternative(
                shelfCode: $0.shelf.code,
                subShelfCode: $0.subShelf.code,
                path: "\($0.shelf.displayName) / \($0.subShelf.displayName)",
                score: $0.score
            )
        }
        facets = suggestion.facets
        warnings = suggestion.warnings
        competingShelves = ledger.competingShelves
        whyNotCompeting = ledger.whyNotCompeting
        neededEvidence = ledger.neededEvidence
        trainingLabel = "shelf.\(suggestion.subShelf.code)"
        trainingText = providerTrainingText(series: series, suggestion: suggestion, ledger: ledger)
        trainingSource = "\(series.provider)-dump"
    }

    func isTrainingRow(minimum: SableLibraryShelfConfidenceLevel) -> Bool {
        guard !ruleChangeNeeded,
              actionability != SableLibraryShelfDecisionActionability.possibleRuleProblem.rawValue,
              actionability != SableLibraryShelfDecisionActionability.evidenceProblem.rawValue,
              confidenceRank(confidence) >= minimum.trainingRank else {
            return false
        }
        return true
    }

    var mlCompanyTrainingRows: [MLCompanyTrainingRow] {
        var labels: [String] = []
        var seen: Set<String> = []

        func append(_ label: String?) {
            guard let label, seen.insert(label).inserted else { return }
            labels.append(label)
        }

        append(readingTypeLabel)
        append("provider.\(provider)")
        append("metadata.identity")
        if hasDetailMetadata {
            append("metadata.detail")
        }
        if !providerID.isEmpty {
            append("provider.matchStrong")
        }

        let text = mlCompanyTrainingText
        return labels.map {
            MLCompanyTrainingRow(text: text, label: $0, source: "\(provider)-dump")
        }
    }

    private var readingTypeLabel: String? {
        if provider == "ranobedb" {
            return "reading.lightNovel"
        }
        switch normalizedText(mediaType ?? "") {
        case "lightnovel", "lightnovels", "ln", "novel":
            return "reading.lightNovel"
        case "manga":
            return "reading.manga"
        case "manhwa", "webtoon":
            return "reading.manhwa"
        case "manhua":
            return "reading.manhua"
        case "oel":
            return "reading.oel"
        case "comic", "comics":
            return "reading.comic"
        default:
            return nil
        }
    }

    private var hasDetailMetadata: Bool {
        description != nil || !genres.isEmpty || !tags.isEmpty || !contentWarnings.isEmpty
    }

    private var mlCompanyTrainingText: String {
        let parts = [
            "provider \(provider)",
            "media \(mediaType ?? "unknown")",
            "title \(title)",
            description.map { "description \($0)" },
            genres.isEmpty ? nil : "genres \(genres.joined(separator: " "))",
            tags.isEmpty ? nil : "tags \(tags.joined(separator: " "))",
            contentWarnings.isEmpty ? nil : "warnings \(contentWarnings.joined(separator: " "))",
            "sss \(suggestedSubShelfCode) \(suggestedPath)"
        ].compactMap { $0 }
        return parts
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ProviderDumpWorkshop {
    var providerShapeRows: [WorkshopTrainingRow]
    var titleAliasRows: [WorkshopTrainingRow]
    var mediaTypeRows: [WorkshopTrainingRow]
    var tagRoleRows: [WorkshopTrainingRow]
    var descriptionRows: [WorkshopTrainingRow]
    var workFamilyRows: [WorkshopTrainingRow]
    var managerRows: [WorkshopTrainingRow]
    var meetingRecords: [WorkshopMeetingRecord]

    init(
        rows: [ProviderDumpCorpusRecord],
        minimumTrainingConfidence: SableLibraryShelfConfidenceLevel,
        labelCap: Int,
        tagRoleRowLimit: Int?
    ) {
        var capper = WorkshopLessonCapper(labelCap: labelCap)
        var providerShapeRows: [WorkshopTrainingRow] = []
        var titleAliasRows: [WorkshopTrainingRow] = []
        var mediaTypeRows: [WorkshopTrainingRow] = []
        var tagRoleRows: [WorkshopTrainingRow] = []
        var descriptionRows: [WorkshopTrainingRow] = []
        var workFamilyRows: [WorkshopTrainingRow] = []
        var managerRows: [WorkshopTrainingRow] = []
        var meetingRecords: [WorkshopMeetingRecord] = []

        for (index, row) in rows.enumerated() {
            let includeTagRoles = tagRoleRowLimit.map { index < $0 } ?? true
            let tagRowsForMeeting = includeTagRoles ? workshopTagRoleRows(row) : []
            appendCapped(workshopProviderShapeRows(row), to: &providerShapeRows, using: &capper)
            appendCapped(workshopTitleAliasRows(row), to: &titleAliasRows, using: &capper)
            appendCapped(workshopMediaTypeRows(row), to: &mediaTypeRows, using: &capper)
            appendCapped(tagRowsForMeeting, to: &tagRoleRows, using: &capper)
            appendCapped(workshopDescriptionRows(row, minimum: minimumTrainingConfidence), to: &descriptionRows, using: &capper)
            appendCapped(workshopWorkFamilyRows(row), to: &workFamilyRows, using: &capper)
            appendCapped(workshopManagerRows(row, minimum: minimumTrainingConfidence), to: &managerRows, using: &capper)
            meetingRecords.append(
                workshopMeetingRecord(
                    row,
                    minimum: minimumTrainingConfidence,
                    tagRoleRows: tagRowsForMeeting,
                    tagRolesWereSampled: includeTagRoles
                )
            )
        }

        self.providerShapeRows = providerShapeRows
        self.titleAliasRows = titleAliasRows
        self.mediaTypeRows = mediaTypeRows
        self.tagRoleRows = tagRoleRows
        self.descriptionRows = descriptionRows
        self.workFamilyRows = workFamilyRows
        self.managerRows = managerRows
        self.meetingRecords = meetingRecords
    }

    var allRows: [WorkshopTrainingRow] {
        providerShapeRows
            + titleAliasRows
            + mediaTypeRows
            + tagRoleRows
            + descriptionRows
            + workFamilyRows
            + managerRows
    }

    var countsByLesson: [(String, Int)] {
        [
            ("provider-shape", providerShapeRows.count),
            ("title-alias", titleAliasRows.count),
            ("media-type", mediaTypeRows.count),
            ("tag-role", tagRoleRows.count),
            ("description-aboutness", descriptionRows.count),
            ("work-family", workFamilyRows.count),
            ("manager-meeting", managerRows.count),
            ("meeting-notes", meetingRecords.count),
            ("all-lessons", allRows.count)
        ]
    }
}

private struct WorkshopLessonCapper {
    var labelCap: Int
    private var counts: [String: Int] = [:]

    init(labelCap: Int) {
        self.labelCap = labelCap
    }

    mutating func shouldKeep(_ row: WorkshopTrainingRow) -> Bool {
        guard labelCap > 0 else { return true }
        let count = counts[row.label, default: 0]
        guard count < labelCap else { return false }
        counts[row.label] = count + 1
        return true
    }
}

private func appendCapped(
    _ rows: [WorkshopTrainingRow],
    to destination: inout [WorkshopTrainingRow],
    using capper: inout WorkshopLessonCapper
) {
    for row in rows where capper.shouldKeep(row) {
        destination.append(row)
    }
}

private func workshopProviderShapeRows(_ row: ProviderDumpCorpusRecord) -> [WorkshopTrainingRow] {
    [
        WorkshopTrainingRow(
            text: workshopText(
                row,
                focus: [
                    "field provider",
                    "alias_count \(row.aliases.count)",
                    row.description == nil ? "description missing" : "description present",
                    "genre_count \(row.genres.count)",
                    "tag_count \(row.tags.count)",
                    "warning_count \(row.contentWarnings.count)"
                ]
            ),
            label: "providerShape.\(labelCode(row.provider))",
            source: "\(row.provider)-workshop"
        )
    ]
}

private func workshopTitleAliasRows(_ row: ProviderDumpCorpusRecord) -> [WorkshopTrainingRow] {
    var rows = [
        WorkshopTrainingRow(
            text: workshopText(row, focus: ["title role primary", row.title]),
            label: "titleAlias.primary",
            source: "\(row.provider)-workshop"
        )
    ]
    rows.append(contentsOf: row.aliases.prefix(12).map { alias in
        WorkshopTrainingRow(
            text: workshopText(row, focus: ["title role alias", alias]),
            label: "titleAlias.alias",
            source: "\(row.provider)-workshop"
        )
    })
    if row.aliases.isEmpty {
        rows.append(
            WorkshopTrainingRow(
                text: workshopText(row, focus: ["title role no aliases"]),
                label: "titleAlias.noAlias",
                source: "\(row.provider)-workshop"
            )
        )
    }
    return rows
}

private func workshopMediaTypeRows(_ row: ProviderDumpCorpusRecord) -> [WorkshopTrainingRow] {
    guard let label = mediaTypeLessonLabel(provider: row.provider, mediaType: row.mediaType) else {
        return [
            WorkshopTrainingRow(
                text: workshopText(row, focus: ["media unknown"]),
                label: "mediaType.unknown",
                source: "\(row.provider)-workshop"
            )
        ]
    }
    return [
        WorkshopTrainingRow(
            text: workshopText(row, focus: ["media \(row.mediaType ?? "provider implied")"]),
            label: label,
            source: "\(row.provider)-workshop"
        )
    ]
}

private func workshopTagRoleRows(_ row: ProviderDumpCorpusRecord) -> [WorkshopTrainingRow] {
    let genreRecords = row.genres.map {
        SableLibraryShelfTagRecord(name: $0, isGenre: true, provider: row.provider)
    }
    let tagRecords = row.tags.map {
        SableLibraryShelfTagRecord(name: $0, isGenre: false, provider: row.provider)
    }
    let warningRecords = row.contentWarnings.map {
        SableLibraryShelfTagRecord(name: $0, isGenre: false, contentRating: "adult", provider: row.provider)
    }
    let classifications = SableLibraryShelfTagClassifier.classify(genreRecords + tagRecords + warningRecords)
    return classifications.map { classification in
        WorkshopTrainingRow(
            text: workshopText(
                row,
                focus: [
                    "tag \(classification.record.name)",
                    "path \(classification.record.path ?? "")",
                    "is_genre \(classification.record.isGenre == true)",
                    "tag_use \(classification.use.rawValue)"
                ]
            ),
            label: "tagRole.\(classification.role.rawValue)",
            source: "\(row.provider)-workshop"
        )
    }
}

private func workshopDescriptionRows(
    _ row: ProviderDumpCorpusRecord,
    minimum: SableLibraryShelfConfidenceLevel
) -> [WorkshopTrainingRow] {
    guard let description = row.description else {
        return [
            WorkshopTrainingRow(
                text: workshopText(row, focus: ["description missing"]),
                label: "description.missing",
                source: "\(row.provider)-workshop"
            )
        ]
    }

    var rows = [
        WorkshopTrainingRow(
            text: workshopText(row, focus: ["description present", description]),
            label: "description.present",
            source: "\(row.provider)-workshop"
        ),
        WorkshopTrainingRow(
            text: workshopText(row, focus: ["description confidence \(row.confidence)", description]),
            label: "description.confidence.\(labelCode(row.confidence))",
            source: "\(row.provider)-workshop"
        )
    ]

    if row.isTrainingRow(minimum: minimum) {
        rows.append(
            WorkshopTrainingRow(
                text: workshopText(row, focus: ["description aboutness", description]),
                label: "description.shelf.\(row.suggestedSubShelfCode)",
                source: "\(row.provider)-workshop"
            )
        )
    }
    return rows
}

private func workshopWorkFamilyRows(_ row: ProviderDumpCorpusRecord) -> [WorkshopTrainingRow] {
    var rows: [WorkshopTrainingRow] = [
        WorkshopTrainingRow(
            text: workshopText(row, focus: ["work identity provider series id \(row.providerID)"]),
            label: "workFamily.providerSeries",
            source: "\(row.provider)-workshop"
        )
    ]

    if !row.aliases.isEmpty {
        rows.append(
            WorkshopTrainingRow(
                text: workshopText(row, focus: ["work identity aliases", row.aliases.prefix(12).joined(separator: " | ")]),
                label: "workFamily.hasAliases",
                source: "\(row.provider)-workshop"
            )
        )
    }
    if mediaTypeLessonLabel(provider: row.provider, mediaType: row.mediaType) != nil {
        rows.append(
            WorkshopTrainingRow(
                text: workshopText(row, focus: ["work identity form specific", row.mediaType ?? "provider implied"]),
                label: "workFamily.formSpecificVersion",
                source: "\(row.provider)-workshop"
            )
        )
    }

    let bibliographicTags = SableLibraryShelfTagClassifier.classify(
        (row.genres + row.tags).map { SableLibraryShelfTagRecord(name: $0, provider: row.provider) }
    ).filter { $0.role == .bibliographicRelationship }

    if !bibliographicTags.isEmpty {
        rows.append(
            WorkshopTrainingRow(
                text: workshopText(
                    row,
                    focus: ["work identity bibliographic relationship", bibliographicTags.map(\.record.name).joined(separator: " ")]
                ),
                label: "workFamily.crossMediaRelationship",
                source: "\(row.provider)-workshop"
            )
        )
    }
    return rows
}

private func workshopManagerRows(
    _ row: ProviderDumpCorpusRecord,
    minimum: SableLibraryShelfConfidenceLevel
) -> [WorkshopTrainingRow] {
    var labels = [
        "manager.confidence.\(labelCode(row.confidence))",
        "manager.actionability.\(labelCode(row.actionability))",
        row.isTrainingRow(minimum: minimum) ? "manager.trainingCandidate" : "manager.reviewCandidate"
    ]
    if !row.competingShelves.isEmpty {
        labels.append("manager.hasCompetingShelves")
    }
    if !row.neededEvidence.isEmpty {
        labels.append("manager.needsEvidence")
    }
    if row.ruleChangeNeeded {
        labels.append("manager.ruleChangeNeeded")
    }
    return labels.map { label in
        WorkshopTrainingRow(
            text: managerMeetingText(row),
            label: label,
            source: "\(row.provider)-workshop"
        )
    }
}

private func workshopMeetingRecord(
    _ row: ProviderDumpCorpusRecord,
    minimum: SableLibraryShelfConfidenceLevel,
    tagRoleRows: [WorkshopTrainingRow],
    tagRolesWereSampled: Bool
) -> WorkshopMeetingRecord {
    let tagRoleCounts = tagRolesWereSampled
        ? Dictionary(grouping: tagRoleRows, by: \.label)
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        : "not sampled for this row"
    let managerLabels = workshopManagerRows(row, minimum: minimum).map(\.label)
    return WorkshopMeetingRecord(
        provider: row.provider,
        providerID: row.providerID,
        title: row.title,
        mediaType: row.mediaType,
        suggestedShelf: row.suggestedPath,
        confidence: row.confidence,
        actionability: row.actionability,
        specialistNotes: [
            "providerShape": "provider \(row.provider) fields aliases \(row.aliases.count) genres \(row.genres.count) tags \(row.tags.count)",
            "titleAlias": row.aliases.isEmpty ? "primary only" : "aliases \(row.aliases.prefix(5).joined(separator: " | "))",
            "mediaType": row.mediaType ?? "unknown",
            "tagRoles": tagRoleCounts,
            "description": row.description == nil ? "missing" : "present",
            "shelf": "\(row.suggestedSubShelfCode) \(row.suggestedPath)",
            "confidence": "\(row.confidence) score \(String(format: "%.2f", row.confidenceScore))",
            "review": row.neededEvidence.joined(separator: " | ")
        ],
        trainingLabels: managerLabels
    )
}

private func workshopText(_ row: ProviderDumpCorpusRecord, focus: [String]) -> String {
    let parts = [
        "provider \(row.provider)",
        "provider_id \(row.providerID)",
        "media \(row.mediaType ?? "unknown")",
        "title \(row.title)",
        row.aliases.isEmpty ? nil : "aliases \(row.aliases.prefix(8).joined(separator: " | "))",
        row.genres.isEmpty ? nil : "genres \(row.genres.joined(separator: " "))",
        row.tags.isEmpty ? nil : "tags \(row.tags.prefix(24).joined(separator: " "))",
        row.contentWarnings.isEmpty ? nil : "warnings \(row.contentWarnings.joined(separator: " "))",
        row.description.map { "description \($0)" },
        "sss \(row.suggestedSubShelfCode) \(row.suggestedPath)",
        focus.joined(separator: " ")
    ].compactMap { $0 }
    return parts
        .joined(separator: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func managerMeetingText(_ row: ProviderDumpCorpusRecord) -> String {
    workshopText(
        row,
        focus: [
            "manager confidence \(row.confidence)",
            "score \(String(format: "%.2f", row.confidenceScore))",
            "actionability \(row.actionability)",
            row.competingShelves.isEmpty ? "no competing shelves" : "competing \(row.competingShelves.joined(separator: " | "))",
            row.neededEvidence.isEmpty ? "no needed evidence" : "needed \(row.neededEvidence.joined(separator: " | "))"
        ]
    )
}

private func mediaTypeLessonLabel(provider: String, mediaType: String?) -> String? {
    if provider == "ranobedb" {
        return "mediaType.lightNovel"
    }
    switch normalizedText(mediaType ?? "") {
    case "lightnovel", "lightnovels", "ln", "novel":
        return "mediaType.lightNovel"
    case "manga":
        return "mediaType.manga"
    case "manhwa", "webtoon":
        return "mediaType.manhwa"
    case "manhua":
        return "mediaType.manhua"
    case "oel":
        return "mediaType.oel"
    case "comic", "comics":
        return "mediaType.comic"
    default:
        return nil
    }
}

private func labelCode(_ value: String) -> String {
    let cleaned = value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    return cleaned.isEmpty ? "unknown" : cleaned
}

private struct RanobeDBDumpParser {
    struct SeriesRow {
        var id: Int
        var description: String?
        var aliases: [String]
        var startDate: Int?
        var status: String?
        var malID: String?
        var anilistID: String?
        var hidden: Bool
    }

    struct TitleRow {
        var lang: String?
        var official: Bool
        var title: String
        var romaji: String?
    }

    struct TagRow {
        var id: Int
        var name: String
        var type: String?
    }

    var reader: LineReader

    final class Result {
        var seriesRows: [Int: SeriesRow] = [:]
        var titlesBySeriesID: [Int: [TitleRow]] = [:]
        var tagRows: [Int: TagRow] = [:]
        var tagIDsBySeriesID: [Int: [Int]] = [:]

        func normalizedSeries(id: Int) -> ProviderDumpSeries? {
            guard let series = seriesRows[id], !series.hidden else { return nil }
            let titles = titlesBySeriesID[id] ?? []
            guard let title = preferredTitle(from: titles) else { return nil }
            let aliases = uniqueStrings(
                titles.flatMap { [$0.title, $0.romaji].compactMap { $0 } }
                    + series.aliases
            ).filter { normalizedText($0) != normalizedText(title) }
            let tags = (tagIDsBySeriesID[id] ?? []).compactMap { tagRows[$0] }
            let genres = tags.filter { normalizedText($0.type ?? "") == "genre" }.map(\.name)
            let contentWarnings = tags.filter { normalizedText($0.type ?? "") == "content" }.map(\.name)
            let otherTags = tags.filter {
                !["genre", "content"].contains(normalizedText($0.type ?? ""))
            }.map(\.name)
            return ProviderDumpSeries(
                provider: "ranobedb",
                providerID: "\(id)",
                providerURL: "https://ranobedb.org/series/\(id)",
                title: title,
                aliases: aliases,
                description: series.description,
                genres: uniqueStrings(genres),
                tags: uniqueStrings(otherTags),
                contentWarnings: uniqueStrings(contentWarnings),
                mediaType: "lightNovel",
                year: packedYear(fromPackedDate: series.startDate)
            )
        }

        private func preferredTitle(from rows: [TitleRow]) -> String? {
            let candidates = [
                rows.first { $0.official && normalizedText($0.lang ?? "") == "en" }?.title,
                rows.first { normalizedText($0.lang ?? "") == "en" }?.title,
                rows.first { $0.official }?.title,
                rows.first?.title,
                rows.first?.romaji
            ]
            return candidates.compactMap { cleanText($0) }.first
        }
    }

    func parse() throws -> Result {
        let result = Result()
        var activeCopy: (table: String, columns: [String])?

        while let line = try reader.nextLine() {
            if let copy = activeCopy {
                if line == #"\\."# || line == #"\."# {
                    activeCopy = nil
                    continue
                }
                let fields = parsePostgresCopyFields(line)
                guard fields.count == copy.columns.count else { continue }
                let row = Dictionary(uniqueKeysWithValues: zip(copy.columns, fields))
                consume(row: row, table: copy.table, into: result)
                continue
            }

            if let copy = parseCopyHeader(line) {
                activeCopy = copy
            }
        }

        return result
    }

    private func consume(row: [String: String?], table: String, into result: Result) {
        switch table {
        case "series":
            guard let id = int(row["id"] ?? nil) else { return }
            result.seriesRows[id] = SeriesRow(
                id: id,
                description: cleanText(row["description"] ?? nil),
                aliases: splitAliasText(row["aliases"] ?? nil),
                startDate: int(row["c_start_date"] ?? nil) ?? int(row["start_date"] ?? nil),
                status: cleanText(row["publication_status"] ?? nil),
                malID: cleanText(row["mal_id"] ?? nil),
                anilistID: cleanText(row["anilist_id"] ?? nil),
                hidden: bool(row["hidden"] ?? nil)
            )
        case "series_title":
            guard let seriesID = int(row["series_id"] ?? nil),
                  let title = cleanText(row["title"] ?? nil) else { return }
            result.titlesBySeriesID[seriesID, default: []].append(
                TitleRow(
                    lang: cleanText(row["lang"] ?? nil),
                    official: bool(row["official"] ?? nil),
                    title: title,
                    romaji: cleanText(row["romaji"] ?? nil)
                )
            )
        case "tag":
            guard let id = int(row["id"] ?? nil),
                  let name = cleanText(row["name"] ?? nil) else { return }
            result.tagRows[id] = TagRow(
                id: id,
                name: name,
                type: cleanText(row["ttype"] ?? nil)
            )
        case "series_tag":
            guard let seriesID = int(row["series_id"] ?? nil),
                  let tagID = int(row["tag_id"] ?? nil) else { return }
            result.tagIDsBySeriesID[seriesID, default: []].append(tagID)
        default:
            break
        }
    }

    private func parseCopyHeader(_ line: String) -> (table: String, columns: [String])? {
        guard line.hasPrefix("COPY public.") else { return nil }
        let wantedTables = Set(["series", "series_title", "series_tag", "tag"])
        let prefix = "COPY public."
        let remainder = String(line.dropFirst(prefix.count))
        guard let tableEnd = remainder.firstIndex(of: " ") else { return nil }
        let table = String(remainder[..<tableEnd])
        guard wantedTables.contains(table),
              let open = line.firstIndex(of: "("),
              let close = line[open...].firstIndex(of: ")") else { return nil }
        let rawColumns = line[line.index(after: open)..<close]
        let columns = rawColumns.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (table, columns)
    }
}

private final class LineReader {
    private let handle: FileHandle
    private let shouldClose: Bool
    private var buffer = Data()
    private var reachedEOF = false
    private let newline = Data([0x0A])

    init(path: String) throws {
        if path == "-" {
            handle = FileHandle.standardInput
            shouldClose = false
        } else {
            handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            shouldClose = true
        }
    }

    func nextLine() throws -> String? {
        while true {
            if let range = buffer.range(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(data: lineData, encoding: .utf8)
            }

            if reachedEOF {
                guard !buffer.isEmpty else { return nil }
                let lineData = buffer
                buffer.removeAll()
                return String(data: lineData, encoding: .utf8)
            }

            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty {
                reachedEOF = true
            } else {
                buffer.append(chunk)
            }
        }
    }

    func close() throws {
        if shouldClose {
            try handle.close()
        }
    }
}

private struct CorpusReport {
    var rows: [ProviderDumpCorpusRecord]
    var jsonRows: [ProviderDumpCorpusRecord]
    var trainingRows: [ProviderDumpCorpusRecord]
    var mlCompanyRows: [MLCompanyTrainingRow]
    var workshop: ProviderDumpWorkshop
    var failedRows: [String]
    var outputJSONL: URL
    var outputCSV: URL
    var outputMLCSV: URL
    var outputWorkshopDirectory: URL
    var minimumTrainingConfidence: SableLibraryShelfConfidenceLevel

    func render() -> String {
        var lines: [String] = []
        lines.append("Provider dump SSS corpus")
        lines.append("Normalized rows: \(rows.count)")
        lines.append("JSONL rows: \(jsonRows.count)")
        lines.append("SSS shelf training rows: \(trainingRows.count)")
        lines.append("Sable company ML rows: \(mlCompanyRows.count)")
        lines.append("Minimum training confidence: \(minimumTrainingConfidence.displayName)")
        lines.append("Output JSONL: \(outputJSONL.path(percentEncoded: false))")
        lines.append("Output SSS CSV: \(outputCSV.path(percentEncoded: false))")
        lines.append("Output company ML CSV: \(outputMLCSV.path(percentEncoded: false))")
        lines.append("Output workshop directory: \(outputWorkshopDirectory.path(percentEncoded: false))")
        lines.append("")
        lines.append("Providers")
        for (provider, count) in topCounts(groupCounts(rows.map(\.provider)), limit: 20) {
            lines.append("  \(padded(count)) \(provider)")
        }
        lines.append("")
        lines.append("Confidence")
        for level in [SableLibraryShelfConfidenceLevel.high, .medium, .low, .needsReview] {
            lines.append("  \(level.displayName): \(rows.filter { $0.confidence == level.rawValue }.count)")
        }
        lines.append("")
        lines.append("Top training labels")
        for (label, count) in topCounts(groupCounts(trainingRows.map(\.trainingLabel)), limit: 20) {
            lines.append("  \(padded(count)) \(label)")
        }
        lines.append("")
        lines.append("Top company ML labels")
        for (label, count) in topCounts(groupCounts(mlCompanyRows.map(\.label)), limit: 20) {
            lines.append("  \(padded(count)) \(label)")
        }
        lines.append("")
        lines.append("Workshop lessons")
        for (name, count) in workshop.countsByLesson {
            lines.append("  \(padded(count)) \(name)")
        }
        if !failedRows.isEmpty {
            lines.append("")
            lines.append("Skipped rows")
            lines.append(contentsOf: failedRows.prefix(20).map { "  \($0)" })
            if failedRows.count > 20 {
                lines.append("  ... \(failedRows.count - 20) more")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func groupCounts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private func topCounts(_ counts: [String: Int], limit: Int) -> [(String, Int)] {
        counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        .prefix(limit)
        .map { ($0.key, $0.value) }
    }

    private func padded(_ value: Int) -> String {
        String(format: "%5d", value)
    }
}

private enum CorpusError: LocalizedError {
    case invalidArgument(String)
    case invalidValue(String, String)
    case missingValue(String)
    case noInput

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "Unknown argument \(argument). Use --help for options."
        case .invalidValue(let argument, let value):
            return "\(argument) could not use value \(value)."
        case .missingValue(let argument):
            return "\(argument) needs a value."
        case .noInput:
            return "Add --mangabaka-jsonl or --ranobedb-pgdump."
        }
    }
}

private extension SableLibraryShelfConfidenceLevel {
    init?(argumentValue: String) {
        switch normalizedText(argumentValue) {
        case "high":
            self = .high
        case "medium":
            self = .medium
        case "low":
            self = .low
        case "needsreview", "review", "needs_review":
            self = .needsReview
        default:
            return nil
        }
    }

    var trainingRank: Int {
        switch self {
        case .needsReview: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }
}

private func confidenceRank(_ value: String) -> Int {
    SableLibraryShelfConfidenceLevel(rawValue: value)?.trainingRank ?? 0
}

private func providerTrainingText(
    series: ProviderDumpSeries,
    suggestion: SableLibraryShelfSuggestion,
    ledger: SableLibraryShelfDecisionLedger
) -> String {
    let parts = [
        "provider \(series.provider)",
        "media \(series.mediaType ?? "unknown")",
        "title \(series.title)",
        series.description.map { "description \($0)" },
        series.genres.isEmpty ? nil : "genres \(series.genres.joined(separator: " "))",
        series.tags.isEmpty ? nil : "tags \(series.tags.joined(separator: " "))",
        series.contentWarnings.isEmpty ? nil : "warnings \(series.contentWarnings.joined(separator: " "))",
        "suggested \(suggestion.subShelf.displayName)",
        ledger.evidenceRoles.engineEvidence.isEmpty ? nil : "engine \(ledger.evidenceRoles.engineEvidence.joined(separator: " "))"
    ].compactMap { $0 }
    return parts
        .joined(separator: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parsePostgresCopyFields(_ line: String) -> [String?] {
    line.split(separator: "\t", omittingEmptySubsequences: false).map { field in
        let value = String(field)
        if value == #"\N"# { return nil }
        return unescapePostgresCopyText(value)
    }
}

private func unescapePostgresCopyText(_ value: String) -> String {
    var result = ""
    var iterator = value.makeIterator()
    while let character = iterator.next() {
        if character != "\\" {
            result.append(character)
            continue
        }
        guard let escaped = iterator.next() else {
            result.append("\\")
            break
        }
        switch escaped {
        case "n": result.append("\n")
        case "r": result.append("\r")
        case "t": result.append("\t")
        case "b": result.append("\u{08}")
        case "f": result.append("\u{0C}")
        default: result.append(escaped)
        }
    }
    return result
}

private func text(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        return cleanText(string)
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

private func intAny(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
        return nil
    }
}

private func boolAny(_ value: Any?) -> Bool? {
    switch value {
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number.boolValue
    case let string as String:
        switch normalizedText(string) {
        case "true", "t", "yes", "1":
            return true
        case "false", "f", "no", "0":
            return false
        default:
            return nil
        }
    default:
        return nil
    }
}

private func stringValues(from value: Any?) -> [String] {
    switch value {
    case let string as String:
        if string.contains("\n") || string.contains(";") || string.contains("|") {
            return splitAliasText(string)
        }
        return cleanText(string).map { [$0] } ?? []
    case let array as [String]:
        return array.compactMap(cleanText)
    case let array as [Any]:
        return array.compactMap(text)
    default:
        return []
    }
}

private func namedValues(from value: Any?) -> [String] {
    switch value {
    case let array as [[String: Any]]:
        return array.compactMap { row in
            text(row["name"])
                ?? text(row["title"])
                ?? text(row["label"])
                ?? text(row["value"])
                ?? text(row["name_en"])
        }
    case let dictionary as [String: Any]:
        return [
            text(dictionary["name"]),
            text(dictionary["title"]),
            text(dictionary["label"]),
            text(dictionary["value"]),
            text(dictionary["name_en"])
        ].compactMap { $0 }
    default:
        return stringValues(from: value)
    }
}

private func mangaBakaV2Names(from value: Any?, whereGenre shouldBeGenre: Bool) -> [String] {
    guard let rows = value as? [[String: Any]] else {
        return namedValues(from: value)
    }
    return rows.compactMap { row in
        let explicitGenre = boolAny(row["isGenre"])
            ?? boolAny(row["is_genre"])
        let type = normalizedText(text(row["type"]) ?? text(row["category"]) ?? "")
        let isGenre = explicitGenre ?? (type.isEmpty ? shouldBeGenre : type == "genre")
        guard isGenre == shouldBeGenre else { return nil }
        return text(row["name"])
            ?? text(row["label"])
            ?? text(row["value"])
    }
}

private func mangaBakaContentWarningNames(from value: Any?) -> [String] {
    guard let rows = value as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        let isExplicit = boolAny(row["isExplicit"])
            ?? boolAny(row["is_explicit"])
            ?? boolAny(row["explicit"])
            ?? boolAny(row["adult"])
            ?? false
        let rating = normalizedText(text(row["contentRating"]) ?? text(row["content_rating"]) ?? "")
        guard isExplicit || ["adult", "mature", "hentai", "erotica"].contains(rating) else { return nil }
        return text(row["name"])
            ?? text(row["label"])
            ?? text(row["value"])
    }
}

private func mangaBakaLegacyTags(from value: Any?) -> (genres: [String], tags: [String]) {
    guard let rows = value as? [[String: Any]] else {
        return ([], namedValues(from: value))
    }
    var genres: [String] = []
    var tags: [String] = []
    for row in rows {
        guard let name = text(row["name"]) ?? text(row["label"]) ?? text(row["value"]) else { continue }
        let type = normalizedText(text(row["type"]) ?? text(row["ttype"]) ?? text(row["category"]) ?? "")
        if type == "genre" || boolAny(row["isGenre"]) == true || boolAny(row["is_genre"]) == true {
            genres.append(name)
        } else {
            tags.append(name)
        }
    }
    return (genres, tags)
}

private func cleanText(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func int(_ value: String?) -> Int? {
    guard let value = cleanText(value) else { return nil }
    return Int(value)
}

private func bool(_ value: String?) -> Bool {
    switch normalizedText(value ?? "") {
    case "t", "true", "1", "yes":
        return true
    default:
        return false
    }
}

private func packedYear(fromPackedDate value: Int?) -> Int? {
    guard let value, value >= 10000 else { return nil }
    let year = value / 10000
    return (1000...9999).contains(year) ? year : nil
}

private func splitAliasText(_ value: String?) -> [String] {
    guard let value else { return [] }
    return uniqueStrings(
        value
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ";|")))
            .compactMap(cleanText)
    )
}

private func uniqueStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        guard let cleaned = cleanText(value) else { continue }
        let key = normalizedText(cleaned)
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        result.append(cleaned)
    }
    return result
}

private func normalizedText(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9+/#]+"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func stableProviderID(provider: String, title: String) -> String {
    "\(provider)-\(abs(title.hashValue))"
}

private func csvEscaped(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
