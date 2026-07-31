#!/usr/bin/env swift
//
//  train_sable_library_ml.swift
//  Sable's Library
//
//  Builds a local Core ML text classifier from Sable's local learning memory,
//  ML training-event receipts, and optional weak filename seeds.
//

import CreateML
import Foundation
import TabularData

private struct Options {
    var repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var outputURL: URL?
    var datasetURL: URL?
    var scanRoots: [URL] = []
    var extraTrainingCSVs: [URL] = []
    var maxExtraRowsPerLabel = 1200
    var includeAppDefaults = true
    var includeTrainingEvents = true
    var includeWeakFilenameSeeds = true
    var maxWeakFilenameSeeds = 900
    var modelFlavor = "personal"
    var anonymizeTrainingText = false
    var trainModelSuite = false
    var selectedSuiteModels: Set<String> = []
}

private struct TrainingExample: Hashable {
    var text: String
    var label: String
    var source: String
}

private struct ModelSuiteSpec {
    var modelName: String
    var labelPrefixes: [String]
    var extraLabels: Set<String> = []
    var description: String

    func includes(_ label: String) -> Bool {
        extraLabels.contains(label) || labelPrefixes.contains { label.hasPrefix($0) }
    }
}

private struct WordTaggerExample {
    var tokens: [MLWordTagger.Token]
    var labels: [String]
    var source: String
}

private struct WordTaggerSpec {
    var modelName: String
    var description: String
    var examples: [WordTaggerExample]
}

private struct RecommenderExample: Hashable {
    var context: String
    var item: String
    var rating: Double
    var source: String
}

private struct RecommenderSpec {
    var modelName: String
    var description: String
}

private struct LearningMemory: Decodable {
    struct CleanupKindTermMemory: Decodable {
        var kindCounts: [String: Int]
    }

    struct RawReadingLaneTermMemory: Decodable {
        var laneCounts: [String: Int]
    }

    struct MetadataTermMemory: Decodable {
        var usedCount: Int
        var dismissedCount: Int
    }

    struct MangaBakaSeriesMemory: Decodable {
        var keptLocalCount: Int
        var acceptedCandidateIDs: [String: Int]
    }

    struct PDFTriageTermMemory: Decodable {
        var documentCount: Int
        var bookCount: Int
    }

    var cleanupKindTerms: [String: CleanupKindTermMemory]
    var rawReadingLaneTerms: [String: RawReadingLaneTermMemory]
    var metadataTerms: [String: MetadataTermMemory]
    var mangaBakaSeries: [String: MangaBakaSeriesMemory]
    var pdfTriageTerms: [String: PDFTriageTermMemory]

    enum CodingKeys: String, CodingKey {
        case cleanupKindTerms
        case rawReadingLaneTerms
        case metadataTerms
        case mangaBakaSeries
        case pdfTriageTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cleanupKindTerms = try container.decodeIfPresent([String: CleanupKindTermMemory].self, forKey: .cleanupKindTerms) ?? [:]
        rawReadingLaneTerms = try container.decodeIfPresent([String: RawReadingLaneTermMemory].self, forKey: .rawReadingLaneTerms) ?? [:]
        metadataTerms = try container.decodeIfPresent([String: MetadataTermMemory].self, forKey: .metadataTerms) ?? [:]
        mangaBakaSeries = try container.decodeIfPresent([String: MangaBakaSeriesMemory].self, forKey: .mangaBakaSeries) ?? [:]
        pdfTriageTerms = try container.decodeIfPresent([String: PDFTriageTermMemory].self, forKey: .pdfTriageTerms) ?? [:]
    }
}

private struct TrainingEvent: Decodable {
    var kind: String
    var domain: String
    var provider: String?
    var confidenceScore: Double?
    var featureSummary: [String: String]?
}

private final class TrainingBuilder {
    private let anonymizeTrainingText: Bool
    private(set) var examples: [TrainingExample] = []

    init(anonymizeTrainingText: Bool = false) {
        self.anonymizeTrainingText = anonymizeTrainingText
    }

    func add(_ text: String, label: String, source: String, count: Int = 1) {
        let sourceText = anonymizeTrainingText ? anonymousFeatureText(from: text) : text
        let cleanedText = sourceText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty,
              !label.isEmpty,
              isAllowedTrainingLabel(label) else { return }

        let cappedCount = max(1, min(count, 8))
        for _ in 0..<cappedCount {
            examples.append(TrainingExample(text: cleanedText, label: label, source: source))
        }
    }

    func writeCSV(to url: URL) throws {
        try writeTrainingCSV(examples, to: url)
    }

    func balanceLabels(prefix: String, maximumTarget: Int) {
        let grouped = Dictionary(grouping: examples.filter { $0.label.hasPrefix(prefix) }, by: \.label)
        guard let largest = grouped.values.map(\.count).max(), largest > 0 else { return }
        let target = min(largest, maximumTarget)

        for (_, labelExamples) in grouped where labelExamples.count < target {
            let needed = target - labelExamples.count
            for index in 0..<needed {
                let example = labelExamples[index % labelExamples.count]
                examples.append(TrainingExample(text: example.text, label: example.label, source: example.source + "-balance"))
            }
        }
    }

}

private func writeTrainingCSV(_ examples: [TrainingExample], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var lines = ["text,label,source"]
    lines.append(contentsOf: examples.map { example in
        [example.text, example.label, example.source].map(csvEscaped).joined(separator: ",")
    })
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func addExtraTrainingExamples(from urls: [URL], to builder: TrainingBuilder, maxRowsPerLabel: Int) throws {
    var acceptedCounts: [String: Int] = [:]
    for url in urls {
        let examples = try loadExtraTrainingExamples(from: url)
        var accepted = 0
        for example in examples {
            let currentCount = acceptedCounts[example.label, default: 0]
            if maxRowsPerLabel > 0, currentCount >= maxRowsPerLabel {
                continue
            }
            builder.add(example.text, label: example.label, source: example.source)
            acceptedCounts[example.label, default: 0] += 1
            accepted += 1
        }
        print("Loaded extra training CSV: \(url.path(percentEncoded: false)) (\(accepted)/\(examples.count) row(s) accepted)")
    }
}

private func loadExtraTrainingExamples(from url: URL) throws -> [TrainingExample] {
    let reader = try TrainingCSVLineReader(url: url)
    defer { try? reader.close() }

    guard let headerLine = try reader.nextLine() else { return [] }
    let header = parseCSVLine(headerLine).map { $0.lowercased() }
    guard let textIndex = header.firstIndex(of: "text"),
          let labelIndex = header.firstIndex(of: "label") else {
        return []
    }
    let sourceIndex = header.firstIndex(of: "source")
    var examples: [TrainingExample] = []

    while let line = try reader.nextLine() {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let fields = parseCSVLine(line)
        guard fields.indices.contains(textIndex),
              fields.indices.contains(labelIndex) else { continue }
        let source = sourceIndex.flatMap { fields.indices.contains($0) ? fields[$0] : nil }
        examples.append(TrainingExample(
            text: fields[textIndex],
            label: fields[labelIndex],
            source: source ?? "extra-csv"
        ))
    }

    return examples
}

private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var isQuoted = false
    var index = line.startIndex

    while index < line.endIndex {
        let character = line[index]
        if character == "\"" {
            let next = line.index(after: index)
            if isQuoted, next < line.endIndex, line[next] == "\"" {
                current.append("\"")
                index = line.index(after: next)
                continue
            }
            isQuoted.toggle()
        } else if character == ",", !isQuoted {
            fields.append(current)
            current.removeAll(keepingCapacity: true)
        } else {
            current.append(character)
        }
        index = line.index(after: index)
    }

    fields.append(current)
    return fields
}

private final class TrainingCSVLineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var reachedEOF = false
    private let newline = Data([0x0A])

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
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
        try handle.close()
    }
}

