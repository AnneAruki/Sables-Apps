//
//  ranobedb_shelf_smoke.swift
//  Sable's Library
//
//  Compile with:
//  swiftc "Sable's Library/App/Core/SableLibraryShelfTagClassifier.swift" \
//      "Sable's Library/App/Core/SableLibraryShelfCatalog.swift" \
//      script/ranobedb_shelf_smoke.swift \
//      -o /tmp/ranobedb_shelf_smoke
//
//  Then run:
//  /tmp/ranobedb_shelf_smoke --count 300
//  /tmp/ranobedb_shelf_smoke --all --output-jsonl /tmp/ranobedb-sss-corpus.jsonl
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
enum RanobeDBShelfSmoke {
    static func main() async {
        do {
            let arguments = try SmokeArguments.parse(CommandLine.arguments.dropFirst())
            if arguments.showHelp {
                print(SmokeArguments.helpText)
                return
            }

            let runner = SmokeRunner(arguments: arguments)
            let report = try await runner.run()
            print(report.render(showIDs: arguments.showIDs, reviewLimit: arguments.reviewLimit))
        } catch {
            fputs("RanobeDB shelf smoke failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct SmokeArguments {
    var count = 300
    var reviewLimit = 40
    var concurrency = 4
    var fetchAll = false
    var useDetails = true
    var useCache = true
    var showIDs = false
    var showHelp = false
    var rateLimitPerMinute = 55
    var outputJSONL: URL?
    var cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sable-ranobedb-shelf-smoke", isDirectory: true)

    static let helpText = """
    RanobeDB shelf smoke

    Options:
      --count N          Number of first RanobeDB series to inspect. Default: 300.
      --all              Inspect every series returned by the API list endpoint.
      --basic            Use only the list endpoint. Faster, but much weaker.
      --no-cache         Ignore the temporary response cache.
      --cache-dir PATH   Store temporary API responses at PATH.
      --concurrency N    Number of detail requests in flight. Default: 4.
      --rate-limit N     Max network requests per minute. Default: 55.
      --output-jsonl PATH
                         Write an SSS training/audit corpus as JSON Lines.
      --review-limit N   Number of low/review rows to print. Default: 40.
      --show-ids         Include RanobeDB ids in printed rows.
      --help             Show this help.
    """

    static func parse(_ rawArguments: ArraySlice<String>) throws -> SmokeArguments {
        var result = SmokeArguments()
        var arguments = Array(rawArguments)

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--help", "-h":
                result.showHelp = true
            case "--count":
                result.count = try nextInt(after: argument, from: &arguments)
            case "--all":
                result.fetchAll = true
            case "--basic":
                result.useDetails = false
            case "--no-cache":
                result.useCache = false
            case "--cache-dir":
                result.cacheDirectory = URL(fileURLWithPath: try nextString(after: argument, from: &arguments), isDirectory: true)
            case "--concurrency":
                result.concurrency = try nextInt(after: argument, from: &arguments)
            case "--rate-limit":
                result.rateLimitPerMinute = try nextInt(after: argument, from: &arguments)
            case "--output-jsonl":
                result.outputJSONL = URL(fileURLWithPath: try nextString(after: argument, from: &arguments))
            case "--review-limit":
                result.reviewLimit = try nextInt(after: argument, from: &arguments)
            case "--show-ids":
                result.showIDs = true
            default:
                throw SmokeError.invalidArgument(argument)
            }
        }

        result.count = max(1, result.count)
        result.concurrency = max(1, min(result.concurrency, 10))
        result.rateLimitPerMinute = max(1, min(result.rateLimitPerMinute, 60))
        result.reviewLimit = max(0, result.reviewLimit)
        return result
    }

    private static func nextString(after argument: String, from arguments: inout [String]) throws -> String {
        guard !arguments.isEmpty else { throw SmokeError.missingValue(argument) }
        return arguments.removeFirst()
    }

    private static func nextInt(after argument: String, from arguments: inout [String]) throws -> Int {
        let value = try nextString(after: argument, from: &arguments)
        guard let intValue = Int(value) else { throw SmokeError.invalidValue(argument, value) }
        return intValue
    }
}

private struct SmokeRunner {
    var arguments: SmokeArguments
    private let pacer: APIRequestPacer

