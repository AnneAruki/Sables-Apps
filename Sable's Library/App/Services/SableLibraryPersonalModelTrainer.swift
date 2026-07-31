//
//  SableLibraryPersonalModelTrainer.swift
//  Sable's Library
//

import Foundation
#if canImport(CreateML)
import CreateML
#endif
#if canImport(CoreML)
import CoreML
#endif

extension Notification.Name {
    static let sableLibraryPersonalModelChanged = Notification.Name("sableLibraryPersonalModelChanged")
}

nonisolated struct SableLibraryPersonalModelTrainingResult: Sendable, Equatable {
    var trainedAt: Date
    var eventCount: Int
    var exampleCount: Int
    var labelCount: Int
    var modelURL: URL
    var datasetURL: URL

    var summary: String {
        "Trained from \(eventCount) local event\(eventCount == 1 ? "" : "s") into \(exampleCount) anonymous example\(exampleCount == 1 ? "" : "s") across \(labelCount) label\(labelCount == 1 ? "" : "s")."
    }
}

nonisolated enum SableLibraryPersonalModelStore {
    static let modelName = "SableLibraryDecisionClassifier"
    static let modelFileName = "SableLibraryPersonalDecisionClassifier.mlmodel"
    static let compiledModelFileName = "SableLibraryPersonalDecisionClassifier.mlmodelc"
    static let datasetFileName = "SableLibraryPersonalDecisionClassifierTraining.csv"
    static let learningFileName = "SableLearningMemory.json"

    static var directory: URL {
        let sharedDirectory = SableLibrarySharedContainer.supportDirectory(named: "ML")
        let legacyDirectory = SableLibrarySharedContainer.legacySupportDirectory(named: "ML")
        SableLibrarySharedContainer.migrateFileIfNeeded(
            from: legacyDirectory.appendingPathComponent(modelFileName),
            to: sharedDirectory.appendingPathComponent(modelFileName)
        )
        SableLibrarySharedContainer.migrateFileIfNeeded(
            from: legacyDirectory.appendingPathComponent(datasetFileName),
            to: sharedDirectory.appendingPathComponent(datasetFileName)
        )
        return sharedDirectory
    }

    static var modelURL: URL {
        directory.appendingPathComponent(modelFileName)
    }

    static var compiledModelURL: URL {
        directory.appendingPathComponent(compiledModelFileName, isDirectory: true)
    }

    static var datasetURL: URL {
        directory.appendingPathComponent(datasetFileName)
    }

    static var learningMemoryURL: URL {
        SableLibrarySharedContainer
            .supportDirectory(named: "Learning")
            .appendingPathComponent(learningFileName)
    }

    static func isPersonalModelFresh(
        modelURL: URL = SableLibraryPersonalModelStore.modelURL,
        learningURL: URL = SableLibraryPersonalModelStore.learningMemoryURL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: modelURL.path(percentEncoded: false)) else { return false }

        let modelDate = modificationDate(for: modelURL, fileManager: fileManager)
        guard let modelDate else { return false }

        guard fileManager.fileExists(atPath: learningURL.path(percentEncoded: false)),
              let learningDate = modificationDate(for: learningURL, fileManager: fileManager) else {
            return true
        }

        return modelDate >= learningDate
    }

    static func isCompiledPersonalModelFresh(
        compiledURL: URL = SableLibraryPersonalModelStore.compiledModelURL,
        modelURL: URL = SableLibraryPersonalModelStore.modelURL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: compiledURL.path(percentEncoded: false)),
              fileManager.fileExists(atPath: modelURL.path(percentEncoded: false)),
              let compiledDate = modificationDate(for: compiledURL, fileManager: fileManager),
              let modelDate = modificationDate(for: modelURL, fileManager: fileManager) else {
            return false
        }
        return compiledDate >= modelDate
    }

    #if canImport(CoreML)
    @discardableResult
    static func prepareCompiledModel(
        sourceURL: URL = SableLibraryPersonalModelStore.modelURL,
        destinationURL: URL = SableLibraryPersonalModelStore.compiledModelURL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let temporaryCompiledURL = try MLModel.compileModel(at: sourceURL)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stagedURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(destinationURL.lastPathComponent)-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: stagedURL) }

        try fileManager.copyItem(at: temporaryCompiledURL, to: stagedURL)
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: stagedURL, to: destinationURL)
        return destinationURL
    }
    #endif

    private static func modificationDate(for url: URL, fileManager: FileManager) -> Date? {
        let path = url.path(percentEncoded: false)
        return (try? fileManager.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }
}

