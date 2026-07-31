//
//  SableLibraryInspectOverviewView.swift
//  Sable's Library
//

import SwiftUI

private struct SableLibraryShelfPreviewBucket: Identifiable {
    var id: String { subShelf.code }
    var shelf: SableLibraryShelfDefinition
    var subShelf: SableLibrarySubShelfDefinition
    var count: Int
    var lowConfidenceCount: Int
    var examples: [String]

    var displayName: String {
        "\(subShelf.displayName)"
    }
}

struct SableLibraryInspectOverviewView: View {
    @Environment(\.sableLibraryPalette) private var palette

    var inspection: LibraryInspection?
    var libraryURL: URL?
    var isWorking: Bool
    @Binding var comicInfoSearchText: String
    @Binding var animeInfoSearchText: String
    var recommendedStage: LibraryPipelineStage?
    var recommendedSafeRowCount = 0
    var onInspect: () -> Void
    var onRunRecommendedAutomation: (LibraryPipelineStage) -> Void = { _ in }
    @State private var isReadingSidecarListExpanded = false
    @State private var isWatchingSidecarListExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inventory & triage")
                        .font(.headline)
                    Text(inspection?.inspectMode.title ?? "Fast local map before specialist lanes")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onInspect) {
                    Label(inspection == nil ? "Scan Inventory" : "Scan Again", systemImage: "magnifyingglass")
                }
                .disabled(libraryURL == nil || isWorking)
            }

            if let inspection {
                inspectionResultLayout(for: inspection)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No inventory has run yet", systemImage: "magnifyingglass")
                        .font(.callout.weight(.medium))
                    Text("Run Scan Inventory to map files, folders, sidecars, and safety markers. Provider refresh, shelf sorting, and metadata cleaning stay asleep until you open those lanes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .sableLibraryPanelSurface()
    }

    private func inspectionResultLayout(for inspection: LibraryInspection) -> some View {
        HStack(alignment: .top, spacing: 16) {
            inspectionMainColumn(for: inspection)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            inspectionInsightColumn(for: inspection)
                .frame(width: 320)
        }
    }

    private func inspectionMainColumn(for inspection: LibraryInspection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SableEagerAdaptiveGrid(
                minimumItemWidth: 132,
                horizontalSpacing: 10,
                verticalSpacing: 10
            ) {
                metricTile("Media files", value: inspection.bookFileCount + inspection.videoFileCount, symbol: "tray.full")
                metricTile("Series/groups", value: inspection.seriesCount + inspection.videoSeriesCount, symbol: "rectangle.stack")
                metricTile("Raw files", value: inspection.looseFileCount, symbol: "tray")
                metricTile("Sidecars to create", value: inspection.missingComicInfoCount + inspection.missingAnimeInfoCount, symbol: "doc.badge.plus")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    inspectionTypeSummary(
                        "Reading types",
                        counts: inspection.readingTypeCounts,
                        emptyText: "No reading series detected yet."
                    )
                    inspectionTypeSummary(
                        "File types",
                        counts: inspection.displayFileTypeCounts,
                        emptyText: "No supported book or video files detected yet."
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    inspectionTypeSummary(
                        "Reading types",
                        counts: inspection.readingTypeCounts,
                        emptyText: "No reading series detected yet."
                    )
                    inspectionTypeSummary(
                        "File types",
                        counts: inspection.displayFileTypeCounts,
                        emptyText: "No supported book or video files detected yet."
                    )
                }
            }

            SableEagerAdaptiveGrid(
                minimumItemWidth: 330,
                horizontalSpacing: 12,
                verticalSpacing: 12
            ) {
                comicInfoInspectSearch(for: inspection)
                if inspection.videoSeriesCount > 0 {
                    animeInfoInspectSearch(for: inspection)
                }
            }
        }
    }

    private func inspectionInsightColumn(for inspection: LibraryInspection) -> some View {
        let shelfBuckets = shelfPreviewBuckets(for: inspection)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Next step", systemImage: "arrow.forward.circle")
                    .font(.subheadline.weight(.semibold))

                Text(inspectionNextStepTitle(for: inspection))
                    .font(.callout.weight(.semibold))

                Text(inspectionNextStepMessage(for: inspection))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recommendedStage {
                    Button {
                        onRunRecommendedAutomation(recommendedStage)
                    } label: {
                        Label(recommendedActionTitle(for: recommendedStage), systemImage: "arrow.forward.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 2)
                    .accessibilityHint(recommendedSafeRowCount > 0 ? "Applies already-safe changes in the recommended area, then refreshes the plan." : "Opens the recommended review area.")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text("Needs attention")
                    .font(.subheadline.weight(.semibold))

                inspectionInsightRow(
                    title: "Sidecars to create",
                    value: inspection.missingComicInfoCount + inspection.missingAnimeInfoCount,
                    detail: "Books are present; metadata notes are not.",
                    symbol: "doc.badge.plus",
                    isWarning: inspection.missingComicInfoCount + inspection.missingAnimeInfoCount > 0
                )
                inspectionInsightRow(
                    title: "Loose files",
                    value: inspection.looseFileCount,
                    detail: "Start here when raw files are waiting.",
                    symbol: "tray",
                    isWarning: inspection.looseFileCount > 0
                )
                inspectionInsightRow(
                    title: "Review clues",
                    value: inspection.duplicateGroupCount + inspection.metadataCandidateCount + inspection.missingNumberCandidateCount,
                    detail: "Provider, duplicate, or naming questions. Specialist lanes wake only when opened.",
                    symbol: "questionmark.circle",
                    isWarning: inspection.duplicateGroupCount + inspection.metadataCandidateCount + inspection.missingNumberCandidateCount > 0
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))

            if !shelfBuckets.isEmpty {
                sortingShelfPreview(buckets: shelfBuckets)
            }

            if !primaryInspectionNotes(for: inspection).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline.weight(.semibold))

                    ForEach(primaryInspectionNotes(for: inspection), id: \.self) { note in
                        Label(note, systemImage: note.localizedCaseInsensitiveContains("cloud") ? "icloud.slash" : "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func inspectionInsightRow(
        title: String,
        value: Int,
        detail: String,
        symbol: String,
        isWarning: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isWarning ? palette.statusWarning : palette.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text("\(value)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isWarning ? palette.statusWarning : palette.textSecondary)
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }

    private func sortingShelfPreview(buckets: [SableLibraryShelfPreviewBucket]) -> some View {
        let totalCount = buckets.reduce(0) { $0 + $1.count }
        let lowConfidenceCount = buckets.reduce(0) { $0 + $1.lowConfidenceCount }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Sorting shelf", systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(totalCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.textSecondary)
            }

            Text(lowConfidenceCount == 0 ? "Local shelf preview is ready." : "\(lowConfidenceCount) low-confidence row\(lowConfidenceCount == 1 ? "" : "s") stay reviewable.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(buckets.prefix(4))) { bucket in
                    sortingShelfRow(bucket)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sorting shelf preview")
    }

    private func sortingShelfRow(_ bucket: SableLibraryShelfPreviewBucket) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(bucket.subShelf.code)
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(palette.accent.opacity(0.12), in: Capsule())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bucket.subShelf.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text("\(bucket.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }

                Text(bucket.examples.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if bucket.lowConfidenceCount > 0 {
                    Text("\(bucket.lowConfidenceCount) review")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.statusWarning)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucket.displayName), \(bucket.count) series")
    }

    private func shelfPreviewBuckets(for inspection: LibraryInspection) -> [SableLibraryShelfPreviewBucket] {
        struct Accumulator {
            var shelf: SableLibraryShelfDefinition
            var subShelf: SableLibrarySubShelfDefinition
            var count = 0
            var lowConfidenceCount = 0
            var examples: [String] = []
        }

        var buckets: [String: Accumulator] = [:]
        for series in inspection.series {
            let title = displayTitle(for: series)
            let suggestion = SableLibraryShelfCatalog.suggestShelf(
                for: SableLibraryShelfCatalogInput(
                    title: title,
                    description: series.shelfDescription,
                    genres: series.genres,
                    themes: series.themes,
                    tags: series.tags,
                    contentWarnings: series.contentWarnings,
                    mediaType: series.mediaType
                )
            )

            var bucket = buckets[suggestion.subShelf.code] ?? Accumulator(
                shelf: suggestion.shelf,
                subShelf: suggestion.subShelf
            )
            bucket.count += 1
            if suggestion.confidenceLevel == .low || suggestion.confidenceLevel == .needsReview {
                bucket.lowConfidenceCount += 1
            }
            if bucket.examples.count < 2 {
                bucket.examples.append(title)
            }
            buckets[suggestion.subShelf.code] = bucket
        }

        return buckets.values
            .map {
                SableLibraryShelfPreviewBucket(
                    shelf: $0.shelf,
                    subShelf: $0.subShelf,
                    count: $0.count,
                    lowConfidenceCount: $0.lowConfidenceCount,
                    examples: $0.examples
                )
            }
            .sorted { first, second in
                if first.count != second.count {
                    return first.count > second.count
                }
                return first.displayName < second.displayName
            }
    }

    private func inspectionNextStepTitle(for inspection: LibraryInspection) -> String {
        if inspection.looseFileCount > 0 {
            return "\(inspection.looseFileCount) raw file\(inspection.looseFileCount == 1 ? "" : "s") can be organized."
        }
        if inspection.missingComicInfoCount + inspection.missingAnimeInfoCount > 0 {
            return "\(inspection.missingComicInfoCount + inspection.missingAnimeInfoCount) sidecar\(inspection.missingComicInfoCount + inspection.missingAnimeInfoCount == 1 ? "" : "s") can be created."
        }
        if inspection.duplicateGroupCount + inspection.metadataCandidateCount + inspection.missingNumberCandidateCount > 0 {
            return "A few choices need review."
        }
        return "Inventory is ready."
    }

    private func inspectionNextStepMessage(for inspection: LibraryInspection) -> String {
        if inspection.looseFileCount > 0 {
            return "Start with obvious local file placement. Sable can sort clear raw files and hold conflicts, merges, and uncertain moves for review."
        }
        if inspection.missingComicInfoCount + inspection.missingAnimeInfoCount > 0 {
            return "The books are present. What is missing is the local ComicInfo metadata note that helps future cleanup, naming, and provider checks."
        }
        if inspection.duplicateGroupCount + inspection.metadataCandidateCount + inspection.missingNumberCandidateCount > 0 {
            return "Open review for the items where a provider match, duplicate, or filename needs judgment."
        }
        return "No urgent inventory issue is standing out. You can inspect again or open a cleanup lane when needed."
    }

    private func recommendedActionTitle(for stage: LibraryPipelineStage) -> String {
        guard recommendedSafeRowCount > 0 else {
            return "Continue to \(stage.title)"
        }

        switch stage {
        case .comicInfo:
            return "Run \(recommendedSafeRowCount) safe sidecar change\(recommendedSafeRowCount == 1 ? "" : "s")"
        case .prepareRawFiles, .canonicalFolders, .canonicalFiles, .epubClinic, .duplicateReview:
            return "Apply \(recommendedSafeRowCount) safe change\(recommendedSafeRowCount == 1 ? "" : "s")"
        case .providerMatches:
            return "Apply \(recommendedSafeRowCount) trusted match\(recommendedSafeRowCount == 1 ? "" : "es")"
        case .covers:
            return "Download covers for \(recommendedSafeRowCount) series"
        case .inspect, .reviewApply:
            return "Run \(recommendedSafeRowCount) safe change\(recommendedSafeRowCount == 1 ? "" : "s")"
        }
    }

    private func primaryInspectionNotes(for inspection: LibraryInspection) -> [String] {
        let priorityTerms = ["cloud", "skipped", "download", "missing", "loose", "duplicate", "review"]
        let priorityNotes = inspection.notes.filter { note in
            priorityTerms.contains { term in
                note.localizedCaseInsensitiveContains(term)
            }
        }

        let notes = priorityNotes.isEmpty ? inspection.notes : priorityNotes
        return Array(notes.prefix(3).map(compactInspectionNote))
    }

    private func compactInspectionNote(_ note: String) -> String {
        if note.localizedCaseInsensitiveContains("cloud-backed"),
           let examplesRange = note.range(of: "Examples:") {
            let leadingText = note[..<examplesRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return leadingText.isEmpty ? "Some cloud-backed files were skipped. Download them in Finder, then inspect again." : leadingText
        }

        if note.count <= 180 {
            return note
        }

        let clipped = String(note.prefix(177)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(clipped)..."
    }

    private func inspectionTypeSummary(_ title: String, counts: [LibraryInspectionTypeCount], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if counts.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                SableEagerAdaptiveGrid(
                    minimumItemWidth: 112,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                ) {
                    ForEach(counts) { row in
                        Text("\(row.count) \(row.label)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func comicInfoInspectSearch(for inspection: LibraryInspection) -> some View {
        let rows = filteredReadingSeries(in: inspection)
        let query = comicInfoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !query.isEmpty
        let shouldShowRows = isSearching || isReadingSidecarListExpanded
        let exampleRows = Array(rows.filter { !$0.hasComicInfo }.prefix(3))
        let displayRows = isSearching ? rows : rows.filter { !$0.hasComicInfo }
        let previewLimit = isSearching ? 8 : 6

        return VStack(alignment: .leading, spacing: 10) {
            inspectSearchHeader(
                title: "Find reading series",
                subtitle: "\(inspection.missingComicInfoCount) need sidecar",
                symbol: "doc.text"
            )

            sidecarStatusSummary(
                presentCount: inspection.comicInfoCount,
                missingCount: inspection.missingComicInfoCount,
                presentLabel: "Already have ComicInfo",
                missingLabel: "Can create safely"
            )

            Text("ComicInfo is the local metadata note. Missing notes can be created safely before provider checks.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SableLibrarySearchField(
                text: $comicInfoSearchText,
                placeholder: "Search reading sidecars"
            )
            .frame(minWidth: 220)
            .accessibilityLabel("Search reading sidecars")
            .accessibilityValue(comicInfoSearchText)

            if rows.isEmpty {
                inspectSearchEmptyState(
                    title: isSearching ? "No matching reading sidecars" : "No reading sidecars to show",
                    query: comicInfoSearchText,
                    fallback: inspection.seriesCount == 0 ? "No reading series were found." : "Try another reading title, path, type, or sidecar status."
                )
            } else if shouldShowRows, !displayRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayRows.prefix(previewLimit)) { series in
                        readingSeriesInspectRow(series)
                    }
                    if displayRows.count > previewLimit {
                        Text(isSearching ? "\(displayRows.count - previewLimit) more matches hidden. Narrow the search to see them." : "Showing missing examples only. Search to find a specific series.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isSearching {
                    Button {
                        isReadingSidecarListExpanded = false
                    } label: {
                        Label("Hide missing examples", systemImage: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else if shouldShowRows {
                inspectSearchEmptyState(
                    title: isSearching ? "No matching reading sidecars" : "No missing reading sidecars",
                    query: comicInfoSearchText,
                    fallback: "All reading series already have ComicInfo. Use search to find a specific title."
                )
            } else {
                if !exampleRows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(exampleRows) { series in
                            sidecarExampleRow(
                                title: displayTitle(for: series),
                                detail: "\(LibraryInspection.readingTypeLabel(for: series)) - \(series.localBookCount) book\(series.localBookCount == 1 ? "" : "s")",
                                status: "Needs sidecar",
                                isMissing: true
                            )
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button {
                            isReadingSidecarListExpanded = true
                        } label: {
                            Label("Show missing examples", systemImage: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Text("Search when you need a specific title.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("All reading series already have ComicInfo. Search when you need a specific title.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func animeInfoInspectSearch(for inspection: LibraryInspection) -> some View {
        let rows = filteredWatchingSeries(in: inspection)
        let query = animeInfoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !query.isEmpty
        let shouldShowRows = isSearching || isWatchingSidecarListExpanded
        let exampleRows = Array(rows.filter { !$0.hasAnimeInfo }.prefix(3))
        let displayRows = isSearching ? rows : rows.filter { !$0.hasAnimeInfo }
        let previewLimit = isSearching ? 8 : 6

        return VStack(alignment: .leading, spacing: 10) {
            inspectSearchHeader(
                title: "Find watching groups",
                subtitle: "\(inspection.missingAnimeInfoCount) need sidecar",
                symbol: "film"
            )

            sidecarStatusSummary(
                presentCount: inspection.animeInfoCount,
                missingCount: inspection.missingAnimeInfoCount,
                presentLabel: "Already have AnimeInfo",
                missingLabel: "Can create safely"
            )

            SableLibrarySearchField(
                text: $animeInfoSearchText,
                placeholder: "Search watching sidecars"
            )
            .frame(minWidth: 220)
            .accessibilityLabel("Search watching sidecars")
            .accessibilityValue(animeInfoSearchText)

            if rows.isEmpty {
                inspectSearchEmptyState(
                    title: isSearching ? "No matching watching sidecars" : "No watching sidecars to show",
                    query: animeInfoSearchText,
                    fallback: inspection.videoSeriesCount == 0 ? "No watching groups were found." : "Try another watching title, path, type, or sidecar status."
                )
            } else if shouldShowRows, !displayRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayRows.prefix(previewLimit)) { series in
                        watchingSeriesInspectRow(series)
                    }
                    if displayRows.count > previewLimit {
                        Text(isSearching ? "\(displayRows.count - previewLimit) more matches hidden. Narrow the search to see them." : "Showing missing examples only. Search to find a specific group.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isSearching {
                    Button {
                        isWatchingSidecarListExpanded = false
                    } label: {
                        Label("Hide missing examples", systemImage: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else if shouldShowRows {
                inspectSearchEmptyState(
                    title: isSearching ? "No matching watching sidecars" : "No missing watching sidecars",
                    query: animeInfoSearchText,
                    fallback: "All watching groups already have AnimeInfo. Use search to find a specific group."
                )
            } else {
                if !exampleRows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(exampleRows) { series in
                            sidecarExampleRow(
                                title: displayTitle(for: series),
                                detail: "\(LibraryInspection.watchingTypeLabel(for: series)) - \(series.localVideoCount) video\(series.localVideoCount == 1 ? "" : "s")",
                                status: "Needs sidecar",
                                isMissing: true
                            )
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button {
                            isWatchingSidecarListExpanded = true
                        } label: {
                            Label("Show missing examples", systemImage: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Text("Search when you need a specific title.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("All watching groups already have AnimeInfo. Search when you need a specific group.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func inspectSearchHeader(title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func inspectSearchEmptyState(title: String, query: String, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "magnifyingglass")
                .font(.caption.weight(.semibold))
            Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : "No rows match \"\(query)\".")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sidecarStatusSummary(
        presentCount: Int,
        missingCount: Int,
        presentLabel: String,
        missingLabel: String
    ) -> some View {
        HStack(spacing: 8) {
            sidecarStatusPill(title: missingLabel, value: missingCount, isEmphasized: missingCount > 0)
            sidecarStatusPill(title: presentLabel, value: presentCount, isEmphasized: false)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func sidecarStatusPill(title: String, value: Int, isEmphasized: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(isEmphasized ? palette.statusWarning : palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isEmphasized ? palette.statusWarning : palette.textSecondary).opacity(0.12), in: Capsule())
    }

    private func sidecarExampleRow(title: String, detail: String, status: String, isMissing: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isMissing ? "doc.badge.plus" : "checkmark.circle")
                .foregroundStyle(isMissing ? palette.statusWarning : palette.statusSuccess)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isMissing ? palette.statusWarning : palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func readingSeriesInspectRow(_ series: LibrarySeriesSnapshot) -> some View {
        inspectionSeriesRow(
            title: displayTitle(for: series),
            path: series.path,
            detail: "\(LibraryInspection.readingTypeLabel(for: series)) - \(series.localBookCount) book\(series.localBookCount == 1 ? "" : "s")",
            sidecarText: series.hasComicInfo ? "Has sidecar" : "Needs sidecar",
            sidecarSymbol: series.hasComicInfo ? "checkmark.circle" : "plus.circle",
            isMissingSidecar: !series.hasComicInfo
        )
    }

    private func watchingSeriesInspectRow(_ series: LibraryVideoSeriesSnapshot) -> some View {
        inspectionSeriesRow(
            title: displayTitle(for: series),
            path: series.path,
            detail: "\(LibraryInspection.watchingTypeLabel(for: series)) - \(series.localVideoCount) video\(series.localVideoCount == 1 ? "" : "s")",
            sidecarText: series.hasAnimeInfo ? "Has sidecar" : "Needs sidecar",
            sidecarSymbol: series.hasAnimeInfo ? "checkmark.circle" : "plus.circle",
            isMissingSidecar: !series.hasAnimeInfo
        )
    }

    private func inspectionSeriesRow(
        title: String,
        path: String,
        detail: String,
        sidecarText: String,
        sidecarSymbol: String,
        isMissingSidecar: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isMissingSidecar ? "doc.badge.plus" : "checkmark.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isMissingSidecar ? palette.statusWarning : palette.statusSuccess)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(path.isEmpty ? "Library root" : path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Label(sidecarText, systemImage: sidecarSymbol)
                .font(.caption2.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isMissingSidecar ? palette.statusWarning : palette.statusSuccess)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func filteredReadingSeries(in inspection: LibraryInspection) -> [LibrarySeriesSnapshot] {
        inspection.series
            .filter { SableLibraryInspectionSearch.matches($0, query: comicInfoSearchText) }
            .sorted { first, second in
                if first.hasComicInfo != second.hasComicInfo {
                    return !first.hasComicInfo && second.hasComicInfo
                }
                return displayTitle(for: first).localizedCaseInsensitiveCompare(displayTitle(for: second)) == .orderedAscending
            }
    }

    private func filteredWatchingSeries(in inspection: LibraryInspection) -> [LibraryVideoSeriesSnapshot] {
        inspection.videoSeries
            .filter { SableLibraryInspectionSearch.matches($0, query: animeInfoSearchText) }
            .sorted { first, second in
                if first.hasAnimeInfo != second.hasAnimeInfo {
                    return !first.hasAnimeInfo && second.hasAnimeInfo
                }
                return displayTitle(for: first).localizedCaseInsensitiveCompare(displayTitle(for: second)) == .orderedAscending
            }
    }

    private func displayTitle(for series: LibrarySeriesSnapshot) -> String {
        series.preferredTitle ?? series.localTitle ?? series.displayName
    }

    private func displayTitle(for series: LibraryVideoSeriesSnapshot) -> String {
        series.preferredTitle ?? series.localTitle ?? series.displayName
    }

    private func metricTile(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