    init(arguments: SmokeArguments) {
        self.arguments = arguments
        pacer = APIRequestPacer(requestsPerMinute: arguments.rateLimitPerMinute)
    }

    func run() async throws -> SmokeReport {
        let listSeries = try await fetchSeriesList()

        let series: [SmokeSeries]
        let failedDetailFetches: [String]
        if arguments.useDetails {
            let detailResult = await fetchDetails(for: listSeries)
            let detailsByID = Dictionary(uniqueKeysWithValues: detailResult.series.map { ($0.id, $0) })
            series = listSeries.map { detailsByID[$0.id] ?? $0 }
            failedDetailFetches = detailResult.failures
        } else {
            series = listSeries
            failedDetailFetches = []
        }

        let rows = series.map { series in
            SmokeSuggestion(series: series, suggestion: SableLibraryShelfCatalog.suggestShelf(for: series.catalogInput))
        }

        if let outputJSONL = arguments.outputJSONL {
            try writeCorpusJSONL(rows, to: outputJSONL)
        }

        return SmokeReport(
            requestedCount: arguments.count,
            requestedAll: arguments.fetchAll,
            fetchedCount: listSeries.count,
            detailedCount: series.filter(\.hasDetail).count,
            failedDetailFetches: failedDetailFetches,
            outputJSONL: arguments.outputJSONL,
            rows: rows
        )
    }

    private func fetchSeriesList() async throws -> [SmokeSeries] {
        let pageSize = 100
        var page = 1
        var totalPages = 1
        var listRows: [[String: Any]] = []

        repeat {
            let url = listURL(page: page, limit: min(pageSize, max(arguments.count - listRows.count, 1)))
            let cacheKey: String
            if arguments.fetchAll {
                cacheKey = "series-list-all-page-\(page).json"
            } else {
                cacheKey = "series-list-count-\(arguments.count)-page-\(page).json"
            }

            let listObject = try await fetchObject(url: url, cacheKey: cacheKey)
            let pageRows = listObject["series"] as? [[String: Any]] ?? []
            listRows.append(contentsOf: pageRows)

            totalPages = Self.int(listObject["totalPages"]) ?? page
            page += 1
        } while page <= totalPages && (arguments.fetchAll || listRows.count < arguments.count)

        return listRows.prefix(arguments.fetchAll ? listRows.count : arguments.count)
            .compactMap(SmokeSeries.init(listRow:))
    }

