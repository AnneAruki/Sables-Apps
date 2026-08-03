#!/usr/bin/env swift

import CoreML
import CreateML
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

private let supportedRatings = [
    "safe", "suggestive", "erotica", "pornographic",
]
private let minimumTrainingCoversPerRating = 8
private let minimumValidationCoversPerRating = 3

private struct Options {
    var repoRoot = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    var libraryRoot: URL?
    var judgmentURLs: [URL] = []
    var examplesPerRating = 80
    var validationFraction = 0.20
    var promotesValidatedModel = false
}

private struct JudgmentExport: Decodable {
    var ruleVersion: String?
    var items: [Judgment]
}

private struct Judgment: Decodable {
    var imageURL: String
    var index: String?
    var language: String?
    var seriesID: String
    var seriesTitle: String
    var sha256: String
    var sourceURL: String?
    var type: String?
    var rating: String
}

private struct SeriesEnvelope: Decodable {
    var data: Series
}

private struct Series: Decodable, Hashable {
    var id: Int
    var title: String
}

private struct ImagesEnvelope: Decodable {
    var data: [ImageRecord]
    var pagination: Pagination
}

private struct Pagination: Decodable {
    var next: String?
}

private struct ImageRecord: Decodable {
    struct Hashes: Decodable {
        var sha256: String?
    }

    struct Image: Decodable {
        struct Raw: Decodable {
            var url: String
        }

        struct Sized: Decodable {
            var x2: String?
        }

        var raw: Raw
        var x350: Sized?
    }

    var id: Int
    var index: String?
    var indexNumeric: Double
    var type: String
    var language: String
    var hashes: Hashes?
    var image: Image

    enum CodingKeys: String, CodingKey {
        case id
        case index
        case indexNumeric = "index_numeric"
        case type
        case language
        case hashes
        case image
    }

    var imageURL: URL? {
        URL(string: image.x350?.x2 ?? image.raw.url)
    }

    var volumeNumber: Int? {
        if let index, let number = Int(index) {
            return number
        }
        guard indexNumeric.rounded() == indexNumeric else { return nil }
        return Int(indexNumeric)
    }
}

private struct LocalCoverManifest: Decodable {
    struct Entry: Decodable {
        var covers: [Cover]
    }

    struct Cover: Decodable {
        var path: String
        var providerItemID: String?
        var providerSeriesID: String?
        var providerVolume: Double?
        var language: String?
        var role: String?
        var source: String?
        var url: String?

        enum CodingKeys: String, CodingKey {
            case path
            case providerItemID = "provider_item_id"
            case providerSeriesID = "provider_series_id"
            case providerVolume = "provider_volume"
            case language
            case role
            case source
            case url
        }
    }

    var entries: [Entry]
    var seriesTitle: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case seriesTitle = "series_title"
    }
}

private struct LocalCoverReference {
    var fileURL: URL
    var relativePath: String
    var seriesID: Int
    var seriesTitle: String
    var imageID: Int?
    var sourceURL: String?
    var language: String?
    var type: String?
    var index: String?
}

private struct Candidate {
    var seriesID: Int
    var seriesTitle: String
    var imageID: Int
    var language: String
    var type: String
    var index: String
    var rating: String
    var labelOrigin: String
    var localURL: URL?
    var remoteURL: URL?
    var sha256: String
    var isUserConfirmed: Bool
}

private struct LocalAuditSource {
    var fileURL: URL
    var relativePath: String
    var seriesID: Int
    var seriesTitle: String
    var imageID: Int?
    var language: String?
    var type: String?
    var index: String?
    var expectedRating: String?
    var labelOrigin: String?
    var sha256: String
}

private enum Partition: String, Codable {
    case training
    case validation
}

private struct ManifestRecord: Codable {
    var seriesID: Int
    var seriesTitle: String
    var imageID: Int
    var language: String
    var type: String
    var index: String
    var rating: String
    var labelOrigin: String
    var partition: Partition
    var source: String
    var sha256: String
}

private struct AuditRecord: Codable {
    var path: String
    var seriesID: Int
    var seriesTitle: String
    var imageID: Int?
    var language: String?
    var type: String?
    var index: String?
    var expectedRating: String?
    var labelOrigin: String?
    var predictedRating: String
    var confidence: Double
    var differsFromSavedRating: Bool
    var wouldRaiseSavedRating: Bool
    var sha256: String
}

private struct Prediction {
    var rating: String
    var confidence: Double
}

private enum TrainerError: LocalizedError {
    case missingLibraryRoot
    case noLocalManifests(URL)
    case incompleteDataset(String)

