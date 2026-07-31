import Foundation
#if canImport(CoreML)
import CoreML
#endif

struct LocalSeriesRecord {
    var comicInfoURL: URL
    var relativePath: String
    var title: String
    var description: String?
    var volumeDescriptions: [String]
    var genres: [String]
    var themes: [String]
    var tags: [String]
    var tagRecords: [SableLibraryShelfTagRecord]
    var contentWarnings: [String]
    var mediaType: String?
    var mangaBakaID: String?
    var ranobeID: String?
}

let fileManager = FileManager.default

struct LocalAuditOptions {
    var root: URL
    var includeReady: Bool
    var includeUnchanged: Bool
    var summaryOnly: Bool
    var withML: Bool
    var limit: Int?
    var modelDirectory: URL

    init(arguments: [String]) {
        var rootArgument: String?
        var includeReady = false
        var includeUnchanged = false
        var summaryOnly = false
        var withML = false
        var limit: Int?
        var modelDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Sable's Library/App/ML")

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--include-ready":
                includeReady = true
                index += 1
            case "--include-unchanged":
                includeUnchanged = true
                index += 1
            case "--summary-only":
                summaryOnly = true
                index += 1
            case "--with-ml":
                withML = true
                index += 1
            case "--limit":
                if index + 1 < arguments.count {
                    limit = Int(arguments[index + 1])
                }
                index += 2
            case "--model-dir":
                if index + 1 < arguments.count {
                    modelDirectory = URL(fileURLWithPath: arguments[index + 1])
                }
                index += 2
            default:
                if !argument.hasPrefix("--"), rootArgument == nil {
                    rootArgument = argument
                }
                index += 1
            }
        }

        let defaultRoot = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Sable Library", isDirectory: true)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.root = URL(
            fileURLWithPath: rootArgument ?? defaultRoot.path(percentEncoded: false)
        )
        self.includeReady = includeReady
        self.includeUnchanged = includeUnchanged
        self.summaryOnly = summaryOnly
        self.withML = withML
        self.limit = limit
        self.modelDirectory = modelDirectory
    }
}

struct LocalAuditRow {
    var record: LocalSeriesRecord
    var suggestion: SableLibraryShelfSuggestion
    var ledger: SableLibraryShelfDecisionLedger
    var currentShelfCode: String?
    var currentSubShelfCode: String?
    var differs: Bool
}

struct LocalMLSmokeResult {
    var labels: [String: String]

    var shelfLabel: String? {
        labels["SableLibraryShelfClassifier"]
    }

    var descriptionLabel: String? {
        labels["SableLibraryDescriptionAboutnessClassifier"]
    }

    var managerLabel: String? {
        labels["SableLibraryEvidenceMeetingClassifier"]
    }

    var shelfCode: String? {
        guard let shelfLabel else { return nil }
        if shelfLabel.hasPrefix("shelf.") {
            return String(shelfLabel.dropFirst("shelf.".count))
        }
        if shelfLabel.hasPrefix("description.shelf.") {
            return String(shelfLabel.dropFirst("description.shelf.".count))
        }
        return nil
    }

    func compactNote() -> String {
        let parts = [
            shelfLabel.map { "Shelf ML: \(displayMLLabel($0))" },
            descriptionLabel.map { "Description ML: \(displayMLLabel($0))" },
            managerLabel.map { "Manager ML: \(displayMLLabel($0))" }
        ].compactMap { $0 }
        return parts.joined(separator: " | ")
    }
}

#if canImport(CoreML)
final class LocalMLSmoke {
    let modelDirectory: URL
    private var models: [String: MLModel] = [:]

    static let modelNames = [
        "SableLibraryShelfClassifier",
        "SableLibraryDescriptionAboutnessClassifier",
        "SableLibraryTagRoleClassifier",
        "SableLibraryMediaTypeClassifier",
        "SableLibraryWorkFamilyRelationshipClassifier",
        "SableLibraryEvidenceMeetingClassifier",
        "SableLibraryReadingClassifier",
        "SableLibrarySidecarClassifier",
        "SableLibraryDecisionClassifier"
    ]

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func availableModelNames() -> [String] {
        Self.modelNames.filter { model(named: $0) != nil }
    }