private func csvEscaped(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private enum TrainerError: LocalizedError {
    case notEnoughLabels([String: Int])

    var errorDescription: String? {
        switch self {
        case .notEnoughLabels(let counts):
            return "Need at least two labels with examples before Create ML can train. Current labels: \(counts)"
        }
    }
}

private let allowedTrainingLabels: Set<String> = [
    "inspect.localOnly",
    "inspect.sidecarCoverage",
    "inspect.duplicates",
    "inspect.epubPackages",
    "task.rawCleanup",
    "task.protectedRoot",
    "task.move",
    "task.folderRename",
    "task.fileRename",
    "task.duplicateReview",
    "task.providerCall",
    "task.jsonSidecar",
    "task.epubRepair",
    "cleanup.document",
    "cleanup.image",
    "cleanup.audio",
    "cleanup.archive",
    "cleanup.watching",
    "cleanup.reading",
    "cleanup.other",
    "reading.book",
    "reading.novel",
    "reading.lightNovel",
    "reading.manga",
    "reading.manhwa",
    "reading.manhua",
    "reading.oel",
    "reading.comic",
    "raw.documents.pdf",
    "raw.documents.text",
    "raw.documents.word",
    "raw.documents.spreadsheet",
    "raw.documents.presentation",
    "raw.documents.json",
    "raw.documents.xml",
    "raw.documents.web",
    "raw.images.jpeg",
    "raw.images.png",
    "raw.images.webp",
    "raw.images.gif",
    "raw.images.heic",
    "raw.images.svg",
    "raw.images.tiff",
    "raw.images.bmp",
    "raw.audio.mp3",
    "raw.audio.aac",
    "raw.audio.flac",
    "raw.audio.wav",
    "raw.audio.ogg",
    "raw.archives.zip",
    "raw.archives.rar",
    "raw.archives.sevenZip",
    "raw.archives.tar",
    "raw.books.epub",
    "raw.books.comicArchive",
    "raw.books.pdf",
    "raw.books.djvu",
    "raw.video.mkv",
    "raw.video.mp4",
    "raw.video.mov",
    "raw.video.avi",
    "raw.video.webm",
    "raw.video.subtitle",
    "epub.repair.package",
    "epub.repair.appleBooks",
    "epub.repair.metadata",
    "epub.repair.cover",
    "epub.repair.fixedLayout",
    "epub.repair.optimize",
    "sidecar.comicInfo.create",
    "sidecar.comicInfo.refresh",
    "sidecar.animeInfo.create",
    "sidecar.animeInfo.refresh",
    "sidecar.json.read",
    "sidecar.json.write",
    "provider.callReading",
    "provider.callWatching",
    "provider.keepLocal",
    "provider.matchStrong",
    "provider.matchAmbiguous",
    "pdf.document",
    "pdf.book",
    "metadata.choice",
    "metadata.identity",
    "metadata.detail",
    "metadata.refresh",
    "metadata.watching",
    "provider.local",
    "provider.mangabaka",
    "provider.ranobedb",
    "provider.openLibrary",
    "provider.tmdb",
    "provider.tvdb",
    "provider.imdb",
    "provider.anilist",
    "provider.tvmaze",
    "provider.wikidata",
    "metadata.use",
    "metadata.keep"
]

private let allowedTrainingLabelPrefixes = [
    "shelf.",
    "providerShape.",
    "titleAlias.",
    "mediaType.",
    "tagRole.",
    "description.",
    "workFamily.",
    "manager."
]

private func isAllowedTrainingLabel(_ label: String) -> Bool {
    allowedTrainingLabels.contains(label)
        || allowedTrainingLabelPrefixes.contains { label.hasPrefix($0) }
}

private let bundledModelSuite: [ModelSuiteSpec] = [
    ModelSuiteSpec(
        modelName: "SableLibraryDecisionClassifier",
        labelPrefixes: ["task.", "cleanup.", "reading.", "pdf.", "provider.", "metadata."],
        extraLabels: [
            "inspect.localOnly",
            "inspect.sidecarCoverage",
            "inspect.duplicates",
            "inspect.epubPackages",
            "epub.repair.package",
            "epub.repair.appleBooks",
            "sidecar.comicInfo.create",
            "sidecar.comicInfo.refresh",
            "sidecar.animeInfo.create",
            "sidecar.animeInfo.refresh"
        ],
        description: "Coordinator model that gives broad review hints after the stage specialists vote."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryInspectionClassifier",
        labelPrefixes: ["inspect."],
        extraLabels: ["task.protectedRoot", "task.rawCleanup", "task.jsonSidecar"],
        description: "Inspection specialist for local folder walks, sidecar coverage, duplicate pressure, and repair candidates."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryRawCleanupClassifier",
        labelPrefixes: ["cleanup.", "raw.", "pdf."],
        extraLabels: ["task.rawCleanup", "task.protectedRoot", "task.move"],
        description: "Raw cleanup specialist for loose files, typed drawers, project-folder protection, PDF triage, and broad cleanup buckets."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryReadingClassifier",
        labelPrefixes: ["reading.", "raw.books.", "pdf."],
        extraLabels: ["provider.openLibrary", "provider.ranobedb", "provider.mangabaka"],
        description: "Reading specialist for prose books, light novels, manga, manhwa, manhua, OEL, comics, EPUBs, PDFs, and comic archives."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryProviderClassifier",
        labelPrefixes: ["provider.", "providerShape."],
        extraLabels: ["task.providerCall", "provider.callReading", "provider.callWatching"],
        description: "Provider specialist for local-vs-network choices and MangaBaka, RanobeDB, Open Library, and watching-provider evidence."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryTitleAliasRoleClassifier",
        labelPrefixes: ["titleAlias."],
        description: "Title and alias specialist for primary titles, alternate titles, romanized titles, native titles, and provider title variants."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryMediaTypeClassifier",
        labelPrefixes: ["mediaType.", "reading."],
        description: "Media-type specialist for manga, manhwa, manhua, OEL, comics, prose books, novels, and light novels."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryTagRoleClassifier",
        labelPrefixes: ["tagRole."],
        description: "Tag-role specialist for genres, settings, narrative engines, themes, relationships, demographics, form noise, bibliographic relationships, status, and advisories."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryDescriptionAboutnessClassifier",
        labelPrefixes: ["description."],
        description: "Description specialist for story-aboutness clues, thin descriptions, and shelf-bearing description evidence."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryWorkFamilyRelationshipClassifier",
        labelPrefixes: ["workFamily."],
        description: "Work-family specialist for provider series identity, aliases, form-specific versions, adaptations, and related works."
    ),
    ModelSuiteSpec(
        modelName: "SableLibrarySidecarClassifier",
        labelPrefixes: ["sidecar.", "metadata.", "workFamily."],
        extraLabels: ["task.jsonSidecar", "provider.keepLocal", "provider.matchStrong", "provider.matchAmbiguous"],
        description: "Sidecar specialist for ComicInfo, AnimeInfo, JSON reads/writes, metadata cleanup, and provider match strength."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryShelfClassifier",
        labelPrefixes: ["shelf.", "description.shelf."],
        description: "SSS shelving specialist for aboutness-first main shelves and sub-shelves."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryEvidenceMeetingClassifier",
        labelPrefixes: ["manager."],
        description: "Manager specialist for confidence, review state, competing shelves, missing evidence, and whether a lesson should train or stay reviewable."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryEPUBRepairClassifier",
        labelPrefixes: ["epub."],
        extraLabels: ["task.epubRepair", "raw.books.epub", "provider.openLibrary", "provider.ranobedb"],
        description: "EPUB repair specialist for package repair, Apple Books compatibility, cover metadata, fixed layout, and import metadata."
    ),
    ModelSuiteSpec(
        modelName: "SableLibraryNamingMoveClassifier",
        labelPrefixes: ["task.", "cleanup.", "reading."],
        extraLabels: ["pdf.document", "pdf.book"],
        description: "Naming and move specialist for folder grouping, file renames, duplicate review, and final-path confidence."
    )
]

private let bundledWordTaggerSuite: [WordTaggerSpec] = [
    WordTaggerSpec(
        modelName: "SableLibraryReadingNameTagger",
        description: "Reading filename tagger for title, year, volume, chapter, provider-noise, edition, and extension spans.",
        examples: [
            wordTags(["Series", "Title", "(", "2022", ")", "-", "Vol", "01", ".", "epub"],
                     ["TITLE", "TITLE", "OTHER", "YEAR", "OTHER", "OTHER", "VOLUME_MARKER", "VOLUME_NUMBER", "OTHER", "EXTENSION"]),
            wordTags(["Series", "Title", "(", "2022", ")", "-", "Vol", "OL", "01", ".", "epub"],
                     ["TITLE", "TITLE", "OTHER", "YEAR", "OTHER", "OTHER", "VOLUME_MARKER", "PROVIDER_NOISE", "VOLUME_NUMBER", "OTHER", "EXTENSION"]),
            wordTags(["Novel", "Name", "-", "Chapter", "12", ".", "epub"],
                     ["TITLE", "TITLE", "OTHER", "CHAPTER_MARKER", "CHAPTER_NUMBER", "OTHER", "EXTENSION"]),
            wordTags(["Book", "Title", "Author", "Name", "(", "Anniversary", "Edition", ")", ".", "pdf"],
                     ["TITLE", "TITLE", "AUTHOR", "AUTHOR", "OTHER", "EDITION", "EDITION", "OTHER", "OTHER", "EXTENSION"]),
            wordTags(["Comic", "Series", "-", "Issue", "004", ".", "cbz"],
                     ["TITLE", "TITLE", "OTHER", "ISSUE_MARKER", "ISSUE_NUMBER", "OTHER", "EXTENSION"])
        ]
    ),
    WordTaggerSpec(
        modelName: "SableLibraryVideoNameTagger",
        description: "Video filename tagger for title, season, episode, year, resolution, codec, source, language, subtitle, and extension spans.",
        examples: [
            wordTags(["Show", "Title", "-", "S01E03", "-", "1080p", "WEB-DL", "x265", ".", "mkv"],
                     ["TITLE", "TITLE", "OTHER", "EPISODE", "OTHER", "RESOLUTION", "SOURCE", "CODEC", "OTHER", "EXTENSION"]),
            wordTags(["Movie", "Title", "(", "2021", ")", "2160p", "BluRay", "HEVC", ".", "mp4"],
                     ["TITLE", "TITLE", "OTHER", "YEAR", "OTHER", "RESOLUTION", "SOURCE", "CODEC", "OTHER", "EXTENSION"]),
            wordTags(["Anime", "Name", "-", "Season", "02", "-", "Episode", "11", ".", "mkv"],
                     ["TITLE", "TITLE", "OTHER", "SEASON_MARKER", "SEASON_NUMBER", "OTHER", "EPISODE_MARKER", "EPISODE_NUMBER", "OTHER", "EXTENSION"]),
            wordTags(["Show", "Title", "-", "S01E03", ".", "en", ".", "forced", ".", "srt"],
                     ["TITLE", "TITLE", "OTHER", "EPISODE", "OTHER", "LANGUAGE", "OTHER", "SUBTITLE_MARKER", "OTHER", "EXTENSION"]),
            wordTags(["Documentary", "Title", "Part", "1", "HDTV", "720p", ".", "avi"],
                     ["TITLE", "TITLE", "PART_MARKER", "PART_NUMBER", "SOURCE", "RESOLUTION", "OTHER", "EXTENSION"])
        ]
    ),
    WordTaggerSpec(
        modelName: "SableLibraryDocumentNameTagger",
        description: "Document and PDF filename tagger for document type, title-ish spans, dates, edition/version clues, and extension spans.",
        examples: [
            wordTags(["Invoice", "2024", "-", "11", ".", "pdf"],
                     ["DOCUMENT_TYPE", "DATE", "OTHER", "DATE", "OTHER", "EXTENSION"]),
            wordTags(["Bank", "Statement", "2025", "-", "02", ".", "pdf"],
                     ["DOCUMENT_TYPE", "DOCUMENT_TYPE", "DATE", "OTHER", "DATE", "OTHER", "EXTENSION"]),
            wordTags(["Project", "Notes", "draft", "v2", ".", "md"],
                     ["TITLE", "DOCUMENT_TYPE", "EDITION", "EDITION", "OTHER", "EXTENSION"]),
            wordTags(["Config", "Export", ".", "xml"],
                     ["DOCUMENT_TYPE", "DOCUMENT_TYPE", "OTHER", "EXTENSION"]),
            wordTags(["Reading", "Guide", "Second", "Edition", ".", "pdf"],
                     ["TITLE", "DOCUMENT_TYPE", "EDITION", "EDITION", "OTHER", "EXTENSION"])
        ]
    )
]

private let bundledRecommenderSuite: [RecommenderSpec] = [
    RecommenderSpec(
        modelName: "SableLibraryReviewActionRecommender",
        description: "Review action recommender for check, skip, protect, treat-as, merge, rename, and provider-choice hints."
    ),
    RecommenderSpec(
        modelName: "SableLibraryProviderRankingRecommender",
        description: "Provider ranking recommender for Open Library, RanobeDB, manga/comic providers, and watching providers."
    ),
    RecommenderSpec(
        modelName: "SableLibraryFolderGroupingRecommender",
        description: "Folder grouping recommender for reading, watching, document, media, archive, and protected-project group hints."
    )
]

private func wordTags(_ tokens: [String], _ labels: [String], source: String = "curated-word-tag-seed") -> WordTaggerExample {
    precondition(tokens.count == labels.count, "Word tagger examples need one label per token.")
    return WordTaggerExample(tokens: tokens, labels: labels, source: source)
}

private func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--repo-root":
            if let value = arguments.first {
                arguments.removeFirst()
                options.repoRoot = URL(fileURLWithPath: value, isDirectory: true)
            }
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--output":
            if let value = arguments.first {
                arguments.removeFirst()
                options.outputURL = URL(fileURLWithPath: value)
            }
        case "--dataset":
            if let value = arguments.first {
                arguments.removeFirst()
                options.datasetURL = URL(fileURLWithPath: value)
            }
        case "--scan-root":
            if let value = arguments.first {
                arguments.removeFirst()
                options.scanRoots.append(URL(fileURLWithPath: value, isDirectory: true))
            }
        case "--extra-csv":
            if let value = arguments.first {
                arguments.removeFirst()
                options.extraTrainingCSVs.append(URL(fileURLWithPath: value))
            }
        case "--extra-csv-label-cap":
            if let value = arguments.first, let limit = Int(value) {
                arguments.removeFirst()
                options.maxExtraRowsPerLabel = max(0, limit)
            }
        case "--project-baseline":
            options.includeAppDefaults = false
            options.includeTrainingEvents = false
            options.includeWeakFilenameSeeds = false
            options.modelFlavor = "baseline"
            options.trainModelSuite = true
            options.outputURL = options.repoRoot
                .appendingPathComponent("Sable's Library/App/ML", isDirectory: true)
                .appendingPathComponent("SableLibraryDecisionClassifier.mlmodel")
            options.datasetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SableLibraryML", isDirectory: true)
                .appendingPathComponent("SableLibraryDecisionClassifierTraining.csv")
        case "--project-anonymous", "--project-personal-anonymous":
            options.anonymizeTrainingText = true
            options.modelFlavor = "anonymous-suite"
            options.trainModelSuite = true
            options.outputURL = options.repoRoot
                .appendingPathComponent("Sable's Library/App/ML", isDirectory: true)
                .appendingPathComponent("SableLibraryDecisionClassifier.mlmodel")
            options.datasetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SableLibraryML", isDirectory: true)
                .appendingPathComponent("SableLibraryDecisionClassifierTraining.anonymous.csv")
        case "--anonymous":
            options.anonymizeTrainingText = true
            options.modelFlavor = "anonymous-personal"
        case "--suite":
            options.trainModelSuite = true
        case "--only-model":
            if let value = arguments.first {
                arguments.removeFirst()
                options.selectedSuiteModels.insert(value)
                options.trainModelSuite = true
            }
        case "--no-app-defaults":
            options.includeAppDefaults = false
        case "--no-training-events":
            options.includeTrainingEvents = false
        case "--no-weak-filename-seeds":
            options.includeWeakFilenameSeeds = false
        case "--max-weak-filename-seeds":
            if let value = arguments.first, let limit = Int(value) {
                arguments.removeFirst()
                options.maxWeakFilenameSeeds = max(0, limit)
            }
        default:
            break
        }
    }
    return options
}

