//
//  SableLibraryFileScanner.swift
//  Sable's Library
//

import Foundation

enum SableLibraryFileScannerError: LocalizedError {
    case unreadableRoot(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableRoot(let url):
            "Library folder cannot be read. Choose the folder again so the app can access: \(url.path(percentEncoded: false))"
        }
    }
}

struct SableLibraryEPUBClinicInventory: Sendable {
    var items: [LibraryItem]
    var fileCount: Int
    var folderCount: Int
    var comicInfoFolders: [String]
    var animeInfoFolders: [String]
    var missingComicInfoFolders: [String]
    var invalidComicInfoPaths: [String]
    var invalidAnimeInfoPaths: [String]
    var epubCountWithComicInfo: Int
    var epubCountWithAnimeInfo: Int
    var warnings: [String]
}

struct SableLibraryLightInventoryScan: Sendable {
    var items: [LibraryItem]
    var fileCount: Int
    var folderCount: Int
    var warnings: [String]
}

extension SableLibraryService {
    func enumerateEPUBClinicItems(
        root: URL,
        config: SableLibraryConfig,
        changedPaths: [String]? = nil
    ) throws -> SableLibraryEPUBClinicInventory {
        let requestedPaths = changedPaths?.map(Self.normalizedFocusedScanPath).filter { !$0.isEmpty } ?? []
        if !requestedPaths.isEmpty {
            return try enumerateChangedEPUBClinicItems(root: root, config: config, relativePaths: requestedPaths)
        }
        let startedAt = Date()

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .nameKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        reportProgress("Sable's Clinic: opening selected folder")
        do {
            _ = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw SableLibraryFileScannerError.unreadableRoot(root)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw SableLibraryFileScannerError.unreadableRoot(root)
        }

        let ignored = Set(config.ignoreNames + [config.reportFolderName, config.duplicateFolderName, config.missingNumberFolderName])
        let matcher = SableLibraryFileTypeMatcher(config: config)
        var epubItems: [LibraryItem] = []
        var scannedCount = 0
        var fileCount = 0
        var folderCount = 0
        var comicInfoFolderPaths = Set<String>()
        var animeInfoFolderPaths = Set<String>()
        var invalidComicInfoPaths: [String] = []
        var invalidAnimeInfoPaths: [String] = []
        var cloudUnavailableCount = 0
        var cloudUnavailableExamples: [String] = []
        var unreadableItemCount = 0
        var unreadableItemExamples: [String] = []

        for case let url as URL in enumerator {
            scannedCount += 1
            try checkForCancellation(at: scannedCount)
            if scannedCount == 1 {
                reportProgress("Sable's Clinic: looking for EPUB files")
            } else if scannedCount == 100 || scannedCount.isMultiple(of: 1_000) {
                let timing = SableLibraryWorkTiming.summary(
                    startedAt: startedAt,
                    completedCount: scannedCount,
                    unit: "item"
                )
                reportProgress("Sable's Clinic: scanned \(scannedCount) item(s), found \(epubItems.count) EPUB file(s). \(timing)")
            }

            let itemPath = relativePath(for: url, root: root)
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                unreadableItemCount += 1
                appendScanWarningExample(itemPath, to: &unreadableItemExamples)
                skipDescendantsIfDirectory(url, enumerator: enumerator)
                continue
            }

            let name = values.name ?? url.lastPathComponent
            let isDirectory = values.isDirectory ?? false

            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus == .notDownloaded {
                cloudUnavailableCount += 1
                appendScanWarningExample(itemPath, to: &cloudUnavailableExamples)
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if ignored.contains(name) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory {
                folderCount += 1
            } else {
                fileCount += 1
            }

            if !isDirectory, name == config.comicInfoFileName {
                if sidecarJSONIsReadable(at: url) {
                    comicInfoFolderPaths.insert(url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false))
                } else {
                    appendScanWarningExample(itemPath, to: &invalidComicInfoPaths)
                }
            } else if !isDirectory, name == config.animeInfoFileName {
                if sidecarJSONIsReadable(at: url) {
                    animeInfoFolderPaths.insert(url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false))
                } else {
                    appendScanWarningExample(itemPath, to: &invalidAnimeInfoPaths)
                }
            }