    func predict(featureText: String) -> LocalMLSmokeResult {
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["text": featureText]) else {
            return LocalMLSmokeResult(labels: [:])
        }
        var labels: [String: String] = [:]
        for name in Self.modelNames {
            guard let model = model(named: name),
                  let output = try? model.prediction(from: input),
                  let label = output.featureValue(for: "label")?.stringValue else {
                continue
            }
            labels[name] = label
        }
        return LocalMLSmokeResult(labels: labels)
    }

    private func model(named name: String) -> MLModel? {
        if let model = models[name] {
            return model
        }
        let compiledURL = modelDirectory.appendingPathComponent("\(name).mlmodelc")
        if fileManager.fileExists(atPath: compiledURL.path),
           let model = try? MLModel(contentsOf: compiledURL) {
            models[name] = model
            return model
        }
        let sourceURL = modelDirectory.appendingPathComponent("\(name).mlmodel")
        if fileManager.fileExists(atPath: sourceURL.path),
           let compiled = try? MLModel.compileModel(at: sourceURL),
           let model = try? MLModel(contentsOf: compiled) {
            models[name] = model
            return model
        }
        return nil
    }
}
#else
final class LocalMLSmoke {
    let modelDirectory: URL

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func availableModelNames() -> [String] { [] }
    func predict(featureText: String) -> LocalMLSmokeResult { LocalMLSmokeResult(labels: [:]) }
}
#endif

@main
struct LocalShelfReviewAudit {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options = LocalAuditOptions(arguments: arguments)
        let root = options.root
        let comicInfoURLs = allComicInfoURLs(under: root)
        let records = comicInfoURLs.compactMap { readRecord(at: $0, root: root) }

        let mlSmoke = options.withML ? LocalMLSmoke(modelDirectory: options.modelDirectory) : nil
        let availableModelNames = mlSmoke?.availableModelNames() ?? []
        var allRows: [LocalAuditRow] = []
        var mlResultsByPath: [String: LocalMLSmokeResult] = [:]

        for record in records {
            let input = SableLibraryShelfCatalogInput(
                title: record.title,
                description: record.description,
                volumeDescriptions: record.volumeDescriptions,
                genres: record.genres,
                themes: record.themes,
                tags: record.tags,
                tagRecords: record.tagRecords,
                contentWarnings: record.contentWarnings,
                mediaType: record.mediaType
            )
            let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
            let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)
            let currentShelf = shelfComponent(in: record.relativePath, decimal: false)
            let currentSubShelf = shelfComponent(in: record.relativePath, decimal: true)
            let currentShelfCode = currentShelf.map(componentCode)
            let currentSubShelfCode = currentSubShelf.map(componentCode)
            let differs = currentShelf != suggestion.shelf.displayName || currentSubShelf != suggestion.subShelf.displayName
                || currentShelfCode != suggestion.shelf.code || currentSubShelfCode != suggestion.subShelf.code
            let row = LocalAuditRow(
                record: record,
                suggestion: suggestion,
                ledger: ledger,
                currentShelfCode: currentShelfCode,
                currentSubShelfCode: currentSubShelfCode,
                differs: differs
            )
            allRows.append(row)