private func printUsage() {
    print(
        """
        Sable Library ML trainer

        Common commands:
          script/train_sable_library_ml.swift --project-anonymous
              Train the bundled project model from local Sable signals after converting titles,
              paths, and provider IDs into anonymous feature tokens.

          script/train_sable_library_ml.swift --project-baseline
              Regenerate the bundled project model from curated non-private seed examples only.

          script/train_sable_library_ml.swift
              Train a private personal model in the selected library reports folder.

        Useful options:
          --scan-root /path/to/folder       Add or override a folder to scan.
          --output /path/to/model.mlmodel   Choose the model output path.
          --dataset /path/to/training.csv   Keep a copy of the training CSV for inspection.
          --extra-csv /path/to/rows.csv     Add text,label,source lessons from provider dumps.
          --extra-csv-label-cap 1200        Cap accepted extra rows per label. Use 0 for no cap.
          --anonymous                       Anonymize training text for a private output model.
          --suite                           Train the coordinator plus specialist model suite.
          --only-model SableLibraryShelfClassifier
                                            Train only one suite model. Repeat for several.
          --no-weak-filename-seeds          Train only from Sable choices and curated seeds.
          --max-weak-filename-seeds 200     Lower the weak filename seed budget.
        """
    )
}

private func defaultReportDirectory() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let library = home.appendingPathComponent("Documents/Sable Library", isDirectory: true)
    if FileManager.default.fileExists(atPath: library.path(percentEncoded: false)) {
        return library.appendingPathComponent("_Sable's Library Reports", isDirectory: true)
    }
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("SableLibraryML", isDirectory: true)
}

private func defaultScanRoots() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
        home.appendingPathComponent("Documents/Sable Library", isDirectory: true)
    ]
    return candidates.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
}