    private func listURL(page: Int, limit: Int) -> URL {
        var components = URLComponents(string: "https://ranobedb.org/api/v0/series")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 100)))"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return components.url!
    }

    private func detailURL(id: Int) -> URL {
        URL(string: "https://ranobedb.org/api/v0/series/\(id)")!
    }

    private func fetchDetails(for listSeries: [SmokeSeries]) async -> (series: [SmokeSeries], failures: [String]) {
        var detailed: [SmokeSeries] = []
        var failures: [String] = []

        for chunk in listSeries.chunked(size: arguments.concurrency) {
            await withTaskGroup(of: DetailFetch.self) { group in
                for series in chunk {
                    group.addTask {
                        do {
                            let object = try await fetchObject(
                                url: detailURL(id: series.id),
                                cacheKey: "series-\(series.id).json"
                            )
                            guard let detail = SmokeSeries(detailObject: object, fallback: series) else {
                                return DetailFetch(id: series.id, series: nil, error: "unreadable detail payload")
                            }
                            return DetailFetch(id: series.id, series: detail, error: nil)
                        } catch {
                            return DetailFetch(id: series.id, series: nil, error: error.localizedDescription)
                        }
                    }
                }

                for await fetch in group {
                    if let series = fetch.series {
                        detailed.append(series)
                    } else {
                        failures.append("#\(fetch.id): \(fetch.error ?? "unknown error")")
                    }
                }
            }
        }

        return (detailed, failures.sorted())
    }

    private func fetchObject(url: URL, cacheKey: String) async throws -> [String: Any] {
        let data = try await fetchData(url: url, cacheKey: cacheKey)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SmokeError.invalidJSON(url.absoluteString)
        }
        return object
    }

    private func fetchData(url: URL, cacheKey: String) async throws -> Data {
        let cacheURL = arguments.cacheDirectory.appendingPathComponent(cacheKey)
        if arguments.useCache,
           let data = try? Data(contentsOf: cacheURL) {
            return data
        }

        var request = URLRequest(url: url)
        request.setValue("SableLibraryRanobeDBShelfSmoke/1.0", forHTTPHeaderField: "User-Agent")
        await pacer.waitIfNeeded()
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw SmokeError.httpStatus(httpResponse.statusCode, url.absoluteString)
        }

        if arguments.useCache {
            try FileManager.default.createDirectory(at: arguments.cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
        return data
    }

    private func writeCorpusJSONL(_ rows: [SmokeSuggestion], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for row in rows {
            data.append(try encoder.encode(SmokeCorpusRecord(row: row)))
            data.append(contentsOf: Data("\n".utf8))
        }
        try data.write(to: url, options: .atomic)
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

private actor APIRequestPacer {
    private let interval: TimeInterval
    private var lastRequestDate: Date?

    init(requestsPerMinute: Int) {
        interval = 60 / Double(max(1, requestsPerMinute))
    }

    func waitIfNeeded() async {
        let now = Date()
        if let lastRequestDate {
            let elapsed = now.timeIntervalSince(lastRequestDate)
            if elapsed < interval {
                let delay = UInt64((interval - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        lastRequestDate = Date()
    }
}

private struct DetailFetch {
    var id: Int
    var series: SmokeSeries?
    var error: String?
}

private struct SmokeSeries {
    var id: Int
    var title: String
    var description: String?
    var genres: [String]
    var tags: [String]
    var contentWarnings: [String]
    var hasDetail: Bool

    init?(listRow row: [String: Any]) {
        guard let id = Self.int(row["id"]),
              let title = Self.text(row["title"]) else {
            return nil
        }

        self.id = id
        self.title = title
        description = nil
        genres = []
        tags = []
        contentWarnings = []
        hasDetail = false
    }

    init?(detailObject object: [String: Any], fallback: SmokeSeries) {
        guard let series = object["series"] as? [String: Any] else { return nil }
        id = Self.int(series["id"]) ?? fallback.id
        title = Self.text(series["title"]) ?? fallback.title
        description = Self.text(series["description"])
            ?? Self.text((series["book_description"] as? [String: Any])?["description"])

        let tagRows = series["tags"] as? [[String: Any]] ?? []
        genres = Self.names(from: tagRows, type: "genre")
        tags = Self.names(from: tagRows, excludingType: "genre")
        contentWarnings = Self.names(from: tagRows, type: "content")
        hasDetail = true
    }

    var catalogInput: SableLibraryShelfCatalogInput {
        let records = genres.map {
            SableLibraryShelfTagRecord(name: $0, isGenre: true, provider: "ranobedb")
        } + tags.map {
            SableLibraryShelfTagRecord(name: $0, isGenre: false, provider: "ranobedb")
        }

        return SableLibraryShelfCatalogInput(
            title: title,
            description: description,
            genres: genres,
            tags: tags,
            tagRecords: records,
            contentWarnings: contentWarnings,
            mediaType: "lightNovel"
        )
    }

    private static func names(from rows: [[String: Any]], type: String) -> [String] {
        unique(rows.compactMap { row in
            guard text(row["ttype"])?.lowercased() == type else { return nil }
            return text(row["name"])
        })
    }

    private static func names(from rows: [[String: Any]], excludingType type: String) -> [String] {
        unique(rows.compactMap { row in
            guard text(row["ttype"])?.lowercased() != type else { return nil }
            return text(row["name"])
        })
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func text(_ value: Any?) -> String? {
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

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        guard let text = text(value) else { return nil }
        return Int(text)
    }
}

private struct SmokeCorpusRecord: Encodable {
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

    var provider = "ranobedb"
    var providerID: Int
    var providerURL: String
    var title: String
    var description: String?
    var genres: [String]
    var tags: [String]
    var contentWarnings: [String]
    var hasDetail: Bool
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

    init(row: SmokeSuggestion) {
        let ledger = row.ledger
        providerID = row.series.id
        providerURL = "https://ranobedb.org/series/\(row.series.id)"
        title = row.series.title
        description = row.series.description
        genres = row.series.genres
        tags = row.series.tags
        contentWarnings = row.series.contentWarnings
        hasDetail = row.series.hasDetail
        suggestedShelfCode = row.suggestion.shelf.code
        suggestedSubShelfCode = row.suggestion.subShelf.code
        suggestedPath = row.suggestion.displayPath
        confidence = row.suggestion.confidenceLevel.rawValue
        confidenceScore = row.suggestion.confidence
        actionability = ledger.actionability.rawValue
        ruleChangeNeeded = ledger.ruleChangeNeeded
        evidence = row.suggestion.evidence.map {
            Evidence(source: $0.source.rawValue, terms: $0.matchedTerms, score: $0.score, note: $0.note)
        }
        evidenceRoles = row.suggestion.evidenceRoles
        alternatives = row.suggestion.alternatives.map {
            Alternative(
                shelfCode: $0.shelf.code,
                subShelfCode: $0.subShelf.code,
                path: "\($0.shelf.displayName) / \($0.subShelf.displayName)",
                score: $0.score
            )
        }
        facets = row.suggestion.facets
        warnings = row.suggestion.warnings
        competingShelves = ledger.competingShelves
        whyNotCompeting = ledger.whyNotCompeting
        neededEvidence = ledger.neededEvidence
    }
}

private struct SmokeSuggestion {
    var series: SmokeSeries
    var suggestion: SableLibraryShelfSuggestion

    var ledger: SableLibraryShelfDecisionLedger {
        SableLibraryShelfCatalog.decisionLedger(for: series.catalogInput, suggestion: suggestion)
    }

    var reviewKey: Int {
        switch suggestion.confidenceLevel {
        case .needsReview: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    func renderedTitle(showIDs: Bool) -> String {
        showIDs ? "\(series.title) {rdb-\(series.id)}" : series.title
    }

    func evidenceSummary() -> String {
        suggestion.evidence
            .prefix(3)
            .map { point in
                let terms = point.matchedTerms.prefix(4).joined(separator: ", ")
                return "\(point.source.displayName): \(terms)"
            }
            .joined(separator: " | ")
    }

    func evidenceRoleSummary() -> String {
        let roleLedger = ledger.evidenceRoles
        return SableLibraryShelfEvidenceRole.allCases.compactMap { role in
            let values = roleLedger.values(for: role)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(4)
            guard !values.isEmpty else { return nil }
            return "\(role.displayName): \(values.joined(separator: ", "))"
        }
        .joined(separator: " | ")
    }

    func patternHint() -> String? {
        let text = normalizedAuditText
        if containsAny(text, ["magic academy", "mage knight", "duel", "duels", "battle"])
            && containsAny(text, ["academy", "school", "student", "students", "lecturer", "teacher", "classroom"]) {
            return "magic academy / battle school / fantasy school combat"
        }
        if containsAny(text, ["war", "military", "army", "general", "soldier", "soldiers", "battlefield"]) {
            return "military fantasy / war-action overlap"
        }
        if containsAny(text, ["romance", "love", "fiance", "fiancee", "bride", "marriage"])
            && containsAny(text, ["fantasy", "magic", "supernatural", "academy", "school"]) {
            return "fantasy romance / school-fantasy overlap"
        }
        if containsAny(text, ["dungeon", "guild", "adventurer", "quest", "journey"]) {
            return "adventure / dungeon-fantasy overlap"
        }
        return nil
    }

    func actionabilityLabels() -> [SableLibraryShelfDecisionActionability] {
        [ledger.actionability]
    }

    private var normalizedAuditText: String {
        ([series.title, series.description].compactMap { $0 } + series.genres + series.tags + suggestion.evidence.flatMap(\.matchedTerms))
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9+/#]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { term in
            let normalizedTerm = term
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9+/#]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedTerm.isEmpty else { return false }
            return text.range(
                of: #"(?<![a-z0-9])"# + NSRegularExpression.escapedPattern(for: normalizedTerm) + #"(?![a-z0-9])"#,
                options: .regularExpression
            ) != nil
        }
    }

}

private struct SmokeReport {
    var requestedCount: Int
    var requestedAll: Bool
    var fetchedCount: Int
    var detailedCount: Int
    var failedDetailFetches: [String]
    var outputJSONL: URL?
    var rows: [SmokeSuggestion]

    func render(showIDs: Bool, reviewLimit: Int) -> String {
        var lines: [String] = []
        lines.append("RanobeDB SSS smoke")
        lines.append("Requested: \(requestedAll ? "all" : "\(requestedCount)")")
        lines.append("Fetched list rows: \(fetchedCount)")
        lines.append("Fetched detail rows: \(detailedCount)")
        lines.append("Real library folders changed: 0")
        if let outputJSONL {
            lines.append("Corpus JSONL: \(outputJSONL.path(percentEncoded: false))")
        }
        lines.append("")
        lines.append("Confidence")
        for level in [SableLibraryShelfConfidenceLevel.high, .medium, .low, .needsReview] {
            lines.append("  \(level.displayName): \(count(level))")
        }
        lines.append("")
        lines.append("Top shelves")
        for (path, count) in topCounts(pathCounts(), limit: 20) {
            lines.append("  \(padded(count)) \(path)")
        }
        lines.append("")
        lines.append("Broad fallback shelves")
        let fallbackRows = broadFallbackRows()
        if fallbackRows.isEmpty {
            lines.append("  None")
        } else {
            for row in fallbackRows {
                lines.append("  \(padded(row.count)) \(row.path)")
            }
            let fallbackTotal = fallbackRows.reduce(0) { $0 + $1.count }
            lines.append("  Fallback total: \(fallbackTotal) / \(rows.count) = \(percent(fallbackTotal, of: rows.count))%")
        }

        let reviewRows = rows
            .filter { [.low, .needsReview].contains($0.suggestion.confidenceLevel) }
            .sorted {
                if $0.reviewKey != $1.reviewKey { return $0.reviewKey < $1.reviewKey }
                return $0.suggestion.confidence < $1.suggestion.confidence
            }

        lines.append("")
        lines.append("Review actionability")
        let actionabilityCounts = actionabilityCounts(for: reviewRows)
        for label in SableLibraryShelfDecisionActionability.allCases where label != .goodEvidence {
            lines.append("  \(label.displayName): \(actionabilityCounts[label, default: 0])")
        }
        lines.append("")
        lines.append("Possible rule-problem patterns")
        let patternCounts = possibleRulePatternCounts(for: reviewRows)
        if patternCounts.isEmpty {
            lines.append("  None")
        } else {
            for (pattern, count) in patternCounts {
                lines.append("  \(padded(count)) \(pattern)")
            }
        }

        lines.append("")
        lines.append("Low / needs-review rows")
        if reviewRows.isEmpty {
            lines.append("  None")
        } else {
            for row in reviewRows.prefix(reviewLimit) {
                let confidence = Int((row.suggestion.confidence * 100).rounded())
                lines.append("  \(row.suggestion.confidenceLevel.displayName) \(confidence)% \(row.suggestion.subShelf.displayName) — \(row.renderedTitle(showIDs: showIDs))")
                let labels = row.actionabilityLabels()
                lines.append("      Actionability: \(labels.map(\.displayName).joined(separator: ", "))")
                let ledger = row.ledger
                if labels.contains(.possibleRuleProblem),
                   let pattern = row.patternHint() {
                    lines.append("      Pattern hint: \(pattern)")
                }
                if !ledger.neededEvidence.isEmpty {
                    lines.append("      Needed evidence: \(ledger.neededEvidence.joined(separator: ", "))")
                }
                if let reason = ledger.whyNotCompeting.first {
                    lines.append("      Why not nearest shelf: \(reason)")
                }
                let evidence = row.evidenceSummary()
                if !evidence.isEmpty {
                    lines.append("      Evidence: \(evidence)")
                }
                let roleSummary = row.evidenceRoleSummary()
                if !roleSummary.isEmpty {
                    lines.append("      Evidence roles: \(roleSummary)")
                }
                if !row.suggestion.warnings.isEmpty {
                    lines.append("      Warnings: \(row.suggestion.warnings.joined(separator: " "))")
                }
            }
            if reviewRows.count > reviewLimit {
                lines.append("  ... \(reviewRows.count - reviewLimit) more hidden by --review-limit")
            }
        }

        let emptyDescriptionCount = rows.filter {
            ($0.series.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count
        lines.append("")
        lines.append("Balance notes")
        lines.append("  No-description rows: \(emptyDescriptionCount)")
        lines.append(contentsOf: balanceNotes().map { "  \($0)" })

        if !failedDetailFetches.isEmpty {
            lines.append("")
            lines.append("Detail fetch failures")
            lines.append(contentsOf: failedDetailFetches.prefix(20).map { "  \($0)" })
            if failedDetailFetches.count > 20 {
                lines.append("  ... \(failedDetailFetches.count - 20) more")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func count(_ level: SableLibraryShelfConfidenceLevel) -> Int {
        rows.filter { $0.suggestion.confidenceLevel == level }.count
    }

    private func pathCounts() -> [String: Int] {
        rows.reduce(into: [:]) { counts, row in
            counts[row.suggestion.subShelf.displayName, default: 0] += 1
        }
    }

    private func topCounts(_ counts: [String: Int], limit: Int) -> [(String, Int)] {
        counts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    private func balanceNotes() -> [String] {
        guard !rows.isEmpty else { return ["No rows to inspect."] }
        let total = Double(rows.count)
        let counts = pathCounts()
        var notes: [String] = []

        let overloaded = topCounts(counts, limit: 5)
            .filter { Double($0.1) / total >= 0.18 }
        if overloaded.isEmpty {
            notes.append("No single sub-shelf took 18% or more of the sample.")
        } else {
            for (path, count) in overloaded {
                let percent = Int((Double(count) / total * 100).rounded())
                notes.append("\(path) took \(percent)% of the sample; review it for over-broad vocabulary.")
            }
        }

        let reviewCount = count(.low) + count(.needsReview)
        let reviewPercent = Int((Double(reviewCount) / total * 100).rounded())
        notes.append("Low/needs-review rate: \(reviewPercent)%")

        let fallbackTotal = broadFallbackRows().reduce(0) { $0 + $1.count }
        if fallbackTotal > 0 {
            notes.append("Broad fallback rate: \(percent(fallbackTotal, of: rows.count))%")
        }
        return notes
    }

    private func broadFallbackRows() -> [(path: String, count: Int)] {
        let counts = pathCounts()
        return [
            "21.1 - Adventure & Quest Isekai",
            "20.1 - Magic & Sorcery",
            "10.2 - Quests & Journeys",
            "30.1 - Contemporary Romance",
            "60.1 - Science Fiction & Speculative Worlds"
        ]
        .compactMap { path in
            let count = counts[path, default: 0]
            return count > 0 ? (path, count) : nil
        }
    }

    private func actionabilityCounts(for reviewRows: [SmokeSuggestion]) -> [SableLibraryShelfDecisionActionability: Int] {
        reviewRows.reduce(into: [:]) { counts, row in
            for label in row.actionabilityLabels() {
                counts[label, default: 0] += 1
            }
        }
    }

    private func possibleRulePatternCounts(for reviewRows: [SmokeSuggestion]) -> [(pattern: String, count: Int)] {
        let counts = reviewRows.reduce(into: [String: Int]()) { counts, row in
            guard row.actionabilityLabels().contains(.possibleRuleProblem) else { return }
            counts[row.patternHint() ?? "unclustered possible rule problem", default: 0] += 1
        }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.map { (pattern: $0.key, count: $0.value) }
    }

    private func padded(_ value: Int) -> String {
        String(format: "%3d", value)
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

private enum SmokeError: LocalizedError {
    case invalidArgument(String)
    case missingValue(String)
    case invalidValue(String, String)
    case invalidJSON(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "Unknown argument \(argument). Use --help for options."
        case .missingValue(let argument):
            return "\(argument) needs a value."
        case .invalidValue(let argument, let value):
            return "\(argument) expected a number, got \(value)."
        case .invalidJSON(let url):
            return "The response was not JSON: \(url)"
        case .httpStatus(let status, let url):
            return "HTTP \(status) from \(url)"
        }
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