nonisolated enum SableLibraryPersonalModelTrainingError: LocalizedError {
    case createMLUnavailable
    case missingLibrary
    case noTrainingMaterial
    case notEnoughLabels([String: Int])

    var errorDescription: String? {
        switch self {
        case .createMLUnavailable:
            "Personal model training needs Create ML on macOS."
        case .missingLibrary:
            "Choose and save a library folder before training."
        case .noTrainingMaterial:
            "No local training material was found yet. Apply trusted rows or make a few corrections first."
        case .notEnoughLabels(let counts):
            "Sable needs at least two kinds of lessons before training. Current labels: \(counts.keys.sorted().joined(separator: ", "))."
        }
    }
}

nonisolated struct SableLibraryPersonalModelTrainer {
    private struct TrainingExample: Hashable {
        var text: String
        var label: String
        var source: String
    }

    func train(
        root: URL?,
        config: SableLibraryConfig,
        learningMemory: SableLibraryLearningMemory,
        outputDirectory: URL = SableLibraryPersonalModelStore.directory
    ) throws -> SableLibraryPersonalModelTrainingResult {
        #if canImport(CreateML)
        guard let root else {
            throw SableLibraryPersonalModelTrainingError.missingLibrary
        }

        let reportDirectory = root.appendingPathComponent(config.reportFolderName, isDirectory: true)
        let eventURL = reportDirectory.appendingPathComponent("_sable_ml_training_events.jsonl")
        let events = decodedTrainingEvents(at: eventURL)
        guard !events.isEmpty || learningMemory.learnedDecisionCount > 0 else {
            throw SableLibraryPersonalModelTrainingError.noTrainingMaterial
        }

        var trainingExamples = curatedExamples()
        for event in events {
            trainingExamples.append(contentsOf: examples(for: event))
        }
        trainingExamples.append(contentsOf: examples(for: learningMemory))

        let counts = Dictionary(grouping: trainingExamples, by: \.label).mapValues(\.count)
        guard counts.count >= 2 else {
            throw SableLibraryPersonalModelTrainingError.notEnoughLabels(counts)
        }

        let modelURL = outputDirectory.appendingPathComponent(SableLibraryPersonalModelStore.modelFileName)
        let datasetURL = outputDirectory.appendingPathComponent(SableLibraryPersonalModelStore.datasetFileName)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try writeTrainingCSV(trainingExamples, to: datasetURL)

        let trainingData = Dictionary(grouping: trainingExamples, by: \.label)
            .mapValues { groupedExamples in groupedExamples.map(\.text) }
        let model = try MLTextClassifier(
            trainingData: trainingData,
            parameters: MLTextClassifier.ModelParameters(validation: .none)
        )
        let metadata = MLModelMetadata(
            author: "Sable's Library",
            shortDescription: "Personal local cleanup decision model trained from anonymous Sable review material on this Mac.",
            version: "0.1"
        )
        try model.write(to: modelURL, metadata: metadata)
        #if canImport(CoreML)
        try SableLibraryPersonalModelStore.prepareCompiledModel(sourceURL: modelURL)
        #endif

        return SableLibraryPersonalModelTrainingResult(
            trainedAt: Date(),
            eventCount: events.count,
            exampleCount: trainingExamples.count,
            labelCount: counts.count,
            modelURL: modelURL,
            datasetURL: datasetURL
        )
        #else
        throw SableLibraryPersonalModelTrainingError.createMLUnavailable
        #endif
    }

    private func decodedTrainingEvents(at url: URL) -> [SableLibraryMLTrainingEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(SableLibraryMLTrainingEvent.self, from: data)
            }
    }

    private func examples(for event: SableLibraryMLTrainingEvent) -> [TrainingExample] {
        labels(for: event).map { label in
            TrainingExample(
                text: featureText(for: event),
                label: label,
                source: "local-training-event"
            )
        }
    }

    private func examples(for memory: SableLibraryLearningMemory) -> [TrainingExample] {
        var examples: [TrainingExample] = []

        for memoryValue in memory.cleanupKindTerms.values {
            for (kind, count) in memoryValue.kindCounts {
                append(
                    &examples,
                    text: "privacy_anonymized local_memory cleanup_kind count_\(bucket(count))",
                    label: "cleanup.\(kind)",
                    source: "local-learning-memory",
                    count: count
                )
            }
        }

        for memoryValue in memory.rawReadingLaneTerms.values {
            for (lane, count) in memoryValue.laneCounts {
                append(
                    &examples,
                    text: "privacy_anonymized local_memory raw_reading_lane count_\(bucket(count))",
                    label: "reading.\(lane)",
                    source: "local-learning-memory",
                    count: count
                )
            }
        }

        for memoryValue in memory.pdfTriageTerms.values {
            append(
                &examples,
                text: "privacy_anonymized local_memory pdf_triage document count_\(bucket(memoryValue.documentCount))",
                label: "pdf.document",
                source: "local-learning-memory",
                count: memoryValue.documentCount
            )
            append(
                &examples,
                text: "privacy_anonymized local_memory pdf_triage book count_\(bucket(memoryValue.bookCount))",
                label: "pdf.book",
                source: "local-learning-memory",
                count: memoryValue.bookCount
            )
        }

        for memoryValue in memory.mangaBakaSeries.values {
            append(
                &examples,
                text: "privacy_anonymized local_memory provider keep_local mangabaka count_\(bucket(memoryValue.keptLocalCount))",
                label: "provider.keepLocal",
                source: "local-learning-memory",
                count: memoryValue.keptLocalCount
            )
            let acceptedCount = memoryValue.acceptedCandidateIDs.values.reduce(0, +)
            append(
                &examples,
                text: "privacy_anonymized local_memory provider match_strong mangabaka count_\(bucket(acceptedCount))",
                label: "provider.matchStrong",
                source: "local-learning-memory",
                count: acceptedCount
            )
        }

        return examples
    }

    private func labels(for event: SableLibraryMLTrainingEvent) -> [String] {
        let reviewTags = event.featureSummary["review_tags"] ?? ""
        let operation = event.featureSummary["operation"] ?? ""
        let destinationRoot = event.featureSummary["destination_root"] ?? ""
        var labels: [String] = []

        func append(_ label: String?) {
            guard let label, allowedLabels.contains(label), !labels.contains(label) else { return }
            labels.append(label)
        }

        if let lane = firstTaggedValue(in: reviewTags, prefix: "raw-reading-") {
            append("reading.\(lane)")
        }
        if let kind = firstTaggedValue(in: reviewTags, prefix: "cleanup-kind-") {
            append(kind == "watching" ? "cleanup.watching" : "cleanup.\(kind)")
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
        if reviewTags.contains("metadata-comicinfo-cleaner") || reviewTags.contains("metadata-provider-data-cleaner") {
            append("metadata.clean")
            append("cleanup.reading")
            append("sidecar.comicInfo.clean")
            append("task.jsonSidecar")
        }
        if reviewTags.contains("metadata-checkpoint-watching") || reviewTags.contains("metadata-provider-watching") {
            append("metadata.watching")
            append("provider.callWatching")
        }
        if reviewTags.contains("manual-provider-match") {
            append("provider.matchStrong")
        }
        if reviewTags.contains("epub-import-metadata") {
            append("epub.repair.metadata")
        }
        if reviewTags.contains("epub-tags") {
            append("epub.repair.tags")
        }
        if reviewTags.contains("epub-cover") {
            append("epub.repair.cover")
        }
        if reviewTags.contains("epub-navigation") || reviewTags.contains("ml-training-epub-navigation") {
            append("epub.repair.navigation")
        }
        if reviewTags.contains("epub-structure") || reviewTags.contains("ml-training-epub-structure") {
            append("epub.repair.structure")
        }
        if reviewTags.contains("epub-package")
            || reviewTags.contains("epub-manifest")
            || reviewTags.contains("ml-training-epub-package") {
            append("epub.repair.package")
        }
        if reviewTags.contains("epub-content")
            || reviewTags.contains("epub-css")
            || reviewTags.contains("ml-training-epub-content") {
            append("epub.repair.content")
        }
        if reviewTags.contains("ml-training-epub-manual-review")
            || reviewTags.contains("epub-manual-review")
            || reviewTags.contains("epub-xhtml")
            || reviewTags.contains("epub-fixed-layout") {
            append("epub.review.manual")
        }

        switch operation {
        case "sortIntoFolder":
            append("task.rawCleanup")
        case "renameFolder":
            append("task.folderRename")
        case "renameFile", "cleanRawName":
            append("task.fileRename")
        case "createComicInfo":
            append("sidecar.comicInfo.create")
            append("task.jsonSidecar")
        case "refreshComicInfo":
            append("sidecar.comicInfo.refresh")
            append("task.jsonSidecar")
        case "createAnimeInfo":
            append("sidecar.animeInfo.create")
            append("task.jsonSidecar")
        case "refreshAnimeInfo":
            append("sidecar.animeInfo.refresh")
            append("task.jsonSidecar")
        case "repairEpubPackage":
            append("epub.repair.package")
            append("task.epubRepair")
        case "repairAppleBooksCompatibility":
            append("epub.repair.appleBooks")
            append("task.epubRepair")
        default:
            break
        }

        if event.kind == .manualIDEntry {
            append("provider.matchStrong")
            append(event.domain == .watching ? "provider.callWatching" : "provider.callReading")
        }
        if event.kind == .skippedAmbiguousMatch || event.kind == .providerDisagreement {
            append("provider.matchAmbiguous")
            append("provider.keepLocal")
        }
        if let provider = event.provider {
            append("provider.\(provider.rawValue)")
        }
        if let rawLabel = rawLabel(for: event.featureSummary["source_extension"] ?? "") {
            append(rawLabel)
        }

        return labels
    }

    private func featureText(for event: SableLibraryMLTrainingEvent) -> String {
        let summary = event.featureSummary
        let safeValues = [
            "privacy_anonymized",
            "event_\(event.kind.rawValue)",
            "domain_\(event.domain.rawValue)",
            event.provider.map { "provider_\($0.rawValue)" } ?? "",
            safeToken("stage", summary["stage"]),
            safeToken("operation", summary["operation"]),
            safeToken("safety", summary["safety"]),
            safeToken("destination_root", summary["destination_root"]),
            safeToken("source_extension", summary["source_extension"]),
            safeToken("metadata_providers", summary["metadata_providers"]),
            safeToken("cleanup_kind", summary["cleanup_kind"]),
            safeToken("provider_data_state", summary["provider_data_state"]),
            safeToken("trusted_title_provider", summary["trusted_title_provider"]),
            safeToken("source_provider_count", summary["source_provider_count"]),
            safeToken("has_cover_url", summary["has_cover_url"]),
            safeToken("has_match_evidence", summary["has_match_evidence"]),
            safeToken("has_source_freshness", summary["has_source_freshness"]),
            safeToken("has_title_variants", summary["has_title_variants"]),
            safeToken("has_native_title", summary["has_native_title"]),
            safeToken("has_romanized_title", summary["has_romanized_title"]),
            safeToken("tag_count", summary["tag_count"]),
            safeToken("genre_count", summary["genre_count"]),
            safeToken("author_count", summary["author_count"]),
            safeToken("publisher_count", summary["publisher_count"]),
            safeToken("isbn_count", summary["isbn_count"]),
            safeToken("volume_count", summary["volume_count"]),
            safeToken("sidecar_source", summary["sidecar_source"]),
            safeReviewTags(summary["review_tags"] ?? "")
        ]
        return safeValues
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func safeReviewTags(_ value: String) -> String {
        value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tag in
                tag.hasPrefix("raw-reading-")
                    || tag.hasPrefix("cleanup-kind-")
                    || tag.hasPrefix("pdf-triage")
                    || tag.hasPrefix("likely-")
                    || tag.hasPrefix("epub-")
                    || tag.hasPrefix("ml-training-epub-")
                    || tag.hasPrefix("metadata-")
                    || tag.hasPrefix("provider-route-")
                    || tag.hasPrefix("provider-")
                    || tag == "needs-provider-choice"
                    || tag == "manual-provider-match"
                    || tag == "training-material"
                    || tag == "bulk-raw-review"
            }
            .map { "tag_\($0)" }
            .joined(separator: " ")
    }

    private func safeToken(_ key: String, _ value: String?) -> String {
        guard let value else { return "" }
        let cleaned = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !cleaned.isEmpty else { return "" }
        return "\(key)_\(cleaned)"
    }

    private func append(
        _ examples: inout [TrainingExample],
        text: String,
        label: String,
        source: String,
        count: Int
    ) {
        guard count > 0, allowedLabels.contains(label) else { return }
        for _ in 0..<min(count, 8) {
            examples.append(TrainingExample(text: text, label: label, source: source))
        }
    }

    private func curatedExamples() -> [TrainingExample] {
        [
            TrainingExample(text: "privacy_anonymized stage_prepareRawFiles raw_reading strong", label: "task.rawCleanup", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized protected project app game package", label: "task.protectedRoot", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized reading prose book openlibrary", label: "reading.book", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized reading light novel volume ranobedb", label: "reading.lightNovel", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized reading manga comic archive", label: "reading.manga", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized cleanup document pdf word spreadsheet", label: "cleanup.document", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized cleanup video episode movie tv anime", label: "cleanup.watching", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized metadata sidecar clean provider evidence cover tags freshness", label: "metadata.clean", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized comicinfo clean trusted ids title cover provider data", label: "sidecar.comicInfo.clean", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized provider ambiguous weak keep local", label: "provider.keepLocal", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized provider manual id exact match", label: "provider.matchStrong", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub package manifest opf identifier refines", label: "epub.repair.package", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub content xhtml css entity attributes", label: "epub.repair.content", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub navigation toc ncx landmarks playorder", label: "epub.repair.navigation", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub semantic structure headings ncx anchors", label: "epub.repair.structure", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub metadata import comicinfo title creator identifier", label: "epub.repair.metadata", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub tags description subjects cleaned", label: "epub.repair.tags", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub cover marker dimensions image review", label: "epub.repair.cover", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized epub manual review duplicate id malformed xhtml fixed layout missing resource", label: "epub.review.manual", source: "curated-seed"),
            TrainingExample(text: "privacy_anonymized training material bulk raw sample first", label: "task.rawCleanup", source: "curated-seed")
        ]
    }

    private func firstTaggedValue(in text: String, prefix: String) -> String? {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func bucket(_ value: Int) -> String {
        switch value {
        case 0: "zero"
        case 1: "one"
        case 2...5: "few"
        case 6...20: "some"
        case 21...80: "many"
        default: "large"
        }
    }

    private func rawLabel(for ext: String) -> String? {
        switch ext.lowercased() {
        case "epub", "mobi", "azw", "azw3": "raw.books.epub"
        case "cbz", "cbr", "cb7", "cbt": "raw.books.comicArchive"
        case "pdf": "raw.documents.pdf"
        case "mkv": "raw.video.mkv"
        case "mp4", "m4v": "raw.video.mp4"
        case "mov": "raw.video.mov"
        case "jpg", "jpeg": "raw.images.jpeg"
        case "png": "raw.images.png"
        case "webp": "raw.images.webp"
        case "mp3": "raw.audio.mp3"
        case "m4a", "aac": "raw.audio.aac"
        case "zip": "raw.archives.zip"
        case "json": "raw.documents.json"
        case "xml", "plist", "opf", "ncx": "raw.documents.xml"
        case "txt", "md", "rtf": "raw.documents.text"
        case "doc", "docx", "pages": "raw.documents.word"
        case "csv", "xls", "xlsx", "numbers": "raw.documents.spreadsheet"
        default: nil
        }
    }

    private func writeTrainingCSV(_ examples: [TrainingExample], to url: URL) throws {
        var lines = ["text,label,source"]
        lines.append(contentsOf: examples.map { example in
            [example.text, example.label, example.source]
                .map { value in "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                .joined(separator: ",")
        })
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    #if DEBUG
    func labelsForTesting(for event: SableLibraryMLTrainingEvent) -> [String] {
        labels(for: event)
    }
    #endif

    private var allowedLabels: Set<String> {
        [
            "task.rawCleanup",
            "task.protectedRoot",
            "task.folderRename",
            "task.fileRename",
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
            "reading.comic",
            "pdf.document",
            "pdf.book",
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
            "provider.callReading",
            "provider.callWatching",
            "provider.keepLocal",
            "provider.matchStrong",
            "provider.matchAmbiguous",
            "metadata.choice",
            "metadata.identity",
            "metadata.detail",
            "metadata.refresh",
            "metadata.clean",
            "metadata.watching",
            "sidecar.comicInfo.create",
            "sidecar.comicInfo.refresh",
            "sidecar.comicInfo.clean",
            "sidecar.animeInfo.create",
            "sidecar.animeInfo.refresh",
            "epub.repair.package",
            "epub.repair.appleBooks",
            "epub.repair.content",
            "epub.repair.navigation",
            "epub.repair.structure",
            "epub.repair.metadata",
            "epub.repair.tags",
            "epub.repair.cover",
            "epub.review.manual",
            "raw.books.epub",
            "raw.books.comicArchive",
            "raw.documents.pdf",
            "raw.documents.text",
            "raw.documents.word",
            "raw.documents.spreadsheet",
            "raw.documents.json",
            "raw.documents.xml",
            "raw.video.mkv",
            "raw.video.mp4",
            "raw.video.mov",
            "raw.images.jpeg",
            "raw.images.png",
            "raw.images.webp",
            "raw.audio.mp3",
            "raw.audio.aac",
            "raw.archives.zip"
        ]
    }
}