private func loadAppLearningMemory() -> LearningMemory? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    let defaultsDomain = ProcessInfo.processInfo.environment[
        "SABLE_LIBRARY_DEFAULTS_DOMAIN"
    ] ?? "com.annearuki.Sables-Library"
    process.arguments = ["export", defaultsDomain, "-"]

    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    do {
        try process.run()
    } catch {
        return nil
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    guard
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
        let dictionary = plist as? [String: Any],
        let memoryData = dictionary["sableLibrary.learningMemory"] as? Data
    else {
        return nil
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(LearningMemory.self, from: memoryData)
}

private func addLearningMemoryExamples(_ memory: LearningMemory, to builder: TrainingBuilder) {
    for (token, memory) in memory.cleanupKindTerms {
        for (kind, count) in memory.kindCounts where count > 0 {
            builder.add("cleanup kind \(token) \(kind) file folder", label: "cleanup.\(kind)", source: "app-learning-memory", count: count)
        }
    }

    for (token, memory) in memory.rawReadingLaneTerms {
        for (lane, count) in memory.laneCounts where count > 0 {
            builder.add("raw reading lane \(token) \(lane) epub book volume", label: "reading.\(lane)", source: "app-learning-memory", count: count)
        }
    }

    for (token, memory) in memory.pdfTriageTerms {
        if memory.documentCount > 0 {
            builder.add("pdf document \(token) office paperwork reference", label: "pdf.document", source: "app-learning-memory", count: memory.documentCount)
        }
        if memory.bookCount > 0 {
            builder.add("pdf book \(token) reading library", label: "pdf.book", source: "app-learning-memory", count: memory.bookCount)
        }
    }

    for (term, memory) in memory.metadataTerms {
        if memory.usedCount > 0 {
            builder.add("metadata cleanup term used \(term)", label: "metadata.use", source: "app-learning-memory", count: memory.usedCount)
        }
        if memory.dismissedCount > 0 {
            builder.add("metadata cleanup term kept title \(term)", label: "metadata.keep", source: "app-learning-memory", count: memory.dismissedCount)
        }
    }

    for (seriesKey, memory) in memory.mangaBakaSeries {
        if memory.keptLocalCount > 0 {
            builder.add("provider local title \(seriesKey)", label: "provider.local", source: "app-learning-memory", count: memory.keptLocalCount)
        }
        let acceptedCount = memory.acceptedCandidateIDs.values.reduce(0, +)
        if acceptedCount > 0 {
            builder.add("provider mangabaka exact match \(seriesKey)", label: "provider.mangabaka", source: "app-learning-memory", count: acceptedCount)
        }
    }
}

private func addSeedExamples(to builder: TrainingBuilder) {
    let seeds: [(String, String)] = [
        ("a court of thorns and roses sarah j maas epub ordinary prose fantasy book", "reading.book"),
        ("the viscount who loved me bridgerton julia quinn epub romance prose", "reading.book"),
        ("the count of monte cristo alexandre dumas classic prose novel", "reading.book"),
        ("count of monte cristo original classic prose not manga not light novel keep out of provider gap", "reading.book"),
        ("count of monte cristo prose book no mangabaka no ranobedb no anilist no mal", "provider.keepLocal"),
        ("radio silence alice oseman contemporary prose novel", "reading.book"),
        ("game changer rachel reid sports romance prose book", "reading.book"),
        ("bridgerton romance prose julia quinn no manga light novel provider queue", "reading.book"),
        ("ordinary prose novel should not ask missing mangabaka ranobedb anilist mal", "provider.keepLocal"),
        ("jane eyre charlotte bronte classic novel epub", "reading.book"),
        ("pride and prejudice jane austen novel epub", "reading.book"),
        ("7th time loop villainess carefree life vol 01 light novel epub", "reading.lightNovel"),
        ("7th time loop villainess carefree life married worst enemy vol 01 epub", "reading.lightNovel"),
        ("a livid lady guide getting even grimoires vol 01 light novel ranobedb open library provider", "reading.lightNovel"),
        ("a livid lady guide getting even crushed homeland mighty grimoires vol 01 epub", "reading.lightNovel"),
        ("agents of the four seasons dance of spring vol 01 light novel", "reading.lightNovel"),
        ("agents of the four seasons dance of spring vol 01 epub", "reading.lightNovel"),
        ("villainess tyrant duke knight magic potion vol 02 light novel", "reading.lightNovel"),
        ("villainess tyrant duke knight magic potion vol 02 epub", "reading.lightNovel"),
        ("ascendance of a bookworm part volume light novel", "reading.lightNovel"),
        ("ascendance of a bookworm part one two three four five main light novel same ranobedb series", "provider.ranobedb"),
        ("ascendance of a bookworm fanbook separate from main parts ambiguous provider title", "provider.matchAmbiguous"),
        ("bookworm fanbook provider result must not overwrite mainline part title", "provider.keepLocal"),
        ("sugar apple fairy tale split manga baka entries ranobedb main series ask before broad merge", "provider.matchAmbiguous"),
        ("ranobedb main light novel identity beats split mangabaka book level entries", "provider.ranobedb"),
        ("accidentally in love witch knight love potion slipup vol 01 epub", "reading.lightNovel"),
        ("manga chapter tankobon cbz volume scan", "reading.manga"),
        ("one piece vol 01 manga cbz", "reading.manga"),
        ("solo leveling manhwa season webtoon", "reading.manhwa"),
        ("heaven official blessing manhua volume", "reading.manhua"),
        ("batman issue comic cbr", "reading.comic"),
        ("invoice tax school work pdf document", "pdf.document"),
        ("contract receipt bank statement pdf document", "pdf.document"),
        ("scanned book memoir pdf reading", "pdf.book"),
        ("artbook novel companion pdf reading", "pdf.book"),
        ("meeting notes docx pages spreadsheet", "cleanup.document"),
        ("photo screenshot cover jpg png heic image", "cleanup.image"),
        ("music soundtrack mp3 flac audio", "cleanup.audio"),
        ("zip rar archive backup compressed", "cleanup.archive"),
        ("episode s01e01 mkv mp4 anime show", "cleanup.watching"),
        ("anime tv season 01 episode 01 mkv fansub subtitles", "cleanup.watching"),
        ("tv show s02e04 webdl h264 mkv subtitles", "cleanup.watching"),
        ("movie 2160p hdr bluray x265 mkv video", "cleanup.watching"),
        ("movie 1080p bluray mp4 video", "cleanup.watching"),
        ("plex movie file tmdb imdb id video", "cleanup.watching"),
        ("subtitle srt ass vtt sidecar belongs with video", "cleanup.watching"),
        ("misc unknown loose file", "cleanup.other"),
        ("manual mangabaka id exact series match", "provider.mangabaka"),
        ("manual ranobedb id exact light novel series", "provider.ranobedb"),
        ("open library isbn author year ordinary book", "provider.openLibrary"),
        ("manual tmdb id exact movie anime tv match", "provider.tmdb"),
        ("manual tvdb id exact tv show season match", "provider.tvdb"),
        ("manual imdb id exact movie tv match", "provider.imdb"),
        ("manual anilist id exact anime match", "provider.anilist"),
        ("manual tvmaze id exact tv show match", "provider.tvmaze"),
        ("manual wikidata id exact watching metadata bridge", "provider.wikidata"),
        ("local title no provider keep folder name", "provider.local"),
        ("inspect library local folder walk no network file type counts sidecar coverage", "inspect.localOnly"),
        ("inspect library duplicate groups conflicting copies review before apply", "inspect.duplicates"),
        ("inspect missing comicinfo animeinfo sidecar coverage json read local", "inspect.sidecarCoverage"),
        ("inspect expanded epub package repair candidates mimetype container opf", "inspect.epubPackages"),
        ("raw cleanup loose files sort into typed drawers keep project roots protected", "task.rawCleanup"),
        ("protect xcode project swift package git repository app game unity unreal folder", "task.protectedRoot"),
        ("move raw file into final folder reversible no delete receipt", "task.move"),
        ("rename folder canonical series folder sidecar title year media type", "task.folderRename"),
        ("rename file canonical volume chapter episode title extension", "task.fileRename"),
        ("duplicate review choose keeper move aside merge not duplicate", "task.duplicateReview"),
        ("provider call checked row network visible rate limited metadata lookup", "task.providerCall"),
        ("json sidecar comicinfo animeinfo read write local snapshot", "task.jsonSidecar"),
        ("epub repair apple books package validation cover metadata fixed layout", "task.epubRepair"),
        ("documents pdf drawer paperwork form statement manual", "raw.documents.pdf"),
        ("documents text drawer txt markdown md notes receipt", "raw.documents.text"),
        ("documents word drawer doc docx pages rtf", "raw.documents.word"),
        ("documents spreadsheet drawer csv xls xlsx numbers", "raw.documents.spreadsheet"),
        ("documents presentation drawer ppt pptx key keynote", "raw.documents.presentation"),
        ("documents json drawer comicinfo animeinfo config sidecar", "raw.documents.json"),
        ("documents xml drawer opf ncx plist metadata", "raw.documents.xml"),
        ("documents web drawer html htm css page", "raw.documents.web"),
        ("images jpeg drawer jpg jpeg photo cover scan", "raw.images.jpeg"),
        ("images png drawer png screenshot cover transparent", "raw.images.png"),
        ("images webp drawer webp cover image", "raw.images.webp"),
        ("images gif drawer gif animated image", "raw.images.gif"),
        ("images heic drawer heic heif photo", "raw.images.heic"),
        ("images svg drawer svg vector image", "raw.images.svg"),
        ("images tiff drawer tif tiff scan", "raw.images.tiff"),
        ("images bmp drawer bmp bitmap image", "raw.images.bmp"),
        ("audio mp3 drawer music audiobook podcast", "raw.audio.mp3"),
        ("audio aac m4a drawer music voice recording", "raw.audio.aac"),
        ("audio flac drawer lossless album", "raw.audio.flac"),
        ("audio wav drawer wave recording", "raw.audio.wav"),
        ("audio ogg opus drawer audio", "raw.audio.ogg"),
        ("archive zip drawer compressed backup export", "raw.archives.zip"),
        ("archive rar drawer compressed backup", "raw.archives.rar"),
        ("archive seven zip drawer 7z compressed", "raw.archives.sevenZip"),
        ("archive tar gz bz2 xz drawer unix archive", "raw.archives.tar"),
        ("books epub drawer ordinary ebook prose", "raw.books.epub"),
        ("books comic archive drawer cbz cbr cb7 cbt manga comic", "raw.books.comicArchive"),
        ("books pdf drawer reading pdf book comic manual", "raw.books.pdf"),
        ("books djvu drawer scanned book", "raw.books.djvu"),
        ("video mkv drawer movie episode subtitles", "raw.video.mkv"),
        ("video mp4 m4v drawer movie episode", "raw.video.mp4"),
        ("video mov drawer quicktime video", "raw.video.mov"),
        ("video avi drawer old video", "raw.video.avi"),
        ("video webm drawer web video", "raw.video.webm"),
        ("video subtitle drawer srt ass ssa vtt sidecar", "raw.video.subtitle"),
        ("epub package repair expanded epub folder mimetype meta inf container opf", "epub.repair.package"),
        ("apple books compatibility repair root itunesmetadata cover-image uuid validation", "epub.repair.appleBooks"),
        ("epub import metadata write title creator publisher isbn openlibrary ranobedb sidecar", "epub.repair.metadata"),
        ("epub cover metadata missing cover-image epub2 cover meta", "epub.repair.cover"),
        ("epub fixed layout page image viewport page box mismatch", "epub.repair.fixedLayout"),
        ("epub optimize page image lossy jpeg downscale fixed layout", "epub.repair.optimize"),
        ("comicinfo create json reading sidecar local title provider evidence", "sidecar.comicInfo.create"),
        ("comicinfo refresh json stale provider snapshot file changed", "sidecar.comicInfo.refresh"),
        ("animeinfo create json watching sidecar local title episode video", "sidecar.animeInfo.create"),
        ("animeinfo refresh json stale provider snapshot file changed", "sidecar.animeInfo.refresh"),
        ("sidecar json read comicinfo animeinfo local metadata safe parse", "sidecar.json.read"),
        ("sidecar json write comicinfo animeinfo local receipt reversible", "sidecar.json.write"),
        ("provider reading call mangabaka ranobedb openlibrary checked row", "provider.callReading"),
        ("provider watching call anilist tvmaze wikidata tmdb tvdb imdb checked row", "provider.callWatching"),
        ("provider keep local title no network no confident match", "provider.keepLocal"),
        ("provider strong match exact id isbn title year bridge", "provider.matchStrong"),
        ("provider ambiguous match fuzzy title collision weak evidence review", "provider.matchAmbiguous"),
        ("metadata choice checkpoint needs provider match use local manual id review", "metadata.choice"),
        ("metadata identity checkpoint create comicinfo first provider identity sidecar", "metadata.identity"),
        ("metadata detail checkpoint ranobedb books isbn volume details after identity", "metadata.detail"),
        ("metadata refresh checkpoint stale sidecar provider snapshot safe update", "metadata.refresh"),
        ("metadata watching checkpoint animeinfo video provider bridge tv anime movie", "metadata.watching"),
        ("company ceosable shared evidence map role clarity staged handoff privacy first", "inspect.localOnly"),
        ("company intakedesk light inventory paths file types sidecars safety markers", "inspect.localOnly"),
        ("company rawintake root only loose files typed drawers balanced cleanup", "task.rawCleanup"),
        ("company rawintake root only protect project internals source repositories", "task.protectedRoot"),
        ("company safetyoffice hard guards veto project app game package git collision", "task.protectedRoot"),
        ("company readinglibrary separates prose books light novels manga manhwa provider context", "cleanup.reading"),
        ("company watchdesk video anime movie tv episode provider context", "cleanup.watching"),
        ("company sidecarrelations comicinfo animeinfo local sidecars identity graph", "task.jsonSidecar"),
        ("company epubclinic apple books repair cover metadata fixed layout validation", "task.epubRepair"),
        ("company naminglogistics folder rename file rename canonical path receipt", "task.folderRename"),
        ("company duplicatesafety collision duplicate merge choice move aside review", "task.duplicateReview"),
        ("company provider boundary weak match skip keep local review", "provider.keepLocal"),
        ("training material sample first bulk raw review check safe after corrections", "task.rawCleanup"),
        ("training material leave uncertain rows unchecked useful safety signal", "task.protectedRoot"),
        ("training material manual provider id correction provider choice", "provider.matchStrong"),
        ("training material weak provider match keep local skip guessed metadata", "provider.keepLocal"),
        ("training material wrong type correction treat as document book light novel video", "cleanup.other")
    ]

    for seed in seeds {
        builder.add(seed.0, label: seed.1, source: "curated-seed", count: 3)
    }
}

private func addTrainingEventExamples(from roots: [URL], to builder: TrainingBuilder) {
    for reportURL in trainingEventFiles(under: roots) {
        guard let lines = try? String(contentsOf: reportURL, encoding: .utf8).split(separator: "\n") else {
            continue
        }
        for line in lines {
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONDecoder().decode(TrainingEvent.self, from: data) else {
                continue
            }
            for label in labels(for: event) {
                builder.add(text(for: event), label: label, source: "training-event")
            }
        }
    }
}

private func trainingEventFiles(under roots: [URL]) -> [URL] {
    let fileManager = FileManager.default
    var seen = Set<String>()
    var files: [URL] = []
    for root in roots {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { continue }

        for case let url as URL in enumerator where url.lastPathComponent == "_sable_ml_training_events.jsonl" {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            if seen.insert(path).inserted {
                files.append(url)
            }
        }
    }
    return files
}

private func labels(for event: TrainingEvent) -> [String] {
    let summary = event.featureSummary ?? [:]
    let reviewTags = summary["review_tags"] ?? ""
    let operation = summary["operation"] ?? ""
    let destinationRoot = summary["destination_root"] ?? ""
    var labels: [String] = []

    func append(_ label: String?) {
        guard let label, isAllowedTrainingLabel(label), !labels.contains(label) else { return }
        labels.append(label)
    }

    if let lane = firstTaggedValue(in: reviewTags, prefix: "raw-reading-") {
        append("reading.\(lane)")
    }
    if let kind = firstTaggedValue(in: reviewTags, prefix: "cleanup-kind-") {
        append("cleanup.\(kind)")
    }
    if reviewTags.contains("pdf-triage") {
        append(destinationRoot == "Documents" ? "pdf.document" : "pdf.book")
    }
    if reviewTags.contains("training-material") || reviewTags.contains("bulk-raw-review") {
        append("task.rawCleanup")
    }
    if reviewTags.contains("metadata-checkpoint-choice") || reviewTags.contains("needs-provider-choice") {
        append("metadata.choice")
        append("provider.matchAmbiguous")
    }
    if reviewTags.contains("metadata-checkpoint-identity") || reviewTags.contains("metadata-pass-identity") {
        append("metadata.identity")
    }
    if reviewTags.contains("metadata-checkpoint-detail") || reviewTags.contains("metadata-pass-detail") {
        append("metadata.detail")
    }
    if reviewTags.contains("metadata-checkpoint-refresh") || reviewTags.contains("metadata-pass-refresh") {
        append("metadata.refresh")
    }
    if reviewTags.contains("metadata-checkpoint-watching") || reviewTags.contains("metadata-provider-watching") {
        append("metadata.watching")
        append("provider.callWatching")
    }
    if reviewTags.contains("manual-provider-match") {
        append("provider.matchStrong")
    }
    if event.kind == "manualIDEntry", let provider = event.provider {
        append("provider.\(provider)")
        append(event.domain == "watching" ? "provider.callWatching" : "provider.callReading")
    }

    if let ext = summary["source_extension"], !ext.isEmpty {
        if let rawVideo = rawVideoLabel(for: ext) {
            append(rawVideo)
        }
        if ["srt", "ass", "ssa", "vtt", "sub"].contains(ext) {
            append("raw.video.subtitle")
        }
        if let rawImage = rawImageLabel(for: ext) {
            append(rawImage)
        }
        if let rawAudio = rawAudioLabel(for: ext) {
            append(rawAudio)
        }
        if let rawArchive = rawArchiveLabel(for: ext) {
            append(rawArchive)
        }
        if let rawDocument = rawDocumentLabel(for: ext) {
            append(rawDocument)
        }
        if ["epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba"].contains(ext) {
            append("raw.books.epub")
        }
        if ["cbz", "cbr", "cb7", "cbt"].contains(ext) {
            append("raw.books.comicArchive")
        }
        if ext == "pdf" {
            append(destinationRoot == "Books" ? "raw.books.pdf" : "raw.documents.pdf")
        }
        if ext == "djvu" {
            append("raw.books.djvu")
        }
    }

    switch operation {
    case "repairEpubPackage":
        append("task.epubRepair")
        append("epub.repair.package")
    case "repairAppleBooksCompatibility":
        append("task.epubRepair")
        append("epub.repair.appleBooks")
        if reviewTags.contains("epub-import-metadata") {
            append("epub.repair.metadata")
        }
        if reviewTags.contains("epub-cover") {
            append("epub.repair.cover")
        }
        if reviewTags.contains("epub-fixed-layout") {
            append("epub.repair.fixedLayout")
        }
        if reviewTags.contains("epub-optimize") {
            append("epub.repair.optimize")
        }
    case "createComicInfo":
        append("task.jsonSidecar")
        append("sidecar.comicInfo.create")
        append("sidecar.json.write")
    case "refreshComicInfo":
        append("task.jsonSidecar")
        append("sidecar.comicInfo.refresh")
        append("sidecar.json.read")
        append("sidecar.json.write")
    case "createAnimeInfo":
        append("task.jsonSidecar")
        append("sidecar.animeInfo.create")
        append("sidecar.json.write")
    case "refreshAnimeInfo":
        append("task.jsonSidecar")
        append("sidecar.animeInfo.refresh")
        append("sidecar.json.read")
        append("sidecar.json.write")
    case "sortIntoFolder":
        append("task.move")
        append("task.rawCleanup")
    case "renameFolder":
        append("task.folderRename")
    case "renameFile", "cleanRawName":
        append("task.fileRename")
    case "duplicateDecision":
        append("task.duplicateReview")
    default:
        break
    }

    if let provider = event.provider {
        append("provider.\(provider)")
        switch provider {
        case "mangabaka", "ranobedb", "openLibrary":
            append("provider.callReading")
        case "anilist", "tvmaze", "wikidata", "tmdb", "tvdb", "imdb":
            append("provider.callWatching")
        case "local":
            append("provider.keepLocal")
        default:
            break
        }
    }

    if !destinationRoot.isEmpty {
        switch destinationRoot {
        case "Books": append("cleanup.reading")
        case "Videos": append("cleanup.watching")
        case "Documents": append("cleanup.document")
        case "Images": append("cleanup.image")
        case "Audio": append("cleanup.audio")
        case "Archives": append("cleanup.archive")
        default: append("cleanup.other")
        }
    }

    if event.kind == "finalSuccessfulSidecar" {
        append("provider.matchStrong")
    }
    if event.kind == "skippedAmbiguousMatch" || event.kind == "providerDisagreement" {
        append("provider.matchAmbiguous")
    }

    return labels
}

private func text(for event: TrainingEvent) -> String {
    let summary = event.featureSummary ?? [:]
    return ([
        event.kind,
        event.domain,
        event.provider ?? "",
        summary["stage"] ?? "",
        summary["operation"] ?? "",
        summary["safety"] ?? "",
        summary["destination_root"] ?? "",
        summary["review_tags"] ?? "",
        summary["source"] ?? ""
    ] + summary.values).joined(separator: " ")
}

private func firstTaggedValue(in text: String, prefix: String) -> String? {
    text.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { $0.hasPrefix(prefix) })
        .map { String($0.dropFirst(prefix.count)) }
}