            if let mlSmoke {
                let featureText = localMLFeatureText(record: record, suggestion: suggestion, ledger: ledger)
                mlResultsByPath[record.relativePath] = mlSmoke.predict(featureText: featureText)
            }
        }

        var reviewRows = allRows.filter { row in
            options.includeUnchanged || (row.differs && (options.includeReady || row.suggestion.confidenceLevel == .low || row.suggestion.confidenceLevel == .needsReview))
        }

        reviewRows.sort {
            if $0.suggestion.subShelf.code == $1.suggestion.subShelf.code {
                return $0.record.title.localizedCaseInsensitiveCompare($1.record.title) == .orderedAscending
            }
            return $0.suggestion.subShelf.code.localizedStandardCompare($1.suggestion.subShelf.code) == .orderedAscending
        }

        print("LOCAL SSS REVIEW AUDIT")
        print("Root: \(root.path)")
        print("ComicInfo sidecars: \(comicInfoURLs.count)")
        print("Readable sidecars: \(records.count)")
        print("Review rows reconstructed: \(reviewRows.count)")
        print("Dry run: no folders or ComicInfo files were changed.")
        if options.withML {
            print("ML smoke: \(availableModelNames.count)/\(LocalMLSmoke.modelNames.count) advisor models loaded from \(options.modelDirectory.path)")
        }
        print("")

        printSummary(rows: allRows, reviewRows: reviewRows, mlResultsByPath: mlResultsByPath)

        if options.summaryOnly {
            return
        }

        let rowsToPrint = options.limit.map { Array(reviewRows.prefix($0)) } ?? reviewRows
        if let limit = options.limit, reviewRows.count > limit {
            print("Showing first \(limit) of \(reviewRows.count) row(s).")
            print("")
        }

        for (index, row) in rowsToPrint.enumerated() {
            let record = row.record
            let suggestion = row.suggestion
            let ledger = row.ledger
            let current = [row.currentShelfCode, row.currentSubShelfCode].compactMap { $0 }.joined(separator: " / ")
            let confidence = Int((suggestion.confidence * 100).rounded())
            print("\(index + 1). \(record.title)")
            print("   path: \(record.relativePath)")
            print("   ids: \(sourceLinks(mangaBakaID: record.mangaBakaID, ranobeID: record.ranobeID))")
            print("   current: \(current.isEmpty ? "unshelved" : current)")
            print("   suggested: \(suggestion.shelf.displayName) / \(suggestion.subShelf.displayName)")
            print("   confidence: \(suggestion.confidenceLevel.displayName) \(confidence)%")
            print("   actionability: \(ledger.actionability.displayName)")
            print("   evidence: \(ledger.mainEvidence.joined(separator: " | "))")
            if !ledger.competingShelves.isEmpty {
                print("   alternatives: \(ledger.competingShelves.joined(separator: " | "))")
            }
            if !ledger.neededEvidence.isEmpty {
                print("   needs: \(ledger.neededEvidence.joined(separator: " | "))")
            }
            if let mlResult = mlResultsByPath[record.relativePath], !mlResult.labels.isEmpty {
                let agreement = mlResult.shelfCode == suggestion.subShelf.code ? "agrees" : "differs"
                print("   ml: shelf advisor \(agreement); \(mlResult.compactNote())")
            }
            print("   genres: \(record.genres.prefix(12).joined(separator: ", "))")
            print("   themes: \(record.themes.prefix(12).joined(separator: ", "))")
            print("   tags: \(record.tags.prefix(16).joined(separator: ", "))")
            if let description = record.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                print("   description: \(singleLine(description).prefix(500))")
            }
            print("")
        }
    }
}

func printSummary(rows: [LocalAuditRow], reviewRows: [LocalAuditRow], mlResultsByPath: [String: LocalMLSmokeResult]) {
    let changedRows = rows.filter(\.differs)
    print("SUMMARY")
    print("Records scanned: \(rows.count)")
    print("Would move/change shelf path: \(changedRows.count)")
    print("Review output rows: \(reviewRows.count)")
    print("")

    printCounter(title: "Confidence", values: rows.map { $0.suggestion.confidenceLevel.displayName })
    printCounter(title: "Actionability", values: rows.map { $0.ledger.actionability.displayName })
    printCounter(title: "Top suggested sub-shelves", values: rows.map { $0.suggestion.subShelf.displayName }, limit: 12)
    printCounter(title: "Top review sub-shelves", values: reviewRows.map { $0.suggestion.subShelf.displayName }, limit: 12)

    guard !mlResultsByPath.isEmpty else {
        print("")
        return
    }

    let modelRows = rows.compactMap { row -> (LocalAuditRow, LocalMLSmokeResult)? in
        guard let result = mlResultsByPath[row.record.relativePath], !result.labels.isEmpty else { return nil }
        return (row, result)
    }
    let shelfCompared = modelRows.filter { $0.1.shelfCode != nil }
    let shelfAgreements = shelfCompared.filter { $0.1.shelfCode == $0.0.suggestion.subShelf.code }
    let shelfDifferences = shelfCompared.filter { $0.1.shelfCode != $0.0.suggestion.subShelf.code }
    print("ML ADVISOR SUMMARY")
    print("Rows with model output: \(modelRows.count)")
    print("Shelf advisor comparable: \(shelfCompared.count)")
    print("Shelf advisor agrees with deterministic SSS: \(shelfAgreements.count)")
    print("Shelf advisor differs from deterministic SSS: \(shelfDifferences.count)")
    printCounter(title: "Shelf ML labels", values: modelRows.compactMap { $0.1.shelfLabel.map(displayMLLabel) }, limit: 12)
    printCounter(title: "Description ML labels", values: modelRows.compactMap { $0.1.descriptionLabel.map(displayMLLabel) }, limit: 8)
    printCounter(title: "Manager ML labels", values: modelRows.compactMap { $0.1.managerLabel.map(displayMLLabel) }, limit: 8)

    let usefulDifferences = shelfDifferences.filter { row, result in
        row.suggestion.confidenceLevel == .low || row.suggestion.confidenceLevel == .needsReview || row.differs
    }.prefix(12)
    if !usefulDifferences.isEmpty {
        print("Notable shelf advisor differences:")
        for (row, result) in usefulDifferences {
            print("- \(row.record.title): SSS \(row.suggestion.subShelf.code), ML \(result.shelfCode ?? result.shelfLabel ?? "unknown")")
        }
    }
    print("")
}

