//
//  SableLibraryCore.swift
//  Sable's Library
//

import Combine
import Foundation

private final class SableLibraryConfigBundleToken {}

struct SableLibraryProgressSnapshot: Sendable, Equatable {
    var title: String
    var message: String
    var completedUnitCount: Int
    var totalUnitCount: Int

    var clampedCompletedUnitCount: Int {
        min(max(0, completedUnitCount), max(0, totalUnitCount))
    }

    var clampedTotalUnitCount: Int {
        max(0, totalUnitCount)
    }

    var fraction: Double? {
        let total = clampedTotalUnitCount
        guard total > 0 else { return nil }
        return Double(clampedCompletedUnitCount) / Double(total)
    }

    var countText: String {
        "\(clampedCompletedUnitCount) of \(clampedTotalUnitCount)"
    }

    var percentageText: String? {
        guard let fraction else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }
}

nonisolated enum SableLibraryWorkTiming {
    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        let hours = rounded / 3_600
        let minutes = (rounded % 3_600) / 60
        let remainingSeconds = rounded % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    nonisolated static func elapsed(since startedAt: Date, now: Date = Date()) -> String {
        "Elapsed \(duration(max(0, now.timeIntervalSince(startedAt))))"
    }

    nonisolated static func summary(
        startedAt: Date,
        completedCount: Int,
        totalCount: Int? = nil,
        unit: String,
        now: Date = Date()
    ) -> String {
        let elapsedSeconds = max(0, now.timeIntervalSince(startedAt))
        guard completedCount > 0, elapsedSeconds > 0 else {
            return "\(elapsed(since: startedAt, now: now))."
        }

        let ratePerSecond = Double(completedCount) / elapsedSeconds
        let rateText: String
        if ratePerSecond >= 1 {
            rateText = "\(String(format: "%.1f", ratePerSecond)) \(unit)/s"
        } else {
            rateText = "\(String(format: "%.1f", ratePerSecond * 60)) \(unit)/min"
        }

        var parts = [
            elapsed(since: startedAt, now: now),
            rateText
        ]
        if let totalCount {
            let remainingCount = max(0, totalCount - completedCount)
            if remainingCount > 0, ratePerSecond > 0 {
                parts.append("about \(duration(Double(remainingCount) / ratePerSecond)) remaining")
            }
        }
        return parts.joined(separator: "; ") + "."
    }
}

nonisolated enum SableLibraryAdaptiveWorkBudget {
    nonisolated static func parallelism(
        minimum: Int,
        multiplier: Int,
        cap: Int,
        itemCount: Int? = nil
    ) -> Int {
        let processorCount = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let adaptiveCount = min(cap, max(minimum, processorCount * multiplier))
        guard let itemCount else { return adaptiveCount }
        return max(1, min(adaptiveCount, itemCount))
    }
}

private struct SableLibraryMoveApplyBatch {
    var applied: [PlannedMove]
    var alreadyAtDestination: [PlannedMove]
    var skipped: [String]
    var removedEmptyFolders: [String]
}

private struct SableLibraryScanCacheEntry {
    var items: [LibraryItem]
    var warnings: [String]
    var createdAt: Date
}

enum SableLibraryProviderRequestContext {
    @TaskLocal static var maximumCacheAge: TimeInterval?
}