private func addWeakFilenameExamples(from roots: [URL], to builder: TrainingBuilder, maxRows: Int) {
    guard maxRows > 0 else { return }
    let fileManager = FileManager.default
    var seen = Set<String>()
    var added = 0
    let perRootLimit = max(1, Int(ceil(Double(maxRows) / Double(max(roots.count, 1)))))

    for root in roots where added < maxRows {
        var rootAdded = 0
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { continue }

        for case let url as URL in enumerator {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            guard added < maxRows,
                  rootAdded < perRootLimit,
                  seen.insert(path).inserted else {
                continue
            }
            let labels = weakLabels(for: url)
            guard !labels.isEmpty else { continue }
            for label in labels {
                builder.add(weakFilenameTrainingText(for: url), label: label, source: "weak-filename-seed")
            }
            added += 1
            rootAdded += 1
        }
    }
}

private func weakFilenameTrainingText(for url: URL) -> String {
    [
        url.deletingPathExtension().lastPathComponent,
        "extension",
        url.pathExtension.lowercased(),
        "parent",
        url.deletingLastPathComponent().lastPathComponent
    ].joined(separator: " ")
}

private func weakLabels(for url: URL) -> [String] {
    let ext = url.pathExtension.lowercased()
    let name = normalized(url.deletingPathExtension().lastPathComponent)
    var labels: [String] = []

    func append(_ label: String?) {
        guard let label, isAllowedTrainingLabel(label), !labels.contains(label) else { return }
        labels.append(label)
    }

    if ["epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba"].contains(ext) {
        append("cleanup.reading")
        append("raw.books.epub")
        if name.contains(" manhwa ") { append("reading.manhwa") }
        else if name.contains(" manhua ") { append("reading.manhua") }
        else if name.contains(" manga ") { append("reading.manga") }
        else if name.contains(" comic ") { append("reading.comic") }
        if name.range(of: #"(^| )vol(ume)? [0-9]+"#, options: .regularExpression) != nil {
            append("reading.lightNovel")
        } else if !labels.contains(where: { $0.hasPrefix("reading.") }) {
            append("reading.book")
        }
        return labels
    }
    if ["cbz", "cbr", "cb7", "cbt"].contains(ext) {
        return ["cleanup.reading", "raw.books.comicArchive", "reading.manga"]
    }
    if ext == "pdf" {
        if name.contains(" novel ") || name.contains(" book ") || name.contains(" manga ") {
            return ["cleanup.reading", "raw.books.pdf", "pdf.book"]
        }
        return ["cleanup.document", "raw.documents.pdf", "pdf.document"]
    }
    if let rawVideo = rawVideoLabel(for: ext) {
        return ["cleanup.watching", rawVideo]
    }
    if ["srt", "ass", "ssa", "vtt", "sub"].contains(ext) {
        return ["cleanup.watching", "raw.video.subtitle"]
    }
    if let rawImage = rawImageLabel(for: ext) {
        return ["cleanup.image", rawImage]
    }
    if let rawAudio = rawAudioLabel(for: ext) {
        return ["cleanup.audio", rawAudio]
    }
    if let rawArchive = rawArchiveLabel(for: ext) {
        return ["cleanup.archive", rawArchive]
    }
    if let rawDocument = rawDocumentLabel(for: ext) {
        return ["cleanup.document", rawDocument]
    }
    if ext == "djvu" {
        return ["cleanup.reading", "raw.books.djvu"]
    }
    return []
}