    var errorDescription: String? {
        switch self {
        case .missingLibraryRoot:
            return "No cover library was found. Pass --library-root with the folder that contains the downloaded series."
        case .noLocalManifests(let root):
            return "No cover-manifest.json files were found under \(root.path(percentEncoded: false))."
        case .incompleteDataset(let detail):
            return "The automatic corpus is not complete enough for honest four-level validation. \(detail)"
        }
    }
}

private actor HTTPClient {
    private let decoder = JSONDecoder()
    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    init(cacheDirectory: URL) throws {
        self.cacheDirectory = cacheDirectory
        try fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        cacheKey: String
    ) async throws -> T {
        let cacheURL = cacheDirectory.appendingPathComponent(cacheKey)
        if let data = try? Data(contentsOf: cacheURL),
           let value = try? decoder.decode(T.self, from: data) {
            return value
        }

        let data = try await requestData(from: url, attempts: 5)
        try? data.write(to: cacheURL, options: .atomic)
        return try decoder.decode(T.self, from: data)
    }

    func data(from url: URL) async throws -> Data {
        try await requestData(from: url, attempts: 4)
    }

    private func requestData(from url: URL, attempts: Int) async throws -> Data {
        var delay: UInt64 = 500_000_000
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                request.setValue(
                    "Sables-Covers-Local-ML-Trainer/2",
                    forHTTPHeaderField: "User-Agent"
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 429 || (500...599).contains(http.statusCode) {
                    throw URLError(.resourceUnavailable)
                }
                guard (200...299).contains(http.statusCode), !data.isEmpty else {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch {
                lastError = error
                guard attempt + 1 < attempts else { break }
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 8_000_000_000)
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}

private enum CoverSafetyTrainer {
    private static let onePieceCalibrationSeriesID = 377

    static func run() async throws {
        let options = parseOptions()
        let fileManager = FileManager.default
        let libraryRoot = try resolvedLibraryRoot(options.libraryRoot)
        let workingDirectory = options.repoRoot
            .appendingPathComponent("build/CoverSafetyML", isDirectory: true)
        let cacheDirectory = workingDirectory
            .appendingPathComponent("api-cache", isDirectory: true)
        let datasetDirectory = workingDirectory
            .appendingPathComponent("dataset", isDirectory: true)
        let trainingDirectory = datasetDirectory
            .appendingPathComponent("training", isDirectory: true)
        let validationDirectory = datasetDirectory
            .appendingPathComponent("validation", isDirectory: true)
        let candidateModelURL = workingDirectory
            .appendingPathComponent("SableLibraryCoverSafetyClassifier.mlmodel")
        let promotedModelURL = options.repoRoot
            .appendingPathComponent(
                "Sable's Library/App/ML/SableLibraryCoverSafetyClassifier.mlmodel"
            )

        try fileManager.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: datasetDirectory)
        try? fileManager.removeItem(at: candidateModelURL)
        for partitionURL in [trainingDirectory, validationDirectory] {
            for rating in supportedRatings {
                try fileManager.createDirectory(
                    at: partitionURL.appendingPathComponent(rating, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        }

        let client = try HTTPClient(cacheDirectory: cacheDirectory)
        let judgmentExports = try loadJudgments(options.judgmentURLs)
        let judgmentsByHash = deduplicatedJudgments(
            judgmentExports.flatMap(\.items)
        )
        let judgmentTrainingCandidates = trainingCandidates(
            from: Array(judgmentsByHash.values)
        )
        let local = try collectLocalCovers(
            libraryRoot: libraryRoot,
            judgmentsByHash: judgmentsByHash
        )
        let localJudgmentCount = local.filter { $0.expectedRating != nil }.count
        print(
            "Found \(local.count) downloaded covers and "
                + "\(Set(local.map(\.sha256)).count) unique image files"
        )
        print(
            "Loaded \(judgmentTrainingCandidates.count) user-confirmed covers"
                + " (\(localJudgmentCount) matched downloaded files)"
                + (judgmentExports.compactMap(\.ruleVersion).isEmpty
                    ? ""
                    : " using \(judgmentExports.compactMap(\.ruleVersion).joined(separator: ", "))")
        )

        let deduplicated = deduplicatedCandidates(
            judgmentTrainingCandidates
        )
        printCandidateCounts(deduplicated, heading: "Available labeled covers")

        let selected = try selectBalancedDataset(
            from: deduplicated,
            options: options
        )
        let balancedSelection = balancedTrainingSelection(selected)
        let manifest = try await materializeDataset(
            balancedSelection,
            at: datasetDirectory,
            client: client
        )
        let counts = manifestCounts(manifest)
        let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        print(
            "Training cover safety model from \(manifest.count) samples made "
                + "from \(Set(manifest.map(\.sha256)).count) unique covers"
        )
        printCounts(counts)

        let parameters = MLImageClassifier.ModelParameters(
            validation: .dataSource(.labeledDirectories(at: validationDirectory)),
            maxIterations: 60,
            augmentation: [.exposure, .noise],
            algorithm: .transferLearning(
                featureExtractor: .scenePrint(revision: 1),
                classifier: .logisticRegressor
            )
        )
        let classifier = try MLImageClassifier(
            trainingData: .labeledDirectories(at: trainingDirectory),
            parameters: parameters
        )

        print("Training classification error: \(classifier.trainingMetrics.classificationError)")
        print("Validation classification error: \(classifier.validationMetrics.classificationError)")
        print("Validation details:\n\(classifier.validationMetrics)")

        let metadata = MLModelMetadata(
            author: "Sable's Library",
            shortDescription: "Local four-level manga cover safety classifier trained only from human item-level judgments.",
            version: "0.2",
            additional: [
                "ratings": supportedRatings.joined(separator: ","),
                "label_policy": "human-only; live MangaBaka ratings excluded",
                "validation_partition": "whole-series human judgments",
                "user_confirmed_covers": String(judgmentTrainingCandidates.count),
                "training_manifest": "build/CoverSafetyML/manifest.json",
            ]
        )
        try classifier.write(to: candidateModelURL, metadata: metadata)
        print("Wrote candidate model: \(candidateModelURL.path(percentEncoded: false))")

        try auditLocalCovers(
            modelURL: candidateModelURL,
            sources: local,
            outputURL: workingDirectory.appendingPathComponent("local-audit.json")
        )

        if options.promotesValidatedModel {
            try fileManager.createDirectory(
                at: promotedModelURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: promotedModelURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: promotedModelURL)
            }
            try fileManager.copyItem(at: candidateModelURL, to: promotedModelURL)
            print("Promoted model: \(promotedModelURL.path(percentEncoded: false))")
        } else {
            print("Candidate was not added to the app. Review validation and local-audit.json first.")
        }
    }

    private static func resolvedLibraryRoot(_ explicit: URL?) throws -> URL {
        let fileManager = FileManager.default
        if let explicit,
           fileManager.fileExists(atPath: explicit.path(percentEncoded: false)) {
            return explicit.standardizedFileURL
        }
        let defaultRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Torika Library", isDirectory: true)
        guard fileManager.fileExists(atPath: defaultRoot.path(percentEncoded: false)) else {
            throw TrainerError.missingLibraryRoot
        }
        return defaultRoot
    }

    private static func collectLocalCovers(
        libraryRoot: URL,
        judgmentsByHash: [String: Judgment]
    ) throws -> [LocalAuditSource] {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw TrainerError.noLocalManifests(libraryRoot)
        }

        var referencesByPath: [String: LocalCoverReference] = [:]
        for case let manifestURL as URL in enumerator
        where manifestURL.lastPathComponent == "cover-manifest.json" {
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(LocalCoverManifest.self, from: data)
            else { continue }
            let seriesDirectory = manifestURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            for cover in manifest.entries.flatMap(\.covers) {
                guard let seriesID = cover.providerSeriesID.flatMap(Int.init) else {
                    continue
                }
                let fileURL = seriesDirectory
                    .appendingPathComponent(cover.path)
                    .standardizedFileURL
                guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                    continue
                }
                let relativePath = relativePath(for: fileURL, under: libraryRoot)
                referencesByPath[relativePath] = LocalCoverReference(
                    fileURL: fileURL,
                    relativePath: relativePath,
                    seriesID: seriesID,
                    seriesTitle: manifest.seriesTitle ?? seriesDirectory.lastPathComponent,
                    imageID: cover.providerItemID.flatMap(Int.init),
                    sourceURL: cover.url,
                    language: cover.language,
                    type: cover.role,
                    index: cover.providerVolume.map(displayIndex)
                )
            }
        }
        guard !referencesByPath.isEmpty else {
            throw TrainerError.noLocalManifests(libraryRoot)
        }

        var auditSources: [LocalAuditSource] = []
        for reference in referencesByPath.values {
            guard let data = try? Data(contentsOf: reference.fileURL) else { continue }
            let digest = sha256(data)
            let judgment = judgmentsByHash[digest]
            auditSources.append(LocalAuditSource(
                fileURL: reference.fileURL,
                relativePath: reference.relativePath,
                seriesID: reference.seriesID,
                seriesTitle: reference.seriesTitle,
                imageID: reference.imageID,
                language: reference.language,
                type: reference.type,
                index: reference.index,
                expectedRating: judgment?.rating,
                labelOrigin: judgment == nil ? nil : "user-confirmed",
                sha256: digest
            ))
        }
        return auditSources.sorted { $0.relativePath < $1.relativePath }
    }

    private static func loadJudgments(
        _ explicitURLs: [URL]
    ) throws -> [JudgmentExport] {
        let fileManager = FileManager.default
        let downloads = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        let urls = explicitURLs.isEmpty ? [
            downloads.appendingPathComponent(
                "sable-cover-safety-judgments-2026-08-03.json"
            ),
            downloads.appendingPathComponent(
                "sable-one-piece-safety-judgments-2026-08-03.json"
            ),
        ] : explicitURLs

        return try urls.compactMap { url in
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                if !explicitURLs.isEmpty {
                    throw CocoaError(.fileNoSuchFile)
                }
                return nil
            }
            return try JSONDecoder().decode(
                JudgmentExport.self,
                from: Data(contentsOf: url)
            )
        }
    }

    private static func deduplicatedJudgments(
        _ judgments: [Judgment]
    ) -> [String: Judgment] {
        var result: [String: Judgment] = [:]
        var conflicts = Set<String>()

        for judgment in judgments {
            guard normalizedRating(judgment.rating) != nil,
                  Int(judgment.seriesID) != nil else {
                continue
            }
            if let existing = result[judgment.sha256],
               existing.rating != judgment.rating {
                conflicts.insert(judgment.sha256)
                result.removeValue(forKey: judgment.sha256)
            } else if !conflicts.contains(judgment.sha256) {
                result[judgment.sha256] = judgment
            }
        }

        if !conflicts.isEmpty {
            print(
                "Excluded \(conflicts.count) judgment hashes with conflicting labels"
            )
        }
        return result
    }

    private static func trainingCandidates(
        from judgments: [Judgment]
    ) -> [Candidate] {
        judgments.compactMap { judgment in
            guard let rating = normalizedRating(judgment.rating),
                  let seriesID = Int(judgment.seriesID) else {
                return nil
            }
            let imageURL = URL(string: judgment.imageURL)
            let localURL = imageURL?.isFileURL == true
                && imageURL.map {
                    FileManager.default.fileExists(
                        atPath: $0.path(percentEncoded: false)
                    )
                } == true ? imageURL : nil
            let remoteURL = localURL == nil
                ? imageURL.flatMap { $0.isFileURL ? nil : $0 }
                    ?? judgment.sourceURL.flatMap(URL.init(string:))
                : nil
            guard localURL != nil || remoteURL != nil else { return nil }
            return Candidate(
                seriesID: seriesID,
                seriesTitle: judgment.seriesTitle,
                imageID: fallbackImageID(for: judgment.sha256),
                language: judgment.language ?? "und",
                type: judgment.type ?? "normal",
                index: judgment.index ?? "0",
                rating: rating,
                labelOrigin: "user-confirmed",
                localURL: localURL,
                remoteURL: remoteURL,
                sha256: judgment.sha256,
                isUserConfirmed: true
            )
        }
    }

    private static func deduplicatedCandidates(
        _ candidates: [Candidate]
    ) -> [Candidate] {
        let groups = Dictionary(grouping: candidates, by: \.sha256)
        var excludedConflicts = 0
        var result: [Candidate] = []

        for (_, group) in groups {
            let directJudgments = group.filter { $0.labelOrigin == "user-confirmed" }
            let confirmed = group.filter(\.isUserConfirmed)
            let preferred = !directJudgments.isEmpty
                ? directJudgments
                : (confirmed.isEmpty ? group : confirmed)
            let labels = Set(preferred.map(\.rating))
            guard labels.count == 1 else {
                excludedConflicts += 1
                continue
            }
            result.append(preferred.sorted {
                if ($0.localURL != nil) != ($1.localURL != nil) {
                    return $0.localURL != nil
                }
                return $0.imageID < $1.imageID
            }[0])
        }

        if excludedConflicts > 0 {
            print("Excluded \(excludedConflicts) duplicate images with conflicting labels")
        }
        return result.sorted {
            if $0.seriesID != $1.seriesID { return $0.seriesID < $1.seriesID }
            return $0.imageID < $1.imageID
        }
    }

    private static func selectBalancedDataset(
        from candidates: [Candidate],
        options: Options
    ) throws -> [(candidate: Candidate, partition: Partition)] {
        let onePieceCalibration = candidates.filter {
            $0.seriesID == onePieceCalibrationSeriesID
        }
        let independentCandidates = candidates.filter {
            $0.seriesID != onePieceCalibrationSeriesID
        }
        let byRating = Dictionary(grouping: independentCandidates, by: \.rating)
        var validationMinimums: [String: Int] = [:]
        var trainingReserves: [String: Int] = [:]

        for rating in supportedRatings {
            let values = byRating[rating] ?? []
            let seriesCount = Set(values.map(\.seriesID)).count
            guard values.count >= 12, seriesCount >= 2 else {
                throw TrainerError.incompleteDataset(
                    "\(rating) has \(values.count) unique covers across \(seriesCount) series; at least 12 covers across 2 series are required."
                )
            }
            let desired = min(options.examplesPerRating, values.count)
            validationMinimums[rating] = min(
                max(
                    minimumValidationCoversPerRating,
                    Int((Double(desired) * options.validationFraction).rounded())
                ),
                desired - minimumTrainingCoversPerRating
            )
            trainingReserves[rating] = max(
                minimumTrainingCoversPerRating,
                Int(Double(desired) * 0.55)
            )
        }

        let candidatesBySeries = Dictionary(
            grouping: independentCandidates,
            by: \.seriesID
        )
        var validationSeries = Set<Int>()
        let ratingOrder = ["pornographic", "erotica", "suggestive", "safe"]

        for rating in ratingOrder {
            let target = validationMinimums[rating] ?? 0
            while validationCount(
                rating: rating,
                candidatesBySeries: candidatesBySeries,
                validationSeries: validationSeries
            ) < target || validationSeriesCount(
                rating: rating,
                candidatesBySeries: candidatesBySeries,
                validationSeries: validationSeries
            ) < 2 {
                let currentCandidates = Set((byRating[rating] ?? []).map(\.seriesID))
                    .subtracting(validationSeries)
                    .sorted { stableSeriesOrder($0) < stableSeriesOrder($1) }
                guard let nextSeries = currentCandidates.first(where: {
                    canMoveSeriesToValidation(
                        $0,
                        candidatesBySeries: candidatesBySeries,
                        validationSeries: validationSeries,
                        trainingReserves: trainingReserves
                    )
                }) else {
                    throw TrainerError.incompleteDataset(
                        "Could not make an independent whole-series validation set for \(rating)."
                    )
                }
                validationSeries.insert(nextSeries)
            }
        }

        let validationAvailable = supportedRatings.map { rating in
            (byRating[rating] ?? []).filter {
                validationSeries.contains($0.seriesID)
            }.count
        }.min() ?? 0
        let requestedValidation = max(
            minimumValidationCoversPerRating,
            Int((Double(options.examplesPerRating) * options.validationFraction).rounded())
        )
        let requestedTraining = options.examplesPerRating - requestedValidation
        let commonValidationTarget = min(requestedValidation, validationAvailable)
        let trainingTargets = Dictionary(
            uniqueKeysWithValues: supportedRatings.map { rating in
                let available = (byRating[rating] ?? []).filter {
                    !validationSeries.contains($0.seriesID)
                }.count
                return (rating, min(requestedTraining, available))
            }
        )
        guard trainingTargets.values.allSatisfy({
            $0 >= minimumTrainingCoversPerRating
        }), commonValidationTarget >= minimumValidationCoversPerRating else {
            throw TrainerError.incompleteDataset(
                "The whole-series split did not leave at least "
                    + "\(minimumTrainingCoversPerRating) training and "
                    + "\(minimumValidationCoversPerRating) validation covers per level."
            )
        }
        let targets = Dictionary(
            uniqueKeysWithValues: supportedRatings.map {
                (
                    $0,
                    (
                        training: trainingTargets[
                            $0,
                            default: minimumTrainingCoversPerRating
                        ],
                        validation: commonValidationTarget
                    )
                )
            }
        )
        let trainingDetail = supportedRatings.map {
            "\($0)=\(trainingTargets[$0, default: 0])"
        }.joined(separator: ", ")
        print(
            "Whole-series split training: \(trainingDetail); validation="
                + "\(commonValidationTarget) per level"
        )

        var selected: [(Candidate, Partition)] = []
        for rating in supportedRatings {
            let sorted = (byRating[rating] ?? []).sorted {
                if $0.seriesID != $1.seriesID {
                    return stableSeriesOrder($0.seriesID) < stableSeriesOrder($1.seriesID)
                }
                return $0.sha256 < $1.sha256
            }
            let training = sorted.filter { !validationSeries.contains($0.seriesID) }
            let validation = sorted.filter { validationSeries.contains($0.seriesID) }
            guard let target = targets[rating],
                  training.count >= target.training,
                  validation.count >= target.validation else {
                throw TrainerError.incompleteDataset(
                    "The balanced split fell short for \(rating): training \(training.count), validation \(validation.count)."
                )
            }
            selected.append(contentsOf: roundRobinSamples(
                training,
                count: target.training
            ).map { ($0, .training) })
            selected.append(contentsOf: roundRobinSamples(
                validation,
                count: target.validation
            ).map { ($0, .validation) })
        }

        let onePieceSafe = roundRobinLanguageSamples(
            onePieceCalibration.filter { $0.rating == "safe" },
            count: min(
                options.examplesPerRating,
                onePieceCalibration.filter { $0.rating == "safe" }.count
            )
        )
        let onePieceSuggestive = onePieceCalibration.filter {
            $0.rating == "suggestive"
        }.sorted {
            if $0.language != $1.language { return $0.language < $1.language }
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.imageID < $1.imageID
        }
        selected.append(contentsOf: onePieceSafe.map { ($0, .training) })
        selected.append(contentsOf: onePieceSuggestive.map { ($0, .training) })
        print(
            "Added One Piece training guide: \(onePieceSafe.count) Safe + "
                + "\(onePieceSuggestive.count) Suggestive front covers across "
                + "\(Set((onePieceSafe + onePieceSuggestive).map(\.language)).count) languages"
        )
        return selected
    }

    private static func balancedTrainingSelection(
        _ selected: [(candidate: Candidate, partition: Partition)]
    ) -> [(candidate: Candidate, partition: Partition)] {
        let trainingByRating = Dictionary(
            grouping: selected.filter { $0.partition == .training },
            by: { $0.candidate.rating }
        )
        let target = trainingByRating.values.map(\.count).max() ?? 0
        guard target > 0 else { return selected }

        var result = selected.filter { $0.partition == .validation }
        for rating in supportedRatings {
            let values = trainingByRating[rating] ?? []
            guard !values.isEmpty else { continue }
            for offset in 0..<target {
                result.append(values[offset % values.count])
            }
        }
        let detail = supportedRatings.map {
            "\($0)=\(trainingByRating[$0]?.count ?? 0)->\(target)"
        }.joined(separator: ", ")
        print("Balanced training samples with augmentation: \(detail)")
        return result
    }

    private static func canMoveSeriesToValidation(
        _ seriesID: Int,
        candidatesBySeries: [Int: [Candidate]],
        validationSeries: Set<Int>,
        trainingReserves: [String: Int]
    ) -> Bool {
        let proposed = validationSeries.union([seriesID])
        for rating in supportedRatings {
            let all = candidatesBySeries.values.flatMap { $0 }.filter { $0.rating == rating }
            let trainingCount = all.filter { !proposed.contains($0.seriesID) }.count
            if trainingCount < (trainingReserves[rating] ?? 8) {
                return false
            }
            let trainingSeriesCount = Set(
                all.filter { !proposed.contains($0.seriesID) }.map(\.seriesID)
            ).count
            if trainingSeriesCount < 4 {
                return false
            }
        }
        return true
    }

    private static func validationCount(
        rating: String,
        candidatesBySeries: [Int: [Candidate]],
        validationSeries: Set<Int>
    ) -> Int {
        validationSeries.reduce(into: 0) { count, seriesID in
            count += candidatesBySeries[seriesID]?.filter { $0.rating == rating }.count ?? 0
        }
    }

    private static func validationSeriesCount(
        rating: String,
        candidatesBySeries: [Int: [Candidate]],
        validationSeries: Set<Int>
    ) -> Int {
        validationSeries.filter { seriesID in
            candidatesBySeries[seriesID]?.contains { $0.rating == rating } == true
        }.count
    }

    private static func roundRobinSamples(
        _ candidates: [Candidate],
        count: Int
    ) -> [Candidate] {
        let groups = Dictionary(grouping: candidates, by: \.seriesID)
            .mapValues { $0.sorted { $0.sha256 < $1.sha256 } }
        let seriesIDs = groups.keys.sorted {
            stableSeriesOrder($0) < stableSeriesOrder($1)
        }
        var result: [Candidate] = []
        var round = 0
        while result.count < count {
            var added = false
            for seriesID in seriesIDs where result.count < count {
                guard let values = groups[seriesID], round < values.count else { continue }
                result.append(values[round])
                added = true
            }
            guard added else { break }
            round += 1
        }
        return result
    }

    private static func roundRobinLanguageSamples(
        _ candidates: [Candidate],
        count: Int
    ) -> [Candidate] {
        let groups = Dictionary(grouping: candidates) {
            $0.language.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }.mapValues {
            $0.sorted {
                if $0.index != $1.index { return $0.index < $1.index }
                return $0.sha256 < $1.sha256
            }
        }
        let languages = groups.keys.sorted()
        var result: [Candidate] = []
        var round = 0
        while result.count < count {
            var added = false
            for language in languages where result.count < count {
                guard let values = groups[language], round < values.count else {
                    continue
                }
                result.append(values[round])
                added = true
            }
            guard added else { break }
            round += 1
        }
        return result
    }

    private static func materializeDataset(
        _ selected: [(candidate: Candidate, partition: Partition)],
        at datasetDirectory: URL,
        client: HTTPClient
    ) async throws -> [ManifestRecord] {
        var manifest: [ManifestRecord] = []

        for (offset, item) in selected.enumerated() {
            let candidate = item.candidate
            let partitionName = item.partition.rawValue
            let destination = datasetDirectory
                .appendingPathComponent(partitionName, isDirectory: true)
                .appendingPathComponent(candidate.rating, isDirectory: true)
                .appendingPathComponent(
                    "\(candidate.seriesID)-\(candidate.imageID)-"
                        + "\(candidate.sha256.prefix(12))-\(offset).jpg"
                )
            do {
                let sourceData: Data
                if let localURL = candidate.localURL {
                    sourceData = try Data(contentsOf: localURL)
                } else if let remoteURL = candidate.remoteURL {
                    sourceData = try await client.data(from: remoteURL)
                } else {
                    continue
                }
                guard let jpegData = normalizedJPEGData(sourceData) else {
                    print("Skipped undecodable image \(candidate.imageID)")
                    continue
                }
                try jpegData.write(to: destination, options: .atomic)
                manifest.append(ManifestRecord(
                    seriesID: candidate.seriesID,
                    seriesTitle: candidate.seriesTitle,
                    imageID: candidate.imageID,
                    language: candidate.language,
                    type: candidate.type,
                    index: candidate.index,
                    rating: candidate.rating,
                    labelOrigin: candidate.labelOrigin,
                    partition: item.partition,
                    source: candidate.localURL == nil ? "mangabaka-api" : "local-library",
                    sha256: candidate.sha256
                ))
            } catch {
                print("Skipped image \(candidate.imageID): \(error.localizedDescription)")
            }
            if (offset + 1).isMultiple(of: 50) {
                print("Prepared \(offset + 1) of \(selected.count) training covers")
            }
        }
        return manifest
    }

    private static func normalizedJPEGData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_048,
                ] as CFDictionary
              ) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func auditLocalCovers(
        modelURL: URL,
        sources: [LocalAuditSource],
        outputURL: URL
    ) throws {
        let compiledURL = try MLModel.compileModel(at: modelURL)
        defer { try? FileManager.default.removeItem(at: compiledURL) }
        let coreModel = try MLModel(contentsOf: compiledURL)
        let visionModel = try VNCoreMLModel(for: coreModel)
        var predictionsByHash: [String: Prediction] = [:]
        let uniqueSources = Dictionary(
            grouping: sources,
            by: \.sha256
        ).compactMap { $0.value.first }

        for (offset, source) in uniqueSources.enumerated() {
            let prediction: Prediction = try autoreleasepool {
                let request = VNCoreMLRequest(model: visionModel)
                request.imageCropAndScaleOption = .centerCrop
                let handler = VNImageRequestHandler(url: source.fileURL, options: [:])
                try handler.perform([request])
                guard let observations = request.results as? [VNClassificationObservation],
                      let best = observations.first else {
                    return Prediction(rating: "suggestive", confidence: 0)
                }
                return Prediction(
                    rating: normalizedRating(best.identifier) ?? "suggestive",
                    confidence: Double(best.confidence)
                )
            }
            predictionsByHash[source.sha256] = prediction
            if (offset + 1).isMultiple(of: 100) {
                print("Audited \(offset + 1) of \(uniqueSources.count) unique local covers")
            }
        }

        let records = sources.compactMap { source -> AuditRecord? in
            guard let prediction = predictionsByHash[source.sha256] else { return nil }
            let differs = source.expectedRating.map { $0 != prediction.rating } ?? false
            let raises = source.expectedRating.map {
                ratingRank(prediction.rating) > ratingRank($0)
            } ?? false
            return AuditRecord(
                path: source.relativePath,
                seriesID: source.seriesID,
                seriesTitle: source.seriesTitle,
                imageID: source.imageID,
                language: source.language,
                type: source.type,
                index: source.index,
                expectedRating: source.expectedRating,
                labelOrigin: source.labelOrigin,
                predictedRating: prediction.rating,
                confidence: prediction.confidence,
                differsFromSavedRating: differs,
                wouldRaiseSavedRating: raises,
                sha256: source.sha256
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(records).write(to: outputURL, options: .atomic)

        let labeled = records.filter { $0.expectedRating != nil }
        let mismatches = labeled.filter(\.differsFromSavedRating)
        let raises = labeled.filter(\.wouldRaiseSavedRating)
        print(
            "Audited all \(records.count) downloaded cover records: "
                + "\(mismatches.count) label disagreements, \(raises.count) stricter suggestions"
        )
        print("Wrote read-only audit: \(outputURL.path(percentEncoded: false))")
    }

    private static func series(id: Int, client: HTTPClient) async throws -> Series {
        let url = URL(string: "https://api.mangabaka.org/v1/series/\(id)")!
        return try await client.decode(
            SeriesEnvelope.self,
            from: url,
            cacheKey: "series-\(id).json"
        ).data
    }

    private static func images(
        seriesID: Int,
        client: HTTPClient
    ) async throws -> [ImageRecord] {
        var page = 1
        var records: [ImageRecord] = []
        while true {
            let url = URL(
                string: "https://api.mangabaka.org/v1/series/\(seriesID)/images?limit=50&page=\(page)"
            )!
            let envelope = try await client.decode(
                ImagesEnvelope.self,
                from: url,
                cacheKey: "images-\(seriesID)-\(page).json"
            )
            records.append(contentsOf: envelope.data)
            guard envelope.pagination.next != nil else { return records }
            page += 1
        }
    }

    private static func normalizedRating(_ value: String?) -> String? {
        guard let value else { return nil }
        let rating = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedRatings.contains(rating) ? rating : nil
    }

    private static func ratingRank(_ rating: String) -> Int {
        supportedRatings.firstIndex(of: rating) ?? 1
    }

    private static func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "https://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func relativePath(for url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func displayIndex(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func stableSeriesOrder(_ id: Int) -> UInt64 {
        UInt64(bitPattern: Int64(id)) &* 2_654_435_761
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fallbackImageID(for digest: String) -> Int {
        let prefix = UInt64(digest.prefix(8), radix: 16) ?? 0
        return -Int(prefix) - 1
    }

    private static func manifestCounts(
        _ manifest: [ManifestRecord]
    ) -> [String: [String: Int]] {
        var counts: [String: [String: Int]] = [:]
        for item in manifest {
            counts[item.partition.rawValue, default: [:]][item.rating, default: 0] += 1
        }
        return counts
    }

    private static func printCandidateCounts(
        _ candidates: [Candidate],
        heading: String
    ) {
        let counts = Dictionary(grouping: candidates, by: \.rating).mapValues(\.count)
        let seriesCounts = Dictionary(grouping: candidates, by: \.rating)
            .mapValues { Set($0.map(\.seriesID)).count }
        let detail = supportedRatings.map {
            "\($0)=\(counts[$0, default: 0]) across \(seriesCounts[$0, default: 0]) series"
        }
        print("\(heading): \(detail.joined(separator: ", "))")
    }

    private static func printCounts(_ counts: [String: [String: Int]]) {
        for partition in [Partition.training, .validation] {
            let values = supportedRatings.map {
                "\($0)=\(counts[partition.rawValue]?[$0, default: 0] ?? 0)"
            }
            print("\(partition.rawValue): \(values.joined(separator: ", "))")
        }
    }

    private static func parseOptions() -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--repo-root":
                if let path = arguments.first {
                    options.repoRoot = URL(fileURLWithPath: path, isDirectory: true)
                    arguments.removeFirst()
                }
            case "--library-root":
                if let path = arguments.first {
                    options.libraryRoot = URL(fileURLWithPath: path, isDirectory: true)
                    arguments.removeFirst()
                }
            case "--judgments":
                if let path = arguments.first {
                    options.judgmentURLs.append(URL(fileURLWithPath: path))
                    arguments.removeFirst()
                }
            case "--examples-per-rating":
                if let value = arguments.first.flatMap(Int.init) {
                    options.examplesPerRating = max(24, value)
                    arguments.removeFirst()
                }
            case "--promote":
                options.promotesValidatedModel = true
            default:
                break
            }
        }
        return options
    }
}

do {
    try await CoverSafetyTrainer.run()
} catch {
    fputs("Cover safety training stopped: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