func printCounter(title: String, values: [String], limit: Int = 10) {
    let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
    let sorted = counts.sorted {
        if $0.value == $1.value {
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
        return $0.value > $1.value
    }
    guard !sorted.isEmpty else { return }
    print("\(title):")
    for (value, count) in sorted.prefix(limit) {
        print("- \(value): \(count)")
    }
    print("")
}

func localMLFeatureText(
    record: LocalSeriesRecord,
    suggestion: SableLibraryShelfSuggestion,
    ledger: SableLibraryShelfDecisionLedger
) -> String {
    let parts: [String?] = [
        "provider local",
        "provider_id \(sourceLinks(mangaBakaID: record.mangaBakaID, ranobeID: record.ranobeID))",
        record.mediaType.map { "media \($0)" },
        "title \(record.title)",
        record.genres.isEmpty ? nil : "genres \(record.genres.joined(separator: " "))",
        record.themes.isEmpty ? nil : "themes \(record.themes.joined(separator: " "))",
        record.tags.isEmpty ? nil : "tags \(record.tags.prefix(40).joined(separator: " "))",
        record.contentWarnings.isEmpty ? nil : "warnings \(record.contentWarnings.joined(separator: " "))",
        record.description.map { "description \($0)" },
        record.volumeDescriptions.isEmpty ? nil : "volume_descriptions \(record.volumeDescriptions.prefix(3).joined(separator: " "))",
        "sss \(suggestion.subShelf.code) \(suggestion.displayPath)",
        "manager confidence \(suggestion.confidenceLevel.displayName)",
        "score \(String(format: "%.2f", suggestion.confidence))",
        "actionability \(ledger.actionability.displayName)",
        ledger.competingShelves.isEmpty ? "no competing shelves" : "competing \(ledger.competingShelves.joined(separator: " | "))",
        ledger.neededEvidence.isEmpty ? "no needed evidence" : "needed \(ledger.neededEvidence.joined(separator: " | "))",
        ledger.mainEvidence.isEmpty ? nil : "evidence \(ledger.mainEvidence.joined(separator: " | "))"
    ]
    return parts.compactMap { $0 }
        .joined(separator: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func displayMLLabel(_ label: String) -> String {
    if let shelf = label.removingPrefix("description.shelf.") {
        return "description points toward \(shelf)"
    }
    if let shelf = label.removingPrefix("shelf.") {
        return "shelf \(shelf)"
    }
    if let value = label.removingPrefix("description.confidence.") {
        return "description confidence \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("description.") {
        return "description \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("manager.confidence.") {
        return "manager confidence \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("manager.actionability.") {
        return "manager actionability \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("manager.") {
        return "manager \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("tagRole.") {
        return "tag role \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("mediaType.") {
        return "media type \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("workFamily.") {
        return "work family \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("reading.") {
        return "reading \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("sidecar.") {
        return "sidecar \(prettyLabelSegment(value))"
    }
    if let value = label.removingPrefix("metadata.") {
        return "metadata \(prettyLabelSegment(value))"
    }
    return label
}

func prettyLabelSegment(_ value: String) -> String {
    value.replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .lowercased()
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

func allComicInfoURLs(under root: URL) -> [URL] {
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }
    var urls: [URL] = []
    for case let url as URL in enumerator where url.lastPathComponent == "ComicInfo.json" {
        urls.append(url)
    }
    return urls
}

func readRecord(at url: URL, root: URL) -> LocalSeriesRecord? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    let folderURL = url.deletingLastPathComponent()
    let relativePath = folderURL.path.replacingOccurrences(of: root.path + "/", with: "")
    let title = textValue(object["preferred_title"])
        ?? textValue(object["title"])
        ?? textValue(object["local_title"])
        ?? folderURL.lastPathComponent
    let genres = uniqueStrings(
        sidecarShelfValues(in: object, keys: ["genres", "genre"])
            + providerV2ShelfNames(in: object, keys: ["genres_v2", "tags_v2"], includeGenres: true)
            + ranobeDBShelfNames(in: object, includeGenres: true)
    )
    let themes = uniqueStrings(sidecarShelfValues(in: object, keys: ["themes", "theme"]))
    let tags = uniqueStrings(
        sidecarShelfValues(in: object, keys: ["tags", "subjects", "subject"])
            + providerV2ShelfNames(in: object, keys: ["tags_v2"], includeGenres: false)
            + ranobeDBShelfNames(in: object, includeGenres: false)
    )
    let records = providerV2ShelfTagRecords(in: object) + ranobeDBShelfTagRecords(in: object)
    let warnings = sidecarShelfValues(in: object, keys: ["content_warnings", "warnings"])
    return LocalSeriesRecord(
        comicInfoURL: url,
        relativePath: relativePath,
        title: title,
        description: sidecarShelfDescription(in: object),
        volumeDescriptions: ranobeDBVolumeDescriptions(in: object),
        genres: genres,
        themes: themes,
        tags: tags,
        tagRecords: records,
        contentWarnings: warnings,
        mediaType: textValue(object["type"]),
        mangaBakaID: sourceID(in: object, provider: "mangabaka", keys: ["mangabaka_id", "manga_baka_id", "mb_id"]),
        ranobeID: sourceID(in: object, provider: "ranobedb", keys: ["ranobedb_id", "ranobe_id", "rdb_id"])
    )
}

func ranobeDBShelfNames(in object: [String: Any], includeGenres: Bool) -> [String] {
    var values: [String] = []
    for row in ranobeDBSeriesTags(in: object) {
        let type = textValue(row["ttype"])?.lowercased() ?? ""
        let isGenre = type == "genre"
        guard includeGenres == isGenre else { continue }
        if let name = textValue(row["name"]) {
            values.append(name)
        }
    }
    return uniqueStrings(values)
}

func ranobeDBShelfTagRecords(in object: [String: Any]) -> [SableLibraryShelfTagRecord] {
    var records: [SableLibraryShelfTagRecord] = []
    var seen: Set<String> = []
    for row in ranobeDBSeriesTags(in: object) {
        guard let name = textValue(row["name"]) else { continue }
        let type = textValue(row["ttype"])?.lowercased() ?? "tag"
        let key = "\(name.lowercased())|\(type)"
        guard seen.insert(key).inserted else { continue }
        let weight: String
        switch type {
        case "genre":
            weight = "core"
        case "tag":
            weight = "recurrent"
        default:
            weight = "incidental"
        }
        records.append(SableLibraryShelfTagRecord(
            name: name,
            path: type,
            providerWeight: weight,
            isGenre: type == "genre",
            provider: "ranobedb"
        ))
    }
    return records
}

func ranobeDBSeriesTags(in object: [String: Any]) -> [[String: Any]] {
    guard let sable = object["_sable"] as? [String: Any],
          let ranobeDB = sable["ranobedb"] as? [String: Any],
          let compact = ranobeDB["api_compact"] as? [String: Any],
          let series = compact["series"] as? [String: Any],
          let tags = series["tags"] as? [[String: Any]] else {
        return []
    }
    return tags
}

func ranobeDBVolumeDescriptions(in object: [String: Any]) -> [String] {
    guard let sable = object["_sable"] as? [String: Any],
          let ranobeDB = sable["ranobedb"] as? [String: Any],
          let compact = ranobeDB["api_compact"] as? [String: Any],
          let bookResponses = compact["book_responses"] as? [[String: Any]] else {
        return []
    }
    var descriptions: [String] = []
    for response in bookResponses {
        let payload = response["response"] as? [String: Any]
        let book = payload?["book"] as? [String: Any]
        if let description = textValue(book?["description"]) {
            descriptions.append(description)
        }
    }
    return uniqueStrings(descriptions)
}

func sidecarShelfDescription(in object: [String: Any]) -> String? {
    let bookDescription = object["book_description"] as? [String: Any]
    for candidate in [object["description"], object["summary"], object["synopsis"], bookDescription?["description"]] {
        if let text = textValue(candidate), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
    }
    return nil
}

func sidecarShelfValues(in object: [String: Any], keys: [String]) -> [String] {
    var values: [String] = []
    for key in keys {
        values.append(contentsOf: sidecarShelfStrings(object[key]))
    }
    return uniqueStrings(values)
}

func sidecarShelfStrings(_ value: Any?) -> [String] {
    if let text = textValue(value) {
        return [text]
    }
    if let values = value as? [String] {
        return values
    }
    if let values = value as? [Any] {
        return values.flatMap(sidecarShelfStrings)
    }
    if let row = value as? [String: Any] {
        for key in ["name", "title", "value", "label"] {
            if let text = textValue(row[key]) {
                return [text]
            }
        }
    }
    return []
}

func providerV2ShelfNames(in object: [String: Any], keys: [String], includeGenres: Bool) -> [String] {
    guard let payload = providerPayload(in: object) else { return [] }
    var values: [String] = []
    for key in keys {
        guard let rows = payload[key] as? [[String: Any]] else { continue }
        let keySuggestsGenres = key.localizedCaseInsensitiveContains("genre")
        for row in rows {
            guard row["is_spoiler"] as? Bool != true else { continue }
            let isGenre = row["is_genre"] as? Bool
            if includeGenres {
                guard keySuggestsGenres || isGenre == true else { continue }
            } else if isGenre == true {
                continue
            }
            if let name = textValue(row["name"]) {
                values.append(name)
            }
        }
    }
    return uniqueStrings(values)
}

func providerV2ShelfTagRecords(in object: [String: Any]) -> [SableLibraryShelfTagRecord] {
    guard let payload = providerPayload(in: object) else { return [] }
    var records: [SableLibraryShelfTagRecord] = []
    var seen: Set<String> = []
    for key in ["genres_v2", "tags_v2"] {
        guard let rows = payload[key] as? [[String: Any]] else { continue }
        let keySuggestsGenre = key.localizedCaseInsensitiveContains("genre")
        for row in rows {
            guard row["is_spoiler"] as? Bool != true,
                  let name = textValue(row["name"]) else {
                continue
            }
            let path = textValue(row["name_path"])
            let normalizedKey = [name, path ?? "", "mangabaka"].map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.joined(separator: "|")
            guard seen.insert(normalizedKey).inserted else { continue }
            records.append(SableLibraryShelfTagRecord(
                name: name,
                path: path,
                providerWeight: textValue(row["weight"]),
                isGenre: (row["is_genre"] as? Bool) ?? keySuggestsGenre,
                isSpoiler: row["is_spoiler"] as? Bool,
                isExplicit: row["is_explicit"] as? Bool,
                contentRating: textValue(row["content_rating"]),
                provider: "mangabaka"
            ))
        }
    }
    return records
}

func providerPayload(in object: [String: Any]) -> [String: Any]? {
    guard let sable = object["_sable"] as? [String: Any] else { return nil }
    return sable["mangabaka"] as? [String: Any]
}

func sourceID(in object: [String: Any], provider: String, keys: [String]) -> String? {
    for key in keys {
        if let text = textValue(object[key]) {
            return text
        }
    }
    if let ids = object["ids"] as? [String: Any] {
        if let text = textValue(ids[provider]) {
            return text
        }
        for key in keys {
            if let text = textValue(ids[key]) {
                return text
            }
        }
    }
    if let sourceIDs = object["source_ids"] as? [[String: Any]] {
        for source in sourceIDs {
            let provider = textValue(source["provider"])?.lowercased() ?? ""
            if keys.contains(where: { $0.contains("mangabaka") || $0.contains("mb") }), provider.contains("mangabaka"),
               let value = textValue(source["value"]) ?? textValue(source["id"]) {
                return value
            }
            if keys.contains(where: { $0.contains("ranobe") || $0.contains("rdb") }), provider.contains("ranobe"),
               let value = textValue(source["value"]) ?? textValue(source["id"]) {
                return value
            }
        }
    }
    return nil
}

func shelfComponent(in relativePath: String, decimal: Bool) -> String? {
    for component in relativePath.split(separator: "/").dropFirst() {
        let prefix = component.split(separator: " ").first.map(String.init) ?? ""
        if decimal {
            if prefix.range(of: #"^[0-9]{2}\.[0-9]+$"#, options: .regularExpression) != nil {
                return String(component)
            }
        } else if prefix.range(of: #"^[0-9]{2}$"#, options: .regularExpression) != nil {
            return String(component)
        }
    }
    return nil
}

func componentCode(_ component: String) -> String {
    component.split(separator: " ").first.map(String.init) ?? component
}

func sourceLinks(mangaBakaID: String?, ranobeID: String?) -> String {
    var parts: [String] = []
    if let mangaBakaID {
        parts.append("mb-\(mangaBakaID)")
    }
    if let ranobeID {
        parts.append("rdb-\(ranobeID)")
    }
    return parts.isEmpty ? "none" : parts.joined(separator: ", ")
}

func textValue(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

func uniqueStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        result.append(trimmed)
    }
    return result
}

func singleLine(_ value: String) -> String {
    value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}