actor SableLibraryProviderResponseCache {
    static let shared = SableLibraryProviderResponseCache()

    private struct Entry {
        var data: Data
        var createdAt: Date
        var expiresAt: Date
    }

    private let maximumTotalBytes: Int
    private let maximumEntryBytes: Int
    private let maximumEntryCount: Int
    private var entries: [String: Entry] = [:]
    private var totalByteCount = 0

    init(
        maximumTotalBytes: Int = 32 * 1_024 * 1_024,
        maximumEntryBytes: Int = 8 * 1_024 * 1_024,
        maximumEntryCount: Int = 128
    ) {
        self.maximumTotalBytes = max(0, maximumTotalBytes)
        self.maximumEntryBytes = max(0, maximumEntryBytes)
        self.maximumEntryCount = max(0, maximumEntryCount)
    }

    nonisolated static func key(provider: SableLibraryMetadataProvider, url: URL) -> String {
        "\(provider.rawValue)|\(url.absoluteString)"
    }

    func cachedData(
        for key: String,
        maximumAge: TimeInterval? = nil,
        now: Date = Date()
    ) -> Data? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now else {
            removeEntry(for: key)
            return nil
        }
        if let maximumAge,
           now.timeIntervalSince(entry.createdAt) > max(0, maximumAge) {
            return nil
        }
        return entry.data
    }

    func store(_ data: Data, for key: String, ttl: TimeInterval, now: Date = Date()) {
        guard ttl > 0,
              maximumEntryCount > 0,
              data.count <= maximumEntryBytes,
              data.count <= maximumTotalBytes else {
            return
        }
        removeEntry(for: key)
        removeExpiredEntries(now: now)
        entries[key] = Entry(
            data: data,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
        totalByteCount += data.count
        trimToLimits()
    }

    private func removeExpiredEntries(now: Date) {
        let expiredKeys = entries.compactMap { key, entry in
            entry.expiresAt <= now ? key : nil
        }
        for key in expiredKeys {
            removeEntry(for: key)
        }
    }

    private func trimToLimits() {
        while entries.count > maximumEntryCount || totalByteCount > maximumTotalBytes {
            guard let oldestKey = entries.min(by: {
                $0.value.createdAt < $1.value.createdAt
            })?.key else {
                break
            }
            removeEntry(for: oldestKey)
        }
    }

    private func removeEntry(for key: String) {
        guard let removed = entries.removeValue(forKey: key) else { return }
        totalByteCount = max(0, totalByteCount - removed.data.count)
    }
}