private func rawVideoLabel(for ext: String) -> String? {
    switch ext {
    case "mkv": return "raw.video.mkv"
    case "mp4", "m4v": return "raw.video.mp4"
    case "mov": return "raw.video.mov"
    case "avi", "wmv": return "raw.video.avi"
    case "webm": return "raw.video.webm"
    default:
        return ["ts", "m2ts"].contains(ext) ? "raw.video.mkv" : nil
    }
}

private func rawImageLabel(for ext: String) -> String? {
    switch ext {
    case "jpg", "jpeg": return "raw.images.jpeg"
    case "png": return "raw.images.png"
    case "webp": return "raw.images.webp"
    case "gif": return "raw.images.gif"
    case "heic", "heif": return "raw.images.heic"
    case "svg": return "raw.images.svg"
    case "tif", "tiff": return "raw.images.tiff"
    case "bmp": return "raw.images.bmp"
    default: return nil
    }
}

private func rawAudioLabel(for ext: String) -> String? {
    switch ext {
    case "mp3": return "raw.audio.mp3"
    case "m4a", "aac": return "raw.audio.aac"
    case "flac": return "raw.audio.flac"
    case "wav", "aiff": return "raw.audio.wav"
    case "ogg", "opus": return "raw.audio.ogg"
    default: return nil
    }
}

private func rawArchiveLabel(for ext: String) -> String? {
    switch ext {
    case "zip": return "raw.archives.zip"
    case "rar": return "raw.archives.rar"
    case "7z": return "raw.archives.sevenZip"
    case "tar", "gz", "bz2", "xz": return "raw.archives.tar"
    default: return nil
    }
}

private func rawDocumentLabel(for ext: String) -> String? {
    switch ext {
    case "txt", "md", "markdown": return "raw.documents.text"
    case "rtf", "doc", "docx", "pages": return "raw.documents.word"
    case "csv", "xls", "xlsx", "numbers": return "raw.documents.spreadsheet"
    case "ppt", "pptx", "key": return "raw.documents.presentation"
    case "json": return "raw.documents.json"
    case "xml", "plist", "opf", "ncx": return "raw.documents.xml"
    case "html", "htm", "css": return "raw.documents.web"
    default: return nil
    }
}

private func normalized(_ value: String) -> String {
    " " + value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines) + " "
}

private func anonymousFeatureText(from text: String) -> String {
    let normalizedText = normalized(text)
    let tokens = normalizedText
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)

    var features: [String] = ["privacy_anonymized"]
    let wordTokens = tokens.filter { !$0.allSatisfy(\.isNumber) }
    features.append("word_count_\(bucket(wordTokens.count, thresholds: [2, 5, 9, 14]))")

    let numericTokens = tokens.filter { $0.allSatisfy(\.isNumber) }
    if !numericTokens.isEmpty {
        features.append("has_number")
        features.append("number_count_\(bucket(numericTokens.count, thresholds: [1, 2, 4, 8]))")
    }
    if numericTokens.contains(where: { $0.count == 4 }) {
        features.append("has_year_like_number")
    }
    if tokens.contains("vol") || tokens.contains("volume") || text.range(of: #"(?i)\bvol(?:ume)?\.?\s*\d+"#, options: .regularExpression) != nil {
        features.append("has_volume_marker")
    }
    if text.range(of: #"(?i)\bchapter\s*\d+|\bch\.?\s*\d+"#, options: .regularExpression) != nil {
        features.append("has_chapter_marker")
    }
    if text.range(of: #"(?i)\bs\d{1,2}e\d{1,3}\b|\bseason\s*\d+\b|\bepisode\s*\d+\b"#, options: .regularExpression) != nil {
        features.append("has_episode_marker")
    }
    if text.range(of: #"(?i)\b(?:480|720|1080|2160|4320)p\b|\b4k\b|\b8k\b"#, options: .regularExpression) != nil {
        features.append("has_video_resolution")
    }
    if text.range(of: #"(?i)\b(?:x264|h264|avc|x265|h265|hevc|av1|xvid)\b"#, options: .regularExpression) != nil {
        features.append("has_video_codec")
    }
    if text.range(of: #"(?i)\b(?:bluray|blu\s*ray|bdrip|webdl|web-dl|webrip|hdtv|dvdrip|remux)\b"#, options: .regularExpression) != nil {
        features.append("has_video_source")
    }
    if text.range(of: #"(?i)\b(?:srt|ass|ssa|vtt|subtitles?|subs?)\b"#, options: .regularExpression) != nil {
        features.append("has_subtitle_marker")
    }
    if text.range(of: #"(?i)\{(?:tmdb|tvdb|imdb)-[^}]+\}"#, options: .regularExpression) != nil {
        features.append("has_plex_source_id")
    }
    if text.contains("(") || text.contains(")") {
        features.append("has_parentheses")
    }
    if text.contains("-") || text.contains("–") || text.contains("—") {
        features.append("has_dash_separator")
    }
    if text.contains(":") {
        features.append("has_colon_separator")
    }
    if text.contains("!") {
        features.append("has_exclamation")
    }

    let longWordCount = wordTokens.filter { $0.count >= 10 }.count
    if longWordCount > 0 {
        features.append("long_word_count_\(bucket(longWordCount, thresholds: [1, 2, 4, 8]))")
    }

    for token in tokens {
        if anonymousVocabulary.contains(token) {
            features.append(token)
        } else if token.allSatisfy(\.isNumber) {
            features.append("number_length_\(bucket(token.count, thresholds: [1, 2, 4, 8]))")
        } else if token.count >= 12 {
            features.append("word_shape_very_long")
        } else if token.count >= 8 {
            features.append("word_shape_long")
        } else if token.count <= 3 {
            features.append("word_shape_short")
        }
    }

    return Array(Set(features)).sorted().joined(separator: " ")
}

private let anonymousVocabulary: Set<String> = [
    "accepted", "anime", "anilist", "archive", "archives", "ass", "audio", "author", "automatic",
    "batch", "bulk",
    "avi", "azw", "azw3", "bmp", "book", "books", "bluray", "cbr", "cbz", "chapter", "checked",
    "ceosable", "choice", "clinic", "collision", "comic", "comicinfo", "comics", "company", "compressed", "config", "container", "cover",
    "cadence", "cleanup", "correction", "curriculum", "css", "csv", "destination", "document", "documents", "doc", "docx",
    "deepdive", "deepevidence", "deepfilecheck", "department", "detail", "detailsafteridentity", "duplicate", "duplicates", "duplicatesafety", "epub", "epubclinic",
    "episode", "extension", "fansub", "file", "folder", "h264", "h265", "image", "images",
    "evidencemap", "handoff", "hardguards", "heic", "html", "identity", "identityfirst", "identitygraph", "imdb", "inspect", "intakedesk", "isbn", "issue", "jpeg", "jpg", "json",
    "kind", "lane", "lazy", "lazycompany", "lesson", "lessons", "library", "light", "local", "localcleanup", "localsidecar", "manual", "manga", "mangabaka", "manhua",
    "manhwa", "material", "match", "mergechoice", "metadata", "mimetype", "mkv", "mlrecommendsuserdecides", "mobi", "mov", "move", "movie", "mp3",
    "mp4", "naminglogistics", "ncx", "network", "novel", "novels", "open", "openlibrary", "operation", "opf",
    "other", "package", "pages", "parent", "pdf", "plist", "plex", "png", "presentation",
    "needschoice", "privacyfirst", "project", "protected", "provider", "providerboundary", "providercontext", "providerreview", "publisher", "quickverify", "ranobedb", "raw", "reading", "receipt",
    "readinglibrary", "refresh", "rename", "repair", "review", "reviewplan", "root", "rootitem", "rootonly", "rawintake", "safety", "safetyoffice", "sample", "sharedevidence", "sidecar", "sidecarrelations", "singleowner", "sort", "spreadsheet",
    "srt", "stage", "stagedhandoff", "subtitle", "subtitles", "swift", "tmdb", "trusted", "tv", "tvdb", "txt",
    "training", "trainingmaterial", "tvmaze", "used", "validation", "veto", "vtt", "video", "videos", "vol", "volume", "watchdesk", "watching",
    "wav", "web", "webdl", "webm", "webp", "webtoon", "wikidata", "wmv", "word", "x264",
    "x265", "xcode", "xcodeproj", "xml", "year", "zip"
]

