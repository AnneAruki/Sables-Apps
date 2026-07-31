//
//  SableLibraryAppleBooksCompatibilityRepair.swift
//  Sable's Library
//

import Foundation
import Compression
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Vision)
import Vision
#endif

struct LibraryAppleBooksCompatibilityRepairApplyResult: Sendable {
    let applied: [String]
    let skipped: [String]
    let failed: [String: String]
    let report: String
    let changedFiles: Bool
}

struct LibraryAppleBooksCompatibilityRepairAnalysis: Sendable {
    let reasons: [String]
    let outputRelativePath: String
    let downloadsTrustedCover: Bool
    let coverProvider: SableLibraryMetadataProvider?
    let protection: LibraryEPUBProtectionAnalysis
}

nonisolated struct LibraryEPUBProtectionAnalysis: Sendable, Equatable {
    var isProtected: Bool
    var reason: String?
    var encryptedResourcePaths: [String]
    var obfuscatedFontPaths: [String]

    static let none = LibraryEPUBProtectionAnalysis(
        isProtected: false,
        reason: nil,
        encryptedResourcePaths: [],
        obfuscatedFontPaths: []
    )
}

enum SableLibraryEPUBRepairScope: String, Codable, CaseIterable, Sendable, Hashable {
    case metadata
    case tags
    case cover
    case readerImport
    case navigation
    case structure
    case package
    case content
    case compatibility
    case diagnostics

    nonisolated static let all = Set(SableLibraryEPUBRepairScope.allCases.filter { $0 != .readerImport })

    nonisolated var reviewTag: String {
        "epub-scope-\(rawValue)"
    }
}

enum SableClinicCheckProfile: String, CaseIterable, Equatable, Identifiable, Sendable {
    case fast
    case metadata
    case covers
    case appleBooks
    case package
    case navigation
    case content
    case deep

    nonisolated var id: String { rawValue }

    nonisolated static let primaryChoices: [SableClinicCheckProfile] = [.fast, .deep]
    nonisolated static let repairLaneChoices: [SableClinicCheckProfile] = [
        .metadata,
        .package,
        .navigation,
        .content
    ]
    nonisolated static let coverChoices: [SableClinicCheckProfile] = [.covers, .appleBooks]

    nonisolated var title: String {
        switch self {
        case .fast:
            return "Fast Check"
        case .metadata:
            return "Metadata"
        case .covers:
            return "Covers"
        case .appleBooks:
            return "Apple Books"
        case .package:
            return "Package"
        case .navigation:
            return "Navigation"
        case .content:
            return "Content"
        case .deep:
            return "Full Check"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .fast:
            return "bolt"
        case .metadata:
            return "tag"
        case .covers:
            return "photo"
        case .appleBooks:
            return "books.vertical"
        case .package:
            return "cube"
        case .navigation:
            return "list.bullet"
        case .content:
            return "doc.text.magnifyingglass"
        case .deep:
            return "square.stack.3d.up"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .fast:
            return "Checks package basics, metadata sync, and light NCX wiring. Cover work stays in Sable's Covers."
        case .metadata:
            return "Syncs local ComicInfo facts, identifiers, descriptions, and cleaned tags."
        case .covers:
            return "Compares the embedded cover with the trusted language-matched library cover, then offers marker repair or a clearly better replacement."
        case .appleBooks:
            return "Prepares selected EPUBs for a clean reimport when Apple Books is stuck on a stale or placeholder cover."
        case .package:
            return "Checks EPUB container, manifest, guide, identifiers, and standards wiring."
        case .navigation:
            return "Checks NCX/nav targets and chapter structure. Opens only the navigation evidence it needs."
        case .content:
            return "Heavy lane for XHTML, CSS, linked resources, and page-box repairs."
        case .deep:
            return "Runs every non-cover Clinic specialist, including metadata, package, navigation, content, CSS, resources, and page checks."
        }
    }

    nonisolated var runsDeepContentChecks: Bool {
        switch self {
        case .navigation, .content, .deep:
            return true
        case .fast, .metadata, .covers, .appleBooks, .package:
            return false
        }
    }

    nonisolated var repairScopes: Set<SableLibraryEPUBRepairScope> {
        switch self {
        case .fast:
            return [.metadata, .tags, .package, .navigation, .compatibility]
        case .metadata:
            return [.metadata, .tags]
        case .covers:
            return [.cover]
        case .appleBooks:
            return [.readerImport]
        case .package:
            return [.package, .compatibility]
        case .navigation:
            return [.navigation, .structure, .compatibility]
        case .content:
            return [.content, .diagnostics]
        case .deep:
            return SableLibraryEPUBRepairScope.all.subtracting([.cover, .readerImport])
        }
    }

    nonisolated var workingStatus: String {
        switch self {
        case .fast:
            return "Fast-checking EPUBs..."
        case .metadata:
            return "Checking EPUB metadata..."
        case .covers:
            return "Checking EPUB covers..."
        case .appleBooks:
            return "Preparing Apple Books refresh rows..."
        case .package:
            return "Checking EPUB packages..."
        case .navigation:
            return "Checking EPUB navigation..."
        case .content:
            return "Checking EPUB content..."
        case .deep:
            return "Deep-checking EPUBs..."
        }
    }

    nonisolated var activityText: String {
        switch self {
        case .fast:
            return "Opening EPUBs for fast package, metadata, and NCX checks."
        case .metadata:
            return "Opening EPUBs for local metadata, identifier, description, and tag sync checks."
        case .covers:
            return "Opening EPUBs for cover markers and trusted language-matched cover comparison."
        case .appleBooks:
            return "Checking EPUB cover sources before offering a review-gated Apple Books import refresh."
        case .package:
            return "Opening EPUBs for package, manifest, guide, identifier, and standards checks."
        case .navigation:
            return "Opening EPUBs for navigation, NCX, TOC, and chapter-structure checks."
        case .content:
            return "Opening EPUBs for heavier XHTML, CSS, linked-resource, and page-box repairs."
        case .deep:
            return "Opening EPUBs for package, navigation, content, and safety checks. Cover work stays in Sable's Covers."
        }
    }

    nonisolated var emptyTitle: String {
        "\(title) found no repair rows"
    }

    nonisolated var emptyMessage: String {
        switch self {
        case .fast:
            return "No fast package, metadata, or light NCX repair rows were found. Deep content, CSS, image, and page-box repair checks did not run."
        case .metadata:
            return "No local metadata, identifier, description, or tag sync rows were found."
        case .covers:
            return "No cover-marker repairs or clearly better language-matched library covers were found."
        case .appleBooks:
            return "No EPUBs with a usable embedded or trusted local cover were found for Apple Books refresh."
        case .package:
            return "No package, manifest, guide, identifier, or standards rows were found."
        case .navigation:
            return "No navigation, NCX, TOC, or chapter-structure rows were found."
        case .content:
            return "No XHTML, CSS, linked-resource, or page-box repair rows were found."
        case .deep:
            return "No EPUB repair suggestions are waiting from the full deeper scan."
        }
    }

    nonisolated static func matching(scopes: Set<SableLibraryEPUBRepairScope>, deepContentChecks: Bool) -> SableClinicCheckProfile {
        let effectiveScopes = scopes.isEmpty ? SableLibraryEPUBRepairScope.all : scopes
        return allCases.first { profile in
            profile.runsDeepContentChecks == deepContentChecks
                && profile.repairScopes == effectiveScopes
        } ?? (deepContentChecks ? .deep : .fast)
    }
}

struct SableLibraryEPUBImportMetadata: Sendable, Equatable {
    var title: String
    var subtitle: String?
    var titleSort: String?
    var seriesTitle: String?
    var volumeNumber: Int?
    var seriesPosition: Int?
    var authors: [String]
    var artists: [String]
    var contributors: [String]
    var creatorCredits: [SableLibraryEPUBImportCredit]
    var contributorCredits: [SableLibraryEPUBImportCredit]
    var publishers: [String]
    var languages: [String]
    var isbn13: [String]
    var sourceIDs: [SableLibrarySourceID]
    var extraIdentifiers: [SableLibraryEPUBImportIdentifier]
    var coverURL: String?
    var coverProvider: SableLibraryMetadataProvider?
    var description: String?
    var subjects: [String]
    var releaseYear: Int?
    var releaseDate: Int?
    var pageCount: Int?
    var localCoverCandidates: [SableLibraryEPUBImportCoverCandidate]
}

struct SableLibraryEPUBImportCoverCandidate: Sendable, Equatable {
    var language: String
    var filePath: String
    var width: Int?
    var height: Int?
    var source: String?
    var volumeNumber: Int? = nil
}

struct SableLibraryEPUBImportCredit: Sendable, Equatable {
    var name: String
    var role: SableLibraryEPUBImportCreditRole
}

enum SableLibraryEPUBImportCreditRole: String, Sendable, Equatable {
    case author
    case artist
    case editor
    case translator
    case narrator
    case staff
    case contributor

    nonisolated var marcRelatorCode: String {
        switch self {
        case .author:
            return "aut"
        case .artist:
            return "ill"
        case .editor:
            return "edt"
        case .translator:
            return "trl"
        case .narrator:
            return "nrt"
        case .staff, .contributor:
            return "ctb"
        }
    }

    nonisolated var belongsInCreatorElement: Bool {
        switch self {
        case .author, .artist:
            return true
        case .editor, .translator, .narrator, .staff, .contributor:
            return false
        }
    }
}

struct SableLibraryEPUBImportIdentifier: Sendable, Equatable {
    var id: String
    var value: String
}

extension SableLibraryService {
    func epubImportMetadataCandidate(
        for epubURL: URL,
        root: URL,
        config: SableLibraryConfig
    ) -> SableLibraryEPUBImportMetadata? {
        guard epubURL.pathExtension.lowercased() == "epub",
              let sidecarLocation = nearestComicInfoSidecarLocation(for: epubURL, root: root, config: config) else {
            return nil
        }
        let sidecar = sidecarLocation.sidecar

        let fallbackTitle = cleanSeriesTitle(epubURL.deletingPathExtension().lastPathComponent)
        let seriesTitle = textValue(sidecar["preferred_title"])
            ?? textValue(sidecar["title"])
            ?? textValue(sidecar["local_title"])
            ?? sidecarTitleStrings(in: sidecar).first
            ?? fallbackTitle
        guard !seriesTitle.isEmpty else { return nil }

        let rawFileTitle = epubURL.deletingPathExtension().lastPathComponent
        let cleanedFileTitle = cleanedTitle(rawFileTitle, config: config)
        let volumeSuffix = volumeOrChapterSuffix(in: cleanedFileTitle)
        let detectedVolumeNumber: Int?
        if let volumeSuffix {
            detectedVolumeNumber = volumeNumber(in: volumeSuffix)
        } else {
            detectedVolumeNumber = nil
        }
        let seriesPosition = detectedVolumeNumber ?? standaloneEPUBSeriesPosition(
            for: epubURL,
            cleanedFileTitle: cleanedFileTitle,
            seriesTitle: seriesTitle
        )
        let volume = detectedVolumeNumber.flatMap { matchingEPUBImportVolume($0, in: sidecar) }
        let ranobeDBSeries = ranobeDBAPISeries(in: sidecar)
        let ranobeDBBook = ranobeDBAPIBook(in: sidecar, volumeNumber: detectedVolumeNumber)
        let subtitle = textValue(volume?["subtitle"])
        let importTitle: String
        if let detectedVolumeNumber {
            let padded = detectedVolumeNumber < 10 ? "0\(detectedVolumeNumber)" : "\(detectedVolumeNumber)"
            if let trustedBookTitle = trustedEPUBImportBookTitle(
                in: volume,
                sidecar: sidecar,
                expectedVolumeNumber: detectedVolumeNumber
            ) {
                importTitle = trustedBookTitle
            } else if let subtitle, !subtitle.isEmpty {
                importTitle = "\(seriesTitle) - Vol \(padded) - \(subtitle)"
            } else {
                importTitle = "\(seriesTitle) - Vol \(padded)"
            }
        } else {
            importTitle = seriesTitle
        }

        let partISBN = arrayStrings(volume?["isbn13"])
        let sidecarISBN = arrayStrings(sidecar["isbn13"])
        let ranobeDBISBN = ranobeDBISBN13(in: ranobeDBBook)
        let partYear = integerValue(volume?["release_year"])
        let partDate = integerValue(volume?["release_date"])
        let ranobeDBReleaseDate = ranobeDBReleaseDate(in: ranobeDBBook)
        let matchedVolumeSourceID = volume.flatMap { volumeSourceID(in: $0) }
        let sidecarSourceIDs = SableLibrarySourceIDParser.sourceIDs(
            from: sidecar,
            extraIDs: [sidecarOrganizerSourceID(in: sidecar)].compactMap { $0 }
        ) { textValue($0) }
        let scopedSourceIDs = epubImportSourceIDs(
            sidecarSourceIDs: sidecarSourceIDs,
            matchedVolumeSourceID: matchedVolumeSourceID,
            detectedVolumeNumber: detectedVolumeNumber
        )
        let sourceIDs = uniqueSourceIDs(
            scopedSourceIDs
                + [matchedVolumeSourceID].compactMap { $0 }
        )
        let coverURL = trustedSidecarCoverURL(in: sidecar)
            ?? ranobeDBCoverURL(in: ranobeDBBook)
            ?? ranobeDBCoverURL(in: ranobeDBSeries)
        let coverProvider = coverURL.flatMap { SableLibraryAppleBooksCompatibilityRepairer.coverProvider(for: $0) }
            ?? sourceIDs.first?.provider
        let localCoverCandidates = localEPUBImportCoverCandidates(
            for: epubURL,
            root: root,
            sidecarFolder: sidecarLocation.folder,
            detectedVolumeNumber: detectedVolumeNumber
        )
        let subjects = uniqueEPUBImportSubjects(
            arrayStrings(sidecar["genres"])
                + arrayStrings(sidecar["tags"])
                + arrayStrings(sidecar["content_warnings"])
                + ranobeDBTagNames(in: ranobeDBSeries)
                + providerV2Names(in: sidecar, provider: .mangabaka, key: "genres_v2")
                + providerV2Names(in: sidecar, provider: .mangabaka, key: "tags_v2")
        )
        let ranobeDBCredits = ranobeDBStaffCredits(in: [ranobeDBBook, ranobeDBSeries])
        let creatorCredits = uniqueEPUBImportCredits(
            sidecarCreatorNames("authors", in: sidecar).map { SableLibraryEPUBImportCredit(name: $0, role: .author) }
                + ranobeDBCredits.filter(\.role.belongsInCreatorElement)
                + sidecarCreatorNames("artists", in: sidecar).map { SableLibraryEPUBImportCredit(name: $0, role: .artist) }
        )
        let contributorCredits = uniqueEPUBImportCredits(
            sidecarCreatorNames("contributors", in: sidecar).map { SableLibraryEPUBImportCredit(name: $0, role: .contributor) }
                + ranobeDBCredits.filter { !$0.role.belongsInCreatorElement }
        )
        let ranobeDBPublishers = ranobeDBPublisherNames(in: [ranobeDBBook, ranobeDBSeries])
        let ranobeDBLanguages = ranobeDBLanguages(in: ranobeDBBook, series: ranobeDBSeries)
        let languages = epubImportLanguages(in: sidecar, ranobeDBLanguages: ranobeDBLanguages)

        return SableLibraryEPUBImportMetadata(
            title: importTitle,
            subtitle: subtitle,
            titleSort: SableLibraryAppleBooksCompatibilityRepairer.epub3FileAsTitle(importTitle),
            seriesTitle: seriesTitle,
            volumeNumber: detectedVolumeNumber,
            seriesPosition: seriesPosition,
            authors: uniqueEPUBImportStrings(
                creatorCredits.filter { $0.role == .author }.map(\.name)
            ),
            artists: uniqueEPUBImportStrings(
                creatorCredits.filter { $0.role == .artist }.map(\.name)
            ),
            contributors: uniqueEPUBImportStrings(contributorCredits.map(\.name)),
            creatorCredits: creatorCredits,
            contributorCredits: contributorCredits,
            publishers: uniqueEPUBImportStrings(
                arrayStrings(sidecar["publishers"])
                    + ranobeDBPublishers
                    + providerV2Names(in: sidecar, provider: .mangabaka, key: "publishers_v2", includeSpoilers: true)
            ),
            languages: languages,
            isbn13: uniqueEPUBImportStrings(partISBN + ranobeDBISBN + sidecarISBN),
            sourceIDs: sourceIDs,
            extraIdentifiers: epubImportExtraIdentifiers(in: sidecar, volume: volume, volumeNumber: detectedVolumeNumber),
            coverURL: coverURL,
            coverProvider: coverProvider,
            description: ranobeDBDescription(in: ranobeDBBook)
                ?? textValue(sidecar["description"])
                ?? ranobeDBDescription(in: ranobeDBSeries),
            subjects: subjects,
            releaseYear: partYear ?? yearFromPackedDate(ranobeDBReleaseDate) ?? integerValue(sidecar["year"]),
            releaseDate: partDate ?? ranobeDBReleaseDate,
            pageCount: integerValue(volume?["pages"]) ?? ranobeDBPageCount(in: ranobeDBBook),
            localCoverCandidates: localCoverCandidates
        )
    }

    func appleBooksCompatibilityRepairOutputRelativePath(
        for relativePath: String,
        config: SableLibraryConfig
    ) -> String {
        relativePath
    }

    func appleBooksCompatibilityRepairAnalysis(
        for epubURL: URL,
        relativePath: String,
        root: URL,
        config: SableLibraryConfig,
        deepContentChecks: Bool = false,
        optimizePageImageEPUBs: Bool = false,
        importMetadata: SableLibraryEPUBImportMetadata? = nil,
        trustedCoverURLString: String? = nil,
        localCoverCandidates: [SableLibraryEPUBImportCoverCandidate] = [],
        coverProvider: SableLibraryMetadataProvider? = nil,
        repairScopes: Set<SableLibraryEPUBRepairScope> = SableLibraryEPUBRepairScope.all
    ) -> LibraryAppleBooksCompatibilityRepairAnalysis? {
        guard epubURL.pathExtension.lowercased() == "epub" else { return nil }
        guard !Task.isCancelled else { return nil }

        do {
            let archive = try SableLibraryAppleBooksCompatibilityRepairer.archiveSnapshot(for: epubURL)
            guard !Task.isCancelled else { return nil }
            let entries = archive.entries
            guard !entries.isEmpty else { return nil }

            let effectiveScopes = repairScopes.isEmpty ? SableLibraryEPUBRepairScope.all : repairScopes
            let wantsMetadata = effectiveScopes.contains(.metadata)
            let wantsTags = effectiveScopes.contains(.tags)
            let wantsCover = effectiveScopes.contains(.cover)
            let wantsReaderImport = effectiveScopes.contains(.readerImport)
            let wantsNavigation = effectiveScopes.contains(.navigation)
            let wantsStructure = effectiveScopes.contains(.structure)
            let wantsPackage = effectiveScopes.contains(.package)
            let wantsContent = effectiveScopes.contains(.content)
            let wantsCompatibility = effectiveScopes.contains(.compatibility)
            let wantsDiagnostics = effectiveScopes.contains(.diagnostics)
            let resolvedCoverProvider = importMetadata?.coverProvider ?? coverProvider
            let protection = try SableLibraryAppleBooksCompatibilityRepairer.protectionAnalysis(in: archive)
            if protection.isProtected {
                return LibraryAppleBooksCompatibilityRepairAnalysis(
                    reasons: [protection.reason ?? "EPUB contains encrypted content resources"],
                    outputRelativePath: appleBooksCompatibilityRepairOutputRelativePath(
                        for: relativePath,
                        config: config
                    ),
                    downloadsTrustedCover: false,
                    coverProvider: resolvedCoverProvider,
                    protection: protection
                )
            }

            var reasons: [String] = []
            if wantsCompatibility, entries.first != "mimetype" {
                reasons.append("mimetype is not first")
            }

            let rootEntries = Set(entries.filter { !$0.contains("/") })
            let appleMetadata = SableLibraryAppleBooksCompatibilityRepairer.appleMetadataFiles.filter { rootEntries.contains($0) }
            if wantsCompatibility, !appleMetadata.isEmpty {
                reasons.append("Has root iTunesMetadata plist file(s)")
            }

            var downloadsTrustedCover = false
            let resolvedCoverURL = importMetadata?.coverURL ?? trustedCoverURLString
            let resolvedLocalCoverCandidates = importMetadata?.localCoverCandidates ?? localCoverCandidates
            let hasLocalCoverCandidate = !resolvedLocalCoverCandidates.isEmpty
            let runsFixedLayoutChecks = (deepContentChecks || optimizePageImageEPUBs)
                && (wantsDiagnostics || wantsNavigation || wantsStructure)

            // Default Clinic scans stay lightweight: ZIP entry names, OPF metadata,
            // and NCX wiring. Deep content/image reads are opt-in.
            if let opfPath = try SableLibraryAppleBooksCompatibilityRepairer.opfPath(in: archive),
               let opfText = try SableLibraryAppleBooksCompatibilityRepairer.entryText(opfPath, in: archive) {
                guard !Task.isCancelled else { return nil }
                if wantsCover || wantsDiagnostics {
                    let cover = SableLibraryAppleBooksCompatibilityRepairer.coverAnalysis(in: opfText)
                    if cover.hasImageManifestItems {
                        if wantsCover, !cover.hasEPUB2CoverMeta {
                            reasons.append("Missing or invalid EPUB2 cover meta")
                        }
                        if wantsCover, !cover.hasEPUB3CoverImage {
                            reasons.append("Missing EPUB3 cover-image marker")
                        }
                        if wantsCover,
                           hasLocalCoverCandidate,
                           let replacementReason = SableLibraryAppleBooksCompatibilityRepairer.localCoverReplacementReason(
                               opfText: opfText,
                               opfPath: opfPath,
                               archive: archive,
                               candidates: resolvedLocalCoverCandidates,
                               fallbackLanguages: importMetadata?.languages ?? []
                           ) {
                            reasons.append(replacementReason)
                        }
                    } else if wantsCover, resolvedCoverURL != nil || hasLocalCoverCandidate {
                        if hasLocalCoverCandidate {
                            reasons.append("Add missing EPUB cover from local language-matched cover file")
                        } else {
                            downloadsTrustedCover = true
                            reasons.append("Download missing cover from trusted ComicInfo cover URL")
                        }
                    }
                }

                if wantsReaderImport {
                    let cover = SableLibraryAppleBooksCompatibilityRepairer.coverAnalysis(in: opfText)
                    if cover.hasImageManifestItems || resolvedCoverURL != nil || hasLocalCoverCandidate {
                        reasons.append("Refresh Apple Books cover import identity after a stale or placeholder library entry")
                    }
                }

                if runsFixedLayoutChecks {
                    guard !Task.isCancelled else { return nil }
                    let fixedLayout = try SableLibraryAppleBooksCompatibilityRepairer.fixedLayoutTextAnalysis(
                        entries: entries,
                        in: archive,
                        opfText: opfText
                    )

                    if wantsDiagnostics, fixedLayout.isPageImageFixedLayout {
                        if !SableLibraryAppleBooksCompatibilityRepairer.hasFreshSableImportIdentifier(opfText) {
                            reasons.append("Fixed-layout page-image EPUB compatibility refresh")
                        }

                        if fixedLayout.hasPageBoxMismatch {
                            reasons.append("Fixed-layout page box mismatch")
                        }

                        if optimizePageImageEPUBs,
                           !SableLibraryAppleBooksCompatibilityRepairer.hasFreshSableImportIdentifier(opfText) {
                            reasons.append("Lossy page-image optimization")
                        }
                    }

                    if deepContentChecks, wantsNavigation, !fixedLayout.isPageImageFixedLayout {
                        guard !Task.isCancelled else { return nil }
                        reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.navigationRepairReasons(
                            entries: entries,
                            in: archive,
                            opfPath: opfPath,
                            opfText: opfText
                        ))
                    }
                    if deepContentChecks, wantsStructure, !fixedLayout.isPageImageFixedLayout {
                        guard !Task.isCancelled else { return nil }
                        reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.structureRepairReasons(
                            entries: entries,
                            in: archive,
                            opfPath: opfPath,
                            opfText: opfText
                        ))
                    }
                }

                if wantsTags {
                    reasons.append(contentsOf: SableLibraryAppleBooksCompatibilityRepairer.subjectTagCasingRepairReasons(
                        in: opfText
                    ))
                }
                if wantsPackage || wantsCover {
                    reasons.append(contentsOf: SableLibraryAppleBooksCompatibilityRepairer.manifestCompatibilityRepairReasons(
                        entries: entries,
                        opfPath: opfPath,
                        opfText: opfText
                    ))
                }
                if deepContentChecks, (wantsContent || wantsDiagnostics) {
                    guard !Task.isCancelled else { return nil }
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.linkedResourceRepairReasons(
                        in: archive,
                        opfPath: opfPath,
                        opfText: opfText
                    ))
                }
                if deepContentChecks, wantsContent {
                    guard !Task.isCancelled else { return nil }
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.contentManifestPropertiesRepairReasons(
                        in: archive,
                        opfPath: opfPath,
                        opfText: opfText
                    ))
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.contentDocumentHeaderRepairReasons(
                        in: archive,
                        opfPath: opfPath,
                        opfText: opfText
                    ))
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.stylesheetRepairReasons(
                        in: archive,
                        opfPath: opfPath,
                        opfText: opfText
                    ))
                }
                if wantsCompatibility {
                    reasons.append(contentsOf: SableLibraryAppleBooksCompatibilityRepairer.metadataCompatibilityRepairReasons(
                        in: opfText
                    ))
                }
                if wantsNavigation || wantsCompatibility {
                    guard !Task.isCancelled else { return nil }
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.ncxIdentifierRepairReasons(
                        entries: entries,
                        in: archive,
                        opfText: opfText
                    ))
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.ncxResourcePathRepairReasons(
                        entries: entries,
                        in: archive,
                        opfPath: opfPath,
                        opfText: opfText
                    ))
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.ncxFragmentRepairReasons(
                        entries: entries,
                        in: archive
                    ))
                    reasons.append(contentsOf: try SableLibraryAppleBooksCompatibilityRepairer.ncxPlayOrderRepairReasons(
                        entries: entries,
                        in: archive
                    ))
                }
                if wantsCompatibility {
                    reasons.append(contentsOf: SableLibraryAppleBooksCompatibilityRepairer.standardsProfileRepairReasons(
                        in: opfText
                    ))
                }
            }

            if (wantsMetadata || wantsTags),
               let importMetadata,
               let opfPath = try SableLibraryAppleBooksCompatibilityRepairer.opfPath(in: archive),
               let opfText = try SableLibraryAppleBooksCompatibilityRepairer.entryText(opfPath, in: archive) {
                guard !Task.isCancelled else { return nil }
                reasons.append(contentsOf: SableLibraryAppleBooksCompatibilityRepairer.importMetadataChangeReasons(
                    importMetadata,
                    currentOPFText: opfText
                ))
            }

            guard !reasons.isEmpty else { return nil }

            return LibraryAppleBooksCompatibilityRepairAnalysis(
                reasons: reasons,
                outputRelativePath: appleBooksCompatibilityRepairOutputRelativePath(
                    for: relativePath,
                    config: config
                ),
                downloadsTrustedCover: downloadsTrustedCover,
                coverProvider: resolvedCoverProvider,
                protection: protection
            )
        } catch {
            return nil
        }
    }

    func applyAppleBooksCompatibilityRepairs(
        root: URL,
        paths: [String],
        reportTitle: String,
        reportName: String,
        optimizePageImageEPUBs: Bool = false,
        importMetadataByPath: [String: SableLibraryEPUBImportMetadata] = [:],
        trustedCoverURLByPath: [String: String] = [:],
        localCoverCandidatesByPath: [String: [SableLibraryEPUBImportCoverCandidate]] = [:],
        repairScopesByPath: [String: Set<SableLibraryEPUBRepairScope>] = [:]
    ) async -> LibraryAppleBooksCompatibilityRepairApplyResult {
        let config = currentConfig()
        var applied: [String] = []
        var skipped: [String] = []
        var failed: [String: String] = [:]

        let orderedPaths = paths.sorted()
        let totalCount = orderedPaths.count
        let startedAt = Date()
        let work = orderedPaths.map { path in
            let importMetadata = importMetadataByPath[path]
            return SableLibraryAppleBooksCompatibilityRepairWorkItem(
                path: path,
                sourceURL: root.appendingPathComponent(path),
                optimizePageImageEPUBs: optimizePageImageEPUBs,
                importMetadata: importMetadata,
                trustedCoverURLString: importMetadata?.coverURL ?? trustedCoverURLByPath[path],
                localCoverCandidates: importMetadata?.localCoverCandidates ?? localCoverCandidatesByPath[path] ?? [],
                repairScopes: repairScopesByPath[path] ?? SableLibraryEPUBRepairScope.all
            )
        }
        let workerCount = min(
            work.count,
            min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        )

        if workerCount > 0 {
            reportProgress("Repairing Apple Books EPUBs with up to \(workerCount) books at once.")
            await withTaskGroup(of: SableLibraryAppleBooksCompatibilityRepairTaskResult.self) { group in
                var nextIndex = 0
                var completedCount = 0
                var stopped = false

                while nextIndex < workerCount {
                    let item = work[nextIndex]
                    group.addTask(priority: .utility) {
                        await SableLibraryAppleBooksCompatibilityRepairer.runRepair(item)
                    }
                    nextIndex += 1
                }

                while let result = await group.next() {
                    completedCount += 1
                    let finishedPath: String
                    switch result {
                    case .applied(let path):
                        finishedPath = path
                        applied.append("\(path) repaired in place")
                    case .skipped(let path, let reason):
                        finishedPath = path
                        skipped.append("\(path): \(reason)")
                    case .failed(let path, let message):
                        finishedPath = path
                        failed[path] = message
                    case .cancelled(let path):
                        finishedPath = path
                        stopped = true
                        group.cancelAll()
                    }

                    let timing = SableLibraryWorkTiming.summary(
                        startedAt: startedAt,
                        completedCount: completedCount,
                        totalCount: totalCount,
                        unit: "EPUB"
                    )
                    reportProgressSnapshot(SableLibraryProgressSnapshot(
                        title: "Applying Sable's Clinic",
                        message: "Checked EPUB \(completedCount) of \(totalCount). \(timing) Last finished: \(finishedPath)",
                        completedUnitCount: completedCount,
                        totalUnitCount: totalCount
                    ))

                    if !stopped, nextIndex < work.count {
                        let item = work[nextIndex]
                        group.addTask(priority: .utility) {
                            await SableLibraryAppleBooksCompatibilityRepairer.runRepair(item)
                        }
                        nextIndex += 1
                    }
                }
            }
        }

        let report = appleBooksCompatibilityRepairReport(
            title: reportTitle,
            applied: applied,
            skipped: skipped,
            failed: failed
        )

        do {
            try writeReport(report, named: reportName, root: root, config: config)
        } catch {
            failed["_receipt"] = error.localizedDescription
        }

        return LibraryAppleBooksCompatibilityRepairApplyResult(
            applied: applied,
            skipped: skipped,
            failed: failed,
            report: report,
            changedFiles: !applied.isEmpty
        )
    }

    private func appleBooksCompatibilityRepairReport(
        title: String,
        applied: [String],
        skipped: [String],
        failed: [String: String]
    ) -> String {
        var lines = [
            title,
            String(repeating: "=", count: title.count),
            "",
            "Repaired Apple Books compatibility EPUBs: \(applied.count)",
            "Skipped: \(skipped.count)",
            "Failed: \(failed.count)",
            "",
            "Original EPUB files were replaced only after a temporary repaired EPUB validated.",
            "No duplicate repaired copies or persistent backup EPUBs are kept after a successful repair.",
            "When enabled, EPUB import metadata is mirrored from local ComicInfo/RanobeDB/Open Library/Wikidata sidecars without fresh provider calls.",
            "Missing EPUB cover images are filled from local language-matched cover files when available, then from trusted cover URLs already saved in local sidecars.",
            "Existing EPUB cover images are replaced only when a local language-matched cover is clearly higher quality."
        ]

        if !applied.isEmpty {
            lines.append("\nRepaired EPUBs:")
            lines.append(contentsOf: applied.map { "- \($0)" })
        }
        if !skipped.isEmpty {
            lines.append("\nSkipped:")
            lines.append(contentsOf: skipped.map { "- \($0)" })
        }
        if !failed.isEmpty {
            lines.append("\nFailed:")
            for (path, reason) in failed.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(path): \(reason)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func nearestComicInfoSidecar(
        for epubURL: URL,
        root: URL,
        config: SableLibraryConfig
    ) -> [String: Any]? {
        nearestComicInfoSidecarLocation(for: epubURL, root: root, config: config)?.sidecar
    }

    private func nearestComicInfoSidecarLocation(
        for epubURL: URL,
        root: URL,
        config: SableLibraryConfig
    ) -> (sidecar: [String: Any], folder: URL)? {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var folder = epubURL.deletingLastPathComponent().standardizedFileURL

        while true {
            let folderPath = folder.path(percentEncoded: false)
            guard folderPath == rootPath || folderPath.hasPrefix(rootPrefix) else {
                return nil
            }

            let sidecarURL = folder.appendingPathComponent(config.comicInfoFileName)
            if folderPath != rootPath,
               let sidecar = readJSONDictionary(at: sidecarURL, within: rootURL),
               epubImportSidecar(sidecar, matches: epubURL, sidecarFolder: folder) {
                return (sidecar, folder)
            }

            guard folderPath != rootPath else { return nil }
            folder.deleteLastPathComponent()
        }
    }

    private func epubImportSidecar(
        _ sidecar: [String: Any],
        matches epubURL: URL,
        sidecarFolder: URL
    ) -> Bool {
        let titles = sidecarTitleStrings(in: sidecar)
        guard !titles.isEmpty else { return false }

        let scopeTitles = [
            sidecarFolder.lastPathComponent,
            epubURL.deletingPathExtension().lastPathComponent
        ]

        return titles.contains { title in
            let titleKey = normalizeTerm(title)
            guard !titleKey.isEmpty else { return false }
            return scopeTitles.contains { scopeTitle in
                let scopeKey = normalizeTerm(cleanSeriesTitle(scopeTitle))
                return !scopeKey.isEmpty
                    && (scopeKey == titleKey
                        || scopeKey.contains(titleKey)
                        || titleKey.contains(scopeKey))
            }
        }
    }

    private func standaloneEPUBSeriesPosition(
        for epubURL: URL,
        cleanedFileTitle: String,
        seriesTitle: String
    ) -> Int? {
        guard volumeOrChapterSuffix(in: cleanedFileTitle) == nil else {
            return nil
        }

        let parentURL = epubURL.deletingLastPathComponent()
        let siblingEPUBCount = (try? fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { sibling in
            guard sibling.pathExtension.lowercased() == "epub" else { return false }
            let values = try? sibling.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }.count) ?? 0

        guard siblingEPUBCount == 1 else {
            return nil
        }

        let seriesKey = normalizeTerm(seriesTitle)
        guard !seriesKey.isEmpty else {
            return nil
        }
        let candidateKeys = [
            standaloneEPUBSeriesTitleKey(cleanedFileTitle),
            standaloneEPUBSeriesTitleKey(parentURL.lastPathComponent)
        ].filter { !$0.isEmpty }
        return candidateKeys.contains(seriesKey) ? 1 : nil
    }

    private func standaloneEPUBSeriesTitleKey(_ value: String) -> String {
        let stripped = value
            .replacingOccurrences(of: #"\s*\{[A-Za-z_]+-[^}]+\}\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeTerm(cleanSeriesTitle(stripped.isEmpty ? value : stripped))
    }

    private func epubImportLanguages(in sidecar: [String: Any], ranobeDBLanguages: [String]) -> [String] {
        let explicit = uniqueEPUBImportStrings(
            arrayStrings(sidecar["languages"])
                + arrayStrings(sidecar["language"])
                + arrayStrings(sidecar["translated_language"])
                + arrayStrings(sidecar["translation_language"])
                + ranobeDBLanguages
        )
        if !explicit.isEmpty {
            return explicit
        }

        return sidecarIndicatesEnglishImport(sidecar) ? ["en"] : []
    }

    private func sidecarIndicatesEnglishImport(_ sidecar: [String: Any]) -> Bool {
        let searchable = uniqueEPUBImportStrings(
            [textValue(sidecar["description"])].compactMap { $0 }
                + groupedURLSourceLinks(in: sidecar)
                + sidecarTitleVariantStrings(in: sidecar)
        )
        let normalized = normalizeTerm(searchable.joined(separator: " "))
        guard normalized.contains("official translations") || normalized.contains("official translation") else {
            return false
        }
        return normalized.contains("english")
    }

    private func readJSONDictionary(at url: URL, within root: URL) -> [String: Any]? {
        guard resolvesInside(url, root: root),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func resolvesInside(_ url: URL, root: URL) -> Bool {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        return resolvedPath == rootPath || resolvedPath.hasPrefix(rootPrefix)
    }

    private func matchingVolume(_ number: Int, in sidecar: [String: Any]) -> [String: Any]? {
        guard let volumes = sidecar["volumes"] as? [[String: Any]] else { return nil }
        return volumes.first { integerValue($0["number"]) == number }
    }

    private func matchingEPUBImportVolume(_ number: Int, in sidecar: [String: Any]) -> [String: Any]? {
        guard let volumes = sidecar["volumes"] as? [[String: Any]] else { return nil }
        let directVolume = volumes.first { integerValue($0["number"]) == number }
        let scopeMarkers = sidecarReadingScopeMarkers(in: sidecar)

        if let directVolume,
           trustedEPUBImportVolume(directVolume, expectedVolumeNumber: number, scopeMarkers: scopeMarkers) {
            return directVolume
        }

        return volumes.first {
            trustedEPUBImportVolume($0, expectedVolumeNumber: number, scopeMarkers: [])
        } ?? directVolume
    }

    private func trustedEPUBImportVolume(
        _ volume: [String: Any],
        expectedVolumeNumber: Int,
        scopeMarkers: Set<String>
    ) -> Bool {
        guard volumeSourceID(in: volume)?.provider == .ranobedb,
              let title = textValue(volume["title"]),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let suffix = volumeOrChapterSuffix(in: title),
              let titleVolumeNumber = volumeNumber(in: suffix) else {
            return false
        }

        if titleVolumeNumber == expectedVolumeNumber {
            return true
        }

        guard !scopeMarkers.isEmpty,
              integerValue(volume["number"]) == expectedVolumeNumber else {
            return false
        }
        let titleKey = normalizeTerm(title)
        return scopeMarkers.contains { titleKey.contains($0) }
    }

    private func trustedEPUBImportBookTitle(
        in volume: [String: Any]?,
        sidecar: [String: Any],
        expectedVolumeNumber: Int
    ) -> String? {
        guard let volume,
              let title = textValue(volume["title"]),
              trustedEPUBImportVolume(
                volume,
                expectedVolumeNumber: expectedVolumeNumber,
                scopeMarkers: sidecarReadingScopeMarkers(in: sidecar)
              ) else {
            return nil
        }

        let compacted = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compacted.isEmpty ? nil : compacted
    }

    private func volumeSourceID(in volume: [String: Any]) -> SableLibrarySourceID? {
        guard let dictionary = volume["source_id"] as? [String: Any],
              let providerName = textValue(dictionary["provider"]),
              let provider = SableLibraryMetadataProvider(rawValue: providerName),
              let value = textValue(dictionary["value"]),
              !value.isEmpty else {
            return nil
        }
        return SableLibrarySourceID(provider: provider, value: value)
    }

    private func sidecarOrganizerSourceID(in sidecar: [String: Any]) -> SableLibrarySourceID? {
        guard let organizer = sidecar["organizer"] as? [String: Any] else { return nil }
        return volumeSourceID(in: organizer)
    }

    private func epubImportSourceIDs(
        sidecarSourceIDs: [SableLibrarySourceID],
        matchedVolumeSourceID: SableLibrarySourceID?,
        detectedVolumeNumber: Int?
    ) -> [SableLibrarySourceID] {
        guard detectedVolumeNumber != nil else {
            return sidecarSourceIDs
        }

        return sidecarSourceIDs.filter { sourceID in
            guard sourceID.provider == .openLibrary else {
                return true
            }
            return matchedVolumeSourceID?.provider == .openLibrary
                && matchedVolumeSourceID?.value == sourceID.value
        }
    }

    private func sidecarReadingScopeMarkers(in sidecar: [String: Any]) -> Set<String> {
        let values = [
            textValue(sidecar["preferred_title"]),
            textValue(sidecar["title"]),
            textValue(sidecar["local_title"])
        ].compactMap { $0 }

        var markers = Set<String>()
        for value in values {
            let normalized = normalizeTerm(value)
            markers.formUnion(regexMatches(#"\bpart\s+\d{1,3}\b"#, in: normalized))
            markers.formUnion(regexMatches(#"\bbook\s+\d{1,3}\b"#, in: normalized))
        }
        return markers
    }

    private func regexMatches(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value) else { return nil }
            return String(value[matchRange])
        }
    }

    private func epubImportExtraIdentifiers(
        in sidecar: [String: Any],
        volume: [String: Any]?,
        volumeNumber: Int?
    ) -> [SableLibraryEPUBImportIdentifier] {
        var identifiers: [SableLibraryEPUBImportIdentifier] = []

        if volumeSourceID(in: volume ?? [:])?.provider == .ranobedb || volumeNumber != nil {
            let releaseIDs = uniqueEPUBImportStrings(
                arrayStrings(volume?["release_ids"])
                    + ranobeDBReleaseIDs(in: ranobeDBAPIBook(in: sidecar, volumeNumber: volumeNumber))
            )
            for releaseID in releaseIDs {
                let cleanID = releaseID.replacingOccurrences(
                    of: #"[^a-zA-Z0-9_-]+"#,
                    with: "-",
                    options: .regularExpression
                )
                guard !cleanID.isEmpty else { continue }
                identifiers.append(
                    SableLibraryEPUBImportIdentifier(
                        id: "sable-release-ranobedb-\(cleanID)",
                        value: "ranobedb-release:\(releaseID)"
                    )
                )
            }
        }

        for (index, link) in epubImportSourceLinks(in: sidecar, volumeNumber: volumeNumber).enumerated() {
            identifiers.append(
                SableLibraryEPUBImportIdentifier(
                    id: "sable-link-\(index + 1)",
                    value: link
                )
            )
        }

        return uniqueEPUBImportIdentifiers(identifiers)
    }

    private func epubImportSourceLinks(in sidecar: [String: Any], volumeNumber: Int? = nil) -> [String] {
        var links: [String] = []
        links += linkStrings(sidecar["mangabaka_url"])
        links += linkStrings(sidecar["links"])
        links += linkStrings(sidecar["links_v2"])
        links += groupedURLSourceLinks(in: sidecar)
        links += ranobeDBLinks(in: sidecar, volumeNumber: volumeNumber)

        if let sable = sidecar["_sable"] as? [String: Any] {
            for provider in SableLibraryMetadataProvider.allCases {
                if let providerPayload = sable[provider.rawValue] as? [String: Any] {
                    links += linkStrings(providerPayload["links"])
                    links += linkStrings(providerPayload["links_v2"])
                    links += linkStrings(providerPayload["url"])
                }
            }
        }

        var seen = Set<String>()
        return links.compactMap { link in
            guard let trusted = trustedEPUBImportSourceLink(link) else { return nil }
            let key = trusted.lowercased()
            return seen.insert(key).inserted ? trusted : nil
        }
    }

    private func linkStrings(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let rows = value as? [[String: Any]] {
            return rows.flatMap { linkStrings($0) }
        }
        if let row = value as? [String: Any] {
            return [
                textValue(row["url"]),
                textValue(row["href"]),
                textValue(row["link"]),
                textValue(row["value"])
            ].compactMap { $0 }
        }
        if let values = value as? [Any] {
            return values.flatMap { linkStrings($0) }
        }
        if let value = textValue(value) {
            return [value]
        }
        return []
    }

    private func trustedEPUBImportSourceLink(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url.absoluteString
    }

    private func ranobeDBAPIBlock(in sidecar: [String: Any]) -> [String: Any]? {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any] else {
            return nil
        }
        return (ranobeDB["api"] as? [String: Any])
            ?? (ranobeDB["api_compact"] as? [String: Any])
    }

    private func ranobeDBAPISeries(in sidecar: [String: Any]) -> [String: Any]? {
        guard let api = ranobeDBAPIBlock(in: sidecar) else { return nil }
        if let series = api["series"] as? [String: Any] {
            return series
        }
        if let response = api["series_response"] as? [String: Any],
           let series = response["series"] as? [String: Any] {
            return series
        }
        return nil
    }

    private func ranobeDBAPIBook(in sidecar: [String: Any], volumeNumber: Int?) -> [String: Any]? {
        guard let volumeNumber,
              let api = ranobeDBAPIBlock(in: sidecar),
              let responses = api["book_responses"] as? [[String: Any]] else {
            return nil
        }

        for row in responses {
            guard integerValue(row["volume_number"]) == volumeNumber else { continue }
            let response = row["response"] as? [String: Any] ?? row
            return response["book"] as? [String: Any] ?? response
        }
        return nil
    }

    private func ranobeDBDescription(in object: [String: Any]?) -> String? {
        guard let object else { return nil }
        let releaseDescription = preferredRanobeDBReleases(in: object)
            .compactMap { textValue($0["description"]) }
            .first
        let bookDescription = object["book_description"] as? [String: Any]
        return [
            textValue(object["description"]),
            releaseDescription,
            textValue(bookDescription?["description"]),
            textValue(object["description_ja"]),
            textValue(bookDescription?["description_ja"])
        ].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.first { !$0.isEmpty }
    }

    private func ranobeDBStaffCredits(in objects: [[String: Any]?]) -> [SableLibraryEPUBImportCredit] {
        var rows: [[String: Any]] = []
        for object in objects.compactMap({ $0 }) {
            rows += object["staff"] as? [[String: Any]] ?? []
            for edition in object["editions"] as? [[String: Any]] ?? [] {
                rows += edition["staff"] as? [[String: Any]] ?? []
            }
        }

        return uniqueEPUBImportCredits(rows.compactMap { row in
            guard let name = textValue(row["name"]),
                  let role = epubImportCreditRole(from: textValue(row["role_type"])) else {
                return nil
            }
            return SableLibraryEPUBImportCredit(name: name, role: role)
        })
    }

    private func epubImportCreditRole(from value: String?) -> SableLibraryEPUBImportCreditRole? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "author":
            return .author
        case "artist":
            return .artist
        case "editor":
            return .editor
        case "translator":
            return .translator
        case "narrator":
            return .narrator
        case "staff":
            return .staff
        default:
            return nil
        }
    }

    private func ranobeDBPublisherNames(in objects: [[String: Any]?]) -> [String] {
        uniqueEPUBImportStrings(objects.compactMap { $0 }.flatMap { object in
            (object["publishers"] as? [[String: Any]] ?? []).compactMap { textValue($0["name"]) }
        })
    }

    private func ranobeDBLanguages(in book: [String: Any]?, series: [String: Any]?) -> [String] {
        var values = [
            textValue(book?["lang"]),
            textValue(book?["olang"]),
            textValue(series?["lang"]),
            textValue(series?["olang"])
        ].compactMap { $0 }
        values += (book?["titles"] as? [[String: Any]] ?? []).compactMap { textValue($0["lang"]) }
        values += (series?["titles"] as? [[String: Any]] ?? []).compactMap { textValue($0["lang"]) }
        values += (book?["releases"] as? [[String: Any]] ?? []).compactMap { textValue($0["lang"]) }
        return uniqueEPUBImportStrings(values)
    }

    private func ranobeDBTagNames(in series: [String: Any]?) -> [String] {
        guard let series else { return [] }
        return uniqueEPUBImportStrings((series["tags"] as? [[String: Any]] ?? []).compactMap { textValue($0["name"]) })
    }

    private func ranobeDBISBN13(in book: [String: Any]?) -> [String] {
        uniqueEPUBImportStrings(preferredRanobeDBReleases(in: book).compactMap { textValue($0["isbn13"]) })
    }

    private func ranobeDBReleaseIDs(in book: [String: Any]?) -> [String] {
        uniqueEPUBImportStrings(preferredRanobeDBReleases(in: book).compactMap { textValue($0["id"]) })
    }

    private func ranobeDBReleaseDate(in book: [String: Any]?) -> Int? {
        preferredRanobeDBReleases(in: book).compactMap { integerValue($0["release_date"]) }.first
    }

    private func ranobeDBPageCount(in book: [String: Any]?) -> Int? {
        preferredRanobeDBReleases(in: book).compactMap { integerValue($0["pages"]) }.first
            ?? integerValue(book?["pages"])
    }

    private func preferredRanobeDBReleases(in book: [String: Any]?) -> [[String: Any]] {
        guard let releases = book?["releases"] as? [[String: Any]],
              !releases.isEmpty else {
            return []
        }
        let english = releases.filter { textValue($0["lang"]) == "en" }
        return english.isEmpty ? releases : english
    }

    private func ranobeDBLinks(in sidecar: [String: Any], volumeNumber: Int?) -> [String] {
        let series = ranobeDBAPISeries(in: sidecar)
        let book = ranobeDBAPIBook(in: sidecar, volumeNumber: volumeNumber)
        var links = [textValue(series?["web_novel"])].compactMap { $0 }
        for release in preferredRanobeDBReleases(in: book) {
            links += [
                textValue(release["website"]),
                textValue(release["amazon"]),
                textValue(release["bookwalker"]),
                textValue(release["rakuten"])
            ].compactMap { $0 }
        }
        return uniqueEPUBImportStrings(links)
    }

    private func ranobeDBCoverURL(in object: [String: Any]?) -> String? {
        guard let object else { return nil }
        if let direct = textValue(object["cover_url"]) ?? textValue(object["image_url"]) {
            return normalizedURLString(direct)
        }
        guard let image = object["image"] as? [String: Any] else { return nil }
        if let url = textValue(image["url"]) {
            return normalizedURLString(url)
        }
        guard let filename = textValue(image["filename"]) else { return nil }
        if filename.hasPrefix("http://") || filename.hasPrefix("https://") || filename.hasPrefix("//") {
            return normalizedURLString(filename)
        }
        let trimmed = filename.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return "https://images.ranobedb.org/\(trimmed)"
    }

    private func normalizedURLString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if trimmed.hasPrefix("http://") {
            return "https://" + trimmed.dropFirst("http://".count)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func yearFromPackedDate(_ value: Int?) -> Int? {
        guard let value, value >= 10_000 else { return nil }
        return value / 10_000
    }

    private func providerV2Names(
        in sidecar: [String: Any],
        provider: SableLibraryMetadataProvider,
        key: String,
        includeSpoilers: Bool = false
    ) -> [String] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let providerPayload = sable[provider.rawValue] as? [String: Any],
              let rows = providerPayload[key] as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { row in
            if !includeSpoilers, (row["is_spoiler"] as? Bool) == true {
                return nil
            }
            return textValue(row["name"])
        }
    }

    private func sidecarTitleStrings(in sidecar: [String: Any]) -> [String] {
        uniqueEPUBImportStrings(
            arrayStrings(sidecar["preferred_title"])
                + arrayStrings(sidecar["title"])
                + arrayStrings(sidecar["local_title"])
                + arrayStrings(sidecar["aliases"])
                + sidecarTitleVariantStrings(in: sidecar)
        )
    }

    private func sidecarTitleVariantStrings(in sidecar: [String: Any]) -> [String] {
        guard let variants = sidecar["title_variants"] as? [String: Any] else { return [] }
        return variants.values.flatMap { arrayStrings($0) }
    }

    private func sidecarCreatorNames(_ key: String, in sidecar: [String: Any]) -> [String] {
        var values = arrayStrings(sidecar[key])
        if let creators = sidecar["creators"] as? [String: Any] {
            values += arrayStrings(creators[key])
        }
        return uniqueEPUBImportStrings(values)
    }

    private func groupedURLSourceLinks(in sidecar: [String: Any]) -> [String] {
        guard let urls = sidecar["urls"] as? [String: Any] else { return [] }
        let directKeys = [
            "mangabaka", "ranobedb", "openlibrary", "open_library",
            "anilist", "myanimelist", "my_anime_list", "mal",
            "wikidata", "publisher", "official", "website", "web",
            "source", "links", "links_v2"
        ]

        var links = directKeys.flatMap { linkStrings(urls[$0]) }
        links += linkStrings(urls["external"])
        return links
    }

    private func uniqueSourceIDs(_ values: [SableLibrarySourceID]) -> [SableLibrarySourceID] {
        var seen = Set<String>()
        return values.compactMap { sourceID in
            let cleanValue = sourceID.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanValue.isEmpty else { return nil }
            let key = "\(sourceID.provider.rawValue):\(cleanValue)"
            return seen.insert(key).inserted
                ? SableLibrarySourceID(provider: sourceID.provider, value: cleanValue)
                : nil
        }
    }

    private func uniqueEPUBImportIdentifiers(
        _ values: [SableLibraryEPUBImportIdentifier]
    ) -> [SableLibraryEPUBImportIdentifier] {
        var seen = Set<String>()
        return values.compactMap { identifier in
            let cleanID = identifier.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanValue = identifier.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanID.isEmpty, !cleanValue.isEmpty else { return nil }
            let key = "\(cleanID)|\(cleanValue)"
            return seen.insert(key).inserted
                ? SableLibraryEPUBImportIdentifier(id: cleanID, value: cleanValue)
                : nil
        }
    }

    private func trustedSidecarCoverURL(in sidecar: [String: Any]) -> String? {
        var candidates: [String?] = [
            textValue(sidecar["cover_url"]),
            textValue(sidecar["coverURL"])
        ]
        if let urls = sidecar["urls"] as? [String: Any] {
            candidates.append(textValue(urls["cover"]))
            candidates.append(textValue(urls["cover_url"]))
            candidates.append(textValue(urls["coverURL"]))
        }
        if let cover = sidecar["cover"] as? [String: Any] {
            candidates.append(textValue(cover["url"]))
            if let raw = cover["raw"] as? [String: Any] {
                candidates.append(textValue(raw["url"]))
            }
        }

        for candidate in candidates {
            guard let candidate,
                  let normalized = SableLibraryAppleBooksCompatibilityRepairer.trustedCoverDownloadURLString(from: candidate) else {
                continue
            }
            return normalized
        }
        return nil
    }

    private func localEPUBImportCoverCandidates(
        for epubURL: URL,
        root: URL,
        sidecarFolder: URL,
        detectedVolumeNumber: Int?
    ) -> [SableLibraryEPUBImportCoverCandidate] {
        let coversFolder = sidecarFolder.appendingPathComponent("_covers", isDirectory: true)
        let manifestURL = coversFolder.appendingPathComponent("cover-manifest.json")
        guard let manifest = readJSONDictionary(at: manifestURL, within: root),
              let entries = manifest["entries"] as? [[String: Any]] else {
            return []
        }
        let manifestVersion = integerValue(manifest["version"]) ?? 1
        let manifestSeriesTitle = textValue(manifest["series_title"])
        let manifestMediaType = textValue(manifest["media_type"])

        let fileName = epubURL.lastPathComponent
        let parsedCoverVolume = SableLibraryCoverDownloadPlanner.localVolumeNumber(
            fileName: fileName,
            seriesTitles: manifestSeriesTitle.map { [$0] } ?? []
        )
        let exactEntries = entries.filter {
            textValue($0["book_file"])?.caseInsensitiveCompare(fileName) == .orderedSame
        }
        let volumeEntries: [[String: Any]]
        if exactEntries.isEmpty, let detectedVolumeNumber {
            volumeEntries = entries.filter {
                guard let volume = doubleValue($0["volume"]) else { return false }
                return SableLibraryCoverDownloadPlanner.volumeNumbersMatch(
                    volume,
                    Double(detectedVolumeNumber)
                )
            }
        } else {
            volumeEntries = []
        }

        let matchedEntries = exactEntries.isEmpty ? volumeEntries : exactEntries
        guard !matchedEntries.isEmpty else { return [] }

        let rootURL = root.standardizedFileURL
        let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif"]
        var candidates: [SableLibraryEPUBImportCoverCandidate] = []
        var seen = Set<String>()

        for entry in matchedEntries {
            guard let covers = entry["covers"] as? [[String: Any]] else { continue }
            for cover in covers {
                guard localCoverManifestRoleCanReplaceNormalCover(textValue(cover["role"])) else {
                    continue
                }
                let providerTitle = textValue(cover["provider_title"])
                if manifestVersion >= 2, providerTitle == nil {
                    continue
                }
                if let manifestSeriesTitle, let providerTitle {
                    guard SableLibraryCoverDownloadPlanner.providerTitle(
                        providerTitle,
                        belongsTo: manifestSeriesTitle
                    ) else {
                        continue
                    }
                }
                let providerMediaType = textValue(cover["provider_media_type"])
                if manifestVersion >= 2, manifestMediaType != nil, providerMediaType == nil {
                    continue
                }
                if let providerMediaType {
                    guard SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                        providerMediaType,
                        isCompatibleWith: manifestMediaType
                    ) else {
                        continue
                    }
                }
                let coverSource = SableLibraryCoverSource.allCases.first {
                    $0.displayName == textValue(cover["source"])
                        || $0.rawValue == textValue(cover["source"])
                } ?? .unknown
                if manifestVersion >= 2, coverSource.isStoreSource {
                    let status = textValue(cover["status"])?.lowercased() ?? ""
                    guard status.contains("store_verified") else {
                        continue
                    }
                }
                let localVolume = parsedCoverVolume ?? doubleValue(entry["volume"])
                let providerVolume = doubleValue(cover["provider_volume"])
                if manifestVersion >= 2, localVolume != nil, providerVolume == nil {
                    continue
                }
                if let localVolume, let providerVolume {
                    guard SableLibraryCoverDownloadPlanner.providerVolume(
                        providerVolume,
                        providerTitle: providerTitle,
                        localTitle: fileName,
                        source: coverSource,
                        matches: localVolume
                    ) else {
                        continue
                    }
                }
                guard let language = normalizedEPUBImportCoverLanguage(textValue(cover["language"])),
                      let rawPath = textValue(cover["path"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawPath.isEmpty else {
                    continue
                }

                let coverURL = rawPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rawPath)
                    : sidecarFolder.appendingPathComponent(rawPath)
                let standardizedCoverURL = coverURL.standardizedFileURL
                guard resolvesInside(standardizedCoverURL, root: rootURL),
                      FileManager.default.fileExists(atPath: standardizedCoverURL.path(percentEncoded: false)),
                      allowedExtensions.contains(standardizedCoverURL.pathExtension.lowercased()) else {
                    continue
                }

                let width = integerValue(cover["width"])
                let height = integerValue(cover["height"])
                let key = "\(language)|\(standardizedCoverURL.path(percentEncoded: false))"
                guard seen.insert(key).inserted else { continue }
                candidates.append(SableLibraryEPUBImportCoverCandidate(
                    language: language,
                    filePath: standardizedCoverURL.path(percentEncoded: false),
                    width: width,
                    height: height,
                    source: textValue(cover["source"]),
                    volumeNumber: localVolume.flatMap {
                        guard $0.isFinite, $0.rounded() == $0 else { return nil }
                        return Int($0)
                    }
                ))
            }
        }

        return candidates.sorted {
            if $0.language != $1.language {
                return $0.language < $1.language
            }
            return (($0.width ?? 0) * ($0.height ?? 0)) > (($1.width ?? 0) * ($1.height ?? 0))
        }
    }

    private func localCoverManifestRoleCanReplaceNormalCover(_ value: String?) -> Bool {
        let normalized = (value ?? "normal")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "", "normal", "selecteddownloaded", "cover":
            return true
        case "special", "specialedition", "alternative", "alternativeedition", "alternate", "alternateedition",
             "bonus", "booklet", "back", "backcover", "other", "extra":
            return false
        default:
            return false
        }
    }

    private func normalizedEPUBImportCoverLanguage(_ value: String?) -> String? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "en", "eng", "english":
            return "en"
        case "ja", "jp", "jpn", "japanese", "日本語":
            return "jp"
        default:
            return nil
        }
    }

    private func arrayStrings(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let values = value as? [Any] {
            return values.compactMap { textValue($0) }
        }
        if let value = textValue(value) {
            return [value]
        }
        return []
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = textValue(value) {
            return Int(text)
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = textValue(value) {
            return Double(text)
        }
        return nil
    }

    private func uniqueEPUBImportStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = normalizeTerm(trimmed)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private func uniqueEPUBImportSubjects(_ values: [String]) -> [String] {
        uniqueEPUBImportStrings(displayMetadataTerms(values))
    }

    private func uniqueEPUBImportCredits(_ credits: [SableLibraryEPUBImportCredit]) -> [SableLibraryEPUBImportCredit] {
        var seen = Set<String>()
        return credits.compactMap { credit in
            let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let key = "\(credit.role.rawValue)|\(normalizeTerm(name))"
            guard seen.insert(key).inserted else { return nil }
            return SableLibraryEPUBImportCredit(name: name, role: credit.role)
        }
    }
}

private enum SableLibraryAppleBooksCompatibilityRepairOutcome: Sendable {
    case applied(URL)
    case skipped(String)
}

private struct SableLibraryAppleBooksCompatibilityRepairWorkItem: Sendable {
    let path: String
    let sourceURL: URL
    let optimizePageImageEPUBs: Bool
    let importMetadata: SableLibraryEPUBImportMetadata?
    let trustedCoverURLString: String?
    let localCoverCandidates: [SableLibraryEPUBImportCoverCandidate]
    let repairScopes: Set<SableLibraryEPUBRepairScope>
}

private enum SableLibraryAppleBooksCompatibilityRepairTaskResult: Sendable {
    case applied(String)
    case skipped(String, String)
    case failed(String, String)
    case cancelled(String)
}

private enum SableLibraryAppleBooksCompatibilityRepairError: LocalizedError, Sendable {
    case processFailed(String)
    case missingContainer
    case missingOPF
    case missingUnpackedOPF(String)
    case invalidRepairedEPUB(String)
    case unsafeArchiveEntry(String)
    case invalidCoverURL(String)
    case coverDownloadFailed(String)
    case unsupportedCoverImage(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let detail):
            "Apple Books repair helper failed: \(detail)"
        case .missingContainer:
            "The EPUB is missing META-INF/container.xml."
        case .missingOPF:
            "The EPUB container does not point to a readable OPF package file."
        case .missingUnpackedOPF(let path):
            "The unpacked EPUB is missing its OPF file: \(path)."
        case .invalidRepairedEPUB(let detail):
            "The repaired EPUB copy did not validate: \(detail)."
        case .unsafeArchiveEntry(let name):
            "The EPUB contains an unsafe archive entry path: \(name)."
        case .invalidCoverURL(let detail):
            "The trusted cover URL could not be used: \(detail)"
        case .coverDownloadFailed(let detail):
            "The trusted cover image could not be downloaded: \(detail)"
        case .unsupportedCoverImage(let detail):
            "The trusted cover image could not be decoded: \(detail)"
        }
    }
}

nonisolated enum SableLibraryAppleBooksCompatibilityRepairer {
    static let appleMetadataFiles: Set<String> = [
        "iTunesMetadata.plist",
        "iTunesMetadata-original.plist"
    ]

    private static let containerEntry = "META-INF/container.xml"
    private static let htmlResourcePathExtensions: Set<String> = ["xhtml", "html", "htm"]

    struct CoverAnalysis {
        let hasEPUB2CoverMeta: Bool
        let hasEPUB3CoverImage: Bool
        let hasImageManifestItems: Bool
        let likelyCoverID: String?
    }

    private struct EPUB3SeriesCollection {
        let id: String
        let title: String
        let collectionType: String?
        let groupPosition: String?
        let fileAs: String?
    }

    private struct DublinCoreElementSnapshot {
        let id: String?
        let value: String
    }

    private struct EPUBImportCreditSnapshot: Hashable {
        let nameKey: String
        let roleCode: String
    }

    private struct EPUBManifestItem {
        let tag: String
        let id: String
        let href: String
        let mediaType: String
        let properties: [String]
        let entryPath: String

        var isNavigationDocument: Bool {
            properties.contains { $0.caseInsensitiveCompare("nav") == .orderedSame }
        }
    }

    private struct EPUBCoverImageCandidate {
        let data: Data
        let isLocalFile: Bool
    }

    private struct EPUBNavigationEntry {
        let href: String
        let label: String
        let source: EPUBNavigationLabelSource
        let level: Int
    }

    private struct EPUBStructureHeadingCandidate {
        let entryPath: String
        let href: String
        let fragment: String?
        let label: String
        let level: Int
    }

    private struct NCXNavigationPoint {
        let label: String
        let source: String
        let depth: Int
        let sequence: Int
    }

    private struct NCXContentSourceRepair {
        let tag: String
        let replacementSource: String
    }

    private struct LocalLinkFragmentRepair {
        let tag: String
        let replacementTag: String
    }

    private struct LinkedResourceReferenceRepair {
        let entryPath: String
        let originalReference: String
        let replacementReference: String
    }

    private struct StaleLinkedResourceReferenceRepair {
        let entryPath: String
        let tag: String
        let originalReference: String
    }

    private struct StaleNavigationLinkRepair {
        let listItem: String
    }

    private struct EPUBManifestResourceDeclaration: Hashable {
        let entryPath: String
        let href: String
        let mediaType: String
    }

    private enum EPUBNavigationLabelSource {
        case heading
        case title
        case ncx
        case fallback
    }

    fileprivate final class EPUBArchiveTextCache: @unchecked Sendable {
        private let storage = NSCache<NSString, NSString>()

        init() {
            storage.countLimit = 512
            storage.totalCostLimit = 32 * 1_024 * 1_024
        }

        func text(for entry: String) -> String? {
            storage.object(forKey: entry as NSString) as String?
        }

        func insert(_ text: String, for entry: String) {
            storage.setObject(
                text as NSString,
                forKey: entry as NSString,
                cost: text.utf8.count
            )
        }
    }

    fileprivate final class EPUBArchiveReader: @unchecked Sendable {
        private let handle: FileHandle
        private let lock = NSLock()

        init(epubURL: URL) throws {
            self.handle = try FileHandle(forReadingFrom: epubURL)
        }

        deinit {
            try? handle.close()
        }

        func data(at offset: UInt64, length: Int) throws -> Data {
            lock.lock()
            defer { lock.unlock() }
            try handle.seek(toOffset: offset)
            return handle.readData(ofLength: length)
        }
    }

    struct EPUBArchiveSnapshot: Sendable {
        let entries: [String]
        fileprivate let epubURL: URL
        fileprivate let recordsByName: [String: ZipCentralDirectoryRecord]
        fileprivate let entryNameByNormalizedPath: [String: String]
        fileprivate let textCache = EPUBArchiveTextCache()
        fileprivate let reader: EPUBArchiveReader

        fileprivate init(epubURL: URL, records: [ZipCentralDirectoryRecord]) throws {
            self.epubURL = epubURL
            self.entries = records.map(\.name)
            self.recordsByName = records.reduce(into: [:]) { partialResult, record in
                partialResult[record.name] = partialResult[record.name] ?? record
            }
            self.entryNameByNormalizedPath = records.reduce(into: [:]) { partialResult, record in
                let key = SableLibraryAppleBooksCompatibilityRepairer.normalizedEPUBResourcePath(record.name)
                partialResult[key] = partialResult[key] ?? record.name
            }
            self.reader = try EPUBArchiveReader(epubURL: epubURL)
        }
    }

    struct ZipCentralDirectoryRecord: Sendable {
        let name: String
        let method: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let externalAttributes: UInt32
        let localOffset: UInt32
    }

    static func archiveSnapshot(for epubURL: URL) throws -> EPUBArchiveSnapshot {
        let records = try zipCentralDirectoryRecords(for: epubURL)
        try validateArchiveRecords(records)
        return try EPUBArchiveSnapshot(epubURL: epubURL, records: records)
    }

    static func zipEntryNames(for epubURL: URL) throws -> [String] {
        try archiveSnapshot(for: epubURL).entries
    }

    static func protectionAnalysis(in archive: EPUBArchiveSnapshot) throws -> LibraryEPUBProtectionAnalysis {
        let normalizedEntries = Set(archive.entries.map(normalizedEPUBResourcePath))
        if normalizedEntries.contains("meta-inf/sinf.xml") {
            return LibraryEPUBProtectionAnalysis(
                isProtected: true,
                reason: "Apple FairPlay DRM marker found (META-INF/sinf.xml).",
                encryptedResourcePaths: ["META-INF/sinf.xml"],
                obfuscatedFontPaths: []
            )
        }

        if normalizedEntries.contains("meta-inf/rights.xml") {
            return LibraryEPUBProtectionAnalysis(
                isProtected: true,
                reason: "Adobe ADEPT DRM marker found (META-INF/rights.xml).",
                encryptedResourcePaths: ["META-INF/rights.xml"],
                obfuscatedFontPaths: []
            )
        }

        guard normalizedEntries.contains("meta-inf/encryption.xml") else {
            return .none
        }

        guard let encryptionEntry = archive.entries.first(where: {
            normalizedEPUBResourcePath($0) == "meta-inf/encryption.xml"
        }), let encryptionXML = try entryText(encryptionEntry, in: archive) else {
            return LibraryEPUBProtectionAnalysis(
                isProtected: true,
                reason: "EPUB encryption metadata is present but could not be read safely.",
                encryptedResourcePaths: ["META-INF/encryption.xml"],
                obfuscatedFontPaths: []
            )
        }

        let encryptedPaths = encryptedResourcePaths(inEncryptionXML: encryptionXML)
        guard !encryptedPaths.isEmpty else {
            return LibraryEPUBProtectionAnalysis(
                isProtected: true,
                reason: "EPUB encryption metadata is present but Sable could not tell which resources are encrypted.",
                encryptedResourcePaths: ["META-INF/encryption.xml"],
                obfuscatedFontPaths: []
            )
        }

        let fontPaths = encryptedPaths.filter(isFontResourcePath)
        let contentPaths = encryptedPaths.filter { !isFontResourcePath($0) }
        if contentPaths.isEmpty {
            return LibraryEPUBProtectionAnalysis(
                isProtected: false,
                reason: nil,
                encryptedResourcePaths: [],
                obfuscatedFontPaths: fontPaths
            )
        }

        let examples = contentPaths.prefix(3).joined(separator: ", ")
        let extra = contentPaths.count > 3 ? " and \(contentPaths.count - 3) more" : ""
        return LibraryEPUBProtectionAnalysis(
            isProtected: true,
            reason: "Encrypted EPUB content resources found: \(examples)\(extra).",
            encryptedResourcePaths: contentPaths,
            obfuscatedFontPaths: fontPaths
        )
    }

    static func protectionAnalysis(for epubURL: URL) throws -> LibraryEPUBProtectionAnalysis {
        try protectionAnalysis(in: archiveSnapshot(for: epubURL))
    }

    static func archiveEntryNameIsSafe(_ name: String) -> Bool {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/") else { return false }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else { return false }

        return components.allSatisfy { component in
            component != "." && component != ".."
        }
    }

    private static func validateArchiveRecords(_ records: [ZipCentralDirectoryRecord]) throws {
        for record in records {
            guard archiveEntryNameIsSafe(record.name), !archiveEntryIsSymbolicLink(record) else {
                throw SableLibraryAppleBooksCompatibilityRepairError.unsafeArchiveEntry(record.name)
            }
        }
    }

    private static func archiveEntryIsSymbolicLink(_ record: ZipCentralDirectoryRecord) -> Bool {
        let unixMode = (record.externalAttributes >> 16) & 0xF000
        return unixMode == 0xA000
    }

    private static func zipCentralDirectoryRecords(for epubURL: URL) throws -> [ZipCentralDirectoryRecord] {
        // Fast path for normal library inspect:
        // read only the ZIP central directory instead of spawning /usr/bin/unzip for every EPUB.
        let handle = try FileHandle(forReadingFrom: epubURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("EPUB ZIP is too small.")
        }

        let tailSize = min(Int(fileSize), 65_557)
        try handle.seek(toOffset: fileSize - UInt64(tailSize))
        let tail = handle.readData(ofLength: tailSize)

        guard let eocdRange = tail.lastRange(of: Data([0x50, 0x4b, 0x05, 0x06])) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("ZIP end of central directory was not found.")
        }

        let eocdOffset = eocdRange.lowerBound
        let centralSize = Int(try littleEndianUInt32(tail, at: eocdOffset + 12))
        let centralOffset = UInt64(try littleEndianUInt32(tail, at: eocdOffset + 16))

        guard centralOffset + UInt64(centralSize) <= fileSize else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("ZIP central directory points outside the EPUB.")
        }

        try handle.seek(toOffset: centralOffset)
        let central = handle.readData(ofLength: centralSize)
        guard central.count == centralSize else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("ZIP central directory could not be read.")
        }

        var records: [ZipCentralDirectoryRecord] = []
        var offset = 0
        while offset < central.count {
            guard offset + 46 <= central.count,
                  try littleEndianUInt32(central, at: offset) == 0x02014b50 else {
                throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("ZIP central directory entry is malformed.")
            }

            let method = try littleEndianUInt16(central, at: offset + 10)
            let compressedSize = try littleEndianUInt32(central, at: offset + 20)
            let uncompressedSize = try littleEndianUInt32(central, at: offset + 24)
            let nameLength = Int(try littleEndianUInt16(central, at: offset + 28))
            let extraLength = Int(try littleEndianUInt16(central, at: offset + 30))
            let commentLength = Int(try littleEndianUInt16(central, at: offset + 32))
            let externalAttributes = try littleEndianUInt32(central, at: offset + 38)
            let localOffset = try littleEndianUInt32(central, at: offset + 42)
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength

            guard nameEnd <= central.count else {
                throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("ZIP entry name points outside the central directory.")
            }

            let nameData = central.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            if !name.isEmpty {
                records.append(
                    ZipCentralDirectoryRecord(
                        name: name,
                        method: method,
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize,
                        externalAttributes: externalAttributes,
                        localOffset: localOffset
                    )
                )
            }

            offset = nameEnd + extraLength + commentLength
        }

        return records
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset + 2 <= data.count else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("Unexpected end of ZIP data.")
        }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("Unexpected end of ZIP data.")
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func entryText(_ entry: String, in epubURL: URL) throws -> String? {
        let archive = try archiveSnapshot(for: epubURL)
        return try entryText(entry, in: archive)
    }

    static func entryText(_ entry: String, in archive: EPUBArchiveSnapshot) throws -> String? {
        if let cached = archive.textCache.text(for: entry) {
            return cached
        }
        guard let data = try entryData(entry, in: archive) else { return nil }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            return nil
        }
        archive.textCache.insert(text, for: entry)
        return text
    }

    static func entryData(_ wantedName: String, in epubURL: URL) throws -> Data? {
        let archive = try archiveSnapshot(for: epubURL)
        return try entryData(wantedName, in: archive)
    }

    private static func entryData(_ wantedName: String, in archive: EPUBArchiveSnapshot) throws -> Data? {
        guard let record = archive.recordsByName[wantedName] else { return nil }

        let header = try archive.reader.data(at: UInt64(record.localOffset), length: 30)
        guard header.count == 30,
              try littleEndianUInt32(header, at: 0) == 0x04034b50 else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("ZIP local header is missing for \(wantedName).")
        }

        let nameLength = UInt64(try littleEndianUInt16(header, at: 26))
        let extraLength = UInt64(try littleEndianUInt16(header, at: 28))
        let dataOffset = UInt64(record.localOffset) + 30 + nameLength + extraLength

        let compressed = try archive.reader.data(at: dataOffset, length: Int(record.compressedSize))
        guard compressed.count == Int(record.compressedSize) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed("Could not read ZIP entry data for \(wantedName).")
        }

        switch record.method {
        case 0:
            return compressed
        case 8:
            if let inflated = inflateDeflatedZIPData(compressed, expectedSize: Int(record.uncompressedSize)) {
                return inflated
            }

            // Fallback only when direct in-process deflate fails.
            // This keeps normal cases fast but avoids giving up on odd EPUBs.
            let output = try runProcess(
                executable: "/usr/bin/unzip",
                arguments: ["-p", archive.epubURL.path(percentEncoded: false), wantedName],
                currentDirectory: nil
            )
            return Data(output.utf8)
        default:
            return nil
        }
    }

    private static func inflateDeflatedZIPData(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize >= 0 else { return nil }
        if data.isEmpty { return Data() }

        let outputCapacity = max(expectedSize, 1)
        var output = Data(count: outputCapacity)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    outputCapacity,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decodedCount == expectedSize else { return nil }
        output.removeSubrange(decodedCount..<output.count)
        return output
    }

    static func opfPath(in epubURL: URL) throws -> String? {
        let archive = try archiveSnapshot(for: epubURL)
        return try opfPath(in: archive)
    }

    static func opfPath(in archive: EPUBArchiveSnapshot) throws -> String? {
        guard let container = try entryText(containerEntry, in: archive) else { return nil }
        return firstMatch(
            in: container,
            pattern: #"full-path\s*=\s*["']([^"']+)["']"#
        )
    }

    static func coverAnalysis(in opfText: String) -> CoverAnalysis {
        let itemTags = matches(
            in: opfText,
            pattern: #"<(?:[A-Za-z0-9_]+:)?item\b[^>]*>"#
        )

        var hasEPUB3 = false
        var imageIDs = Set<String>()
        var candidates: [(score: Int, id: String)] = []

        for tag in itemTags {
            let attrs = attributes(in: tag)
            guard let id = attrs["id"] else { continue }

            let properties = attrs["properties"] ?? ""
            let propertyParts = properties
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).lowercased() }
            let href = (attrs["href"] ?? "").lowercased()
            let itemID = id.lowercased()
            let mediaType = (attrs["media-type"] ?? "").lowercased()

            let looksLikeImage =
                mediaType.hasPrefix("image/")
                || href.hasSuffix(".jpg")
                || href.hasSuffix(".jpeg")
                || href.hasSuffix(".png")
                || href.hasSuffix(".webp")
                || href.hasSuffix(".gif")
                || href.hasSuffix(".svg")

            guard looksLikeImage else { continue }
            imageIDs.insert(id)

            var score = 0
            if propertyParts.contains("cover-image") {
                hasEPUB3 = true
                score += 100
            }
            if href.contains("cover") || itemID.contains("cover") {
                score += 50
            }
            if href.hasSuffix(".jpg") || href.hasSuffix(".jpeg") || href.hasSuffix(".png") || href.hasSuffix(".webp") {
                score += 5
            }
            if mediaType.hasPrefix("image/") {
                score += 2
            }

            candidates.append((score, id))
        }

        let metaTags = metaTags(in: opfText).filter {
            metadataComparisonKey(attributes(in: $0)["name"] ?? "").caseInsensitiveCompare("cover") == .orderedSame
        }
        let coverMetaIDs = metaTags.compactMap { attributes(in: $0)["content"] }
        let hasValidEPUB2 = coverMetaIDs.contains { imageIDs.contains($0) }

        let likelyID = candidates
            .sorted { $0.score > $1.score }
            .first?
            .id
            ?? coverMetaIDs.first(where: { imageIDs.contains($0) })
            ?? firstManifestImageID(in: itemTags)

        return CoverAnalysis(
            hasEPUB2CoverMeta: hasValidEPUB2,
            hasEPUB3CoverImage: hasEPUB3,
            hasImageManifestItems: !imageIDs.isEmpty,
            likelyCoverID: likelyID
        )
    }

    static func navigationRepairReasons(
        entries: [String],
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        guard !manifestItems.isEmpty else { return [] }

        let navItems = manifestItems.filter(\.isNavigationDocument)
        let likelyNavItem = try likelyNavigationManifestItem(
            in: manifestItems,
            archive: archive
        )
        let chosenNavItem = navItems.first ?? likelyNavItem
        let navigationText = try chosenNavItem.flatMap { item in
            try entryTextForNormalizedPath(item.entryPath, in: archive)
        }
        let generatedEntries = try navigationEntriesForSpine(
            in: opfText,
            manifestItems: manifestItems
        ) { entryPath in
            try entryTextForNormalizedPath(entryPath, in: archive)
        }
        let ncxEntries = try navigationEntriesFromNCX(
            in: manifestItems,
            opfPath: opfPath,
            textForEntry: { entryPath in
                try entryTextForNormalizedPath(entryPath, in: archive)
            },
            entryExists: { entryPath in
                archive.entries.contains {
                    normalizedEPUBResourcePath($0) == normalizedEPUBResourcePath(entryPath)
                }
            }
        )
        let canGenerateUsefulTOC = navigationEntriesAreUseful(generatedEntries)
        let canGenerateUsefulNCXTOC = navigationEntriesAreUseful(ncxEntries)

        var reasons: [String] = []
        if navItems.count > 1 {
            reasons.append("Reduce duplicate EPUB navigation document markers")
        }
        if navItems.isEmpty, likelyNavItem != nil {
            reasons.append("Declare existing EPUB navigation document")
        }
        if chosenNavItem == nil, canGenerateUsefulTOC {
            reasons.append("Create EPUB3 navigation document from spine")
        } else if chosenNavItem == nil, canGenerateUsefulNCXTOC {
            reasons.append("Create EPUB3 navigation document from existing NCX table of contents")
        } else if chosenNavItem != nil,
                  navigationText.map(navigationDocumentHasTOC) != true,
                  canGenerateUsefulTOC {
            reasons.append("Create EPUB navigation TOC from spine")
        } else if chosenNavItem != nil,
                  navigationText.map(navigationDocumentHasTOC) != true,
                  canGenerateUsefulNCXTOC {
            reasons.append("Create EPUB navigation TOC from existing NCX table of contents")
        }

        let missingFragmentCount = try missingLocalLinkFragmentCount(
            in: archive,
            manifestItems: manifestItems
        )
        if missingFragmentCount > 0 {
            let fragmentText = missingFragmentCount == 1 ? "target" : "targets"
            reasons.append("Repair \(missingFragmentCount) EPUB navigation/local link fragment \(fragmentText)")
        }

        if let navigationText,
           let chosenNavItem {
            let staleNavigationLinks = staleNavigationLinkRepairs(
                in: navigationText,
                navEntryPath: chosenNavItem.entryPath,
                existingEntries: Set(archive.entries.map(normalizedEPUBResourcePath))
            )
            if !staleNavigationLinks.isEmpty {
                let linkText = staleNavigationLinks.count == 1 ? "link" : "links"
                reasons.append("Remove \(staleNavigationLinks.count) stale EPUB navigation \(linkText)")
            }
        }

        if let navigationText,
           navigationOrderNeedsManualReview(
            navigationText: navigationText,
            navEntryPath: chosenNavItem?.entryPath ?? opfPath,
            opfPath: opfPath,
            opfText: opfText,
           manifestItems: manifestItems
           ) {
            reasons.append("Rebuild EPUB navigation order from spine")
        }

        return reasons
    }

    static func structureRepairReasons(
        entries: [String],
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        guard !manifestItems.isEmpty else { return [] }

        let candidates = try semanticHeadingCandidates(
            in: opfText,
            manifestItems: manifestItems,
            opfPath: opfPath,
            textForEntry: { entryPath in
                try entryTextForNormalizedPath(entryPath, in: archive)
            },
            entryExists: { entryPath in
                archive.entries.contains {
                    normalizedEPUBResourcePath($0) == normalizedEPUBResourcePath(entryPath)
                }
            }
        )
        guard candidates.count >= 2 else { return [] }

        let fileCount = Set(candidates.map(\.entryPath)).count
        let headingText = candidates.count == 1 ? "heading" : "headings"
        let fileText = fileCount == 1 ? "file" : "files"
        let levels = Array(Set(candidates.map { "H\(clampedSemanticHeadingLevel($0.level))" })).sorted()
        let levelText = levels.isEmpty ? "" : ", \(levels.joined(separator: "/"))"
        return [
            "Promote exact NCX-backed semantic headings (\(candidates.count) \(headingText) in \(fileCount) \(fileText)\(levelText))"
        ]
    }

    static func subjectTagCasingRepairReasons(in opfText: String) -> [String] {
        let currentSubjects = currentDublinCoreValues(in: opfText, localName: "subject")
        guard subjectTagsNeedDisplayCasing(currentSubjects) else { return [] }
        return ["Clean EPUB subject tag display casing"]
    }

    static func manifestCompatibilityRepairReasons(
        entries: [String],
        opfPath: String,
        opfText: String
    ) -> [String] {
        var reasons: [String] = []
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let existingEntries = Set(entries.map(normalizedEPUBResourcePath))
        let missingItems = removableMissingManifestHelperItems(
            manifestItems: manifestItems,
            existingEntries: existingEntries,
            opfText: opfText
        )
        if !missingItems.isEmpty {
            let count = missingItems.count
            let fileText = count == 1 ? "helper reference" : "helper references"
            reasons.append("Remove \(count) missing EPUB manifest \(fileText)")
        }

        let deadSpineItemRefs = deadSpineItemrefTags(in: opfText, manifestItems: manifestItems)
        if !deadSpineItemRefs.isEmpty {
            let count = deadSpineItemRefs.count
            let referenceText = count == 1 ? "reference" : "references"
            reasons.append("Remove \(count) dead EPUB spine item \(referenceText)")
        }

        let legacyPageMapCount = legacySpinePageMapTags(in: opfText).count
        if legacyPageMapCount > 0 {
            let attributeText = legacyPageMapCount == 1 ? "attribute" : "attributes"
            reasons.append("Remove \(legacyPageMapCount) legacy EPUB spine page-map \(attributeText)")
        }

        let duplicateManifestIDCount = duplicateManifestIDRepairCount(in: manifestItems)
        if duplicateManifestIDCount > 0 {
            let idText = duplicateManifestIDCount == 1 ? "ID" : "IDs"
            reasons.append("Repair \(duplicateManifestIDCount) duplicate EPUB manifest \(idText)")
        }

        let fontMediaTypeRepairs = fontManifestMediaTypeRepairs(in: manifestItems)
        if !fontMediaTypeRepairs.isEmpty {
            let count = fontMediaTypeRepairs.count
            let typeText = count == 1 ? "type" : "types"
            reasons.append("Normalize \(count) EPUB font manifest media \(typeText)")
        }

        let invalidCoverItems = invalidCoverImagePropertyManifestItems(in: manifestItems)
        if !invalidCoverItems.isEmpty {
            let count = invalidCoverItems.count
            let itemText = count == 1 ? "item" : "items"
            reasons.append("Remove invalid cover-image marker from \(count) non-image EPUB manifest \(itemText)")
        }

        let duplicateCoverItems = duplicateCoverImagePropertyManifestItems(in: manifestItems, opfText: opfText)
        if !duplicateCoverItems.isEmpty {
            let count = duplicateCoverItems.count
            let itemText = count == 1 ? "item" : "items"
            reasons.append("Remove duplicate cover-image marker from \(count) EPUB manifest \(itemText)")
        }

        let brokenGuideReferences = brokenGuideReferenceTags(
            in: opfText,
            opfPath: opfPath,
            existingEntries: existingEntries,
            manifestItems: manifestItems
        )
        if !brokenGuideReferences.isEmpty {
            let count = brokenGuideReferences.count
            let referenceText = count == 1 ? "reference" : "references"
            reasons.append("Remove \(count) broken EPUB guide \(referenceText)")
        }

        let emptyGuideCount = emptyGuideTags(in: opfText).count
        if emptyGuideCount > 0 {
            let guideText = emptyGuideCount == 1 ? "guide" : "guides"
            reasons.append("Remove \(emptyGuideCount) empty EPUB \(guideText)")
        }

        let obsoleteToursCount = obsoleteToursTags(in: opfText).count
        if obsoleteToursCount > 0 {
            let elementText = obsoleteToursCount == 1 ? "element" : "elements"
            reasons.append("Remove \(obsoleteToursCount) obsolete EPUB tours \(elementText)")
        }

        return reasons
    }

    static func linkedResourceRepairReasons(
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let existingEntries = Set(archive.entries.map(normalizedEPUBResourcePath))
        let manifestDeclarations = try missingManifestResourceDeclarations(
            existingEntries: existingEntries,
            opfPath: opfPath,
            opfText: opfText
        ) { entryPath in
            try entryTextForNormalizedPath(entryPath, in: archive)
        }
        let missingLinkedResources = try missingLinkedResourceReferenceCount(
            existingEntries: existingEntries,
            entries: archive.entries,
            opfPath: opfPath,
            opfText: opfText
        ) { entryPath in
            try entryTextForNormalizedPath(entryPath, in: archive)
        }
        let staleLinkedResources = try staleLinkedResourceReferenceCount(
            existingEntries: existingEntries,
            entries: archive.entries,
            opfPath: opfPath,
            opfText: opfText
        ) { entryPath in
            try entryTextForNormalizedPath(entryPath, in: archive)
        }

        var reasons: [String] = []
        if !manifestDeclarations.isEmpty {
            let count = manifestDeclarations.count
            let declarationText = count == 1 ? "declaration" : "declarations"
            reasons.append("Add \(count) missing EPUB manifest resource \(declarationText)")
        }
        if missingLinkedResources > 0 {
            let resourceText = missingLinkedResources == 1 ? "resource" : "resources"
            reasons.append("Retarget \(missingLinkedResources) missing EPUB linked \(resourceText) to existing files")
        }
        if staleLinkedResources > 0 {
            let referenceText = staleLinkedResources == 1 ? "reference" : "references"
            reasons.append("Remove \(staleLinkedResources) missing EPUB linked resource \(referenceText) with no existing target")
        }
        return reasons
    }

    static func contentManifestPropertiesRepairReasons(
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let missingProperties = try missingRequiredManifestProperties(
            in: opfText,
            opfPath: opfPath
        ) { entryPath in
            try entryTextForNormalizedPath(entryPath, in: archive)
        }

        var countsByProperty: [String: Int] = [:]
        for item in missingProperties {
            for property in item.properties {
                countsByProperty[property, default: 0] += 1
            }
        }

        var reasons = countsByProperty.keys.sorted().map { property in
            let count = countsByProperty[property] ?? 0
            let fileText = count == 1 ? "content document" : "content documents"
            return "Declare \(property) in EPUB manifest for \(count) \(fileText)"
        }

        let falseScriptedItems = try falseScriptedManifestItems(
            in: opfText,
            opfPath: opfPath
        ) { entryPath in
            try entryTextForNormalizedPath(entryPath, in: archive)
        }
        if !falseScriptedItems.isEmpty {
            let count = falseScriptedItems.count
            let fileText = count == 1 ? "content document" : "content documents"
            reasons.append("Remove false scripted EPUB manifest marker from \(count) \(fileText)")
        }

        return reasons
    }

    static func contentDocumentHeaderRepairReasons(
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let existingEntries = Set(archive.entries.map(normalizedEPUBResourcePath))
        var legacyDoctypeCount = 0
        var contentTypeMetaCount = 0
        var obsoleteHTTPMetaCount = 0
        var emptyTitleCount = 0
        var invalidImageDimensionCount = 0
        var namedNBSPCount = 0
        var unsupportedNamedEntityCount = 0
        var bareAmpersandCount = 0
        var htmlVoidElementCount = 0
        var invalidXMLControlCharacters = 0
        var uppercaseDataAttributeCount = 0
        var duplicateIDCount = 0
        var orphanInlineClosingTagCount = 0
        var headingParagraphCount = 0
        var missingLocalScriptCount = 0
        var malformedXHTMLCount = 0

        for item in manifestItems where manifestItemCanCarryContentDocumentProperties(item) {
            guard let text = try entryTextForNormalizedPath(item.entryPath, in: archive) else { continue }
            if hasLegacyXHTMLDoctype(in: text) {
                legacyDoctypeCount += 1
            }
            contentTypeMetaCount += contentTypeMetaTagsNeedingRepair(in: text).count
            obsoleteHTTPMetaCount += obsoleteHTTPMetadataTags(in: text).count
            if !emptyHTMLTitleTags(in: text).isEmpty {
                emptyTitleCount += 1
            }
            invalidImageDimensionCount += invalidImageDimensionAttributeCount(in: text)
            namedNBSPCount += namedNBSPReferenceCount(in: text)
            unsupportedNamedEntityCount += unsupportedXHTMLNamedEntityReferenceCount(in: text)
            bareAmpersandCount += bareAmpersandReferenceCount(in: text)
            htmlVoidElementCount += htmlVoidElementClosureCount(in: text)
            invalidXMLControlCharacters += invalidXMLControlCharacterCount(in: text)
            uppercaseDataAttributeCount += uppercaseCustomDataAttributeCount(in: text)
            duplicateIDCount += duplicateContentIDCount(in: text)
            orphanInlineClosingTagCount += orphanClosingInlineTagCount(in: text)
            if paragraphChildrenInsideHeadingCount(in: text) > 0 {
                headingParagraphCount += 1
            }
            missingLocalScriptCount += missingLocalScriptReferenceCount(
                in: text,
                baseEntryPath: item.entryPath,
                existingEntries: existingEntries
            )
            if xhtmlDocumentNeedsManualStructureReview(text) {
                malformedXHTMLCount += 1
            }
        }

        var reasons: [String] = []
        if legacyDoctypeCount > 0 {
            let fileText = legacyDoctypeCount == 1 ? "document" : "documents"
            reasons.append("Modernize \(legacyDoctypeCount) legacy XHTML doctype \(fileText)")
        }
        if contentTypeMetaCount > 0 {
            let tagText = contentTypeMetaCount == 1 ? "declaration" : "declarations"
            reasons.append("Normalize \(contentTypeMetaCount) EPUB content-type meta \(tagText)")
        }
        if obsoleteHTTPMetaCount > 0 {
            let tagText = obsoleteHTTPMetaCount == 1 ? "declaration" : "declarations"
            reasons.append("Remove \(obsoleteHTTPMetaCount) obsolete EPUB http-equiv meta \(tagText)")
        }
        if emptyTitleCount > 0 {
            let fileText = emptyTitleCount == 1 ? "document" : "documents"
            reasons.append("Fill \(emptyTitleCount) empty EPUB content document title \(fileText)")
        }
        if invalidImageDimensionCount > 0 {
            let attributeText = invalidImageDimensionCount == 1 ? "attribute" : "attributes"
            reasons.append("Move \(invalidImageDimensionCount) invalid EPUB image dimension \(attributeText) into CSS")
        }
        if namedNBSPCount > 0 {
            let entityText = namedNBSPCount == 1 ? "entity" : "entities"
            reasons.append("Normalize \(namedNBSPCount) XHTML non-breaking space \(entityText)")
        }
        if unsupportedNamedEntityCount > 0 {
            let entityText = unsupportedNamedEntityCount == 1 ? "entity" : "entities"
            reasons.append("Normalize \(unsupportedNamedEntityCount) XHTML named \(entityText)")
        }
        if bareAmpersandCount > 0 {
            let characterText = bareAmpersandCount == 1 ? "character" : "characters"
            reasons.append("Escape \(bareAmpersandCount) bare XHTML ampersand \(characterText)")
        }
        if htmlVoidElementCount > 0 {
            let tagText = htmlVoidElementCount == 1 ? "tag" : "tags"
            reasons.append("Self-close \(htmlVoidElementCount) XHTML void element \(tagText)")
        }
        if invalidXMLControlCharacters > 0 {
            let characterText = invalidXMLControlCharacters == 1 ? "character" : "characters"
            reasons.append("Remove \(invalidXMLControlCharacters) invalid XHTML control \(characterText)")
        }
        if uppercaseDataAttributeCount > 0 {
            let attributeText = uppercaseDataAttributeCount == 1 ? "attribute" : "attributes"
            reasons.append("Normalize \(uppercaseDataAttributeCount) EPUB custom data \(attributeText)")
        }
        if duplicateIDCount > 0 {
            let idText = duplicateIDCount == 1 ? "ID" : "IDs"
            reasons.append("Repair \(duplicateIDCount) duplicate EPUB content \(idText)")
        }
        if orphanInlineClosingTagCount > 0 {
            let tagText = orphanInlineClosingTagCount == 1 ? "tag" : "tags"
            reasons.append("Remove \(orphanInlineClosingTagCount) orphan XHTML inline closing \(tagText)")
        }
        if headingParagraphCount > 0 {
            let documentText = headingParagraphCount == 1 ? "document" : "documents"
            reasons.append("Repair paragraph markup inside \(headingParagraphCount) EPUB content document heading \(documentText)")
        }
        if missingLocalScriptCount > 0 {
            let referenceText = missingLocalScriptCount == 1 ? "reference" : "references"
            reasons.append("Remove \(missingLocalScriptCount) missing local EPUB script \(referenceText)")
        }
        if malformedXHTMLCount > 0 {
            let documentText = malformedXHTMLCount == 1 ? "document" : "documents"
            reasons.append("Run guarded XHTML parser repair for \(malformedXHTMLCount) malformed \(documentText)")
        }
        return reasons
    }

    static func stylesheetRepairReasons(
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        var simpleSyntaxCount = 0
        var riskySyntaxCount = 0

        for item in manifestItems where manifestItemIsCSS(item) {
            guard let text = try entryTextForNormalizedPath(item.entryPath, in: archive) else { continue }
            if normalizingSimpleCSSSyntax(in: text) != text {
                simpleSyntaxCount += 1
            }
            if cssNeedsManualSyntaxReview(text) {
                riskySyntaxCount += 1
            }
        }

        var reasons: [String] = []
        if simpleSyntaxCount > 0 {
            let fileText = simpleSyntaxCount == 1 ? "file" : "files"
            reasons.append("Normalize simple EPUB CSS syntax in \(simpleSyntaxCount) \(fileText)")
        }
        if riskySyntaxCount > 0 {
            let fileText = riskySyntaxCount == 1 ? "file" : "files"
            reasons.append("Run guarded EPUB CSS repair in \(riskySyntaxCount) \(fileText)")
        }
        return reasons
    }

    static func standardsProfileRepairReasons(in opfText: String) -> [String] {
        guard packageNeedsEPUB3VersionForStandardsProfile(opfText) else { return [] }
        return ["Modernize EPUB 3.3/3.4 package wiring while keeping package version 3.0"]
    }

    static func metadataCompatibilityRepairReasons(in opfText: String) -> [String] {
        var reasons: [String] = []
        let orphanedCount = orphanedRefinementMetaTags(in: opfText).count
        if orphanedCount > 0 {
            let refinementText = orphanedCount == 1 ? "refinement" : "refinements"
            reasons.append("Remove \(orphanedCount) orphaned EPUB metadata \(refinementText)")
        }

        let invalidCount = invalidTypedRefinementMetaTags(in: opfText).count
        if invalidCount > 0 {
            let refinementText = invalidCount == 1 ? "refinement" : "refinements"
            reasons.append("Remove \(invalidCount) invalid EPUB metadata \(refinementText)")
        }

        let legacyCount = legacyDublinCoreAttributeElementTags(in: opfText).count
        if legacyCount > 0 {
            let elementText = legacyCount == 1 ? "element" : "elements"
            reasons.append("Normalize \(legacyCount) legacy EPUB metadata \(elementText) into EPUB 3 refinements")
        }
        let nonNamespacedMetaCount = nonNamespacedMetadataMetaTags(in: opfText).count
        if nonNamespacedMetaCount > 0 {
            let elementText = nonNamespacedMetaCount == 1 ? "element" : "elements"
            reasons.append("Repair \(nonNamespacedMetaCount) non-namespaced EPUB metadata \(elementText)")
        }
        return reasons
    }

    static func ncxIdentifierRepairReasons(
        entries: [String],
        in archive: EPUBArchiveSnapshot,
        opfText: String
    ) throws -> [String] {
        let ncxEntries = entries.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "ncx" }
        guard !ncxEntries.isEmpty,
              let packageID = packageUniqueIdentifierValue(in: opfText),
              !packageID.isEmpty else {
            return []
        }

        var mismatches = 0
        for entry in ncxEntries {
            guard let ncxText = try entryText(entry, in: archive),
                  let ncxID = ncxIdentifierValue(in: ncxText),
                  !ncxID.isEmpty,
                  metadataComparisonKey(ncxID) != metadataComparisonKey(packageID) else {
                continue
            }
            mismatches += 1
        }

        guard mismatches > 0 else { return [] }
        let fileText = mismatches == 1 ? "file" : "files"
        return ["Align \(mismatches) NCX table of contents identifier \(fileText) with the OPF package identifier"]
    }

    static func ncxResourcePathRepairReasons(
        entries: [String],
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String] {
        let repairs = try ncxContentSourceRepairs(
            entries: entries,
            in: archive,
            opfPath: opfPath,
            opfText: opfText
        )
        let count = repairs.values.reduce(0) { $0 + $1.count }
        guard count > 0 else { return [] }
        let targetText = count == 1 ? "target" : "targets"
        return ["Relink \(count) NCX table of contents \(targetText) to manifest paths"]
    }

    static func ncxFragmentRepairReasons(
        entries: [String],
        in archive: EPUBArchiveSnapshot
    ) throws -> [String] {
        let existingEntries = Set(entries.map(normalizedEPUBResourcePath))
        var count = 0

        for ncxEntry in entries where URL(fileURLWithPath: ncxEntry).pathExtension.lowercased() == "ncx" {
            guard let ncxText = try entryText(ncxEntry, in: archive) else { continue }
            count += try repairableNCXContentFragmentTags(
                in: ncxText,
                ncxEntry: ncxEntry,
                entryExists: { existingEntries.contains(normalizedEPUBResourcePath($0)) },
                textForEntry: { try entryTextForNormalizedPath($0, in: archive) }
            ).count
        }

        guard count > 0 else { return [] }
        let targetText = count == 1 ? "fragment target" : "fragment targets"
        return ["Repair \(count) NCX table of contents \(targetText) with missing anchors"]
    }

    static func ncxPlayOrderRepairReasons(
        entries: [String],
        in archive: EPUBArchiveSnapshot
    ) throws -> [String] {
        var playOrderCount = 0
        var pageListCount = 0
        var incompleteNavPointCount = 0
        for entry in entries where URL(fileURLWithPath: entry).pathExtension.lowercased() == "ncx" {
            guard let ncxText = try entryText(entry, in: archive) else {
                continue
            }
            if ncxPlayOrderNeedsRepair(in: ncxText) {
                playOrderCount += 1
            }
            if ncxPageListNeedsRepair(in: ncxText) {
                pageListCount += 1
            }
            incompleteNavPointCount += incompleteNCXNavPointRepairCount(in: ncxText)
        }

        var reasons: [String] = []
        if incompleteNavPointCount > 0 {
            let pointText = incompleteNavPointCount == 1 ? "point" : "points"
            reasons.append("Repair \(incompleteNavPointCount) incomplete NCX navigation \(pointText)")
        }
        if playOrderCount > 0 {
            let fileText = playOrderCount == 1 ? "file" : "files"
            reasons.append("Renumber \(playOrderCount) NCX table of contents playOrder \(fileText)")
        }
        if pageListCount > 0 {
            let fileText = pageListCount == 1 ? "file" : "files"
            reasons.append("Remove broken NCX pageList from \(pageListCount) table of contents \(fileText)")
        }
        return reasons
    }

    private static func ncxContentSourceRepairs(
        entries: [String],
        in archive: EPUBArchiveSnapshot,
        opfPath: String,
        opfText: String
    ) throws -> [String: [NCXContentSourceRepair]] {
        let existingEntries = Set(entries.map(normalizedEPUBResourcePath))
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
            .filter { item in
                manifestItemIsOPSContentDocument(item)
                    && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
            }
        let manifestItemsByFileName = Dictionary(grouping: manifestItems) { item in
            URL(fileURLWithPath: normalizedEPUBResourcePath(item.entryPath)).lastPathComponent
        }

        var repairsByNCX: [String: [NCXContentSourceRepair]] = [:]
        for ncxEntry in entries where URL(fileURLWithPath: ncxEntry).pathExtension.lowercased() == "ncx" {
            guard let ncxText = try entryText(ncxEntry, in: archive) else { continue }
            let repairs = repairableNCXContentSourceTags(
                in: ncxText,
                ncxEntry: ncxEntry,
                existingEntries: existingEntries,
                manifestItemsByFileName: manifestItemsByFileName
            )
            if !repairs.isEmpty {
                repairsByNCX[ncxEntry] = repairs
            }
        }
        return repairsByNCX
    }

    private static func repairableNCXContentSourceTags(
        in ncxText: String,
        ncxEntry: String,
        existingEntries: Set<String>,
        manifestItemsByFileName: [String: [EPUBManifestItem]]
    ) -> [NCXContentSourceRepair] {
        matches(in: ncxText, pattern: #"<(?:[A-Za-z0-9_]+:)?content\b[^>]*>"#).compactMap { tag in
            let attrs = attributes(in: tag)
            guard let rawSource = attrs["src"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawSource.isEmpty else {
                return nil
            }

            let sourceWithoutFragment = hrefWithoutFragment(rawSource)
            let currentTarget = joinedEPUBPath(baseEntryPath: ncxEntry, href: sourceWithoutFragment)
            guard !existingEntries.contains(normalizedEPUBResourcePath(currentTarget)) else {
                return nil
            }

            let fileName = URL(fileURLWithPath: normalizedEPUBResourcePath(sourceWithoutFragment)).lastPathComponent
            guard let candidates = manifestItemsByFileName[fileName],
                  candidates.count == 1,
                  let candidate = candidates.first else {
                return nil
            }

            let replacement = relativeEPUBHref(from: ncxEntry, to: candidate.entryPath) + hrefFragment(from: rawSource)
            guard replacement != rawSource else { return nil }
            return NCXContentSourceRepair(tag: tag, replacementSource: replacement)
        }
    }

    private static func repairableNCXContentFragmentTags(
        in ncxText: String,
        ncxEntry: String,
        entryExists: (String) -> Bool,
        textForEntry: (String) throws -> String?
    ) throws -> [NCXContentSourceRepair] {
        var repairs: [NCXContentSourceRepair] = []
        for tag in matches(in: ncxText, pattern: #"<(?:[A-Za-z0-9_]+:)?content\b[^>]*>"#) {
            let attrs = attributes(in: tag)
            guard let rawSource = attributeValue("src", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  localHrefIsFragmentRepairCandidate(rawSource) else {
                continue
            }

            let fragment = hrefFragmentIdentifier(from: rawSource)
            guard !fragment.isEmpty else { continue }

            let sourceWithoutFragment = hrefWithoutFragment(rawSource)
            let targetEntryPath = joinedEPUBPath(baseEntryPath: ncxEntry, href: sourceWithoutFragment)
            guard entryExists(targetEntryPath),
                  let targetText = try textForEntry(targetEntryPath),
                  !documentContainsFragmentIdentifier(targetText, fragment) else {
                continue
            }

            guard sourceWithoutFragment != rawSource else { continue }
            repairs.append(NCXContentSourceRepair(tag: tag, replacementSource: sourceWithoutFragment))
        }
        return repairs
    }

    private static func packageNeedsEPUB3VersionForStandardsProfile(_ opfText: String) -> Bool {
        guard let packageTag = matches(
            in: opfText,
            pattern: #"<(?:[A-Za-z0-9_]+:)?package\b[^>]*>"#
        ).first else {
            return false
        }

        let version = attributes(in: packageTag)["version"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.map(packageVersionIsOlderThanEPUB3) ?? true else { return false }
        return packageUsesEPUB3OnlyFeatures(opfText)
    }

    private static func packageUsesEPUB3OnlyFeatures(_ opfText: String) -> Bool {
        [
            #"<(?:[A-Za-z0-9_]+:)?item\b(?=[^>]*\bproperties\s*=)"#,
            #"<(?:[A-Za-z0-9_]+:)?meta\b(?=[^>]*\bproperty\s*=)"#,
            #"<(?:[A-Za-z0-9_]+:)?meta\b(?=[^>]*\brefines\s*=)"#,
            #"<(?:[A-Za-z0-9_]+:)?link\b(?=[^>]*\brel\s*=)"#,
            #"<(?:[A-Za-z0-9_]+:)?collection\b"#,
            #"<(?:[A-Za-z0-9_]+:)?package\b(?=[^>]*\bprefix\s*=)"#
        ].contains { pattern in
            opfText.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    private static func epubManifestItems(in opfText: String, opfPath: String) -> [EPUBManifestItem] {
        matches(in: opfText, pattern: #"<(?:[A-Za-z0-9_]+:)?item\b[^>]*>"#).compactMap { tag in
            let attrs = attributes(in: tag)
            guard let id = attrs["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let href = attrs["href"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  !href.isEmpty else {
                return nil
            }
            return EPUBManifestItem(
                tag: tag,
                id: id,
                href: xmlUnescapedText(href),
                mediaType: attrs["media-type"] ?? "",
                properties: propertyParts(attrs["properties"] ?? ""),
                entryPath: joinedEPUBPath(baseEntryPath: opfPath, href: href)
            )
        }
    }

    private static func removableMissingManifestHelperItems(
        manifestItems: [EPUBManifestItem],
        existingEntries: Set<String>,
        opfText: String
    ) -> [EPUBManifestItem] {
        let spineIDs = Set(spineIDRefs(in: opfText))
        return manifestItems.filter { item in
            guard !spineIDs.contains(item.id),
                  !existingEntries.contains(normalizedEPUBResourcePath(item.entryPath)) else {
                return false
            }
            return manifestHelperReferenceCanBeRemoved(item)
        }
    }

    private static func removingMissingManifestHelperReferences(
        in opfText: String,
        opfPath: String,
        existingEntries: Set<String>
    ) -> String {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let removableItems = removableMissingManifestHelperItems(
            manifestItems: manifestItems,
            existingEntries: existingEntries,
            opfText: opfText
        )
        guard !removableItems.isEmpty else { return opfText }
        return removableItems.reduce(opfText) { text, item in
            text.replacingOccurrences(of: item.tag, with: "\n")
        }
    }

    private static func deadSpineItemrefTags(
        in opfText: String,
        manifestItems: [EPUBManifestItem]
    ) -> [String] {
        let manifestIDs = Set(manifestItems.map(\.id))
        return itemrefTags(in: opfText).filter { tag in
            guard let idref = attributeValue("idref", in: attributes(in: tag)),
                  !idref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return !manifestIDs.contains(idref)
        }
    }

    private static func removingDeadSpineItemrefs(in opfText: String, manifestItems: [EPUBManifestItem]) -> String {
        deadSpineItemrefTags(in: opfText, manifestItems: manifestItems).reduce(opfText) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func legacySpinePageMapTags(in opfText: String) -> [String] {
        xmlStartTags(named: "spine", in: opfText).filter { tag in
            attributes(in: tag)["page-map"] != nil
        }
    }

    private static func removingLegacySpinePageMapAttributes(in opfText: String) -> String {
        legacySpinePageMapTags(in: opfText).reduce(opfText) { partial, tag in
            partial.replacingOccurrences(
                of: tag,
                with: tagRemovingAttribute(tag, name: "page-map")
            )
        }
    }

    private static func itemrefTags(in text: String) -> [String] {
        xmlStartTags(named: "itemref", in: text)
    }

    private static func duplicateManifestIDRepairCount(in manifestItems: [EPUBManifestItem]) -> Int {
        var seen = Set<String>()
        var duplicates = 0
        for item in manifestItems {
            if !seen.insert(item.id).inserted {
                duplicates += 1
            }
        }
        return duplicates
    }

    private static func uniquingDuplicateManifestIDs(in opfText: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(?:[A-Za-z0-9_]+:)?item\b[^>]*>"#,
            options: []
        ) else {
            return opfText
        }

        let matches = regex.matches(in: opfText, range: NSRange(opfText.startIndex..<opfText.endIndex, in: opfText))
        guard !matches.isEmpty else { return opfText }

        var usedKeys = Set<String>()
        for match in matches {
            guard let range = Range(match.range, in: opfText) else { continue }
            let tag = String(opfText[range])
            guard let rawID = attributes(in: tag)["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawID.isEmpty else {
                continue
            }
            usedKeys.insert(metadataComparisonKey(xmlUnescapedText(rawID)))
        }

        var seenKeys = Set<String>()
        var replacements: [(range: NSRange, replacement: String)] = []

        for match in matches {
            guard let range = Range(match.range, in: opfText) else { continue }
            let tag = String(opfText[range])
            guard let rawID = attributes(in: tag)["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawID.isEmpty else {
                continue
            }
            let cleanID = xmlUnescapedText(rawID)
            let key = metadataComparisonKey(cleanID)
            guard !key.isEmpty else { continue }

            if seenKeys.insert(key).inserted {
                continue
            }

            let replacementID = uniqueDuplicateManifestID(base: cleanID, usedKeys: &usedKeys)
            let replacementTag = tagSettingAttribute(tag, name: "id", value: replacementID)
            guard replacementTag != tag else { continue }
            replacements.append((match.range, replacementTag))
        }

        guard !replacements.isEmpty else { return opfText }

        var result = opfText
        for replacement in replacements.reversed() {
            guard let range = Range(replacement.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement.replacement)
        }
        return result
    }

    private static func invalidCoverImagePropertyManifestItems(in manifestItems: [EPUBManifestItem]) -> [EPUBManifestItem] {
        manifestItems.filter { item in
            item.properties.contains { $0.caseInsensitiveCompare("cover-image") == .orderedSame }
                && !manifestItemIsImage(item)
        }
    }

    private static func removingInvalidManifestProperties(in opfText: String, opfPath: String) -> String {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let withoutInvalidCoverMarkers = invalidCoverImagePropertyManifestItems(in: manifestItems).reduce(opfText) { partial, item in
            partial.replacingOccurrences(
                of: item.tag,
                with: tagSettingProperties(item.tag, adding: [], removing: ["cover-image"])
            )
        }
        let refreshedItems = epubManifestItems(in: withoutInvalidCoverMarkers, opfPath: opfPath)
        return duplicateCoverImagePropertyManifestItems(
            in: refreshedItems,
            opfText: withoutInvalidCoverMarkers
        ).reduce(withoutInvalidCoverMarkers) { partial, item in
            partial.replacingOccurrences(
                of: item.tag,
                with: tagSettingProperties(item.tag, adding: [], removing: ["cover-image"])
            )
        }
    }

    private static func manifestItemIsImage(_ item: EPUBManifestItem) -> Bool {
        let mediaType = item.mediaType.lowercased()
        let fileExtension = URL(fileURLWithPath: item.href).pathExtension.lowercased()
        return mediaType.hasPrefix("image/")
            || ["jpg", "jpeg", "png", "webp", "gif", "svg"].contains(fileExtension)
    }

    private static func fontManifestMediaTypeRepairs(
        in manifestItems: [EPUBManifestItem]
    ) -> [(item: EPUBManifestItem, mediaType: String)] {
        manifestItems.compactMap { item in
            guard let mediaType = standardizedFontMediaType(for: item),
                  item.mediaType.lowercased() != mediaType else {
                return nil
            }
            return (item, mediaType)
        }
    }

    private static func standardizedFontMediaType(for item: EPUBManifestItem) -> String? {
        switch URL(fileURLWithPath: item.href).pathExtension.lowercased() {
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        default:
            return nil
        }
    }

    private static func normalizingFontManifestMediaTypes(in opfText: String, opfPath: String) -> String {
        fontManifestMediaTypeRepairs(
            in: epubManifestItems(in: opfText, opfPath: opfPath)
        ).reduce(opfText) { partial, repair in
            partial.replacingOccurrences(
                of: repair.item.tag,
                with: tagSettingAttribute(repair.item.tag, name: "media-type", value: repair.mediaType)
            )
        }
    }

    private static func addingMissingManifestResourceDeclarations(
        in opfText: String,
        opfPath: String,
        unpackedURL: URL,
        existingEntries: Set<String>,
        fileManager: FileManager
    ) throws -> String {
        let declarations = try missingManifestResourceDeclarations(
            existingEntries: existingEntries,
            opfPath: opfPath,
            opfText: opfText
        ) { entryPath in
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try String(contentsOf: url, encoding: .utf8)
        }
        guard !declarations.isEmpty else { return opfText }

        var manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let insertion = declarations.map { declaration -> String in
            let baseID = manifestIDBase(forResourcePath: declaration.entryPath)
            let id = uniqueManifestID(prefix: baseID, existingItems: manifestItems)
            let tag = #"    <item id="\#(xmlEscapedAttribute(id))" href="\#(xmlEscapedAttribute(declaration.href))" media-type="\#(xmlEscapedAttribute(declaration.mediaType))"/>"#
            manifestItems.append(EPUBManifestItem(
                tag: tag,
                id: id,
                href: declaration.href,
                mediaType: declaration.mediaType,
                properties: [],
                entryPath: declaration.entryPath
            ))
            return tag
        }.joined(separator: "\n")

        return insertBeforeManifestClose(in: opfText, insertion: insertion + "\n  ")
    }

    private static func manifestIDBase(forResourcePath path: String) -> String {
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let cleaned = fileName
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return cleaned.isEmpty ? "sable-resource" : "sable-\(cleaned)"
    }

    private static func duplicateCoverImagePropertyManifestItems(
        in manifestItems: [EPUBManifestItem],
        opfText: String
    ) -> [EPUBManifestItem] {
        let coverItems = manifestItems.filter { item in
            manifestItemIsImage(item)
                && item.properties.contains { $0.caseInsensitiveCompare("cover-image") == .orderedSame }
        }
        guard coverItems.count > 1 else { return [] }
        let preferredID = coverAnalysis(in: opfText).likelyCoverID ?? coverItems[0].id
        return coverItems.filter { $0.id != preferredID }
    }

    private static func brokenGuideReferenceTags(
        in opfText: String,
        opfPath: String,
        existingEntries: Set<String>,
        manifestItems: [EPUBManifestItem]
    ) -> [String] {
        var manifestItemsByEntryPath: [String: EPUBManifestItem] = [:]
        for item in manifestItems {
            manifestItemsByEntryPath[normalizedEPUBResourcePath(item.entryPath)] = item
        }
        return guideReferenceTags(in: opfText).filter { tag in
            let attrs = attributes(in: tag)
            guard let href = attrs["href"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty else {
                return true
            }

            let targetPath = joinedEPUBPath(baseEntryPath: opfPath, href: hrefWithoutFragment(href))
            let normalizedTarget = normalizedEPUBResourcePath(targetPath)
            guard existingEntries.contains(normalizedTarget) else {
                return true
            }

            if let item = manifestItemsByEntryPath[normalizedTarget] {
                return !manifestItemIsOPSContentDocument(item)
            }

            let fileExtension = URL(fileURLWithPath: normalizedTarget).pathExtension.lowercased()
            return !["html", "xhtml"].contains(fileExtension)
        }
    }

    private static func removingBrokenGuideReferences(
        in opfText: String,
        opfPath: String,
        existingEntries: Set<String>
    ) -> String {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let brokenReferences = brokenGuideReferenceTags(
            in: opfText,
            opfPath: opfPath,
            existingEntries: existingEntries,
            manifestItems: manifestItems
        )
        let withoutBrokenReferences = brokenReferences.reduce(opfText) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
        return removingEmptyGuideElements(in: withoutBrokenReferences)
    }

    private static func guideReferenceTags(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?reference\b[^>]*?/\s*>|<(?:[A-Za-z0-9_]+:)?reference\b[^>]*>[\s\S]*?</(?:[A-Za-z0-9_]+:)?reference>"#
        )
    }

    private static func emptyGuideTags(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?guide\b[^>]*?/\s*>|<(?:[A-Za-z0-9_]+:)?guide\b[^>]*>\s*</(?:[A-Za-z0-9_]+:)?guide>"#
        )
    }

    private static func removingEmptyGuideElements(in text: String) -> String {
        emptyGuideTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func obsoleteToursTags(in text: String) -> [String] {
        let blocks = xmlElementBlocks(named: "tours", in: text).map(\.fullText)
        let selfClosing = xmlStartTags(named: "tours", in: text).filter { tag in
            tag.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/>")
        }
        return blocks + selfClosing
    }

    private static func removingObsoleteToursElements(in text: String) -> String {
        obsoleteToursTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func hrefWithoutFragment(_ href: String) -> String {
        guard let fragmentRange = href.range(of: "#") else {
            return href
        }
        return String(href[..<fragmentRange.lowerBound])
    }

    private static func hrefSuffix(from href: String) -> String {
        let queryRange = href.range(of: "?")
        let fragmentRange = href.range(of: "#")
        switch (queryRange, fragmentRange) {
        case (let query?, let fragment?):
            let start = query.lowerBound < fragment.lowerBound ? query.lowerBound : fragment.lowerBound
            return String(href[start...])
        case (let query?, nil):
            return String(href[query.lowerBound...])
        case (nil, let fragment?):
            return String(href[fragment.lowerBound...])
        case (nil, nil):
            return ""
        }
    }

    private static func missingLocalLinkFragmentCount(
        in archive: EPUBArchiveSnapshot,
        manifestItems: [EPUBManifestItem]
    ) throws -> Int {
        let existingEntries = Set(archive.entries.map(normalizedEPUBResourcePath))
        let contentItems = manifestItems.filter { item in
            manifestItemIsOPSContentDocument(item)
                && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
        }
        var textCache: [String: String] = [:]

        func textForEntry(_ entryPath: String) throws -> String? {
            let key = normalizedEPUBResourcePath(entryPath)
            if let cached = textCache[key] {
                return cached
            }
            guard let text = try entryTextForNormalizedPath(entryPath, in: archive) else {
                return nil
            }
            textCache[key] = text
            return text
        }

        var count = 0
        for item in contentItems {
            guard let text = try textForEntry(item.entryPath) else { continue }
            count += try localMissingFragmentLinkRepairs(
                in: text,
                sourceEntryPath: item.entryPath,
                entryExists: { entryPath in
                    existingEntries.contains(normalizedEPUBResourcePath(entryPath))
                },
                textForEntry: textForEntry
            ).count
        }
        return count
    }

    private static func localMissingFragmentLinkRepairs(
        in text: String,
        sourceEntryPath: String,
        entryExists: (String) -> Bool,
        textForEntry: (String) throws -> String?
    ) throws -> [LocalLinkFragmentRepair] {
        var repairs: [LocalLinkFragmentRepair] = []
        for tag in localHrefTags(in: text) {
            let attrs = attributes(in: tag)
            guard let href = attributeValue("href", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  localHrefIsFragmentRepairCandidate(href) else {
                continue
            }

            let fragment = hrefFragmentIdentifier(from: href)
            guard !fragment.isEmpty else { continue }

            let hrefBase = hrefWithoutFragment(href)
            guard !hrefBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let targetEntryPath = joinedEPUBPath(baseEntryPath: sourceEntryPath, href: hrefBase)
            guard entryExists(targetEntryPath),
                  let targetText = try textForEntry(targetEntryPath),
                  !documentContainsFragmentIdentifier(targetText, fragment) else {
                continue
            }

            let replacementTag = tagSettingAttribute(tag, name: "href", value: hrefBase)
            guard replacementTag != tag else { continue }
            repairs.append(LocalLinkFragmentRepair(tag: tag, replacementTag: replacementTag))
        }
        return repairs
    }

    private static func localHrefTags(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?(?:a|area|link)\b(?=[^>]*\bhref\s*=)[^>]*>"#
        )
    }

    private static func localHrefIsFragmentRepairCandidate(_ href: String) -> Bool {
        let trimmed = xmlUnescapedText(href)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("#") else { return false }
        guard !trimmed.hasPrefix("#") else { return false }
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                            options: .regularExpression) == nil else {
            return false
        }
        return true
    }

    private static func missingManifestResourceDeclarations(
        existingEntries: Set<String>,
        opfPath: String,
        opfText: String,
        textForEntry: (String) throws -> String?
    ) throws -> [EPUBManifestResourceDeclaration] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let manifestEntryPaths = Set(manifestItems.map { normalizedEPUBResourcePath($0.entryPath) })
        let references = try linkedResourceReferences(
            existingEntries: existingEntries,
            opfPath: opfPath,
            opfText: opfText,
            textForEntry: textForEntry
        )

        var declarations: [EPUBManifestResourceDeclaration] = []
        var seen = Set<String>()
        for entryPath in references.existingTargets {
            let normalizedPath = normalizedEPUBResourcePath(entryPath)
            guard !manifestEntryPaths.contains(normalizedPath),
                  seen.insert(normalizedPath).inserted,
                  let mediaType = manifestMediaType(forResourcePath: normalizedPath) else {
                continue
            }
            declarations.append(EPUBManifestResourceDeclaration(
                entryPath: entryPath,
                href: opfRelativeHref(from: opfPath, to: entryPath),
                mediaType: mediaType
            ))
        }
        return declarations.sorted { $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending }
    }

    private static func missingLinkedResourceReferenceCount(
        existingEntries: Set<String>,
        entries: [String],
        opfPath: String,
        opfText: String,
        textForEntry: (String) throws -> String?
    ) throws -> Int {
        try linkedResourceReferenceRepairs(
            existingEntries: existingEntries,
            entries: entries,
            opfPath: opfPath,
            opfText: opfText,
            textForEntry: textForEntry
        ).count
    }

    private static func staleLinkedResourceReferenceCount(
        existingEntries: Set<String>,
        entries: [String],
        opfPath: String,
        opfText: String,
        textForEntry: (String) throws -> String?
    ) throws -> Int {
        try staleLinkedResourceReferenceRepairs(
            existingEntries: existingEntries,
            entries: entries,
            opfPath: opfPath,
            opfText: opfText,
            textForEntry: textForEntry
        ).count
    }

    private static func linkedResourceReferences(
        existingEntries: Set<String>,
        opfPath: String,
        opfText: String,
        textForEntry: (String) throws -> String?
    ) throws -> (existingTargets: Set<String>, missingTargets: Set<String>) {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let scannableItems = manifestItems.filter { item in
            (manifestItemCanCarryContentDocumentProperties(item) || manifestItemIsCSS(item))
                && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
        }

        var existingTargets = Set<String>()
        var missingTargets = Set<String>()
        for item in scannableItems {
            guard let text = try textForEntry(item.entryPath) else { continue }
            let hrefs = manifestItemIsCSS(item)
                ? cssResourceHrefs(in: text)
                : contentResourceHrefs(in: text)
            for href in hrefs {
                guard let target = localResourceTargetEntryPath(from: href, baseEntryPath: item.entryPath) else {
                    continue
                }
                let normalizedTarget = normalizedEPUBResourcePath(target)
                guard manifestMediaType(forResourcePath: normalizedTarget) != nil else {
                    continue
                }
                if existingEntries.contains(normalizedTarget) {
                    existingTargets.insert(target)
                } else {
                    missingTargets.insert(normalizedTarget)
                }
            }
        }
        return (existingTargets, missingTargets)
    }

    private static func linkedResourceReferenceRepairs(
        existingEntries: Set<String>,
        entries: [String],
        opfPath: String,
        opfText: String,
        textForEntry: (String) throws -> String?
    ) throws -> [LinkedResourceReferenceRepair] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let scannableItems = manifestItems.filter { item in
            (manifestItemCanCarryContentDocumentProperties(item) || manifestItemIsCSS(item))
                && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
        }
        let exactEntries = Set(entries.map(cleanEPUBResourcePath))
        let entriesByNormalized = uniqueEntriesByNormalizedPath(entries)
        let entriesByFileName = uniqueResourceEntriesByFileName(entries)

        var repairs: [LinkedResourceReferenceRepair] = []
        var seen = Set<String>()
        for item in scannableItems {
            guard let text = try textForEntry(item.entryPath) else { continue }
            let hrefs = manifestItemIsCSS(item)
                ? cssResourceHrefs(in: text)
                : contentResourceHrefs(in: text)
            for href in hrefs {
                guard let target = localResourceTargetEntryPath(from: href, baseEntryPath: item.entryPath) else {
                    continue
                }
                let exactTarget = cleanEPUBResourcePath(target)
                guard manifestMediaType(forResourcePath: exactTarget) != nil,
                      !exactEntries.contains(exactTarget),
                      let replacementTarget = replacementEntryForMissingResource(
                        exactTarget,
                        entriesByNormalized: entriesByNormalized,
                        entriesByFileName: entriesByFileName
                      ) else {
                    continue
                }
                let replacement = relativeEPUBHref(from: item.entryPath, to: replacementTarget) + hrefSuffix(from: href)
                let key = "\(item.entryPath)\n\(href)\n\(replacement)"
                guard replacement != href, seen.insert(key).inserted else { continue }
                repairs.append(LinkedResourceReferenceRepair(
                    entryPath: item.entryPath,
                    originalReference: href,
                    replacementReference: replacement
                ))
            }
        }
        return repairs
    }

    private static func staleLinkedResourceReferenceRepairs(
        existingEntries: Set<String>,
        entries: [String],
        opfPath: String,
        opfText: String,
        textForEntry: (String) throws -> String?
    ) throws -> [StaleLinkedResourceReferenceRepair] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let scannableItems = manifestItems.filter { item in
            manifestItemCanCarryContentDocumentProperties(item)
                && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
        }
        let exactEntries = Set(entries.map(cleanEPUBResourcePath))
        let entriesByNormalized = uniqueEntriesByNormalizedPath(entries)
        let entriesByFileName = uniqueResourceEntriesByFileName(entries)

        var repairs: [StaleLinkedResourceReferenceRepair] = []
        var seen = Set<String>()
        for item in scannableItems {
            guard let text = try textForEntry(item.entryPath) else { continue }
            for reference in contentResourceReferenceTags(in: text) {
                guard staleResourceTagCanBeRemoved(reference.tag, tagName: reference.tagName, reference: reference.reference),
                      let target = localResourceTargetEntryPath(from: reference.reference, baseEntryPath: item.entryPath) else {
                    continue
                }
                let exactTarget = cleanEPUBResourcePath(target)
                guard manifestMediaType(forResourcePath: exactTarget) != nil,
                      !exactEntries.contains(exactTarget),
                      replacementEntryForMissingResource(
                        exactTarget,
                        entriesByNormalized: entriesByNormalized,
                        entriesByFileName: entriesByFileName
                      ) == nil else {
                    continue
                }
                let key = "\(item.entryPath)\n\(reference.tag)\n\(reference.reference)"
                guard seen.insert(key).inserted else { continue }
                repairs.append(StaleLinkedResourceReferenceRepair(
                    entryPath: item.entryPath,
                    tag: reference.tag,
                    originalReference: reference.reference
                ))
            }
        }
        return repairs
    }

    private static func uniqueEntriesByNormalizedPath(_ entries: [String]) -> [String: String] {
        Dictionary(grouping: entries.map(cleanEPUBResourcePath)) { normalizedEPUBResourcePath($0) }
            .compactMapValues { paths in
                let unique = Array(Set(paths))
                return unique.count == 1 ? unique[0] : nil
            }
    }

    private static func uniqueResourceEntriesByFileName(_ entries: [String]) -> [String: String] {
        Dictionary(grouping: entries.map(cleanEPUBResourcePath).filter { manifestMediaType(forResourcePath: $0) != nil }) {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased()
        }
        .compactMapValues { paths in
            let unique = Array(Set(paths))
            return unique.count == 1 ? unique[0] : nil
        }
    }

    private static func replacementEntryForMissingResource(
        _ target: String,
        entriesByNormalized: [String: String],
        entriesByFileName: [String: String]
    ) -> String? {
        if let exactCaseRepair = entriesByNormalized[normalizedEPUBResourcePath(target)],
           URL(fileURLWithPath: exactCaseRepair).pathExtension.caseInsensitiveCompare(URL(fileURLWithPath: target).pathExtension) == .orderedSame {
            return exactCaseRepair
        }

        let fileName = URL(fileURLWithPath: target).lastPathComponent.lowercased()
        guard let fileNameRepair = entriesByFileName[fileName],
              URL(fileURLWithPath: fileNameRepair).pathExtension.caseInsensitiveCompare(URL(fileURLWithPath: target).pathExtension) == .orderedSame else {
            return nil
        }
        return fileNameRepair
    }

    private static func contentResourceHrefs(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b(?=[^>]*\b(?:href|src|poster)\s*=)[^>]*>"#
        ).flatMap { tag in
            let attrs = attributes(in: tag)
            return ["href", "src", "poster"].compactMap { name in
                attributeValue(name, in: attrs)
            }
        }
    }

    private static func contentResourceReferenceTags(in text: String) -> [(tag: String, tagName: String, reference: String)] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b(?=[^>]*\b(?:href|src|poster)\s*=)[^>]*>"#
        ).compactMap { tag in
            guard let tagName = firstMatch(in: tag, pattern: #"<\s*([A-Za-z0-9_]+:?[A-Za-z0-9_.-]*)\b"#) else {
                return nil
            }
            let attrs = attributes(in: tag)
            let reference = ["href", "src", "poster"].compactMap { name in
                attributeValue(name, in: attrs)
            }.first
            guard let reference else { return nil }
            return (tag, tagName, reference)
        }
    }

    private static func staleResourceTagCanBeRemoved(
        _ tag: String,
        tagName: String,
        reference: String
    ) -> Bool {
        let localName = tagName.split(separator: ":").last.map(String.init)?.lowercased() ?? tagName.lowercased()
        let attrs = attributes(in: tag)
        let extensionName = URL(fileURLWithPath: hrefWithoutFragment(reference)).pathExtension.lowercased()
        switch localName {
        case "link":
            let rel = attributeValue("rel", in: attrs)?.lowercased() ?? ""
            let type = attributeValue("type", in: attrs)?.lowercased() ?? ""
            return rel.split(whereSeparator: \.isWhitespace).contains("stylesheet")
                || type == "text/css"
                || extensionName == "css"
        case "img", "image":
            return ["jpg", "jpeg", "png", "gif", "webp", "svg"].contains(extensionName)
        default:
            return false
        }
    }

    private static func cssResourceHrefs(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"url\(\s*['"]?([^'")]+)['"]?\s*\)"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func missingLocalScriptReferenceCount(
        in text: String,
        baseEntryPath: String,
        existingEntries: Set<String>
    ) -> Int {
        missingLocalScriptReferenceTags(
            in: text,
            baseEntryPath: baseEntryPath,
            existingEntries: existingEntries
        ).count
    }

    private static func removeMissingLocalScriptReferences(
        in unpackedURL: URL,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws -> Bool {
        let existingEntries = Set(try unpackedEntryNames(in: unpackedURL, fileManager: fileManager)
            .map(normalizedEPUBResourcePath))
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let contentItems = manifestItems.filter { item in
            manifestItemCanCarryContentDocumentProperties(item)
                && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
        }

        var changed = false
        for item in contentItems {
            let url = try safeUnpackedURL(for: item.entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            var text = try String(contentsOf: url, encoding: .utf8)
            let missingScriptTags = missingLocalScriptReferenceTags(
                in: text,
                baseEntryPath: item.entryPath,
                existingEntries: existingEntries
            )
            guard !missingScriptTags.isEmpty else { continue }

            for tag in missingScriptTags {
                text = text.replacingOccurrences(of: tag, with: "\n")
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            changed = true
        }

        return changed
    }

    private static func missingLocalScriptReferenceTags(
        in text: String,
        baseEntryPath: String,
        existingEntries: Set<String>
    ) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?script\b[^>]*\bsrc\s*=\s*["'][^"']+["'][^>]*>\s*</(?:[A-Za-z0-9_]+:)?script>"#
        ).filter { tag in
            let attrs = attributes(in: tag)
            guard let src = attributeValue("src", in: attrs),
                  let target = localResourceTargetEntryPath(from: src, baseEntryPath: baseEntryPath) else {
                return false
            }
            return !existingEntries.contains(normalizedEPUBResourcePath(target))
        }
    }

    private static func localResourceTargetEntryPath(from href: String, baseEntryPath: String) -> String? {
        let trimmed = xmlUnescapedText(href).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#") else {
            return nil
        }
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                            options: .regularExpression) == nil else {
            return nil
        }
        let withoutFragment = hrefWithoutFragment(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutFragment.isEmpty else { return nil }
        return joinedEPUBPath(baseEntryPath: baseEntryPath, href: withoutFragment)
    }

    private static func manifestMediaType(forResourcePath path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "xhtml", "html":
            return "application/xhtml+xml"
        case "css":
            return "text/css"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "webp":
            return "image/webp"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "js", "mjs":
            return "application/javascript"
        case "ncx":
            return "application/x-dtbncx+xml"
        default:
            return nil
        }
    }

    private static func documentContainsFragmentIdentifier(_ text: String, _ fragment: String) -> Bool {
        let wanted = metadataComparisonKey(fragment)
        guard !wanted.isEmpty else { return false }
        return matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b[^>]*>"#
        ).contains { tag in
            let attrs = attributes(in: tag)
            return ["id", "name"].contains { key in
                guard let value = attributeValue(key, in: attrs) else { return false }
                return metadataComparisonKey(xmlUnescapedText(value)) == wanted
            }
        }
    }

    private static func manifestHelperReferenceCanBeRemoved(_ item: EPUBManifestItem) -> Bool {
        let mediaType = item.mediaType.lowercased()
        let fileExtension = URL(fileURLWithPath: item.href).pathExtension.lowercased()
        if ["css", "js"].contains(fileExtension) {
            return true
        }
        return [
            "text/css",
            "text/javascript",
            "application/javascript",
            "application/ecmascript",
            "application/x-javascript"
        ].contains(mediaType)
    }

    private static func spineIDRefs(in opfText: String) -> [String] {
        matches(in: opfText, pattern: #"<(?:[A-Za-z0-9_]+:)?itemref\b[^>]*>"#)
            .compactMap { attributes(in: $0)["idref"] }
    }

    private static func propertyParts(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func manifestItemIsOPSContentDocument(_ item: EPUBManifestItem) -> Bool {
        let mediaType = item.mediaType.lowercased()
        let fileExtension = URL(fileURLWithPath: item.href).pathExtension.lowercased()
        return mediaType == "application/xhtml+xml" || ["html", "xhtml"].contains(fileExtension)
    }

    private static func manifestItemIsCSS(_ item: EPUBManifestItem) -> Bool {
        item.mediaType.lowercased() == "text/css"
            || URL(fileURLWithPath: item.href).pathExtension.lowercased() == "css"
    }

    private static func manifestItemCanCarryContentDocumentProperties(_ item: EPUBManifestItem) -> Bool {
        manifestItemIsOPSContentDocument(item)
    }

    private static func missingRequiredManifestProperties(
        in opfText: String,
        opfPath: String,
        textForEntry: (String) throws -> String?
    ) throws -> [(item: EPUBManifestItem, properties: [String])] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        var missing: [(item: EPUBManifestItem, properties: [String])] = []
        for item in manifestItems where manifestItemCanCarryContentDocumentProperties(item) {
            guard let text = try textForEntry(item.entryPath) else { continue }
            let requiredProperties = requiredManifestProperties(forContentDocument: text)
            let currentProperties = Set(item.properties.map { $0.lowercased() })
            let missingProperties = requiredProperties
                .filter { !currentProperties.contains($0.lowercased()) }
                .sorted()
            if !missingProperties.isEmpty {
                missing.append((item, missingProperties))
            }
        }
        return missing
    }

    private static func falseScriptedManifestItems(
        in opfText: String,
        opfPath: String,
        textForEntry: (String) throws -> String?
    ) throws -> [EPUBManifestItem] {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        var items: [EPUBManifestItem] = []
        for item in manifestItems where manifestItemCanCarryContentDocumentProperties(item) {
            guard item.properties.contains(where: { $0.caseInsensitiveCompare("scripted") == .orderedSame }),
                  let text = try textForEntry(item.entryPath) else {
                continue
            }
            guard !requiredManifestProperties(forContentDocument: text).contains("scripted") else {
                continue
            }
            items.append(item)
        }
        return items
    }

    private static func removingFalseScriptedManifestProperties(
        in opfText: String,
        opfPath: String,
        unpackedURL: URL,
        fileManager: FileManager
    ) throws -> String {
        try falseScriptedManifestItems(in: opfText, opfPath: opfPath) { entryPath in
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try String(contentsOf: url, encoding: .utf8)
        }.reduce(opfText) { partial, item in
            partial.replacingOccurrences(
                of: item.tag,
                with: tagSettingProperties(item.tag, adding: [], removing: ["scripted"])
            )
        }
    }

    private static func declaringRequiredManifestProperties(
        in opfText: String,
        opfPath: String,
        unpackedURL: URL,
        fileManager: FileManager
    ) throws -> String {
        try missingRequiredManifestProperties(in: opfText, opfPath: opfPath) { entryPath in
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try String(contentsOf: url, encoding: .utf8)
        }.reduce(opfText) { partial, item in
            partial.replacingOccurrences(
                of: item.item.tag,
                with: tagSettingProperties(item.item.tag, adding: item.properties, removing: [])
            )
        }
    }

    private static let contentDocumentSVGElementRegex = try! NSRegularExpression(
        pattern: #"<(?:[A-Za-z0-9_]+:)?svg\b"#,
        options: [.caseInsensitive]
    )
    private static let contentDocumentSVGNamespaceRegex = try! NSRegularExpression(
        pattern: #"xmlns(?::[A-Za-z0-9_]+)?\s*=\s*["']http://www\.w3\.org/2000/svg["']"#,
        options: [.caseInsensitive]
    )
    private static let contentDocumentScriptElementRegex = try! NSRegularExpression(
        pattern: #"<(?:[A-Za-z0-9_]+:)?script\b"#,
        options: [.caseInsensitive]
    )
    private static let contentDocumentEventHandlerRegex = try! NSRegularExpression(
        pattern: #"\son[A-Za-z]+\s*="#
    )
    private static let contentDocumentJavaScriptLinkRegex = try! NSRegularExpression(
        pattern: #"\b(?:href|src)\s*=\s*["'][^"']*javascript:"#,
        options: [.caseInsensitive]
    )

    private static func requiredManifestProperties(forContentDocument text: String) -> Set<String> {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var properties = Set<String>()
        if contentDocumentSVGElementRegex.firstMatch(in: text, range: fullRange) != nil
            || contentDocumentSVGNamespaceRegex.firstMatch(in: text, range: fullRange) != nil {
            properties.insert("svg")
        }

        if contentDocumentScriptElementRegex.firstMatch(in: text, range: fullRange) != nil
            || contentDocumentEventHandlerRegex.firstMatch(in: text, range: fullRange) != nil
            || contentDocumentJavaScriptLinkRegex.firstMatch(in: text, range: fullRange) != nil {
            properties.insert("scripted")
        }

        return properties
    }

    private static func repairEPUBContentDocumentHeaders(
        in unpackedURL: URL,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws -> Bool {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let fallbackTitle = currentDublinCoreValues(in: opfText, localName: "title").first ?? "EPUB document"
        var changed = false

        for item in manifestItems where manifestItemCanCarryContentDocumentProperties(item) {
            let url = try safeUnpackedURL(for: item.entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            var text = try String(contentsOf: url, encoding: .utf8)
            var repaired = normalizingLegacyXHTMLDoctype(in: text)
            repaired = normalizingContentTypeMetaDeclarations(in: repaired)
            repaired = removingObsoleteHTTPMetadataTags(in: repaired)
            repaired = normalizingInvalidImageDimensionAttributes(in: repaired)
            repaired = repairingParagraphChildrenInsideHeadings(in: repaired)
            repaired = removingOrphanClosingInlineTags(in: repaired)
            repaired = normalizingHTMLVoidElementClosures(in: repaired)
            repaired = removingInvalidXMLControlCharacters(in: repaired)
            repaired = normalizingNamedNBSPReferences(in: repaired)
            repaired = normalizingUnsupportedXHTMLNamedEntities(in: repaired)
            repaired = normalizingBareAmpersands(in: repaired)
            repaired = normalizingDuplicateContentIDs(in: repaired)
            repaired = normalizingCustomDataAttributeNames(in: repaired)
            repaired = fillingEmptyHTMLTitle(in: repaired, title: fallbackTitle)
            if repaired != text {
                text = repaired
                try text.write(to: url, atomically: true, encoding: .utf8)
                changed = true
            }
        }

        return changed
    }

    private static func hasLegacyXHTMLDoctype(in text: String) -> Bool {
        !legacyXHTMLDoctypeTags(in: text).isEmpty
    }

    private static func legacyXHTMLDoctypeTags(in text: String) -> [String] {
        matches(in: text, pattern: #"<!DOCTYPE[^>]*>"#).filter { tag in
            let normalized = tag
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .lowercased()
            return normalized.contains("<!doctype html ")
                && (normalized.contains(" public ") || normalized.contains(" system "))
        }
    }

    private static func normalizingLegacyXHTMLDoctype(in text: String) -> String {
        legacyXHTMLDoctypeTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "<!DOCTYPE html>")
        }
    }

    private static func contentTypeMetaTagsNeedingRepair(in text: String) -> [String] {
        metaTags(in: text).filter { tag in
            let attrs = attributes(in: tag)
            guard metadataComparisonKey(attrs["http-equiv"] ?? "")
                .caseInsensitiveCompare("content-type") == .orderedSame else {
                return false
            }
            let content = metadataComparisonKey(attrs["content"] ?? "")
                .replacingOccurrences(of: #"\s*;\s*"#, with: "; ", options: .regularExpression)
                .lowercased()
            return content != "text/html; charset=utf-8"
        }
    }

    private static func normalizingContentTypeMetaDeclarations(in text: String) -> String {
        contentTypeMetaTagsNeedingRepair(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(
                of: tag,
                with: tagSettingAttribute(tag, name: "content", value: "text/html; charset=utf-8")
            )
        }
    }

    private static func obsoleteHTTPMetadataTags(in text: String) -> [String] {
        metaTags(in: text).filter { tag in
            let value = metadataComparisonKey(attributes(in: tag)["http-equiv"] ?? "").lowercased()
            return value == "content-style-type" || value == "content-script-type"
        }
    }

    private static func removingObsoleteHTTPMetadataTags(in text: String) -> String {
        obsoleteHTTPMetadataTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func emptyHTMLTitleTags(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?title\b[^>]*>\s*</(?:[A-Za-z0-9_]+:)?title>"#
        )
    }

    private static func fillingEmptyHTMLTitle(in text: String, title: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return text }
        return emptyHTMLTitleTags(in: text).reduce(text) { partial, tag in
            let replacement = tag.replacingOccurrences(
                of: #">\s*</"#,
                with: ">\(xmlEscapedText(cleanTitle))</",
                options: .regularExpression
            )
            return partial.replacingOccurrences(of: tag, with: replacement)
        }
    }

    private static func invalidImageDimensionAttributeCount(in text: String) -> Int {
        imageTags(in: text).reduce(0) { count, tag in
            let attrs = attributes(in: tag)
            return count + ["width", "height"].filter { name in
                invalidImageDimensionAttributeValue(attrs[name])
            }.count
        }
    }

    private static func normalizingInvalidImageDimensionAttributes(in text: String) -> String {
        imageTags(in: text).reduce(text) { partial, tag in
            let attrs = attributes(in: tag)
            var replacement = tag
            var style = attrs["style"] ?? ""
            var changed = false

            for name in ["width", "height"] {
                guard let value = attrs[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      invalidImageDimensionAttributeValue(value) else {
                    continue
                }
                if !cssStyleHasProperty(style, name) {
                    style = cssStyleAppendingDeclaration(style, property: name, value: value)
                }
                replacement = tagRemovingAttribute(replacement, name: name)
                changed = true
            }

            guard changed else { return partial }
            replacement = tagSettingAttribute(replacement, name: "style", value: style)
            return partial.replacingOccurrences(of: tag, with: replacement)
        }
    }

    private static func namedNBSPReferenceCount(in text: String) -> Int {
        matches(in: text, pattern: #"&nbsp;"#).count
    }

    private static func normalizingNamedNBSPReferences(in text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: "&#160;")
    }

    private static let xmlBuiltinEntityNames: Set<String> = ["amp", "lt", "gt", "apos", "quot"]

    private static let commonXHTMLNamedEntityReplacements: [String: String] = [
        "nbsp": "&#160;",
        "ndash": "&#8211;",
        "mdash": "&#8212;",
        "hellip": "&#8230;",
        "lsquo": "&#8216;",
        "rsquo": "&#8217;",
        "ldquo": "&#8220;",
        "rdquo": "&#8221;",
        "bull": "&#8226;",
        "copy": "&#169;",
        "reg": "&#174;",
        "trade": "&#8482;",
        "times": "&#215;",
        "divide": "&#247;",
        "middot": "&#183;",
        "laquo": "&#171;",
        "raquo": "&#187;"
    ]

    private static func unsupportedXHTMLNamedEntityReferenceCount(in text: String) -> Int {
        unsupportedXHTMLNamedEntityReferences(in: text).count
    }

    private static func unsupportedXHTMLNamedEntityReferences(in text: String) -> [(name: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"&([A-Za-z][A-Za-z0-9]+);"#,
            options: []
        ) else {
            return []
        }

        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let name = String(text[nameRange]).lowercased()
            guard !xmlBuiltinEntityNames.contains(name) else { return nil }
            guard name != "nbsp" else { return nil }
            return (name, match.range)
        }
    }

    private static func normalizingUnsupportedXHTMLNamedEntities(in text: String) -> String {
        let references = unsupportedXHTMLNamedEntityReferences(in: text)
        guard !references.isEmpty else { return text }

        var result = text
        for reference in references.reversed() {
            guard let range = Range(reference.range, in: result) else { continue }
            let replacement = commonXHTMLNamedEntityReplacements[reference.name]
                ?? "&amp;\(reference.name);"
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func bareAmpersandReferenceCount(in text: String) -> Int {
        bareAmpersandRanges(in: text).count
    }

    private static func bareAmpersandRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(
            pattern: #"&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9]+;)"#,
            options: []
        ) else {
            return []
        }
        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).map(\.range)
    }

    private static func normalizingBareAmpersands(in text: String) -> String {
        let ranges = bareAmpersandRanges(in: text)
        guard !ranges.isEmpty else { return text }

        var result = text
        for nsRange in ranges.reversed() {
            guard let range = Range(nsRange, in: result) else { continue }
            result.replaceSubrange(range, with: "&amp;")
        }
        return result
    }

    private static let htmlVoidElementNames: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    private static func htmlVoidElementClosureCount(in text: String) -> Int {
        htmlVoidElementTagsNeedingClosure(in: text).count
    }

    private static func htmlVoidElementTagsNeedingClosure(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?(?:area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr)\b[^>]*>"#
        ).filter { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasSuffix("/>") else { return false }
            guard let tagName = firstMatch(
                in: trimmed,
                pattern: #"^<\s*(?:[A-Za-z0-9_]+:)?([A-Za-z][A-Za-z0-9_.:-]*)"#
            )?.lowercased() else {
                return false
            }
            return htmlVoidElementNames.contains(tagName)
        }
    }

    private static func normalizingHTMLVoidElementClosures(in text: String) -> String {
        htmlVoidElementTagsNeedingClosure(in: text).reduce(text) { partial, tag in
            let replacement = String(tag.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) + " />"
            return partial.replacingOccurrences(of: tag, with: replacement)
        }
    }

    private static func invalidXMLControlCharacterCount(in text: String) -> Int {
        text.unicodeScalars.filter { scalar in
            !xmlScalarIsAllowed(scalar)
        }.count
    }

    private static func removingInvalidXMLControlCharacters(in text: String) -> String {
        String(text.unicodeScalars.filter(xmlScalarIsAllowed))
    }

    private static func xmlScalarIsAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x9, 0xA, 0xD,
             0x20...0xD7FF,
             0xE000...0xFFFD,
             0x10000...0x10FFFF:
            return true
        default:
            return false
        }
    }

    private static func uppercaseCustomDataAttributeCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: #"\sdata-[A-Za-z0-9_.:-]*[A-Z][A-Za-z0-9_.:-]*\s*="#,
            options: []
        ) else {
            return 0
        }
        return regex.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }

    private static func normalizingCustomDataAttributeNames(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\s(data-[A-Za-z0-9_.:-]*[A-Z][A-Za-z0-9_.:-]*)(\s*=)"#,
            options: []
        ) else {
            return text
        }

        var result = text
        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges > 2,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let nameRange = Range(match.range(at: 1), in: result),
                  let equalsRange = Range(match.range(at: 2), in: result) else {
                continue
            }
            let prefix = result[fullRange.lowerBound..<nameRange.lowerBound]
            let suffix = result[equalsRange]
            result.replaceSubrange(
                fullRange,
                with: "\(prefix)\(result[nameRange].lowercased())\(suffix)"
            )
        }
        return result
    }

    private static func duplicateContentIDCount(in text: String) -> Int {
        var seen = Set<String>()
        var duplicates = 0
        for tag in matches(in: text, pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b[^>]*>"#) {
            guard let rawID = attributeValue("id", in: attributes(in: tag)) else { continue }
            let key = metadataComparisonKey(xmlUnescapedText(rawID))
            guard !key.isEmpty else { continue }
            if !seen.insert(key).inserted {
                duplicates += 1
            }
        }
        return duplicates
    }

    private static func normalizingDuplicateContentIDs(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b[^>]*>"#,
            options: []
        ) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard !matches.isEmpty else { return text }

        var allExistingKeys = Set<String>()
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let tag = String(text[range])
            guard let rawID = attributeValue("id", in: attributes(in: tag)) else { continue }
            let key = metadataComparisonKey(xmlUnescapedText(rawID))
            guard !key.isEmpty else { continue }
            allExistingKeys.insert(key)
        }

        var seenKeys = Set<String>()
        var usedKeys = allExistingKeys
        var replacements: [(range: NSRange, replacement: String)] = []

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let tag = String(text[range])
            guard let rawID = attributeValue("id", in: attributes(in: tag)) else { continue }
            let cleanID = xmlUnescapedText(rawID).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = metadataComparisonKey(cleanID)
            guard !key.isEmpty else { continue }

            if seenKeys.insert(key).inserted {
                continue
            }

            let replacementID = uniqueDuplicateContentID(base: cleanID, usedKeys: &usedKeys)
            let replacementTag = tagSettingAttribute(tag, name: "id", value: replacementID)
            guard replacementTag != tag else { continue }
            replacements.append((match.range, replacementTag))
        }

        guard !replacements.isEmpty else { return text }

        var result = text
        for replacement in replacements.reversed() {
            guard let range = Range(replacement.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement.replacement)
        }
        return result
    }

    private static func uniqueDuplicateContentID(base: String, usedKeys: inout Set<String>) -> String {
        var cleanBase = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^A-Za-z0-9_.:-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if cleanBase.isEmpty {
            cleanBase = "sable-id"
        }
        if cleanBase.range(of: #"^[A-Za-z_]"#, options: .regularExpression) == nil {
            cleanBase = "sable-\(cleanBase)"
        }

        for index in 2...1000 {
            let candidate = "\(cleanBase)-sable-\(index)"
            let key = metadataComparisonKey(candidate)
            if usedKeys.insert(key).inserted {
                return candidate
            }
        }

        let fallback = "\(cleanBase)-sable-\(UUID().uuidString)"
        usedKeys.insert(metadataComparisonKey(fallback))
        return fallback
    }

    private struct HeadingParagraphBlock {
        var range: NSRange
        var tagName: String
        var attributes: String
        var paragraphBodies: [String]
    }

    private struct XMLElementBlock {
        var range: NSRange
        var tagName: String
        var openingTag: String
        var body: String
        var fullText: String
    }

    private static func paragraphChildrenInsideHeadingCount(in text: String) -> Int {
        headingParagraphBlocks(in: text).count
    }

    private static func repairingParagraphChildrenInsideHeadings(in text: String) -> String {
        let blocks = headingParagraphBlocks(in: text)
        guard !blocks.isEmpty else { return text }

        var result = text
        for block in blocks.reversed() {
            guard let fullRange = Range(block.range, in: result) else { continue }

            let paragraphBodies = block.paragraphBodies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !paragraphBodies.isEmpty else { continue }

            let replacement = paragraphBodies.map { body in
                "<\(block.tagName)\(block.attributes)>\(body)</\(block.tagName)>"
            }.joined(separator: "\n")
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    private static func headingParagraphBlocks(in text: String) -> [HeadingParagraphBlock] {
        guard let openingRegex = try? NSRegularExpression(
            pattern: #"<((?:[A-Za-z0-9_]+:)?h[1-6])\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = openingRegex.matches(in: text, range: fullRange)
        var blocks: [HeadingParagraphBlock] = []

        for match in matches {
            guard match.numberOfRanges > 2,
                  let openingRange = Range(match.range(at: 0), in: text),
                  let nameRange = Range(match.range(at: 1), in: text),
                  let attributesRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let tagName = String(text[nameRange])
            let closingPattern = #"</\s*"# + NSRegularExpression.escapedPattern(for: tagName) + #"\s*>"#
            guard let closingRegex = try? NSRegularExpression(pattern: closingPattern, options: [.caseInsensitive]) else {
                continue
            }

            let closingSearchRange = NSRange(openingRange.upperBound..<text.endIndex, in: text)
            guard let closingMatch = closingRegex.firstMatch(in: text, range: closingSearchRange),
                  let closingRange = Range(closingMatch.range, in: text) else {
                continue
            }

            let body = String(text[openingRange.upperBound..<closingRange.lowerBound])
            guard let paragraphBodies = paragraphChildBodiesIfOnlyParagraphs(in: body),
                  !paragraphBodies.isEmpty else {
                continue
            }

            let blockRange = NSRange(openingRange.lowerBound..<closingRange.upperBound, in: text)
            blocks.append(
                HeadingParagraphBlock(
                    range: blockRange,
                    tagName: tagName,
                    attributes: String(text[attributesRange]),
                    paragraphBodies: paragraphBodies
                )
            )
        }

        return blocks
    }

    private static func paragraphChildBodiesIfOnlyParagraphs(in text: String) -> [String]? {
        guard let openingParagraphRegex = try? NSRegularExpression(
            pattern: #"<(?:[A-Za-z0-9_]+:)?p\b[^>]*>"#,
            options: [.caseInsensitive]
        ),
            let closingParagraphRegex = try? NSRegularExpression(
                pattern: #"</(?:[A-Za-z0-9_]+:)?p\s*>"#,
                options: [.caseInsensitive]
            ) else {
            return nil
        }

        var cursor = text.startIndex
        var bodies: [String] = []

        while cursor < text.endIndex {
            let searchRange = NSRange(cursor..<text.endIndex, in: text)
            guard let openingMatch = openingParagraphRegex.firstMatch(in: text, range: searchRange),
                  let openingRange = Range(openingMatch.range, in: text) else {
                return text[cursor..<text.endIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? bodies
                    : nil
            }

            guard text[cursor..<openingRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let closingSearchRange = NSRange(openingRange.upperBound..<text.endIndex, in: text)
            guard let closingMatch = closingParagraphRegex.firstMatch(in: text, range: closingSearchRange),
                  let closingRange = Range(closingMatch.range, in: text) else {
                return nil
            }

            bodies.append(String(text[openingRange.upperBound..<closingRange.lowerBound]))
            cursor = closingRange.upperBound
        }

        return bodies
    }

    private static let removableOrphanInlineClosingTags: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "cite", "code", "dfn", "em", "i",
        "kbd", "mark", "q", "s", "samp", "small", "span", "strong", "sub",
        "sup", "time", "u", "var"
    ]

    private static func orphanClosingInlineTagCount(in text: String) -> Int {
        orphanClosingInlineTagRanges(in: text).count
    }

    private static func removingOrphanClosingInlineTags(in text: String) -> String {
        let ranges = orphanClosingInlineTagRanges(in: text)
        guard !ranges.isEmpty else { return text }

        var result = text
        for nsRange in ranges.reversed() {
            guard let range = Range(nsRange, in: result) else { continue }
            result.removeSubrange(range)
        }
        return result
    }

    private static func orphanClosingInlineTagRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9_.:-]*)\b[^>]*?>"#,
            options: []
        ) else {
            return []
        }

        var openCounts: [String: Int] = [:]
        var orphanRanges: [NSRange] = []
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)

        for match in matches {
            guard match.numberOfRanges > 2,
                  let tagRange = Range(match.range, in: text),
                  let slashRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let tagName = text[nameRange].lowercased()
            guard removableOrphanInlineClosingTags.contains(String(tagName)) else {
                continue
            }

            let tagText = text[tagRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let isClosingTag = !text[slashRange].isEmpty
            let isSelfClosingTag = tagText.hasSuffix("/>")
            let key = String(tagName)

            if isClosingTag {
                let count = openCounts[key, default: 0]
                if count > 0 {
                    openCounts[key] = count - 1
                } else {
                    orphanRanges.append(match.range)
                }
            } else if !isSelfClosingTag {
                openCounts[key, default: 0] += 1
            }
        }

        return orphanRanges
    }

    private static func uniqueDuplicateManifestID(base: String, usedKeys: inout Set<String>) -> String {
        uniqueDuplicateContentID(base: base, usedKeys: &usedKeys)
    }

    private static func xhtmlDocumentNeedsManualStructureReview(_ text: String) -> Bool {
        let repairedForParser = repairingParagraphChildrenInsideHeadings(
            in: removingOrphanClosingInlineTags(
                in: normalizingBareAmpersands(
                    in: normalizingUnsupportedXHTMLNamedEntities(
                        in: normalizingNamedNBSPReferences(
                            in: removingInvalidXMLControlCharacters(
                                in: normalizingHTMLVoidElementClosures(
                                    in: normalizingLegacyXHTMLDoctype(in: text)
                                )
                            )
                        )
                    )
                )
            )
        )
        guard let data = repairedForParser.data(using: .utf8) else { return true }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        return !parser.parse()
    }

    private static func normalizingSimpleCSSSyntax(in text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: #";{2,}"#, with: ";", options: .regularExpression)
        return closingSimpleCSSBraceImbalance(
            in: removingUnmatchedCSSClosingBraces(
                in: closingUnclosedCSSComments(in: cleaned)
            )
        )
    }

    private static func cssNeedsManualSyntaxReview(_ text: String) -> Bool {
        let repaired = normalizingSimpleCSSSyntax(in: text)
        return cssHasUnclosedComment(repaired) || cssBraceBalance(repaired) != 0
    }

    private static func cssHasUnclosedComment(_ text: String) -> Bool {
        let openingCount = matches(in: text, pattern: #"/\*"#).count
        let closingCount = matches(in: text, pattern: #"\*/"#).count
        return openingCount != closingCount
    }

    private static func cssBraceBalance(_ text: String) -> Int {
        var balance = 0
        var isInString: Character?
        var previous: Character?
        for character in text {
            if let quote = isInString {
                if character == quote, previous != "\\" {
                    isInString = nil
                }
                previous = character
                continue
            }

            if character == "\"" || character == "'" {
                isInString = character
            } else if character == "{" {
                balance += 1
            } else if character == "}" {
                balance -= 1
            }
            previous = character
        }
        return balance
    }

    private static func closingUnclosedCSSComments(in text: String) -> String {
        let openingCount = matches(in: text, pattern: #"/\*"#).count
        let closingCount = matches(in: text, pattern: #"\*/"#).count
        guard openingCount > closingCount else { return text }
        return text + String(repeating: " */", count: openingCount - closingCount)
    }

    private static func removingUnmatchedCSSClosingBraces(in text: String) -> String {
        var result = ""
        var balance = 0
        var isInString: Character?
        var previous: Character?

        for character in text {
            if let quote = isInString {
                result.append(character)
                if character == quote, previous != "\\" {
                    isInString = nil
                }
                previous = character
                continue
            }

            if character == "\"" || character == "'" {
                isInString = character
                result.append(character)
            } else if character == "{" {
                balance += 1
                result.append(character)
            } else if character == "}" {
                guard balance > 0 else {
                    previous = character
                    continue
                }
                balance -= 1
                result.append(character)
            } else {
                result.append(character)
            }
            previous = character
        }

        return result
    }

    private static func closingSimpleCSSBraceImbalance(in text: String) -> String {
        guard !cssHasUnclosedComment(text) else { return text }
        let balance = cssBraceBalance(text)
        guard balance > 0 else { return text }
        return text + String(repeating: "}", count: balance)
    }

    private static func repairEPUBStylesheets(
        in unpackedURL: URL,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws -> Bool {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        var changed = false
        for item in manifestItems where manifestItemIsCSS(item) {
            let url = try safeUnpackedURL(for: item.entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let repaired = normalizingSimpleCSSSyntax(in: text)
            guard repaired != text else { continue }
            try repaired.write(to: url, atomically: true, encoding: .utf8)
            changed = true
        }
        return changed
    }

    private static func imageTags(in text: String) -> [String] {
        matches(in: text, pattern: #"<(?:[A-Za-z0-9_]+:)?img\b[^>]*>"#)
    }

    private static func invalidImageDimensionAttributeValue(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return false
        }
        return value.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil
    }

    private static func cssStyleHasProperty(_ style: String, _ property: String) -> Bool {
        style.range(
            of: #"(?i)(^|;)\s*\#(NSRegularExpression.escapedPattern(for: property))\s*:"#,
            options: .regularExpression
        ) != nil
    }

    private static func cssStyleAppendingDeclaration(_ style: String, property: String, value: String) -> String {
        let trimmed = style.trimmingCharacters(in: .whitespacesAndNewlines)
        let declaration = "\(property): \(value);"
        guard !trimmed.isEmpty else { return declaration }
        if trimmed.hasSuffix(";") {
            return "\(trimmed) \(declaration)"
        }
        return "\(trimmed); \(declaration)"
    }

    private static func likelyNavigationManifestItem(
        in manifestItems: [EPUBManifestItem],
        archive: EPUBArchiveSnapshot
    ) throws -> EPUBManifestItem? {
        var candidates: [(score: Int, item: EPUBManifestItem)] = []
        for item in manifestItems where item.mediaType.lowercased().contains("xhtml") {
            let hrefKey = item.href.lowercased()
            let idKey = item.id.lowercased()
            var score = 0
            if hrefKey.contains("nav") || idKey.contains("nav") {
                score += 50
            }
            if hrefKey.contains("toc") || idKey.contains("toc") {
                score += 40
            }
            guard score > 0,
                  let text = try entryTextForNormalizedPath(item.entryPath, in: archive),
                  navigationDocumentHasTOC(text) else {
                continue
            }
            candidates.append((score, item))
        }
        return candidates.sorted { $0.score > $1.score }.first?.item
    }

    private static func entryTextForNormalizedPath(_ path: String, in archive: EPUBArchiveSnapshot) throws -> String? {
        let key = normalizedEPUBResourcePath(path)
        guard let entry = archive.entryNameByNormalizedPath[key] else {
            return nil
        }
        return try entryText(entry, in: archive)
    }

    private static func entryDataForNormalizedPath(_ path: String, in archive: EPUBArchiveSnapshot) throws -> Data? {
        let key = normalizedEPUBResourcePath(path)
        guard let entry = archive.entryNameByNormalizedPath[key] else {
            return nil
        }
        return try entryData(entry, in: archive)
    }

    private static func navigationEntriesForSpine(
        in opfText: String,
        manifestItems: [EPUBManifestItem],
        textForEntry: (String) throws -> String?
    ) rethrows -> [EPUBNavigationEntry] {
        let itemsByID = Dictionary(manifestItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let itemRefs = matches(in: opfText, pattern: #"<(?:[A-Za-z0-9_]+:)?itemref\b[^>]*>"#)
            .compactMap { attributes(in: $0)["idref"] }

        var seen = Set<String>()
        var entries: [EPUBNavigationEntry] = []
        for idref in itemRefs {
            guard let item = itemsByID[idref],
                  !item.isNavigationDocument,
                  item.mediaType.lowercased().contains("xhtml"),
                  seen.insert(item.entryPath).inserted else {
                continue
            }
            let text = try textForEntry(item.entryPath)
            let label = navigationLabel(from: text, fallbackHref: item.href)
            entries.append(EPUBNavigationEntry(
                href: item.href,
                label: label.text,
                source: label.source,
                level: 1
            ))
        }
        return entries
    }

    private static func navigationOrderNeedsManualReview(
        navigationText: String,
        navEntryPath: String,
        opfPath: String,
        opfText: String,
        manifestItems: [EPUBManifestItem]
    ) -> Bool {
        let spineEntries = spineEntryPaths(in: opfText, manifestItems: manifestItems)
        guard spineEntries.count > 1 else { return false }
        let spineIndexByPath = Dictionary(uniqueKeysWithValues: spineEntries.enumerated().map { index, path in
            (normalizedEPUBResourcePath(path), index)
        })

        let orderedNavIndexes = navigationDocumentHrefs(in: navigationText).compactMap { href -> Int? in
            guard let target = localResourceTargetEntryPath(from: href, baseEntryPath: navEntryPath) else {
                return nil
            }
            return spineIndexByPath[normalizedEPUBResourcePath(target)]
        }
        guard orderedNavIndexes.count >= 2 else { return false }
        return orderedNavIndexes != orderedNavIndexes.sorted()
    }

    private static func spineEntryPaths(in opfText: String, manifestItems: [EPUBManifestItem]) -> [String] {
        let itemsByID = Dictionary(manifestItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return spineIDRefs(in: opfText).compactMap { idref in
            itemsByID[idref]?.entryPath
        }
    }

    private static func navigationDocumentHrefs(in text: String) -> [String] {
        let tocNavBlock = xmlElementBlocks(named: "nav", in: text).first { block in
            let attrs = attributes(in: block.openingTag)
            return attrs.contains { key, value in
                (key.caseInsensitiveCompare("epub:type") == .orderedSame
                    || key.caseInsensitiveCompare("type") == .orderedSame)
                    && propertyParts(value).contains { $0.caseInsensitiveCompare("toc") == .orderedSame }
            }
        }
        let searchText = tocNavBlock?.fullText ?? text
        return localHrefTags(in: searchText).compactMap { tag in
            attributeValue("href", in: attributes(in: tag))
        }
    }

    private static func navigationEntriesFromNCX(
        in manifestItems: [EPUBManifestItem],
        opfPath: String,
        textForEntry: (String) throws -> String?,
        entryExists: (String) -> Bool
    ) rethrows -> [EPUBNavigationEntry] {
        let manifestEntryPaths = Set(manifestItems.map { normalizedEPUBResourcePath($0.entryPath) })
        let ncxItems = manifestItems.filter { item in
            let mediaType = item.mediaType.lowercased()
            let href = item.href.lowercased()
            let id = item.id.lowercased()
            return mediaType.contains("dtbncx")
                || href.hasSuffix(".ncx")
                || id.contains("ncx")
        }

        var entries: [EPUBNavigationEntry] = []
        var seenTargets = Set<String>()
        for item in ncxItems {
            guard let ncxText = try textForEntry(item.entryPath) else { continue }
            let points = ncxNavigationPoints(in: ncxText)
            for point in points {
                guard navigationLabelIsUseful(point.label) else { continue }

                let targetEntryPath = joinedEPUBPath(baseEntryPath: item.entryPath, href: point.source)
                let normalizedTarget = normalizedEPUBResourcePath(targetEntryPath)
                guard manifestEntryPaths.contains(normalizedTarget),
                      entryExists(targetEntryPath),
                      seenTargets.insert("\(normalizedTarget)#\(hrefFragment(from: point.source))").inserted else {
                    continue
                }

                let href = opfRelativeHref(from: opfPath, to: targetEntryPath) + hrefFragment(from: point.source)
                entries.append(EPUBNavigationEntry(
                    href: href,
                    label: point.label,
                    source: .ncx,
                    level: clampedSemanticHeadingLevel(point.depth)
                ))
            }
        }
        return entries
    }

    private static func ncxNavigationPoints(in ncxText: String) -> [NCXNavigationPoint] {
        if let xmlPoints = NCXNavigationParser.parse(ncxText), !xmlPoints.isEmpty {
            return xmlPoints
        }
        return fallbackNCXNavigationPoints(in: ncxText)
    }

    private static func fallbackNCXNavigationPoints(in ncxText: String) -> [NCXNavigationPoint] {
        let navPointBlocks = xmlElementBlocks(named: "navPoint", in: ncxText)
        return navPointBlocks.enumerated().compactMap { index, block in
            guard let rawLabel = firstElementText(named: "text", in: block.body),
                  let contentTag = xmlStartTags(named: "content", in: block.body).first,
                  let rawSource = attributeValue("src", in: attributes(in: contentTag)) else {
                return nil
            }

            let label = strippingHTMLTags(rawLabel)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            return NCXNavigationPoint(label: label, source: rawSource, depth: 1, sequence: index)
        }
    }

    private final class NCXNavigationParser: NSObject, XMLParserDelegate {
        private struct OpenPoint {
            var depth: Int
            var sequence: Int
            var label = ""
            var source = ""
            var isInNavLabel = false
            var isCollectingText = false
            var textBuffer = ""
        }

        private var stack: [OpenPoint] = []
        private var points: [NCXNavigationPoint] = []
        private var nextSequence = 0

        static func parse(_ text: String) -> [NCXNavigationPoint]? {
            guard let data = text.data(using: .utf8) else { return nil }
            let delegate = NCXNavigationParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.shouldResolveExternalEntities = false
            guard parser.parse() else { return nil }
            return delegate.points.sorted { lhs, rhs in
                lhs.sequence < rhs.sequence
            }
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localXMLName(elementName, qualifiedName: qName)
            switch name {
            case "navpoint":
                let depth = stack.count + 1
                stack.append(OpenPoint(depth: depth, sequence: nextSequence))
                nextSequence += 1
            case "navlabel":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].isInNavLabel = true
            case "text":
                guard !stack.isEmpty, stack[stack.count - 1].isInNavLabel else { return }
                stack[stack.count - 1].isCollectingText = true
                stack[stack.count - 1].textBuffer = ""
            case "content":
                guard !stack.isEmpty else { return }
                let source = attributeDict.first { key, _ in
                    key.caseInsensitiveCompare("src") == .orderedSame
                }?.value ?? ""
                if !source.isEmpty, stack[stack.count - 1].source.isEmpty {
                    stack[stack.count - 1].source = source
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty, stack[stack.count - 1].isCollectingText else { return }
            stack[stack.count - 1].textBuffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localXMLName(elementName, qualifiedName: qName)
            switch name {
            case "text":
                guard !stack.isEmpty, stack[stack.count - 1].isCollectingText else { return }
                let text = stack[stack.count - 1].textBuffer
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, stack[stack.count - 1].label.isEmpty {
                    stack[stack.count - 1].label = text
                }
                stack[stack.count - 1].textBuffer = ""
                stack[stack.count - 1].isCollectingText = false
            case "navlabel":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].isInNavLabel = false
            case "navpoint":
                guard let point = stack.popLast() else { return }
                let label = point.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let source = point.source.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty, !source.isEmpty else { return }
                points.append(NCXNavigationPoint(
                    label: label,
                    source: source,
                    depth: point.depth,
                    sequence: point.sequence
                ))
            default:
                break
            }
        }

        private func localXMLName(_ elementName: String, qualifiedName qName: String?) -> String {
            let value: String
            if let qName, !qName.isEmpty {
                value = qName
            } else {
                value = elementName
            }
            return value
                .split(separator: ":", omittingEmptySubsequences: false)
                .last
                .map(String.init)?
                .lowercased() ?? value.lowercased()
        }
    }

    private static func semanticHeadingCandidates(
        in opfText: String,
        manifestItems: [EPUBManifestItem],
        opfPath: String,
        textForEntry: (String) throws -> String?,
        entryExists: (String) -> Bool
    ) rethrows -> [EPUBStructureHeadingCandidate] {
        let ncxEntries = try navigationEntriesFromNCX(
            in: manifestItems,
            opfPath: opfPath,
            textForEntry: textForEntry,
            entryExists: entryExists
        )
        let entryMap = manifestItems.reduce(into: [String: EPUBManifestItem]()) { partialResult, item in
            let key = normalizedEPUBResourcePath(item.entryPath)
            if partialResult[key] == nil {
                partialResult[key] = item
            }
        }

        var candidates: [EPUBStructureHeadingCandidate] = []
        var seen = Set<String>()
        for entry in ncxEntries {
            let fragment = hrefFragmentIdentifier(from: entry.href)
            guard semanticHeadingLabelIsUseful(entry.label) else {
                continue
            }

            let entryPath = joinedEPUBPath(baseEntryPath: opfPath, href: entry.href)
            let normalizedEntryPath = normalizedEPUBResourcePath(entryPath)
            guard let manifestItem = entryMap[normalizedEntryPath],
                  manifestItem.mediaType.lowercased().contains("xhtml") || htmlResourcePathExtensions.contains(URL(fileURLWithPath: entryPath).pathExtension.lowercased()),
                  let text = try textForEntry(entryPath) else {
                continue
            }

            let replacement: (range: Range<String.Index>, replacement: String)?
            let candidateFragment: String?
            let seenKey: String
            if fragment.isEmpty {
                replacement = semanticHeadingReplacementAtFirstVisibleBlock(
                    in: text,
                    label: entry.label,
                    level: entry.level
                )
                candidateFragment = nil
                seenKey = "\(normalizedEntryPath)#document"
            } else {
                replacement = semanticHeadingReplacement(
                    in: text,
                    fragment: fragment,
                    label: entry.label,
                    level: entry.level
                )
                candidateFragment = fragment
                seenKey = "\(normalizedEntryPath)#\(fragment)"
            }
            guard replacement != nil,
                  seen.insert(seenKey).inserted else {
                continue
            }
            candidates.append(EPUBStructureHeadingCandidate(
                entryPath: entryPath,
                href: entry.href,
                fragment: candidateFragment,
                label: entry.label,
                level: entry.level
            ))
        }
        return candidates
    }

    private static func clampedSemanticHeadingLevel(_ level: Int) -> Int {
        min(max(level, 1), 6)
    }

    private static func semanticHeadingLabelIsUseful(_ label: String) -> Bool {
        let key = metadataComparisonKey(label)
        guard navigationLabelIsUseful(label) else { return false }
        if ["contents", "table of contents", "toc"].contains(key) {
            return false
        }
        return true
    }

    private static func navigationEntriesAreUseful(_ entries: [EPUBNavigationEntry]) -> Bool {
        guard (2...150).contains(entries.count) else { return false }
        let usefulLabels = entries.filter {
            $0.source != .fallback && navigationLabelIsUseful($0.label)
        }
        return usefulLabels.count >= 2
    }

    private static func navigationLabelIsUseful(_ label: String) -> Bool {
        let key = metadataComparisonKey(label)
        guard !key.isEmpty else { return false }
        if ["chapter", "section", "page", "cover", "title page", "untitled"].contains(key) {
            return false
        }
        if key.range(of: #"^page\s*\d+$"#, options: .regularExpression) != nil {
            return false
        }
        if key.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func subjectTagsNeedDisplayCasing(_ values: [String]) -> Bool {
        values.contains { value in
            let cleaned = cleanedEPUBSubjectTerm(value)
            return !cleaned.isEmpty && cleaned != value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func cleaningSubjectTagDisplayCasing(in opfText: String) -> String {
        let subjects = currentDublinCoreValues(in: opfText, localName: "subject")
        guard subjectTagsNeedDisplayCasing(subjects) else { return opfText }
        return replacingDublinCoreElements(
            in: opfText,
            localName: "subject",
            values: subjects.map(cleanedEPUBSubjectTerm)
        )
    }

    private static func cleanedEPUBSubjectTerm(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return collapsed }

        let phraseOverrides: [String: String] = [
            "boys love": "Boys Love",
            "girls love": "Girls Love",
            "light novel": "Light Novel",
            "male protagonist": "Male Protagonist",
            "manga tie-in": "Manga Tie-In",
            "science fiction": "Science Fiction",
            "slice of life": "Slice of Life",
            "web novel": "Web Novel"
        ]
        let phraseKey = metadataComparisonKey(collapsed).lowercased()
        if let override = phraseOverrides[phraseKey] {
            return override
        }

        let smallWords: Set<String> = [
            "a", "an", "and", "as", "at", "but", "by", "for", "from",
            "in", "into", "nor", "of", "on", "or", "the", "to", "via",
            "vs", "with", "without"
        ]
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
            "ona": "ONA",
            "ova": "OVA",
            "pdf": "PDF",
            "r18": "R18",
            "tv": "TV",
            "vr": "VR",
            "ya": "YA"
        ]

        var wordIndex = 0
        return collapsed
            .components(separatedBy: " ")
            .map { word in
                defer { wordIndex += 1 }
                return cleanedEPUBSubjectWord(
                    word,
                    isFirstWord: wordIndex == 0,
                    smallWords: smallWords,
                    acronymOverrides: acronymOverrides
                )
            }
            .joined(separator: " ")
    }

    private static func cleanedEPUBSubjectWord(
        _ value: String,
        isFirstWord: Bool,
        smallWords: Set<String>,
        acronymOverrides: [String: String]
    ) -> String {
        var result = ""
        var current = ""
        var isFirstSegment = true

        func flush() {
            guard !current.isEmpty else { return }
            result += cleanedEPUBSubjectWordSegment(
                current,
                isFirstWord: isFirstWord && isFirstSegment,
                smallWords: smallWords,
                acronymOverrides: acronymOverrides
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

    private static func cleanedEPUBSubjectWordSegment(
        _ value: String,
        isFirstWord: Bool,
        smallWords: Set<String>,
        acronymOverrides: [String: String]
    ) -> String {
        let characters = Array(value)
        guard let start = characters.firstIndex(where: { character in
            character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }),
              let end = characters.lastIndex(where: { character in
                  character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
              }) else {
            return value
        }

        let prefix = String(characters[..<start])
        let core = String(characters[start...end])
        let suffix = end + 1 < characters.count ? String(characters[(end + 1)...]) : ""
        let acronymKey = core.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9+]+"#, with: "", options: .regularExpression)
        if let override = acronymOverrides[acronymKey] {
            return prefix + override + suffix
        }

        let lowerCore = core.lowercased()
        if !isFirstWord, smallWords.contains(lowerCore) {
            return prefix + lowerCore + suffix
        }

        let hasLetters = core.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        let isAllUppercase = hasLetters && core == core.uppercased() && core != core.lowercased()
        let hasInternalUppercase = core.dropFirst().unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        if isAllUppercase || hasInternalUppercase {
            return value
        }

        guard let first = core.first else { return value }
        return prefix + String(first).uppercased() + String(core.dropFirst()).lowercased() + suffix
    }

    private static func navigationLabel(from text: String?, fallbackHref: String) -> (text: String, source: EPUBNavigationLabelSource) {
        let labelSource: EPUBNavigationLabelSource
        let rawHeading: String
        if let heading = text.flatMap({ firstHTMLText(in: $0, elementPattern: #"h[1-6]"#) }) {
            rawHeading = heading
            labelSource = .heading
        } else if let title = text.flatMap({ firstHTMLText(in: $0, elementPattern: #"title"#) }) {
            rawHeading = title
            labelSource = .title
        } else {
            rawHeading = fallbackNavigationLabel(from: fallbackHref)
            labelSource = .fallback
        }
        let stripped = strippingHTMLTags(rawHeading)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            return (fallbackNavigationLabel(from: fallbackHref), .fallback)
        }
        return (stripped, labelSource)
    }

    private static func firstHTMLText(in text: String, elementPattern: String) -> String? {
        firstMatch(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?\#(elementPattern)\b[^>]*>([\s\S]*?)</(?:[A-Za-z0-9_]+:)?\#(elementPattern)>"#
        )
    }

    private static func strippingHTMLTags(_ value: String) -> String {
        xmlUnescapedText(value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        ))
    }

    private static func fallbackNavigationLabel(from href: String) -> String {
        let path = xmlUnescapedText(href)
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let spaced = fileName
            .replacingOccurrences(of: #"[_\-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = spaced.first else { return "Chapter" }
        return first.uppercased() + spaced.dropFirst()
    }

    private static func hrefFragment(from href: String) -> String {
        let unescaped = xmlUnescapedText(href)
        guard let fragmentStart = unescaped.firstIndex(of: "#") else { return "" }
        return String(unescaped[fragmentStart...])
    }

    private static func hrefFragmentIdentifier(from href: String) -> String {
        let fragment = hrefFragment(from: href)
        guard fragment.hasPrefix("#") else { return "" }
        let raw = String(fragment.dropFirst())
        return (raw.removingPercentEncoding ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func opfRelativeHref(from opfPath: String, to entryPath: String) -> String {
        relativeEPUBHref(from: opfPath, to: entryPath)
    }

    private static func semanticHeadingReplacement(
        in text: String,
        fragment: String,
        label: String,
        level: Int
    ) -> (range: Range<String.Index>, replacement: String)? {
        guard semanticHeadingLabelIsUseful(label) else { return nil }
        let headingTagName = "h\(clampedSemanticHeadingLevel(level))"
        let blocks = (xmlElementBlocks(named: "p", in: text) + xmlElementBlocks(named: "div", in: text))
            .sorted { $0.range.location < $1.range.location }
        for block in blocks {
            guard attributeValue("id", in: attributes(in: block.openingTag)) == fragment else { continue }
            let body = block.body
            guard body.count <= 1_200 else { continue }
            guard !htmlContainsBlockStructure(body) else { continue }

            let visibleText = strippingHTMLTags(body)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard metadataComparisonKey(visibleText) == metadataComparisonKey(label) else {
                continue
            }

            guard let elementRange = Range(block.range, in: text) else { continue }
            let tagName = block.tagName.lowercased()
            let element = block.fullText
            let escapedTagName = NSRegularExpression.escapedPattern(for: tagName)
            let replacement = element
                .replacingOccurrences(
                    of: #"<\#(escapedTagName)\b"#,
                    with: "<\(headingTagName)",
                    options: [.regularExpression, .caseInsensitive],
                    range: nil
                )
                .replacingOccurrences(
                    of: #"</\#(escapedTagName)>"#,
                    with: "</\(headingTagName)>",
                    options: [.regularExpression, .caseInsensitive],
                    range: nil
                )
            guard replacement != element else { continue }
            return (elementRange, replacement)
        }

        return nil
    }

    private static func semanticHeadingReplacementAtFirstVisibleBlock(
        in text: String,
        label: String,
        level: Int
    ) -> (range: Range<String.Index>, replacement: String)? {
        guard semanticHeadingLabelIsUseful(label) else { return nil }
        let headingTagName = "h\(clampedSemanticHeadingLevel(level))"
        let blocks = (xmlElementBlocks(named: "p", in: text) + xmlElementBlocks(named: "div", in: text))
            .sorted { $0.range.location < $1.range.location }
        for block in blocks {
            let body = block.body
            guard body.count <= 1_200 else { continue }
            guard !htmlContainsBlockStructure(body) else { continue }

            let visibleText = strippingHTMLTags(body)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visibleText.isEmpty else { continue }
            guard metadataComparisonKey(visibleText) == metadataComparisonKey(label) else {
                return nil
            }

            guard let elementRange = Range(block.range, in: text) else { continue }
            let tagName = block.tagName.lowercased()
            let element = block.fullText
            let escapedTagName = NSRegularExpression.escapedPattern(for: tagName)
            let replacement = element
                .replacingOccurrences(
                    of: #"<\#(escapedTagName)\b"#,
                    with: "<\(headingTagName)",
                    options: [.regularExpression, .caseInsensitive],
                    range: nil
                )
                .replacingOccurrences(
                    of: #"</\#(escapedTagName)>"#,
                    with: "</\(headingTagName)>",
                    options: [.regularExpression, .caseInsensitive],
                    range: nil
                )
            guard replacement != element else { continue }
            return (elementRange, replacement)
        }

        return nil
    }

    private static func htmlContainsBlockStructure(_ text: String) -> Bool {
        text.range(
            of: #"<\s*(h[1-6]|p|div|section|article|table|ul|ol|figure|blockquote)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func navigationDocumentHasTOC(_ text: String) -> Bool {
        matches(in: text, pattern: #"<(?:[A-Za-z0-9_]+:)?nav\b[^>]*>"#).contains { tag in
            let attrs = attributes(in: tag)
            return attrs.contains { key, value in
                (key.caseInsensitiveCompare("epub:type") == .orderedSame
                    || key.caseInsensitiveCompare("type") == .orderedSame)
                    && propertyParts(value).contains { $0.caseInsensitiveCompare("toc") == .orderedSame }
            }
        }
    }

    private static func joinedEPUBPath(baseEntryPath: String, href: String) -> String {
        let cleanHref = cleanEPUBResourcePath(href)
        let base = baseEntryPath.replacingOccurrences(of: "\\", with: "/")
        let baseDirectory = base.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")
        let combined = baseDirectory.isEmpty ? cleanHref : "\(baseDirectory)/\(cleanHref)"
        return normalizingRelativePath(combined)
    }

    private static func cleanEPUBResourcePath(_ value: String) -> String {
        let unescaped = xmlUnescapedText(value)
        let withoutFragment = unescaped.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? unescaped
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutFragment
        let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
        var path = decoded.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") {
            path.removeFirst()
        }
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }

    private static func normalizingRelativePath(_ path: String) -> String {
        var components: [String] = []
        for component in path.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            switch component {
            case ".", "":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }

    fileprivate static func runRepair(
        _ item: SableLibraryAppleBooksCompatibilityRepairWorkItem
    ) async -> SableLibraryAppleBooksCompatibilityRepairTaskResult {
        guard !Task.isCancelled else { return .cancelled(item.path) }
        do {
            let outcome = try await repairInPlace(
                sourceURL: item.sourceURL,
                optimizePageImageEPUBs: item.optimizePageImageEPUBs,
                importMetadata: item.importMetadata,
                trustedCoverURLString: item.trustedCoverURLString,
                localCoverCandidates: item.localCoverCandidates,
                repairScopes: item.repairScopes,
                fileManager: FileManager()
            )
            switch outcome {
            case .applied:
                return .applied(item.path)
            case .skipped(let reason):
                return .skipped(item.path, reason)
            }
        } catch is CancellationError {
            return .cancelled(item.path)
        } catch {
            return .failed(item.path, error.localizedDescription)
        }
    }

    fileprivate static func repairInPlace(
        sourceURL: URL,
        optimizePageImageEPUBs: Bool = false,
        importMetadata: SableLibraryEPUBImportMetadata? = nil,
        trustedCoverURLString: String? = nil,
        localCoverCandidates: [SableLibraryEPUBImportCoverCandidate] = [],
        repairScopes: Set<SableLibraryEPUBRepairScope> = SableLibraryEPUBRepairScope.all,
        fileManager: FileManager
    ) async throws -> SableLibraryAppleBooksCompatibilityRepairOutcome {
        try Task.checkCancellation()
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return .skipped("The source EPUB no longer exists.")
        }
        guard !isDirectory.boolValue else {
            return .skipped("Expanded EPUB packages use the separate EPUB package repair.")
        }

        let sourceArchive = try archiveSnapshot(for: sourceURL)
        let protection = try protectionAnalysis(in: sourceArchive)
        if protection.isProtected {
            return .skipped(protection.reason ?? "EPUB contains encrypted content resources.")
        }

        let token = UUID().uuidString
        let workingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SableAppleBooksRepair-\(token)", isDirectory: true)
        let unpackedURL = workingRoot.appendingPathComponent("unpacked", isDirectory: true)
        let tempOutputURL = workingRoot.appendingPathComponent("repaired.epub")

        try fileManager.createDirectory(at: unpackedURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingRoot) }

        try runProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", sourceURL.path(percentEncoded: false), "-d", unpackedURL.path(percentEncoded: false)],
            currentDirectory: nil
        )
        try Task.checkCancellation()
        try validateUnpackedTree(root: unpackedURL, fileManager: fileManager)

        let effectiveScopes = repairScopes.isEmpty ? SableLibraryEPUBRepairScope.all : repairScopes
        let shouldRepairMetadata = effectiveScopes.contains(.metadata)
        let shouldRepairTags = effectiveScopes.contains(.tags)
        let shouldRepairReaderImport = effectiveScopes.contains(.readerImport)
        let shouldRepairCover = effectiveScopes.contains(.cover) || shouldRepairReaderImport
        let shouldRepairNavigation = effectiveScopes.contains(.navigation)
        let shouldRepairStructure = effectiveScopes.contains(.structure)
        let shouldRepairCompatibility = effectiveScopes.contains(.compatibility)
        let shouldRemoveAppleMetadata = shouldRepairCompatibility || shouldRepairReaderImport
        let shouldRepairPackage = effectiveScopes.contains(.package) || shouldRepairCompatibility
        let shouldRepairContent = effectiveScopes.contains(.content)
        let shouldRepairDiagnostics = effectiveScopes.contains(.diagnostics)

        if shouldRemoveAppleMetadata {
            try removeAppleMetadataFiles(in: unpackedURL, fileManager: fileManager)
        }

        let containerURL = unpackedURL.appendingPathComponent(containerEntry)
        guard fileManager.fileExists(atPath: containerURL.path(percentEncoded: false)) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.missingContainer
        }
        let container = try String(contentsOf: containerURL, encoding: .utf8)
        guard let opfPath = firstMatch(in: container, pattern: #"full-path\s*=\s*["']([^"']+)["']"#) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.missingOPF
        }

        let opfURL = try safeUnpackedURL(for: opfPath, in: unpackedURL)
        guard fileManager.fileExists(atPath: opfURL.path(percentEncoded: false)) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.missingUnpackedOPF(opfPath)
        }

        var opfText = try String(contentsOf: opfURL, encoding: .utf8)
        let freshID = "urn:uuid:\(UUID().uuidString)"
        let shouldRefreshPackageIdentifier = shouldRepairCompatibility
            || shouldRepairMetadata
            || shouldRepairTags
            || shouldRepairCover
            || shouldRepairPackage
            || shouldRepairNavigation
            || shouldRepairStructure
        if shouldRefreshPackageIdentifier {
            opfText = addFreshPackageIdentifier(to: opfText, freshID: freshID)
        }
        if shouldRepairPackage {
            let existingEntries = Set(try unpackedEntryNames(in: unpackedURL, fileManager: fileManager)
                .map(normalizedEPUBResourcePath))
            let cleanedOPF = removingMissingManifestHelperReferences(
                in: opfText,
                opfPath: opfPath,
                existingEntries: existingEntries
            )
            if cleanedOPF != opfText {
                opfText = replacingDCTermsModified(in: cleanedOPF, dateText: epubModifiedDateText(Date()))
            }

            var manifestOPF = removingInvalidManifestProperties(in: opfText, opfPath: opfPath)
            manifestOPF = uniquingDuplicateManifestIDs(in: manifestOPF)
            manifestOPF = removingBrokenGuideReferences(
                in: manifestOPF,
                opfPath: opfPath,
                existingEntries: existingEntries
            )
            manifestOPF = removingLegacySpinePageMapAttributes(in: manifestOPF)
            manifestOPF = removingObsoleteToursElements(in: manifestOPF)
            manifestOPF = removingDeadSpineItemrefs(
                in: manifestOPF,
                manifestItems: epubManifestItems(in: manifestOPF, opfPath: opfPath)
            )
            manifestOPF = normalizingFontManifestMediaTypes(in: manifestOPF, opfPath: opfPath)
            manifestOPF = try removingFalseScriptedManifestProperties(
                in: manifestOPF,
                opfPath: opfPath,
                unpackedURL: unpackedURL,
                fileManager: fileManager
            )
            manifestOPF = try addingMissingManifestResourceDeclarations(
                in: manifestOPF,
                opfPath: opfPath,
                unpackedURL: unpackedURL,
                existingEntries: existingEntries,
                fileManager: fileManager
            )
            let normalizedManifestOPF = try declaringRequiredManifestProperties(
                in: manifestOPF,
                opfPath: opfPath,
                unpackedURL: unpackedURL,
                fileManager: fileManager
            )
            if normalizedManifestOPF != opfText {
                opfText = replacingDCTermsModified(in: normalizedManifestOPF, dateText: epubModifiedDateText(Date()))
            }
        }

        if shouldRepairCompatibility {
            if packageNeedsEPUB3VersionForStandardsProfile(opfText) {
                opfText = replacingDCTermsModified(
                    in: settingEPUB3PackageVersionIfNeeded(in: opfText),
                    dateText: epubModifiedDateText(Date())
                )
            }

            let normalizedMetadataOPF = removingInvalidTypedRefinementMeta(
                in: removingOrphanedRefinementMeta(
                    in: normalizingNonNamespacedMetadataMetaTags(
                        in: normalizingLegacyDublinCoreAttributes(in: opfText)
                    )
                )
            )
            if normalizedMetadataOPF != opfText {
                opfText = replacingDCTermsModified(in: normalizedMetadataOPF, dateText: epubModifiedDateText(Date()))
            }
        }

        if shouldRepairContent {
            let repairedHeaders = try repairEPUBContentDocumentHeaders(
                in: unpackedURL,
                opfPath: opfPath,
                opfText: opfText,
                fileManager: fileManager
            )
            let repairedStylesheets = try repairEPUBStylesheets(
                in: unpackedURL,
                opfPath: opfPath,
                opfText: opfText,
                fileManager: fileManager
            )
            let repairedLinkedResources = try repairLinkedResourceReferences(
                in: unpackedURL,
                opfPath: opfPath,
                opfText: opfText,
                fileManager: fileManager
            )
            let removedMissingScripts = try removeMissingLocalScriptReferences(
                in: unpackedURL,
                opfPath: opfPath,
                opfText: opfText,
                fileManager: fileManager
            )
            if removedMissingScripts {
                let normalizedScriptedOPF = try removingFalseScriptedManifestProperties(
                    in: opfText,
                    opfPath: opfPath,
                    unpackedURL: unpackedURL,
                    fileManager: fileManager
                )
                if normalizedScriptedOPF != opfText {
                    opfText = normalizedScriptedOPF
                }
            }
            if repairedHeaders || repairedStylesheets || repairedLinkedResources || removedMissingScripts {
                opfText = replacingDCTermsModified(in: opfText, dateText: epubModifiedDateText(Date()))
            }
        }
        if shouldRepairCover {
            let normalizedCoverManifestOPF = removingInvalidManifestProperties(in: opfText, opfPath: opfPath)
            if normalizedCoverManifestOPF != opfText {
                opfText = replacingDCTermsModified(in: normalizedCoverManifestOPF, dateText: epubModifiedDateText(Date()))
            }
            opfText = try await addingDownloadedCoverIfNeeded(
                to: opfText,
                opfPath: opfPath,
                opfURL: opfURL,
                unpackedURL: unpackedURL,
                coverURLString: trustedCoverURLString,
                localCoverCandidates: localCoverCandidates,
                fileManager: fileManager
            )
            opfText = addCoverMetadata(to: opfText)
        }
        if shouldRepairStructure,
           try repairEPUBStructure(
            in: unpackedURL,
            opfPath: opfPath,
            opfText: opfText,
            fileManager: fileManager
           ) {
            opfText = replacingDCTermsModified(in: opfText, dateText: epubModifiedDateText(Date()))
        }
        if shouldRepairNavigation {
            opfText = try repairEPUBNavigation(
                in: unpackedURL,
                opfPath: opfPath,
                opfText: opfText,
                fileManager: fileManager
            )
        }
        if let importMetadata, shouldRepairMetadata || shouldRepairTags {
            opfText = applyingImportMetadata(
                importMetadata,
                to: opfText,
                scopes: effectiveScopes
            )
        }
        if shouldRepairTags {
            let cleanedOPF = cleaningSubjectTagDisplayCasing(in: opfText)
            if cleanedOPF != opfText {
                opfText = replacingDCTermsModified(in: cleanedOPF, dateText: epubModifiedDateText(Date()))
            }
        }
        try opfText.write(to: opfURL, atomically: true, encoding: .utf8)

        if optimizePageImageEPUBs, shouldRepairDiagnostics {
            try optimizePageImages(
                in: unpackedURL,
                opfURL: opfURL,
                opfText: opfText,
                fileManager: fileManager
            )
        }

        if shouldRepairDiagnostics {
            try repairFixedLayoutPageBoxesIfNeeded(in: unpackedURL, fileManager: fileManager)
        }

        if shouldRepairCompatibility || shouldRepairPackage || shouldRepairMetadata || shouldRepairTags || shouldRepairCover || shouldRepairNavigation {
            try patchNCXFiles(
                in: unpackedURL,
                packageID: packageUniqueIdentifierValue(in: opfText),
                opfPath: opfPath,
                opfText: opfText,
                fileManager: fileManager
            )
        }

        try Task.checkCancellation()
        try? fileManager.removeItem(at: tempOutputURL)
        try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-X", "-q", "-0", tempOutputURL.path(percentEncoded: false), "mimetype"],
            currentDirectory: unpackedURL
        )
        try runProcess(
            executable: "/usr/bin/zip",
            arguments: [
                "-X", "-q", "-r",
                "-n", ".jpg:.jpeg:.png:.gif:.webp:.avif:.heic:.heif:.jxl:.mp3:.m4a:.aac:.ogg:.mp4:.m4v:.mov:.webm:.woff:.woff2:.ttf:.otf:.pdf",
                tempOutputURL.path(percentEncoded: false),
                ".",
                "-x", "mimetype"
            ],
            currentDirectory: unpackedURL
        )

        try Task.checkCancellation()
        try validate(epubURL: tempOutputURL)
        try Task.checkCancellation()

        let originalTemporaryURL = workingRoot.appendingPathComponent("original.epub")

        try fileManager.moveItem(at: sourceURL, to: originalTemporaryURL)
        do {
            try fileManager.moveItem(at: tempOutputURL, to: sourceURL)
        } catch {
            if fileManager.fileExists(atPath: originalTemporaryURL.path(percentEncoded: false)),
               !fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
                try? fileManager.moveItem(at: originalTemporaryURL, to: sourceURL)
            }
            throw error
        }

        return .applied(sourceURL)
    }

    struct FixedLayoutTextAnalysis {
        let isPageImageFixedLayout: Bool
        let hasPageBoxMismatch: Bool
    }

    static func hasFreshSableImportIdentifier(_ opfText: String) -> Bool {
        opfText.contains("sable-import-id")
    }

    static func importMetadataChangeReasons(
        _ metadata: SableLibraryEPUBImportMetadata,
        currentOPFText: String
    ) -> [String] {
        if importMetadataAlreadyMatches(metadata, currentOPFText: currentOPFText) {
            return []
        }

        let patched = applyingImportMetadata(metadata, to: currentOPFText)
        guard patched != currentOPFText else { return [] }

        var reasons = [
            hasFreshSableImportIdentifier(currentOPFText)
                ? "Sync changed ComicInfo metadata into EPUB import fields"
                : "Write ComicInfo metadata into EPUB import fields"
        ]
        if metadata.seriesTitle != nil || effectiveSeriesPosition(for: metadata) != nil {
            reasons.append("Write series and volume import metadata")
        }
        if !metadata.languages.isEmpty {
            reasons.append("Write language metadata")
        }
        if metadata.subtitle != nil || metadata.titleSort != nil {
            reasons.append("Write title sorting and subtitle metadata")
        }
        if !metadata.isbn13.isEmpty || !metadata.sourceIDs.isEmpty || !metadata.extraIdentifiers.isEmpty {
            reasons.append("Write ISBN/provider identifiers")
        }
        if !metadata.authors.isEmpty || !metadata.artists.isEmpty || !metadata.contributors.isEmpty || !metadata.publishers.isEmpty {
            reasons.append("Write creator, contributor, and publisher metadata")
        }
        if !metadata.subjects.isEmpty || metadata.description != nil {
            reasons.append("Write description and subject tags")
        }
        return reasons
    }

    private static func importMetadataAlreadyMatches(
        _ metadata: SableLibraryEPUBImportMetadata,
        currentOPFText: String
    ) -> Bool {
        if !metadataValuesMatch(
            currentDublinCoreValues(in: currentOPFText, localName: "title"),
            [metadata.title]
        ) {
            return false
        }
        if !titleRefinementMetadataMatches(metadata, currentOPFText: currentOPFText) {
            return false
        }
        if !subtitleMetadataMatches(metadata, currentOPFText: currentOPFText) {
            return false
        }

        let creatorCreditNames = uniqueImportMetadataStrings(creatorCredits(for: metadata).map(\.name))
        if !creatorCreditNames.isEmpty,
           !metadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "creator"), creatorCreditNames) {
            return false
        }
        if !creditMetadataMatches(
            expectedCredits: creatorCredits(for: metadata),
            currentOPFText: currentOPFText,
            localName: "creator"
        ) {
            return false
        }

        let contributorCreditNames = uniqueImportMetadataStrings(contributorCredits(for: metadata).map(\.name))
        if !contributorCreditNames.isEmpty,
           !metadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "contributor"), contributorCreditNames) {
            return false
        }
        if !creditMetadataMatches(
            expectedCredits: contributorCredits(for: metadata),
            currentOPFText: currentOPFText,
            localName: "contributor"
        ) {
            return false
        }

        if !metadata.publishers.isEmpty,
           !metadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "publisher"), metadata.publishers) {
            return false
        }

        if let language = normalizedLanguage(metadata.languages.first),
           !metadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "language"), [language]) {
            return false
        }

        if let description = metadata.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty,
           !metadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "description"), [description]) {
            return false
        }

        let subjects = Array(metadata.subjects.prefix(30))
        if !subjects.isEmpty,
           !subjectMetadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "subject"), subjects) {
            return false
        }

        if let date = importDateText(releaseDate: metadata.releaseDate, releaseYear: metadata.releaseYear),
           !metadataValuesMatch(currentDublinCoreValues(in: currentOPFText, localName: "date"), [date]) {
            return false
        }

        if let pageCount = metadata.pageCount,
           pageCount > 0,
           !metadataValuesMatch(propertyMetaValues(in: currentOPFText, property: "schema:numberOfPages"), ["\(pageCount)"]) {
            return false
        }

        let expectedIdentifiers = importIdentifiers(from: metadata)
        if !expectedIdentifiers.isEmpty,
           currentSableMetadataIdentifiers(in: currentOPFText) != Set(expectedIdentifiers.map { "\($0.0)|\($0.1)" }) {
            return false
        }

        if let seriesTitle = metadata.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !seriesTitle.isEmpty,
           metadataComparisonKey(namedMetaContent(in: currentOPFText, name: "calibre:series") ?? "")
            != metadataComparisonKey(seriesTitle) {
            return false
        }

        if let seriesPosition = effectiveSeriesPosition(for: metadata),
           metadataComparisonKey(namedMetaContent(in: currentOPFText, name: "calibre:series_index") ?? "")
            != metadataComparisonKey("\(seriesPosition)") {
            return false
        }

        if !epub3SeriesCollectionMetadataMatches(metadata, currentOPFText: currentOPFText) {
            return false
        }

        if !sableISBNIdentifierTypesMatch(metadata, currentOPFText: currentOPFText) {
            return false
        }

        return true
    }

    static func fixedLayoutTextAnalysis(
        entries: [String],
        in epubURL: URL,
        opfText: String
    ) throws -> FixedLayoutTextAnalysis {
        let archive = try archiveSnapshot(for: epubURL)
        return try fixedLayoutTextAnalysis(entries: entries, in: archive, opfText: opfText)
    }

    static func fixedLayoutTextAnalysis(
        entries: [String],
        in archive: EPUBArchiveSnapshot,
        opfText: String
    ) throws -> FixedLayoutTextAnalysis {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
        let textExtensions: Set<String> = ["xhtml", "html", "htm"]

        let imageCount = entries.filter {
            imageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }.count

        let textPageEntries = entries.filter {
            textExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }

        let cssEntries = entries.filter {
            URL(fileURLWithPath: $0).pathExtension.lowercased() == "css"
        }

        let fixedLayout = opfText.localizedCaseInsensitiveContains("pre-paginated")
        let isPageImageFixedLayout = fixedLayout && imageCount >= 40 && textPageEntries.count >= 20

        guard isPageImageFixedLayout else {
            return FixedLayoutTextAnalysis(isPageImageFixedLayout: false, hasPageBoxMismatch: false)
        }

        var sampledText = opfText
        for entry in Array(cssEntries.prefix(20)) + Array(textPageEntries.prefix(40)) {
            if let entryText = try entryText(entry, in: archive) {
                sampledText += "\\n"
                sampledText += entryText
            }
        }

        let viewport = dominantDimensionPair(
            in: sampledText,
            widthPattern: "viewport[^>]*width\\\\s*=\\\\s*(\\\\d+)",
            heightPattern: "viewport[^>]*height\\\\s*=\\\\s*(\\\\d+)"
        )

        let pageBox = dimensionPair(
            in: sampledText,
            widthPattern: "div\\\\.page\\\\s*\\\\{[^}]*width\\\\s*:\\\\s*(\\\\d+)px",
            heightPattern: "div\\\\.page\\\\s*\\\\{[^}]*height\\\\s*:\\\\s*(\\\\d+)px"
        )

        let backgroundSize = dimensionPair(
            in: sampledText,
            widthPattern: "background-size\\\\s*:\\\\s*(\\\\d+)px\\\\s+\\\\d+px",
            heightPattern: "background-size\\\\s*:\\\\s*\\\\d+px\\\\s+(\\\\d+)px"
        )

        guard let viewport else {
            return FixedLayoutTextAnalysis(isPageImageFixedLayout: true, hasPageBoxMismatch: false)
        }

        var mismatch = false
        if let pageBox {
            mismatch = mismatch || pageBox.width != viewport.width || pageBox.height != viewport.height
        }
        if let backgroundSize {
            mismatch = mismatch || backgroundSize.width != viewport.width || backgroundSize.height != viewport.height
        }

        return FixedLayoutTextAnalysis(
            isPageImageFixedLayout: true,
            hasPageBoxMismatch: mismatch
        )
    }

    private static func dominantDimensionPair(
        in text: String,
        widthPattern: String,
        heightPattern: String
    ) -> (width: Int, height: Int)? {
        let widths = integerMatches(in: text, pattern: widthPattern)
        let heights = integerMatches(in: text, pattern: heightPattern)

        guard let width = mostCommonInteger(widths),
              let height = mostCommonInteger(heights) else {
            return nil
        }

        return (width, height)
    }

    private static func dimensionPair(
        in text: String,
        widthPattern: String,
        heightPattern: String
    ) -> (width: Int, height: Int)? {
        guard let width = integerMatches(in: text, pattern: widthPattern).first,
              let height = integerMatches(in: text, pattern: heightPattern).first else {
            return nil
        }

        return (width, height)
    }

    private static func integerMatches(in text: String, pattern: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return Int(text[range])
        }
    }

    private static func mostCommonInteger(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    static func isPageImageOptimizationCandidate(entries: [String], opfText: String) -> Bool {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png"]
        let textExtensions: Set<String> = ["xhtml", "html", "htm"]

        let imageEntries = entries.filter {
            imageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }
        let textCount = entries.filter {
            textExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }.count

        let fixedLayout = opfText.range(
            of: #"rendition:layout["'>\s]*pre-paginated|rendition:layout[^>]+pre-paginated"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        // Conservative gate:
        // mixed-layout EPUBs can crop if optimized blindly.
        // Only offer lossy optimization for simple page-image manga-like EPUBs.
        return fixedLayout && imageEntries.count >= 40 && textCount >= 40
    }

    private struct OptimizedPageImage {
        let fileName: String
        let oldWidth: Int
        let oldHeight: Int
        let newWidth: Int
        let newHeight: Int
    }

    private static let pageImageMaxLongEdge = 1800
    private static let pageImageMinimumLongEdge = 1600
    private static let pageImageMinimumShortEdge = 1000
    private static let pageImageMinimumSourceBytes = 350_000
    private static let pageImageMinimumSavingsRatio = 0.08
    private static let pageImageJPEGQualityCandidates: [CGFloat] = [0.88, 0.84, 0.80, 0.76]

    private static func optimizePageImages(
        in unpackedURL: URL,
        opfURL: URL,
        opfText: String,
        fileManager: FileManager
    ) throws {
        #if canImport(AppKit)
        let files = allFiles(in: unpackedURL, fileManager: fileManager)
        let entries = files.compactMap { relativeUnpackedPath(for: $0, root: unpackedURL) }
        guard isPageImageOptimizationCandidate(entries: entries, opfText: opfText) else { return }

        let coverImagePaths = coverImageFilePaths(
            in: opfText,
            opfURL: opfURL,
            unpackedURL: unpackedURL
        )
        let imageURLs = files
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .filter { !coverImagePaths.contains(normalizedFilePath($0)) }
            .filter { !isCoverLikeImagePath($0, root: unpackedURL) }

        var optimized: [OptimizedPageImage] = []

        for imageURL in imageURLs {
            guard let optimizedImage = try optimizeJPEGPageImageIfNeeded(imageURL) else {
                continue
            }
            optimized.append(optimizedImage)
        }

        guard !optimized.isEmpty else { return }

        try updateFixedLayoutDimensions(
            in: unpackedURL,
            optimized: optimized,
            fileManager: fileManager
        )
        #endif
    }

    #if canImport(AppKit)
    private static func optimizeJPEGPageImageIfNeeded(_ imageURL: URL) throws -> OptimizedPageImage? {
        guard let sourceData = try? Data(contentsOf: imageURL),
              let source = NSBitmapImageRep(data: sourceData) else {
            return nil
        }
        guard sourceData.count >= pageImageMinimumSourceBytes else { return nil }

        let oldWidth = source.pixelsWide
        let oldHeight = source.pixelsHigh
        let oldLong = max(oldWidth, oldHeight)

        guard oldLong > pageImageMaxLongEdge else { return nil }

        let scale = CGFloat(pageImageMaxLongEdge) / CGFloat(oldLong)
        let newWidth = Int((CGFloat(oldWidth) * scale).rounded())
        let newHeight = Int((CGFloat(oldHeight) * scale).rounded())
        let newLong = max(newWidth, newHeight)
        let newShort = min(newWidth, newHeight)

        guard newLong >= pageImageMinimumLongEdge,
              newShort >= pageImageMinimumShortEdge else {
            return nil
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: newWidth,
            pixelsHigh: newHeight,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true

        let image = NSImage(size: NSSize(width: oldWidth, height: oldHeight))
        image.addRepresentation(source)
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: oldWidth, height: oldHeight),
            operation: .copy,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()

        let maximumOutputSize = Int(Double(sourceData.count) * (1.0 - pageImageMinimumSavingsRatio))
        var output: Data?
        for quality in pageImageJPEGQualityCandidates {
            guard let candidate = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            ) else {
                continue
            }
            if candidate.count <= maximumOutputSize {
                output = candidate
                break
            }
        }

        // Failsafe: never replace if the quality-preserving pass cannot make a meaningful size win.
        guard let output else { return nil }

        try output.write(to: imageURL, options: .atomic)

        return OptimizedPageImage(
            fileName: imageURL.lastPathComponent,
            oldWidth: oldWidth,
            oldHeight: oldHeight,
            newWidth: newWidth,
            newHeight: newHeight
        )
    }
    #endif

    private static func relativeUnpackedPath(for url: URL, root: URL) -> String? {
        let rootPath = normalizedFilePath(root.resolvingSymlinksInPath())
        let path = normalizedFilePath(url.resolvingSymlinksInPath())
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func isCoverLikeImagePath(_ url: URL, root: URL) -> Bool {
        guard let relativePath = relativeUnpackedPath(for: url, root: root) else { return false }
        return isCoverLikeImagePathForOptimization(relativePath)
    }

    static func isCoverLikeImagePathForOptimization(_ relativePath: String) -> Bool {
        let normalized = normalizingRelativePath(relativePath)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        let components = normalized.split(separator: "/").map(String.init)
        if components.contains("_covers") || components.contains("covers") {
            return true
        }

        guard let fileName = components.last else { return false }
        let stem = URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
        let compactStem = stem.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "",
            options: .regularExpression
        )

        if ["cover", "frontcover", "backcover", "folder", "poster"].contains(compactStem) {
            return true
        }
        return compactStem.hasPrefix("cover") || compactStem.hasSuffix("cover")
    }

    private static func coverImageFilePaths(
        in opfText: String,
        opfURL: URL,
        unpackedURL: URL
    ) -> Set<String> {
        let itemTags = matches(in: opfText, pattern: #"<(?:[A-Za-z0-9_]+:)?item\b[^>]*>"#)
        let metaTags = matches(
            in: opfText,
            pattern: #"<(?:[A-Za-z0-9_]+:)?meta\b(?=[^>]*\bname=["']cover["'])[^>]*>"#
        )
        let coverMetaIDs = Set(metaTags.compactMap { attributes(in: $0)["content"] })
        var paths = Set<String>()

        for tag in itemTags {
            let attrs = attributes(in: tag)
            guard let href = attrs["href"],
                  isImageManifestItem(attrs) else {
                continue
            }

            let id = attrs["id"] ?? ""
            let properties = attrs["properties"] ?? ""
            let propertyParts = properties
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).lowercased() }
            let cleanHref = hrefBeforeFragmentOrQuery(href)
            let looksLikeCover = coverMetaIDs.contains(id)
                || propertyParts.contains("cover-image")
                || id.localizedCaseInsensitiveContains("cover")
                || cleanHref.localizedCaseInsensitiveContains("cover")
            guard looksLikeCover else { continue }

            let decodedHref = cleanHref.removingPercentEncoding ?? cleanHref
            let fileURL = opfURL
                .deletingLastPathComponent()
                .appendingPathComponent(decodedHref)
                .standardizedFileURL
            guard normalizedFilePath(fileURL).hasPrefix(normalizedFilePath(unpackedURL) + "/") else {
                continue
            }
            paths.insert(normalizedFilePath(fileURL))
        }

        return paths
    }

    private static func isImageManifestItem(_ attrs: [String: String]) -> Bool {
        let href = (attrs["href"] ?? "").lowercased()
        let mediaType = (attrs["media-type"] ?? "").lowercased()
        return mediaType.hasPrefix("image/")
            || href.hasSuffix(".jpg")
            || href.hasSuffix(".jpeg")
            || href.hasSuffix(".png")
            || href.hasSuffix(".webp")
            || href.hasSuffix(".gif")
            || href.hasSuffix(".svg")
    }

    private static func hrefBeforeFragmentOrQuery(_ href: String) -> String {
        let withoutFragment = href
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        return withoutFragment
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? withoutFragment
    }

    private static func normalizedFilePath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private static func updateFixedLayoutDimensions(
        in unpackedURL: URL,
        optimized: [OptimizedPageImage],
        fileManager: FileManager
    ) throws {
        let textExtensions: Set<String> = ["xhtml", "html", "htm", "css"]
        let textURLs = allFiles(in: unpackedURL, fileManager: fileManager)
            .filter { textExtensions.contains($0.pathExtension.lowercased()) }

        for textURL in textURLs {
            guard var text = try? String(contentsOf: textURL, encoding: .utf8) else { continue }
            let original = text

            for image in optimized {
                let mentionsImage = text.contains(image.fileName)
                if mentionsImage || optimized.count == 1 {
                    text = updateDimensionText(text, old: image.oldWidth, new: image.newWidth)
                    text = updateDimensionText(text, old: image.oldHeight, new: image.newHeight)
                    text = updateViewportText(text, image: image)
                }
            }

            if text != original {
                try text.write(to: textURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func updateDimensionText(_ text: String, old: Int, new: Int) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?i)(width\s*:\s*)\#(old)(px\s*[;!])"#,
            with: "$1\(new)$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(height\s*:\s*)\#(old)(px\s*[;!])"#,
            with: "$1\(new)$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(background-size\s*:\s*)\#(old)(px)"#,
            with: "$1\(new)$2",
            options: .regularExpression
        )
        return result
    }

    private static func updateViewportText(_ text: String, image: OptimizedPageImage) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?i)(viewport[^>]*content=["'][^"']*width\s*=\s*)\#(image.oldWidth)([^"']*["'])"#,
            with: "$1\(image.newWidth)$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(viewport[^>]*content=["'][^"']*height\s*=\s*)\#(image.oldHeight)([^"']*["'])"#,
            with: "$1\(image.newHeight)$2",
            options: .regularExpression
        )
        return result
    }

    private static func allFiles(in root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    static func hasFixedLayoutPageBoxMismatch(entries: [String], in epubURL: URL) throws -> Bool {
        let archive = try archiveSnapshot(for: epubURL)
        return try hasFixedLayoutPageBoxMismatch(entries: entries, in: archive)
    }

    static func hasFixedLayoutPageBoxMismatch(entries: [String], in archive: EPUBArchiveSnapshot) throws -> Bool {
        let jpegEntries = entries
            .filter { ["jpg", "jpeg"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .prefix(160)
        let textEntries = entries
            .filter { ["css", "xhtml", "html", "htm"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .prefix(80)

        var sizes: [(width: Int, height: Int)] = []
        for entry in jpegEntries {
            guard let data = try entryData(entry, in: archive),
                  let size = fixedLayoutJPEGDimensions(data) else {
                continue
            }
            sizes.append(size)
        }

        guard let dominant = dominantPageSize(from: sizes) else {
            return false
        }

        var text = ""
        for entry in textEntries {
            if let entryText = try entryText(entry, in: archive) {
                text += "\n"
                text += entryText
            }
        }

        guard !text.isEmpty else { return false }

        let expectedWidth = dominant.width
        let expectedHeight = dominant.height

        if let cssWidth = firstIntegerMatch(
            in: text,
            pattern: #"(?i)div\.page\s*\{[^}]*?\bwidth\s*:\s*(\d+)px"#
        ), cssWidth != expectedWidth {
            return true
        }

        if let cssHeight = firstIntegerMatch(
            in: text,
            pattern: #"(?i)div\.page\s*\{[^}]*?\bheight\s*:\s*(\d+)px"#
        ), cssHeight != expectedHeight {
            return true
        }

        if let bgWidth = firstIntegerMatch(
            in: text,
            pattern: #"(?i)background-size\s*:\s*(\d+)px\s+\d+px"#
        ), bgWidth != expectedWidth {
            return true
        }

        if let bgHeight = firstIntegerMatch(
            in: text,
            pattern: #"(?i)background-size\s*:\s*\d+px\s+(\d+)px"#
        ), bgHeight != expectedHeight {
            return true
        }

        return false
    }

    private static func repairFixedLayoutPageBoxesIfNeeded(in unpackedURL: URL, fileManager: FileManager) throws {
        let jpegURLs = allFiles(in: unpackedURL, fileManager: fileManager)
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }

        var sizes: [(width: Int, height: Int)] = []
        for url in jpegURLs.prefix(300) {
            guard let size = fixedLayoutJPEGDimensionsInFile(url) else {
                continue
            }
            sizes.append(size)
        }

        guard let dominant = dominantPageSize(from: sizes) else {
            return
        }

        let textExtensions: Set<String> = ["css", "xhtml", "html", "htm"]
        let textURLs = allFiles(in: unpackedURL, fileManager: fileManager)
            .filter { textExtensions.contains($0.pathExtension.lowercased()) }

        for textURL in textURLs {
            guard var text = try? String(contentsOf: textURL, encoding: .utf8) else { continue }
            let original = text

            text = forceFixedLayoutDimensions(text, width: dominant.width, height: dominant.height)

            if text != original {
                try text.write(to: textURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func forceFixedLayoutDimensions(_ text: String, width: Int, height: Int) -> String {
        var result = text

        result = result.replacingOccurrences(
            of: #"(?i)(div\.page\s*\{[^}]*?\bwidth\s*:\s*)\d+(px\s*;)"#,
            with: "$1\(width)$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(div\.page\s*\{[^}]*?\bheight\s*:\s*)\d+(px\s*;)"#,
            with: "$1\(height)$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(background-size\s*:\s*)\d+px\s+\d+px"#,
            with: "$1\(width)px \(height)px",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(viewport[^>]*content=["'][^"']*width\s*=\s*)\d+([^"']*["'])"#,
            with: "$1\(width)$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(viewport[^>]*content=["'][^"']*height\s*=\s*)\d+([^"']*["'])"#,
            with: "$1\(height)$2",
            options: .regularExpression
        )

        return result
    }

    private static func dominantPageSize(from sizes: [(width: Int, height: Int)]) -> (width: Int, height: Int)? {
        guard !sizes.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        var examples: [String: (width: Int, height: Int)] = [:]

        for size in sizes {
            let key = "\(size.width)x\(size.height)"
            counts[key, default: 0] += 1
            examples[key] = size
        }

        guard let best = counts.max(by: { $0.value < $1.value }),
              best.value >= max(20, Int(Double(sizes.count) * 0.75)) else {
            return nil
        }

        return examples[best.key]
    }

    private static func fixedLayoutJPEGDimensionsInFile(_ url: URL) -> (width: Int, height: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 512 * 1024)
        return fixedLayoutJPEGDimensions(data)
    }

    private static func fixedLayoutJPEGDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count > 10,
              data[0] == 0xFF,
              data[1] == 0xD8 else {
            return nil
        }

        var index = 2
        let markers: Set<UInt8> = [
            0xC0, 0xC1, 0xC2, 0xC3,
            0xC5, 0xC6, 0xC7,
            0xC9, 0xCA, 0xCB,
            0xCD, 0xCE, 0xCF
        ]

        while index + 9 < data.count {
            if data[index] != 0xFF {
                index += 1
                continue
            }

            let marker = data[index + 1]
            index += 2

            if marker == 0xD8 || marker == 0xD9 {
                continue
            }

            guard index + 2 <= data.count else { return nil }
            let length = Int(data[index]) << 8 | Int(data[index + 1])
            guard length >= 2, index + length <= data.count else { return nil }

            if markers.contains(marker), index + 7 <= data.count {
                let height = Int(data[index + 3]) << 8 | Int(data[index + 4])
                let width = Int(data[index + 5]) << 8 | Int(data[index + 6])
                return (width, height)
            }

            index += length
        }

        return nil
    }

    private static func coverImageDimensions(_ data: Data) -> (width: Int, height: Int)? {
        if let size = fixedLayoutJPEGDimensions(data) {
            return size
        }
        #if canImport(AppKit)
        guard let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            return nil
        }
        return (bitmap.pixelsWide, bitmap.pixelsHigh)
        #else
        return nil
        #endif
    }

    static func coverImageIsUsableForEPUBCover(_ data: Data) -> Bool {
        guard let size = coverImageDimensions(data) else { return false }
        return SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
            width: size.width,
            height: size.height
        )
            && coverDimensionsHaveBookShape(
                width: size.width,
                height: size.height
            )
    }

    static func shouldUseCoverReplacement(
        existingData: Data?,
        candidateData: Data,
        expectedVolume: Int? = nil
    ) -> Bool {
        if existingData == candidateData {
            return false
        }
        guard coverImageIsUsableForEPUBCover(candidateData),
              let candidateSize = coverImageDimensions(candidateData) else {
            return false
        }
        return shouldUseCoverReplacement(
            existingData: existingData,
            candidateWidth: candidateSize.width,
            candidateHeight: candidateSize.height,
            expectedVolume: expectedVolume
        )
    }

    private static func shouldUseCoverReplacement(
        existingData: Data?,
        candidateWidth: Int,
        candidateHeight: Int,
        expectedVolume: Int? = nil
    ) -> Bool {
        guard SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
            width: candidateWidth,
            height: candidateHeight
        ),
              coverDimensionsHaveBookShape(
                width: candidateWidth,
                height: candidateHeight
              ) else {
            return false
        }
        guard let existingData,
              let existingSize = coverImageDimensions(existingData) else {
            return true
        }

        if !coverImageIsUsableForEPUBCover(existingData) {
            return true
        }

        if existingCoverVolumeLooksMismatched(existingData, expectedVolume: expectedVolume) {
            return true
        }

        let candidatePixels = candidateWidth * candidateHeight
        let existingPixels = existingSize.width * existingSize.height
        guard candidatePixels > existingPixels else { return false }

        let candidateKeepsShape = candidateWidth >= Int(Double(existingSize.width) * 0.92)
            && candidateHeight >= Int(Double(existingSize.height) * 0.92)
        let enoughMorePixels = candidatePixels - existingPixels >= 250_000
        let meaningfullyLarger = Double(candidatePixels) >= Double(existingPixels) * 1.15
        return candidateKeepsShape && enoughMorePixels && meaningfullyLarger
    }

    private static func existingCoverVolumeLooksMismatched(
        _ data: Data,
        expectedVolume: Int?
    ) -> Bool {
        guard let expectedVolume, expectedVolume > 0 else { return false }
        let detected = detectedExplicitCoverVolumeNumbers(in: data)
        return !detected.isEmpty && !detected.contains(expectedVolume)
    }

    private static func detectedExplicitCoverVolumeNumbers(in data: Data) -> Set<Int> {
        #if canImport(Vision)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "ja-JP"]

        let handler = VNImageRequestHandler(data: data, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        return explicitCoverVolumeNumbers(in: text)
        #else
        return []
        #endif
    }

    static func explicitCoverVolumeNumbers(in text: String) -> Set<Int> {
        var values = Set(integerMatches(
            in: text,
            pattern: #"\b(?:vol(?:ume)?|book)\s*[\.:#-]?\s*(\d{1,3})\b"#
        ))
        values.formUnion(integerMatches(
            in: text,
            pattern: #"(?:第\s*)?(\d{1,3})\s*巻"#
        ))

        let wordNumbers: [(String, Int)] = [
            ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
            ("eleven", 11), ("twelve", 12), ("thirteen", 13), ("fourteen", 14),
            ("fifteen", 15), ("sixteen", 16), ("seventeen", 17), ("eighteen", 18),
            ("nineteen", 19), ("twenty", 20)
        ]
        for (word, number) in wordNumbers where text.range(
            of: #"\b(?:vol(?:ume)?|book)\s*[\.:#-]?\s*"# + word + #"\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            values.insert(number)
        }
        return values
    }

    static func coverDimensionsHaveBookShape(
        width: Int,
        height: Int
    ) -> Bool {
        SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
            width: width,
            height: height
        )
    }

    static func localCoverReplacementReason(
        opfText: String,
        opfPath: String,
        archive: EPUBArchiveSnapshot,
        candidates: [SableLibraryEPUBImportCoverCandidate],
        fallbackLanguages: [String]
    ) -> String? {
        var preferredLanguage: String?
        for value in currentDublinCoreValues(in: opfText, localName: "language") {
            if let language = coverLanguageCode(from: value) {
                preferredLanguage = language
                break
            }
        }
        if preferredLanguage == nil {
            for value in fallbackLanguages {
                if let language = coverLanguageCode(from: value) {
                    preferredLanguage = language
                    break
                }
            }
        }
        guard let candidate = selectedLocalCoverCandidate(
            in: candidates,
            preferredLanguage: preferredLanguage
        ),
              let coverItem = likelyCoverManifestItem(in: opfText, opfPath: opfPath) else {
            return nil
        }

        let existingData: Data
        do {
            guard let data = try entryData(coverItem.entryPath, in: archive) else {
                return nil
            }
            existingData = data
        } catch {
            return nil
        }
        guard let candidateImage = try? localCoverImageCandidate(from: candidate),
              existingData != candidateImage.data,
              coverImageIsUsableForEPUBCover(candidateImage.data) else {
            return nil
        }
        let languageName: String
        switch candidate.language.lowercased() {
        case "en":
            languageName = "English"
        case "jp", "ja":
            languageName = "Japanese"
        default:
            languageName = candidate.language.uppercased()
        }
        let sourceName = candidate.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateLabel = [
            languageName,
            sourceName.flatMap { $0.isEmpty ? nil : $0 }
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            + " cover"
        let candidateSize = coverImageDimensions(candidateImage.data)
        let existingSize = coverImageDimensions(existingData)
        let sizeEvidence: String
        if let candidateSize, let existingSize {
            sizeEvidence = "\(candidateLabel) is \(candidateSize.width) x \(candidateSize.height); the embedded cover is \(existingSize.width) x \(existingSize.height)."
        } else if let candidateSize {
            sizeEvidence = "\(candidateLabel) is \(candidateSize.width) x \(candidateSize.height)."
        } else {
            sizeEvidence = "\(candidateLabel) passed the Clinic cover-quality check."
        }

        if let expectedVolume = candidate.volumeNumber {
            let detectedVolumes = detectedExplicitCoverVolumeNumbers(in: existingData)
            if !detectedVolumes.isEmpty, !detectedVolumes.contains(expectedVolume) {
                let printed = detectedVolumes.sorted().map(String.init).joined(separator: ", ")
                return "Review local language-matched cover replacement: the embedded cover prints Volume \(printed), but this EPUB is Volume \(expectedVolume). \(sizeEvidence)"
            }
        }

        guard shouldUseCoverReplacement(
            existingData: existingData,
            candidateData: candidateImage.data,
            expectedVolume: nil
        ) else {
            return nil
        }
        if !coverImageIsUsableForEPUBCover(existingData) {
            return "Review local language-matched cover replacement: the embedded image is too small or is not shaped like a book cover. \(sizeEvidence)"
        }
        return "Review local language-matched cover replacement: the trusted library cover has meaningfully better image quality. \(sizeEvidence)"
    }

    private static func epubCoverLanguageCode(
        opfText: String,
        opfPath: String,
        unpackedURL: URL,
        fileManager: FileManager
    ) -> String? {
        for value in currentDublinCoreValues(in: opfText, localName: "language") {
            if let language = coverLanguageCode(from: value) {
                return language
            }
        }

        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let spineEntries = Array(spineEntryPaths(in: opfText, manifestItems: manifestItems).prefix(8))
        var sample = ""
        for entry in spineEntries {
            guard let url = try? safeUnpackedURL(for: entry, in: unpackedURL),
                  fileManager.fileExists(atPath: url.path(percentEncoded: false)),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            sample += "\n"
            sample += text
            if sample.count > 80_000 {
                break
            }
        }
        return coverLanguageCode(fromTextSample: sample)
    }

    private static func coverLanguageCode(from value: String) -> String? {
        guard let normalized = normalizedLanguage(value) else { return nil }
        if normalized.hasPrefix("ja") {
            return "jp"
        }
        if normalized.hasPrefix("en") {
            return "en"
        }
        return nil
    }

    private static func coverLanguageCode(fromTextSample sample: String) -> String? {
        guard !sample.isEmpty else { return nil }
        var japaneseScalars = 0
        var latinLetters = 0
        for scalar in sample.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF:
                japaneseScalars += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinLetters += 1
            default:
                continue
            }
        }
        if japaneseScalars >= 40 && japaneseScalars > latinLetters / 4 {
            return "jp"
        }
        if latinLetters >= 200 && japaneseScalars < 20 {
            return "en"
        }
        return nil
    }

    private static func firstIntegerMatch(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Int(text[range])
    }

    private static func removeAppleMetadataFiles(in unpackedURL: URL, fileManager: FileManager) throws {
        for name in appleMetadataFiles {
            let url = unpackedURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func safeUnpackedURL(for entryPath: String, in root: URL) throws -> URL {
        guard archiveEntryNameIsSafe(entryPath) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.unsafeArchiveEntry(entryPath)
        }

        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let url = rootURL.appendingPathComponent(entryPath).standardizedFileURL
        let path = url.path(percentEncoded: false)
        guard path == rootPath || path.hasPrefix(rootPrefix) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.unsafeArchiveEntry(entryPath)
        }
        return url
    }

    private static func unpackedEntryNames(in root: URL, fileManager: FileManager) throws -> Set<String> {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var entries = Set<String>()
        for case let url as URL in enumerator {
            var isDirectory = ObjCBool(false)
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  path.hasPrefix(rootPrefix) else {
                continue
            }
            let relativePath = cleanEPUBResourcePath(String(path.dropFirst(rootPrefix.count)))
            if archiveEntryNameIsSafe(relativePath) {
                entries.insert(relativePath)
            }
        }
        return entries
    }

    private static func validateUnpackedTree(root: URL, fileManager: FileManager) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw SableLibraryAppleBooksCompatibilityRepairError.unsafeArchiveEntry(
                    url.lastPathComponent
                )
            }

            let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPrefix) else {
                throw SableLibraryAppleBooksCompatibilityRepairError.unsafeArchiveEntry(
                    url.lastPathComponent
                )
            }
        }
    }

    private static func addFreshPackageIdentifier(to opfText: String, freshID: String) -> String {
        var text = opfText
        if text.range(of: #"id\s*=\s*["']sable-import-id["']"#, options: .regularExpression) == nil {
            text = insertBeforeMetadataClose(
                in: text,
                insertion: #"    <dc:identifier id="sable-import-id">\#(freshID)</dc:identifier>"# + "\n  "
            )
        } else {
            text = replacingDublinCoreElementValue(
                in: text,
                id: "sable-import-id",
                value: freshID
            )
        }

        if text.range(of: #"unique-identifier\s*="#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(
                of: #"unique-identifier\s*=\s*["'][^"']*["']"#,
                with: #"unique-identifier="sable-import-id""#,
                options: .regularExpression
            )
        } else {
            text = text.replacingOccurrences(
                of: #"<package\b"#,
                with: #"<package unique-identifier="sable-import-id""#,
                options: [.regularExpression]
            )
        }

        return replacingDCTermsModified(in: text, dateText: epubModifiedDateText(Date()))
    }

    private static func replacingDublinCoreElementValue(
        in opfText: String,
        id: String,
        value: String
    ) -> String {
        let pattern = #"<(?:[A-Za-z0-9_]+:)?identifier\b(?=[^>]*\bid\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: id))["'])[^>]*>[\s\S]*?</(?:[A-Za-z0-9_]+:)?identifier>"#
        guard let range = opfText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return opfText
        }

        let element = String(opfText[range])
        guard let openingEnd = element.range(of: ">"),
              let closingStart = element.range(
                of: #"</(?:[A-Za-z0-9_]+:)?identifier>"#,
                options: [.regularExpression, .caseInsensitive],
                range: openingEnd.upperBound..<element.endIndex
              ) else {
            return opfText
        }

        let replacement = String(element[..<openingEnd.upperBound])
            + xmlEscapedText(value)
            + String(element[closingStart.lowerBound...])
        return opfText.replacingCharacters(in: range, with: replacement)
    }

    private static func settingEPUB3PackageVersionIfNeeded(in opfText: String) -> String {
        guard let packageTag = matches(
            in: opfText,
            pattern: #"<(?:[A-Za-z0-9_]+:)?package\b[^>]*>"#
        ).first else {
            return opfText
        }

        let attrs = attributes(in: packageTag)
        let version = attrs["version"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.map(packageVersionIsOlderThanEPUB3) ?? true else {
            return opfText
        }

        let replacement: String
        if attrs["version"] != nil {
            replacement = tagSettingAttribute(packageTag, name: "version", value: "3.0")
        } else if packageTag.hasSuffix("/>") {
            replacement = String(packageTag.dropLast(2)) + #" version="3.0"/>"#
        } else {
            replacement = String(packageTag.dropLast()) + #" version="3.0">"#
        }
        return opfText.replacingOccurrences(of: packageTag, with: replacement)
    }

    private static func packageVersionIsOlderThanEPUB3(_ value: String) -> Bool {
        let numericText = value
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(numericText) else {
            return true
        }
        return number < 3
    }

    private static func addCoverMetadata(to opfText: String) -> String {
        var text = opfText
        let cover = coverAnalysis(in: text)
        guard let coverID = cover.likelyCoverID, !coverID.isEmpty else { return text }

        let metaTags = metaTags(in: text).filter {
            metadataComparisonKey(attributes(in: $0)["name"] ?? "").caseInsensitiveCompare("cover") == .orderedSame
        }

        if let existingMeta = metaTags.first {
            let replacement = tagSettingAttribute(existingMeta, name: "content", value: coverID)
            if replacement != existingMeta {
                text = text.replacingOccurrences(of: existingMeta, with: replacement)
            }
        } else {
            text = insertBeforeMetadataClose(
                in: text,
                insertion: #"    <meta name="cover" content="\#(coverID)"/>"# + "\n  "
            )
        }

        let itemTags = matches(in: text, pattern: #"<(?:[A-Za-z0-9_]+:)?item\b[^>]*>"#)
        for tag in itemTags {
            let attrs = attributes(in: tag)
            guard attrs["id"] == coverID else { continue }

            let replacement: String
            if let properties = attrs["properties"] {
                let parts = properties.split(whereSeparator: \.isWhitespace).map(String.init)
                if parts.map({ $0.lowercased() }).contains("cover-image") {
                    return text
                }
                let newProperties = (parts + ["cover-image"]).joined(separator: " ")
                replacement = tagSettingAttribute(tag, name: "properties", value: newProperties)
            } else if tag.hasSuffix("/>") {
                replacement = String(tag.dropLast(2)) + #" properties="cover-image"/>"#
            } else {
                replacement = String(tag.dropLast()) + #" properties="cover-image">"#
            }

            text = text.replacingOccurrences(of: tag, with: replacement)
            break
        }

        return text
    }

    private static func repairEPUBNavigation(
        in unpackedURL: URL,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws -> String {
        var text = opfText
        var changed = false
        var manifestItems = epubManifestItems(in: text, opfPath: opfPath)
        guard !manifestItems.isEmpty else { return text }

        let navItems = manifestItems.filter(\.isNavigationDocument)
        let likelyNavItem = try likelyNavigationManifestItem(in: manifestItems, unpackedURL: unpackedURL)
        var chosenNavItem = navItems.first ?? likelyNavItem
        let navigationEntries = try navigationEntriesForSpine(
            in: text,
            manifestItems: manifestItems
        ) { entryPath in
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try String(contentsOf: url, encoding: .utf8)
        }
        let ncxNavigationEntries = try navigationEntriesFromNCX(
            in: manifestItems,
            opfPath: opfPath,
            textForEntry: { entryPath in
                let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
                guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
                return try String(contentsOf: url, encoding: .utf8)
            },
            entryExists: { entryPath in
                guard let url = try? safeUnpackedURL(for: entryPath, in: unpackedURL) else { return false }
                return fileManager.fileExists(atPath: url.path(percentEncoded: false))
            }
        )
        let tocEntries = navigationEntriesAreUseful(navigationEntries) ? navigationEntries : ncxNavigationEntries
        let canGenerateUsefulTOC = navigationEntriesAreUseful(tocEntries)

        if chosenNavItem == nil, canGenerateUsefulTOC {
            let href = uniqueNavigationHref(opfPath: opfPath, unpackedURL: unpackedURL, fileManager: fileManager)
            let id = uniqueManifestID(prefix: "sable-nav", existingItems: manifestItems)
            let entryPath = joinedEPUBPath(baseEntryPath: opfPath, href: href)
            let itemTag = #"    <item id="\#(xmlEscapedAttribute(id))" href="\#(xmlEscapedAttribute(href))" media-type="application/xhtml+xml" properties="nav"/>"#
            text = insertBeforeManifestClose(in: text, insertion: itemTag + "\n  ")
            chosenNavItem = EPUBManifestItem(
                tag: itemTag,
                id: id,
                href: href,
                mediaType: "application/xhtml+xml",
                properties: ["nav"],
                entryPath: entryPath
            )
            manifestItems.append(chosenNavItem!)
            changed = true
        }

        if changed {
            text = settingEPUB3PackageVersionIfNeeded(in: text)
        }

        guard let chosenNavItem else {
            return changed ? replacingDCTermsModified(in: text, dateText: epubModifiedDateText(Date())) : text
        }

        let updatedChosenTag = tagSettingProperties(chosenNavItem.tag, adding: ["nav"], removing: [])
        if updatedChosenTag != chosenNavItem.tag {
            text = text.replacingOccurrences(of: chosenNavItem.tag, with: updatedChosenTag)
            changed = true
        }

        for duplicate in navItems where duplicate.id != chosenNavItem.id {
            let updatedTag = tagSettingProperties(duplicate.tag, adding: [], removing: ["nav"])
            if updatedTag != duplicate.tag {
                text = text.replacingOccurrences(of: duplicate.tag, with: updatedTag)
                changed = true
            }
        }

        let navURL = try safeUnpackedURL(for: chosenNavItem.entryPath, in: unpackedURL)
        var existingNavText = fileManager.fileExists(atPath: navURL.path(percentEncoded: false))
            ? (try? String(contentsOf: navURL, encoding: .utf8))
            : nil
        let shouldRebuildExistingTOCOrder = existingNavText.map { navText in
            navigationDocumentHasTOC(navText)
                && navigationOrderNeedsManualReview(
                    navigationText: navText,
                    navEntryPath: chosenNavItem.entryPath,
                    opfPath: opfPath,
                    opfText: text,
                    manifestItems: manifestItems
                )
        } == true
        if canGenerateUsefulTOC,
           (existingNavText.map(navigationDocumentHasTOC) != true || shouldRebuildExistingTOCOrder) {
            let navText: String
            if let existingNavText, shouldRebuildExistingTOCOrder {
                navText = replacingTOCNavigation(
                    in: existingNavText,
                    entries: tocEntries,
                    navHref: chosenNavItem.href
                )
            } else if let existingNavText {
                navText = addingTOCNavigation(
                    to: existingNavText,
                    entries: tocEntries,
                    navHref: chosenNavItem.href
                )
            } else {
                navText = generatedNavigationDocument(
                    entries: tocEntries,
                    navHref: chosenNavItem.href
                )
            }
            try fileManager.createDirectory(
                at: navURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try navText.write(to: navURL, atomically: true, encoding: .utf8)
            existingNavText = navText
            changed = true
        }

        if let navText = existingNavText {
            let existingEntries = Set(try unpackedEntryNames(in: unpackedURL, fileManager: fileManager)
                .map(normalizedEPUBResourcePath))
            let staleLinkRepairs = staleNavigationLinkRepairs(
                in: navText,
                navEntryPath: chosenNavItem.entryPath,
                existingEntries: existingEntries
            )
            if !staleLinkRepairs.isEmpty {
                var patchedNavText = navText
                for repair in staleLinkRepairs {
                    patchedNavText = patchedNavText.replacingOccurrences(of: repair.listItem, with: "")
                }
                if patchedNavText != navText {
                    try patchedNavText.write(to: navURL, atomically: true, encoding: .utf8)
                    existingNavText = patchedNavText
                    changed = true
                }
            }
        }

        if try repairLocalMissingFragmentLinks(
            in: unpackedURL,
            manifestItems: manifestItems,
            fileManager: fileManager
        ) {
            changed = true
        }

        if changed {
            text = settingEPUB3PackageVersionIfNeeded(in: text)
        }
        return changed ? replacingDCTermsModified(in: text, dateText: epubModifiedDateText(Date())) : text
    }

    private static func staleNavigationLinkRepairs(
        in navigationText: String,
        navEntryPath: String,
        existingEntries: Set<String>
    ) -> [StaleNavigationLinkRepair] {
        xmlElementBlocks(named: "li", in: navigationText).compactMap { block in
            let localTargets = contentResourceHrefs(in: block.fullText).compactMap { href -> String? in
                guard let target = localResourceTargetEntryPath(from: href, baseEntryPath: navEntryPath) else {
                    return nil
                }
                let extensionName = URL(fileURLWithPath: target).pathExtension.lowercased()
                guard htmlResourcePathExtensions.contains(extensionName) else {
                    return nil
                }
                return normalizedEPUBResourcePath(target)
            }
            guard !localTargets.isEmpty else { return nil }

            let hasExistingTarget = localTargets.contains { existingEntries.contains($0) }
            let hasMissingTarget = localTargets.contains { !existingEntries.contains($0) }
            guard hasMissingTarget, !hasExistingTarget else { return nil }
            return StaleNavigationLinkRepair(listItem: block.fullText)
        }
    }

    private static func repairLocalMissingFragmentLinks(
        in unpackedURL: URL,
        manifestItems: [EPUBManifestItem],
        fileManager: FileManager
    ) throws -> Bool {
        let existingEntries = Set(try unpackedEntryNames(in: unpackedURL, fileManager: fileManager)
            .map(normalizedEPUBResourcePath))
        let contentItems = manifestItems.filter { item in
            manifestItemIsOPSContentDocument(item)
                && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
        }
        var textCache: [String: String] = [:]

        func textForEntry(_ entryPath: String) throws -> String? {
            let key = normalizedEPUBResourcePath(entryPath)
            if let cached = textCache[key] {
                return cached
            }
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                return nil
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            textCache[key] = text
            return text
        }

        var changed = false
        for item in contentItems {
            let key = normalizedEPUBResourcePath(item.entryPath)
            guard var text = try textForEntry(item.entryPath) else { continue }
            let repairs = try localMissingFragmentLinkRepairs(
                in: text,
                sourceEntryPath: item.entryPath,
                entryExists: { entryPath in
                    existingEntries.contains(normalizedEPUBResourcePath(entryPath))
                },
                textForEntry: textForEntry
            )
            guard !repairs.isEmpty else { continue }

            for repair in repairs {
                text = text.replacingOccurrences(of: repair.tag, with: repair.replacementTag)
            }
            let url = try safeUnpackedURL(for: item.entryPath, in: unpackedURL)
            try text.write(to: url, atomically: true, encoding: .utf8)
            textCache[key] = text
            changed = true
        }
        return changed
    }

    private static func repairLinkedResourceReferences(
        in unpackedURL: URL,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws -> Bool {
        let entryNames = try unpackedEntryNames(in: unpackedURL, fileManager: fileManager)
        let entryList = entryNames.sorted()
        let existingEntries = Set(entryList.map(normalizedEPUBResourcePath))
        var textCache: [String: String] = [:]

        func textForEntry(_ entryPath: String) throws -> String? {
            let key = normalizedEPUBResourcePath(entryPath)
            if let cached = textCache[key] {
                return cached
            }
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                return nil
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            textCache[key] = text
            return text
        }

        let repairs = try linkedResourceReferenceRepairs(
            existingEntries: existingEntries,
            entries: entryList,
            opfPath: opfPath,
            opfText: opfText,
            textForEntry: textForEntry
        )
        let staleRepairs = try staleLinkedResourceReferenceRepairs(
            existingEntries: existingEntries,
            entries: entryList,
            opfPath: opfPath,
            opfText: opfText,
            textForEntry: textForEntry
        )
        guard !repairs.isEmpty || !staleRepairs.isEmpty else { return false }

        var changed = false
        let repairsByEntry = Dictionary(grouping: repairs) { $0.entryPath }
        let staleRepairsByEntry = Dictionary(grouping: staleRepairs) { $0.entryPath }
        let repairEntryPaths = Set(repairsByEntry.keys).union(staleRepairsByEntry.keys)
        for entryPath in repairEntryPaths {
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            var text = try String(contentsOf: url, encoding: .utf8)
            var changedThisFile = false
            for repair in repairsByEntry[entryPath, default: []] {
                let patched = replacingResourceReference(
                    repair.originalReference,
                    with: repair.replacementReference,
                    in: text
                )
                if patched != text {
                    text = patched
                    changedThisFile = true
                }
            }
            for repair in staleRepairsByEntry[entryPath, default: []] {
                let patched = text.replacingOccurrences(of: repair.tag, with: "\n")
                if patched != text {
                    text = patched
                    changedThisFile = true
                }
            }
            if changedThisFile {
                try text.write(to: url, atomically: true, encoding: .utf8)
                changed = true
            }
        }
        return changed
    }

    private static func replacingResourceReference(
        _ original: String,
        with replacement: String,
        in text: String
    ) -> String {
        var result = text
        let escapedOriginal = xmlEscapedAttribute(original)
        let escapedReplacement = xmlEscapedAttribute(replacement)
        let pairs = [
            ("\"\(escapedOriginal)\"", "\"\(escapedReplacement)\""),
            ("'\(escapedOriginal)'", "'\(escapedReplacement)'"),
            ("(\(original))", "(\(replacement))"),
            ("('\(original)')", "('\(replacement)')"),
            ("(\"\(original)\")", "(\"\(replacement)\")")
        ]
        for (needle, replacementText) in pairs {
            result = result.replacingOccurrences(of: needle, with: replacementText)
        }
        return result
    }

    private static func repairEPUBStructure(
        in unpackedURL: URL,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws -> Bool {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        guard !manifestItems.isEmpty else { return false }

        let candidates = try semanticHeadingCandidates(
            in: opfText,
            manifestItems: manifestItems,
            opfPath: opfPath,
            textForEntry: { entryPath in
                let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
                guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
                return try String(contentsOf: url, encoding: .utf8)
            },
            entryExists: { entryPath in
                guard let url = try? safeUnpackedURL(for: entryPath, in: unpackedURL) else { return false }
                return fileManager.fileExists(atPath: url.path(percentEncoded: false))
            }
        )
        guard candidates.count >= 2 else { return false }

        var changed = false
        let candidatesByEntry = Dictionary(grouping: candidates, by: \.entryPath)
        for (entryPath, entryCandidates) in candidatesByEntry {
            let url = try safeUnpackedURL(for: entryPath, in: unpackedURL)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }

            var text = try String(contentsOf: url, encoding: .utf8)
            var changedThisFile = false
            for candidate in entryCandidates {
                let replacement: (range: Range<String.Index>, replacement: String)?
                if let fragment = candidate.fragment {
                    replacement = semanticHeadingReplacement(
                        in: text,
                        fragment: fragment,
                        label: candidate.label,
                        level: candidate.level
                    )
                } else {
                    replacement = semanticHeadingReplacementAtFirstVisibleBlock(
                        in: text,
                        label: candidate.label,
                        level: candidate.level
                    )
                }
                guard let replacement else {
                    continue
                }
                text.replaceSubrange(replacement.range, with: replacement.replacement)
                changedThisFile = true
            }

            if changedThisFile {
                try text.write(to: url, atomically: true, encoding: .utf8)
                changed = true
            }
        }

        return changed
    }

    private static func likelyNavigationManifestItem(
        in manifestItems: [EPUBManifestItem],
        unpackedURL: URL
    ) throws -> EPUBManifestItem? {
        var candidates: [(score: Int, item: EPUBManifestItem)] = []
        for item in manifestItems where item.mediaType.lowercased().contains("xhtml") {
            let hrefKey = item.href.lowercased()
            let idKey = item.id.lowercased()
            var score = 0
            if hrefKey.contains("nav") || idKey.contains("nav") {
                score += 50
            }
            if hrefKey.contains("toc") || idKey.contains("toc") {
                score += 40
            }
            guard score > 0 else { continue }
            let url = try safeUnpackedURL(for: item.entryPath, in: unpackedURL)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  navigationDocumentHasTOC(text) else {
                continue
            }
            candidates.append((score, item))
        }
        return candidates.sorted { $0.score > $1.score }.first?.item
    }

    private static func uniqueNavigationHref(
        opfPath: String,
        unpackedURL: URL,
        fileManager: FileManager
    ) -> String {
        for index in 0...100 {
            let href = index == 0 ? "nav.xhtml" : "nav-\(index).xhtml"
            let entryPath = joinedEPUBPath(baseEntryPath: opfPath, href: href)
            guard let url = try? safeUnpackedURL(for: entryPath, in: unpackedURL),
                  !fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            return href
        }
        return "nav-\(UUID().uuidString).xhtml"
    }

    private static func uniqueManifestID(prefix: String, existingItems: [EPUBManifestItem]) -> String {
        let existing = Set(existingItems.map(\.id))
        if !existing.contains(prefix) {
            return prefix
        }
        for index in 1...1000 {
            let candidate = "\(prefix)-\(index)"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "\(prefix)-\(UUID().uuidString)"
    }

    private static func tagSettingProperties(_ tag: String, adding: [String], removing: Set<String>) -> String {
        var attrs = attributes(in: tag)
        var parts = propertyParts(attrs["properties"] ?? "")
        parts.removeAll { part in
            removing.contains { $0.caseInsensitiveCompare(part) == .orderedSame }
        }
        for addition in adding where !parts.contains(where: { $0.caseInsensitiveCompare(addition) == .orderedSame }) {
            parts.append(addition)
        }

        if parts.isEmpty {
            return tagRemovingAttribute(tag, name: "properties")
        }

        attrs["properties"] = parts.joined(separator: " ")
        return tagSettingAttribute(tag, name: "properties", value: attrs["properties"] ?? "")
    }

    private static func tagRemovingAttribute(_ tag: String, name: String) -> String {
        tag.replacingOccurrences(
            of: #"\s+\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*["'][^"']*["']"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func attributeValue(_ name: String, in attributes: [String: String]) -> String? {
        attributes.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private static func generatedNavigationDocument(entries: [EPUBNavigationEntry], navHref: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head>
            <title>Table of Contents</title>
          </head>
          <body>
        \(generatedTOCNavigation(entries: entries, navHref: navHref).split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))
          </body>
        </html>
        """
    }

    private static func addingTOCNavigation(
        to navText: String,
        entries: [EPUBNavigationEntry],
        navHref: String
    ) -> String {
        var text = ensureEPUBNamespace(in: navText)
        let insertion = generatedTOCNavigation(entries: entries, navHref: navHref) + "\n"
        guard let bodyRange = text.range(
            of: #"<(?:[A-Za-z0-9_]+:)?body\b[^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return generatedNavigationDocument(entries: entries, navHref: navHref)
        }
        text.insert(contentsOf: "\n\(insertion)", at: bodyRange.upperBound)
        return text
    }

    private static func replacingTOCNavigation(
        in navText: String,
        entries: [EPUBNavigationEntry],
        navHref: String
    ) -> String {
        var text = ensureEPUBNamespace(in: navText)
        let replacement = generatedTOCNavigation(entries: entries, navHref: navHref)
        guard let range = text.range(
            of: #"<(?:[A-Za-z0-9_]+:)?nav\b(?=[^>]*(?:epub:)?type\s*=\s*["'][^"']*\btoc\b)[\s\S]*?</(?:[A-Za-z0-9_]+:)?nav>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return addingTOCNavigation(to: text, entries: entries, navHref: navHref)
        }
        text.replaceSubrange(range, with: replacement)
        return text
    }

    private static func ensureEPUBNamespace(in navText: String) -> String {
        guard navText.range(of: #"xmlns:epub\s*="#, options: [.regularExpression, .caseInsensitive]) == nil,
              let htmlRange = navText.range(
                of: #"<(?:[A-Za-z0-9_]+:)?html\b[^>]*>"#,
                options: [.regularExpression, .caseInsensitive]
              ) else {
            return navText
        }
        let tag = String(navText[htmlRange])
        let replacement = tagSettingAttribute(tag, name: "xmlns:epub", value: "http://www.idpf.org/2007/ops")
        return navText.replacingOccurrences(of: tag, with: replacement)
    }

    private static func generatedTOCNavigation(entries: [EPUBNavigationEntry], navHref: String) -> String {
        let rows = entries.map { entry in
            let href = relativeEPUBHref(from: navHref, to: entry.href) + hrefFragment(from: entry.href)
            return #"      <li><a href="\#(xmlEscapedAttribute(href))">\#(xmlEscapedText(entry.label))</a></li>"#
        }.joined(separator: "\n")
        return """
        <nav epub:type="toc" id="toc">
          <h1>Table of Contents</h1>
          <ol>
        \(rows)
          </ol>
        </nav>
        """
    }

    private static func relativeEPUBHref(from sourceHref: String, to targetHref: String) -> String {
        let sourceComponents = cleanEPUBResourcePath(sourceHref).split(separator: "/").map(String.init)
        let targetComponents = cleanEPUBResourcePath(targetHref).split(separator: "/").map(String.init)
        let sourceDirectory = Array(sourceComponents.dropLast())

        var commonCount = 0
        while commonCount < sourceDirectory.count,
              commonCount < targetComponents.count,
              sourceDirectory[commonCount] == targetComponents[commonCount] {
            commonCount += 1
        }

        let up = Array(repeating: "..", count: sourceDirectory.count - commonCount)
        let down = Array(targetComponents.dropFirst(commonCount))
        let components = up + down
        return components.isEmpty ? targetHref : components.joined(separator: "/")
    }

    static func trustedCoverDownloadURLString(from rawValue: String) -> String? {
        try? trustedCoverDownloadURL(from: rawValue).absoluteString
    }

    static func coverProvider(for coverURLString: String) -> SableLibraryMetadataProvider? {
        guard let url = URL(string: coverURLString),
              let host = url.host?.lowercased() else {
            return nil
        }

        if host.contains("mangabaka") {
            return .mangabaka
        }
        if host.contains("openlibrary") {
            return .openLibrary
        }
        if host.contains("anilist") {
            return .anilist
        }
        if host.contains("myanimelist") || host.contains("malcdn") {
            return .myAnimeList
        }
        if host.contains("themoviedb") || host.contains("tmdb") {
            return .tmdb
        }
        if host.contains("tvmaze") {
            return .tvmaze
        }
        return nil
    }

    private static func addingDownloadedCoverIfNeeded(
        to opfText: String,
        opfPath: String,
        opfURL: URL,
        unpackedURL: URL,
        coverURLString: String?,
        localCoverCandidates: [SableLibraryEPUBImportCoverCandidate],
        fileManager: FileManager
    ) async throws -> String {
        let cover = coverAnalysis(in: opfText)
        let preferredLanguage = epubCoverLanguageCode(
            opfText: opfText,
            opfPath: opfPath,
            unpackedURL: unpackedURL,
            fileManager: fileManager
        )
        let localCandidate = selectedLocalCoverCandidate(
            in: localCoverCandidates,
            preferredLanguage: preferredLanguage
        )
        let candidateImage: EPUBCoverImageCandidate

        if let localCandidate {
            candidateImage = try localCoverImageCandidate(from: localCandidate)
        } else if !localCoverCandidates.isEmpty {
            return opfText
        } else if !cover.hasImageManifestItems, let coverURLString {
            let coverURL = try trustedCoverDownloadURL(from: coverURLString)
            let coverData = try await downloadTrustedCoverImage(from: coverURL)
            let jpegData = try normalizedCoverJPEGData(from: coverData, source: coverURL)
            candidateImage = EPUBCoverImageCandidate(data: jpegData, isLocalFile: false)
        } else {
            return opfText
        }

        guard coverImageIsUsableForEPUBCover(candidateImage.data) else {
            return opfText
        }

        guard cover.hasImageManifestItems else {
            return try opfTextAddingMissingCover(
                to: opfText,
                opfURL: opfURL,
                jpegData: candidateImage.data,
                fileManager: fileManager
            )
        }

        guard candidateImage.isLocalFile,
              let coverItem = likelyCoverManifestItem(in: opfText, opfPath: opfPath),
              let existingCoverURL = try? safeUnpackedURL(for: coverItem.entryPath, in: unpackedURL) else {
            return opfText
        }

        let existingData = try? Data(contentsOf: existingCoverURL)
        guard shouldUseCoverReplacement(
            existingData: existingData,
            candidateData: candidateImage.data,
            expectedVolume: localCandidate?.volumeNumber
        ) else {
            return opfText
        }

        let existingExtension = existingCoverURL.pathExtension.lowercased()
        let targetURL: URL
        let patchedOPF: String
        let replacesExistingCoverFile: Bool

        if existingExtension == "jpg" || existingExtension == "jpeg" {
            targetURL = existingCoverURL
            replacesExistingCoverFile = true
            let updatedTag = tagSettingProperties(
                tagSettingAttribute(coverItem.tag, name: "media-type", value: "image/jpeg"),
                adding: ["cover-image"],
                removing: []
            )
            patchedOPF = opfText.replacingOccurrences(of: coverItem.tag, with: updatedTag)
        } else {
            let coverFileName = uniqueCoverFileName(
                in: opfURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
            targetURL = opfURL.deletingLastPathComponent().appendingPathComponent(coverFileName)
            replacesExistingCoverFile = false
            var updatedTag = tagSettingAttribute(coverItem.tag, name: "href", value: coverFileName)
            updatedTag = tagSettingAttribute(updatedTag, name: "media-type", value: "image/jpeg")
            updatedTag = tagSettingProperties(updatedTag, adding: ["cover-image"], removing: [])
            patchedOPF = opfText.replacingOccurrences(of: coverItem.tag, with: updatedTag)
        }

        guard replacesExistingCoverFile || patchedOPF != opfText else { return opfText }
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try candidateImage.data.write(to: targetURL, options: .atomic)
        return addCoverMetadata(to: patchedOPF)
    }

    private static func opfTextAddingMissingCover(
        to opfText: String,
        opfURL: URL,
        jpegData: Data,
        fileManager: FileManager
    ) throws -> String {
        let coverID = availableManifestID(base: "sable-cover-image", in: opfText)
        let coverFileName = uniqueCoverFileName(
            in: opfURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        let patched = opfTextAddingDownloadedCover(
            to: opfText,
            coverID: coverID,
            coverHref: coverFileName,
            mediaType: "image/jpeg"
        )
        guard patched != opfText else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("OPF manifest could not accept a downloaded cover image")
        }

        let coverFileURL = opfURL.deletingLastPathComponent().appendingPathComponent(coverFileName)
        try fileManager.createDirectory(
            at: coverFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try jpegData.write(to: coverFileURL, options: .atomic)
        return patched
    }

    private static func localCoverImageCandidate(
        from candidate: SableLibraryEPUBImportCoverCandidate
    ) throws -> EPUBCoverImageCandidate {
        let url = URL(fileURLWithPath: candidate.filePath)
        let data = try Data(contentsOf: url)
        let jpegData = try normalizedCoverJPEGData(from: data, source: url)
        return EPUBCoverImageCandidate(data: jpegData, isLocalFile: true)
    }

    private static func selectedLocalCoverCandidate(
        in candidates: [SableLibraryEPUBImportCoverCandidate],
        preferredLanguage: String?
    ) -> SableLibraryEPUBImportCoverCandidate? {
        guard let preferredLanguage else { return nil }
        return candidates
            .filter { $0.language.caseInsensitiveCompare(preferredLanguage) == .orderedSame }
            .max {
                (($0.width ?? 0) * ($0.height ?? 0)) < (($1.width ?? 0) * ($1.height ?? 0))
            }
    }

    private static func likelyCoverManifestItem(in opfText: String, opfPath: String) -> EPUBManifestItem? {
        let manifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let imageItems = manifestItems.filter(manifestItemIsImage)
        guard !imageItems.isEmpty else { return nil }
        if let likelyID = coverAnalysis(in: opfText).likelyCoverID,
           let likelyItem = imageItems.first(where: { $0.id == likelyID }) {
            return likelyItem
        }
        return imageItems.first
    }

    static func opfTextAddingDownloadedCover(
        to opfText: String,
        coverID: String,
        coverHref: String,
        mediaType: String
    ) -> String {
        guard !coverAnalysis(in: opfText).hasImageManifestItems else {
            return addCoverMetadata(to: opfText)
        }

        let item = """
            <item id="\(xmlEscapedAttribute(coverID))" href="\(xmlEscapedAttribute(coverHref))" media-type="\(xmlEscapedAttribute(mediaType))" properties="cover-image"/>
        """
        let patched = insertBeforeManifestClose(in: opfText, insertion: item + "\n  ")
        guard patched != opfText else { return opfText }
        return addCoverMetadata(to: patched)
    }

    private static func trustedCoverDownloadURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              var scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidCoverURL("Only http or https provider cover URLs are accepted.")
        }

        guard !hostIsLocalOrPrivate(host) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidCoverURL("Local and private-network cover URLs are not allowed.")
        }

        components.user = nil
        components.password = nil
        if scheme == "http" {
            scheme = "https"
            components.scheme = scheme
        }

        guard let url = components.url else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidCoverURL("The cover URL is malformed.")
        }
        return url
    }

    private static func hostIsLocalOrPrivate(_ host: String) -> Bool {
        let cleaned = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if cleaned == "localhost" || cleaned == "::1" || cleaned == "0:0:0:0:0:0:0:1" || cleaned.hasSuffix(".local") {
            return true
        }

        let parts = cleaned.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 || parts[0] == 127 || parts[0] == 0 {
            return true
        }
        if parts[0] == 169 && parts[1] == 254 {
            return true
        }
        if parts[0] == 172 && (16...31).contains(parts[1]) {
            return true
        }
        if parts[0] == 192 && parts[1] == 168 {
            return true
        }
        return false
    }

    private static let maxDownloadedCoverBytes = 15 * 1024 * 1024

    private static func downloadTrustedCoverImage(from url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw SableLibraryAppleBooksCompatibilityRepairError.coverDownloadFailed("HTTP \(http.statusCode) from \(url.host ?? "provider").")
            }
            guard data.count <= maxDownloadedCoverBytes else {
                throw SableLibraryAppleBooksCompatibilityRepairError.coverDownloadFailed("The cover image is larger than 15 MB.")
            }
            return data
        } catch let error as SableLibraryAppleBooksCompatibilityRepairError {
            throw error
        } catch {
            throw SableLibraryAppleBooksCompatibilityRepairError.coverDownloadFailed(error.localizedDescription)
        }
    }

    private static func normalizedCoverJPEGData(from data: Data, source: URL) throws -> Data {
        if data.starts(with: [0xFF, 0xD8, 0xFF]),
           coverImageDimensions(data) != nil {
            return data
        }

        #if canImport(AppKit)
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.unsupportedCoverImage(source.absoluteString)
        }
        return jpeg
        #else
        guard data.starts(with: [0xFF, 0xD8, 0xFF]) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.unsupportedCoverImage(source.absoluteString)
        }
        return data
        #endif
    }

    private static func availableManifestID(base: String, in opfText: String) -> String {
        let itemTags = matches(in: opfText, pattern: #"<(?:[A-Za-z0-9_]+:)?item\b[^>]*>"#)
        let existing = Set(itemTags.compactMap { attributes(in: $0)["id"] })
        if !existing.contains(base) {
            return base
        }
        for index in 2...999 {
            let candidate = "\(base)-\(index)"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "\(base)-\(UUID().uuidString)"
    }

    private static func uniqueCoverFileName(in folder: URL, fileManager: FileManager) -> String {
        let base = "sable-cover"
        let ext = "jpg"
        let first = "\(base).\(ext)"
        if !fileManager.fileExists(atPath: folder.appendingPathComponent(first).path(percentEncoded: false)) {
            return first
        }
        for index in 2...999 {
            let candidate = "\(base)-\(index).\(ext)"
            if !fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path(percentEncoded: false)) {
                return candidate
            }
        }
        return "\(base)-\(UUID().uuidString).\(ext)"
    }

    private static func tagSettingAttribute(_ tag: String, name: String, value: String) -> String {
        let safeValue = value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["'][^"']*["']"#
        let replacement = "\(name)=\"\(safeValue)\""

        if tag.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return tag.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        if tag.hasSuffix("/>") {
            return String(tag.dropLast(2)) + " \(name)=\"\(safeValue)\"/>"
        }

        return String(tag.dropLast()) + " \(name)=\"\(safeValue)\">"
    }

    private static func applyingImportMetadata(
        _ metadata: SableLibraryEPUBImportMetadata,
        to opfText: String,
        scopes: Set<SableLibraryEPUBRepairScope> = SableLibraryEPUBRepairScope.all
    ) -> String {
        var text = opfText
        let shouldWriteMetadata = scopes.contains(.metadata)
        let shouldWriteTags = scopes.contains(.tags)

        if shouldWriteMetadata {
            text = replacingTitleMetadata(in: text, metadata: metadata)
            text = replacingSubtitleMetadata(in: text, metadata: metadata)

            let creators = uniqueImportMetadataStrings(metadata.authors + metadata.artists)
            if !creators.isEmpty {
                text = replacingCreditMetadata(
                    in: text,
                    localName: "creator",
                    idPrefix: "sable-creator",
                    credits: creatorCredits(for: metadata)
                )
            }
            if !metadata.contributors.isEmpty {
                text = replacingCreditMetadata(
                    in: text,
                    localName: "contributor",
                    idPrefix: "sable-contributor",
                    credits: contributorCredits(for: metadata)
                )
            }
            if !metadata.publishers.isEmpty {
                text = replacingDublinCoreElements(in: text, localName: "publisher", values: metadata.publishers)
            }
            if let language = normalizedLanguage(metadata.languages.first) {
                text = replacingDublinCoreElements(in: text, localName: "language", values: [language])
            }
            if let date = importDateText(releaseDate: metadata.releaseDate, releaseYear: metadata.releaseYear) {
                text = replacingDublinCoreElements(in: text, localName: "date", values: [date])
            }
            if let pageCount = metadata.pageCount, pageCount > 0 {
                text = replacingPropertyMeta(in: text, property: "schema:numberOfPages", content: "\(pageCount)")
            }

            text = replacingSableImportIdentifiers(in: text, metadata: metadata)
            if let seriesTitle = metadata.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !seriesTitle.isEmpty {
                text = replacingNamedMeta(in: text, name: "calibre:series", content: seriesTitle)
            }
            if let seriesPosition = effectiveSeriesPosition(for: metadata) {
                text = replacingNamedMeta(in: text, name: "calibre:series_index", content: "\(seriesPosition)")
            }
            if let titleSort = metadata.titleSort?.trimmingCharacters(in: .whitespacesAndNewlines),
               !titleSort.isEmpty {
                text = replacingNamedMeta(in: text, name: "calibre:title_sort", content: titleSort)
            }
            text = replacingEPUB3SeriesCollectionMetadata(in: text, metadata: metadata)
        }

        if shouldWriteTags {
            if let description = metadata.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                text = replacingDublinCoreElements(in: text, localName: "description", values: [description])
            }
            if !metadata.subjects.isEmpty {
                text = replacingDublinCoreElements(in: text, localName: "subject", values: Array(metadata.subjects.prefix(30)))
            }
        }

        return text
    }

    private static func replacingTitleMetadata(in text: String, metadata: SableLibraryEPUBImportMetadata) -> String {
        let title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return text }

        let existingIDs = dublinCoreElements(in: text, localName: "title")
            .compactMap(\.id)
        let strippedRefinements = removingRefinedMeta(
            in: text,
            refinesIDs: Set(existingIDs + ["sable-title"])
        )
        let stripped = strippingDublinCoreElements(in: strippedRefinements, localName: "title")
        var rows = [
            "    <dc:title id=\"sable-title\">\(xmlEscapedText(title))</dc:title>",
            "    <meta refines=\"#sable-title\" property=\"title-type\">main</meta>"
        ]

        if let titleSort = metadata.titleSort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !titleSort.isEmpty {
            rows.append("    <meta refines=\"#sable-title\" property=\"file-as\">\(xmlEscapedText(titleSort))</meta>")
        }

        return insertBeforeMetadataClose(in: stripped, insertion: rows.joined(separator: "\n") + "\n  ")
    }

    private static func replacingSubtitleMetadata(in text: String, metadata: SableLibraryEPUBImportMetadata) -> String {
        let stripped = removingSablePropertyMeta(in: text, id: "sable-subtitle")
        guard let subtitle = metadata.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subtitle.isEmpty else {
            return stripped
        }

        let insertion = "    <meta property=\"dcterms:alternative\" id=\"sable-subtitle\">\(xmlEscapedText(subtitle))</meta>\n  "
        return insertBeforeMetadataClose(in: stripped, insertion: insertion)
    }

    private static func replacingCreditMetadata(
        in text: String,
        localName: String,
        idPrefix: String,
        credits: [SableLibraryEPUBImportCredit]
    ) -> String {
        let cleanedCredits = uniqueImportMetadataCredits(credits)
        guard !cleanedCredits.isEmpty else { return text }

        let existingIDs = dublinCoreElements(in: text, localName: localName)
            .compactMap(\.id)
        let strippedRefinements = removingRefinedMeta(
            in: text,
            refinesIDs: Set(existingIDs + cleanedCredits.indices.map { "\(idPrefix)-\($0 + 1)" })
        )
        let stripped = strippingDublinCoreElements(in: strippedRefinements, localName: localName)
        let rows = cleanedCredits.enumerated().flatMap { index, credit in
            let id = "\(idPrefix)-\(index + 1)"
            return [
                "    <dc:\(localName) id=\"\(id)\">\(xmlEscapedText(credit.name))</dc:\(localName)>",
                "    <meta refines=\"#\(id)\" property=\"role\" scheme=\"marc:relators\">\(credit.role.marcRelatorCode)</meta>"
            ]
        }
        return insertBeforeMetadataClose(in: stripped, insertion: rows.joined(separator: "\n") + "\n  ")
    }

    private static func replacingDublinCoreElements(
        in text: String,
        localName: String,
        values: [String]
    ) -> String {
        let cleanedValues = uniqueImportMetadataStrings(values)
        guard !cleanedValues.isEmpty else { return text }

        let stripped = strippingDublinCoreElements(in: text, localName: localName)
        let insertion = cleanedValues
            .map { "    <dc:\(localName)>\(xmlEscapedText($0))</dc:\(localName)>" }
            .joined(separator: "\n") + "\n  "
        return insertBeforeMetadataClose(in: stripped, insertion: insertion)
    }

    private static func strippingDublinCoreElements(in text: String, localName: String) -> String {
        let name = NSRegularExpression.escapedPattern(for: localName)
        return text.replacingOccurrences(
            of: #"\s*<(?:[A-Za-z0-9_]+:)?"# + name + #"\b[^>]*?(?:/>|>[\s\S]*?</(?:[A-Za-z0-9_]+:)?"# + name + #">)\s*"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func replacingSableImportIdentifiers(
        in text: String,
        metadata: SableLibraryEPUBImportMetadata
    ) -> String {
        let identifiers = importIdentifiers(from: metadata)
        let withoutOldRefinements = removingSableImportIdentifierRefinements(in: text)
        let stripped = withoutOldRefinements.replacingOccurrences(
            of: #"\s*<(?:[A-Za-z0-9_]+:)?identifier\b(?=[^>]*\bid=["']sable-(?:isbn|source|release|link)[^"']*["'])[^>]*>[\s\S]*?</(?:[A-Za-z0-9_]+:)?identifier>\s*"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        guard !identifiers.isEmpty else { return stripped }

        let insertionRows = identifiers.flatMap { id, value in
            var rows = [
                "    <dc:identifier id=\"\(xmlEscapedAttribute(id))\">\(xmlEscapedText(value))</dc:identifier>"
            ]
            if id.hasPrefix("sable-isbn-13-") {
                rows.append(
                    "    <meta refines=\"#\(xmlEscapedAttribute(id))\" property=\"identifier-type\" scheme=\"onix:codelist5\">15</meta>"
                )
            }
            return rows
        }
        let insertion = insertionRows.joined(separator: "\n") + "\n  "
        return insertBeforeMetadataClose(in: stripped, insertion: insertion)
    }

    private static func replacingDCTermsModified(in text: String, dateText: String) -> String {
        let stripped = metaTags(in: text).reduce(text) { partial, tag in
            guard metadataComparisonKey(attributes(in: tag)["property"] ?? "").caseInsensitiveCompare("dcterms:modified") == .orderedSame else {
                return partial
            }
            return partial.replacingOccurrences(of: tag, with: "\n")
        }
        let insertion = "    <meta property=\"dcterms:modified\">\(xmlEscapedText(dateText))</meta>\n  "
        return insertBeforeMetadataClose(in: stripped, insertion: insertion)
    }

    private static func replacingPropertyMeta(in text: String, property: String, content: String) -> String {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return text }

        let stripped = metaTags(in: text).reduce(text) { partial, tag in
            guard metadataComparisonKey(attributes(in: tag)["property"] ?? "").caseInsensitiveCompare(property) == .orderedSame else {
                return partial
            }
            return partial.replacingOccurrences(of: tag, with: "\n")
        }
        let insertion = "    <meta property=\"\(xmlEscapedAttribute(property))\">\(xmlEscapedText(cleanContent))</meta>\n  "
        return insertBeforeMetadataClose(in: stripped, insertion: insertion)
    }

    private static func replacingEPUB3SeriesCollectionMetadata(
        in text: String,
        metadata: SableLibraryEPUBImportMetadata
    ) -> String {
        guard let seriesTitle = metadata.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !seriesTitle.isEmpty else {
            return text
        }

        let stripped = removingEPUB3SeriesCollectionMetadata(in: text, seriesTitle: seriesTitle)
        let collectionID = "sable-series"
        var rows = [
            "    <meta property=\"belongs-to-collection\" id=\"\(collectionID)\">\(xmlEscapedText(seriesTitle))</meta>",
            "    <meta refines=\"#\(collectionID)\" property=\"collection-type\">series</meta>"
        ]

        if let groupPosition = epub3GroupPositionText(effectiveSeriesPosition(for: metadata)) {
            rows.append("    <meta refines=\"#\(collectionID)\" property=\"group-position\">\(xmlEscapedText(groupPosition))</meta>")
        }

        if let fileAs = epub3FileAsTitle(seriesTitle) {
            rows.append("    <meta refines=\"#\(collectionID)\" property=\"file-as\">\(xmlEscapedText(fileAs))</meta>")
        }

        return insertBeforeMetadataClose(in: stripped, insertion: rows.joined(separator: "\n") + "\n  ")
    }

    private static func removingEPUB3SeriesCollectionMetadata(in text: String, seriesTitle: String) -> String {
        let tags = metaTags(in: text)
        let targetIDs = Set(tags.compactMap { tag -> String? in
            let attrs = attributes(in: tag)
            let property = metadataComparisonKey(attrs["property"] ?? "")
            guard property.caseInsensitiveCompare("belongs-to-collection") == .orderedSame else {
                return nil
            }

            let id = attrs["id"] ?? ""
            if id == "sable-series" {
                return id
            }

            let title = metaElementText(in: tag)
            if metadataComparisonKey(title).caseInsensitiveCompare(metadataComparisonKey(seriesTitle)) == .orderedSame {
                return id.isEmpty ? nil : id
            }
            return nil
        })

        guard !targetIDs.isEmpty else { return text }

        return tags.reduce(text) { partial, tag in
            let attrs = attributes(in: tag)
            let id = attrs["id"] ?? ""
            let refinesID = (attrs["refines"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if targetIDs.contains(id) || targetIDs.contains(refinesID) {
                return partial.replacingOccurrences(of: tag, with: "\n")
            }
            return partial
        }
    }

    private static func replacingNamedMeta(in text: String, name: String, content: String) -> String {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return text }

        let stripped = metaTags(in: text).reduce(text) { partial, tag in
            guard metadataComparisonKey(attributes(in: tag)["name"] ?? "").caseInsensitiveCompare(name) == .orderedSame else {
                return partial
            }
            return partial.replacingOccurrences(of: tag, with: "\n")
        }
        let insertion = "    <meta name=\"\(xmlEscapedAttribute(name))\" content=\"\(xmlEscapedAttribute(cleanContent))\"/>\n  "
        return insertBeforeMetadataClose(in: stripped, insertion: insertion)
    }

    private static func importIdentifiers(from metadata: SableLibraryEPUBImportMetadata) -> [(String, String)] {
        var identifiers: [(String, String)] = []
        for (index, isbn) in uniqueImportMetadataStrings(metadata.isbn13).enumerated() {
            identifiers.append(("sable-isbn-13-\(index + 1)", "urn:isbn:\(isbn)"))
        }

        for sourceID in metadata.sourceIDs {
            let cleanProvider = sourceID.provider.rawValue.replacingOccurrences(of: #"[^a-zA-Z0-9_-]+"#, with: "-", options: .regularExpression)
            let cleanValue = sourceID.value.replacingOccurrences(of: #"[^a-zA-Z0-9_-]+"#, with: "-", options: .regularExpression)
            guard !cleanValue.isEmpty else { continue }
            identifiers.append(("sable-source-\(cleanProvider)-\(cleanValue)", "\(sourceID.provider.rawValue):\(sourceID.value)"))
        }

        for identifier in metadata.extraIdentifiers {
            let cleanID = identifier.id.replacingOccurrences(
                of: #"[^a-zA-Z0-9_-]+"#,
                with: "-",
                options: .regularExpression
            )
            let cleanValue = identifier.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanID.isEmpty, !cleanValue.isEmpty else { continue }
            identifiers.append((cleanID, cleanValue))
        }

        var seen = Set<String>()
        return identifiers.compactMap { id, value in
            let key = "\(id)|\(value)"
            return seen.insert(key).inserted ? (id, value) : nil
        }
    }

    private static func epubModifiedDateText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func effectiveSeriesPosition(for metadata: SableLibraryEPUBImportMetadata) -> Int? {
        metadata.volumeNumber ?? metadata.seriesPosition
    }

    private static func epub3GroupPositionText(_ volumeNumber: Int?) -> String? {
        guard let volumeNumber, volumeNumber > 0 else { return nil }
        return "\(volumeNumber)"
    }

    fileprivate static func epub3FileAsTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for article in ["The", "An", "A"] {
            let prefix = article + " "
            if trimmed.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return rest.isEmpty ? nil : "\(rest), \(article)"
            }
        }
        return nil
    }

    private static func epub3SeriesCollectionMetadataMatches(
        _ metadata: SableLibraryEPUBImportMetadata,
        currentOPFText: String
    ) -> Bool {
        guard let seriesTitle = metadata.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !seriesTitle.isEmpty else {
            return true
        }

        let expectedPosition = epub3GroupPositionText(effectiveSeriesPosition(for: metadata))
        let expectedFileAs = epub3FileAsTitle(seriesTitle)
        return epub3SeriesCollections(in: currentOPFText).contains { collection in
            guard metadataComparisonKey(collection.title).caseInsensitiveCompare(metadataComparisonKey(seriesTitle)) == .orderedSame,
                  metadataComparisonKey(collection.collectionType ?? "").caseInsensitiveCompare("series") == .orderedSame else {
                return false
            }

            if let expectedPosition,
               metadataComparisonKey(collection.groupPosition ?? "") != metadataComparisonKey(expectedPosition) {
                return false
            }

            if let expectedFileAs,
               metadataComparisonKey(collection.fileAs ?? "").caseInsensitiveCompare(metadataComparisonKey(expectedFileAs)) != .orderedSame {
                return false
            }

            return true
        }
    }

    private static func epub3SeriesCollections(in text: String) -> [EPUB3SeriesCollection] {
        let tags = metaTags(in: text)
        return tags.compactMap { tag in
            let attrs = attributes(in: tag)
            guard metadataComparisonKey(attrs["property"] ?? "").caseInsensitiveCompare("belongs-to-collection") == .orderedSame,
                  let id = attrs["id"],
                  !id.isEmpty else {
                return nil
            }

            return EPUB3SeriesCollection(
                id: id,
                title: metaElementText(in: tag),
                collectionType: refinedMetaValue(in: tags, id: id, property: "collection-type"),
                groupPosition: refinedMetaValue(in: tags, id: id, property: "group-position"),
                fileAs: refinedMetaValue(in: tags, id: id, property: "file-as")
            )
        }
    }

    private static func refinedMetaValue(in tags: [String], id: String, property: String) -> String? {
        for tag in tags {
            let attrs = attributes(in: tag)
            guard (attrs["refines"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#")) == id,
                  metadataComparisonKey(attrs["property"] ?? "").caseInsensitiveCompare(property) == .orderedSame else {
                continue
            }
            return metaElementText(in: tag)
        }
        return nil
    }

    private static func titleRefinementMetadataMatches(
        _ metadata: SableLibraryEPUBImportMetadata,
        currentOPFText: String
    ) -> Bool {
        guard let title = dublinCoreElements(in: currentOPFText, localName: "title").first,
              metadataComparisonKey(title.value) == metadataComparisonKey(metadata.title),
              let titleID = title.id,
              !titleID.isEmpty else {
            return false
        }

        let tags = metaTags(in: currentOPFText)
        guard metadataComparisonKey(refinedMetaValue(in: tags, id: titleID, property: "title-type") ?? "")
            .caseInsensitiveCompare("main") == .orderedSame else {
            return false
        }

        if let titleSort = metadata.titleSort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !titleSort.isEmpty {
            let epubSort = refinedMetaValue(in: tags, id: titleID, property: "file-as")
            guard metadataComparisonKey(epubSort ?? "")
                .caseInsensitiveCompare(metadataComparisonKey(titleSort)) == .orderedSame else {
                return false
            }
            guard metadataComparisonKey(namedMetaContent(in: currentOPFText, name: "calibre:title_sort") ?? "")
                .caseInsensitiveCompare(metadataComparisonKey(titleSort)) == .orderedSame else {
                return false
            }
        }

        return true
    }

    private static func subtitleMetadataMatches(
        _ metadata: SableLibraryEPUBImportMetadata,
        currentOPFText: String
    ) -> Bool {
        guard let subtitle = metadata.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subtitle.isEmpty else {
            return true
        }

        return metadataComparisonKey(sablePropertyMetaValue(in: currentOPFText, id: "sable-subtitle") ?? "")
            .caseInsensitiveCompare(metadataComparisonKey(subtitle)) == .orderedSame
    }

    private static func creditMetadataMatches(
        expectedCredits: [SableLibraryEPUBImportCredit],
        currentOPFText: String,
        localName: String
    ) -> Bool {
        let expected = Set(uniqueImportMetadataCredits(expectedCredits).map {
            EPUBImportCreditSnapshot(
                nameKey: metadataComparisonKey($0.name),
                roleCode: $0.role.marcRelatorCode
            )
        })
        guard !expected.isEmpty else { return true }

        let tags = metaTags(in: currentOPFText)
        let current: Set<EPUBImportCreditSnapshot> = Set(dublinCoreElements(in: currentOPFText, localName: localName).compactMap { element in
            guard let id = element.id,
                  let role = refinedMetaValue(in: tags, id: id, property: "role"),
                  !role.isEmpty else {
                return nil
            }
            return EPUBImportCreditSnapshot(
                nameKey: metadataComparisonKey(element.value),
                roleCode: metadataComparisonKey(role)
            )
        })
        return current == expected
    }

    private static func creatorCredits(for metadata: SableLibraryEPUBImportMetadata) -> [SableLibraryEPUBImportCredit] {
        let credits = metadata.creatorCredits
        if !credits.isEmpty {
            return uniqueImportMetadataCredits(credits)
        }

        return uniqueImportMetadataCredits(
            metadata.authors.map { SableLibraryEPUBImportCredit(name: $0, role: .author) }
                + metadata.artists.map { SableLibraryEPUBImportCredit(name: $0, role: .artist) }
        )
    }

    private static func contributorCredits(for metadata: SableLibraryEPUBImportMetadata) -> [SableLibraryEPUBImportCredit] {
        let credits = metadata.contributorCredits
        if !credits.isEmpty {
            return uniqueImportMetadataCredits(credits)
        }

        return uniqueImportMetadataCredits(
            metadata.contributors.map { SableLibraryEPUBImportCredit(name: $0, role: .contributor) }
        )
    }

    private static func sableISBNIdentifierTypesMatch(
        _ metadata: SableLibraryEPUBImportMetadata,
        currentOPFText: String
    ) -> Bool {
        let expectedISBNIDs = Set(importIdentifiers(from: metadata).compactMap { id, _ in
            id.hasPrefix("sable-isbn-13-") ? id : nil
        })
        guard !expectedISBNIDs.isEmpty else { return true }
        return currentSableISBNIdentifierTypeRefinements(in: currentOPFText) == expectedISBNIDs
    }

    private static func currentSableISBNIdentifierTypeRefinements(in text: String) -> Set<String> {
        Set(metaTags(in: text).compactMap { tag in
            let attrs = attributes(in: tag)
            let refines = (attrs["refines"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard refines.hasPrefix("sable-isbn-13-"),
                  metadataComparisonKey(attrs["property"] ?? "").caseInsensitiveCompare("identifier-type") == .orderedSame,
                  metadataComparisonKey(attrs["scheme"] ?? "").caseInsensitiveCompare("onix:codelist5") == .orderedSame,
                  metadataComparisonKey(metaElementText(in: tag)) == "15" else {
                return nil
            }
            return refines
        })
    }

    private static func importDateText(releaseDate: Int?, releaseYear: Int?) -> String? {
        if let releaseDate, releaseDate >= 10_000 {
            let year = releaseDate / 10_000
            let month = (releaseDate / 100) % 100
            let day = releaseDate % 100
            if (1...12).contains(month), (1...31).contains(day) {
                return String(format: "%04d-%02d-%02d", year, month, day)
            }
            return "\(year)"
        }
        return releaseYear.map { "\($0)" }
    }

    private static func normalizedLanguage(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !cleaned.isEmpty else { return nil }
        switch cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() {
        case "english", "eng":
            return "en"
        case "french", "français", "francais", "fre":
            return "fr"
        case "japanese", "jpn":
            return "ja"
        case "korean", "kor":
            return "ko"
        case "chinese", "chi", "zho":
            return "zh"
        default:
            return cleaned
        }
    }

    private static func uniqueImportMetadataStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private static func metadataValuesMatch(_ current: [String], _ expected: [String]) -> Bool {
        let currentKeys = Set(uniqueImportMetadataStrings(current).map(metadataComparisonKey))
        let expectedKeys = Set(uniqueImportMetadataStrings(expected).map(metadataComparisonKey))
        return currentKeys == expectedKeys
    }

    private static func subjectMetadataValuesMatch(_ current: [String], _ expected: [String]) -> Bool {
        let currentKeys = Set(uniqueImportMetadataStrings(current).map { metadataComparisonKey(cleanedEPUBSubjectTerm($0)) })
        let expectedKeys = Set(uniqueImportMetadataStrings(expected).map { metadataComparisonKey(cleanedEPUBSubjectTerm($0)) })
        return currentKeys == expectedKeys
    }

    private static func uniqueImportMetadataCredits(_ credits: [SableLibraryEPUBImportCredit]) -> [SableLibraryEPUBImportCredit] {
        var seen = Set<String>()
        return credits.compactMap { credit in
            let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let key = "\(credit.role.rawValue)|\(metadataComparisonKey(name).lowercased())"
            guard seen.insert(key).inserted else { return nil }
            return SableLibraryEPUBImportCredit(name: name, role: credit.role)
        }
    }

    private static func metadataComparisonKey(_ value: String) -> String {
        xmlUnescapedText(value)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentDublinCoreValues(in text: String, localName: String) -> [String] {
        xmlElementBlocks(named: localName, in: text).map { block in
            xmlUnescapedText(block.body)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func dublinCoreElements(in text: String, localName: String) -> [DublinCoreElementSnapshot] {
        dublinCoreElementTags(in: text, localName: localName).map { tag in
            DublinCoreElementSnapshot(
                id: attributes(in: tag)["id"],
                value: dublinCoreElementText(in: tag, localName: localName)
            )
        }
    }

    private static func dublinCoreElementTags(in text: String, localName: String) -> [String] {
        let blocks = xmlElementBlocks(named: localName, in: text).map(\.fullText)
        let selfClosing = xmlStartTags(named: localName, in: text).filter { tag in
            tag.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/>")
        }
        return blocks + selfClosing
    }

    private static func dublinCoreElementText(in tag: String, localName: String) -> String {
        xmlElementBlocks(named: localName, in: tag).first
            .map { xmlUnescapedText($0.body).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
    }

    private static let legacyDublinCoreAttributeNames: Set<String> = [
        "display-seq",
        "file-as",
        "opf:display-seq",
        "opf:file-as",
        "opf:role",
        "opf:scheme",
        "role",
        "scheme"
    ]

    private static func legacyDublinCoreAttributeElementTags(in text: String) -> [String] {
        ["creator", "contributor", "publisher", "identifier", "title"].flatMap { localName in
            dublinCoreElementTags(in: text, localName: localName).filter { tag in
                attributes(in: tag).keys.contains { legacyDublinCoreAttributeNames.contains($0.lowercased()) }
            }
        }
    }

    private static func normalizingLegacyDublinCoreAttributes(in text: String) -> String {
        var result = text
        var existingIDs = opfElementIDs(in: result)
        for localName in ["creator", "contributor", "publisher", "identifier", "title"] {
            let tags = dublinCoreElementTags(in: result, localName: localName)
            for tag in tags {
                let attrs = attributes(in: tag)
                guard attrs.keys.contains(where: { legacyDublinCoreAttributeNames.contains($0.lowercased()) }),
                      let openingTag = dublinCoreOpeningTag(in: tag, localName: localName) else {
                    continue
                }

                let id = usableMetadataID(
                    existingID: attrs["id"],
                    localName: localName,
                    existingIDs: &existingIDs
                )
                var normalizedOpeningTag = openingTag
                for name in legacyDublinCoreAttributeNames where attrs[name] != nil {
                    normalizedOpeningTag = tagRemovingAttribute(normalizedOpeningTag, name: name)
                }
                if attrs["id"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    normalizedOpeningTag = tagSettingAttribute(normalizedOpeningTag, name: "id", value: id)
                }

                var normalizedTag = tag.replacingOccurrences(of: openingTag, with: normalizedOpeningTag)
                let refinementRows = legacyDublinCoreRefinementRows(
                    for: localName,
                    id: id,
                    attrs: attrs
                )
                if !refinementRows.isEmpty {
                    normalizedTag += "\n" + refinementRows.joined(separator: "\n")
                }
                result = result.replacingOccurrences(of: tag, with: normalizedTag)
            }
        }
        return result
    }

    private static func dublinCoreOpeningTag(in tag: String, localName: String) -> String? {
        let name = NSRegularExpression.escapedPattern(for: localName)
        return matches(
            in: tag,
            pattern: #"<(?:[A-Za-z0-9_]+:)?"# + name + #"\b[^>]*>"#
        ).first
    }

    private static func usableMetadataID(
        existingID: String?,
        localName: String,
        existingIDs: inout Set<String>
    ) -> String {
        if let existingID = existingID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingID.isEmpty {
            existingIDs.insert(existingID)
            return existingID
        }

        let base = "sable-\(localName)-legacy"
        if existingIDs.insert(base).inserted {
            return base
        }
        for index in 2...999 {
            let candidate = "\(base)-\(index)"
            if existingIDs.insert(candidate).inserted {
                return candidate
            }
        }
        let fallback = "\(base)-\(UUID().uuidString)"
        existingIDs.insert(fallback)
        return fallback
    }

    private static func legacyDublinCoreRefinementRows(
        for localName: String,
        id: String,
        attrs: [String: String]
    ) -> [String] {
        var rows: [String] = []
        if ["creator", "contributor", "publisher"].contains(localName),
           let role = legacyAttributeValue(["opf:role", "role"], in: attrs),
           let code = normalizedLegacyRoleCode(role) {
            rows.append("    <meta refines=\"#\(xmlEscapedAttribute(id))\" property=\"role\" scheme=\"marc:relators\">\(xmlEscapedText(code))</meta>")
        }

        if ["creator", "contributor", "publisher", "title"].contains(localName),
           let fileAs = legacyAttributeValue(["opf:file-as", "file-as"], in: attrs) {
            rows.append("    <meta refines=\"#\(xmlEscapedAttribute(id))\" property=\"file-as\">\(xmlEscapedText(fileAs))</meta>")
        }

        if ["creator", "contributor", "publisher", "title"].contains(localName),
           let displaySeq = legacyAttributeValue(["opf:display-seq", "display-seq"], in: attrs),
           !displaySeq.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append("    <meta refines=\"#\(xmlEscapedAttribute(id))\" property=\"display-seq\">\(xmlEscapedText(displaySeq))</meta>")
        }

        if localName == "identifier",
           let scheme = legacyAttributeValue(["opf:scheme", "scheme"], in: attrs),
           !scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(legacyIdentifierTypeRefinementRow(id: id, scheme: scheme))
        }
        return rows
    }

    private static func legacyAttributeValue(_ names: [String], in attrs: [String: String]) -> String? {
        for name in names {
            if let value = attrs[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return xmlUnescapedText(value)
            }
        }
        return nil
    }

    private static func normalizedLegacyRoleCode(_ value: String) -> String? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.range(of: #"^[a-z][a-z0-9]{1,8}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned
    }

    private static func legacyIdentifierTypeRefinementRow(id: String, scheme: String) -> String {
        let cleanScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cleanScheme
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .lowercased()
        if key.contains("isbn") {
            return "    <meta refines=\"#\(xmlEscapedAttribute(id))\" property=\"identifier-type\" scheme=\"onix:codelist5\">15</meta>"
        }
        return "    <meta refines=\"#\(xmlEscapedAttribute(id))\" property=\"identifier-type\">\(xmlEscapedText(cleanScheme))</meta>"
    }

    private static func nonNamespacedMetadataMetaTags(in text: String) -> [String] {
        metaTags(in: text).filter { tag in
            attributeValue("xmlns", in: attributes(in: tag)) == ""
        }
    }

    private static func normalizingNonNamespacedMetadataMetaTags(in text: String) -> String {
        nonNamespacedMetadataMetaTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: tagRemovingAttribute(tag, name: "xmlns"))
        }
    }

    private static func opfElementIDs(in text: String) -> Set<String> {
        Set(matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b[^>]*>"#
        ).compactMap { tag in
            attributes(in: tag)["id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
    }

    private static func orphanedRefinementMetaTags(in text: String) -> [String] {
        let ids = opfElementIDs(in: text)
        return metaTags(in: text).filter { tag in
            let refinesID = (attributes(in: tag)["refines"] ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !refinesID.isEmpty && !ids.contains(refinesID)
        }
    }

    private static func removingOrphanedRefinementMeta(in text: String) -> String {
        orphanedRefinementMetaTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func invalidTypedRefinementMetaTags(in text: String) -> [String] {
        let targetElementNames = opfElementNamesByID(in: text)
        return metaTags(in: text).filter { tag in
            let attrs = attributes(in: tag)
            let property = metadataComparisonKey(attrs["property"] ?? "").lowercased()
            guard ["identifier-type", "role", "title-type"].contains(property) else {
                return false
            }

            let refinesID = (attrs["refines"] ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !refinesID.isEmpty,
                  let targetName = targetElementNames[refinesID] else {
                return false
            }

            switch property {
            case "identifier-type":
                return !["identifier", "source"].contains(targetName)
            case "role":
                return !["creator", "contributor", "publisher"].contains(targetName)
            case "title-type":
                return targetName != "title"
            default:
                return false
            }
        }
    }

    private static func removingInvalidTypedRefinementMeta(in text: String) -> String {
        invalidTypedRefinementMetaTags(in: text).reduce(text) { partial, tag in
            partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func opfElementNamesByID(in text: String) -> [String: String] {
        var names: [String: String] = [:]
        let tags = matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?[A-Za-z][A-Za-z0-9_.:-]*\b[^>]*>"#
        )
        for tag in tags {
            guard let id = attributes(in: tag)["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  let localName = elementLocalName(inOpeningTag: tag) else {
                continue
            }
            names[id] = localName
        }
        return names
    }

    private static func elementLocalName(inOpeningTag tag: String) -> String? {
        guard let rawName = firstMatch(
            in: tag,
            pattern: #"<\s*([A-Za-z_][A-Za-z0-9_.:-]*)"#
        ) else {
            return nil
        }
        return rawName.split(separator: ":").last.map { String($0).lowercased() }
    }

    private static func packageUniqueIdentifierValue(in text: String) -> String? {
        guard let packageTag = matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?package\b[^>]*>"#
        ).first else {
            return nil
        }

        let uniqueID = attributes(in: packageTag)["unique-identifier"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let uniqueID, !uniqueID.isEmpty {
            for element in dublinCoreElements(in: text, localName: "identifier") where element.id == uniqueID {
                return element.value
            }
        }
        return dublinCoreElements(in: text, localName: "identifier").first?.value
    }

    private static func ncxIdentifierValue(in text: String) -> String? {
        for tag in metaTags(in: text) {
            let attrs = attributes(in: tag)
            guard metadataComparisonKey(attrs["name"] ?? "").caseInsensitiveCompare("dtb:uid") == .orderedSame else {
                continue
            }
            return xmlUnescapedText(attrs["content"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func currentSableMetadataIdentifiers(in text: String) -> Set<String> {
        let pattern = #"<(?:[A-Za-z0-9_]+:)?identifier\b[^>]*>([\s\S]*?)</(?:[A-Za-z0-9_]+:)?identifier>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        var identifiers = Set<String>()
        for match in regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            guard let fullRange = Range(match.range, in: text),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let tag = String(text[fullRange])
            let id = xmlUnescapedText(attributes(in: tag)["id"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard id.range(of: #"^sable-(?:isbn|source|release|link)"#, options: [.regularExpression, .caseInsensitive]) != nil else {
                continue
            }
            let value = xmlUnescapedText(String(text[valueRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            identifiers.insert("\(id)|\(value)")
        }
        return identifiers
    }

    private static func removingRefinedMeta(in text: String, refinesIDs: Set<String>) -> String {
        guard !refinesIDs.isEmpty else { return text }
        return metaTags(in: text).reduce(text) { partial, tag in
            let refinesID = (attributes(in: tag)["refines"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return refinesIDs.contains(refinesID) ? partial.replacingOccurrences(of: tag, with: "\n") : partial
        }
    }

    private static func removingSableImportIdentifierRefinements(in text: String) -> String {
        metaTags(in: text).reduce(text) { partial, tag in
            let refinesID = (attributes(in: tag)["refines"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let refinesSableImportIdentifier =
                refinesID.range(
                    of: #"^sable-(?:isbn|source|release|link)"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            return refinesSableImportIdentifier ? partial.replacingOccurrences(of: tag, with: "\n") : partial
        }
    }

    private static func removingSablePropertyMeta(in text: String, id: String) -> String {
        metaTags(in: text).reduce(text) { partial, tag in
            guard metadataComparisonKey(attributes(in: tag)["id"] ?? "").caseInsensitiveCompare(id) == .orderedSame else {
                return partial
            }
            return partial.replacingOccurrences(of: tag, with: "\n")
        }
    }

    private static func namedMetaContent(in text: String, name: String) -> String? {
        for tag in metaTags(in: text) {
            let attrs = attributes(in: tag)
            guard let currentName = attrs["name"],
                  metadataComparisonKey(currentName).caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }
            return xmlUnescapedText(attrs["content"] ?? "")
        }
        return nil
    }

    private static func sablePropertyMetaValue(in text: String, id: String) -> String? {
        for tag in metaTags(in: text) {
            let attrs = attributes(in: tag)
            guard metadataComparisonKey(attrs["id"] ?? "").caseInsensitiveCompare(id) == .orderedSame else {
                continue
            }
            return metaElementText(in: tag)
        }
        return nil
    }

    private static func propertyMetaValues(in text: String, property: String) -> [String] {
        metaTags(in: text).compactMap { tag in
            let attrs = attributes(in: tag)
            guard metadataComparisonKey(attrs["property"] ?? "").caseInsensitiveCompare(property) == .orderedSame else {
                return nil
            }
            return metaElementText(in: tag)
        }
    }

    private static func metaElementText(in tag: String) -> String {
        firstMatch(in: tag, pattern: #"<(?:[A-Za-z0-9_]+:)?meta\b[^>]*>([\s\S]*?)</(?:[A-Za-z0-9_]+:)?meta>"#)
            .map { xmlUnescapedText($0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    private static func metaTags(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?meta\b[^>]*?/\s*>|<(?:[A-Za-z0-9_]+:)?meta\b[^>]*>[\s\S]*?</(?:[A-Za-z0-9_]+:)?meta>"#
        )
    }

    private static func xmlEscapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlEscapedAttribute(_ value: String) -> String {
        xmlEscapedText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func xmlUnescapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func encryptedResourcePaths(inEncryptionXML text: String) -> [String] {
        var seen: Set<String> = []
        var paths: [String] = []
        for tag in matches(in: text, pattern: #"<(?:[A-Za-z0-9_]+:)?CipherReference\b[^>]*>"#) {
            let attrs = attributes(in: tag)
            let uri = attrs.first { key, _ in
                key.localizedCaseInsensitiveCompare("URI") == .orderedSame
            }?.value
            guard let uri else { continue }
            let normalized = normalizedEPUBResourcePath(xmlUnescapedText(uri))
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            paths.append(normalized)
        }
        return paths
    }

    private static func normalizedEPUBResourcePath(_ value: String) -> String {
        let unescaped = xmlUnescapedText(value)
        let withoutFragment = unescaped.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? unescaped
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutFragment
        let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
        var path = decoded.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") {
            path.removeFirst()
        }
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path.lowercased()
    }

    private static func isFontResourcePath(_ path: String) -> Bool {
        ["otf", "ttf", "woff", "woff2"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func firstManifestImageID(in itemTags: [String]) -> String? {
        for tag in itemTags {
            let attrs = attributes(in: tag)
            guard let id = attrs["id"] else { continue }

            let href = (attrs["href"] ?? "").lowercased()
            let mediaType = (attrs["media-type"] ?? "").lowercased()

            let looksLikeImage =
                mediaType.hasPrefix("image/")
                || href.hasSuffix(".jpg")
                || href.hasSuffix(".jpeg")
                || href.hasSuffix(".png")
                || href.hasSuffix(".webp")
                || href.hasSuffix(".gif")

            if looksLikeImage {
                return id
            }
        }

        return nil
    }

    private static func patchNCXFiles(
        in unpackedURL: URL,
        packageID: String?,
        opfPath: String,
        opfText: String,
        fileManager: FileManager
    ) throws {
        let entries = Array(try unpackedEntryNames(in: unpackedURL, fileManager: fileManager))
        let existingEntries = Set(entries.map(normalizedEPUBResourcePath))
        let entriesByResolvedFilePath = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry -> (String, String)? in
                guard let url = try? safeUnpackedURL(for: entry, in: unpackedURL) else { return nil }
                return (normalizedFilePath(url.resolvingSymlinksInPath()), entry)
            }
        )
        let allManifestItems = epubManifestItems(in: opfText, opfPath: opfPath)
        let ncxManifestItems = allManifestItems.filter { item in
            item.mediaType.lowercased() == "application/x-dtbncx+xml"
                || URL(fileURLWithPath: item.href).pathExtension.lowercased() == "ncx"
        }
        let manifestItems = allManifestItems
            .filter { item in
                manifestItemIsOPSContentDocument(item)
                    && existingEntries.contains(normalizedEPUBResourcePath(item.entryPath))
            }
        let manifestItemsByFileName = Dictionary(grouping: manifestItems) { item in
            URL(fileURLWithPath: normalizedEPUBResourcePath(item.entryPath)).lastPathComponent
        }

        guard let enumerator = fileManager.enumerator(
            at: unpackedURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "ncx" {
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let resolvedPath = normalizedFilePath(url.resolvingSymlinksInPath())
            let relativePath = ncxManifestItems.first {
                URL(fileURLWithPath: $0.entryPath).lastPathComponent.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame
            }?.entryPath
                ?? entriesByResolvedFilePath[resolvedPath]
                ?? relativeUnpackedPath(for: url, root: unpackedURL)
                ?? url.lastPathComponent
            let identifierPatched = packageID.map {
                patchingNCXIdentifier(in: text, packageID: $0)
            } ?? text
            let contentPatched = patchingNCXContentSources(
                in: identifierPatched,
                ncxEntry: relativePath,
                existingEntries: existingEntries,
                manifestItemsByFileName: manifestItemsByFileName
            )
            let fragmentPatched = try repairingNCXContentFragments(
                in: contentPatched,
                ncxEntry: relativePath,
                existingEntries: existingEntries,
                unpackedURL: unpackedURL,
                fileManager: fileManager
            )
            let patched = renumberingNCXPlayOrder(in: removingBrokenNCXPageLists(in: repairingIncompleteNCXNavPoints(in: fragmentPatched)))
            if patched != text {
                text = patched
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func patchingNCXIdentifier(in text: String, packageID: String) -> String {
        var result = text
        var patchedExistingUID = false
        for tag in metaTags(in: text) {
            let attrs = attributes(in: tag)
            guard metadataComparisonKey(attrs["name"] ?? "").caseInsensitiveCompare("dtb:uid") == .orderedSame else {
                continue
            }

            let replacement = tagSettingAttribute(tag, name: "content", value: packageID)
            result = result.replacingOccurrences(of: tag, with: replacement)
            patchedExistingUID = true
        }

        if patchedExistingUID {
            return result
        }

        guard let headRange = result.range(
            of: #"<(?:[A-Za-z0-9_]+:)?head\b[^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return result
        }

        result.insert(
            contentsOf: "\n    <meta name=\"dtb:uid\" content=\"\(xmlEscapedAttribute(packageID))\" />",
            at: headRange.upperBound
        )
        return result
    }

    private static func patchingNCXContentSources(
        in text: String,
        ncxEntry: String,
        existingEntries: Set<String>,
        manifestItemsByFileName: [String: [EPUBManifestItem]]
    ) -> String {
        repairableNCXContentSourceTags(
            in: text,
            ncxEntry: ncxEntry,
            existingEntries: existingEntries,
            manifestItemsByFileName: manifestItemsByFileName
        ).reduce(text) { partial, repair in
            partial.replacingOccurrences(
                of: repair.tag,
                with: tagSettingAttribute(repair.tag, name: "src", value: repair.replacementSource)
            )
        }
    }

    private static func repairingNCXContentFragments(
        in text: String,
        ncxEntry: String,
        existingEntries: Set<String>,
        unpackedURL: URL,
        fileManager: FileManager
    ) throws -> String {
        try repairableNCXContentFragmentTags(
            in: text,
            ncxEntry: ncxEntry,
            entryExists: { existingEntries.contains(normalizedEPUBResourcePath($0)) },
            textForEntry: {
                try unpackedEntryText($0, in: unpackedURL, fileManager: fileManager)
            }
        ).reduce(text) { partial, repair in
            partial.replacingOccurrences(
                of: repair.tag,
                with: tagSettingAttribute(repair.tag, name: "src", value: repair.replacementSource)
            )
        }
    }

    private static func unpackedEntryText(
        _ entry: String,
        in unpackedURL: URL,
        fileManager: FileManager
    ) throws -> String? {
        let url = try safeUnpackedURL(for: entry, in: unpackedURL)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func ncxPlayOrderNeedsRepair(in text: String) -> Bool {
        let orderedTags = ncxOrderedPlayOrderTags(in: text)
        guard !orderedTags.isEmpty else { return false }
        for (index, tag) in orderedTags.enumerated() {
            let expected = "\(index + 1)"
            let value = attributeValue("playOrder", in: attributes(in: tag))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value != expected {
                return true
            }
        }
        if ncxPlayOrderHasTargetConflicts(in: orderedTags) {
            return true
        }
        return false
    }

    private static func renumberingNCXPlayOrder(in text: String) -> String {
        let orderedTags = ncxOrderedPlayOrderTags(in: text)
        guard !orderedTags.isEmpty else { return text }

        var result = text
        for (index, tag) in orderedTags.enumerated() {
            let replacement = tagSettingAttribute(tag, name: "playOrder", value: "\(index + 1)")
            if replacement != tag {
                result = result.replacingOccurrences(of: tag, with: replacement)
            }
        }
        return result
    }

    private static func ncxOrderedPlayOrderTags(in text: String) -> [String] {
        matches(
            in: text,
            pattern: #"<(?:[A-Za-z0-9_]+:)?(?:navPoint|navTarget|pageTarget)\b[^>]*>"#
        )
    }

    private static func ncxPlayOrderHasTargetConflicts(in tags: [String]) -> Bool {
        var targetByPlayOrder: [String: String] = [:]
        var playOrdersByTarget: [String: Set<String>] = [:]

        for tag in tags {
            let attrs = attributes(in: tag)
            guard let playOrder = attributeValue("playOrder", in: attrs)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !playOrder.isEmpty else {
                continue
            }
            guard let target = attributeValue("src", in: attrs)
                .map({ hrefWithoutFragment(xmlUnescapedText($0)).trimmingCharacters(in: .whitespacesAndNewlines) }),
                  !target.isEmpty else {
                continue
            }
            if let existingTarget = targetByPlayOrder[playOrder],
               metadataComparisonKey(existingTarget) != metadataComparisonKey(target) {
                return true
            }
            targetByPlayOrder[playOrder] = target
            playOrdersByTarget[target, default: []].insert(playOrder)
        }

        return playOrdersByTarget.values.contains { $0.count > 1 }
    }

    private static func incompleteNCXNavPointRepairCount(in text: String) -> Int {
        incompleteNCXNavPointBlocks(in: text).count
    }

    private static func repairingIncompleteNCXNavPoints(in text: String) -> String {
        let blocks = incompleteNCXNavPointBlocks(in: text)
        guard !blocks.isEmpty else { return text }

        var result = text
        for block in blocks.reversed() {
            guard let range = Range(block.range, in: result) else { continue }
            if let inheritedContent = firstNCXContentTag(in: block.body) {
                let replacement = insertingDirectNCXContent(in: block, contentTag: inheritedContent)
                result.replaceSubrange(range, with: replacement)
            } else {
                result.replaceSubrange(range, with: "\n")
            }
        }
        return result
    }

    private static func incompleteNCXNavPointBlocks(in text: String) -> [XMLElementBlock] {
        xmlElementBlocks(named: "navPoint", in: text).filter { block in
            directNCXContentTag(in: block) == nil
        }
    }

    private static func directNCXContentTag(in block: XMLElementBlock) -> String? {
        let directBody = ncxBodyBeforeNestedNavPoint(block.body)
        return firstNCXContentTag(in: directBody)
    }

    private static func firstNCXContentTag(in text: String) -> String? {
        xmlStartTags(named: "content", in: text).first
    }

    private static func ncxBodyBeforeNestedNavPoint(_ body: String) -> String {
        guard let nestedRange = body.range(
            of: #"<(?:[A-Za-z0-9_]+:)?navPoint\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return body
        }
        return String(body[..<nestedRange.lowerBound])
    }

    private static func insertingDirectNCXContent(in block: XMLElementBlock, contentTag: String) -> String {
        let insertion = "\n    \(contentTag)"
        if let navLabel = xmlElementBlocks(named: "navLabel", in: block.body).first,
           let range = block.fullText.range(of: navLabel.fullText) {
            return String(block.fullText[..<range.upperBound]) + insertion + String(block.fullText[range.upperBound...])
        }
        guard let openingRange = block.fullText.range(of: block.openingTag) else {
            return block.fullText
        }
        return String(block.fullText[..<openingRange.upperBound]) + insertion + String(block.fullText[openingRange.upperBound...])
    }

    private static func ncxPageListNeedsRepair(in text: String) -> Bool {
        let pageLists = xmlElementBlocks(named: "pageList", in: text)
        guard !pageLists.isEmpty else { return false }
        if pageLists.contains(where: { attributes(in: $0.openingTag)["class"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }) {
            return true
        }
        let pageTargetTags = xmlStartTags(named: "pageTarget", in: text)
        guard !pageTargetTags.isEmpty else { return false }
        return ncxPlayOrderHasTargetConflicts(in: ncxOrderedPlayOrderTags(in: text))
    }

    private static func removingBrokenNCXPageLists(in text: String) -> String {
        guard ncxPageListNeedsRepair(in: text) else { return text }
        return xmlElementBlocks(named: "pageList", in: text).reduce(text) { partial, block in
            partial.replacingOccurrences(of: block.fullText, with: "\n")
        }
    }

    private static func validate(epubURL: URL) throws {
        let archive = try archiveSnapshot(for: epubURL)
        let entries = archive.entries
        guard entries.first == "mimetype" else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("mimetype is not first")
        }
        guard let mimetype = try entryText("mimetype", in: archive),
              mimetype.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("mimetype content is not exact")
        }
        guard entries.contains(containerEntry) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("META-INF/container.xml is missing")
        }

        guard let opfPath = try opfPath(in: archive),
              entries.contains(opfPath),
              let opfText = try entryText(opfPath, in: archive) else {
            throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("OPF package path is missing or unreadable")
        }

        let cover = coverAnalysis(in: opfText)
        if cover.hasEPUB2CoverMeta || cover.hasEPUB3CoverImage {
            guard cover.hasEPUB2CoverMeta else {
                throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("EPUB2 cover meta is missing or points to a non-image manifest item")
            }
            guard cover.hasEPUB3CoverImage else {
                throw SableLibraryAppleBooksCompatibilityRepairError.invalidRepairedEPUB("EPUB3 cover-image marker is missing")
            }
        }

        _ = try runProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-t", epubURL.path(percentEncoded: false)],
            currentDirectory: nil
        )
    }

    private static func insertBeforeMetadataClose(in text: String, insertion: String) -> String {
        guard let range = text.range(
            of: #"</(?:[A-Za-z0-9_]+:)?metadata\s*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return text
        }
        return String(text[..<range.lowerBound]) + insertion + String(text[range.lowerBound...])
    }

    private static func insertBeforeManifestClose(in text: String, insertion: String) -> String {
        guard let range = text.range(
            of: #"</(?:[A-Za-z0-9_]+:)?manifest\s*>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return text
        }
        return String(text[..<range.lowerBound]) + insertion + String(text[range.lowerBound...])
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func xmlStartTags(named localName: String, in text: String) -> [String] {
        xmlStartTagMatches(named: localName, in: text).map(\.tag)
    }

    private static func xmlElementBlocks(named localName: String, in text: String) -> [XMLElementBlock] {
        xmlStartTagMatches(named: localName, in: text).compactMap { match in
            let trimmedOpening = match.tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOpening.hasSuffix("/>"),
                  let openingRange = Range(match.range, in: text) else {
                return nil
            }

            let closingPattern = #"</\s*"# + NSRegularExpression.escapedPattern(for: match.tagName) + #"\s*>"#
            guard let closingRegex = try? NSRegularExpression(pattern: closingPattern, options: [.caseInsensitive]) else {
                return nil
            }
            let searchRange = NSRange(openingRange.upperBound..<text.endIndex, in: text)
            guard let closingMatch = closingRegex.firstMatch(in: text, range: searchRange),
                  let closingRange = Range(closingMatch.range, in: text) else {
                return nil
            }

            let fullRange = NSRange(openingRange.lowerBound..<closingRange.upperBound, in: text)
            return XMLElementBlock(
                range: fullRange,
                tagName: match.tagName,
                openingTag: match.tag,
                body: String(text[openingRange.upperBound..<closingRange.lowerBound]),
                fullText: String(text[openingRange.lowerBound..<closingRange.upperBound])
            )
        }
    }

    private static func firstElementText(named localName: String, in text: String) -> String? {
        xmlElementBlocks(named: localName, in: text).first?.body
    }

    private static func xmlStartTagMatches(
        named localName: String,
        in text: String
    ) -> [(range: NSRange, tag: String, tagName: String)] {
        let name = NSRegularExpression.escapedPattern(for: localName)
        let pattern = #"<\s*((?:[A-Za-z0-9_]+:)?"# + name + #")\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: text),
                  let nameRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return (
                range: match.range,
                tag: String(text[fullRange]),
                tagName: String(text[nameRange])
            )
        }
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]

        var index = tag.startIndex
        while index < tag.endIndex {
            guard attributeNameCanStart(tag[index]) else {
                tag.formIndex(after: &index)
                continue
            }

            let keyStart = index
            tag.formIndex(after: &index)
            while index < tag.endIndex, attributeNameCanContinue(tag[index]) {
                tag.formIndex(after: &index)
            }
            let keyEnd = index

            var lookahead = index
            skipAttributeWhitespace(in: tag, from: &lookahead)
            guard lookahead < tag.endIndex, tag[lookahead] == "=" else {
                index = keyStart
                tag.formIndex(after: &index)
                continue
            }
            tag.formIndex(after: &lookahead)
            skipAttributeWhitespace(in: tag, from: &lookahead)
            guard lookahead < tag.endIndex,
                  tag[lookahead] == "\"" || tag[lookahead] == "'" else {
                index = lookahead
                continue
            }

            let quote = tag[lookahead]
            tag.formIndex(after: &lookahead)
            let valueStart = lookahead
            while lookahead < tag.endIndex, tag[lookahead] != quote {
                tag.formIndex(after: &lookahead)
            }
            guard lookahead < tag.endIndex else {
                break
            }

            result[String(tag[keyStart..<keyEnd])] = String(tag[valueStart..<lookahead])
            tag.formIndex(after: &lookahead)
            index = lookahead
        }
        return result
    }

    private static func skipAttributeWhitespace(in text: String, from index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            text.formIndex(after: &index)
        }
    }

    private static func attributeNameCanStart(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 65...90, 97...122, 95, 58:
            return true
        default:
            return false
        }
    }

    private static func attributeNameCanContinue(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 45, 46, 48...57, 58, 65...90, 95, 97...122:
            return true
        default:
            return false
        }
    }

    @discardableResult
    private static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> String {
        let token = UUID().uuidString
        let captureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableProcessOutput-\(token)", isDirectory: true)
        let stdoutURL = captureDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = captureDirectory.appendingPathComponent("stderr.txt")
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: stdoutURL.path(percentEncoded: false), contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path(percentEncoded: false), contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: captureDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed(error.localizedDescription)
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()
        let stdout = String(data: (try? Data(contentsOf: stdoutURL)) ?? Data(), encoding: .utf8) ?? ""
        let stderr = String(data: (try? Data(contentsOf: stderrURL)) ?? Data(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw SableLibraryAppleBooksCompatibilityRepairError.processFailed(stderr.isEmpty ? stdout : stderr)
        }

        return stdout
    }
}