nonisolated final class SableLibraryService: ObservableObject, @unchecked Sendable {
    private static let scanCacheLifetime: TimeInterval = 120
    let fileManager = FileManager.default
    private let progressLock = NSLock()
    private var lastProgressDate = Date.distantPast
    private var lastProgressSnapshotDate = Date.distantPast
    private var lastProgressSnapshot: SableLibraryProgressSnapshot?
    private let scanCacheLock = NSLock()
    private var scanCache: [String: SableLibraryScanCacheEntry] = [:]

    var progressHandler: (@Sendable (String) -> Void)?
    var progressSnapshotHandler: (@Sendable (SableLibraryProgressSnapshot?) -> Void)?

    func reportProgress(_ message: String) {
        let now = Date()
        progressLock.lock()
        let shouldSend = shouldAlwaysReport(message) || now.timeIntervalSince(lastProgressDate) >= 0.75
        if shouldSend {
            lastProgressDate = now
        }
        progressLock.unlock()

        if shouldSend {
            progressHandler?(message)
        }
    }

    func reportProgressSnapshot(_ snapshot: SableLibraryProgressSnapshot?) {
        let now = Date()
        progressLock.lock()
        let shouldSend: Bool
        if let snapshot {
            let titleChanged = snapshot.title != lastProgressSnapshot?.title
            let totalChanged = snapshot.totalUnitCount != lastProgressSnapshot?.totalUnitCount
            let completed = snapshot.clampedTotalUnitCount > 0
                && snapshot.clampedCompletedUnitCount >= snapshot.clampedTotalUnitCount
            shouldSend = titleChanged
                || totalChanged
                || completed
                || now.timeIntervalSince(lastProgressSnapshotDate) >= 0.25
            if shouldSend {
                lastProgressSnapshot = snapshot
                lastProgressSnapshotDate = now
            }
        } else {
            shouldSend = lastProgressSnapshot != nil
            lastProgressSnapshot = nil
            lastProgressSnapshotDate = now
        }
        progressLock.unlock()

        if shouldSend {
            progressSnapshotHandler?(snapshot)
        }
    }

    func clearScanCache() {
        scanCacheLock.lock()
        scanCache.removeAll()
        scanCacheLock.unlock()
    }

    func invalidateScanCache(for root: URL? = nil) {
        scanCacheLock.lock()
        if let root {
            let path = root.standardizedFileURL.path(percentEncoded: false)
            scanCache = scanCache.filter { !$0.key.hasPrefix(path) }
        } else {
            scanCache.removeAll()
        }
        scanCacheLock.unlock()
    }

    func cachedItems(for key: String) -> [LibraryItem]? {
        scanCacheLock.lock()
        let items: [LibraryItem]?
        if let entry = scanCache[key],
           Date().timeIntervalSince(entry.createdAt) <= Self.scanCacheLifetime {
            items = entry.items
        } else {
            scanCache.removeValue(forKey: key)
            items = nil
        }
        scanCacheLock.unlock()
        return items
    }

    func cachedScanWarnings(for key: String) -> [String] {
        scanCacheLock.lock()
        let warnings: [String]
        if let entry = scanCache[key],
           Date().timeIntervalSince(entry.createdAt) <= Self.scanCacheLifetime {
            warnings = entry.warnings
        } else {
            scanCache.removeValue(forKey: key)
            warnings = []
        }
        scanCacheLock.unlock()
        return warnings
    }

    func storeCachedItems(_ items: [LibraryItem], warnings: [String] = [], for key: String) {
        scanCacheLock.lock()
        scanCache[key] = SableLibraryScanCacheEntry(
            items: items,
            warnings: warnings,
            createdAt: Date()
        )
        scanCacheLock.unlock()
    }

    func localFileSnapshotSignature(items: [LibraryItem]) -> String {
        let snapshotText = items
            .map { "\($0.relativePath)|\($0.fileSize)" }
            .sorted()
            .joined(separator: "\n")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in snapshotText.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    func scanCacheKey(root: URL, config: SableLibraryConfig) -> String {
        [
            root.standardizedFileURL.path(percentEncoded: false),
            config.bookExtensions.sorted().joined(separator: ","),
            config.videoExtensions.sorted().joined(separator: ","),
            config.packageExtensions.sorted().joined(separator: ","),
            config.ignoreNames.sorted().joined(separator: ","),
            config.reportFolderName,
            config.duplicateFolderName,
            config.missingNumberFolderName
        ].joined(separator: "|")
    }

    func checkForCancellation() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    func checkForCancellation(at index: Int, every interval: Int = 100) throws {
        if index.isMultiple(of: interval) {
            try checkForCancellation()
        }
    }

    func currentConfig() -> SableLibraryConfig {
        loadConfig()
    }

    func applyPlannedMovesWithApplied(
        root: URL,
        moves: [PlannedMove],
        reportTitle: String,
        reportName: String,
        cleanupEmptySourceFolders: Bool = false
    ) async -> LibraryFileMoveApplyResult {
        let config = loadConfig()
        let batch: SableLibraryMoveApplyBatch
        do {
            batch = try applyMoves(
                moves,
                root: root,
                config: config,
                cleanupEmptySourceFolders: cleanupEmptySourceFolders
            )
        } catch {
            return LibraryFileMoveApplyResult(applied: [], skipped: [error.localizedDescription], report: "Error: \(error.localizedDescription)", changedFiles: false)
        }

        let applied = batch.applied
        let skipped = batch.skipped
        var report = cleanupReport(title: reportTitle, moves: applied)

        if !batch.alreadyAtDestination.isEmpty {
            report += "\n\nAlready sorted: \(batch.alreadyAtDestination.count)."
            report += "\nThe requested destination already exists and the old source path is gone. Sable treated these stale rows as complete instead of failures."
        }
        let collisionCount = applied.filter { $0.reason == PlannedMove.manualNameCollisionReason }.count
        if collisionCount > 0 {
            report += "\n\nReviewed name collisions: \(collisionCount). Existing destination item(s) were moved to \(config.duplicateFolderName) before replacement."
        }
        let mergeCount = applied.filter { $0.reason == PlannedMove.manualFolderMergeReason }.count
        if mergeCount > 0 {
            report += "\n\nMerged folder contents: \(mergeCount) item(s) were moved into existing destination folder(s)."
        }
        let duplicateReviewCount = applied.filter { $0.reason == PlannedMove.duplicateReviewReason }.count
        if duplicateReviewCount > 0 {
            report += "\n\nDuplicate review: \(duplicateReviewCount) extra copy item(s) were moved to \(config.duplicateFolderName)."
        }
        if !batch.removedEmptyFolders.isEmpty {
            report += "\n\nRemoved empty source folders: \(batch.removedEmptyFolders.count)."
            report += "\n" + batch.removedEmptyFolders.map { "- \($0)" }.joined(separator: "\n")
        }
        if !skipped.isEmpty {
            report += "\n\nSkipped \(skipped.count) move(s). The rest of the safe batch was allowed to continue:"
            report += "\n" + skipped.map { "- \($0)" }.joined(separator: "\n")
        }

        if !applied.isEmpty {
            do {
                try saveUndoPlan(applied, root: root, config: config)
            } catch {
                let changeVerb = applied.count == 1 ? "was" : "were"
                report += "\n\nRecovery warning: \(applied.count) change\(applied.count == 1 ? "" : "s") \(changeVerb) applied, but Sable could not save the undo plan: \(error.localizedDescription)"
            }
        }

        do {
            try writeReport(report, named: reportName, root: root, config: config)
        } catch {
            let changeSummary = applied.isEmpty
                ? "No files were changed"
                : "\(applied.count) change\(applied.count == 1 ? "" : "s") \(applied.count == 1 ? "was" : "were") applied"
            report += "\n\nReceipt warning: \(changeSummary), but Sable could not save this receipt: \(error.localizedDescription)"
        }

        return LibraryFileMoveApplyResult(
            applied: applied,
            skipped: skipped,
            report: report,
            changedFiles: !applied.isEmpty || !batch.removedEmptyFolders.isEmpty
        )
    }

    func removeCheckedEmptySortingFolders(
        root: URL,
        relativePaths: [String],
        reportTitle: String,
        reportName: String
    ) async -> LibraryEmptyFolderCleanupApplyResult {
        let config = loadConfig()
        var removed: [String] = []
        var skipped: [String] = []
        let orderedPaths = Array(Set(relativePaths)).sorted { lhs, rhs in
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        for relativePath in orderedPaths {
            do {
                try checkForCancellation()
                guard isRecognizedEmptySortingFolderPath(relativePath) else {
                    skipped.append("\(relativePath): not a recognized SSS shelf or subshelf path")
                    continue
                }

                let folder = root.appendingPathComponent(relativePath, isDirectory: true)
                let folderPath = folder.path(percentEncoded: false)
                guard fileManager.fileExists(atPath: folderPath) else {
                    skipped.append("\(relativePath): folder was already absent")
                    continue
                }

                try removeEmptyFolderIfSafe(folder, root: root)
                if fileManager.fileExists(atPath: folderPath) {
                    skipped.append("\(relativePath): folder now contains real files or folders")
                } else {
                    removed.append(relativePath)
                }
            } catch is CancellationError {
                skipped.append("\(relativePath): stopped before cleanup")
                break
            } catch {
                skipped.append("\(relativePath): \(error.localizedDescription)")
            }
        }

        if !removed.isEmpty {
            invalidateScanCache(for: root)
        }

        var report = reportTitle
        report += "\n\nRemoved empty sorting folders: \(removed.count)."
        if !removed.isEmpty {
            report += "\n" + removed.map { "- \($0)" }.joined(separator: "\n")
        }
        if !skipped.isEmpty {
            report += "\n\nSkipped \(skipped.count) folder(s):"
            report += "\n" + skipped.map { "- \($0)" }.joined(separator: "\n")
        }

        do {
            try writeReport(report, named: reportName, root: root, config: config)
        } catch {
            report += "\n\nReceipt warning: cleanup finished, but Sable could not save this receipt: \(error.localizedDescription)"
        }

        return LibraryEmptyFolderCleanupApplyResult(
            removed: removed,
            skipped: skipped,
            report: report
        )
    }

    func restoreLastApply(root: URL) async -> LibraryApplyResult {
        do {
            let config = loadConfig()
            let undoURL = reportDirectory(root: root, config: config).appendingPathComponent(config.reports.undoPlanJSON)
            let data = try Data(contentsOf: undoURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let plan = try decoder.decode(UndoPlan.self, from: data)

            var restored: [PlannedMove] = []
            var skipped: [PlannedMove] = []
            var removedEmptyFolders: [String] = []

            for move in plan.moves.reversed() {
                try checkForCancellation()
                reportProgress("Restoring change: \(move.toPath)")

                let source = root.appendingPathComponent(move.toPath)
                let target = root.appendingPathComponent(move.fromPath)
                let sourcePath = source.path(percentEncoded: false)
                let targetPath = target.path(percentEncoded: false)

                guard fileManager.fileExists(atPath: sourcePath),
                      !fileManager.fileExists(atPath: targetPath),
                      sourcePath != targetPath else {
                    skipped.append(move)
                    continue
                }

                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: target)
                removedEmptyFolders.append(contentsOf: try removeEmptyAncestorFoldersAfterMove(
                    startingAt: source.deletingLastPathComponent(),
                    root: root
                ))
                restored.append(PlannedMove(reason: "restore: \(move.reason)", fromPath: move.toPath, toPath: move.fromPath))
            }

            if !restored.isEmpty {
                invalidateScanCache(for: root)
            }

            var report = restoreReport(createdAt: plan.createdAt, restored: restored, skipped: skipped)
            if !removedEmptyFolders.isEmpty {
                report += "\n\nRemoved empty folders left by the restored layout: \(removedEmptyFolders.count)."
                report += "\n" + removedEmptyFolders.map { "- \($0)" }.joined(separator: "\n")
            }
            try writeReport(report, named: config.reports.restoreReport, root: root, config: config)
            let receiptPath = reportDirectory(root: root, config: config)
                .appendingPathComponent(config.reports.restoreReport)
                .path(percentEncoded: false)

            return LibraryApplyResult(
                appliedCount: restored.count,
                skippedCount: skipped.count,
                receiptPath: receiptPath,
                summary: report
            )
        } catch {
            return LibraryApplyResult(
                appliedCount: 0,
                skippedCount: 0,
                receiptPath: nil,
                summary: "Restore could not run: \(error.localizedDescription)"
            )
        }
    }

    private func shouldAlwaysReport(_ message: String) -> Bool {
        message.hasPrefix("Inspect Library")
            || message.hasPrefix("Preparing Library")
            || message.hasPrefix("Prepared Library")
            || message.hasPrefix("Restoring")
            || message.hasPrefix("Step")
            || message.hasPrefix("Started")
            || message.hasPrefix("Finished")
            || message.hasPrefix("Failed")
            || message.hasPrefix("Stopped")
            || message == "Stop Requested"
    }

    private func loadConfig() -> SableLibraryConfig {
        let bundles = [Bundle.main, Bundle(for: SableLibraryConfigBundleToken.self)]
            + Bundle.allBundles
            + Bundle.allFrameworks
        for bundle in bundles {
            guard let url = bundle.url(forResource: "sable_library_config", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(SableLibraryConfig.self, from: data) else {
                continue
            }
            return config
        }
        return SableLibraryConfig.fallback
    }

    private func applyMoves(
        _ moves: [PlannedMove],
        root: URL,
        config: SableLibraryConfig,
        cleanupEmptySourceFolders: Bool
    ) throws -> SableLibraryMoveApplyBatch {
        var applied: [PlannedMove] = []
        var alreadyAtDestination: [PlannedMove] = []
        var skipped: [String] = []
        var removedEmptyFolders: [String] = []
        let orderedMoves = moves.sorted { lhs, rhs in
            let lhsDepth = lhs.fromPath.split(separator: "/").count
            let rhsDepth = rhs.fromPath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth > rhsDepth
            }

            let lhsIsDirectory = isDirectory(lhs.fromPath, root: root)
            let rhsIsDirectory = isDirectory(rhs.fromPath, root: root)
            if lhsIsDirectory != rhsIsDirectory {
                return !lhsIsDirectory && rhsIsDirectory
            }

            return lhs.fromPath.localizedStandardCompare(rhs.fromPath) == .orderedAscending
        }

        let totalCount = orderedMoves.count

        for (index, move) in orderedMoves.enumerated() {
            let completedCount = index + 1
            do {
                try checkForCancellation()
                reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: "Applying file changes",
                    message: "Applying change \(completedCount) of \(totalCount): \(move.fromPath)",
                    completedUnitCount: index,
                    totalUnitCount: totalCount
                ))
                defer {
                    reportProgressSnapshot(SableLibraryProgressSnapshot(
                        title: "Applying file changes",
                        message: "Checked change \(completedCount) of \(totalCount): \(move.fromPath)",
                        completedUnitCount: completedCount,
                        totalUnitCount: totalCount
                    ))
                }
                reportProgress("Applying change: \(move.fromPath)")

                let source = root.appendingPathComponent(move.fromPath)
                let target = root.appendingPathComponent(move.toPath)
                let sourcePath = source.path(percentEncoded: false)
                let sourceWasDirectory = isDirectory(move.fromPath, root: root)
                var finalTarget = target
                var finalToPath = move.toPath
                let targetPath = target.path(percentEncoded: false)

                guard fileManager.fileExists(atPath: sourcePath) else {
                    if fileManager.fileExists(atPath: targetPath) {
                        alreadyAtDestination.append(move)
                        if cleanupEmptySourceFolders {
                            removedEmptyFolders.append(contentsOf: try removeEmptyAncestorFoldersAfterMove(
                                startingAt: source.deletingLastPathComponent(),
                                root: root
                            ))
                        }
                        continue
                    }
                    skipped.append("\(move.fromPath): source file was missing")
                    continue
                }
                guard sourcePath != targetPath else {
                    skipped.append("\(move.fromPath): source and destination were the same")
                    continue
                }

                if move.reason == PlannedMove.manualFolderMergeReason {
                    let merged = try mergeFolderContents(source: source, target: target, root: root, reason: move.reason)
                    if merged.isEmpty {
                        skipped.append("\(move.fromPath): folder merge had no files to move")
                    } else {
                        applied.append(contentsOf: merged)
                    }
                    continue
                }

                if fileManager.fileExists(atPath: targetPath) {
                    if move.reason == PlannedMove.manualNameCollisionReason {
                        let duplicateFolder = root.appendingPathComponent(config.duplicateFolderName, isDirectory: true)
                        try fileManager.createDirectory(at: duplicateFolder, withIntermediateDirectories: true)
                        let duplicateTarget = uniqueURL(duplicateFolder.appendingPathComponent(target.lastPathComponent), root: root)
                        try fileManager.moveItem(at: target, to: duplicateTarget)
                    } else if move.reason == PlannedMove.duplicateReviewReason {
                        finalTarget = uniqueURL(target, root: root)
                        finalToPath = relativePath(for: finalTarget, root: root)
                    } else {
                        skipped.append("\(move.fromPath): destination already exists at \(move.toPath)")
                        continue
                    }
                }

                try fileManager.createDirectory(at: finalTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: finalTarget)
                if cleanupEmptySourceFolders, sourceWasDirectory {
                    removedEmptyFolders.append(contentsOf: try removeEmptyAncestorFoldersAfterMove(
                        startingAt: source.deletingLastPathComponent(),
                        root: root
                    ))
                }
                if move.reason == PlannedMove.volumeWrapperFolderReason
                    || move.reason == PlannedMove.rawUpdateFolderReason {
                    try removeEmptyFolderIfSafe(source.deletingLastPathComponent(), root: root)
                }
                applied.append(PlannedMove(reason: move.reason, fromPath: move.fromPath, toPath: finalToPath))
                if move.reason == PlannedMove.rawVideoNumberedWrapperReason,
                   let archivedFolderMove = try archiveGeneratedVideoWrapperSidecarsIfSafe(
                    source.deletingLastPathComponent(),
                    root: root,
                    config: config,
                    reason: move.reason
                   ) {
                    applied.append(archivedFolderMove)
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                skipped.append("\(move.fromPath): \(error.localizedDescription)")
                continue
            }
        }

        if !applied.isEmpty {
            invalidateScanCache(for: root)
        }
        return SableLibraryMoveApplyBatch(
            applied: applied,
            alreadyAtDestination: alreadyAtDestination,
            skipped: skipped,
            removedEmptyFolders: Array(Set(removedEmptyFolders)).sorted()
        )
    }

    private func archiveGeneratedVideoWrapperSidecarsIfSafe(
        _ folder: URL,
        root: URL,
        config: SableLibraryConfig,
        reason: String
    ) throws -> PlannedMove? {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let folderURL = folder.standardizedFileURL
        let folderPath = folderURL.path(percentEncoded: false)
        guard folderPath != rootPath,
              folderPath.hasPrefix(rootPrefix),
              fileManager.fileExists(atPath: folderPath) else {
            return nil
        }

        let children = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard !children.isEmpty else {
            try removeEmptyFolderIfSafe(folderURL, root: root)
            return nil
        }

        let allowedNames: Set<String> = [config.animeInfoFileName, ".plexmatch", ".DS_Store"]
        guard children.allSatisfy({ allowedNames.contains($0.lastPathComponent) }),
              children.contains(where: { $0.lastPathComponent == config.animeInfoFileName }) else {
            return nil
        }

        let animeInfoURL = folderURL.appendingPathComponent(config.animeInfoFileName)
        guard generatedLocalWatchingSidecarCanBeRetired(animeInfoURL) else {
            return nil
        }

        let sourceRelativePath = relativePath(for: folderURL, root: root)
        let archiveRoot = root
            .appendingPathComponent(config.reportFolderName, isDirectory: true)
            .appendingPathComponent("Retired Video Sidecars", isDirectory: true)
        let archiveTarget = uniqueURL(archiveRoot.appendingPathComponent(sourceRelativePath, isDirectory: true), root: root)
        try fileManager.createDirectory(at: archiveTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: folderURL, to: archiveTarget)
        return PlannedMove(
            reason: reason,
            fromPath: sourceRelativePath,
            toPath: relativePath(for: archiveTarget, root: root)
        )
    }

    private func generatedLocalWatchingSidecarCanBeRetired(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let sidecar = object as? [String: Any] else {
            return false
        }

        let source = (sidecar["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mediaType = (sidecar["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ids = sidecar["ids"] as? [String: Any] ?? [:]
        let sable = sidecar["_sable"] as? [String: Any] ?? [:]
        let sidecarName = (sable["sidecar"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return source == "local"
            && (mediaType == nil || mediaType == "unknownvideo" || mediaType == "unknown video")
            && ids.isEmpty
            && (sidecarName == nil || sidecarName == url.lastPathComponent)
    }

    private func removeEmptyFolderIfSafe(_ folder: URL, root: URL) throws {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let folderURL = folder.standardizedFileURL
        let folderPath = folderURL.path(percentEncoded: false)
        guard folderPath != rootPath,
              folderPath.hasPrefix(rootPrefix),
              fileManager.fileExists(atPath: folderPath) else {
            return
        }

        let children = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard children.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else { return }
        for child in children {
            try fileManager.removeItem(at: child)
        }
        try fileManager.removeItem(at: folderURL)
    }

    private func isRecognizedEmptySortingFolderPath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count == 2 || components.count == 3,
              let name = components.last else {
            return false
        }
        let codeParts = name
            .components(separatedBy: " - ")
            .first?
            .split(separator: ".")
            .map(String.init) ?? []
        guard !codeParts.isEmpty,
              codeParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return false
        }
        return components.count == 2 ? codeParts.count == 1 : codeParts.count == 2
    }

    private func removeEmptyAncestorFoldersAfterMove(
        startingAt folder: URL,
        root: URL
    ) throws -> [String] {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var current = folder.standardizedFileURL
        var removed: [String] = []

        while true {
            let currentPath = current.path(percentEncoded: false)
            guard currentPath != rootPath,
                  currentPath.hasPrefix(rootPrefix) else {
                break
            }

            let relative = relativePath(for: current, root: root)
            // Preserve collection roots such as Manga, Light Novels, Books, and TV.
            guard relative.split(separator: "/").count > 1 else { break }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: currentPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                current = current.deletingLastPathComponent()
                continue
            }

            let children = try fileManager.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: nil,
                options: []
            )
            guard children.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else { break }
            for child in children {
                try fileManager.removeItem(at: child)
            }
            try fileManager.removeItem(at: current)
            removed.append(relative)
            current = current.deletingLastPathComponent()
        }

        return removed
    }

    private func isDirectory(_ relativePath: String, root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: root.appendingPathComponent(relativePath).path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func mergeFolderContents(source: URL, target: URL, root: URL, reason: String) throws -> [PlannedMove] {
        let sourcePath = source.path(percentEncoded: false)
        let targetPath = target.path(percentEncoded: false)
        var sourceIsDirectory: ObjCBool = false
        var targetIsDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: sourcePath, isDirectory: &sourceIsDirectory),
              sourceIsDirectory.boolValue,
              fileManager.fileExists(atPath: targetPath, isDirectory: &targetIsDirectory),
              targetIsDirectory.boolValue else {
            return []
        }

        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard !children.isEmpty else { return [] }

        var applied: [PlannedMove] = []
        for child in children {
            try checkForCancellation()
            let fromPath = relativePath(for: child, root: root)
            let targetChild = uniqueURL(target.appendingPathComponent(child.lastPathComponent), root: root)
            try fileManager.moveItem(at: child, to: targetChild)
            applied.append(PlannedMove(
                reason: reason,
                fromPath: fromPath,
                toPath: relativePath(for: targetChild, root: root)
            ))
        }

        if (try? fileManager.contentsOfDirectory(atPath: sourcePath).isEmpty) == true {
            try fileManager.removeItem(at: source)
        }

        return applied
    }

    private func saveUndoPlan(_ moves: [PlannedMove], root: URL, config: SableLibraryConfig) throws {
        guard !moves.isEmpty else { return }
        let plan = UndoPlan(createdAt: Date(), moves: moves)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(plan)
        try ensureReportDirectory(root: root, config: config)
        let reportFolder = reportDirectory(root: root, config: config)
        try data.write(to: reportFolder.appendingPathComponent(config.reports.undoPlanJSON), options: .atomic)

        let stamp = ISO8601DateFormatter()
            .string(from: plan.createdAt)
            .replacingOccurrences(of: #"[^\dA-Za-z]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let baseName = (config.reports.undoPlanJSON as NSString).deletingPathExtension
        let ext = (config.reports.undoPlanJSON as NSString).pathExtension
        let historyName = ext.isEmpty ? "\(baseName)_\(stamp)" : "\(baseName)_\(stamp).\(ext)"
        try data.write(to: reportFolder.appendingPathComponent(historyName), options: .atomic)
    }
}