            let isEPUB = url.pathExtension.caseInsensitiveCompare("epub") == .orderedSame
            if isEPUB, !isDirectory || (isDirectory && matcher.isBook(url: url, isDirectory: true)) {
                epubItems.append(
                    LibraryItem(
                        url: url,
                        relativePath: itemPath,
                        name: name,
                        isDirectory: isDirectory,
                        fileSize: Int64(values.fileSize ?? 0),
                        modificationDate: values.contentModificationDate
                    )
                )
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory, matcher.isBook(url: url, isDirectory: true) {
                enumerator.skipDescendants()
            }
        }

        let warnings = scanWarningNotes(
            cloudUnavailableCount: cloudUnavailableCount,
            cloudUnavailableExamples: cloudUnavailableExamples,
            unreadableItemCount: unreadableItemCount,
            unreadableItemExamples: unreadableItemExamples
        )
        let sortedItems = epubItems.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        let coverage = epubClinicSidecarCoverage(
            for: sortedItems,
            root: root,
            comicInfoFolderPaths: comicInfoFolderPaths,
            animeInfoFolderPaths: animeInfoFolderPaths
        )
        let warningSuffix = warnings.isEmpty ? "" : ", \(cloudUnavailableCount + unreadableItemCount) skipped"
        let timing = SableLibraryWorkTiming.summary(
            startedAt: startedAt,
            completedCount: scannedCount,
            unit: "item"
        )
        reportProgress("Sable's Clinic: found \(sortedItems.count) EPUB file(s), checked \(comicInfoFolderPaths.count + animeInfoFolderPaths.count) sidecar folder(s)\(warningSuffix). \(timing)")
        return SableLibraryEPUBClinicInventory(
            items: sortedItems,
            fileCount: fileCount,
            folderCount: folderCount,
            comicInfoFolders: coverage.comicInfoFolders,
            animeInfoFolders: coverage.animeInfoFolders,
            missingComicInfoFolders: coverage.missingComicInfoFolders,
            invalidComicInfoPaths: invalidComicInfoPaths.sorted(),
            invalidAnimeInfoPaths: invalidAnimeInfoPaths.sorted(),
            epubCountWithComicInfo: coverage.epubCountWithComicInfo,
            epubCountWithAnimeInfo: coverage.epubCountWithAnimeInfo,
            warnings: warnings
        )
    }

    func enumerateLightInventoryItems(root: URL, config: SableLibraryConfig) throws -> SableLibraryLightInventoryScan {
        let startedAt = Date()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .nameKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        reportProgress("Scan Inventory: opening library folder")
        do {
            _ = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw SableLibraryFileScannerError.unreadableRoot(root)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw SableLibraryFileScannerError.unreadableRoot(root)
        }

        let ignored = Set(config.ignoreNames + [config.reportFolderName, config.duplicateFolderName, config.missingNumberFolderName])
        let matcher = SableLibraryFileTypeMatcher(config: config)
        var inventoryItems: [LibraryItem] = []
        var scannedCount = 0
        var fileCount = 0
        var folderCount = 0
        var cloudUnavailableCount = 0
        var cloudUnavailableExamples: [String] = []
        var unreadableItemCount = 0
        var unreadableItemExamples: [String] = []

        for case let url as URL in enumerator {
            scannedCount += 1
            try checkForCancellation(at: scannedCount)
            if scannedCount == 1 {
                reportProgress("Scan Inventory: mapping books, videos, and sidecars")
            } else if scannedCount == 100 || scannedCount.isMultiple(of: 1_000) {
                let timing = SableLibraryWorkTiming.summary(
                    startedAt: startedAt,
                    completedCount: scannedCount,
                    unit: "item"
                )
                reportProgress("Scan Inventory: scanned \(scannedCount) item(s), kept \(inventoryItems.count) triage marker(s). \(timing)")
            }

            let itemPath = relativePath(for: url, root: root)
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                unreadableItemCount += 1
                appendScanWarningExample(itemPath, to: &unreadableItemExamples)
                skipDescendantsIfDirectory(url, enumerator: enumerator)
                continue
            }

            let name = values.name ?? url.lastPathComponent
            let isDirectory = values.isDirectory ?? false

            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus == .notDownloaded {
                cloudUnavailableCount += 1
                appendScanWarningExample(itemPath, to: &cloudUnavailableExamples)
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if ignored.contains(name) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory {
                folderCount += 1
            } else {
                fileCount += 1
            }

            let isSidecar = !isDirectory && (name == config.comicInfoFileName || name == config.animeInfoFileName)
            let isBook = matcher.isBook(url: url, isDirectory: isDirectory)
            let isVideo = matcher.isVideo(url: url, isDirectory: isDirectory)

            if isSidecar || isBook || isVideo {
                inventoryItems.append(
                    LibraryItem(
                        url: url,
                        relativePath: itemPath,
                        name: name,
                        isDirectory: isDirectory,
                        fileSize: Int64(values.fileSize ?? 0),
                        modificationDate: values.contentModificationDate
                    )
                )
            }

            if isDirectory, isBook {
                enumerator.skipDescendants()
            }
        }

        let warnings = scanWarningNotes(
            cloudUnavailableCount: cloudUnavailableCount,
            cloudUnavailableExamples: cloudUnavailableExamples,
            unreadableItemCount: unreadableItemCount,
            unreadableItemExamples: unreadableItemExamples
        )
        let sortedItems = inventoryItems.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        let warningSuffix = warnings.isEmpty ? "" : ", \(cloudUnavailableCount + unreadableItemCount) skipped"
        let timing = SableLibraryWorkTiming.summary(
            startedAt: startedAt,
            completedCount: scannedCount,
            unit: "item"
        )
        reportProgress("Scan Inventory: found \(sortedItems.count) triage marker(s), \(fileCount + folderCount) total item(s)\(warningSuffix). \(timing)")
        return SableLibraryLightInventoryScan(
            items: sortedItems,
            fileCount: fileCount,
            folderCount: folderCount,
            warnings: warnings
        )
    }

    func enumerateItems(root: URL, config: SableLibraryConfig) throws -> [LibraryItem] {
        let cacheKey = scanCacheKey(root: root, config: config)
        if let cached = cachedItems(for: cacheKey) {
            return cached
        }
        let startedAt = Date()

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .nameKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        reportProgress("Preparing Library: opening library folder")
        do {
            _ = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw SableLibraryFileScannerError.unreadableRoot(root)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw SableLibraryFileScannerError.unreadableRoot(root)
        }

        var items: [LibraryItem] = []
        let ignored = Set(config.ignoreNames + [config.reportFolderName, config.duplicateFolderName, config.missingNumberFolderName])
        let matcher = SableLibraryFileTypeMatcher(config: config)
        var scannedCount = 0
        var cloudUnavailableCount = 0
        var cloudUnavailableExamples: [String] = []
        var unreadableItemCount = 0
        var unreadableItemExamples: [String] = []

        for case let url as URL in enumerator {
            scannedCount += 1
            try checkForCancellation(at: scannedCount)
            if scannedCount == 1 {
                reportProgress("Preparing Library: reading the first folder items")
            } else if scannedCount == 25 || scannedCount == 100 || scannedCount.isMultiple(of: 500) {
                let timing = SableLibraryWorkTiming.summary(
                    startedAt: startedAt,
                    completedCount: scannedCount,
                    unit: "item"
                )
                reportProgress("Preparing Library: checked \(scannedCount) item(s). \(timing) Current: \(url.lastPathComponent)")
            }
            let itemPath = relativePath(for: url, root: root)
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                unreadableItemCount += 1
                appendScanWarningExample(itemPath, to: &unreadableItemExamples)
                skipDescendantsIfDirectory(url, enumerator: enumerator)
                continue
            }
            let name = values.name ?? url.lastPathComponent
            let isDirectory = values.isDirectory ?? false

            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus == .notDownloaded {
                cloudUnavailableCount += 1
                appendScanWarningExample(itemPath, to: &cloudUnavailableExamples)
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if ignored.contains(name) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            items.append(
                LibraryItem(
                    url: url,
                    relativePath: itemPath,
                    name: name,
                    isDirectory: isDirectory,
                    fileSize: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate
                )
            )

            if isDirectory, matcher.isBook(url: url, isDirectory: true) {
                enumerator.skipDescendants()
            }
        }

        let sortedItems = items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        let bookCount = sortedItems.filter { matcher.isBook(url: $0.url, isDirectory: $0.isDirectory) }.count
        let warnings = scanWarningNotes(
            cloudUnavailableCount: cloudUnavailableCount,
            cloudUnavailableExamples: cloudUnavailableExamples,
            unreadableItemCount: unreadableItemCount,
            unreadableItemExamples: unreadableItemExamples
        )
        let warningSuffix = warnings.isEmpty ? "" : ", \(cloudUnavailableCount + unreadableItemCount) skipped"
        let timing = SableLibraryWorkTiming.summary(
            startedAt: startedAt,
            completedCount: scannedCount,
            unit: "item"
        )
        reportProgress("Prepared Library: \(bookCount) book file(s), \(sortedItems.count) total item(s)\(warningSuffix). \(timing)")
        storeCachedItems(sortedItems, warnings: warnings, for: cacheKey)
        return sortedItems
    }

    private func enumerateChangedEPUBClinicItems(
        root: URL,
        config: SableLibraryConfig,
        relativePaths: [String]
    ) throws -> SableLibraryEPUBClinicInventory {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .nameKey, .contentModificationDateKey]
        var items: [LibraryItem] = []
        var unreadableExamples: [String] = []
        var comicInfoFolderPaths = Set<String>()
        var animeInfoFolderPaths = Set<String>()
        var invalidComicInfoPaths: [String] = []
        var invalidAnimeInfoPaths: [String] = []

        for (index, relativePath) in relativePaths.enumerated() {
            try checkForCancellation(at: index + 1)
            guard (relativePath as NSString).pathExtension.caseInsensitiveCompare("epub") == .orderedSame else {
                continue
            }

            let url = root.appendingPathComponent(relativePath)
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                appendScanWarningExample(relativePath, to: &unreadableExamples)
                continue
            }

            items.append(
                LibraryItem(
                    url: url,
                    relativePath: relativePath,
                    name: values.name ?? url.lastPathComponent,
                    isDirectory: values.isDirectory ?? false,
                    fileSize: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate
                )
            )

            let parent = url.deletingLastPathComponent()
            if let sidecarFolder = nearestExistingSidecarFolder(
                from: parent,
                root: root,
                sidecarName: config.comicInfoFileName,
                invalidSidecarPaths: &invalidComicInfoPaths
            ) {
                comicInfoFolderPaths.insert(sidecarFolder.standardizedFileURL.path(percentEncoded: false))
            }
            if let sidecarFolder = nearestExistingSidecarFolder(
                from: parent,
                root: root,
                sidecarName: config.animeInfoFileName,
                invalidSidecarPaths: &invalidAnimeInfoPaths
            ) {
                animeInfoFolderPaths.insert(sidecarFolder.standardizedFileURL.path(percentEncoded: false))
            }
        }

        let warnings = unreadableExamples.isEmpty
            ? []
            : ["\(unreadableExamples.count) changed EPUB path(s) could not be re-read. Check permissions or cloud-provider status, then scan again.\(scanWarningExamplesText(unreadableExamples))"]
        let sortedItems = items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        let coverage = epubClinicSidecarCoverage(
            for: sortedItems,
            root: root,
            comicInfoFolderPaths: comicInfoFolderPaths,
            animeInfoFolderPaths: animeInfoFolderPaths
        )

        return SableLibraryEPUBClinicInventory(
            items: sortedItems,
            fileCount: sortedItems.filter { !$0.isDirectory }.count,
            folderCount: sortedItems.filter(\.isDirectory).count,
            comicInfoFolders: coverage.comicInfoFolders,
            animeInfoFolders: coverage.animeInfoFolders,
            missingComicInfoFolders: coverage.missingComicInfoFolders,
            invalidComicInfoPaths: invalidComicInfoPaths.sorted(),
            invalidAnimeInfoPaths: invalidAnimeInfoPaths.sorted(),
            epubCountWithComicInfo: coverage.epubCountWithComicInfo,
            epubCountWithAnimeInfo: coverage.epubCountWithAnimeInfo,
            warnings: warnings
        )
    }

    private func sidecarJSONIsReadable(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return object is [String: Any]
    }

    private func nearestExistingSidecarFolder(
        from folder: URL,
        root: URL,
        sidecarName: String,
        invalidSidecarPaths: inout [String]
    ) -> URL? {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var current = folder.standardizedFileURL

        while true {
            let currentPath = current.path(percentEncoded: false)
            guard currentPath == rootPath || currentPath.hasPrefix(rootPrefix) else {
                return nil
            }

            let sidecarURL = current.appendingPathComponent(sidecarName)
            if fileManager.fileExists(atPath: sidecarURL.path(percentEncoded: false)) {
                if sidecarJSONIsReadable(at: sidecarURL) {
                    return current
                }
                appendScanWarningExample(relativePath(for: sidecarURL, root: root), to: &invalidSidecarPaths)
                return nil
            }

            guard currentPath != rootPath else { return nil }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    private func epubClinicSidecarCoverage(
        for items: [LibraryItem],
        root: URL,
        comicInfoFolderPaths: Set<String>,
        animeInfoFolderPaths: Set<String>
    ) -> (
        comicInfoFolders: [String],
        animeInfoFolders: [String],
        missingComicInfoFolders: [String],
        epubCountWithComicInfo: Int,
        epubCountWithAnimeInfo: Int
    ) {
        var usedComicInfoFolders = Set<String>()
        var usedAnimeInfoFolders = Set<String>()
        var missingComicInfoFolders = Set<String>()
        var epubCountWithComicInfo = 0
        var epubCountWithAnimeInfo = 0

        for item in items {
            let parent = item.url.deletingLastPathComponent()
            if let comicInfoFolder = nearestSidecarFolder(
                from: parent,
                root: root,
                sidecarFolderPaths: comicInfoFolderPaths
            ) {
                usedComicInfoFolders.insert(relativePath(for: comicInfoFolder, root: root))
                epubCountWithComicInfo += 1
            } else {
                missingComicInfoFolders.insert(relativePath(for: parent, root: root))
            }

            if let animeInfoFolder = nearestSidecarFolder(
                from: parent,
                root: root,
                sidecarFolderPaths: animeInfoFolderPaths
            ) {
                usedAnimeInfoFolders.insert(relativePath(for: animeInfoFolder, root: root))
                epubCountWithAnimeInfo += 1
            }
        }

        return (
            comicInfoFolders: usedComicInfoFolders.sorted(),
            animeInfoFolders: usedAnimeInfoFolders.sorted(),
            missingComicInfoFolders: missingComicInfoFolders.sorted(),
            epubCountWithComicInfo: epubCountWithComicInfo,
            epubCountWithAnimeInfo: epubCountWithAnimeInfo
        )
    }

    private func appendScanWarningExample(_ path: String, to examples: inout [String]) {
        guard examples.count < 3 else { return }
        examples.append(path.isEmpty ? "Library root" : path)
    }

    private func skipDescendantsIfDirectory(_ url: URL, enumerator: FileManager.DirectoryEnumerator) {
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
           isDirectory.boolValue {
            enumerator.skipDescendants()
        }
    }

    private func scanWarningNotes(
        cloudUnavailableCount: Int,
        cloudUnavailableExamples: [String],
        unreadableItemCount: Int,
        unreadableItemExamples: [String]
    ) -> [String] {
        var notes: [String] = []
        if cloudUnavailableCount > 0 {
            notes.append(
                "\(cloudUnavailableCount) cloud-backed item(s) were not downloaded locally and were skipped. Download them in Finder, then inspect again.\(scanWarningExamplesText(cloudUnavailableExamples))"
            )
        }
        if unreadableItemCount > 0 {
            notes.append(
                "\(unreadableItemCount) item(s) could not be read and were skipped. Check permissions or cloud-provider status, then inspect again.\(scanWarningExamplesText(unreadableItemExamples))"
            )
        }
        return notes
    }

    private func scanWarningExamplesText(_ examples: [String]) -> String {
        examples.isEmpty ? "" : " Examples: \(examples.joined(separator: ", "))."
    }

    private nonisolated static func normalizedFocusedScanPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    func isBook(_ item: LibraryItem, config: SableLibraryConfig) -> Bool {
        SableLibraryFileTypeMatcher(config: config).isBook(url: item.url, isDirectory: item.isDirectory)
    }

    func bookItems(root: URL, config: SableLibraryConfig) throws -> [LibraryItem] {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        return try enumerateItems(root: root, config: config)
            .filter { matcher.isBook(url: $0.url, isDirectory: $0.isDirectory) }
    }

    func bookItems(root: URL, config: SableLibraryConfig, cleanupOptions: CleanupOptions) throws -> [LibraryItem] {
        let items = try enumerateItems(root: root, config: config)
        return bookItems(in: items, root: root, config: config, cleanupOptions: cleanupOptions)
    }

    func bookItems(
        in items: [LibraryItem],
        root: URL,
        config: SableLibraryConfig,
        cleanupOptions: CleanupOptions
    ) -> [LibraryItem] {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        let context = SableLibraryPDFBookEvidenceContext(
            items: items,
            config: config,
            matcher: matcher
        )
        return items.filter {
            isReadingItem(
                $0,
                matcher: matcher,
                pdfEvidence: context,
                cleanupOptions: cleanupOptions
            )
        }
    }

    func isVideo(_ item: LibraryItem, config: SableLibraryConfig) -> Bool {
        SableLibraryFileTypeMatcher(config: config).isVideo(url: item.url, isDirectory: item.isDirectory)
    }

    func videoItems(root: URL, config: SableLibraryConfig) throws -> [LibraryItem] {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        return try enumerateItems(root: root, config: config)
            .filter { matcher.isVideo(url: $0.url, isDirectory: $0.isDirectory) }
    }

    func bookItems(in folder: URL, libraryRoot root: URL, config: SableLibraryConfig) throws -> [LibraryItem] {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        return try enumerateItems(root: folder, config: config)
            .filter { matcher.isBook(url: $0.url, isDirectory: $0.isDirectory) }
            .map { item in
                LibraryItem(
                    url: item.url,
                    relativePath: relativePath(for: item.url, root: root),
                    name: item.name,
                    isDirectory: item.isDirectory,
                    fileSize: item.fileSize,
                    modificationDate: item.modificationDate
                )
            }
    }

    func bookItemsByParent(root: URL, config: SableLibraryConfig) throws -> [String: [LibraryItem]] {
        var grouped: [String: [LibraryItem]] = [:]
        for item in try bookItems(root: root, config: config) {
            let parentPath = item.url
                .deletingLastPathComponent()
                .standardizedFileURL
                .path(percentEncoded: false)
            grouped[parentPath, default: []].append(item)
        }
        return grouped
    }

    func bookItemsByParent(
        root: URL,
        config: SableLibraryConfig,
        cleanupOptions: CleanupOptions
    ) throws -> [String: [LibraryItem]] {
        var grouped: [String: [LibraryItem]] = [:]
        for item in try bookItems(root: root, config: config, cleanupOptions: cleanupOptions) {
            let parentPath = item.url
                .deletingLastPathComponent()
                .standardizedFileURL
                .path(percentEncoded: false)
            grouped[parentPath, default: []].append(item)
        }
        return grouped
    }

    func catalogEntries(root: URL, config: SableLibraryConfig) throws -> [[String: String]] {
        try bookItems(root: root, config: config)
            .map { item in
                [
                    "path": item.relativePath,
                    "name": item.name,
                    "size": String(item.fileSize)
                ]
            }
    }

    func seriesEntries(root: URL, config: SableLibraryConfig) throws -> [SeriesEntry] {
        try seriesEntries(root: root, config: config, cleanupOptions: CleanupOptions(treatPDFsAsBooks: true))
    }

    func seriesEntries(root: URL, config: SableLibraryConfig, cleanupOptions: CleanupOptions) throws -> [SeriesEntry] {
        let items = try enumerateItems(root: root, config: config)
        let matcher = SableLibraryFileTypeMatcher(config: config)
        let pdfEvidence = SableLibraryPDFBookEvidenceContext(
            items: items,
            config: config,
            matcher: matcher
        )
        let books = items.filter {
            isReadingItem(
                $0,
                matcher: matcher,
                pdfEvidence: pdfEvidence,
                cleanupOptions: cleanupOptions
            )
        }
        let comicInfoFolders = items
            .filter { !$0.isDirectory && $0.name == config.comicInfoFileName }
            .map { $0.url.deletingLastPathComponent() }
        let comicInfoFolderPaths = Set(comicInfoFolders.map { $0.standardizedFileURL.path(percentEncoded: false) })
        var grouped: [String: [LibraryItem]] = [:]
        var foldersByPath: [String: URL] = [:]

        for book in books {
            let parent = book.url.deletingLastPathComponent()
            let nameParts = bookNameParts(for: book.url.deletingPathExtension().lastPathComponent, config: config)
            let folder: URL
            if parent.standardizedFileURL == root.standardizedFileURL {
                folder = root.appendingPathComponent(nameParts.seriesTitle, isDirectory: true)
            } else if let sidecarFolder = nearestSidecarFolder(
                from: parent,
                root: root,
                sidecarFolderPaths: comicInfoFolderPaths
            ) {
                folder = sidecarFolder
            } else {
                folder = parent
            }
            let folderURL = folder.standardizedFileURL
            let folderPath = folderURL.path(percentEncoded: false)
            foldersByPath[folderPath] = folderURL
            grouped[folderPath, default: []].append(book)
        }

        for folder in comicInfoFolders {
            let folderURL = folder.standardizedFileURL
            let folderPath = folderURL.path(percentEncoded: false)
            foldersByPath[folderPath] = folderURL
            if grouped[folderPath] == nil {
                grouped[folderPath] = []
            }
        }

        return grouped.compactMap { folderPath, items in
            guard let folder = foldersByPath[folderPath] else { return nil }
            let formats = Array(Set(items.map { $0.url.pathExtension.lowercased() })).sorted()
            return SeriesEntry(
                title: cleanSeriesTitle(folder.lastPathComponent),
                folderURL: folder,
                relativePath: relativePath(for: folder, root: root),
                formats: formats
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func isReadingItem(
        _ item: LibraryItem,
        matcher: SableLibraryFileTypeMatcher,
        pdfEvidence: SableLibraryPDFBookEvidenceContext,
        cleanupOptions: CleanupOptions
    ) -> Bool {
        guard matcher.isBook(url: item.url, isDirectory: item.isDirectory) else { return false }
        guard isAmbiguousPDF(item) else { return true }
        return cleanupOptions.treatPDFsAsBooks || pdfEvidence.hasBookEvidence(for: item)
    }

    private func isAmbiguousPDF(_ item: LibraryItem) -> Bool {
        !item.isDirectory && item.url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
    }

    func videoSeriesEntries(root: URL, config: SableLibraryConfig) throws -> [SeriesEntry] {
        let items = try enumerateItems(root: root, config: config)
        let matcher = SableLibraryFileTypeMatcher(config: config)
        let videos = items.filter { matcher.isVideo(url: $0.url, isDirectory: $0.isDirectory) }
        let animeInfoFolders = items
            .filter { !$0.isDirectory && $0.name == config.animeInfoFileName }
            .map { $0.url.deletingLastPathComponent() }
        let animeInfoFolderPaths = Set(animeInfoFolders.map { $0.standardizedFileURL.path(percentEncoded: false) })
        var grouped: [String: [LibraryItem]] = [:]
        var foldersByPath: [String: URL] = [:]

        for video in videos {
            let parent = video.url.deletingLastPathComponent()
            let folder: URL
            if parent.standardizedFileURL == root.standardizedFileURL {
                folder = root.appendingPathComponent(cleanSeriesTitle(video.url.deletingPathExtension().lastPathComponent), isDirectory: true)
            } else if let sidecarFolder = nearestSidecarFolder(
                from: parent,
                root: root,
                sidecarFolderPaths: animeInfoFolderPaths
            ) {
                folder = sidecarFolder
            } else if let seasonParent = plexSeasonParent(for: parent, root: root) {
                folder = seasonParent
            } else {
                folder = parent
            }
            let folderURL = folder.standardizedFileURL
            let folderPath = folderURL.path(percentEncoded: false)
            foldersByPath[folderPath] = folderURL
            grouped[folderPath, default: []].append(video)
        }

        for folder in animeInfoFolders {
            let folderURL = folder.standardizedFileURL
            let folderPath = folderURL.path(percentEncoded: false)
            foldersByPath[folderPath] = folderURL
            if grouped[folderPath] == nil {
                grouped[folderPath] = []
            }
        }

        return grouped.compactMap { folderPath, items in
            guard let folder = foldersByPath[folderPath] else { return nil }
            let formats = Array(Set(items.map { $0.url.pathExtension.lowercased() })).sorted()
            return SeriesEntry(
                title: cleanSeriesTitle(folder.lastPathComponent),
                folderURL: folder,
                relativePath: relativePath(for: folder, root: root),
                formats: formats
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func comicInfoFolders(root: URL, config: SableLibraryConfig) throws -> [URL] {
        let items = try enumerateItems(root: root, config: config)
        return items
            .filter { !$0.isDirectory && $0.name == config.comicInfoFileName }
            .map { $0.url.deletingLastPathComponent() }
            .sorted { $0.path(percentEncoded: false).localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending }
    }

    func animeInfoFolders(root: URL, config: SableLibraryConfig) throws -> [URL] {
        let items = try enumerateItems(root: root, config: config)
        return items
            .filter { !$0.isDirectory && $0.name == config.animeInfoFileName }
            .map { $0.url.deletingLastPathComponent() }
            .sorted { $0.path(percentEncoded: false).localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending }
    }

    private func nearestSidecarFolder(
        from folder: URL,
        root: URL,
        sidecarFolderPaths: Set<String>
    ) -> URL? {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        var current = folder.standardizedFileURL

        while current.path(percentEncoded: false).hasPrefix(rootPath) {
            if sidecarFolderPaths.contains(current.path(percentEncoded: false)) {
                return current
            }
            if current == rootURL {
                return nil
            }
            current = current.deletingLastPathComponent().standardizedFileURL
        }

        return nil
    }

    private func plexSeasonParent(for folder: URL, root: URL) -> URL? {
        let current = folder.standardizedFileURL
        let rootURL = root.standardizedFileURL
        guard current != rootURL,
              isPlexSeasonFolderName(current.lastPathComponent) else {
            return nil
        }

        let parent = current.deletingLastPathComponent().standardizedFileURL
        return parent == rootURL ? nil : parent
    }

    private func isPlexSeasonFolderName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "specials" {
            return true
        }
        return normalized.range(of: #"^season\s+\d{1,3}$"#, options: .regularExpression) != nil
    }
}

private struct SableLibraryPDFBookEvidenceContext {
    private let comicInfoFolderPaths: Set<String>
    private let nonPDFBookFolderPaths: Set<String>
    private let readingSourceHintPaths: Set<String>
    private let readingRootPaths: Set<String>

    init(
        items: [LibraryItem],
        config: SableLibraryConfig,
        matcher: SableLibraryFileTypeMatcher
    ) {
        let comicInfoName = config.comicInfoFileName
        self.comicInfoFolderPaths = Set(items.compactMap { item in
            guard !item.isDirectory, item.name == comicInfoName else { return nil }
            return Self.parentPath(for: item.relativePath)
        })
        self.nonPDFBookFolderPaths = Set(items.compactMap { item in
            guard matcher.isBook(url: item.url, isDirectory: item.isDirectory),
                  item.isDirectory || item.url.pathExtension.caseInsensitiveCompare("pdf") != .orderedSame else {
                return nil
            }
            return Self.parentPath(for: item.relativePath)
        })
        self.readingSourceHintPaths = Set(items.compactMap { item in
            let parent = Self.parentPath(for: item.relativePath)
            return Self.pathComponents(in: parent).contains(where: Self.hasReadingSourceHint) ? parent : nil
        })
        self.readingRootPaths = Set(items.compactMap { item in
            let parent = Self.parentPath(for: item.relativePath)
            return Self.pathComponents(in: parent).contains(where: Self.isKnownReadingFolderName) ? parent : nil
        })
    }

    func hasBookEvidence(for item: LibraryItem) -> Bool {
        let parent = Self.parentPath(for: item.relativePath)
        let ancestors = Self.ancestorPaths(including: parent)
        return ancestors.contains(where: comicInfoFolderPaths.contains)
            || ancestors.contains(where: readingSourceHintPaths.contains)
            || ancestors.contains(where: readingRootPaths.contains)
            || nonPDFBookFolderPaths.contains(parent)
    }

    private static func parentPath(for relativePath: String) -> String {
        normalizedPath((relativePath as NSString).deletingLastPathComponent)
    }

    private static func ancestorPaths(including path: String) -> [String] {
        var paths: [String] = [path]
        var current = path
        while !current.isEmpty {
            current = parentPath(for: current)
            paths.append(current)
        }
        return paths
    }

    private static func pathComponents(in path: String) -> [String] {
        normalizedPath(path)
            .split(separator: "/")
            .map(String.init)
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed == "." ? "" : trimmed
    }

    nonisolated private static func hasReadingSourceHint(_ folderName: String) -> Bool {
        SableLibrarySourceIDParser.folderHints(in: folderName).contains { sourceID in
            switch sourceID.provider {
            case .mangabaka, .ranobedb, .openLibrary:
                true
            case .myAnimeList, .anilist, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb, .local:
                false
            }
        }
    }

    nonisolated private static func isKnownReadingFolderName(_ folderName: String) -> Bool {
        let normalized = folderName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return [
            "book",
            "books",
            "comic",
            "comic books",
            "comics",
            "graphic novels",
            "light novel",
            "light novels",
            "manga",
            "manhwa",
            "manhua",
            "novel",
            "novels",
            "reading"
        ].contains(normalized)
    }
}