private func bucket(_ value: Int, thresholds: [Int]) -> String {
    for threshold in thresholds where value <= threshold {
        return "le\(threshold)"
    }
    return "gt\(thresholds.last ?? value)"
}

private func trainModel(options: Options) throws {
    let reportDirectory = defaultReportDirectory()
    let outputURL = options.outputURL
        ?? reportDirectory.appendingPathComponent("SableLibraryPersonalDecisionClassifier.mlmodel")
    let datasetURL = options.datasetURL
        ?? reportDirectory.appendingPathComponent("SableLibraryPersonalDecisionClassifierTraining.csv")
    let scanRoots = options.scanRoots.isEmpty ? defaultScanRoots() : options.scanRoots

    let builder = TrainingBuilder(anonymizeTrainingText: options.anonymizeTrainingText)
    addSeedExamples(to: builder)

    if options.includeAppDefaults, let memory = loadAppLearningMemory() {
        addLearningMemoryExamples(memory, to: builder)
    }

    if options.includeTrainingEvents {
        addTrainingEventExamples(from: scanRoots, to: builder)
    }

    if options.includeWeakFilenameSeeds {
        addWeakFilenameExamples(from: scanRoots, to: builder, maxRows: options.maxWeakFilenameSeeds)
    }

    try addExtraTrainingExamples(
        from: options.extraTrainingCSVs,
        to: builder,
        maxRowsPerLabel: options.maxExtraRowsPerLabel
    )

    builder.balanceLabels(prefix: "reading.", maximumTarget: 260)

    let counts = Dictionary(grouping: builder.examples, by: \.label)
        .mapValues(\.count)
    guard counts.count >= 2 else {
        throw TrainerError.notEnoughLabels(counts)
    }

    try builder.writeCSV(to: datasetURL)

    print("Wrote training CSV: \(datasetURL.path(percentEncoded: false))")
    print("Examples: \(builder.examples.count)")
    print("Labels:")
    for (label, count) in counts.sorted(by: { $0.key < $1.key }) {
        print("  \(label): \(count)")
    }

    if options.trainModelSuite {
        try trainModelSuite(
            examples: builder.examples,
            outputDirectory: outputURL.deletingLastPathComponent(),
            datasetDirectory: datasetURL.deletingLastPathComponent(),
            modelFlavor: options.modelFlavor,
            selectedModelNames: options.selectedSuiteModels
        )
    } else {
        _ = try trainTextClassifier(
            examples: builder.examples,
            outputURL: outputURL,
            datasetURL: datasetURL,
            description: modelDescription(for: options.modelFlavor)
        )
        print("Wrote model: \(outputURL.path(percentEncoded: false))")
    }
}

@discardableResult
private func trainTextClassifier(
    examples: [TrainingExample],
    outputURL: URL,
    datasetURL: URL,
    description: String
) throws -> [String: Int] {
    let counts = Dictionary(grouping: examples, by: \.label).mapValues(\.count)
    guard counts.count >= 2 else {
        throw TrainerError.notEnoughLabels(counts)
    }

    try writeTrainingCSV(examples, to: datasetURL)
    let data = textClassifierTrainingData(from: examples)
    let model = try MLTextClassifier(
        trainingData: data,
        parameters: MLTextClassifier.ModelParameters(validation: .none)
    )
    let metadata = MLModelMetadata(
        author: "Sable's Library",
        shortDescription: description,
        version: "0.2"
    )
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try model.write(to: outputURL, metadata: metadata)
    return counts
}

private func trainModelSuite(
    examples: [TrainingExample],
    outputDirectory: URL,
    datasetDirectory: URL,
    modelFlavor: String,
    selectedModelNames: Set<String>
) throws {
    print("\nTraining specialist model suite:")
    let specs = bundledModelSuite.filter { spec in
        selectedModelNames.isEmpty || selectedModelNames.contains(spec.modelName)
    }
    let knownModelNames = Set(bundledModelSuite.map(\.modelName))
    let unknownModelNames = selectedModelNames.subtracting(knownModelNames)
    for modelName in unknownModelNames.sorted() {
        print("  \(modelName): skipped; no bundled suite model with that name")
    }

    for spec in specs {
        let specialistExamples = examples.filter { spec.includes($0.label) }
        let datasetURL = datasetDirectory.appendingPathComponent("\(spec.modelName)Training.csv")
        let outputURL = outputDirectory.appendingPathComponent("\(spec.modelName).mlmodel")
        let specialistCounts = Dictionary(grouping: specialistExamples, by: \.label).mapValues(\.count)
        guard specialistCounts.count >= 2 else {
            print("  \(spec.modelName): skipped; needs at least 2 labels, found \(specialistCounts.count)")
            continue
        }
        let counts = try trainTextClassifier(
            examples: specialistExamples,
            outputURL: outputURL,
            datasetURL: datasetURL,
            description: "\(modelDescription(for: modelFlavor)) \(spec.description)"
        )
        print("  \(spec.modelName): \(specialistExamples.count) example(s), \(counts.count) label(s)")
        print("    wrote \(outputURL.path(percentEncoded: false))")
        for (label, count) in counts.sorted(by: { $0.key < $1.key }) {
            print("    \(label): \(count)")
        }
    }

    guard selectedModelNames.isEmpty else { return }

    try trainWordTaggerSuite(
        outputDirectory: outputDirectory,
        datasetDirectory: datasetDirectory,
        modelFlavor: modelFlavor
    )

    try trainRecommenderSuite(
        examples: examples,
        outputDirectory: outputDirectory,
        datasetDirectory: datasetDirectory,
        modelFlavor: modelFlavor
    )
}

private func trainWordTaggerSuite(
    outputDirectory: URL,
    datasetDirectory: URL,
    modelFlavor: String
) throws {
    print("\nTraining specialist word taggers:")
    for spec in bundledWordTaggerSuite {
        let outputURL = outputDirectory.appendingPathComponent("\(spec.modelName).mlmodel")
        let datasetURL = datasetDirectory.appendingPathComponent("\(spec.modelName)Training.jsonl")
        try writeWordTaggerDataset(spec.examples, to: datasetURL)
        let model = try MLWordTagger(
            trainingData: spec.examples.map { (tokens: $0.tokens, labels: $0.labels) },
            parameters: MLWordTagger.ModelParameters(validation: .none)
        )
        let metadata = MLModelMetadata(
            author: "Sable's Library",
            shortDescription: "\(modelDescription(for: modelFlavor)) \(spec.description)",
            version: "0.3"
        )
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try model.write(to: outputURL, metadata: metadata)
        print("  \(spec.modelName): \(spec.examples.count) tagged sequence(s)")
        print("    wrote \(outputURL.path(percentEncoded: false))")
    }
}

private func writeWordTaggerDataset(_ examples: [WordTaggerExample], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let lines = try examples.map { example -> String in
        let object: [String: Any] = [
            "tokens": example.tokens,
            "labels": example.labels,
            "source": example.source
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func trainRecommenderSuite(
    examples: [TrainingExample],
    outputDirectory: URL,
    datasetDirectory: URL,
    modelFlavor: String
) throws {
    print("\nTraining specialist recommenders:")
    for spec in bundledRecommenderSuite {
        let recommenderExamples = recommenderExamples(for: spec, classifierExamples: examples)
        let trainingRows = recommenderTrainingRows(from: recommenderExamples)
        let outputURL = outputDirectory.appendingPathComponent("\(spec.modelName).mlmodel")
        let datasetURL = datasetDirectory.appendingPathComponent("\(spec.modelName)Training.csv")
        try writeRecommenderCSV(trainingRows, to: datasetURL)
        let data = recommenderTrainingDataFrame(from: trainingRows)
        let model = try MLRecommender(
            trainingData: data,
            userColumn: "context",
            itemColumn: "item",
            ratingColumn: "rating"
        )
        let metadata = MLModelMetadata(
            author: "Sable's Library",
            shortDescription: "\(modelDescription(for: modelFlavor)) \(spec.description)",
            version: "0.3"
        )
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try model.write(to: outputURL, metadata: metadata)
        let contexts = Set(trainingRows.map(\.context)).count
        let items = Set(trainingRows.map(\.item)).count
        print("  \(spec.modelName): \(trainingRows.count) row(s), \(contexts) context(s), \(items) item(s)")
        print("    wrote \(outputURL.path(percentEncoded: false))")
    }
}

private func textClassifierTrainingData(from examples: [TrainingExample]) -> [String: [String]] {
    Dictionary(grouping: examples, by: \.label)
        .mapValues { groupedExamples in
            groupedExamples.map(\.text)
        }
}

private func recommenderTrainingDataFrame(from examples: [RecommenderExample]) -> DataFrame {
    DataFrame(
        dictionaryLiteral:
            ("context", examples.map(\.context)),
            ("item", examples.map(\.item)),
            ("rating", examples.map(\.rating))
    )
}

private func writeRecommenderCSV(_ examples: [RecommenderExample], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var lines = ["context,item,rating,source"]
    lines.append(contentsOf: examples.map { example in
        [
            example.context,
            example.item,
            String(format: "%.2f", example.rating),
            example.source
        ].map(csvEscaped).joined(separator: ",")
    })
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func recommenderExamples(
    for spec: RecommenderSpec,
    classifierExamples: [TrainingExample]
) -> [RecommenderExample] {
    var rows = curatedRecommenderExamples(for: spec.modelName)
    for example in classifierExamples {
        rows.append(contentsOf: inferredRecommenderExamples(for: spec.modelName, label: example.label))
    }
    return uniquedRecommenderExamples(rows)
}

private func recommenderTrainingRows(from examples: [RecommenderExample]) -> [RecommenderExample] {
    var rows = examples
    for example in examples {
        for signal in recommenderContextSignals(example.context) {
            rows.append(
                rec(
                    example.context,
                    signal,
                    max(1, min(4, example.rating - 1)),
                    source: "\(example.source)-signal"
                )
            )
        }
    }
    return uniquedRecommenderExamples(rows)
}

private func recommenderContextSignals(_ context: String) -> [String] {
    let parts = context
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
        .filter { !$0.isEmpty }
    var seen = Set<String>()
    return parts.compactMap { part in
        let signal = "signal.\(part)"
        return seen.insert(signal).inserted ? signal : nil
    }
}

private func curatedRecommenderExamples(for modelName: String) -> [RecommenderExample] {
    switch modelName {
    case "SableLibraryReviewActionRecommender":
        return [
            rec("stage.prepareRawFiles raw.reading strong", "check.sortIntoFolder", 5),
            rec("stage.prepareRawFiles protected.project", "protect.skip", 5),
            rec("department.rawintake scope.rootonly safety.reversible", "check.sortIntoFolder", 4),
            rec("department.safetyoffice safety.veto protected.project", "protect.skip", 5),
            rec("department.safetyoffice trust.hardguards project app game package", "protect.skip", 5),
            rec("stage.prepareRawFiles pdf.document", "treatAsDocument", 5),
            rec("stage.prepareRawFiles pdf.book", "treatAsBook", 5),
            rec("stage.prepareRawFiles cleanup.document", "treatAsDocument", 5),
            rec("stage.prepareRawFiles cleanup.video", "check.sortIntoFolder", 4),
            rec("stage.prepareRawFiles cleanup.image", "check.sortIntoFolder", 4),
            rec("stage.prepareRawFiles cleanup.audio", "check.sortIntoFolder", 4),
            rec("stage.prepareRawFiles cleanup.archive", "check.sortIntoFolder", 4),
            rec("stage.prepareRawFiles training.material bulk.raw.review", "review.sampleFirst", 5),
            rec("department.rawintake training.material sample.first", "review.sampleFirst", 5),
            rec("stage.comicInfo provider.ambiguous", "review.keepLocal", 4),
            rec("department.sidecarrelations trust.localsidecar provider.ambiguous", "review.keepLocal", 5),
            rec("trust.providerboundary escalation.providerreview", "review.providerChoice", 4),
            rec("stage.canonicalFolders collision", "review.mergeOrMoveAside", 5),
            rec("department.naminglogistics escalation.collision communication.mergechoice", "review.mergeOrMoveAside", 5),
            rec("stage.canonicalFiles missing.number", "review.fixNumber", 5),
            rec("stage.canonicalFolders task.folderRename safe", "check.renameWhenSafe", 4),
            rec("stage.canonicalFiles task.fileRename safe", "check.renameWhenSafe", 4)
        ]
    case "SableLibraryProviderRankingRecommender":
        return [
            rec("domain.reading prose isbn author year", "provider.openLibrary", 5),
            rec("department.readinglibrary trust.providerboundary prose openlibrary", "provider.openLibrary", 5),
            rec("domain.reading lightNovel volume ranobe", "provider.ranobedb", 5),
            rec("department.readinglibrary lightNovel ranobedb volume", "provider.ranobedb", 5),
            rec("domain.reading manga manhwa comic", "provider.mangabaka", 5),
            rec("department.sidecarrelations manga comic mangabaka identitygraph", "provider.mangabaka", 5),
            rec("domain.watching anime", "provider.anilist", 4),
            rec("department.watchdesk anime providercontext", "provider.anilist", 4),
            rec("domain.watching movie", "provider.tmdb", 5),
            rec("domain.watching tv", "provider.tvdb", 5),
            rec("domain.watching mixed", "provider.imdb", 3)
        ]
    case "SableLibraryFolderGroupingRecommender":
        return [
            rec("reading.book prose", "group.Books", 5),
            rec("reading.lightNovel volume", "group.LightNovels", 5),
            rec("reading.manga comicArchive", "group.Manga", 5),
            rec("reading.manhwa webtoon", "group.Manhwa", 5),
            rec("cleanup.video episode", "group.Videos", 5),
            rec("cleanup.watching episode", "group.Videos", 5),
            rec("cleanup.document paperwork", "group.Documents", 5),
            rec("cleanup.image photo", "group.Images", 5),
            rec("cleanup.audio music", "group.Audio", 5),
            rec("cleanup.archive compressed", "group.Archives", 5),
            rec("task.protectedRoot project", "group.Protected", 5),
            rec("department.safetyoffice protected.project", "group.Protected", 5),
            rec("department.rawintake raw.documents", "group.Documents", 4),
            rec("department.readinglibrary raw.books", "group.Books", 4),
            rec("department.watchdesk cleanup.watching", "group.Videos", 4)
        ]
    default:
        return []
    }
}

private func inferredRecommenderExamples(for modelName: String, label: String) -> [RecommenderExample] {
    switch modelName {
    case "SableLibraryReviewActionRecommender":
        if label == "task.protectedRoot" {
            return [rec("label.\(label)", "protect.skip", 4, source: "classifier-label")]
        }
        if label.hasPrefix("pdf.") {
            let item = label == "pdf.document" ? "treatAsDocument" : "treatAsBook"
            return [rec("label.\(label)", item, 4, source: "classifier-label")]
        }
        if label.hasPrefix("provider.") {
            return [rec("label.\(label)", "review.providerChoice", 3, source: "classifier-label")]
        }
        if label.hasPrefix("task.folderRename") || label.hasPrefix("task.fileRename") {
            return [rec("label.\(label)", "check.renameWhenSafe", 3, source: "classifier-label")]
        }
        return [rec("label.\(label)", "check.ifSafe", 2, source: "classifier-label")]
    case "SableLibraryProviderRankingRecommender":
        guard label.hasPrefix("provider.") else { return [] }
        return [rec("label.\(label)", label, 4, source: "classifier-label")]
    case "SableLibraryFolderGroupingRecommender":
        if let group = folderGroupItem(for: label) {
            return [rec("label.\(label)", group, 4, source: "classifier-label")]
        }
        return []
    default:
        return []
    }
}

private func folderGroupItem(for label: String) -> String? {
    switch label {
    case "reading.book", "reading.novel", "raw.books.epub", "raw.books.pdf", "raw.books.djvu":
        return "group.Books"
    case "reading.lightNovel":
        return "group.LightNovels"
    case "reading.manga", "reading.comic", "raw.books.comicArchive":
        return "group.Manga"
    case "reading.manhwa":
        return "group.Manhwa"
    case "reading.manhua":
        return "group.Manhua"
    case "cleanup.watching":
        return "group.Videos"
    case "cleanup.document", "pdf.document":
        return "group.Documents"
    case "cleanup.image":
        return "group.Images"
    case "cleanup.audio":
        return "group.Audio"
    case "cleanup.archive":
        return "group.Archives"
    case "task.protectedRoot":
        return "group.Protected"
    default:
        if label.hasPrefix("raw.video.") { return "group.Videos" }
        if label.hasPrefix("raw.documents.") { return "group.Documents" }
        if label.hasPrefix("raw.images.") { return "group.Images" }
        if label.hasPrefix("raw.audio.") { return "group.Audio" }
        if label.hasPrefix("raw.archives.") { return "group.Archives" }
        return nil
    }
}

private func uniquedRecommenderExamples(_ rows: [RecommenderExample]) -> [RecommenderExample] {
    var ratings: [String: RecommenderExample] = [:]
    for row in rows {
        let key = "\(row.context)\u{1f}\(row.item)"
        if let existing = ratings[key] {
            ratings[key] = RecommenderExample(
                context: row.context,
                item: row.item,
                rating: min(5, existing.rating + row.rating * 0.1),
                source: existing.source
            )
        } else {
            ratings[key] = row
        }
    }
    return ratings.values.sorted {
        if $0.context != $1.context { return $0.context < $1.context }
        return $0.item < $1.item
    }
}

private func rec(_ context: String, _ item: String, _ rating: Double, source: String = "curated-recommender-seed") -> RecommenderExample {
    RecommenderExample(context: context, item: item, rating: rating, source: source)
}

private func modelDescription(for flavor: String) -> String {
    switch flavor {
    case "baseline":
        return "Bundled starter cleanup decision classifier trained from curated non-private Sable examples."
    case "anonymous":
        return "Bundled cleanup decision classifier trained from local Sable signals after title and path text were converted to anonymous feature tokens."
    case "anonymous-suite":
        return "Bundled Sable model suite trained from local signals after title and path text were converted to anonymous feature tokens."
    case "anonymous-personal":
        return "Personal cleanup decision classifier trained from local Sable signals after title and path text were converted to anonymous feature tokens."
    default:
        return "Personal cleanup decision classifier trained from local Sable review choices, training receipts, and weak filename seeds."
    }
}

do {
    try trainModel(options: parseOptions())
} catch {
    fputs("Sable ML training failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
