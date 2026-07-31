//
//  SableLibraryFileSafetyTests.swift
//  Sable's LibraryTests
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreML)
import CoreML
#endif
import XCTest
@testable import Sable_s_Library

final class SableLibraryFileSafetyTests: XCTestCase {
    func testOneManualProviderMatchDoesNotHideSiblingIdentityRows() {
        let regularItem = LibraryPlanItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            currentPath: "Light Novels/Second Series",
            proposedPath: "Light Novels/Second Series/ComicInfo.json",
            reason: "Create a sidecar",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false
        )
        let matchedItem = LibraryPlanItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            currentPath: "Light Novels/Matched Series",
            proposedPath: "Light Novels/Matched Series/ComicInfo.json",
            reason: "Use the chosen RanobeDB ID",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            metadataProviders: [.ranobedb],
            manualRanobeDBID: "6585",
            manualSourceIDs: [SableLibrarySourceID(provider: .ranobedb, value: "6585")],
            reviewTags: ["manual-provider-match"]
        )
        let identityGroup = LibraryPlanGroup(
            stage: .comicInfo,
            title: "Create Reading ComicInfo - Identity Pass",
            summary: "Two missing sidecars",
            items: [matchedItem, regularItem]
        )

        XCTAssertFalse(identityGroup.isManualProviderGapReviewGroup)
        XCTAssertEqual(identityGroup.activeItems.count, 2)

        let providerGapGroup = LibraryPlanGroup(
            stage: .providerMatches,
            title: "Missing Providers - RanobeDB",
            summary: "One provider question",
            items: [matchedItem]
        )
        XCTAssertTrue(providerGapGroup.isManualProviderGapReviewGroup)
    }

    func testProviderFolderAndFileAppliesSelectDownstreamAutomaticRefreshes() {
        var cleanup = CleanupOptions()
        cleanup.renameFolders = true
        cleanup.renameFiles = true
        let options = LibraryPipelineOptions(
            cleanup: cleanup,
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        XCTAssertEqual(
            LibraryPipelineStage.comicInfo.automaticRefreshStages(
                options: options,
                focusedMetadataApply: true
            ),
            [.canonicalFolders, .canonicalFiles]
        )
        XCTAssertEqual(
            LibraryPipelineStage.providerMatches.automaticRefreshStages(
                options: options,
                focusedMetadataApply: false
            ),
            [.providerMatches, .canonicalFolders, .canonicalFiles]
        )
        XCTAssertEqual(
            LibraryPipelineStage.canonicalFolders.automaticRefreshStages(
                options: options,
                focusedMetadataApply: false
            ),
            [.canonicalFolders, .canonicalFiles]
        )
        XCTAssertEqual(
            LibraryPipelineStage.canonicalFiles.automaticRefreshStages(
                options: options,
                focusedMetadataApply: false
            ),
            [.canonicalFiles]
        )
    }

    func testCoverRefreshClearsOnlyAttemptedCoverSelections() {
        let root = URL(fileURLWithPath: "/tmp/SableCoverRefreshPlan", isDirectory: true)
        let attemptedJapanese = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Shared Series",
            proposedPath: "Light Novels/Shared Series/_covers/cover-manifest.json",
            reason: "Search Japanese covers",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            reviewTags: ["cover-language-jp"]
        )
        let stillWaitingEnglish = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Shared Series",
            proposedPath: "Light Novels/Shared Series/_covers/cover-manifest.json",
            reason: "Search English covers",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            reviewTags: ["cover-language-en"]
        )
        var plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .covers,
                    title: "Ready to Find Covers",
                    summary: "Two series",
                    items: [attemptedJapanese, stillWaitingEnglish]
                )
            ]
        )

        plan.clearCheckedItems(stage: .covers, itemIDs: [attemptedJapanese.id])

        XCTAssertEqual(
            plan.items.first { $0.id == attemptedJapanese.id }?.decision,
            .unchecked
        )
        XCTAssertEqual(
            plan.items.first { $0.id == stillWaitingEnglish.id }?.decision,
            .checked
        )
    }

    func testSeriesFolderBookLookupDoesNotWalkSiblingSeries() throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let targetFolder = "Light Novels/Target Series"
        try writeFile("\(targetFolder)/Target Series - Vol 01.epub", contents: "book", root: root)
        try writeFile(
            "Light Novels/Unrelated Series/Unrelated Series - Vol 01.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        let items = try service.bookItems(
            in: root.appendingPathComponent(targetFolder, isDirectory: true),
            libraryRoot: root,
            config: service.currentConfig()
        )

        XCTAssertEqual(items.map(\.relativePath), ["\(targetFolder)/Target Series - Vol 01.epub"])
    }

    func testReplacingRefreshedNamingGroupsKeepsProviderRowsAndReviewChoices() throws {
        let root = URL(fileURLWithPath: "/tmp/SableRefreshPlan", isDirectory: true)
        let providerItem = LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Dan Machi",
            proposedPath: "Light Novels/Dan Machi/ComicInfo.json",
            reason: "Waiting for a provider choice",
            confidence: .medium,
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: true
        )
        let oldFolderItem = LibraryPlanItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: "Light Novels/Dan Machi",
            proposedPath: "Light Novels/00 - Review & Exceptions/Dan Machi - Novel",
            reason: "Old suggestion",
            confidence: .medium,
            safety: .reversible,
            decision: .unchecked,
            requiresReview: false
        )
        let oldFolderGroup = LibraryPlanGroup(
            stage: .canonicalFolders,
            title: "Folder sorting",
            summary: "Old folder pass",
            items: [oldFolderItem]
        )
        var plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .providerMatches,
                    title: "Missing Providers - RanobeDB",
                    summary: "One provider row",
                    items: [providerItem]
                ),
                oldFolderGroup
            ]
        )

        let refreshedFolderItem = LibraryPlanItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: oldFolderItem.currentPath,
            proposedPath: oldFolderItem.proposedPath,
            reason: "Fresh suggestion",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false
        )
        let refreshedFileItem = LibraryPlanItem(
            stage: .canonicalFiles,
            operation: .renameFile,
            currentPath: "Light Novels/Dan Machi/Volume 1.epub",
            proposedPath: "Light Novels/Dan Machi/Dan Machi - Vol 01.epub",
            reason: "Fresh file suggestion",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false
        )
        let refreshedPlan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .canonicalFolders,
                    title: "Folder sorting",
                    summary: "Fresh folder pass",
                    items: [refreshedFolderItem]
                ),
                LibraryPlanGroup(
                    stage: .canonicalFiles,
                    title: "File names",
                    summary: "Fresh file pass",
                    items: [refreshedFileItem]
                )
            ]
        )

        plan.replaceGroups(
            for: [.canonicalFolders, .canonicalFiles],
            with: refreshedPlan
        )

        XCTAssertEqual(plan.groups.first?.stage, .providerMatches)
        XCTAssertEqual(plan.items.first(where: { $0.stage == .providerMatches })?.id, providerItem.id)
        let mergedFolderGroup = try XCTUnwrap(plan.groups.first(where: { $0.stage == .canonicalFolders }))
        XCTAssertEqual(mergedFolderGroup.id, oldFolderGroup.id)
        let mergedFolderItem = try XCTUnwrap(mergedFolderGroup.items.first)
        XCTAssertEqual(mergedFolderItem.id, oldFolderItem.id)
        XCTAssertEqual(mergedFolderItem.decision, .unchecked)
        XCTAssertEqual(mergedFolderItem.reason, "Fresh suggestion")
        XCTAssertNotNil(plan.items.first(where: { $0.stage == .canonicalFiles }))
    }

    func testProviderQuickRefreshRebuildsFolderAndFileSuggestionsTogether() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/The Saga Of Tanya The Evil"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: #"{"title":"The Saga of Tanya the Evil","preferred_title":"The Saga of Tanya the Evil","type":"lightNovel","year":2017,"ids":{"ranobedb":"3148"}}"#,
            root: root
        )
        try writeFile(
            "\(folder)/The Saga Of Tanya The Evil Vol. 1.epub",
            contents: "book",
            root: root
        )

        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .quickVerifyAndBuildPlan(
                root: root,
                options: options,
                previousStage: .providerMatches,
                changedPaths: ["\(folder)/ComicInfo.json"],
                refreshStages: [.canonicalFolders, .canonicalFiles]
            )

        let folderItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFolders
                && item.operation == .renameFolder
                && item.currentPath == folder
        })
        XCTAssertEqual(
            folderItem.proposedPath,
            "Light Novels/The Saga of Tanya the Evil (2017) {rdb-3148}"
        )

        let fileItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath.hasSuffix("The Saga Of Tanya The Evil Vol. 1.epub")
        })
        XCTAssertEqual(
            fileItem.proposedPath,
            "\(folder)/The Saga of Tanya the Evil (2017) - Vol 01.epub"
        )
        XCTAssertEqual(
            Set(run.context.plan.groups.map(\.stage)),
            Set([.canonicalFolders, .canonicalFiles])
        )
    }

    func testRefreshingCoverPlanUnchecksCompleteSetsUntilExplicitlySelectedAgain() throws {
        let root = URL(fileURLWithPath: "/tmp/SableLibraryCompleteCoverRefresh", isDirectory: true)
        let path = "Light Novels/Complete Cover Set"
        let checkedIncomplete = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: path,
            proposedPath: "\(path)/_covers/cover-manifest.json",
            reason: "Fill cover gaps",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            reviewTags: ["metadata-cover-download", "cover-manifest-incomplete"]
        )
        var plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .covers,
                    title: "Cover Gaps to Retry",
                    summary: "One checked gap",
                    items: [checkedIncomplete]
                )
            ]
        )

        let refreshedComplete = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: path,
            proposedPath: "\(path)/_covers/cover-manifest.json",
            reason: "Complete cover set",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            reviewTags: ["metadata-cover-download", "cover-manifest-present"]
        )
        let refreshedPlan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .covers,
                    title: "Complete Cover Sets",
                    summary: "One complete set",
                    reviewPrompt: "Complete cover sets stay unchecked after scans and refreshes.",
                    items: [refreshedComplete]
                )
            ]
        )

        plan.replaceGroups(for: [.covers], with: refreshedPlan)

        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.id, checkedIncomplete.id)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-present"))
    }

    func testManualCoverSeriesMatchesOnlyAppearAfterAutomaticGapAndSurviveRefresh() throws {
        let root = URL(fileURLWithPath: "/tmp/SableLibraryManualCoverMatchRefresh", isDirectory: true)
        let path = "Light Novels/Agents of the Four Seasons"
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "1375365",
            itemType: "series",
            title: "春夏秋冬代行者",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/product/index/title_id/1375365/vol_no/001",
            thumbnailURL: nil
        )
        let matchedGap = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: path,
            proposedPath: "\(path)/_covers/cover-manifest.json",
            reason: "Fill cover gaps",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            manualCoverSeriesMatches: [match],
            reviewTags: ["metadata-cover-download", "cover-manifest-incomplete"]
        )
        XCTAssertTrue(matchedGap.canManuallyMatchCoverSeries)

        let neverSearched = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Never Searched",
            proposedPath: nil,
            reason: "Run the automatic pass first",
            confidence: .medium,
            safety: .reversible,
            decision: .unchecked,
            requiresReview: false,
            reviewTags: ["cover-manifest-missing"]
        )
        let complete = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Complete",
            proposedPath: nil,
            reason: "Complete",
            confidence: .medium,
            safety: .reversible,
            decision: .unchecked,
            requiresReview: false,
            reviewTags: ["cover-manifest-present"]
        )
        XCTAssertFalse(neverSearched.canManuallyMatchCoverSeries)
        XCTAssertFalse(complete.canManuallyMatchCoverSeries)

        var plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .covers,
                    title: "Cover Gaps to Retry",
                    summary: "One gap",
                    items: [matchedGap]
                )
            ]
        )
        let refreshedNoResult = LibraryPlanItem(
            stage: .covers,
            operation: .refreshComicInfo,
            currentPath: path,
            proposedPath: "\(path)/_covers/cover-manifest.json",
            reason: "No trusted cover found",
            confidence: .medium,
            safety: .reversible,
            decision: .unchecked,
            requiresReview: false,
            usedNetworkData: true,
            reviewTags: ["metadata-cover-download", "cover-manifest-no-result"]
        )
        plan.replaceGroups(
            for: [.covers],
            with: LibraryPlan(
                root: root,
                groups: [
                    LibraryPlanGroup(
                        stage: .covers,
                        title: "No Trusted Cover Found Last Search",
                        summary: "One no-result row",
                        items: [refreshedNoResult]
                    )
                ]
            )
        )

        let refreshed = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(refreshed.manualCoverSeriesMatches, [match])
        XCTAssertEqual(refreshed.decision, .checked)
        XCTAssertTrue(refreshed.canManuallyMatchCoverSeries)
    }

    func testBookLiveSeriesGroupDiscoveryAndBookFiltering() throws {
        let productHTML = """
        <li>
          <dl>
            <dt>シリーズ</dt>
            <dd class="colon">：</dd>
            <dd><a href="/search/keyword/tag_ids/105874">シュガーアップル・フェアリーテイルシリーズ</a></dd>
          </dl>
        </li>
        """
        let reference = try XCTUnwrap(
            SableLibraryBookLiveSeriesGroupClient.seriesGroupReference(
                fromProductHTML: productHTML
            )
        )
        XCTAssertEqual(reference.id, "105874")
        XCTAssertEqual(reference.title, "シュガーアップル・フェアリーテイル")
        XCTAssertEqual(
            reference.url,
            "https://booklive.jp/search/keyword/tag_ids/105874"
        )
        XCTAssertEqual(
            SableLibraryBookLiveSeriesGroupClient.tagID(from: reference.url),
            "105874"
        )

        let groupHTML = """
        <h1>シュガーアップル・フェアリーテイルシリーズ作品一覧</h1>
        <li class="item clearfix">
          <a href="/product/index/title_id/390768/vol_no/001"><img src="https://res.booklive.jp/390768/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル Collector's Edition１"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/181412/vol_no/001"><img src="https://res.booklive.jp/181412/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル 銀砂糖師と青の公爵"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/365955/vol_no/001"><img src="https://res.booklive.jp/365955/001/thumbnail/S.jpg" alt="銀砂糖師と黒の妖精 ～シュガーアップル・フェアリーテイル～ 1巻"></a>
          <span class="category-label__text">少女・女性マンガ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/181410/vol_no/001"><img src="https://res.booklive.jp/181410/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル 銀砂糖師と黒の妖精"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/20063674/vol_no/001"><img src="https://res.booklive.jp/20063674/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル【ノベル分冊版】 1"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/999999/vol_no/001"><img src="https://res.booklive.jp/999999/001/thumbnail/S.jpg" alt="【合本版】シュガーアップル・フェアリーテイル 全17巻"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        """
        let books = SableLibraryBookLiveSeriesGroupClient.seriesGroupBooks(
            from: groupHTML,
            groupID: "105874",
            expectedMediaType: "lightNovel"
        )

        XCTAssertEqual(
            SableLibraryBookLiveSeriesGroupClient.seriesGroupTitle(from: groupHTML),
            "シュガーアップル・フェアリーテイル"
        )
        XCTAssertEqual(books.count, 3)
        XCTAssertEqual(books[0].id, "181410-001")
        XCTAssertEqual(books[0].volumeNumber, 1)
        XCTAssertEqual(books[1].id, "181412-001")
        XCTAssertEqual(books[1].volumeNumber, 2)
        XCTAssertEqual(books[2].id, "390768-001")
        XCTAssertEqual(books[2].volumeNumber, 1)
        XCTAssertTrue(books.allSatisfy { $0.bookType == "novel" })
        XCTAssertTrue(books.allSatisfy { $0.coverURL.hasSuffix("/thumbnail/X.jpg") })
        XCTAssertFalse(books.contains { $0.id == "365955-001" })
        XCTAssertFalse(books.contains { $0.id == "20063674-001" })
        XCTAssertFalse(books.contains { $0.id == "999999-001" })

        let coverCandidates = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: books,
            source: .bookLiveJP,
            language: "jp",
            mediaType: "novel"
        )
        XCTAssertEqual(
            coverCandidates.first { $0.providerItemID == "390768-001" }?.role,
            .specialEdition
        )
    }

    func testAmazonAndBookWalkerPreferTypedParentSeries() throws {
        let amazonData = try XCTUnwrap(
            """
            {
              "data": {
                "amz": [
                  {
                    "id": "B0CJF9965P",
                    "title": "The Frontier Lord Begins with Zero Subjects Vol. 1",
                    "type": "book",
                    "bookType": "novel"
                  },
                  {
                    "id": "B0CLKWGDS4",
                    "title": "The Frontier Lord Begins with Zero Subjects",
                    "type": "series",
                    "bookType": "novel"
                  }
                ]
              }
            }
            """.data(using: .utf8)
        )
        let amazon = try SableLibraryBigBookCoversClient.seriesCandidates(
            fromSearchData: amazonData,
            provider: .amazon
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.exactIdentifierCandidates(amazon).first?.id,
            "B0CLKWGDS4"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.bestSeriesCandidate(
                for: "The Frontier Lord Begins with Zero Subjects",
                in: amazon,
                mediaType: "lightNovel"
            )?.id,
            "B0CLKWGDS4"
        )

        let bookWalkerJPData = try XCTUnwrap(
            """
            {
              "data": {
                "bw": [
                  {
                    "id": "357814",
                    "title": "シュガーアップル・フェアリーテイル",
                    "type": "series",
                    "bookType": "manga"
                  },
                  {
                    "id": "1646",
                    "title": "シュガーアップル・フェアリーテイル",
                    "type": "series",
                    "bookType": "novel"
                  },
                  {
                    "id": "volume-1",
                    "title": "シュガーアップル・フェアリーテイル 1",
                    "type": "book",
                    "bookType": "novel"
                  }
                ]
              }
            }
            """.data(using: .utf8)
        )
        let bookWalkerJP = try SableLibraryBigBookCoversClient.seriesCandidates(
            fromSearchData: bookWalkerJPData,
            provider: .bookWalkerJP
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.bestSeriesCandidate(
                for: "シュガーアップル・フェアリーテイル",
                in: bookWalkerJP,
                mediaType: "lightNovel"
            )?.id,
            "1646"
        )

        let bookWalkerGlobalData = try XCTUnwrap(
            """
            {
              "data": {
                "bw-g": [
                  {
                    "id": "volume-1",
                    "title": "Sugar Apple Fairy Tale, Vol. 1",
                    "type": "book",
                    "bookType": "novel"
                  },
                  {
                    "id": "CNT_2W60CBEK0TG0",
                    "title": "Sugar Apple Fairy Tale",
                    "type": "series",
                    "bookType": "novel"
                  }
                ]
              }
            }
            """.data(using: .utf8)
        )
        let bookWalkerGlobal = try SableLibraryBigBookCoversClient.seriesCandidates(
            fromSearchData: bookWalkerGlobalData,
            provider: .bookWalkerGlobal
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.bestSeriesCandidate(
                for: "Sugar Apple Fairy Tale",
                in: bookWalkerGlobal,
                mediaType: "lightNovel"
            )?.id,
            "CNT_2W60CBEK0TG0"
        )
    }

    func testAppModesKeepLibraryClinicAndCoversWorkflowsSeparate() {
        XCTAssertEqual(SableLibraryAppMode.library.appName, "Sable's Library")
        XCTAssertEqual(SableLibraryAppMode.clinic.appName, "Sable's Clinic")
        XCTAssertEqual(SableLibraryAppMode.covers.appName, "Sable's Covers")
        XCTAssertEqual(SableLibraryAppMode.library.clearStatusTitle, "Library looks clear")
        XCTAssertEqual(SableLibraryAppMode.clinic.clearStatusTitle, "No Clinic rows from this pass")
        XCTAssertFalse(SableLibraryAppMode.library.workflowStages.contains(.epubClinic))
        XCTAssertFalse(SableLibraryAppMode.library.workflowStages.contains(.covers))
        XCTAssertEqual(SableLibraryAppMode.clinic.workflowStages, [.epubClinic])
        XCTAssertEqual(SableLibraryAppMode.covers.workflowStages, [.covers, .epubClinic])
        XCTAssertEqual(SableLibraryAppMode.clinic.inspectActionTitle, "Scan EPUBs")
        XCTAssertFalse(SableClinicCheckProfile.repairLaneChoices.contains(.covers))
        XCTAssertEqual(SableClinicCheckProfile.coverChoices, [.covers, .appleBooks])

        let libraryFullDepartments = SableLibraryMLCompany.departments(for: .library, mode: .full)
        XCTAssertTrue(libraryFullDepartments.contains(.shelfManager))
        XCTAssertTrue(libraryFullDepartments.contains(.metadataManager))
        XCTAssertFalse(libraryFullDepartments.contains(.clinicManager))
        XCTAssertFalse(libraryFullDepartments.contains(.epubClinic))
        XCTAssertFalse(SableLibraryMLCompany.departments(for: .library, stage: .canonicalFiles).contains(.epubClinic))
        XCTAssertFalse(SableLibraryMLCompany.departments(for: .library, stage: .epubClinic).contains(.clinicManager))
        XCTAssertFalse(SableLibraryMLCompany.departments(for: .library, mode: .epubClinicInventory).contains(.epubClinic))

        let clinicFullDepartments = SableLibraryMLCompany.departments(for: .clinic, mode: .full)
        XCTAssertTrue(clinicFullDepartments.contains(.clinicManager))
        XCTAssertTrue(clinicFullDepartments.contains(.epubClinic))
        XCTAssertTrue(clinicFullDepartments.contains(.metadataManager))
        XCTAssertFalse(clinicFullDepartments.contains(.shelfManager))
        XCTAssertFalse(clinicFullDepartments.contains(.moveManager))

        XCTAssertEqual(
            SableLibraryMLCompany.finalSayManager(for: .library, stage: .canonicalFolders),
            .shelfManager
        )
        XCTAssertEqual(
            SableLibraryMLCompany.finalSayManager(for: .clinic, stage: .epubClinic),
            .clinicManager
        )
        XCTAssertEqual(
            SableLibraryMLCompany.finalSayManager(for: .library, stage: .epubClinic),
            .reviewManager
        )
    }

    func testClinicCleanSummaryRequiresPostRepairVerification() {
        let root = URL(fileURLWithPath: "/tmp/SableCleanSummary", isDirectory: true)
        let reviewApplyStep = SableLibraryStep6ReviewApply()

        let quietClinicPass = LibraryPlan(
            root: root,
            inspectMode: .stageDeepDive(.epubClinic)
        )
        let quietSummary = reviewApplyStep.summarize(plan: quietClinicPass, lastApplyResult: nil)
        XCTAssertEqual(quietSummary.title, "No Clinic rows from this pass")
        XCTAssertFalse(quietSummary.title.localizedCaseInsensitiveContains("clean"))
        XCTAssertTrue(quietSummary.message.contains("only says clean after repairs are applied"))

        let verifiedClinicPass = LibraryPlan(
            root: root,
            inspectMode: .quickVerify(
                previousStage: .epubClinic,
                changedPaths: ["Books/Repaired.epub"],
                focusStage: .epubClinic
            )
        )
        let verifiedSummary = reviewApplyStep.summarize(
            plan: verifiedClinicPass,
            lastApplyResult: LibraryApplyResult(
                appliedCount: 2,
                skippedCount: 0,
                receiptPath: nil,
                summary: "Two repair rows applied."
            )
        )

        XCTAssertEqual(verifiedSummary.title, "Clinic verification clean")
        XCTAssertTrue(verifiedSummary.message.contains("rechecked the changed EPUBs"))
        XCTAssertTrue(verifiedSummary.message.contains("no remaining Clinic rows"))
    }

    func testEPUBClinicModifiedWindowFiltersChangedFiles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 28,
            hour: 12
        ))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: now)!
        let twentyNineDaysAgo = calendar.date(byAdding: .day, value: -29, to: now)!
        let thirtyOneDaysAgo = calendar.date(byAdding: .day, value: -31, to: now)!

        XCTAssertTrue(SableEPUBClinicModifiedWindow.all.includes(modificationDate: nil, now: now, calendar: calendar))
        XCTAssertTrue(SableEPUBClinicModifiedWindow.today.includes(modificationDate: now, now: now, calendar: calendar))
        XCTAssertFalse(SableEPUBClinicModifiedWindow.today.includes(modificationDate: yesterday, now: now, calendar: calendar))
        XCTAssertTrue(SableEPUBClinicModifiedWindow.last7Days.includes(modificationDate: sixDaysAgo, now: now, calendar: calendar))
        XCTAssertFalse(SableEPUBClinicModifiedWindow.last7Days.includes(modificationDate: eightDaysAgo, now: now, calendar: calendar))
        XCTAssertTrue(SableEPUBClinicModifiedWindow.last30Days.includes(modificationDate: twentyNineDaysAgo, now: now, calendar: calendar))
        XCTAssertFalse(SableEPUBClinicModifiedWindow.last30Days.includes(modificationDate: thirtyOneDaysAgo, now: now, calendar: calendar))
    }

    func testLibraryTabsRememberIndependentModifiedWindows() throws {
        var options = LibraryPipelineStageOptions()
        options.setModifiedWindow(.today, for: .covers)
        options.setModifiedWindow(.last7Days, for: .comicInfo)

        XCTAssertEqual(options.modifiedWindow(for: .covers), .today)
        XCTAssertEqual(options.modifiedWindow(for: .comicInfo), .last7Days)
        XCTAssertEqual(options.modifiedWindow(for: .canonicalFiles), .all)
        XCTAssertEqual(options.modifiedWindow(for: .epubClinic), .all)

        let encoded = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(LibraryPipelineStageOptions.self, from: encoded)
        XCTAssertEqual(decoded.modifiedWindow(for: .covers), .today)
        XCTAssertEqual(decoded.modifiedWindow(for: .comicInfo), .last7Days)
    }

    func testExplicitProviderRefreshRejectsOldCacheWithoutDiscardingNormalCache() async {
        let key = "test-provider-refresh-\(UUID().uuidString)"
        let data = Data("cached".utf8)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        await SableLibraryProviderResponseCache.shared.store(
            data,
            for: key,
            ttl: 600,
            now: createdAt
        )

        let refreshRead = await SableLibraryProviderResponseCache.shared.cachedData(
            for: key,
            maximumAge: 30,
            now: createdAt.addingTimeInterval(31)
        )
        let normalRead = await SableLibraryProviderResponseCache.shared.cachedData(
            for: key,
            now: createdAt.addingTimeInterval(31)
        )

        XCTAssertNil(refreshRead)
        XCTAssertEqual(normalRead, data)
    }

    func testProviderResponseCacheEvictsOldestEntriesWithinMemoryLimit() async {
        let cache = SableLibraryProviderResponseCache(
            maximumTotalBytes: 8,
            maximumEntryBytes: 6,
            maximumEntryCount: 2
        )
        let now = Date(timeIntervalSince1970: 1_000)

        await cache.store(Data("aaaa".utf8), for: "first", ttl: 600, now: now)
        await cache.store(Data("bbbb".utf8), for: "second", ttl: 600, now: now.addingTimeInterval(1))
        await cache.store(Data("cccc".utf8), for: "third", ttl: 600, now: now.addingTimeInterval(2))
        await cache.store(Data("oversized".utf8), for: "oversized", ttl: 600, now: now)

        let first = await cache.cachedData(for: "first", now: now.addingTimeInterval(3))
        let second = await cache.cachedData(for: "second", now: now.addingTimeInterval(3))
        let third = await cache.cachedData(for: "third", now: now.addingTimeInterval(3))
        let oversized = await cache.cachedData(for: "oversized", now: now.addingTimeInterval(3))

        XCTAssertNil(first)
        XCTAssertEqual(second, Data("bbbb".utf8))
        XCTAssertEqual(third, Data("cccc".utf8))
        XCTAssertNil(oversized)
    }

    func testLibraryStageModifiedWindowScopesCandidatesBeforeSpecialistWork() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 21,
            hour: 12
        ))!
        let olderDate = calendar.date(byAdding: .day, value: -2, to: now)!
        let recentSeriesPath = "Light Novels/Recent Series"
        let olderSeriesPath = "Light Novels/Older Series"
        let recentBookPath = recentSeriesPath + "/Recent - Vol 01.epub"
        let olderBookPath = olderSeriesPath + "/Older - Vol 01.epub"

        var inspection = LibraryInspection.empty(root: URL(fileURLWithPath: "/tmp/library-stage-scope"))
        inspection.series = [
            readingSeries(path: recentSeriesPath, displayName: "Recent Series", mediaType: "Novel"),
            readingSeries(path: olderSeriesPath, displayName: "Older Series", mediaType: "Novel")
        ]
        inspection.books = [
            LibraryBookSnapshot(
                id: recentBookPath,
                path: recentBookPath,
                fileName: "Recent - Vol 01.epub",
                fileExtension: "epub",
                seriesID: recentSeriesPath,
                isPackageBook: false,
                modificationDate: now
            ),
            LibraryBookSnapshot(
                id: olderBookPath,
                path: olderBookPath,
                fileName: "Older - Vol 01.epub",
                fileExtension: "epub",
                seriesID: olderSeriesPath,
                isPackageBook: false,
                modificationDate: olderDate
            )
        ]
        inspection.comicInfoSeriesPaths = [recentSeriesPath, olderSeriesPath]
        inspection.duplicateCandidates = [
            LibraryInspectionDuplicateGroup(
                fingerprint: "recent-copy",
                kind: DuplicateReviewGroup.Kind.exactContent.rawValue,
                paths: [recentBookPath, "Duplicates/Recent - Vol 01.epub"],
                suggestedKeeperPath: recentBookPath,
                note: "Recent duplicate"
            ),
            LibraryInspectionDuplicateGroup(
                fingerprint: "older-copy",
                kind: DuplicateReviewGroup.Kind.exactContent.rawValue,
                paths: [olderBookPath, "Duplicates/Older - Vol 01.epub"],
                suggestedKeeperPath: olderBookPath,
                note: "Older duplicate"
            )
        ]

        let coverScope = inspection.scoped(
            to: .today,
            for: .covers,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(coverScope.books.map(\.path), [recentBookPath])
        XCTAssertEqual(coverScope.series.map(\.path), [recentSeriesPath])
        XCTAssertEqual(coverScope.comicInfoSeriesPaths, [recentSeriesPath])
        XCTAssertEqual(coverScope.duplicateCandidates.map(\.fingerprint), ["recent-copy"])

        let rawScope = inspection.scoped(
            to: .today,
            for: .prepareRawFiles,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(rawScope.books.map(\.path), [recentBookPath])
        XCTAssertEqual(rawScope.series.map(\.path), [recentSeriesPath, olderSeriesPath])
    }

    func testPersonalModelTrainerKeepsSpecificEPUBRepairTrainingLabels() {
        let event = SableLibraryMLTrainingEvent.make(
            kind: .finalSuccessfulPlanRow,
            domain: .reading,
            localPath: "Books/Clean Candidate.epub",
            confidenceScore: 0.95,
            featureSummary: [
                "operation": LibraryPlanOperation.repairEpubPackage.rawValue,
                "review_tags": [
                    "epub-cover",
                    "epub-import-metadata",
                    "epub-navigation",
                    "epub-package",
                    "epub-structure",
                    "epub-tags",
                    "ml-training-epub-content",
                    "ml-training-epub-manual-review"
                ].joined(separator: ",")
            ]
        )

        let labels = SableLibraryPersonalModelTrainer().labelsForTesting(for: event)

        XCTAssertTrue(labels.contains("task.epubRepair"))
        XCTAssertTrue(labels.contains("epub.repair.package"))
        XCTAssertTrue(labels.contains("epub.repair.content"))
        XCTAssertTrue(labels.contains("epub.repair.navigation"))
        XCTAssertTrue(labels.contains("epub.repair.structure"))
        XCTAssertTrue(labels.contains("epub.repair.metadata"))
        XCTAssertTrue(labels.contains("epub.repair.tags"))
        XCTAssertTrue(labels.contains("epub.repair.cover"))
        XCTAssertTrue(labels.contains("epub.review.manual"))
    }

    func testPersonalModelStoreRejectsModelOlderThanLearningMemory() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let modelURL = folder.appendingPathComponent("Personal.mlmodel")
        let learningURL = folder.appendingPathComponent("SableLearningMemory.json")
        FileManager.default.createFile(atPath: modelURL.path(percentEncoded: false), contents: Data())
        FileManager.default.createFile(atPath: learningURL.path(percentEncoded: false), contents: Data())

        let oldModelDate = Date(timeIntervalSince1970: 100)
        let newerLearningDate = Date(timeIntervalSince1970: 200)
        try FileManager.default.setAttributes([.modificationDate: oldModelDate], ofItemAtPath: modelURL.path(percentEncoded: false))
        try FileManager.default.setAttributes([.modificationDate: newerLearningDate], ofItemAtPath: learningURL.path(percentEncoded: false))

        XCTAssertFalse(SableLibraryPersonalModelStore.isPersonalModelFresh(modelURL: modelURL, learningURL: learningURL))

        try FileManager.default.setAttributes([.modificationDate: newerLearningDate], ofItemAtPath: modelURL.path(percentEncoded: false))
        try FileManager.default.setAttributes([.modificationDate: oldModelDate], ofItemAtPath: learningURL.path(percentEncoded: false))

        XCTAssertTrue(SableLibraryPersonalModelStore.isPersonalModelFresh(modelURL: modelURL, learningURL: learningURL))
    }

    func testPersonalModelStoreRejectsCompiledModelOlderThanSource() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let modelURL = folder.appendingPathComponent("Personal.mlmodel")
        let compiledURL = folder.appendingPathComponent("Personal.mlmodelc", isDirectory: true)
        FileManager.default.createFile(atPath: modelURL.path(percentEncoded: false), contents: Data())
        try FileManager.default.createDirectory(at: compiledURL, withIntermediateDirectories: true)

        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: compiledURL.path(percentEncoded: false)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: newDate],
            ofItemAtPath: modelURL.path(percentEncoded: false)
        )

        XCTAssertFalse(
            SableLibraryPersonalModelStore.isCompiledPersonalModelFresh(
                compiledURL: compiledURL,
                modelURL: modelURL
            )
        )

        try FileManager.default.setAttributes(
            [.modificationDate: newDate],
            ofItemAtPath: compiledURL.path(percentEncoded: false)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: modelURL.path(percentEncoded: false)
        )

        XCTAssertTrue(
            SableLibraryPersonalModelStore.isCompiledPersonalModelFresh(
                compiledURL: compiledURL,
                modelURL: modelURL
            )
        )
    }

    func testBundledSpecialistModelsCompileAndTagProviderNoise() throws {
        #if canImport(CoreML)
        let mlDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sable's Library/App/ML", isDirectory: true)
        let modelNames = [
            "SableLibraryDecisionClassifier",
            "SableLibraryInspectionClassifier",
            "SableLibraryRawCleanupClassifier",
            "SableLibraryReadingClassifier",
            "SableLibraryProviderClassifier",
            "SableLibraryTitleAliasRoleClassifier",
            "SableLibraryMediaTypeClassifier",
            "SableLibraryTagRoleClassifier",
            "SableLibraryDescriptionAboutnessClassifier",
            "SableLibraryWorkFamilyRelationshipClassifier",
            "SableLibrarySidecarClassifier",
            "SableLibraryShelfClassifier",
            "SableLibraryEvidenceMeetingClassifier",
            "SableLibraryEPUBRepairClassifier",
            "SableLibraryNamingMoveClassifier",
            "SableLibraryReadingNameTagger",
            "SableLibraryVideoNameTagger",
            "SableLibraryDocumentNameTagger",
            "SableLibraryReviewActionRecommender",
            "SableLibraryProviderRankingRecommender",
            "SableLibraryFolderGroupingRecommender"
        ]

        for modelName in modelNames {
            let modelURL = mlDirectory.appendingPathComponent("\(modelName).mlmodel")
            XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)), "\(modelName) should be bundled in the project.")
            _ = try MLModel.compileModel(at: modelURL)
        }

        let readingTagger = try MLModel(contentsOf: MLModel.compileModel(
            at: mlDirectory.appendingPathComponent("SableLibraryReadingNameTagger.mlmodel")
        ))
        let tagInput = try MLDictionaryFeatureProvider(dictionary: [
            "text": "A Livid Lady Guide (2022) - Vol OL 01.epub"
        ])
        let tagOutput = try readingTagger.prediction(from: tagInput)
        let tokens = tagOutput.featureValue(for: "tokens")?.sequenceValue?.stringValues ?? []
        let labels = tagOutput.featureValue(for: "labels")?.sequenceValue?.stringValues ?? []

        XCTAssertTrue(zip(tokens, labels).contains { token, label in
            token.localizedCaseInsensitiveCompare("OL") == .orderedSame && label == "PROVIDER_NOISE"
        }, "The reading tagger should treat OL as provider/source noise, not a volume number.")

        let chapterInput = try MLDictionaryFeatureProvider(dictionary: [
            "text": "Chapter 149.5"
        ])
        let chapterOutput = try readingTagger.prediction(from: chapterInput)
        let chapterLabels = chapterOutput.featureValue(for: "labels")?.sequenceValue?.stringValues ?? []
        XCTAssertTrue(chapterLabels.contains("CHAPTER_MARKER"))
        XCTAssertTrue(chapterLabels.contains("CHAPTER_NUMBER"))

        let volumeTitleInput = try MLDictionaryFeatureProvider(dictionary: [
            "text": "Clean Candidate, Vol. 4 (light Novel)"
        ])
        let volumeTitleOutput = try readingTagger.prediction(from: volumeTitleInput)
        let volumeTitleLabels = volumeTitleOutput.featureValue(for: "labels")?.sequenceValue?.stringValues ?? []
        XCTAssertTrue(volumeTitleLabels.contains("VOLUME_MARKER"))

        let reviewRecommender = try MLModel(contentsOf: MLModel.compileModel(
            at: mlDirectory.appendingPathComponent("SableLibraryReviewActionRecommender.mlmodel")
        ))
        let recommenderInput = try MLDictionaryFeatureProvider(dictionary: [
            "items": [
                "signal.stage.prepareRawFiles": 5.0,
                "signal.raw.reading": 5.0,
                "signal.strong": 3.0
            ],
            "k": 3,
            "restrict": [
                "check.sortIntoFolder",
                "protect.skip",
                "treatAsDocument"
            ]
        ])
        let recommenderOutput = try reviewRecommender.prediction(from: recommenderInput)
        let recommendations = recommenderOutput.featureValue(for: "recommendations")?.sequenceValue?.stringValues ?? []
        XCTAssertTrue(recommendations.contains("check.sortIntoFolder"))
        #else
        throw XCTSkip("Core ML is unavailable in this test environment.")
        #endif
    }

    func testPipelineDefaultsKeepOutsideMetadataLookupOff() {
        let defaults = LibraryPipelineStageOptions()

        XCTAssertFalse(defaults.useMangaBaka)
        XCTAssertFalse(defaults.useMetadataProviders)
        XCTAssertEqual(defaults.preferredTitleStyle, .english)
        XCTAssertTrue(defaults.repairEPUBs)
        XCTAssertTrue(defaults.deepEPUBContentChecks)
        XCTAssertTrue(defaults.writeEPUBImportMetadata)
        XCTAssertTrue(defaults.exportReports)
    }

    func testCleanupSettingsRoundTripReadingFolderDepths() throws {
        for depth in SableLibraryFolderOrganizationDepth.allCases {
            var options = CleanupOptions()
            options.readingFolderOrganizationDepth = depth

            let data = try JSONEncoder().encode(options)
            let decoded = try JSONDecoder().decode(CleanupOptions.self, from: data)

            XCTAssertEqual(decoded.readingFolderOrganizationDepth, depth)
        }
    }

    func testOlderCleanupSettingsDefaultReadingFolderDepthToForm() throws {
        let data = """
        {
          "organizeLooseBooks": true,
          "renameFiles": true,
          "renameFolders": true,
          "checkDuplicates": true,
          "treatPDFsAsBooks": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CleanupOptions.self, from: data)

        XCTAssertEqual(decoded.readingFolderOrganizationDepth, .form)
    }

    func testOlderPipelineStageSettingsKeepMetadataProvidersOff() throws {
        let data = """
        {
          "applyCleanup": true,
          "moveMissingNumbers": true,
          "useComicInfoTitles": true,
          "useMangaBaka": false,
          "refreshComicInfo": false,
          "exportReports": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LibraryPipelineStageOptions.self, from: data)

        XCTAssertFalse(decoded.useMetadataProviders)
        XCTAssertEqual(decoded.preferredTitleStyle, .english)
        XCTAssertTrue(decoded.repairEPUBs)
        XCTAssertTrue(decoded.deepEPUBContentChecks)
        XCTAssertTrue(decoded.writeEPUBImportMetadata)
        XCTAssertTrue(decoded.exportReports)
    }

    func testInspectionKeepsScannerWarningNotesVisible() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SableLibraryService()
        let config = service.currentConfig()
        let warning = "1 cloud-backed item was not downloaded locally and was skipped. Download it in Finder, then inspect again."

        service.storeCachedItems([], warnings: [warning], for: service.scanCacheKey(root: root, config: config))

        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            mode: .lightInventory,
            service: service
        )

        XCTAssertTrue(inspection.notes.contains(warning))
    }

    func testInspectUsesPreferredSidecarNameStyleForReadingAndWatching() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Manga/Apothecary/ComicInfo.json",
            contents: """
            {
              "title": "The Apothecary Diaries",
              "preferred_title": "The Apothecary Diaries",
              "romanized_title": "Kusuriya no Hitorigoto",
              "native_title": "薬屋のひとりごと",
              "title_variants": {
                "english": ["The Apothecary Diaries"],
                "romaji": ["Kusuriya no Hitorigoto"],
                "japanese": ["薬屋のひとりごと"]
              },
              "type": "manga"
            }
            """,
            root: root
        )
        try writeFile("Manga/Apothecary/The Apothecary Diaries - Vol 01.cbz", contents: "book", root: root)
        try writeFile(
            "TV/Frieren/AnimeInfo.json",
            contents: """
            {
              "title": "Frieren: Beyond Journey's End",
              "preferred_title": "Frieren: Beyond Journey's End",
              "romanized_title": "Sousou no Frieren",
              "native_title": "葬送のフリーレン",
              "title_variants": {
                "en": ["Frieren: Beyond Journey's End"],
                "romanized": ["Sousou no Frieren"],
                "zh-hans": ["葬送的芙莉莲"]
              },
              "type": "animeTV"
            }
            """,
            root: root
        )
        try writeFile("TV/Frieren/Frieren S01E01.mkv", contents: "video", root: root)

        let expectations: [(SableLibraryPreferredTitleStyle, String, String)] = [
            (.english, "The Apothecary Diaries", "Frieren: Beyond Journey's End"),
            (.romaji, "Kusuriya no Hitorigoto", "Sousou no Frieren"),
            (.native, "薬屋のひとりごと", "葬送のフリーレン")
        ]

        for (style, expectedReadingTitle, expectedWatchingTitle) in expectations {
            var stages = LibraryPipelineStageOptions()
            stages.preferredTitleStyle = style
            let options = LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: stages,
                intelligence: SableLibraryIntelligenceOptions()
            )
            let inspection = await SableLibraryStep1InspectLibrary().inspect(
                root: root,
                options: options,
                service: SableLibraryService()
            )

            XCTAssertEqual(
                inspection.series.first { $0.path == "Manga/Apothecary" }?.preferredTitle,
                expectedReadingTitle
            )
            XCTAssertEqual(
                inspection.videoSeries.first { $0.path == "TV/Frieren" }?.preferredTitle,
                expectedWatchingTitle
            )
        }
    }

    func testInspectPrefersTopLevelSeriesTitleBeforeShortEnglishVariants() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fullTitle = "Banished from the Hero's Party, I Decided to Live a Quiet Life in the Countryside"
        try writeFile(
            "Light Novels/Banished/ComicInfo.json",
            contents: """
            {
              "title": "\(fullTitle)",
              "preferred_title": "\(fullTitle)",
              "local_title": "\(fullTitle), Vol. 4 (light Novel)",
              "type": "lightNovel",
              "title_variants": {
                "english": [
                  "Banished from the Hero's Party",
                  "I Decided to Live a Quiet Life in the Countryside",
                  "Vol. 4 (light Novel)",
                  "\(fullTitle)"
                ]
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Banished/Banished from the Hero's Party - Vol 01.epub", contents: "book", root: root)

        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            service: SableLibraryService()
        )

        let series = try XCTUnwrap(inspection.series.first { $0.path == "Light Novels/Banished" })
        XCTAssertEqual(series.preferredTitle, fullTitle)
        XCTAssertEqual(series.localTitle, "\(fullTitle), Vol. 4 (light Novel)")
    }

    func testPaletteAccessibilityAuditHasNoWarnings() {
        let warnings = SableLibraryPaletteAudit.findings().filter { !$0.passed }
        let message = warnings.map(\.line).joined(separator: "\n")

        XCTAssertTrue(warnings.isEmpty, message)
    }

    func testReviewRequiredRowsAreNotApplyableEvenWhenChecked() {
        let item = planItem(
            safety: .reversible,
            decision: .checked,
            requiresReview: true
        )

        XCTAssertFalse(item.isApplyableOperation)
        XCTAssertTrue(item.needsDecisionReview)
    }

    func testManualTitleReviewRenameCanBeApprovedAndAppliedAfterChecking() {
        let item = planItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: "Light Novels/Ai no Kusabi (1986) {mb-82805}",
            proposedPath: "Light Novels/Ai no Kusabi - O Espaco Entre (1986) {mb-82805}",
            safety: .needsChoice,
            decision: .checked,
            requiresReview: true,
            reviewTags: ["naming-title-change"]
        )

        XCTAssertTrue(item.isManualApprovalFileOperation)
        XCTAssertTrue(item.isApplyableOperation)
        XCTAssertFalse(item.needsDecisionReview)
    }

    func testManualTitleReviewRenameWaitsUntilChecked() {
        let item = planItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: "Light Novels/Ai no Kusabi (1986) {mb-82805}",
            proposedPath: "Light Novels/Ai no Kusabi - O Espaco Entre (1986) {mb-82805}",
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: true,
            reviewTags: ["naming-title-change"]
        )

        XCTAssertTrue(item.isManualApprovalFileOperation)
        XCTAssertTrue(item.isApplyableOperation)
        XCTAssertTrue(item.needsDecisionReview)
    }

    func testNetworkRowsStayOutOfApplyUntilSpecificReviewFlowExists() {
        let item = planItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            proposedPath: "/Library/Series/ComicInfo.json",
            safety: .network,
            decision: .checked,
            usedNetworkData: true
        )

        XCTAssertFalse(item.isApplyableOperation)
        XCTAssertTrue(item.needsDecisionReview)
    }

    func testNameCollisionNeedsExplicitMoveAsideResolutionBeforeApply() {
        let unresolved = planItem(
            operation: .renameFile,
            safety: .collision,
            decision: .checked
        )
        let resolved = planItem(
            operation: .renameFile,
            reason: PlannedMove.manualNameCollisionReason,
            safety: .collision,
            decision: .checked
        )

        XCTAssertFalse(unresolved.isApplyableOperation)
        XCTAssertTrue(unresolved.needsDecisionReview)
        XCTAssertTrue(resolved.isNameCollisionResolution)
        XCTAssertTrue(resolved.isApplyableOperation)
        XCTAssertFalse(resolved.needsDecisionReview)
    }

    func testDuplicateMoveAsideNeedsExplicitDuplicateReasonBeforeApply() {
        let unresolved = planItem(
            stage: .duplicateReview,
            operation: .duplicateDecision,
            safety: .reversible,
            decision: .checked
        )
        let resolved = planItem(
            stage: .duplicateReview,
            operation: .duplicateDecision,
            reason: PlannedMove.duplicateReviewReason,
            safety: .reversible,
            decision: .checked
        )

        XCTAssertFalse(unresolved.isApplyableOperation)
        XCTAssertFalse(unresolved.isDuplicateMoveAside)
        XCTAssertTrue(resolved.isDuplicateMoveAside)
        XCTAssertTrue(resolved.isApplyableOperation)
    }

    func testApplyFiltersCheckedRowsThroughSafetyContract() {
        let safeRename = planItem(decision: .checked)
        let checkedNetwork = planItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            proposedPath: "/Library/Series/ComicInfo.json",
            safety: .network,
            decision: .checked,
            usedNetworkData: true
        )
        let plan = LibraryPlan(
            root: URL(fileURLWithPath: "/Library", isDirectory: true),
            groups: [
                LibraryPlanGroup(
                    stage: .canonicalFiles,
                    title: "Book file names",
                    summary: "Test plan",
                    items: [safeRename, checkedNetwork]
                )
            ]
        )

        XCTAssertEqual(plan.checkedItems.count, 2)
        XCTAssertEqual(plan.checkedItems.filter(\.isApplyableOperation), [safeRename])
    }

    func testReviewSearchMatchesPathsReasonsAndSafetyTerms() {
        let item = planItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: "/Library/Raw/Stray Series",
            proposedPath: "/Library/Stray Series",
            reason: "clean folder name",
            confidence: .medium,
            safety: .collision
        )

        XCTAssertTrue(SableLibraryPlanSearch.matches(item, query: "stray collision"))
        XCTAssertTrue(SableLibraryPlanSearch.matches(item, query: "folder medium"))
        XCTAssertTrue(SableLibraryPlanSearch.matches(item, query: "/library/raw"))
    }

    func testReviewSearchRequiresEveryTermToMatch() {
        let item = planItem(
            currentPath: "/Library/Series/Old.cbz",
            proposedPath: "/Library/Series/New.cbz",
            reason: "clean book file name"
        )

        XCTAssertTrue(SableLibraryPlanSearch.matches(item, query: "series clean"))
        XCTAssertFalse(SableLibraryPlanSearch.matches(item, query: "series manga"))
    }

    func testReviewSearchTreatsBlankQueryAsUnfiltered() {
        let item = planItem()

        XCTAssertTrue(SableLibraryPlanSearch.matches(item, query: ""))
        XCTAssertTrue(SableLibraryPlanSearch.matches(item, query: "   "))
    }

    func testInspectionTypeCountsSeparateReadingAndWatchingKinds() {
        var inspection = LibraryInspection.empty(root: URL(fileURLWithPath: "/Library", isDirectory: true))
        inspection.series = [
            readingSeries(path: "Manga/Witch Hat Atelier", displayName: "Witch Hat Atelier", mediaType: "manga"),
            readingSeries(path: "Light Novels/Tanya", displayName: "The Saga of Tanya the Evil", mediaType: "lightNovel")
        ]
        inspection.videoSeries = [
            watchingSeries(path: "TV/Frieren", displayName: "Frieren", mediaType: "animeTV"),
            watchingSeries(path: "Movies/Spirited Away", displayName: "Spirited Away", mediaType: "animeMovie")
        ]

        XCTAssertEqual(
            inspection.readingTypeCounts,
            [
                LibraryInspectionTypeCount(label: "Manga", count: 1),
                LibraryInspectionTypeCount(label: "Light novels", count: 1)
            ]
        )
        XCTAssertEqual(
            inspection.watchingTypeCounts,
            [
                LibraryInspectionTypeCount(label: "TV", count: 1),
                LibraryInspectionTypeCount(label: "Movies", count: 1)
            ]
        )
    }

    func testInspectionDisplayFileTypesGroupsNoisyHashExtensions() {
        var inspection = LibraryInspection.empty(root: URL(fileURLWithPath: "/Library", isDirectory: true))
        inspection.fileTypeCounts = [
            "pdf": 3,
            "docx": 2,
            "xml": 4,
            "h-10wosd6age32z": 1,
            "ek3xyz": 1,
            LibraryInspection.fileTypeCountKey(for: URL(fileURLWithPath: "/Library/LooseFile")): 2
        ]

        let rows = inspection.displayFileTypeCounts
        let counts = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0.count) })

        XCTAssertEqual(counts["XML"], 4)
        XCTAssertEqual(counts["PDF"], 3)
        XCTAssertEqual(counts["DOCX"], 2)
        XCTAssertEqual(counts["No extension"], 2)
        XCTAssertEqual(counts["Other file types"], 2)
        XCTAssertFalse(rows.contains { $0.label.localizedCaseInsensitiveContains("h-10wosd6age32z") })
        XCTAssertFalse(rows.contains { $0.label.localizedCaseInsensitiveContains("ek3xyz") })
    }

    func testInspectionSearchKeepsComicInfoAndAnimeInfoQueriesSeparate() {
        let reading = readingSeries(
            path: "Manga/Frieren",
            displayName: "Frieren manga",
            mediaType: "manga",
            hasComicInfo: false
        )
        let watching = watchingSeries(
            path: "TV/Frieren",
            displayName: "Frieren anime",
            mediaType: "animeTV",
            hasAnimeInfo: false
        )

        XCTAssertTrue(SableLibraryInspectionSearch.matches(reading, query: "missing comicinfo manga"))
        XCTAssertFalse(SableLibraryInspectionSearch.matches(reading, query: "animeinfo"))
        XCTAssertTrue(SableLibraryInspectionSearch.matches(watching, query: "missing animeinfo anime tv"))
        XCTAssertFalse(SableLibraryInspectionSearch.matches(watching, query: "comicinfo"))
    }

    func testMangaBakaIDParserAcceptsNumericID() {
        XCTAssertEqual(SableLibraryMangaBakaIDParser.id(from: "12345"), "12345")
    }

    func testMangaBakaIDParserAcceptsQueryAndPathURLs() {
        XCTAssertEqual(SableLibraryMangaBakaIDParser.id(from: "https://mangabaka.org/series?id=67890"), "67890")
        XCTAssertEqual(SableLibraryMangaBakaIDParser.id(from: "https://mangabaka.org/series/98765"), "98765")
    }

    func testMangaBakaIDParserAcceptsExplicitLabeledIDText() {
        XCTAssertEqual(SableLibraryMangaBakaIDParser.id(from: "MangaBaka ID: 24680"), "24680")
        XCTAssertEqual(SableLibraryMangaBakaIDParser.id(from: "series id 13579"), "13579")
    }

    func testMangaBakaIDParserRejectsUnlabeledNumbers() {
        XCTAssertNil(SableLibraryMangaBakaIDParser.id(from: "Volume 4 looks right"))
        XCTAssertNil(SableLibraryMangaBakaIDParser.id(from: "not a match"))
    }

    func testAppleBooksRepairRejectsUnsafeArchiveEntryNames() {
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("mimetype"))
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("META-INF/container.xml"))
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("OPS/chapter-01.xhtml"))

        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("/absolute/path"))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("../outside.txt"))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("OPS/../outside.txt"))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("OPS\\..\\outside.txt"))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe("."))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.archiveEntryNameIsSafe(""))
    }

    func testAppleBooksArchiveSnapshotRejectsUnsafeZipRecords() throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let safeArchive = root.appendingPathComponent("safe.epub")
        try writeStoredZip(entries: [StoredZipEntry(name: "mimetype")], to: safeArchive)
        XCTAssertEqual(try SableLibraryAppleBooksCompatibilityRepairer.zipEntryNames(for: safeArchive), ["mimetype"])

        let traversalArchive = root.appendingPathComponent("traversal.epub")
        try writeStoredZip(entries: [StoredZipEntry(name: "../outside.txt")], to: traversalArchive)
        XCTAssertThrowsError(try SableLibraryAppleBooksCompatibilityRepairer.zipEntryNames(for: traversalArchive))

        let symlinkArchive = root.appendingPathComponent("symlink.epub")
        try writeStoredZip(
            entries: [
                StoredZipEntry(name: "OPS/link", externalAttributes: 0xA1FF_0000)
            ],
            to: symlinkArchive
        )
        XCTAssertThrowsError(try SableLibraryAppleBooksCompatibilityRepairer.zipEntryNames(for: symlinkArchive))
    }

    func testAppleBooksRepairCanWriteEPUBImportMetadataFromComicInfo() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/The Saga of Tanya the Evil"
        try writeJSONObject(
            [
                "title": "The Saga of Tanya the Evil",
                "preferred_title": "The Saga of Tanya the Evil",
                "type": "lightNovel",
                "authors": ["Carlo Zen"],
                "artists": ["Shinobu Shinotsuki"],
                "publishers": ["Yen Press"],
                "languages": ["en"],
                "description": "A careful import description.",
                "genres": ["military"],
                "tags": ["alternate history", "bl", "slice of life"],
                "isbn13": ["9780316512442"],
                "mangabaka_url": "https://mangabaka.org/9001",
                "links": [
                    "file:///tmp/ignore-me",
                    "https://ranobedb.org/series/9001"
                ],
                "ids": [
                    "ranobedb": "9001",
                    "open_library": "OL123W"
                ],
                "volumes": [
                    [
                        "number": 1,
                        "title": "The Saga of Tanya the Evil, Vol. 1: Deus lo Vult",
                        "subtitle": "Deus lo Vult",
                        "file_suffix": "Vol 01 - Deus lo Vult",
                        "release_year": 2017,
                        "release_date": 20171219,
                        "pages": 256,
                        "isbn13": ["9780316512442"],
                        "release_ids": ["86002", "86003"],
                        "source_id": [
                            "provider": "ranobedb",
                            "value": "11515"
                        ]
                    ]
                ],
                "_sable": [
                    "mangabaka": [
                        "links_v2": [
                            [
                                "name_display": "MangaBaka",
                                "url": "https://mangabaka.org/9001"
                            ]
                        ],
                        "genres_v2": [
                            [
                                "name": "war drama",
                                "is_genre": true
                            ]
                        ],
                        "tags_v2": [
                            [
                                "name": "military strategy",
                                "is_spoiler": false
                            ],
                            [
                                "name": "Late-volume twist",
                                "is_spoiler": true
                            ]
                        ],
                        "publishers_v2": [
                            [
                                "name": "Kadokawa",
                                "type": "Japanese"
                            ]
                        ]
                    ],
                    "ranobedb": [
                        "outcome": "safeApply",
                        "series_id": "9001",
                        "url": "https://ranobedb.org/series/9001",
                        "api": [
                            "book_responses": [
                                [
                                    "volume_number": 1,
                                    "response": [
                                        "book": [
                                            "staff": [
                                                [
                                                    "role_type": "author",
                                                    "name": "Zen Karuro"
                                                ],
                                                [
                                                    "role_type": "artist",
                                                    "name": "Shinotsuki Shinobu"
                                                ],
                                                [
                                                    "role_type": "translator",
                                                    "name": "Emily Balistrieri"
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "\(folder)/The Saga of Tanya the Evil Vol. 1.epub",
            title: "Old Import Title",
            root: root,
            extraMetadataXML: """
                <meta refines="#sable-isbn-13-old" property="identifier-type" scheme="onix:codelist5">15</meta>
                <meta property="schema:numberOfPages">999</meta>
            """
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.writeEPUBImportMetadata = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB metadata sync", "EPUB tag sync", "EPUB metadata identifiers"])
        XCTAssertEqual(groups.map { $0.items.count }, [1, 1, 1])
        let metadataItem = try XCTUnwrap(groups.first { $0.title == "EPUB metadata sync" }?.items.first)
        let tagsItem = try XCTUnwrap(groups.first { $0.title == "EPUB tag sync" }?.items.first)
        let compatibilityItem = try XCTUnwrap(groups.first { $0.title == "EPUB metadata identifiers" }?.items.first)
        XCTAssertEqual(metadataItem.stage, .epubClinic)
        XCTAssertEqual(tagsItem.stage, .epubClinic)
        XCTAssertEqual(compatibilityItem.stage, .epubClinic)

        let item = metadataItem
        XCTAssertEqual(item.stage, .epubClinic)

        XCTAssertTrue(item.reason.contains("Write ComicInfo metadata into EPUB import fields"), item.reason)
        XCTAssertTrue(item.reason.contains("Write ISBN/provider identifiers"), item.reason)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("epub-scope-metadata"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(tagsItem.reason.contains("Write description and subject tags"), tagsItem.reason)
        XCTAssertEqual(tagsItem.decision, .checked)
        XCTAssertTrue(tagsItem.reviewTags.contains("epub-scope-tags"), tagsItem.reviewTags.joined(separator: ", "))
        XCTAssertTrue(compatibilityItem.reason.contains("orphaned EPUB metadata"), compatibilityItem.reason)
        XCTAssertEqual(compatibilityItem.decision, .checked)
        XCTAssertTrue(compatibilityItem.reviewTags.contains("epub-scope-compatibility"), compatibilityItem.reviewTags.joined(separator: ", "))

        let plan = LibraryPlan(root: root, groups: groups)
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 3, result.summary)
        XCTAssertTrue(result.summary.contains("Selected Sable's Clinic repair rows: 3"), result.summary)
        XCTAssertTrue(result.summary.contains("Unique EPUB files touched: 1 of 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Completed repair rows: 3"), result.summary)

        let epubURL = fileURL("\(folder)/The Saga of Tanya the Evil Vol. 1.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains("<dc:title id=\"sable-title\">The Saga of Tanya the Evil, Vol. 1: Deus lo Vult</dc:title>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-title\" property=\"title-type\">main</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-title\" property=\"file-as\">Saga of Tanya the Evil, Vol. 1: Deus lo Vult, The</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta property=\"dcterms:alternative\" id=\"sable-subtitle\">Deus lo Vult</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta name=\"calibre:title_sort\" content=\"Saga of Tanya the Evil, Vol. 1: Deus lo Vult, The\"/>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:creator id=\"sable-creator-1\">Carlo Zen</dc:creator>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-creator-1\" property=\"role\" scheme=\"marc:relators\">aut</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:creator id=\"sable-creator-2\">Zen Karuro</dc:creator>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-creator-2\" property=\"role\" scheme=\"marc:relators\">aut</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:creator id=\"sable-creator-3\">Shinotsuki Shinobu</dc:creator>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-creator-3\" property=\"role\" scheme=\"marc:relators\">ill</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:creator id=\"sable-creator-4\">Shinobu Shinotsuki</dc:creator>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-creator-4\" property=\"role\" scheme=\"marc:relators\">ill</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:contributor id=\"sable-contributor-1\">Emily Balistrieri</dc:contributor>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-contributor-1\" property=\"role\" scheme=\"marc:relators\">trl</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:publisher>Yen Press</dc:publisher>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:publisher>Kadokawa</dc:publisher>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:language>en</dc:language>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>Military</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>Alternate History</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>BL</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>Slice of Life</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>War Drama</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>Military Strategy</dc:subject>"), opfText)
        XCTAssertFalse(opfText.contains("Late-volume twist"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-isbn-13-1\">urn:isbn:9780316512442</dc:identifier>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-isbn-13-1\" property=\"identifier-type\" scheme=\"onix:codelist5\">15</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-source-ranobedb-9001\">ranobedb:9001</dc:identifier>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-source-ranobedb-11515\">ranobedb:11515</dc:identifier>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-release-ranobedb-86002\">ranobedb-release:86002</dc:identifier>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-release-ranobedb-86003\">ranobedb-release:86003</dc:identifier>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-link-1\">https://mangabaka.org/9001</dc:identifier>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-link-2\">https://ranobedb.org/series/9001</dc:identifier>"), opfText)
        XCTAssertFalse(opfText.contains("file:///tmp/ignore-me"), opfText)
        XCTAssertTrue(opfText.contains("<meta property=\"belongs-to-collection\" id=\"sable-series\">The Saga of Tanya the Evil</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-series\" property=\"collection-type\">series</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-series\" property=\"group-position\">1</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-series\" property=\"file-as\">Saga of Tanya the Evil, The</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta name=\"calibre:series\" content=\"The Saga of Tanya the Evil\"/>"), opfText)
        XCTAssertTrue(opfText.contains("<meta name=\"calibre:series_index\" content=\"1\"/>"), opfText)
        XCTAssertTrue(opfText.contains("<meta property=\"schema:numberOfPages\">256</meta>"), opfText)
        XCTAssertFalse(opfText.contains("sable-isbn-13-old"), opfText)
        XCTAssertFalse(opfText.contains("<meta property=\"schema:numberOfPages\">999</meta>"), opfText)
        XCTAssertNotNil(opfText.range(of: #"<meta property="dcterms:modified">\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z</meta>"#, options: .regularExpression), opfText)
        XCTAssertTrue(opfText.contains("<dc:date>2017-12-19</dc:date>"), opfText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        let followUpItems = followUpGroups.flatMap(\.items)
        XCTAssertTrue(
            followUpItems.isEmpty,
            followUpItems.map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsStandaloneSeriesIndexAndStaleLanguage() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/The Lazy Lord Masters the Sword (2020) {mb-85614}"
        try writeJSONObject(
            [
                "schema": "ComicInfo.Clean.v1",
                "title": "The Lazy Lord Masters the Sword",
                "preferred_title": "The Lazy Lord Masters the Sword",
                "type": "Light Novel",
                "description": """
                Mocked as the laziest man in the kingdom, Airen Farreira sleeps his life away until dreams of a mysterious swordsman change him.
                **Official Translations:**
                [English](https://www.wattpad.com/story/389288158-the-lazy-lord-masters-the-sword)
                """,
                "authors": ["Second Star"],
                "publishers": ["J&C Media"],
                "genres": ["Fantasy", "Action", "Adventure"],
                "ids": [
                    "mangabaka": "85614"
                ],
                "urls": [
                    "official": [
                        "https://www.wattpad.com/story/389288158-the-lazy-lord-masters-the-sword"
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "\(folder)/The Lazy Lord Masters The Sword (2020).epub",
            title: "The Lazy Lord Masters the Sword",
            root: root,
            extraMetadataXML: """
                <dc:language>fr-FR</dc:language>
                <meta name="calibre:series" content="The Lazy Lord Masters the Sword"/>
                <meta name="calibre:title_sort" content="The Lazy Lord Masters the Sword"/>
            """
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.writeEPUBImportMetadata = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let items = groups.flatMap(\.items)
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.contains { $0.reason.contains("Write language metadata") }, items.map(\.reason).joined(separator: "\n"))
        XCTAssertTrue(items.contains { $0.reason.contains("Write series and volume import metadata") }, items.map(\.reason).joined(separator: "\n"))

        let plan = LibraryPlan(root: root, groups: groups)
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThan(result.appliedCount, 0, result.summary)

        let epubURL = fileURL("\(folder)/The Lazy Lord Masters The Sword (2020).epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains("<dc:title id=\"sable-title\">The Lazy Lord Masters the Sword</dc:title>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:language>en</dc:language>"), opfText)
        XCTAssertFalse(opfText.contains("<dc:language>fr-FR</dc:language>"), opfText)
        XCTAssertTrue(opfText.contains("<meta name=\"calibre:series\" content=\"The Lazy Lord Masters the Sword\"/>"), opfText)
        XCTAssertTrue(opfText.contains("<meta name=\"calibre:series_index\" content=\"1\"/>"), opfText)
        XCTAssertTrue(opfText.contains("<meta name=\"calibre:title_sort\" content=\"Lazy Lord Masters the Sword, The\"/>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-series\" property=\"group-position\">1</meta>"), opfText)
    }

    func testEPUBClinicReadsGroupedCompactComicInfoFields() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Compact Grouped Series"
        try writeJSONObject(
            [
                "schema": "ComicInfo.Clean.v1",
                "title": "Compact Grouped Series",
                "preferred_title": "Compact Grouped Series",
                "type": "Light Novel",
                "creators": [
                    "authors": ["Grouped Author"],
                    "artists": ["Grouped Artist"],
                    "contributors": ["Grouped Translator"]
                ],
                "ids": [
                    "mangabaka": "222",
                    "ranobedb": "1234"
                ],
                "urls": [
                    "mangabaka": "https://mangabaka.org/222",
                    "cover": "https://images.mangabaka.dev/compact-cover.jpg",
                    "external": [
                        [
                            "name": "Official site",
                            "type": "info",
                            "url": "https://example.com/compact-grouped-series"
                        ]
                    ]
                ],
                "publishers": ["Grouped Press"],
                "languages": ["en"],
                "description": "A compact sidecar description.",
                "genres": ["Fantasy"],
                "tags": ["Magic"],
                "volumes": [
                    [
                        "number": 1,
                        "title": "Compact Grouped Series, Vol. 1: First Spell",
                        "subtitle": "First Spell",
                        "release_year": 2024,
                        "release_date": 20240102,
                        "pages": 222,
                        "isbn13": ["9780000000222"],
                        "source_id": [
                            "provider": "ranobedb",
                            "value": "5678"
                        ],
                        "release_ids": ["999"]
                    ]
                ],
                "organizer": [
                    "source_id": [
                        "provider": "ranobedb",
                        "value": "1234"
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeFile("\(folder)/Compact Grouped Series Vol. 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let metadata = try XCTUnwrap(service.epubImportMetadataCandidate(
            for: fileURL("\(folder)/Compact Grouped Series Vol. 1.epub", root: root),
            root: root,
            config: .fallback
        ))

        XCTAssertEqual(metadata.title, "Compact Grouped Series, Vol. 1: First Spell")
        XCTAssertEqual(metadata.subtitle, "First Spell")
        XCTAssertEqual(metadata.seriesTitle, "Compact Grouped Series")
        XCTAssertEqual(metadata.authors, ["Grouped Author"])
        XCTAssertEqual(metadata.artists, ["Grouped Artist"])
        XCTAssertEqual(metadata.contributors, ["Grouped Translator"])
        XCTAssertEqual(metadata.publishers, ["Grouped Press"])
        XCTAssertEqual(metadata.languages, ["en"])
        XCTAssertEqual(metadata.description, "A compact sidecar description.")
        XCTAssertEqual(metadata.subjects, ["Fantasy", "Magic"])
        XCTAssertEqual(metadata.isbn13, ["9780000000222"])
        XCTAssertEqual(metadata.coverURL, "https://images.mangabaka.dev/compact-cover.jpg")
        XCTAssertEqual(metadata.releaseYear, 2024)
        XCTAssertEqual(metadata.releaseDate, 20240102)
        XCTAssertEqual(metadata.pageCount, 222)
        XCTAssertTrue(metadata.sourceIDs.contains(SableLibrarySourceID(provider: .mangabaka, value: "222")))
        XCTAssertTrue(metadata.sourceIDs.contains(SableLibrarySourceID(provider: .ranobedb, value: "1234")))
        XCTAssertTrue(metadata.sourceIDs.contains(SableLibrarySourceID(provider: .ranobedb, value: "5678")))

        let extraIdentifierValues = metadata.extraIdentifiers.map { $0.value }
        XCTAssertTrue(extraIdentifierValues.contains("ranobedb-release:999"), extraIdentifierValues.joined(separator: ", "))
        XCTAssertTrue(extraIdentifierValues.contains("https://mangabaka.org/222"), extraIdentifierValues.joined(separator: ", "))
        XCTAssertTrue(extraIdentifierValues.contains("https://example.com/compact-grouped-series"), extraIdentifierValues.joined(separator: ", "))
        XCTAssertFalse(extraIdentifierValues.contains("https://images.mangabaka.dev/compact-cover.jpg"))
    }

    func testEPUBClinicSplitsMetadataSyncByWorkType() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONObject(
            [
                "title": "Quiet Novel",
                "preferred_title": "Quiet Novel",
                "type": "lightNovel",
                "authors": ["Novel Author"],
                "tags": ["slice of life"]
            ],
            to: "Light Novels/Quiet Novel/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "Light Novels/Quiet Novel/Quiet Novel Vol. 1.epub",
            title: "Old Novel Title",
            root: root
        )

        try writeJSONObject(
            [
                "title": "Quiet Manga",
                "preferred_title": "Quiet Manga",
                "type": "manga",
                "authors": ["Manga Author"],
                "tags": ["school life"]
            ],
            to: "Manga/Quiet Manga/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "Manga/Quiet Manga/Quiet Manga Vol. 1.epub",
            title: "Old Manga Title",
            root: root
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)

        XCTAssertEqual(groups.map(\.title), [
            "EPUB metadata sync",
            "EPUB tag sync"
        ])
        XCTAssertEqual(groups.map { $0.items.count }, [2, 2])
        XCTAssertTrue(groups.allSatisfy { group in
            group.items.allSatisfy {
                $0.operation == .repairAppleBooksCompatibility
                    && $0.decision == .checked
                    && $0.safety == .reversible
            }
        })
        XCTAssertTrue(groups[0].items.allSatisfy { $0.reviewTags.contains("epub-scope-metadata") })
        XCTAssertTrue(groups[1].items.allSatisfy { $0.reviewTags.contains("epub-scope-tags") })

        var tagsOnlyGroups = groups
        tagsOnlyGroups = tagsOnlyGroups.map { group in
            var updatedGroup = group
            updatedGroup.items = updatedGroup.items.map { item in
                var updatedItem = item
                updatedItem.decision = item.reviewTags.contains("epub-scope-tags") ? .checked : .unchecked
                return updatedItem
            }
            return updatedGroup
        }

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: tagsOnlyGroups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 2, result.summary)

        let novelOPF = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText(
            "OPS/content.opf",
            in: fileURL("Light Novels/Quiet Novel/Quiet Novel Vol. 1.epub", root: root)
        ))
        XCTAssertTrue(novelOPF.contains("<dc:title>Old Novel Title</dc:title>"), novelOPF)
        XCTAssertFalse(novelOPF.contains("<dc:title id=\"sable-title\">Quiet Novel</dc:title>"), novelOPF)
        XCTAssertTrue(novelOPF.contains("<dc:subject>Slice of Life</dc:subject>"), novelOPF)
    }

    func testEPUBClinicKeepsLargeScopesMergedInSingleReviewGroup() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let epubPath = "Books/Bulk Tags.epub"
        try writeEPUBFixture(
            epubPath,
            title: "Bulk Tags",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:subject>science fiction</dc:subject>
                <dc:subject>male protagonist</dc:subject>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        var inspection = LibraryInspection.empty(root: root)
        inspection.books = (1...251).map { index in
            LibraryBookSnapshot(
                id: "bulk-tags-\(index)",
                path: epubPath,
                fileName: "Bulk Tags.epub",
                fileExtension: "epub",
                seriesID: "Books",
                isPackageBook: false
            )
        }
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)

        XCTAssertEqual(groups.map(\.title), ["EPUB tag sync"])
        XCTAssertEqual(groups.first?.items.count, 251)
        XCTAssertFalse(groups.first?.summary.contains("This batch covers") ?? true)
    }

    func testEPUBClinicQuickVerifyChecksOnlyChangedEPUBPaths() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Changed Subjects.epub",
            title: "Changed Subjects",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:subject>science fiction</dc:subject>
            """
        )
        try writeEPUBFixture(
            "Books/Unchanged Subjects.epub",
            title: "Unchanged Subjects",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:subject>male protagonist</dc:subject>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await SableLibraryPipelineCoordinator(service: service).quickVerifyAndBuildPlan(
            root: root,
            options: options,
            previousStage: .epubClinic,
            changedPaths: ["Books/Changed Subjects.epub"]
        )

        let items = run.context.plan.items
        XCTAssertEqual(items.map(\.currentPath), ["Books/Changed Subjects.epub"])
        XCTAssertEqual(run.context.plan.groups.map(\.title), ["EPUB tag sync"])
    }

    func testEPUBClinicFocusedInspectUsesLeanEPUBInventory() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Clinic Subject.epub",
            title: "Clinic Subject",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:subject>science fiction</dc:subject>
            """
        )
        try writeFile("Manga/Quiet Hero/Vol 01.cbz", contents: "book", root: root)
        try writeFile("Videos/Quiet Show/Quiet Show - S01E01.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stageOptions = LibraryPipelineStageOptions()
        stageOptions.deepEPUBContentChecks = false
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stageOptions,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .epubClinic)
        let inspection = try XCTUnwrap(run.context.inspection)

        XCTAssertEqual(run.context.inspectMode, .stageDeepDive(.epubClinic))
        XCTAssertEqual(inspection.bookFileCount, 1)
        XCTAssertEqual(inspection.videoFileCount, 0)
        XCTAssertTrue(inspection.series.isEmpty)
        XCTAssertTrue(inspection.videoSeries.isEmpty)
        XCTAssertNil(inspection.fileTypeCounts["mkv"])
        XCTAssertEqual(run.context.plan.groups.map(\.title), ["EPUB tag sync"])
    }

    func testEPUBClinicCleansLowercaseSubjectTags() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Lowercase Subjects.epub",
            title: "Lowercase Subjects",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:subject>science fiction</dc:subject>
                <dc:subject>male protagonist</dc:subject>
                <dc:subject>ai</dc:subject>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB tag sync"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertTrue(item.reviewTags.contains("epub-tags"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("subject tag display casing"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)
        XCTAssertTrue(result.summary.contains("Selected Sable's Clinic repair rows: 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Unique EPUB files touched: 1 of 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Completed repair rows: 1"), result.summary)

        let epubURL = fileURL("Books/Lowercase Subjects.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains("<dc:subject>Science Fiction</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>Male Protagonist</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>AI</dc:subject>"), opfText)
        XCTAssertFalse(opfText.contains("<dc:subject>science fiction</dc:subject>"), opfText)
    }

    func testEPUBClinicSetsOldPackageVersionWhenNavigationAlreadyExists() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Old Version With Nav.epub",
            title: "Old Version With Nav",
            root: root,
            includeCover: false,
            packageVersion: "2.0",
            extraManifestXML: """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            extraFiles: [
                "OPS/nav.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter.xhtml">Start</a></li></ol></nav></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB standards profile"])
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("package version"), reasons)
        XCTAssertFalse(reasons.contains("navigation reachability"), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy { $0.decision == .checked })

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)
        XCTAssertTrue(result.summary.contains("Selected Sable's Clinic repair rows: 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Unique EPUB files touched: 1 of 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Completed repair rows: 1"), result.summary)

        let epubURL = fileURL("Books/Old Version With Nav.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"version="3.0""#), opfText)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertFalse(chapterText.contains("EPUB navigation"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRemovesOrphanedMetadataRefinementsAndAlignsNCXIdentifier() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ncxText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta content="urn:uuid:old-ncx-id" name="dtb:uid" />
            <meta name="dtb:depth" content="1" />
          </head>
          <docTitle><text>Orphaned Refinements</text></docTitle>
          <navMap>
            <navPoint id="navPoint-1" playOrder="1">
              <navLabel><text>Chapter 1</text></navLabel>
              <content src="chapter.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """

        try writeEPUBFixture(
            "Books/Orphaned Refinements.epub",
            title: "Orphaned Refinements",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <meta refines="#creator01" property="file-as">AUTHOR, OLD</meta>
                <meta refines="#creator01" property="role" scheme="marc:relators">aut</meta>
            """,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            extraFiles: [
                "OPS/toc.ncx": Data(ncxText.utf8),
                "OPS/nav.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter.xhtml">Chapter 1</a></li></ol></nav></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("orphaned EPUB metadata"), item.reason)
        XCTAssertTrue(item.reason.contains("NCX table of contents identifier"), item.reason)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("epub-scope-compatibility"), item.reviewTags.joined(separator: ", "))

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Orphaned Refinements.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains("creator01"), opfText)
        let freshID = try XCTUnwrap(opfText.range(
            of: #"<dc:identifier id="sable-import-id">([^<]+)</dc:identifier>"#,
            options: .regularExpression
        ).flatMap { range in
            String(opfText[range]).range(of: #">([^<]+)<"#, options: .regularExpression).map { innerRange in
                String(String(opfText[range])[innerRange].dropFirst().dropLast())
            }
        })
        let ncx = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncx.contains(#"name="dtb:uid""#), ncx)
        XCTAssertTrue(ncx.contains(#"content="\#(freshID)""#), ncx)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRefreshesExistingSableImportIdentifierBeforeAligningNCX() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ncxText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta content="urn:uuid:old-ncx-id" name="dtb:uid" />
          </head>
          <docTitle><text>Existing Import ID</text></docTitle>
          <navMap>
            <navPoint id="navPoint-1" playOrder="1">
              <navLabel><text>Chapter 1</text></navLabel>
              <content src="chapter.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """

        try writeEPUBFixture(
            "Books/Existing Import ID.epub",
            title: "Existing Import ID",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:identifier id="sable-import-id">urn:uuid:old-sable-import</dc:identifier>
            """,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            extraFiles: [
                "OPS/toc.ncx": Data(ncxText.utf8),
                "OPS/nav.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter.xhtml">Chapter 1</a></li></ol></nav></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("NCX table of contents identifier"), item.reason)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Existing Import ID.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        let freshID = try XCTUnwrap(opfText.range(
            of: #"<dc:identifier id="sable-import-id">([^<]+)</dc:identifier>"#,
            options: .regularExpression
        ).flatMap { range in
            String(opfText[range]).range(of: #">([^<]+)<"#, options: .regularExpression).map { innerRange in
                String(String(opfText[range])[innerRange].dropFirst().dropLast())
            }
        })
        XCTAssertNotEqual(freshID, "urn:uuid:old-sable-import", opfText)

        let ncx = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncx.contains(#"content="\#(freshID)""#), ncx)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicNormalizesLegacyDublinCoreAttributes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Legacy Metadata Attributes.epub",
            title: "Legacy Metadata Attributes",
            root: root,
            includeCover: false,
            extraMetadataXML: """
                <dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" opf:scheme="MOBI-ASIN">B00F016TBI</dc:identifier>
                <dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" id="legacy-isbn" opf:scheme="ISBN">9780316512442</dc:identifier>
                <dc:contributor xmlns:opf="http://www.idpf.org/2007/opf" opf:role="bkp">calibre</dc:contributor>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB metadata identifiers"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("legacy EPUB metadata"), item.reason)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Legacy Metadata Attributes.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains("opf:scheme"), opfText)
        XCTAssertFalse(opfText.contains("opf:role"), opfText)
        XCTAssertTrue(opfText.contains(#"<dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" id="sable-identifier-legacy">B00F016TBI</dc:identifier>"#), opfText)
        XCTAssertTrue(opfText.contains(##"<meta refines="#sable-identifier-legacy" property="identifier-type">MOBI-ASIN</meta>"##), opfText)
        XCTAssertTrue(opfText.contains(#"<dc:identifier xmlns:opf="http://www.idpf.org/2007/opf" id="legacy-isbn">9780316512442</dc:identifier>"#), opfText)
        XCTAssertTrue(opfText.contains(##"<meta refines="#legacy-isbn" property="identifier-type" scheme="onix:codelist5">15</meta>"##), opfText)
        XCTAssertTrue(opfText.contains(#"<dc:contributor xmlns:opf="http://www.idpf.org/2007/opf" id="sable-contributor-legacy">calibre</dc:contributor>"#), opfText)
        XCTAssertTrue(opfText.contains(##"<meta refines="#sable-contributor-legacy" property="role" scheme="marc:relators">bkp</meta>"##), opfText)
    }

    func testEPUBClinicRepairsNonNamespacedMetadataMetaTags() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Non Namespaced Metadata.epub",
            title: "Non Namespaced Metadata",
            root: root,
            includeCover: false,
            extraMetadataXML: #"<meta content="book" name="BNContentKind" xmlns=""/>"#
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB metadata identifiers"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("non-namespaced EPUB metadata"), item.reason)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableOperation)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Non Namespaced Metadata.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"<meta content="book" name="BNContentKind"/>"#), opfText)
        XCTAssertFalse(opfText.contains(#"xmlns="""#), opfText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRemovesInvalidMetadataRefinementsAndBrokenGuideReferences() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Invalid Refinements And Guide.epub",
            title: "Invalid Refinements And Guide",
            root: root,
            extraMetadataXML: """
                <dc:identifier id="legacy-id">urn:uuid:legacy</dc:identifier>
                <meta refines="#legacy-id" property="role" scheme="marc:relators">aut</meta>
                <meta refines="#legacy-id" property="title-type">main</meta>
            """,
            extraPackageXML: """
              <guide>
                <reference type="text" title="Missing" href="missing.xhtml"/>
                <reference type="cover" title="Cover Image" href="cover.jpg"/>
              </guide>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB package layer", "EPUB metadata identifiers"])
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("invalid EPUB metadata"), reasons)
        XCTAssertTrue(reasons.contains("broken EPUB guide"), reasons)
        let packageItem = try XCTUnwrap(groups.first { $0.title == "EPUB package layer" }?.items.first)
        XCTAssertTrue(packageItem.reviewTags.contains("epub-guide"), packageItem.reviewTags.joined(separator: ", "))
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy { $0.decision == .checked })

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Invalid Refinements And Guide.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains(#"property="role""#), opfText)
        XCTAssertFalse(opfText.contains(#"property="title-type""#), opfText)
        XCTAssertFalse(opfText.contains("<guide>"), opfText)
        XCTAssertFalse(opfText.contains("<reference"), opfText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicDeclaresContentManifestPropertiesAndRepairsHeaders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Header Compatibility.epub",
            title: "Header Compatibility",
            root: root,
            includeCover: false,
            chapterText: """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
              "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head>
                <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=UTF-8"/>
                <meta http-equiv="Content-Style-Type" content="text/css"/>
                <title>   </title>
              </head>
              <body>
                <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 10 10"></svg>
                <script type="text/javascript">window.SableFixture = true;</script>
              </body>
            </html>
            """
        )

        let fixtureURL = fileURL("Books/Header Compatibility.epub", root: root)
        let originalChapterText = try XCTUnwrap(
            try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: fixtureURL)
        )
        XCTAssertTrue(originalChapterText.contains("<!DOCTYPE html PUBLIC"), originalChapterText)

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let groupTitles = groups.map(\.title)
        XCTAssertTrue(groupTitles.contains("EPUB package layer"), groupTitles.joined(separator: ", "))
        XCTAssertTrue(groupTitles.contains("EPUB content layer"), groupTitles.joined(separator: ", "))
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("Declare scripted"), reasons)
        XCTAssertTrue(reasons.contains("Declare svg"), reasons)
        XCTAssertTrue(reasons.contains("legacy XHTML doctype"), reasons)
        XCTAssertTrue(reasons.contains("content-type meta"), reasons)
        XCTAssertTrue(reasons.contains("http-equiv meta"), reasons)
        XCTAssertTrue(reasons.contains("empty EPUB content document title"), reasons)
        let packageItem = try XCTUnwrap(groups.first { $0.title == "EPUB package layer" }?.items.first)
        XCTAssertTrue(packageItem.reviewTags.contains("epub-scope-package"), packageItem.reviewTags.joined(separator: ", "))
        let contentItem = try XCTUnwrap(groups.first { $0.title == "EPUB content layer" }?.items.first)
        XCTAssertTrue(contentItem.reviewTags.contains("epub-content"), contentItem.reviewTags.joined(separator: ", "))
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy { $0.decision == .checked })

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Header Compatibility.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        let chapterItem = try XCTUnwrap(opfText.range(
            of: #"<item id="chapter"[^>]+>"#,
            options: .regularExpression
        ).map { String(opfText[$0]) })
        XCTAssertTrue(chapterItem.contains("scripted"), chapterItem)
        XCTAssertTrue(chapterItem.contains("svg"), chapterItem)

        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains("<!DOCTYPE html>"), chapterText)
        XCTAssertFalse(chapterText.contains("XHTML 1.1"), chapterText)
        XCTAssertTrue(chapterText.contains(#"content="text/html; charset=utf-8""#), chapterText)
        XCTAssertFalse(chapterText.contains("Content-Style-Type"), chapterText)
        XCTAssertTrue(chapterText.contains("<title>Header Compatibility</title>"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsEPUBCheckPackageAndContentFindings() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/EPUBCheck Package Content.epub",
            title: "EPUBCheck Package Content",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="body-font" href="Fonts/Body.ttf" media-type="application/x-font-truetype"/>
                <item id="plain" href="plain.xhtml" media-type="application/xhtml+xml" properties="scripted"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <div data-AmznRemoved-M8="true">One&nbsp;two</div>
                <p id="same">First duplicate id</p>
                <p id="same">Second duplicate id</p>
              </body>
            </html>
            """,
            extraFiles: [
                "OPS/Fonts/Body.ttf": Data("font".utf8),
                "OPS/plain.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Plain page</p></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertTrue(groups.map(\.title).contains("EPUB package layer"), groups.map(\.title).joined(separator: ", "))
        XCTAssertTrue(groups.map(\.title).contains("EPUB content layer"), groups.map(\.title).joined(separator: ", "))
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("font manifest media"), reasons)
        XCTAssertTrue(reasons.contains("false scripted"), reasons)
        XCTAssertTrue(reasons.contains("non-breaking space"), reasons)
        XCTAssertTrue(reasons.contains("custom data"), reasons)
        XCTAssertTrue(reasons.contains("duplicate EPUB content"), reasons)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/EPUBCheck Package Content.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"href="Fonts/Body.ttf" media-type="font/ttf""#), opfText)
        let plainItem = try XCTUnwrap(opfText.range(
            of: #"<item id="plain"[^>]+>"#,
            options: .regularExpression
        ).map { String(opfText[$0]) })
        XCTAssertFalse(plainItem.contains("scripted"), plainItem)

        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains("One&#160;two"), chapterText)
        XCTAssertTrue(chapterText.contains("data-amznremoved-m8"), chapterText)
        XCTAssertTrue(chapterText.contains(#"id="same""#), chapterText)
        XCTAssertTrue(chapterText.contains(#"id="same-sable-2""#), chapterText)
        XCTAssertFalse(chapterText.contains("&nbsp;"), chapterText)
        XCTAssertFalse(chapterText.contains("data-AmznRemoved"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRemovesLegacyPageMapAndToursElements() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Legacy OPF Leftovers.epub",
            title: "Legacy OPF Leftovers",
            root: root,
            includeCover: false,
            spineAttributes: #" page-map="_page_map_""#,
            extraManifestXML: """
                <item id="_page_map_" href="_page_map_.xml" media-type="application/oebps-page-map+xml"/>
            """,
            extraPackageXML: """
              <tours>
              </tours>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("page-map"), reasons)
        XCTAssertTrue(reasons.contains("tours"), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy(\.isApplyableOperation), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy { $0.decision == .checked }, reasons)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Legacy OPF Leftovers.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains(#"page-map=""#), opfText)
        XCTAssertFalse(opfText.contains("<tours"), opfText)
    }

    func testEPUBClinicRepairsParagraphsInsideHeadings() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Heading Paragraphs.epub",
            title: "Heading Paragraphs",
            root: root,
            includeCover: false,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <h2>
                  <p>AI NO KUSABI</p>
                  <p>THE SPACE BETWEEN</p>
                </h2>
              </body>
            </html>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertTrue(groups.map(\.title).contains("EPUB content layer"), groups.map(\.title).joined(separator: ", "))
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("paragraph markup"), reasons)
        XCTAssertFalse(reasons.contains("malformed XHTML"), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy(\.isApplyableOperation), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy { $0.decision == .checked }, reasons)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Heading Paragraphs.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains("<h2>AI NO KUSABI</h2>"), chapterText)
        XCTAssertTrue(chapterText.contains("<h2>THE SPACE BETWEEN</h2>"), chapterText)
        XCTAssertFalse(chapterText.contains("<h2>\n                  <p>"), chapterText)
    }

    func testEPUBClinicDoesNotSpinOnLargeMixedHeadingMarkup() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let noisyHeading = (0..<500)
            .map { "<p>Least Interesting Master Swordsman \($0)</p>" }
            .joined(separator: "\n")

        try writeEPUBFixture(
            "Books/Large Mixed Heading.epub",
            title: "Large Mixed Heading",
            root: root,
            includeCover: false,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <h2>
                  \(noisyHeading)
                  <span>Publisher inserted an inline note inside the heading.</span>
                </h2>
              </body>
            </html>
            """
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.epubClinicRepairScopes = [.content]
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertFalse(reasons.contains("paragraph markup"), reasons)
    }

    func testEPUBClinicRepairsCommonXHTMLParserRecoveryIssues() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/XHTML Parser Recovery.epub",
            title: "XHTML Parser Recovery",
            root: root,
            includeCover: false,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head>
                <meta charset="utf-8">
                <title>XHTML Parser Recovery</title>
              </head>
              <body>
                <p>Fish & Chips &mdash; with a line break<br></p>
              </body>
            </html>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB content layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("XHTML named"), item.reason)
        XCTAssertTrue(item.reason.contains("bare XHTML ampersand"), item.reason)
        XCTAssertTrue(item.reason.contains("XHTML void element"), item.reason)
        XCTAssertFalse(item.reason.contains("before repair"), item.reason)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableOperation)
        XCTAssertTrue(item.reviewTags.contains("epub-xhtml"), item.reviewTags.joined(separator: ", "))
        XCTAssertFalse(item.reviewTags.contains("ml-training-epub-manual-review"), item.reviewTags.joined(separator: ", "))

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/XHTML Parser Recovery.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains(#"<meta charset="utf-8" />"#), chapterText)
        XCTAssertTrue(chapterText.contains("Fish &amp; Chips &#8212;"), chapterText)
        XCTAssertTrue(chapterText.contains("<br />"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicModernizesOldPackageWithEPUB3MetadataAndCreatesNavigation() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Old Package With EPUB3 Metadata.epub",
            title: "Old Package With EPUB3 Metadata",
            root: root,
            includeCover: false,
            packageVersion: "2.0",
            extraMetadataXML: """
                <meta property="belongs-to-collection" id="series-title">Old Series</meta>
            """,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
            """,
            extraSpineXML: """
                <itemref idref="chapter2"/>
            """,
            extraFiles: [
                "OPS/chapter2.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Second page</p></body></html>"#.utf8),
                "OPS/toc.ncx": Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <head><meta name="dtb:uid" content="urn:uuid:fixture"/></head>
                  <docTitle><text>Old Package With EPUB3 Metadata</text></docTitle>
                  <navMap>
                    <navPoint id="navPoint-1" playOrder="1">
                      <navLabel><text>Arrival</text></navLabel>
                      <content src="chapter.xhtml"/>
                    </navPoint>
                    <navPoint id="navPoint-2" playOrder="2">
                      <navLabel><text>Second Page</text></navLabel>
                      <content src="chapter2.xhtml"/>
                    </navPoint>
                  </navMap>
                </ncx>
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("Modernize EPUB 3.3/3.4 package wiring"), reasons)
        XCTAssertTrue(reasons.contains("Create EPUB3 navigation document"), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy(\.isApplyableOperation), reasons)
        XCTAssertTrue(groups.flatMap(\.items).allSatisfy { $0.decision == .checked }, reasons)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Old Package With EPUB3 Metadata.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"version="3.0""#), opfText)
        XCTAssertTrue(opfText.contains(#"properties="nav""#), opfText)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertFalse(chapterText.contains("EPUB navigation"), chapterText)
        let navText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/nav.xhtml", in: epubURL))
        XCTAssertTrue(navText.contains("Arrival"), navText)
        XCTAssertTrue(navText.contains("Second Page"), navText)
    }

    func testEPUBClinicDoesNotAddHiddenReachabilityLinkForExistingNavigationDocument() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Unreachable Nav.epub",
            title: "Unreachable Nav",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            extraFiles: [
                "OPS/nav.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter.xhtml">Chapter</a></li></ol></nav></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(groups.isEmpty, reasons)
        XCTAssertFalse(reasons.contains("navigation reachability"), reasons)

        let epubURL = fileURL("Books/Unreachable Nav.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertFalse(chapterText.contains(#"href="nav.xhtml""#), chapterText)
        XCTAssertFalse(chapterText.contains("EPUB navigation"), chapterText)
    }

    func testEPUBClinicRepairsNavigationFragmentsAndNCXPlayOrder() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/EPUBCheck Navigation.epub",
            title: "EPUBCheck Navigation",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="toc-file" href="toc.xhtml" media-type="application/xhtml+xml"/>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <p>Chapter</p>
                <p><a href="toc.xhtml#missing">Copyright</a></p>
              </body>
            </html>
            """,
            extraFiles: [
                "OPS/toc.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p id="present">Copyright</p></body></html>"#.utf8),
                "OPS/toc.ncx": Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <head><meta name="dtb:uid" content="urn:uuid:old"/></head>
                  <docTitle><text>EPUBCheck Navigation</text></docTitle>
                  <navMap>
                    <navPoint id="nav-1" playOrder="1"><navLabel><text>Chapter</text></navLabel><content src="chapter.xhtml"/></navPoint>
                    <navPoint id="nav-2" playOrder="4"><navLabel><text>Copyright</text></navLabel><content src="toc.xhtml#present"/></navPoint>
                  </navMap>
                  <pageList>
                    <pageTarget id="page-1" type="normal" value="1" playOrder="1"><navLabel><text>1</text></navLabel><content src="chapter.xhtml"/></pageTarget>
                    <pageTarget id="page-2" type="normal" value="2" playOrder="1"><navLabel><text>2</text></navLabel><content src="toc.xhtml#present"/></pageTarget>
                  </pageList>
                </ncx>
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertTrue(groups.map(\.title).contains("EPUB navigation layer"), groups.map(\.title).joined(separator: ", "))
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("local link fragment"), reasons)
        XCTAssertTrue(reasons.contains("playOrder"), reasons)
        XCTAssertTrue(reasons.contains("pageList"), reasons)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/EPUBCheck Navigation.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains(#"href="toc.xhtml""#), chapterText)
        XCTAssertFalse(chapterText.contains("#missing"), chapterText)

        let ncxText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncxText.contains(#"playOrder="1""#), ncxText)
        XCTAssertTrue(ncxText.contains(#"playOrder="2""#), ncxText)
        XCTAssertFalse(ncxText.contains(#"playOrder="4""#), ncxText)
        XCTAssertFalse(ncxText.contains("<pageList"), ncxText)
        XCTAssertFalse(ncxText.contains("<pageTarget"), ncxText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsIncompleteNCXNavigationPoints() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Incomplete NCX NavPoint.epub",
            title: "Incomplete NCX NavPoint",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            """,
            extraFiles: [
                "OPS/toc.ncx": Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <head><meta name="dtb:uid" content="urn:uuid:old"/></head>
                  <docTitle><text>Incomplete NCX NavPoint</text></docTitle>
                  <navMap>
                    <navPoint id="nav-1" playOrder="1"><navLabel><text>Chapter</text></navLabel><content src="chapter.xhtml"/></navPoint>
                    <navPoint id="nav-dead" playOrder="2"><navLabel><text>Loose heading</text></navLabel></navPoint>
                  </navMap>
                </ncx>
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("incomplete NCX navigation"), item.reason)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableOperation)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Incomplete NCX NavPoint.epub", root: root)
        let ncxText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncxText.contains(#"content src="chapter.xhtml""#), ncxText)
        XCTAssertFalse(ncxText.contains("nav-dead"), ncxText)
        XCTAssertFalse(ncxText.contains("Loose heading"), ncxText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRemovesStaleNavigationLinks() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Stale Navigation Link.epub",
            title: "Stale Navigation Link",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="nav" href="Text/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body><p>Chapter</p></body>
            </html>
            """,
            extraFiles: [
                "OPS/Text/nav.xhtml": Data("""
                <html xmlns="http://www.w3.org/1999/xhtml">
                  <body>
                    <nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops">
                      <ol>
                        <li><a href="../chapter.xhtml">Chapter</a></li>
                        <li><a href="jnovels.xhtml">Jnovels</a></li>
                      </ol>
                    </nav>
                  </body>
                </html>
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("stale EPUB navigation"), item.reason)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Stale Navigation Link.epub", root: root)
        let navText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/Text/nav.xhtml", in: epubURL))
        XCTAssertTrue(navText.contains("chapter.xhtml"), navText)
        XCTAssertFalse(navText.contains("jnovels.xhtml"), navText)
        XCTAssertFalse(navText.contains("Jnovels"), navText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsMissingManifestResourcesAndDeadSpineReferences() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Package Resource Repairs.epub",
            title: "Package Resource Repairs",
            root: root,
            includeCover: true,
            extraSpineXML: """
                <itemref idref="missing-spine-item"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <p><img src="Images/page.png" alt=""/></p>
              </body>
            </html>
            """,
            extraFiles: [
                "OPS/Images/page.png": pngHeaderFixtureData(width: 600, height: 900)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB package layer"])
        let reasons = groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        XCTAssertTrue(reasons.contains("missing EPUB manifest resource"), reasons)
        XCTAssertTrue(reasons.contains("dead EPUB spine"), reasons)
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reviewTags.contains("epub-resource-manifest"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-spine"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Package Resource Repairs.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"href="Images/page.png" media-type="image/png""#), opfText)
        XCTAssertFalse(opfText.contains(#"idref="missing-spine-item""#), opfText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRetargetsMissingLinkedResourcesAsRunnableContentRepair() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Linked Resource Repair.epub",
            title: "Linked Resource Repair",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="page-image" href="Images/page.png" media-type="image/png"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>Linked Resource Repair</title></head>
              <body>
                <p><img src="Images/Page.PNG" alt=""/></p>
              </body>
            </html>
            """,
            extraFiles: [
                "OPS/Images/page.png": pngHeaderFixtureData(width: 600, height: 900)
            ]
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.deepEPUBContentChecks = true
        stages.epubClinicRepairScopes = [.content]
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB content layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("missing EPUB linked"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("epub-missing-resource"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-content"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableOperation)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Linked Resource Repair.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains(#"src="Images/page.png""#), chapterText)
        XCTAssertFalse(chapterText.contains(#"src="Images/Page.PNG""#), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRemovesMissingScriptFromNavigationDocument() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Nav Missing Script.epub",
            title: "Nav Missing Script",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            extraFiles: [
                "OPS/nav.xhtml": Data("""
                <html xmlns="http://www.w3.org/1999/xhtml">
                  <head><title>Nav Missing Script</title><script type="text/javascript" src="js/kobo.js"></script></head>
                  <body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter.xhtml">Chapter</a></li></ol></nav></body>
                </html>
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB package layer", "EPUB content layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.reason.contains("missing local EPUB script") })
        XCTAssertTrue(item.reason.contains("missing local EPUB script"), item.reason)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableOperation)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 2, result.summary)

        let epubURL = fileURL("Books/Nav Missing Script.epub", root: root)
        let navText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/nav.xhtml", in: epubURL))
        XCTAssertFalse(navText.contains("kobo.js"), navText)
        XCTAssertFalse(navText.contains("<script"), navText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsSimpleCSSSyntax() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/CSS Syntax Cleanup.epub",
            title: "CSS Syntax Cleanup",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="style" href="Styles/site.css" media-type="text/css"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head>
                <link rel="stylesheet" type="text/css" href="Styles/site.css"/>
              </head>
              <body><p>Styled.</p></body>
            </html>
            """,
            extraFiles: [
                "OPS/Styles/site.css": Data("""
                <!--
                body { color: red;; }
                -->
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB content layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("simple EPUB CSS syntax"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("epub-css"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertGreaterThanOrEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/CSS Syntax Cleanup.epub", root: root)
        let cssText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/Styles/site.css", in: epubURL))
        XCTAssertFalse(cssText.contains("<!--"), cssText)
        XCTAssertFalse(cssText.contains("-->"), cssText)
        XCTAssertFalse(cssText.contains(";;"), cssText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicTurnsKnownEPUBCheckFindingsIntoRunnableRepairRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Manual Diagnostics.epub",
            title: "Manual Diagnostics",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="risky-css" href="Styles/risky.css" media-type="text/css"/>
                <item id="duplicate-id" href="unused.xhtml" media-type="application/xhtml+xml"/>
                <item id="duplicate-id" href="unused-2.xhtml" media-type="application/xhtml+xml"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body>
                <p id="same">One</p>
                <p id="same">Two</p>
                <img src="Images/missing.jpg" alt=""/>
              </body>
            </html>
            """,
            extraFiles: [
                "OPS/Styles/risky.css": Data("body { color: red;".utf8),
                "OPS/unused.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Unused</p></body></html>"#.utf8),
                "OPS/unused-2.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Unused 2</p></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let groupTitles = groups.map(\.title)
        XCTAssertTrue(groupTitles.contains("EPUB package layer"), groupTitles.joined(separator: ", "))
        XCTAssertTrue(groupTitles.contains("EPUB content layer"), groupTitles.joined(separator: ", "))

        let packageItem = try XCTUnwrap(groups.flatMap(\.items).first { $0.reason.contains("duplicate EPUB manifest") })
        XCTAssertEqual(packageItem.safety, .reversible)
        XCTAssertEqual(packageItem.decision, .checked)
        XCTAssertFalse(packageItem.requiresReview)
        XCTAssertTrue(packageItem.isApplyableOperation)
        XCTAssertTrue(packageItem.reviewTags.contains("epub-duplicate-id"), packageItem.reviewTags.joined(separator: ", "))
        XCTAssertTrue(packageItem.reviewTags.contains("epub-manifest"), packageItem.reviewTags.joined(separator: ", "))

        let contentItem = try XCTUnwrap(groups.flatMap(\.items).first { $0.reason.contains("duplicate EPUB content") })
        XCTAssertTrue(contentItem.reason.contains("simple EPUB CSS syntax"), contentItem.reason)
        XCTAssertTrue(contentItem.reason.contains("missing EPUB linked resource"), contentItem.reason)
        XCTAssertEqual(contentItem.safety, .reversible)
        XCTAssertEqual(contentItem.decision, .checked)
        XCTAssertFalse(contentItem.requiresReview)
        XCTAssertTrue(contentItem.isApplyableOperation)
        XCTAssertTrue(contentItem.reviewTags.contains("epub-duplicate-id"), contentItem.reviewTags.joined(separator: ", "))
        XCTAssertTrue(contentItem.reviewTags.contains("epub-css"), contentItem.reviewTags.joined(separator: ", "))

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 2, result.summary)

        let epubURL = fileURL("Books/Manual Diagnostics.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"id="duplicate-id""#), opfText)
        XCTAssertTrue(opfText.contains(#"id="duplicate-id-sable-2""#), opfText)

        let cssText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/Styles/risky.css", in: epubURL))
        XCTAssertTrue(cssText.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}"), cssText)

        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertFalse(chapterText.contains("Images/missing.jpg"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsOrphanXHTMLInlineClosingTagsAsContentWork() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Orphan Inline Close.epub",
            title: "Orphan Inline Close",
            root: root,
            includeCover: false,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head>
                <title>Orphan Inline Close</title>
                <script type="text/javascript" src="../js/kobo.js"></script>
              </head>
              <body>
                <p>Newsletter sentence with no opening span.</span></p>
              </body>
            </html>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB package layer", "EPUB content layer"])

        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.reason.contains("orphan XHTML inline closing") })
        XCTAssertTrue(item.reason.contains("orphan XHTML inline closing"), item.reason)
        XCTAssertTrue(item.reason.contains("missing local EPUB script"), item.reason)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableOperation)
        XCTAssertTrue(item.reviewTags.contains("epub-content"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-xhtml"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-scripted"), item.reviewTags.joined(separator: ", "))
        XCTAssertFalse(item.reviewTags.contains("ml-training-epub-manual-review"), item.reviewTags.joined(separator: ", "))

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 2, result.summary)

        let epubURL = fileURL("Books/Orphan Inline Close.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertFalse(chapterText.contains("</span></p>"), chapterText)
        XCTAssertFalse(chapterText.contains("kobo.js"), chapterText)
        XCTAssertTrue(chapterText.contains("opening span.</p>"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicDoesNotTreatCoverDimensionsAsEPUBCheckRepairs() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Small Square Cover.epub",
            title: "Small Square Cover",
            root: root,
            coverHref: "cover.png",
            coverMediaType: "image/png",
            coverData: pngHeaderFixtureData(width: 180, height: 180)
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.deepEPUBContentChecks = true
        stages.epubClinicRepairScopes = SableClinicCheckProfile.deep.repairScopes
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let epubURL = fileURL("Books/Small Square Cover.epub", root: root)
        let analysis = service.appleBooksCompatibilityRepairAnalysis(
            for: epubURL,
            relativePath: "Books/Small Square Cover.epub",
            root: root,
            config: service.currentConfig(),
            deepContentChecks: true,
            repairScopes: stages.epubClinicRepairScopes
        )
        XCTAssertNil(analysis)

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertTrue(
            groups.isEmpty,
            groups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRemovesDuplicateCoverImageMarkers() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Duplicate Cover Markers.epub",
            title: "Duplicate Cover Markers",
            root: root,
            extraManifestXML: """
                <item id="illustration" href="Images/page.jpg" media-type="image/jpeg" properties="cover-image"/>
            """,
            extraFiles: [
                "OPS/Images/page.jpg": Data("page".utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB cover/image layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("duplicate cover-image marker"), item.reason)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Duplicate Cover Markers.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image""#), opfText)
        let illustrationItem = try XCTUnwrap(opfText.range(
            of: #"<item id="illustration"[^>]+>"#,
            options: .regularExpression
        ).map { String(opfText[$0]) })
        XCTAssertFalse(illustrationItem.contains("cover-image"), illustrationItem)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicCoverPassOnlySurfacesCoverRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Mixed Repair EPUB.epub",
            title: "Mixed Repair EPUB",
            root: root,
            extraMetadataXML: """
                <meta refines="#missing-id" property="identifier-type">15</meta>
            """,
            extraManifestXML: """
                <item id="illustration" href="Images/page.jpg" media-type="image/jpeg" properties="cover-image"/>
            """,
            extraFiles: [
                "OPS/Images/page.jpg": Data("page".utf8)
            ]
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.deepEPUBContentChecks = false
        stages.epubClinicRepairScopes = SableClinicCheckProfile.covers.repairScopes
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB cover/image layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("duplicate cover-image marker"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("epub-scope-cover"), item.reviewTags.joined(separator: ", "))
        XCTAssertFalse(groups.flatMap(\.items).contains { $0.reviewTags.contains("epub-scope-compatibility") })
    }

    func testEPUBClinicAppleBooksPassOffersReviewGatedImportRefresh() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let epubPath = "Books/Reader Placeholder.epub"
        try writeEPUBFixture(
            epubPath,
            title: "Reader Placeholder",
            root: root,
            extraMetadataXML: """
                <meta refines="#missing-id" property="identifier-type">15</meta>
            """
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.deepEPUBContentChecks = false
        stages.epubClinicRepairScopes = SableClinicCheckProfile.appleBooks.repairScopes
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: context,
            service: service
        )
        XCTAssertEqual(groups.map(\.title), ["Apple Books import refresh"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.requiresReview)
        XCTAssertTrue(item.isReviewGatedEPUBRepairOperation)
        XCTAssertTrue(item.reviewTags.contains("epub-scope-readerImport"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-reader-import-refresh"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.epubRepairScopes, [.readerImport])
        XCTAssertTrue(item.isReaderImportRefreshOnly)

        var mixedScopeItem = item
        mixedScopeItem.reviewTags.append(SableLibraryEPUBRepairScope.compatibility.reviewTag)
        XCTAssertFalse(mixedScopeItem.isReaderImportRefreshOnly)

        let epubURL = fileURL(epubPath, root: root)
        let beforeOPF = try XCTUnwrap(
            try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL)
        )
        var approvedItem = item
        approvedItem.decision = .checked
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(
                root: root,
                groups: [
                    LibraryPlanGroup(
                        stage: .epubClinic,
                        title: "Apple Books import refresh",
                        summary: "Test",
                        items: [approvedItem]
                    )
                ]
            ),
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)
        let afterOPF = try XCTUnwrap(
            try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL)
        )
        XCTAssertNotEqual(beforeOPF, afterOPF)
        XCTAssertTrue(afterOPF.contains(#"id="sable-import-id""#), afterOPF)
        XCTAssertTrue(afterOPF.contains(#"unique-identifier="sable-import-id""#), afterOPF)
        XCTAssertTrue(afterOPF.contains(#"properties="cover-image""#), afterOPF)
        XCTAssertTrue(afterOPF.contains("refines=\"#missing-id\""), afterOPF)
    }

    func testEPUBClinicRelinksNCXTargetsToManifestPaths() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ncxText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="urn:uuid:fixture"/>
          </head>
          <docTitle><text>NCX Paths</text></docTitle>
          <navMap>
            <navPoint id="navPoint-1" playOrder="1">
              <navLabel><text>Chapter 1</text></navLabel>
              <content src="chapter1.xhtml#start"/>
            </navPoint>
          </navMap>
        </ncx>
        """

        try writeEPUBFixture(
            "Books/NCX Paths.epub",
            title: "NCX Paths",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="chapter-1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
            """,
            extraFiles: [
                "OPS/toc.ncx": Data(ncxText.utf8),
                "OPS/nav.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="Text/chapter1.xhtml#start">Chapter 1</a></li></ol></nav></body></html>"#.utf8),
                "OPS/Text/chapter1.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter 1</title></head><body><h1 id="start">Chapter 1</h1></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("NCX table of contents target"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("epub-navigation-source-ncx"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/NCX Paths.epub", root: root)
        let ncx = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncx.contains(#"src="Text/chapter1.xhtml#start""#), ncx)
        XCTAssertFalse(ncx.contains(#"src="chapter1.xhtml#start""#), ncx)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicRepairsNCXTargetsWithMissingFragments() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/NCX Missing Fragment.epub",
            title: "NCX Missing Fragment",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>Chapter 1</title></head>
              <body><p id="real-anchor">Chapter 1</p></body>
            </html>
            """,
            extraFiles: [
                "OPS/toc.ncx": Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <head><meta name="dtb:uid" content="urn:uuid:fixture"/></head>
                  <docTitle><text>NCX Missing Fragment</text></docTitle>
                  <navMap>
                    <navPoint id="nav-1" playOrder="1"><navLabel><text>Chapter 1</text></navLabel><content src="chapter.xhtml#missing-anchor"/></navPoint>
                  </navMap>
                </ncx>
                """.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("NCX table of contents fragment"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("epub-navigation-source-ncx"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/NCX Missing Fragment.epub", root: root)
        let ncx = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncx.contains(#"src="chapter.xhtml""#), ncx)
        XCTAssertFalse(ncx.contains("#missing-anchor"), ncx)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicMovesInvalidImageDimensionsIntoCSS() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Image Dimensions.epub",
            title: "Image Dimensions",
            root: root,
            includeCover: true,
            extraManifestXML: """
                <item id="page-image" href="Images/page.jpg" media-type="image/jpeg"/>
            """,
            chapterText: """
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>Image Dimensions</title></head>
              <body>
                <p><img src="Images/page.jpg" alt="" width="75%" height="100%" style="vertical-align: top;"/></p>
              </body>
            </html>
            """,
            extraFiles: [
                "OPS/Images/page.jpg": Data("image".utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB content layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("image dimension"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("epub-content"), item.reviewTags.joined(separator: ", "))
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Image Dimensions.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertNil(chapterText.range(of: #"<img[^>]*\bwidth\s*="#, options: .regularExpression), chapterText)
        XCTAssertNil(chapterText.range(of: #"<img[^>]*\bheight\s*="#, options: .regularExpression), chapterText)
        XCTAssertTrue(chapterText.contains("vertical-align: top; width: 75%; height: 100%;"), chapterText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicCreatesEPUB3NavigationFromExistingHeadings() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Navigation Needed.epub",
            title: "Navigation Needed",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="chapter-2" href="chapter-02.xhtml" media-type="application/xhtml+xml"/>
                <item id="chapter-3" href="chapter-03.xhtml" media-type="application/xhtml+xml"/>
            """,
            extraSpineXML: """
                <itemref idref="chapter-2"/>
                <itemref idref="chapter-3"/>
            """,
            chapterText: #"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Old</title></head><body><h1>Chapter 1: Arrival</h1><p>One.</p></body></html>"#,
            extraFiles: [
                "OPS/chapter-02.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Chapter 2: Tea</h1><p>Two.</p></body></html>"#.utf8),
                "OPS/chapter-03.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Chapter 3: Rain</h1><p>Three.</p></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertTrue(item.reviewTags.contains("epub-scope-navigation"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-navigation-source-document-structure"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("Create EPUB3 navigation document from spine"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Navigation Needed.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"properties="nav""#), opfText)
        XCTAssertTrue(opfText.contains(#"href="nav.xhtml""#), opfText)
        let navText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/nav.xhtml", in: epubURL))
        XCTAssertTrue(navText.contains(#"epub:type="toc""#), navText)
        XCTAssertTrue(navText.contains(#"<a href="chapter.xhtml">Chapter 1: Arrival</a>"#), navText)
        XCTAssertTrue(navText.contains(#"<a href="chapter-02.xhtml">Chapter 2: Tea</a>"#), navText)
        XCTAssertTrue(navText.contains(#"<a href="chapter-03.xhtml">Chapter 3: Rain</a>"#), navText)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains("<h1>Chapter 1: Arrival</h1>"), chapterText)
    }

    func testEPUBClinicDoesNotInventNavigationFromFilenamesOnly() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Filename Only Navigation.epub",
            title: "Filename Only Navigation",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="chapter-2" href="chapter-02.xhtml" media-type="application/xhtml+xml"/>
                <item id="chapter-3" href="chapter-03.xhtml" media-type="application/xhtml+xml"/>
            """,
            extraSpineXML: """
                <itemref idref="chapter-2"/>
                <itemref idref="chapter-3"/>
            """,
            chapterText: #"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>One.</p></body></html>"#,
            extraFiles: [
                "OPS/chapter-02.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Two.</p></body></html>"#.utf8),
                "OPS/chapter-03.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Three.</p></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertTrue(groups.isEmpty, groups.flatMap(\.items).map(\.reason).joined(separator: "\n"))
    }

    func testEPUBClinicCreatesEPUB3NavigationFromExistingNCXTOC() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ncxText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="navPoint-1" playOrder="1">
              <navLabel><text>Prologue</text></navLabel>
              <content src="chapter.xhtml"/>
            </navPoint>
            <navPoint id="navPoint-2" playOrder="2">
              <navLabel><text>Chapter 1</text></navLabel>
              <content src="chapter-02.xhtml#start"/>
            </navPoint>
            <navPoint id="navPoint-3" playOrder="3">
              <navLabel><text>Chapter 2</text></navLabel>
              <content src="chapter-03.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """

        try writeEPUBFixture(
            "Books/Legacy NCX Navigation.epub",
            title: "Legacy NCX Navigation",
            root: root,
            includeCover: false,
            packageVersion: "2.0",
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="chapter-2" href="chapter-02.xhtml" media-type="application/xhtml+xml"/>
                <item id="chapter-3" href="chapter-03.xhtml" media-type="application/xhtml+xml"/>
            """,
            extraSpineXML: """
                <itemref idref="chapter-2"/>
                <itemref idref="chapter-3"/>
            """,
            chapterText: #"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Start.</p></body></html>"#,
            extraFiles: [
                "OPS/toc.ncx": Data(ncxText.utf8),
                "OPS/chapter-02.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>One.</p></body></html>"#.utf8),
                "OPS/chapter-03.xhtml": Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Two.</p></body></html>"#.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("epub-navigation-source-ncx"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("existing NCX table of contents"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Legacy NCX Navigation.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains(#"version="3.0""#), opfText)
        XCTAssertTrue(opfText.contains(#"properties="nav""#), opfText)
        let navText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/nav.xhtml", in: epubURL))
        XCTAssertTrue(navText.contains(#"epub:type="toc""#), navText)
        XCTAssertTrue(navText.contains(#"<a href="chapter.xhtml">Prologue</a>"#), navText)
        XCTAssertTrue(navText.contains(#"<a href="chapter-02.xhtml">Chapter 1</a>"#), navText)
        XCTAssertFalse(navText.contains("#start"), navText)
        XCTAssertTrue(navText.contains(#"<a href="chapter-03.xhtml">Chapter 2</a>"#), navText)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(chapterText.contains("<p>Start.</p>"), chapterText)
    }

    func testEPUBClinicRemovesMissingManifestHelperReferences() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Missing Helpers.epub",
            title: "Missing Helpers",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="kobo-css" href="../css/kobo.css" media-type="text/css"/>
                <item id="kobo-js" href="../js/kobo.js" media-type="application/javascript"/>
            """
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB package layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("epub-manifest"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("missing EPUB manifest"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Missing Helpers.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains("kobo.css"), opfText)
        XCTAssertFalse(opfText.contains("kobo.js"), opfText)
        XCTAssertTrue(opfText.contains(#"<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>"#), opfText)
    }

    func testEPUBClinicChecksStructureRowsFromExistingNCXAnchors() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeNCXBackedStructureFixture(
            "Books/Structure Needed.epub",
            root: root,
            firstChapterLabel: "Chapter 1: Arrival",
            firstChapterBody: #"<p id="chapter-1" class="chapter-title">Chapter 1: Arrival</p><p>One.</p>"#
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB structure layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.reviewTags.contains("epub-scope-structure"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-structure-h1"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("ml-training-epub-structure"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("exact NCX-backed semantic headings"), item.reason)
    }

    func testEPUBClinicOffersStructureRowsFromNCXFileEntries() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeNCXBackedStructureFixture(
            "Books/Structure File Entries.epub",
            root: root,
            firstChapterLabel: "Chapter 1: Arrival",
            firstChapterBody: #"<p class="chapter-title"><span>Chapter 1: Arrival</span></p><p>One.</p>"#,
            useFragmentTargets: false
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB structure layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Structure File Entries.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(
            chapterText.contains(#"<h1 class="chapter-title"><span>Chapter 1: Arrival</span></h1>"#),
            chapterText
        )
        XCTAssertFalse(chapterText.contains(#"<p class="chapter-title">"#), chapterText)
    }

    func testEPUBClinicAppliesStructureHeadingsFromNCXAnchors() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeNCXBackedStructureFixture(
            "Books/Structure Applies.epub",
            root: root,
            firstChapterLabel: "Chapter 1: Arrival",
            firstChapterBody: #"<p id="chapter-1" class="chapter-title">Chapter 1: Arrival</p><p>One.</p>"#
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Structure Applies.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(
            chapterText.contains(#"<h1 id="chapter-1" class="chapter-title">Chapter 1: Arrival</h1>"#),
            chapterText
        )
        XCTAssertFalse(chapterText.contains(#"<p id="chapter-1" class="chapter-title">"#), chapterText)

        let secondChapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter-02.xhtml", in: epubURL))
        XCTAssertTrue(
            secondChapterText.contains(#"<h1 id="chapter-2" class="chapter-title">Chapter 2: Tea</h1>"#),
            secondChapterText
        )
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains("dcterms:modified"), opfText)
    }

    func testEPUBClinicAppliesNestedNCXStructureAsLowerHeadings() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ncxText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="navPoint-1" playOrder="1">
              <navLabel><text>Chapter 1: Arrival</text></navLabel>
              <content src="chapter.xhtml#chapter-1"/>
              <navPoint id="navPoint-1-1" playOrder="2">
                <navLabel><text>Scene 1: Tea</text></navLabel>
                <content src="chapter.xhtml#scene-1"/>
              </navPoint>
            </navPoint>
          </navMap>
        </ncx>
        """

        try writeEPUBFixture(
            "Books/Nested Structure.epub",
            title: "Nested Structure",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            """,
            chapterText: #"<html xmlns="http://www.w3.org/1999/xhtml"><body><p id="chapter-1" class="chapter-title">Chapter 1: Arrival</p><p>One.</p><div id="scene-1" class="scene-title"><span>Scene 1: Tea</span></div><p>Tea.</p></body></html>"#,
            extraFiles: [
                "OPS/toc.ncx": Data(ncxText.utf8),
                "OPS/nav.xhtml": Data(
                    """
                    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                      <body>
                        <nav epub:type="toc"><ol>
                          <li><a href="chapter.xhtml#chapter-1">Chapter 1: Arrival</a>
                            <ol><li><a href="chapter.xhtml#scene-1">Scene 1: Tea</a></li></ol>
                          </li>
                        </ol></nav>
                      </body>
                    </html>
                    """.utf8
                )
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB structure layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("epub-structure-h1"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reviewTags.contains("epub-structure-lower-headings"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("H1/H2"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Nested Structure.epub", root: root)
        let chapterText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/chapter.xhtml", in: epubURL))
        XCTAssertTrue(
            chapterText.contains(#"<h1 id="chapter-1" class="chapter-title">Chapter 1: Arrival</h1>"#),
            chapterText
        )
        XCTAssertTrue(
            chapterText.contains(#"<h2 id="scene-1" class="scene-title"><span>Scene 1: Tea</span></h2>"#),
            chapterText
        )
        XCTAssertFalse(chapterText.contains(#"<p id="chapter-1" class="chapter-title">"#), chapterText)
        XCTAssertFalse(chapterText.contains(#"<div id="scene-1" class="scene-title">"#), chapterText)
    }

    func testEPUBClinicDoesNotStructureCleanWhenNCXTextDoesNotMatchAnchor() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeNCXBackedStructureFixture(
            "Books/Structure Mismatch.epub",
            root: root,
            firstChapterLabel: "Chapter 1: Arrival",
            firstChapterBody: #"<p id="chapter-1" class="chapter-title">A Different Visible Heading</p><p>One.</p>"#,
            includeThirdChapter: false
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertTrue(groups.isEmpty, groups.flatMap(\.items).map(\.reason).joined(separator: "\n"))
    }

    func testEPUBClinicRepairsDuplicateNavigationMarkers() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let navFile = """
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <body>
            <nav epub:type="toc"><ol><li><a href="chapter.xhtml">Start</a></li></ol></nav>
          </body>
        </html>
        """
        try writeEPUBFixture(
            "Books/Duplicate Navigation.epub",
            title: "Duplicate Navigation",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="toc" href="toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """,
            extraFiles: [
                "OPS/nav.xhtml": Data(navFile.utf8),
                "OPS/toc.xhtml": Data(navFile.utf8)
            ]
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB navigation layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertTrue(item.reason.contains("Reduce duplicate EPUB navigation document markers"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Duplicate Navigation.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertEqual(opfText.components(separatedBy: #"properties="nav""#).count - 1, 1, opfText)
        XCTAssertTrue(opfText.contains(#"id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav""#), opfText)
        XCTAssertTrue(opfText.contains(#"id="toc" href="toc.xhtml" media-type="application/xhtml+xml""#), opfText)
    }

    func testAppleBooksRepairReplacesStaleEPUB3SeriesCollectionMetadata() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Clean Series"
        try writeJSONObject(
            [
                "title": "Clean Series",
                "preferred_title": "Clean Series",
                "type": "lightNovel",
                "authors": ["Example Author"],
                "languages": ["en"],
                "volumes": [
                    [
                        "number": 2,
                        "title": "Clean Series, Vol. 2",
                        "isbn13": ["9780000000002"],
                        "source_id": [
                            "provider": "ranobedb",
                            "value": "222"
                        ]
                    ]
                ],
                "ids": [
                    "ranobedb": "111"
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "\(folder)/Clean Series Vol. 2.epub",
            title: "Old Import Title",
            root: root,
            extraMetadataXML: """
                <meta property="belongs-to-collection" id="sable-series">Old Series</meta>
                <meta refines="#sable-series" property="collection-type">series</meta>
                <meta refines="#sable-series" property="group-position">1</meta>
                <meta property="belongs-to-collection" id="old-series">Clean Series</meta>
                <meta refines="#old-series" property="collection-type">series</meta>
                <meta refines="#old-series" property="group-position">9</meta>
            """
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.writeEPUBImportMetadata = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertTrue(item.reason.contains("Write series and volume import metadata"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("\(folder)/Clean Series Vol. 2.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains("Old Series"), opfText)
        XCTAssertFalse(opfText.contains("old-series"), opfText)
        XCTAssertEqual(opfText.components(separatedBy: #"property="belongs-to-collection""#).count - 1, 1, opfText)
        XCTAssertTrue(opfText.contains("<meta property=\"belongs-to-collection\" id=\"sable-series\">Clean Series</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-series\" property=\"collection-type\">series</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-series\" property=\"group-position\">2</meta>"), opfText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.flatMap(\.items).isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicMetadataSyncRowsApplyEvenWithSelfClosingDublinCoreStubs() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Looping Metadata"
        let ncxText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta content="urn:uuid:fixture" name="dtb:uid" />
          </head>
          <docTitle><text>Looping Metadata</text></docTitle>
          <navMap>
            <navPoint id="navPoint-1" playOrder="1">
              <navLabel><text>Chapter 1</text></navLabel>
              <content src="chapter.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        try writeJSONObject(
            [
                "title": "Looping Metadata",
                "preferred_title": "Looping Metadata",
                "type": "lightNovel",
                "year": 2020,
                "authors": ["Example Author"],
                "publishers": ["Example Press"],
                "languages": ["en"],
                "genres": ["Mystery"],
                "tags": ["Manga Tie-in"],
                "ids": [
                    "ranobedb": "777"
                ],
                "volumes": [
                    [
                        "number": 1,
                        "title": "Looping Metadata, Vol. 1",
                        "isbn13": ["9780000000001"],
                        "release_date": 20200102,
                        "source_id": [
                            "provider": "ranobedb",
                            "value": "888"
                        ]
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "\(folder)/Looping Metadata Vol. 1.epub",
            title: "Old Import Title",
            root: root,
            extraMetadataXML: #"    <dc:creator role="aut"/>"#,
            extraManifestXML: """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            """,
            extraFiles: [
                "OPS/toc.ncx": Data(ncxText.utf8)
            ]
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.writeEPUBImportMetadata = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertTrue(item.reviewTags.contains("epub-import-metadata"), item.reviewTags.joined(separator: ", "))

        let plan = LibraryPlan(root: root, groups: groups)
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .epubClinic,
            options: nil,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 3, result.summary)
        XCTAssertTrue(result.summary.contains("Selected Sable's Clinic repair rows: 3"), result.summary)
        XCTAssertTrue(result.summary.contains("Unique EPUB files touched: 1 of 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Completed repair rows: 3"), result.summary)

        let epubURL = fileURL("\(folder)/Looping Metadata Vol. 1.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertFalse(opfText.contains(#"<dc:creator role="aut"/>"#), opfText)
        XCTAssertTrue(opfText.contains("<dc:title id=\"sable-title\">Looping Metadata, Vol. 1</dc:title>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-title\" property=\"title-type\">main</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:creator id=\"sable-creator-1\">Example Author</dc:creator>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-creator-1\" property=\"role\" scheme=\"marc:relators\">aut</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:publisher>Example Press</dc:publisher>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:subject>Manga Tie-In</dc:subject>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-source-ranobedb-888\">ranobedb:888</dc:identifier>"), opfText)
        let freshID = try XCTUnwrap(opfText.range(
            of: #"<dc:identifier id="sable-import-id">([^<]+)</dc:identifier>"#,
            options: .regularExpression
        ).flatMap { range in
            String(opfText[range]).range(of: #">([^<]+)<"#, options: .regularExpression).map { innerRange in
                String(String(opfText[range])[innerRange].dropFirst().dropLast())
            }
        })
        let ncx = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/toc.ncx", in: epubURL))
        XCTAssertTrue(ncx.contains(#"content="\#(freshID)""#), ncx)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.flatMap(\.items).isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testEPUBClinicMetadataSyncPreservesCoverMetaAfterCalibreSeriesTags() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Cover Metadata Loop"
        try writeJSONObject(
            [
                "title": "Cover Metadata Loop",
                "preferred_title": "Cover Metadata Loop",
                "type": "lightNovel",
                "year": 2018,
                "authors": ["Example Author"],
                "artists": ["Example Artist"],
                "publishers": ["Example Press"],
                "languages": ["en"],
                "genres": ["Fantasy"],
                "ids": [
                    "ranobedb": "2643"
                ],
                "volumes": [
                    [
                        "number": 12,
                        "title": "Cover Metadata Loop, Vol. 12",
                        "isbn13": ["9781975354794"],
                        "release_date": 20181030,
                        "source_id": [
                            "provider": "ranobedb",
                            "value": "20181"
                        ]
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "\(folder)/Cover Metadata Loop-, Vol. 12.epub",
            title: "Cover Metadata Loop, Vol. 12",
            root: root,
            includeCoverMeta: false,
            coverItemID: "cover",
            coverHref: "Images/cover.jpeg",
            coverMediaType: "image/jpeg",
            coverProperties: "cover-image",
            extraMetadataXML: """
                <meta content="Cover Metadata Loop" name="calibre:series" />
                <meta content="12" name="calibre:series_index" />
                <meta name="cover" content="cover" />
                <dc:identifier id="uuid_id">urn:uuid:fixture</dc:identifier>
                <meta content="0.9.13" name="Sigil version" />
                <meta property="dcterms:modified">2019-05-24T15:39:20Z</meta>
            """
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.writeEPUBImportMetadata = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        _ = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        let plan = LibraryPlan(root: root, groups: groups)
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertFalse(result.summary.contains("Failed: 1"), result.summary)
        XCTAssertEqual(result.appliedCount, 2, result.summary)
        XCTAssertTrue(result.summary.contains("Selected Sable's Clinic repair rows: 2"), result.summary)
        XCTAssertTrue(result.summary.contains("Unique EPUB files touched: 1 of 1"), result.summary)
        XCTAssertTrue(result.summary.contains("Completed repair rows: 2"), result.summary)

        let epubURL = fileURL("\(folder)/Cover Metadata Loop-, Vol. 12.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        let cover = SableLibraryAppleBooksCompatibilityRepairer.coverAnalysis(in: opfText)
        XCTAssertTrue(cover.hasEPUB2CoverMeta, opfText)
        XCTAssertTrue(cover.hasEPUB3CoverImage, opfText)
        XCTAssertTrue(opfText.contains("<dc:title id=\"sable-title\">Cover Metadata Loop, Vol. 12</dc:title>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-title\" property=\"title-type\">main</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-source-ranobedb-20181\">ranobedb:20181</dc:identifier>"), opfText)

        let followUpInspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var followUpContext = LibraryPipelineContext(root: root, options: options)
        followUpContext.inspection = followUpInspection
        let followUpGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(
            context: followUpContext,
            service: service
        )
        XCTAssertTrue(
            followUpGroups.flatMap(\.items).isEmpty,
            followUpGroups.flatMap(\.items).map(\.reason).joined(separator: "\n")
        )
    }

    func testAppleBooksRepairUsesScopedRanobeDBBookTitleFromComicInfo() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ascendance of a Bookworm Part 2"
        let ranobeTitle = "Ascendance of a Bookworm: I'll Do Anything to Become a Librarian! Part 2: Apprentice Shrine Maiden Volume 1"
        try writeJSONObject(
            [
                "title": "Ascendance of a Bookworm Part 2",
                "preferred_title": "Ascendance of a Bookworm Part 2",
                "local_title": "Ascendance of a Bookworm Part 2",
                "type": "lightNovel",
                "year": 2015,
                "ids": [
                    "ranobedb": "4239"
                ],
                "volumes": [
                    [
                        "number": 4,
                        "title": ranobeTitle,
                        "source_id": [
                            "provider": "ranobedb",
                            "value": "part-2-volume-1"
                        ]
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeEPUBFixture(
            "\(folder)/Ascendance of a Bookworm Part 2 Vol 04.epub",
            title: "Old Import Title",
            root: root
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.writeEPUBImportMetadata = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertEqual(item.decision, .checked)

        let plan = LibraryPlan(root: root, groups: groups)
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("\(folder)/Ascendance of a Bookworm Part 2 Vol 04.epub", root: root)
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains("<dc:title id=\"sable-title\">\(ranobeTitle)</dc:title>"), opfText)
        XCTAssertTrue(opfText.contains("<meta refines=\"#sable-title\" property=\"title-type\">main</meta>"), opfText)
        XCTAssertTrue(opfText.contains("<dc:identifier id=\"sable-source-ranobedb-part-2-volume-1\">ranobedb:part-2-volume-1</dc:identifier>"), opfText)
    }

    func testAppleBooksRepairAllowsTextOnlyEPUBWithoutCoverImages() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Text Only Import.epub",
            title: "Text Only Import",
            root: root,
            includeCover: false,
            includeAppleMetadata: true
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB container layer"])
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertEqual(item.stage, .epubClinic)

        XCTAssertTrue(item.reason.contains("Has root iTunesMetadata plist"), item.reason)
        XCTAssertFalse(item.reason.localizedCaseInsensitiveContains("cover"), item.reason)
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Books/Text Only Import.epub", root: root)
        let entries = try SableLibraryAppleBooksCompatibilityRepairer.zipEntryNames(for: epubURL)
        XCTAssertFalse(entries.contains("iTunesMetadata.plist"))
        XCTAssertFalse(entries.contains("iTunesMetadata-original.plist"))
        let opfText = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryText("OPS/content.opf", in: epubURL))
        XCTAssertTrue(opfText.contains("sable-import-id"), opfText)
    }

    func testEPUBClinicMakesFixedLayoutPageWorkRunnable() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var extraFiles: [String: Data] = [:]
        for index in 1...39 {
            extraFiles["OPS/pages/page-\(index).jpg"] = Data("page \(index)".utf8)
        }
        for index in 1...19 {
            extraFiles["OPS/pages/page-\(index).xhtml"] = Data(
                """
                <html><head><meta name="viewport" content="width=1600,height=2400"/></head><body></body></html>
                """.utf8
            )
        }

        try writeEPUBFixture(
            "Manga/Page Box Review.epub",
            title: "Page Box Review",
            root: root,
            extraMetadataXML: #"<meta property="rendition:layout">pre-paginated</meta>"#,
            extraFiles: extraFiles
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        XCTAssertEqual(groups.map(\.title), ["EPUB fixed-layout repairs"])

        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.isReviewGatedEPUBRepairOperation)
        XCTAssertTrue(item.isApplyableAppleBooksCompatibilityRepairOperation)
        XCTAssertTrue(item.confidenceExplanation.contains("temporary EPUB"), item.confidenceExplanation)

        var checkedItem = item
        checkedItem.decision = .checked
        let applyResult = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: [
                LibraryPlanGroup(
                    stage: .epubClinic,
                    title: "EPUB fixed-layout repairs",
                    summary: "",
                    items: [checkedItem]
                )
            ]),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(applyResult.appliedCount, 1, applyResult.summary)
    }

    func testEPUBClinicDoesNotTreatFontObfuscationAsDRM() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let encryptionXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://ns.adobe.com/pdf/enc#RC"/>
            <enc:CipherData>
              <enc:CipherReference URI="OPS/fonts/BookFont.otf"/>
            </enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """
        try writeEPUBFixture(
            "Books/Font Obfuscated.epub",
            title: "Font Obfuscated",
            root: root,
            includeAppleMetadata: true,
            extraFiles: [
                "META-INF/encryption.xml": Data(encryptionXML.utf8),
                "OPS/fonts/BookFont.otf": Data("font bytes".utf8)
            ]
        )

        let epubURL = fileURL("Books/Font Obfuscated.epub", root: root)
        let protection = try SableLibraryAppleBooksCompatibilityRepairer.protectionAnalysis(for: epubURL)
        XCTAssertFalse(protection.isProtected)
        XCTAssertEqual(protection.obfuscatedFontPaths, ["ops/fonts/bookfont.otf"])

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.reason.localizedCaseInsensitiveContains("DRM"), item.reason)
        XCTAssertFalse(item.reason.localizedCaseInsensitiveContains("protected"), item.reason)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let repairedProtection = try SableLibraryAppleBooksCompatibilityRepairer.protectionAnalysis(for: epubURL)
        XCTAssertFalse(repairedProtection.isProtected)
        let entries = try SableLibraryAppleBooksCompatibilityRepairer.zipEntryNames(for: epubURL)
        XCTAssertTrue(entries.contains("META-INF/encryption.xml"))
    }

    func testEPUBClinicSkipsEncryptedContentResources() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let encryptionXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
            <enc:CipherData>
              <enc:CipherReference URI="OPS/chapter.xhtml"/>
            </enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """
        try writeEPUBFixture(
            "Books/Encrypted Content.epub",
            title: "Encrypted Content",
            root: root,
            includeAppleMetadata: true,
            extraFiles: [
                "META-INF/encryption.xml": Data(encryptionXML.utf8)
            ]
        )

        let epubURL = fileURL("Books/Encrypted Content.epub", root: root)
        let protection = try SableLibraryAppleBooksCompatibilityRepairer.protectionAnalysis(for: epubURL)
        XCTAssertTrue(protection.isProtected)
        XCTAssertEqual(protection.encryptedResourcePaths, ["ops/chapter.xhtml"])

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first)
        XCTAssertEqual(item.safety, .inspectOnly)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.requiresReview)
        XCTAssertFalse(item.isApplyableOperation)
        XCTAssertTrue(item.reviewTags.contains("epub-protected"), item.reviewTags.joined(separator: ", "))
        XCTAssertTrue(item.reason.contains("Encrypted EPUB content resources"), item.reason)

        let result = await service.applyAppleBooksCompatibilityRepairs(
            root: root,
            paths: ["Books/Encrypted Content.epub"],
            reportTitle: "Encrypted content test",
            reportName: "run-summary.txt"
        )
        XCTAssertTrue(result.applied.isEmpty, result.report)
        XCTAssertEqual(result.skipped.count, 1, result.report)
        XCTAssertTrue(result.skipped[0].contains("Encrypted EPUB content resources"), result.report)

        let entries = try SableLibraryAppleBooksCompatibilityRepairer.zipEntryNames(for: epubURL)
        XCTAssertTrue(entries.contains("iTunesMetadata.plist"))
    }

    func testEPUBProtectionMarkersStillDetectADEPTAndFairPlay() throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/ADEPT Marker.epub",
            title: "ADEPT Marker",
            root: root,
            extraFiles: [
                "META-INF/rights.xml": Data("<rights/>".utf8)
            ]
        )
        try writeEPUBFixture(
            "Books/FairPlay Marker.epub",
            title: "FairPlay Marker",
            root: root,
            extraFiles: [
                "META-INF/sinf.xml": Data("<sinf/>".utf8)
            ]
        )

        let adept = try SableLibraryAppleBooksCompatibilityRepairer.protectionAnalysis(
            for: fileURL("Books/ADEPT Marker.epub", root: root)
        )
        XCTAssertTrue(adept.isProtected)
        XCTAssertTrue(adept.reason?.contains("Adobe ADEPT") == true)

        let fairPlay = try SableLibraryAppleBooksCompatibilityRepairer.protectionAnalysis(
            for: fileURL("Books/FairPlay Marker.epub", root: root)
        )
        XCTAssertTrue(fairPlay.isProtected)
        XCTAssertTrue(fairPlay.reason?.contains("Apple FairPlay") == true)
    }

    func testAppleBooksRepairDoesNotOptimizeTextNovelCoverWhenImageOptimizationIsOn() async throws {
        #if canImport(AppKit)
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let coverData = try jpegFixtureData(width: 2200, height: 3200, quality: 0.95)
        try writeEPUBFixture(
            "Light Novels/Cover Safety.epub",
            title: "Cover Safety",
            root: root,
            includeAppleMetadata: true,
            coverData: coverData
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.optimizePageImageEPUBs = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertEqual(item.decision, .checked)

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(root: root, groups: groups),
            stage: .epubClinic,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let epubURL = fileURL("Light Novels/Cover Safety.epub", root: root)
        let repairedCover = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryData("OPS/cover.jpg", in: epubURL))
        XCTAssertEqual(repairedCover, coverData)
        #endif
    }

    func testPageImageOptimizerSkipsCoverLikePaths() {
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.isCoverLikeImagePathForOptimization("OPS/cover.jpg"))
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.isCoverLikeImagePathForOptimization("OPS/Images/front-cover.jpeg"))
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.isCoverLikeImagePathForOptimization("OPS/_covers/jp/Series Cover JP.jpg"))
        XCTAssertTrue(SableLibraryAppleBooksCompatibilityRepairer.isCoverLikeImagePathForOptimization("OPS/Covers/special-edition.jpg"))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.isCoverLikeImagePathForOptimization("OPS/Images/page-0001.jpg"))
        XCTAssertFalse(SableLibraryAppleBooksCompatibilityRepairer.isCoverLikeImagePathForOptimization("OPS/Images/spread-0042.jpeg"))
    }

    func testEPUBClinicReplacesSquareAudiobookArtworkWithSmallerPortraitBookCover() throws {
        #if canImport(AppKit)
        let squareAudiobookCover = try jpegFixtureData(width: 1_500, height: 1_500, quality: 0.95)
        let portraitBookCover = try jpegFixtureData(width: 938, height: 1_500, quality: 0.95)

        XCTAssertTrue(
            SableLibraryAppleBooksCompatibilityRepairer.shouldUseCoverReplacement(
                existingData: squareAudiobookCover,
                candidateData: portraitBookCover
            )
        )
        XCTAssertFalse(
            SableLibraryAppleBooksCompatibilityRepairer.shouldUseCoverReplacement(
                existingData: portraitBookCover,
                candidateData: squareAudiobookCover
            )
        )
        #endif
    }

    func testEPUBClinicUsesLocalEnglishCoverCandidateForEnglishText() async throws {
        #if canImport(AppKit)
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seriesFolder = "Light Novels/Language Cover (2024)"
        let epubPath = "\(seriesFolder)/Language Cover- Volume 1.epub"
        let existingCover = try jpegFixtureData(width: 320, height: 480, quality: 0.92)
        let englishCover = try jpegFixtureData(width: 1400, height: 2000, quality: 0.95)
        let englishSpecialCover = try jpegFixtureData(width: 2400, height: 3200, quality: 0.95)
        let englishAudiobookCover = try jpegFixtureData(width: 2400, height: 2400, quality: 0.95)
        let japaneseCover = try jpegFixtureData(width: 1500, height: 2200, quality: 0.95)
        try writeEPUBFixture(
            epubPath,
            title: "Language Cover",
            root: root,
            coverData: existingCover,
            language: "en"
        )

        let service = SableLibraryService()
        let config = service.currentConfig()
        try writeJSONObject(
            [
                "title": "Language Cover",
                "languages": ["en"],
                "volumes": [
                    ["number": 1, "title": "Language Cover - Vol 01"]
                ]
            ],
            to: "\(seriesFolder)/\(config.comicInfoFileName)",
            root: root
        )

        let englishCoverPath = "\(seriesFolder)/_covers/en/Language Cover- Volume 1 - Cover EN [Test].jpg"
        let englishSpecialCoverPath = "\(seriesFolder)/_covers/en/Language Cover- Volume 1 - Special 01 EN [Test].jpg"
        let englishAudiobookCoverPath = "\(seriesFolder)/_covers/audiobook/en/Language Cover- Volume 1 - Audiobook EN [Test].jpg"
        let japaneseCoverPath = "\(seriesFolder)/_covers/jp/Language Cover- Volume 1 - Cover JP [Test].jpg"
        for (path, data) in [
            (englishCoverPath, englishCover),
            (englishSpecialCoverPath, englishSpecialCover),
            (englishAudiobookCoverPath, englishAudiobookCover),
            (japaneseCoverPath, japaneseCover)
        ] {
            let url = fileURL(path, root: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        try writeJSONObject(
            [
                "entries": [
                    [
                        "book_file": "Language Cover- Volume 1.epub",
                        "volume": "1",
                        "covers": [
                            [
                                "language": "jp",
                                "source": "BookLive",
                                "status": "selected_downloaded",
                                "path": "_covers/jp/Language Cover- Volume 1 - Cover JP [Test].jpg",
                                "width": 1500,
                                "height": 2200
                            ],
                            [
                                "language": "en",
                                "source": "BookWalker Global",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": "_covers/en/Language Cover- Volume 1 - Cover EN [Test].jpg",
                                "width": 1400,
                                "height": 2000
                            ],
                            [
                                "language": "en",
                                "source": "MangaBaka",
                                "role": "specialEdition",
                                "status": "extra_downloaded",
                                "path": "_covers/en/Language Cover- Volume 1 - Special 01 EN [Test].jpg",
                                "width": 2400,
                                "height": 3200
                            ],
                            [
                                "language": "en",
                                "source": "MangaBaka",
                                "role": "audiobook",
                                "status": "extra_downloaded",
                                "path": "_covers/audiobook/en/Language Cover- Volume 1 - Audiobook EN [Test].jpg",
                                "width": 2400,
                                "height": 2400
                            ]
                        ]
                    ]
                ]
            ],
            to: "\(seriesFolder)/_covers/cover-manifest.json",
            root: root
        )

        let epubURL = fileURL(epubPath, root: root)
        let metadata = try XCTUnwrap(service.epubImportMetadataCandidate(for: epubURL, root: root, config: config))
        XCTAssertEqual(Set(metadata.localCoverCandidates.map(\.language)), ["en", "jp"])
        XCTAssertFalse(metadata.localCoverCandidates.contains { $0.filePath.hasSuffix("Special 01 EN [Test].jpg") })
        XCTAssertFalse(metadata.localCoverCandidates.contains { $0.filePath.hasSuffix("Audiobook EN [Test].jpg") })

        let analysis = try XCTUnwrap(service.appleBooksCompatibilityRepairAnalysis(
            for: epubURL,
            relativePath: epubPath,
            root: root,
            config: config,
            localCoverCandidates: metadata.localCoverCandidates,
            repairScopes: [.cover]
        ))
        XCTAssertTrue(analysis.reasons.contains { $0.contains("language-matched cover") }, analysis.reasons.joined(separator: "\n"))
        XCTAssertTrue(
            analysis.reasons.contains {
                $0.contains("English BookWalker Global cover is 1400 x 2000")
                    && $0.contains("embedded cover is 320 x 480")
            },
            analysis.reasons.joined(separator: "\n")
        )

        let result = await service.applyAppleBooksCompatibilityRepairs(
            root: root,
            paths: [epubPath],
            reportTitle: "Local cover apply test",
            reportName: "run-summary.txt",
            localCoverCandidatesByPath: [epubPath: metadata.localCoverCandidates],
            repairScopesByPath: [epubPath: [.cover]]
        )

        XCTAssertEqual(result.applied.count, 1, result.report)
        let repairedCover = try XCTUnwrap(try SableLibraryAppleBooksCompatibilityRepairer.entryData("OPS/cover.jpg", in: epubURL))
        XCTAssertEqual(repairedCover, englishCover)
        XCTAssertNotEqual(repairedCover, englishSpecialCover)
        XCTAssertNotEqual(repairedCover, englishAudiobookCover)
        #endif
    }

    func testEPUBClinicRequiresStoreProofBeforeUsingVersionTwoCover() throws {
        #if canImport(AppKit)
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seriesFolder = "Light Novels/Store Proof Cover (2024)"
        let epubPath = "\(seriesFolder)/Store Proof Cover - Vol 01.epub"
        try writeEPUBFixture(
            epubPath,
            title: "Store Proof Cover",
            root: root,
            coverData: try jpegFixtureData(width: 320, height: 480, quality: 0.92),
            language: "en"
        )

        let service = SableLibraryService()
        let config = service.currentConfig()
        try writeJSONObject(
            [
                "title": "Store Proof Cover",
                "languages": ["en"],
                "volumes": [["number": 1, "title": "Store Proof Cover - Vol 01"]]
            ],
            to: "\(seriesFolder)/\(config.comicInfoFileName)",
            root: root
        )

        let coverPath =
            "\(seriesFolder)/_covers/en/Store Proof Cover - Vol 01 - Cover EN [BookWalker Global].jpg"
        let coverURL = fileURL(coverPath, root: root)
        try FileManager.default.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try jpegFixtureData(width: 1_400, height: 2_000, quality: 0.95)
            .write(to: coverURL)

        func writeManifest(status: String) throws {
            try writeJSONObject(
                [
                    "version": 2,
                    "series_title": "Store Proof Cover",
                    "media_type": "lightNovel",
                    "entries": [
                        [
                            "book_file": "Store Proof Cover - Vol 01.epub",
                            "volume": 1,
                            "covers": [
                                [
                                    "language": "en",
                                    "source": "BookWalker Global",
                                    "role": "normal",
                                    "status": status,
                                    "path": "_covers/en/Store Proof Cover - Vol 01 - Cover EN [BookWalker Global].jpg",
                                    "width": 1_400,
                                    "height": 2_000,
                                    "provider_title": "Store Proof Cover, Vol. 1",
                                    "provider_media_type": "novel",
                                    "provider_volume": 1
                                ]
                            ]
                        ]
                    ]
                ],
                to: "\(seriesFolder)/_covers/cover-manifest.json",
                root: root
            )
        }

        try writeManifest(status: "selected_downloaded")
        let epubURL = fileURL(epubPath, root: root)
        let unverified = try XCTUnwrap(
            service.epubImportMetadataCandidate(
                for: epubURL,
                root: root,
                config: config
            )
        )
        XCTAssertTrue(unverified.localCoverCandidates.isEmpty)

        try writeManifest(status: "selected_downloaded_store_verified")
        let verified = try XCTUnwrap(
            service.epubImportMetadataCandidate(
                for: epubURL,
                root: root,
                config: config
            )
        )
        XCTAssertEqual(verified.localCoverCandidates.map(\.filePath), [coverURL.path])
        #endif
    }

    func testEPUBClinicUsesLocalJapaneseCoverCandidateForJapaneseText() async throws {
        #if canImport(AppKit)
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seriesFolder = "Light Novels/Language Cover Japanese (2024)"
        let epubPath = "\(seriesFolder)/Language Cover Japanese- Volume 1.epub"
        let existingCover = try jpegFixtureData(width: 320, height: 480, quality: 0.92)
        let englishCover = try jpegFixtureData(width: 1600, height: 2400, quality: 0.95)
        let japaneseCover = try jpegFixtureData(width: 1400, height: 2000, quality: 0.95)
        try writeEPUBFixture(
            epubPath,
            title: "言語カバー",
            root: root,
            coverData: existingCover,
            language: "ja",
            chapterText: "<html lang=\"ja\"><body><p>これは日本語の本文です。季節と物語について十分な長さの文章を収録しています。</p></body></html>"
        )

        let service = SableLibraryService()
        let config = service.currentConfig()
        try writeJSONObject(
            [
                "title": "Language Cover Japanese",
                "languages": ["ja"],
                "volumes": [
                    ["number": 1, "title": "Language Cover Japanese - Vol 01"]
                ]
            ],
            to: "\(seriesFolder)/\(config.comicInfoFileName)",
            root: root
        )

        let englishCoverPath = "\(seriesFolder)/_covers/en/Language Cover Japanese- Volume 1 - Cover EN [Test].jpg"
        let japaneseCoverPath = "\(seriesFolder)/_covers/jp/Language Cover Japanese- Volume 1 - Cover JP [Test].jpg"
        for (path, data) in [
            (englishCoverPath, englishCover),
            (japaneseCoverPath, japaneseCover)
        ] {
            let url = fileURL(path, root: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        try writeJSONObject(
            [
                "entries": [
                    [
                        "book_file": "Language Cover Japanese- Volume 1.epub",
                        "volume": "1",
                        "covers": [
                            [
                                "language": "en",
                                "source": "BookWalker Global",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": "_covers/en/Language Cover Japanese- Volume 1 - Cover EN [Test].jpg",
                                "width": 1600,
                                "height": 2400
                            ],
                            [
                                "language": "jp",
                                "source": "BookLive",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": "_covers/jp/Language Cover Japanese- Volume 1 - Cover JP [Test].jpg",
                                "width": 1400,
                                "height": 2000
                            ]
                        ]
                    ]
                ]
            ],
            to: "\(seriesFolder)/_covers/cover-manifest.json",
            root: root
        )

        let epubURL = fileURL(epubPath, root: root)
        let metadata = try XCTUnwrap(service.epubImportMetadataCandidate(for: epubURL, root: root, config: config))
        let result = await service.applyAppleBooksCompatibilityRepairs(
            root: root,
            paths: [epubPath],
            reportTitle: "Japanese local cover apply test",
            reportName: "run-summary.txt",
            localCoverCandidatesByPath: [epubPath: metadata.localCoverCandidates],
            repairScopesByPath: [epubPath: [.cover]]
        )

        XCTAssertEqual(result.applied.count, 1, result.report)
        let repairedCover = try XCTUnwrap(
            try SableLibraryAppleBooksCompatibilityRepairer.entryData("OPS/cover.jpg", in: epubURL)
        )
        XCTAssertEqual(repairedCover, japaneseCover)
        XCTAssertNotEqual(repairedCover, englishCover)
        #endif
    }

    func testEPUBClinicDoesNotOfferLowerResolutionLocalCoverReplacement() throws {
        #if canImport(AppKit)
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let epubPath = "Light Novels/Quality Cover (2024)/Quality Cover- Volume 1.epub"
        let existingCover = try jpegFixtureData(width: 1600, height: 2400, quality: 0.92)
        let localCover = try jpegFixtureData(width: 1200, height: 1800, quality: 0.95)
        try writeEPUBFixture(
            epubPath,
            title: "Quality Cover",
            root: root,
            coverData: existingCover,
            language: "en"
        )

        let localCoverURL = fileURL(
            "Light Novels/Quality Cover (2024)/_covers/en/Quality Cover- Volume 1 - Cover EN [Test].jpg",
            root: root
        )
        try FileManager.default.createDirectory(
            at: localCoverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try localCover.write(to: localCoverURL, options: .atomic)

        let service = SableLibraryService()
        let analysis = service.appleBooksCompatibilityRepairAnalysis(
            for: fileURL(epubPath, root: root),
            relativePath: epubPath,
            root: root,
            config: service.currentConfig(),
            localCoverCandidates: [
                SableLibraryEPUBImportCoverCandidate(
                    language: "en",
                    filePath: localCoverURL.path(percentEncoded: false),
                    width: 1200,
                    height: 1800,
                    source: "Test"
                )
            ],
            repairScopes: [.cover]
        )

        XCTAssertNil(analysis)
        #endif
    }

    func testAppleBooksRepairCanAddDownloadedCoverManifestMetadata() throws {
        let opfText = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Coverless Book</dc:title>
          </metadata>
          <manifest>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chapter"/>
          </spine>
        </package>
        """

        let patched = SableLibraryAppleBooksCompatibilityRepairer.opfTextAddingDownloadedCover(
            to: opfText,
            coverID: "sable-cover-image",
            coverHref: "sable-cover.jpg",
            mediaType: "image/jpeg"
        )
        let cover = SableLibraryAppleBooksCompatibilityRepairer.coverAnalysis(in: patched)

        XCTAssertTrue(patched.contains(#"<meta name="cover" content="sable-cover-image"/>"#), patched)
        XCTAssertTrue(patched.contains(#"<item id="sable-cover-image" href="sable-cover.jpg" media-type="image/jpeg" properties="cover-image"/>"#), patched)
        XCTAssertTrue(cover.hasEPUB2CoverMeta)
        XCTAssertTrue(cover.hasEPUB3CoverImage)
        XCTAssertTrue(cover.hasImageManifestItems)
        XCTAssertEqual(cover.likelyCoverID, "sable-cover-image")
    }

    func testTrustedCoverDownloadURLRejectsLocalSources() {
        XCTAssertEqual(
            SableLibraryAppleBooksCompatibilityRepairer.trustedCoverDownloadURLString(from: "http://covers.openlibrary.org/b/id/123-M.jpg"),
            "https://covers.openlibrary.org/b/id/123-M.jpg"
        )
        XCTAssertNil(SableLibraryAppleBooksCompatibilityRepairer.trustedCoverDownloadURLString(from: "file:///etc/passwd"))
        XCTAssertNil(SableLibraryAppleBooksCompatibilityRepairer.trustedCoverDownloadURLString(from: "https://localhost/cover.jpg"))
        XCTAssertNil(SableLibraryAppleBooksCompatibilityRepairer.trustedCoverDownloadURLString(from: "https://127.0.0.1/cover.jpg"))
        XCTAssertNil(SableLibraryAppleBooksCompatibilityRepairer.trustedCoverDownloadURLString(from: "https://192.168.1.2/cover.jpg"))
    }

    func testRawCleanupDoesNotPrepareEPUBRepairRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Needs Repair.epub",
            title: "Needs Repair",
            root: root,
            includeAppleMetadata: true
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let rawGroups = await SableLibraryStep2PrepareRawFiles().prepare(context: context, service: service)
        XCTAssertFalse(rawGroups.flatMap(\.items).contains { item in
            item.operation == .repairAppleBooksCompatibility || item.operation == .repairEpubPackage
        })

        let clinicGroups = await SableLibraryStep2PrepareRawFiles().prepareEPUBClinic(context: context, service: service)
        let clinicItem = try XCTUnwrap(clinicGroups.flatMap(\.items).first { $0.operation == .repairAppleBooksCompatibility })
        XCTAssertEqual(clinicItem.stage, .epubClinic)
    }

    func testAppleBooksRepairHandlesNoisyZipValidationOutput() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/Noisy Validate.epub",
            title: "Noisy Validate",
            root: root,
            includeAppleMetadata: true,
            extraTextFileCount: 2_000
        )

        let result = await SableLibraryService().applyAppleBooksCompatibilityRepairs(
            root: root,
            paths: ["Books/Noisy Validate.epub"],
            reportTitle: "Noisy EPUB repair",
            reportName: "_noisy_epub_repair.txt"
        )

        XCTAssertEqual(result.applied.count, 1, result.report)
        XCTAssertTrue(result.failed.isEmpty, result.report)
    }

    func testEPUBImportMetadataIgnoresComicInfoSymlinkOutsideLibraryRoot() async throws {
        let root = try makeTemporaryLibraryRoot()
        let outsideRoot = try makeTemporaryLibraryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        try writeJSONObject(
            [
                "title": "Outside Metadata",
                "authors": ["Should Not Import"]
            ],
            to: "ComicInfo.json",
            root: outsideRoot
        )

        let folderURL = fileURL("Light Novels/Outside Link", root: root)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folderURL.appendingPathComponent("ComicInfo.json"),
            withDestinationURL: fileURL("ComicInfo.json", root: outsideRoot)
        )

        let service = SableLibraryService()
        let metadata = service.epubImportMetadataCandidate(
            for: folderURL.appendingPathComponent("Outside Link Vol. 1.epub"),
            root: root,
            config: .fallback
        )

        XCTAssertNil(metadata)
    }

    func testEPUBImportMetadataIgnoresMixedLibraryRootComicInfo() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/A Court Of Wings And Ruin/A Court Of Wings And Ruin.epub",
            title: "A Court Of Wings And Ruin",
            root: root
        )
        try writeJSONObject(
            [
                "preferred_title": "Its In His Kiss",
                "authors": ["Julia Quinn"]
            ],
            to: "ComicInfo.json",
            root: root
        )

        let service = SableLibraryService()
        let metadata = service.epubImportMetadataCandidate(
            for: fileURL("Books/A Court Of Wings And Ruin/A Court Of Wings And Ruin.epub", root: root),
            root: root,
            config: .fallback
        )

        XCTAssertNil(metadata)
    }

    func testEPUBImportMetadataIgnoresMismatchedParentComicInfo() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEPUBFixture(
            "Books/A Court Of Wings And Ruin/A Court Of Wings And Ruin.epub",
            title: "A Court Of Wings And Ruin",
            root: root
        )
        try writeJSONObject(
            [
                "preferred_title": "Its In His Kiss",
                "authors": ["Julia Quinn"]
            ],
            to: "Books/ComicInfo.json",
            root: root
        )

        let service = SableLibraryService()
        let metadata = service.epubImportMetadataCandidate(
            for: fileURL("Books/A Court Of Wings And Ruin/A Court Of Wings And Ruin.epub", root: root),
            root: root,
            config: .fallback
        )

        XCTAssertNil(metadata)
    }

    func testProviderQueriesStripFolderYearsSourceIDsAndTypeHints() {
        let title = SableLibraryProviderQueryCleaner.searchTitle(from: "Quiet Hero (2018) {mb-1238}")
        let typeHinted = SableLibraryProviderQueryCleaner.searchTitle(from: "Quiet Hero - Light Novel")
        let volumeFile = SableLibraryProviderQueryCleaner.searchTitle(from: "Quiet Hero (2018) - Vol 01 - First Light {rdb-6832}")
        let variants = SableLibraryProviderQueryCleaner.searchTitles(
            from: ["Quiet Hero (2018) {mb-1238}", "Quiet Hero"],
            limit: 8,
            includeLooseVariants: true
        )

        XCTAssertEqual(title, "Quiet Hero", String(describing: title))
        XCTAssertEqual(typeHinted, "Quiet Hero", String(describing: typeHinted))
        XCTAssertEqual(volumeFile, "Quiet Hero", String(describing: volumeFile))
        XCTAssertEqual(variants.first, "Quiet Hero")
        XCTAssertFalse(variants.contains { $0.contains("2018") || $0.contains("{mb-") })
    }

    func testMangaBakaCreateRowsRemainApplyableWithoutFolderTypeHint() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Crowded Title/Volume 1.cbz", contents: "book", root: root)
        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let step = SableLibraryStep3ComicInfo()
        let groups = await step.prepare(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .createComicInfo })

        XCTAssertTrue(item.usedNetworkData)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableComicInfoOperation)
    }

    func testSeriesCoverDownloadRowsAreReviewableAndActuallyApplyable() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Usable Cover Search"
        try writeFile("\(folder)/Usable Cover Search - Vol 01.epub", contents: "book", root: root)
        try writeJSONObject(
            [
                "title": "Usable Cover Search",
                "native_title": "使える表紙検索",
                "type": "lightNovel",
                "volumes": [
                    ["number": 1, "title": "Usable Cover Search - Vol 01"]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: options,
            stage: .covers
        )
        let groups = run.context.plan.groups
        let item = try XCTUnwrap(groups.flatMap(\.items).first {
            $0.reviewTags.contains("cover-download-series")
        })
        let languageItems = groups.flatMap(\.items).filter {
            $0.currentPath == folder && $0.reviewTags.contains("cover-download-series")
        }

        XCTAssertFalse(options.stages.downloadSeriesCovers)
        XCTAssertEqual(run.context.inspectMode, .stageDeepDive(.covers))
        XCTAssertEqual(item.currentPath, folder)
        XCTAssertEqual(item.proposedPath, "\(folder)/_covers/cover-manifest.json")
        XCTAssertEqual(item.stage, .covers)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.usedNetworkData)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.isApplyableComicInfoOperation)
        XCTAssertTrue(item.isApplyableOperation)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-missing"))
        XCTAssertEqual(languageItems.count, 2)
        XCTAssertEqual(Set(languageItems.flatMap(\.requestedCoverLanguages)), Set(["jp", "en"]))
        XCTAssertEqual(item.coverSearchTitles.first, "Usable Cover Search")
        XCTAssertTrue(item.coverSearchTitles.contains("使える表紙検索"))
    }

    func testCoverRowsIncludeNestedRanobeDBJapaneseSeriesTitles() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Agents Of The Four Seasons"
        try writeFile("\(folder)/Agents Of The Four Seasons - Vol 01.epub", contents: "book", root: root)
        try writeJSONObject(
            [
                "title": "Agents Of The Four Seasons",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "Agents Of The Four Seasons - Vol 01"]],
                "_sable": [
                    "ranobedb": [
                        "api_compact": [
                            "series": [
                                "title": "Agents of the Four Seasons",
                                "title_orig": "春夏秋冬代行者",
                                "romaji_orig": "Shunkashuutou Daikousha",
                                "titles": [
                                    ["lang": "ja", "official": true, "title": "春夏秋冬代行者"],
                                    ["lang": "en", "official": true, "title": "Agents of the Four Seasons"]
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )

        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.reviewTags.contains("cover-download-series")
        })

        XCTAssertTrue(item.coverSearchTitles.contains("春夏秋冬代行者"))
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.orderedQueries(item.coverSearchTitles, language: "jp").first,
            "春夏秋冬代行者"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.orderedQueries(item.coverSearchTitles, language: "en").first,
            "Agents Of The Four Seasons"
        )
    }

    func testSeriesCoverDownloadRowsDistinguishCompleteAndIncompleteManifests() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let completeFolder = "Light Novels/Complete Cover Set"
        let incompleteFolder = "Light Novels/Incomplete Cover Set"
        let completeBook = "Complete Cover Set - Vol 01.epub"
        let incompleteBook1 = "Incomplete Cover Set - Vol 01.epub"
        let incompleteBook2 = "Incomplete Cover Set - Vol 02.epub"
        try writeFile("\(completeFolder)/\(completeBook)", contents: "book", root: root)
        try writeFile("\(incompleteFolder)/\(incompleteBook1)", contents: "book", root: root)
        try writeFile("\(incompleteFolder)/\(incompleteBook2)", contents: "book", root: root)

        for (folder, title, volumes) in [
            (completeFolder, "Complete Cover Set", [1]),
            (incompleteFolder, "Incomplete Cover Set", [1, 2])
        ] {
            try writeJSONObject(
                [
                    "title": title,
                    "type": "lightNovel",
                    "volumes": volumes.map { ["number": $0, "title": "\(title) - Vol \(String(format: "%02d", $0))"] }
                ],
                to: "\(folder)/ComicInfo.json",
                root: root
            )
        }

        let completeCoverPath = "_covers/en/Complete Cover Set - Vol 01 - Cover EN [Test].jpg"
        let incompleteCoverPath = "_covers/en/Incomplete Cover Set - Vol 01 - Cover EN [Test].jpg"
        try writeFile("\(completeFolder)/\(completeCoverPath)", contents: "cover", root: root)
        try writeFile("\(incompleteFolder)/\(incompleteCoverPath)", contents: "cover", root: root)
        try writeCoverManifest(
            bookFile: completeBook,
            coverPath: completeCoverPath,
            folder: completeFolder,
            root: root
        )
        try writeCoverManifest(
            bookFile: incompleteBook1,
            coverPath: incompleteCoverPath,
            folder: incompleteFolder,
            root: root
        )

        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let items = run.context.plan.groups.flatMap(\.items)
        let complete = try XCTUnwrap(items.first { $0.currentPath == completeFolder })
        let incomplete = try XCTUnwrap(items.first { $0.currentPath == incompleteFolder })
        let completeGroup = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.currentPath == completeFolder }
        })

        XCTAssertTrue(complete.reviewTags.contains("cover-manifest-present"), complete.reason)
        XCTAssertFalse(complete.reviewTags.contains("cover-manifest-incomplete"), complete.reason)
        XCTAssertEqual(complete.decision, .unchecked)
        XCTAssertTrue(completeGroup.reviewPrompt.contains("stay unchecked"))
        XCTAssertTrue(completeGroup.reviewPrompt.contains("Check All"))
        XCTAssertTrue(incomplete.reviewTags.contains("cover-manifest-incomplete"), incomplete.reason)
        XCTAssertFalse(incomplete.reviewTags.contains("cover-manifest-present"), incomplete.reason)
    }

    func testSeriesCoverDownloadRowsSeparatePreviousNoResultSearches() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/No Cover Result"
        let book = "No Cover Result - Vol 01.epub"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeJSONObject(
            [
                "title": "No Cover Result",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "No Cover Result - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-21T12:34:56Z",
                "generator": "Sable's Library",
                "series_title": "No Cover Result",
                "media_type": "lightNovel",
                "search_attempts": [[
                    "schema_version": 1,
                    "language": "jp",
                    "pass": "mangaBakaBaseline",
                    "completed_at": "2026-07-21T12:34:56Z",
                    "providers": ["MangaBaka"]
                ]],
                "manual_series_matches": [[
                    "source": "booklive_jp",
                    "providerID": "1375365",
                    "itemType": "series",
                    "title": "No Cover Result JP",
                    "mediaType": "lightNovel",
                    "bookType": "lightNovel"
                ]],
                "entries": [],
                "skipped": [
                    "BookLive JP: no confident series result for No Cover Result JP.",
                    "BookWalker JP: no confident series result for No Cover Result JP.",
                    "MangaBaka: The exact MangaBaka series No Cover Result is the correct novel, but MangaBaka has no volume-cover records. Its only image is a 256 x 400 series thumbnail, below the 800 x 1100 quality floor."
                ]
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let group = try XCTUnwrap(run.context.plan.groups.first { group in
            group.items.contains { $0.currentPath == folder }
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(group.title, "Japanese MangaBaka Baseline Finished, Gaps Remain")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-no-result"), item.reason)
        XCTAssertEqual(item.manualCoverSeriesMatches.count, 1)
        XCTAssertEqual(item.manualCoverSeriesMatches.first?.source, .bookLiveJP)
        XCTAssertEqual(item.manualCoverSeriesMatches.first?.providerID, "1375365")
        XCTAssertTrue(item.reason.contains("2026-07-21"), item.reason)
        XCTAssertTrue(item.reason.contains("MangaBaka baseline checked"), item.reason)
        XCTAssertFalse(item.reason.contains("no confident series result"), item.reason)
        XCTAssertTrue(item.reason.contains("Find Quality Upgrades"), item.reason)
    }

    func testExhaustedPartialJapaneseCoverSetMovesToFinishedLaneWhileEnglishIsComplete() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Split Language Covers"
        let books = [
            "Split Language Covers - Vol 01.epub",
            "Split Language Covers - Vol 02.epub"
        ]
        let englishPaths = [
            "_covers/en/Split Language Covers - Vol 01 - Cover EN [Test].jpg",
            "_covers/en/Split Language Covers - Vol 02 - Cover EN [Test].jpg"
        ]
        let japanesePath = "_covers/jp/Split Language Covers - Vol 01 - Cover JP [Test].jpg"
        for book in books {
            try writeFile("\(folder)/\(book)", contents: "book", root: root)
        }
        for path in englishPaths {
            try writeFile("\(folder)/\(path)", contents: "english cover", root: root)
        }
        try writeFile("\(folder)/\(japanesePath)", contents: "japanese cover", root: root)
        try writeJSONObject(
            [
                "title": "Split Language Covers",
                "native_title": "言語別表紙",
                "type": "lightNovel",
                "volumes": [
                    ["number": 1, "title": "Split Language Covers - Vol 01"],
                    ["number": 2, "title": "Split Language Covers - Vol 02"]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )

        func cover(
            language: String,
            path: String,
            volume: Int
        ) -> [String: Any] {
            var result: [String: Any] = [
                "language": language,
                "source": language == "jp" ? "MangaBaka" : "BookWalker Global",
                "role": "normal",
                "status": language == "jp"
                    ? "selected_downloaded"
                    : "selected_downloaded_store_verified",
                "path": path,
                "width": 1_400,
                "height": 2_000,
                "provider_title": language == "jp"
                    ? "言語別表紙 \(volume)"
                    : "Split Language Covers, Vol. \(volume)",
                "provider_item_id": "\(language)-\(volume)",
                "provider_volume": volume,
                "provider_media_type": "novel"
            ]
            if language == "en" {
                result["provider_url"] = "https://bookwalker.com/series/123456/split-language-covers/"
            }
            return result
        }
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-24T08:20:46Z",
                "generator": "Sable's Library Tests",
                "series_title": "Split Language Covers",
                "media_type": "lightNovel",
                "search_attempts": [[
                    "schema_version": 1,
                    "language": "jp",
                    "pass": "mangaBakaBaseline",
                    "completed_at": "2026-07-24T08:20:46Z",
                    "providers": ["MangaBaka"]
                ]],
                "entries": [
                    [
                        "book_file": books[0],
                        "volume": 1,
                        "covers": [
                            cover(language: "en", path: englishPaths[0], volume: 1),
                            cover(language: "jp", path: japanesePath, volume: 1)
                        ]
                    ],
                    [
                        "book_file": books[1],
                        "volume": 2,
                        "covers": [
                            cover(language: "en", path: englishPaths[1], volume: 2)
                        ]
                    ]
                ],
                "skipped": [
                    "No trusted cover found in BookLive JP, BookWalker JP, Amazon JP, MangaBaka. 1 of 2 book slots remain empty."
                ]
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let japanese = try XCTUnwrap(run.context.plan.items.first {
            $0.currentPath == folder && $0.requestedCoverLanguages == ["jp"]
        })
        let english = try XCTUnwrap(run.context.plan.items.first {
            $0.currentPath == folder && $0.requestedCoverLanguages == ["en"]
        })
        let japaneseGroup = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.id == japanese.id }
        })
        let englishGroup = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.id == english.id }
        })

        XCTAssertEqual(japaneseGroup.title, "Japanese MangaBaka Baseline Finished, Gaps Remain")
        XCTAssertTrue(japanese.reviewTags.contains("cover-manifest-no-result"))
        XCTAssertEqual(japanese.decision, .unchecked)
        XCTAssertEqual(englishGroup.title, "English Complete Cover Sets")
        XCTAssertTrue(english.reviewTags.contains("cover-manifest-present"))
        XCTAssertEqual(english.decision, .unchecked)
    }

    func testEmptyManifestOnlyFinishesTheLanguageThatWasSearched() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/One Language Search"
        let book = "One Language Search - Vol 01.epub"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeJSONObject(
            [
                "title": "One Language Search",
                "native_title": "一言語検索",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "One Language Search - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-24T09:15:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "One Language Search",
                "media_type": "lightNovel",
                "search_attempts": [[
                    "schema_version": 1,
                    "language": "jp",
                    "pass": "storeQualityUpgrade",
                    "completed_at": "2026-07-24T09:15:00Z",
                    "providers": ["BookLive JP", "BookWalker JP", "Amazon JP"]
                ]],
                "entries": [],
                "skipped": [
                    "No trusted cover found in BookLive JP, BookWalker JP, Amazon JP, MangaBaka. "
                        + "1 of 1 book slots remain empty."
                ]
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let japanese = try XCTUnwrap(run.context.plan.items.first {
            $0.currentPath == folder && $0.requestedCoverLanguages == ["jp"]
        })
        let english = try XCTUnwrap(run.context.plan.items.first {
            $0.currentPath == folder && $0.requestedCoverLanguages == ["en"]
        })
        let japaneseGroup = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.id == japanese.id }
        })
        let englishGroup = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.id == english.id }
        })

        XCTAssertEqual(japaneseGroup.title, "Japanese Ready to Find Covers")
        XCTAssertEqual(japanese.decision, .checked)
        XCTAssertEqual(englishGroup.title, "English Ready to Find Covers")
        XCTAssertEqual(english.decision, .checked)
    }

    func testArchivedCoverBelowClinicQualityGetsItsOwnUncheckedGroup() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Archive Quality Cover"
        let book = "Archive Quality Cover - Vol 01.epub"
        let coverPath = "_covers/jp/Archive Quality Cover - Vol 01 - Cover JP [BookLive JP].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(coverPath)", contents: "archive cover", root: root)
        try writeJSONObject(
            [
                "title": "Archive Quality Cover",
                "native_title": "保存品質表紙",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "Archive Quality Cover - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-24T09:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "Archive Quality Cover",
                "media_type": "lightNovel",
                "entries": [[
                    "book_file": book,
                    "volume": 1,
                    "covers": [[
                        "language": "jp",
                        "source": "BookLive JP",
                        "role": "normal",
                        "status": "archived_below_clinic_quality",
                        "path": coverPath,
                        "width": 607,
                        "height": 861,
                        "provider_title": "保存品質表紙 1",
                        "provider_item_id": "archive-jp-1",
                        "provider_volume": 1,
                        "provider_media_type": "novel"
                    ]]
                ]],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.currentPath == folder && $0.requestedCoverLanguages == ["jp"]
        })
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.id == item.id }
        })

        XCTAssertEqual(group.title, "Japanese Covers Found Below Clinic Quality")
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-below-clinic-quality"))
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reason.contains("607 x 861"), item.reason)
    }

    func testLegacyCompleteCoverManifestStaysUnverified() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Legacy Complete Cover Set"
        let book = "Legacy Complete Cover Set - Vol 01.epub"
        let englishPath = "_covers/en/Legacy Complete Cover Set - Vol 01 - Cover EN [Test].jpg"
        let japanesePath = "_covers/jp/Legacy Complete Cover Set - Vol 01 - Cover JP [Test].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(englishPath)", contents: "english cover", root: root)
        try writeFile("\(folder)/\(japanesePath)", contents: "japanese cover", root: root)
        try writeJSONObject(
            [
                "title": "Legacy Complete Cover Set",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "Legacy Complete Cover Set - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 1,
                "generated_at": "2026-07-20T00:00:00Z",
                "entries": [
                    [
                        "book_file": book,
                        "volume": 1,
                        "covers": [
                            [
                                "language": "en",
                                "source": "BookWalker Global",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": englishPath,
                                "width": 1_400,
                                "height": 2_000
                            ],
                            [
                                "language": "jp",
                                "source": "BookLive JP",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": japanesePath,
                                "width": 1_400,
                                "height": 2_000
                            ]
                        ]
                    ]
                ],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.currentPath == folder }
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(group.title, "Japanese Ready to Verify Existing Covers")
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-unverified"), item.reason)
        XCTAssertFalse(item.reviewTags.contains("cover-manifest-present"), item.reason)

        let manifestURL = root.appendingPathComponent(
            "\(folder)/_covers/cover-manifest.json"
        )
        let manifestData = try Data(contentsOf: manifestURL)
        var attemptedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        attemptedManifest["skipped"] = [
            "Store proof repair JP finished: schema 4; 1 existing cover still needs a readable product page or exact series choice."
        ]
        try writeJSONObject(
            attemptedManifest,
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let checkedRun = await SableLibraryPipelineCoordinator(
            service: service
        ).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let checkedItem = try XCTUnwrap(
            checkedRun.context.plan.items.first {
                $0.currentPath == folder
                    && $0.requestedCoverLanguages == ["jp"]
            }
        )
        let checkedGroup = try XCTUnwrap(
            checkedRun.context.plan.groups.first {
                $0.items.contains { $0.id == checkedItem.id }
            }
        )

        XCTAssertEqual(checkedGroup.title, "Japanese Unproven Covers to Replace")
        XCTAssertEqual(checkedItem.decision, .checked)
        XCTAssertTrue(
            checkedItem.reviewTags.contains(
                "cover-manifest-needs-store-check"
            ),
            checkedItem.reason
        )

        let checkedManifestData = try Data(contentsOf: manifestURL)
        var replacementAttemptedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: checkedManifestData) as? [String: Any]
        )
        replacementAttemptedManifest["skipped"] = [
            "Store proof repair JP finished: schema 4; 1 existing cover still needs a readable product page or exact series choice.",
            "Unproven cover replacement JP finished: schema 1; no trusted replacement was found for 1 normal cover. Existing image files were kept as fallbacks."
        ]
        try writeJSONObject(
            replacementAttemptedManifest,
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let replacementRun = await SableLibraryPipelineCoordinator(
            service: service
        ).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let replacementItem = try XCTUnwrap(
            replacementRun.context.plan.items.first {
                $0.currentPath == folder
                    && $0.requestedCoverLanguages == ["jp"]
            }
        )
        let replacementGroup = try XCTUnwrap(
            replacementRun.context.plan.groups.first {
                $0.items.contains { $0.id == replacementItem.id }
            }
        )

        XCTAssertEqual(
            replacementGroup.title,
            "Japanese Replacement Search Finished, No Trusted Match"
        )
        XCTAssertEqual(replacementItem.decision, .unchecked)
        XCTAssertTrue(
            replacementItem.reviewTags.contains(
                "cover-manifest-unproven-no-result"
            ),
            replacementItem.reason
        )
    }

    func testFractionalVolumeCoverMismatchRoutesToConflictRepair() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Fractional Cover Conflict"
        let book = "Fractional Cover Conflict - Vol 08.5.epub"
        let englishPath = "_covers/en/Fractional Cover Conflict - Vol 08.5 - Cover EN [Test].jpg"
        let japanesePath = "_covers/jp/Fractional Cover Conflict - Vol 08.5 - Cover JP [Test].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(englishPath)", contents: "english cover", root: root)
        try writeFile("\(folder)/\(japanesePath)", contents: "japanese cover", root: root)
        try writeJSONObject(
            [
                "title": "Fractional Cover Conflict",
                "type": "lightNovel",
                "volumes": [["number": 8.5, "title": "Fractional Cover Conflict - Vol 08.5"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-22T00:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "Fractional Cover Conflict",
                "media_type": "lightNovel",
                "entries": [
                    [
                        "book_file": book,
                        "volume": 8,
                        "covers": [
                            [
                                "language": "en",
                                "source": "BookWalker Global",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": englishPath,
                                "width": 1_400,
                                "height": 2_000,
                                "provider_title": "Fractional Cover Conflict, Vol. 8",
                                "provider_item_id": "fractional-en-8",
                                "provider_volume": 8,
                                "provider_media_type": "novel"
                            ],
                            [
                                "language": "jp",
                                "source": "BookLive JP",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": japanesePath,
                                "width": 1_400,
                                "height": 2_000,
                                "provider_title": "Fractional Cover Conflict 8",
                                "provider_item_id": "fractional-jp-8",
                                "provider_volume": 8,
                                "provider_media_type": "novel"
                            ]
                        ]
                    ]
                ],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.currentPath == folder }
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(group.title, "Japanese Cover Conflicts to Repair")
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-conflict"), item.reason)
        XCTAssertTrue(item.reason.contains("8.5"), item.reason)
        XCTAssertFalse(item.reviewTags.contains("cover-manifest-present"), item.reason)
    }

    func testTrustedSeriesAliasKeepsCompleteCoverManifestVerified() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Localized Fanbook"
        let book = "Localized Fanbook - Vol 01.epub"
        let coverPath = "_covers/en/Localized Fanbook - Vol 01 - Cover EN [Test].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(coverPath)", contents: "english cover", root: root)
        try writeJSONObject(
            [
                "title": "Localized Fanbook",
                "type": "lightNovel",
                "aliases": ["Romanized Fanbook"],
                "volumes": [["number": 1, "title": "Localized Fanbook - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeCoverManifest(
            bookFile: book,
            coverPath: coverPath,
            folder: folder,
            root: root
        )

        let manifestPath = "\(folder)/_covers/cover-manifest.json"
        let manifestURL = fileURL(manifestPath, root: root)
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var entries = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
        var covers = try XCTUnwrap(entries[0]["covers"] as? [[String: Any]])
        covers[1]["provider_title"] = "Romanized Fanbook"
        entries[0]["covers"] = covers
        manifest["entries"] = entries
        try writeJSONObject(manifest, to: manifestPath, root: root)

        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            ),
            stage: .covers
        )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.items.contains { $0.currentPath == folder }
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(group.title, "Japanese Complete Cover Sets")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-present"), item.reason)
        XCTAssertFalse(item.reviewTags.contains("cover-manifest-conflict"), item.reason)
    }

    func testUnreferencedLanguageCoverSurfacesAsRepairableConflict() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Stale Cover Series"
        let book = "Stale Cover Series - Vol 01.epub"
        let englishPath = "_covers/en/Stale Cover Series - Vol 01 - Cover EN [Test].jpg"
        let staleJapanesePath = "_covers/jp/Stale Cover Series - Vol 02 - Cover JP [Old].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(englishPath)", contents: "english cover", root: root)
        try writeJSONObject(
            [
                "title": "Stale Cover Series",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "Stale Cover Series - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeCoverManifest(
            bookFile: book,
            coverPath: englishPath,
            folder: folder,
            root: root
        )
        try writeFile(
            "\(folder)/\(staleJapanesePath)",
            contents: "stale japanese cover",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let group = try XCTUnwrap(
            run.context.plan.groups.first {
                $0.title == "Japanese Cover Conflicts to Repair"
            },
            "Cover groups: \(run.context.plan.groups.map { $0.title })"
        )
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-conflict"), item.reason)
        XCTAssertTrue(item.reason.contains("unreferenced Japanese cover"), item.reason)
        XCTAssertTrue(item.reason.contains("quarantined on repair"), item.reason)
    }

    func testQuickCoverAuditFlagsIdenticalImagesAssignedToDifferentBooks() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Duplicate Cover Assignment"
        let books = [
            "Duplicate Cover Assignment - Vol 01.epub",
            "Duplicate Cover Assignment - Vol 02.epub"
        ]
        let coverPaths = [
            "_covers/en/Duplicate Cover Assignment - Vol 01 - Cover EN [MangaBaka].jpg",
            "_covers/en/Duplicate Cover Assignment - Vol 02 - Cover EN [MangaBaka].jpg"
        ]
        for book in books {
            try writeFile("\(folder)/\(book)", contents: "book", root: root)
        }
        let duplicateImage = String(repeating: "same-cover-image-data", count: 128)
        for coverPath in coverPaths {
            try writeFile(
                "\(folder)/\(coverPath)",
                contents: duplicateImage,
                root: root
            )
        }
        try writeJSONObject(
            [
                "title": "Duplicate Cover Assignment",
                "type": "lightNovel",
                "volumes": [
                    ["number": 1, "title": "Duplicate Cover Assignment - Vol 01"],
                    ["number": 2, "title": "Duplicate Cover Assignment - Vol 02"]
                ]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-26T00:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "Duplicate Cover Assignment",
                "media_type": "lightNovel",
                "entries": books.indices.map { index in
                    [
                        "book_file": books[index],
                        "volume": index + 1,
                        "covers": [[
                            "language": "en",
                            "source": "MangaBaka",
                            "role": "normal",
                            "status": "selected_downloaded",
                            "path": coverPaths[index],
                            "width": 1_400,
                            "height": 2_000,
                            "provider_title": "Duplicate Cover Assignment, Vol. \(index + 1)",
                            "provider_item_id": "duplicate-cover-\(index + 1)",
                            "provider_volume": index + 1,
                            "provider_media_type": "novel"
                        ]]
                    ]
                },
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.title == "English Cover Conflicts to Repair"
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertTrue(item.reviewTags.contains("cover-manifest-conflict"), item.reason)
        XCTAssertTrue(
            item.reason.contains("reuses the same local cover image"),
            item.reason
        )
    }

    func testQuickCoverAuditRequiresProductURLForStoreVerifiedCover() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Missing Store Proof URL"
        let book = "Missing Store Proof URL - Vol 01.epub"
        let coverPath =
            "_covers/en/Missing Store Proof URL - Vol 01 - Cover EN [BookWalker Global].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(coverPath)", contents: "cover", root: root)
        try writeJSONObject(
            [
                "title": "Missing Store Proof URL",
                "type": "lightNovel",
                "volumes": [["number": 1, "title": "Missing Store Proof URL - Vol 01"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-26T00:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "Missing Store Proof URL",
                "media_type": "lightNovel",
                "entries": [[
                    "book_file": book,
                    "volume": 1,
                    "covers": [[
                        "language": "en",
                        "source": "BookWalker Global",
                        "role": "normal",
                        "status": "selected_downloaded_store_verified",
                        "path": coverPath,
                        "width": 1_400,
                        "height": 2_000,
                        "provider_title": "Missing Store Proof URL, Vol. 1",
                        "provider_item_id": "missing-proof-en-1",
                        "provider_volume": 1,
                        "provider_media_type": "novel"
                    ]]
                ]],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.title == "English Ready to Verify Existing Covers"
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertTrue(item.reviewTags.contains("cover-manifest-unverified"), item.reason)
        XCTAssertTrue(
            item.reason.contains("no saved product-page URL"),
            item.reason
        )
    }

    func testCrossScriptAliasCannotVerifyUnrelatedEnglishCover() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Hell Mode"
        let book = "Hell Mode - Vol 03.epub"
        let coverPath = "_covers/en/Hell Mode - Vol 03 - Cover EN [Amazon].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(coverPath)", contents: "english cover", root: root)
        try writeJSONObject(
            [
                "title": "Hell Mode",
                "type": "lightNovel",
                "aliases": [
                    "Hell Mode: The Hardcore Gamer Dominates in Another World with Garbage Balancing",
                    "ヘルモード"
                ],
                "volumes": [["number": 3, "title": "Hell Mode - Vol 03"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-24T00:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "Hell Mode",
                "media_type": "lightNovel",
                "manual_series_matches": [[
                    "source": "booklive_jp",
                    "providerID": "126944",
                    "title": "ヘルモード",
                    "itemType": "series",
                    "mediaType": "novel"
                ]],
                "entries": [[
                    "book_file": book,
                    "volume": 3,
                    "covers": [[
                        "language": "en",
                        "source": "Amazon",
                        "role": "normal",
                        "status": "selected_downloaded",
                        "path": coverPath,
                        "width": 1_050,
                        "height": 1_500,
                        "provider_title": "Hardcore Gaming 101 Digest Vol. 3: The Guide to Retro Horror",
                        "provider_item_id": "B07J4M8PVC",
                        "provider_volume": 3,
                        "provider_media_type": "novel"
                    ]]
                ]],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.title == "English Cover Conflicts to Repair"
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-conflict"), item.reason)
        XCTAssertTrue(item.reason.contains("Hardcore Gaming 101"), item.reason)
    }

    func testExactManualSeriesCanVerifySparseProviderVolumeTitle() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/The Saga of Tanya the Evil"
        let book = "The Saga of Tanya the Evil - Vol 10.epub"
        let coverPath = "_covers/en/The Saga of Tanya the Evil - Vol 10 - Cover EN [BookWalker Global].jpg"
        try writeFile("\(folder)/\(book)", contents: "book", root: root)
        try writeFile("\(folder)/\(coverPath)", contents: "english cover", root: root)
        try writeJSONObject(
            [
                "title": "The Saga of Tanya the Evil",
                "type": "lightNovel",
                "volumes": [["number": 10, "title": "The Saga of Tanya the Evil - Vol 10"]]
            ],
            to: "\(folder)/ComicInfo.json",
            root: root
        )
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-24T00:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": "The Saga of Tanya the Evil",
                "media_type": "lightNovel",
                "manual_series_matches": [[
                    "source": "bookwalker_global",
                    "providerID": "CNT_2ATJ2CC1R4QG",
                    "title": "The Saga of Tanya the Evil",
                    "itemType": "series",
                    "mediaType": "novel"
                ]],
                "entries": [[
                    "book_file": book,
                    "volume": 10,
                    "covers": [[
                        "language": "en",
                        "source": "BookWalker Global",
                        "role": "normal",
                        "status": "selected_downloaded",
                        "path": coverPath,
                        "width": 1_667,
                        "height": 2_500,
                        "provider_title": "Volume 10",
                        "provider_series_id": "CNT_2ATJ2CC1R4QG",
                        "provider_item_id": "PRD_TANYA_10",
                        "provider_volume": 10,
                        "provider_media_type": "novel"
                    ]]
                ]],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )

        let run = await SableLibraryPipelineCoordinator(service: SableLibraryService())
            .inspectStageAndBuildPlan(
                root: root,
                options: LibraryPipelineOptions(
                    cleanup: CleanupOptions(),
                    stages: LibraryPipelineStageOptions(),
                    intelligence: SableLibraryIntelligenceOptions()
                ),
                stage: .covers
            )
        let group = try XCTUnwrap(run.context.plan.groups.first {
            $0.title == "English Complete Cover Sets"
        })
        let item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reviewTags.contains("cover-manifest-present"), item.reason)
        XCTAssertFalse(item.reviewTags.contains("cover-manifest-conflict"), item.reason)
    }

    func testBooksLaneMissingComicInfoRowsRouteAsProviderOptionalProse() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Books/A Court Of Wings And Ruin/A Court Of Wings And Ruin.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep3ComicInfo().prepare(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first {
            $0.operation == .createComicInfo && $0.currentPath == "Books/A Court Of Wings And Ruin"
        })

        XCTAssertEqual(item.metadataProviders, [.openLibrary, .wikidata])
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.usedNetworkData)
        XCTAssertTrue(item.reviewTags.contains("provider-route-prose"))
        XCTAssertFalse(item.reviewTags.contains("metadata-checkpoint-choice"))
        XCTAssertTrue(item.isApplyableComicInfoOperation)
    }

    func testProviderlessOpenLibraryBookCreateWritesLocalBookSidecar() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Books/Providerless Prose"
        try writeFile("\(folder)/Providerless Prose.epub", contents: "book", root: root)

        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            currentPath: folder,
            proposedPath: "\(folder)/ComicInfo.json",
            reason: "Create provider-optional prose ComicInfo.",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [.openLibrary],
            reviewTags: ["provider-route-prose"]
        )
        let plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Create Reading ComicInfo with Metadata Providers",
                    summary: "Test provider-optional prose create",
                    items: [item]
                )
            ]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(plan: plan, service: SableLibraryService())

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        XCTAssertEqual(comicInfo["type"] as? String, SableLibraryReadingType.book.rawValue)
        XCTAssertEqual(comicInfo["source"] as? String, "local")
        XCTAssertEqual(comicInfo["title"] as? String, "Providerless Prose")
    }

    func testNonBookPDFsDoNotPrepareComicInfoByDefault() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("7 3 Wajong/Loonstrook202411.pdf", contents: "document", root: root)
        try writeFile("Sales Hand Out Odido Mobiel/handout.pdf", contents: "document", root: root)
        try writeFile("loose statement.pdf", contents: "document", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let inspection = try XCTUnwrap(run.context.inspection)

        XCTAssertEqual(inspection.bookFileCount, 0)
        XCTAssertFalse(run.context.plan.items.contains { $0.operation == .createComicInfo })
        let documentMove = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "loose statement.pdf"
        })
        XCTAssertEqual(documentMove.proposedPath, "Documents/PDFs/loose statement.pdf")
        XCTAssertEqual(documentMove.safety, .needsChoice)
        XCTAssertEqual(documentMove.decision, .unchecked)
        XCTAssertFalse(documentMove.requiresReview)
        XCTAssertTrue(documentMove.correctionOptions.contains(.treatAsDocument))
        XCTAssertFalse(documentMove.isApplyableOperation)
    }

    func testSinglePDFDocumentWrapperFoldersEnterPDFTriage() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Loonstrook202411/Loonstrook202411.pdf", contents: "document", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let pdfFolderMove = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "Loonstrook202411"
        })

        XCTAssertEqual(pdfFolderMove.operation, .renameFolder)
        XCTAssertEqual(pdfFolderMove.proposedPath, "Documents/PDFs/Loonstrook202411")
        XCTAssertEqual(pdfFolderMove.safety, .reversible)
        XCTAssertEqual(pdfFolderMove.decision, .checked)
        XCTAssertFalse(pdfFolderMove.requiresReview)
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("pdf-triage"))
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("likely-document"))
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("pdf-wrapper-folder"))
        XCTAssertTrue(pdfFolderMove.correctionOptions.contains(.treatAsDocument))
        XCTAssertTrue(pdfFolderMove.correctionOptions.contains(.treatAsBook))
        XCTAssertTrue(pdfFolderMove.isApplyableOperation)
    }

    func testPrepareRawFilesDoesNotMoveProjectOrLibraryRootFolders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: fileURL("Sable Project/.git", root: root),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fileURL("Sable Project/Sable Project.xcodeproj", root: root),
            withIntermediateDirectories: true
        )
        try writeFile("Sable Project/README.md", contents: "# Sable Project", root: root)
        try writeFile("Sable Project/Notes.txt", contents: "project notes", root: root)

        try writeFile("Sample Library/_Sable's Library Reports/_sable_run_summary.txt", contents: "ready", root: root)
        try writeEPUBFixture("Sample Library/A Court of Project Roots.epub", title: "A Court of Project Roots", root: root)

        try writeFile("Little Game/game.project", contents: "godot project", root: root)
        try writeFile("Little Game/data.xml", contents: "<level/>", root: root)
        try writeFile("Receipts/receipt.txt", contents: "receipt", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let prepareItems = run.context.plan.items.filter { $0.stage == .prepareRawFiles }

        let prepareSummary = prepareItems
            .map { "\($0.currentPath) -> \($0.proposedPath ?? "")" }
            .joined(separator: "\n")
        XCTAssertFalse(prepareItems.contains { $0.currentPath == "Sable Project" }, prepareSummary)
        XCTAssertFalse(prepareItems.contains { $0.currentPath == "Sample Library" }, prepareSummary)
        XCTAssertFalse(prepareItems.contains { $0.currentPath == "Little Game" }, prepareSummary)

        let receiptMove = try XCTUnwrap(prepareItems.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "Receipts"
        })
        XCTAssertEqual(receiptMove.operation, .renameFolder)
        XCTAssertEqual(receiptMove.proposedPath, "Documents/Text/Receipts")
    }

    func testRawCleanupSkipsProjectInternalsButComicInfoCanInspectSubfolders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: fileURL("torika/.git", root: root),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fileURL("sample/Sample.xcodeproj", root: root),
            withIntermediateDirectories: true
        )
        try writeEPUBFixture(
            "sample/SampleTests/Fixtures/SeedLibrary/Series Alpha/Vol 01.epub",
            title: "Series Alpha",
            root: root
        )
        try writeFile("sample/SampleTests/Fixtures/SeedLibrary/notes.txt", contents: "fixture", root: root)
        try writeFile("Loose Note.txt", contents: "root note", root: root)

        let coordinator = SableLibraryPipelineCoordinator(service: SableLibraryService())
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let rawRun = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let rawOrganizingItems = rawRun.context.plan.items.filter {
            $0.operation == .sortIntoFolder || $0.operation == .renameFolder || $0.operation == .cleanRawName
        }

        XCTAssertTrue(rawOrganizingItems.contains {
            $0.currentPath == "Loose Note.txt" && $0.proposedPath == "Documents/Text/Loose Note.txt"
        })
        XCTAssertFalse(rawOrganizingItems.contains { $0.currentPath.hasPrefix("torika/") })

        let comicInfoRun = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        XCTAssertTrue(comicInfoRun.context.plan.items.contains {
            $0.operation == .createComicInfo
                && $0.currentPath == "sample/SampleTests/Fixtures/SeedLibrary/Series Alpha"
        })
    }

    func testMLCompanyRoutesRowsToOwnersAndSafetyHandoffs() async throws {
        let rawItem = planItem(
            stage: .prepareRawFiles,
            operation: .sortIntoFolder,
            currentPath: "Loose Note.txt",
            proposedPath: "Documents/Text/Loose Note.txt"
        )
        let conflictItem = planItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: "Drive download/Animated/Screen",
            proposedPath: "TV/Screen (2003) {tmdb-53737}",
            safety: .collision,
            requiresReview: true
        )

        XCTAssertEqual(SableLibraryMLCompany.owner(for: rawItem), .rawIntake)
        XCTAssertEqual(SableLibraryMLCompany.owner(for: conflictItem), .namingLogistics)
        XCTAssertEqual(SableLibraryMLCompany.finalSayManager(for: rawItem), .moveManager)
        XCTAssertEqual(SableLibraryMLCompany.finalSayManager(for: conflictItem), .shelfManager)
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: rawItem).contains("department.rawintake"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: rawItem).contains("manager.foundation.move"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: rawItem).contains("scope.rootitem"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: conflictItem).contains("department.safetyoffice"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: conflictItem).contains("manager.foundation.shelfcatalog"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: conflictItem).contains("department.descriptionaboutness"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: conflictItem).contains("department.evidencequality"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: conflictItem).contains("escalation.collision"))
        XCTAssertTrue(SableLibraryMLCompany.operatingNote(for: .stageDeepDive(.comicInfo)).contains("Sidecar Relations"))
        XCTAssertTrue(SableLibraryMLCompany.operatingNote(for: .stageDeepDive(.comicInfo)).contains("Metadata Manager"))

        let metadataItem = planItem(
            stage: .comicInfo,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Series/ComicInfo.json",
            proposedPath: "Light Novels/Series/ComicInfo.json",
            reviewTags: ["metadata-comicinfo-cleaner"]
        )
        let clinicItem = planItem(
            stage: .epubClinic,
            operation: .repairEpubPackage,
            currentPath: "Light Novels/Series/Volume 01.epub",
            proposedPath: "Light Novels/Series/Volume 01.epub",
            reviewTags: ["epub-repair"]
        )

        XCTAssertEqual(SableLibraryMLCompany.finalSayManager(for: metadataItem), .metadataManager)
        XCTAssertEqual(SableLibraryMLCompany.finalSayManager(for: clinicItem), .clinicManager)
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: metadataItem).contains("manager.foundation.metadata"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: clinicItem).contains("manager.foundation.clinic"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: .library, item: conflictItem).contains("app.library"))
        XCTAssertTrue(SableLibraryMLCompany.featureTokens(for: .clinic, item: clinicItem).contains("app.clinic"))

        let metadataCleanerWithShelfVocabulary = planItem(
            stage: .comicInfo,
            operation: .refreshComicInfo,
            currentPath: "Light Novels/Series/ComicInfo.json",
            proposedPath: "Light Novels/Series/ComicInfo.json",
            reviewTags: ["metadata-comicinfo-cleaner", "sss-shelf-suggestion", "shelf-21"]
        )
        let metadataCleanerTokens = SableLibraryMLCompany.featureTokens(for: .library, item: metadataCleanerWithShelfVocabulary)
        XCTAssertTrue(metadataCleanerTokens.contains("manager.foundation.metadata"))
        XCTAssertFalse(metadataCleanerTokens.contains("manager.foundation.shelfcatalog"))
        XCTAssertFalse(metadataCleanerTokens.contains("department.shelfcatalog"))

        let shelfItem = planItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: "Light Novels/Example Isekai Series",
            proposedPath: "Light Novels/21 - Isekai & Other Worlds/21.1 - Adventure & Quest Isekai/Example Isekai Series",
            reviewTags: ["sss-shelf-suggestion", "shelf-21", "classification.sssShelf"]
        )
        let maybeShelfNote = await SableLibraryPipelineIntelligence().reviewNote(
            for: shelfItem,
            options: SableLibraryIntelligenceOptions(improveSuggestions: true, useLocalLearning: true)
        )
        let shelfNote = try XCTUnwrap(maybeShelfNote)
        XCTAssertTrue(shelfNote.confidenceNote.contains("Local ML ensemble"), shelfNote.confidenceNote)

        let maybeClinicNote = await SableLibraryPipelineIntelligence().reviewNote(
            for: clinicItem,
            options: SableLibraryIntelligenceOptions(improveSuggestions: true, useLocalLearning: true)
        )
        let clinicNote = try XCTUnwrap(maybeClinicNote)
        XCTAssertTrue(clinicNote.confidenceNote.contains("Local ML ensemble"), clinicNote.confidenceNote)

        let maybeNote = await SableLibraryPipelineIntelligence().reviewNote(
            for: conflictItem,
            options: SableLibraryIntelligenceOptions(improveSuggestions: true, useLocalLearning: false)
        )
        let note = try XCTUnwrap(maybeNote)

        XCTAssertTrue(note.confidenceNote.contains("Owner: Naming Logistics"), note.confidenceNote)
        XCTAssertTrue(note.confidenceNote.contains("Foundation manager: Shelf Manager"), note.confidenceNote)
        XCTAssertTrue(note.riskNote.contains("Safety Office flagged a collision"), note.riskNote)
    }

    func testBookLikePDFWrapperFoldersStayReviewOnly() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Fate's Ties/Chapter 01 The Red Threads of Fate.pdf", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let pdfFolderMove = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "Fate's Ties"
        })

        XCTAssertEqual(pdfFolderMove.proposedPath, "Documents/PDFs/Fate's Ties")
        XCTAssertEqual(pdfFolderMove.safety, .needsChoice)
        XCTAssertEqual(pdfFolderMove.decision, .unchecked)
        XCTAssertFalse(pdfFolderMove.requiresReview)
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("pdf-triage"))
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("likely-book"))
        XCTAssertFalse(pdfFolderMove.isApplyableOperation)
    }

    func testLocalLearningCanRaisePDFDocumentTriageConfidence() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Mystery Slip/Mystery Slip.pdf", contents: "document", root: root)

        var learning = SableLibraryLearningMemory()
        learning.recordPDFTriage(path: "Mystery Slip/Mystery Slip.pdf", proposedPath: "Documents/PDFs/Mystery Slip", choice: .document)
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions(useLocalLearning: true),
            learning: learning
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let pdfFolderMove = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "Mystery Slip"
        })

        XCTAssertTrue(pdfFolderMove.reviewTags.contains("pdf-triage"))
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("likely-document"))
        XCTAssertTrue(pdfFolderMove.reviewTags.contains("learned-pdf-triage"))
        XCTAssertTrue(pdfFolderMove.confidenceExplanation.contains("Learned document clue"))
        XCTAssertEqual(pdfFolderMove.decision, .checked)
        XCTAssertEqual(pdfFolderMove.safety, .reversible)
        XCTAssertFalse(pdfFolderMove.requiresReview)
        XCTAssertTrue(pdfFolderMove.isApplyableOperation)
    }

    func testPDFsWithComicInfoRemainReadingBooksByDefault() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Quiet PDF/ComicInfo.json",
            contents: #"{"title":"Quiet PDF","source":"local"}"#,
            root: root
        )
        try writeFile("Light Novels/Quiet PDF/Volume 01.pdf", contents: "book pdf", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let inspection = try XCTUnwrap(run.context.inspection)

        XCTAssertEqual(inspection.bookFileCount, 1)
        XCTAssertTrue(inspection.series.contains { $0.path == "Light Novels/Quiet PDF" })
        XCTAssertFalse(inspection.missingComicInfoSeriesPaths.contains("Light Novels/Quiet PDF"))
        XCTAssertFalse(run.context.plan.items.contains {
            $0.operation == .createComicInfo && $0.currentPath == "Light Novels/Quiet PDF"
        })
        XCTAssertFalse(run.context.plan.items.contains {
            $0.reviewTags.contains("pdf-triage") && $0.currentPath == "Light Novels/Quiet PDF"
        })
    }

    func testTreatPDFsAsBooksSettingRestoresPDFBookPlanning() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Sales Hand Out Odido Mobiel/handout.pdf", contents: "book pdf", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var cleanup = CleanupOptions()
        cleanup.treatPDFsAsBooks = true
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        let options = LibraryPipelineOptions(
            cleanup: cleanup,
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let inspection = try XCTUnwrap(run.context.inspection)

        XCTAssertEqual(inspection.bookFileCount, 1)
        XCTAssertTrue(run.context.plan.items.contains {
            $0.operation == .createComicInfo && $0.currentPath == "Sales Hand Out Odido Mobiel"
        })
    }

    func testComicInfoOnlyFoldersCanPrepareMangaBakaRefreshRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Quiet Shelf/ComicInfo.json",
            contents: #"{"title":"Quiet Shelf","last_checked":"2024-01-01T00:00:00Z","source":"local"}"#,
            root: root
        )
        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let step = SableLibraryStep3ComicInfo()
        let groups = await step.prepare(context: context, service: service)
        let item = try XCTUnwrap(groups.flatMap(\.items).first { $0.operation == .refreshComicInfo && $0.usedNetworkData })

        XCTAssertEqual(inspection.seriesCount, 1)
        XCTAssertEqual(inspection.comicInfoCount, 1)
        XCTAssertTrue(inspection.series.first?.hasComicInfo == true)
        XCTAssertTrue(item.usedNetworkData)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.isApplyableComicInfoOperation)
    }

    func testStaleProviderFreshnessPreparesMetadataRefreshRow() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let now = ISO8601DateFormatter().string(from: Date())
        try writeFile(
            "Light Novels/Quiet Provider/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Provider",
              "preferred_title": "Quiet Provider",
              "type": "lightNovel",
              "ids": {
                "mangabaka": "42",
                "ranobedb": "3148"
              },
              "last_checked": "\(now)",
              "source": "ranobedb",
              "source_freshness": [
                {
                  "provider": "ranobedb",
                  "fetched_at": "2024-01-01T00:00:00Z",
                  "ttl_seconds": 1
                }
              ]
            }
            """,
            root: root
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: service
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let sourceFreshness = try XCTUnwrap(inspection.series.first?.sourceFreshness.first)
        XCTAssertEqual(sourceFreshness.provider, .ranobedb)
        XCTAssertFalse(sourceFreshness.isFresh())

        let step = SableLibraryStep3ComicInfo()
        let groups = await step.prepare(context: context, service: service)
        let providerGroups = await step.prepareProviderMatches(context: context, service: service)
        let refreshItem = try XCTUnwrap(
            groups.flatMap(\.items).first {
                $0.operation == .refreshComicInfo
                    && $0.reviewTags.contains("metadata-ranobedb-series-refresh")
            }
        )
        XCTAssertTrue(refreshItem.usedNetworkData)
        XCTAssertEqual(refreshItem.metadataProviders, [.ranobedb, .openLibrary, .wikidata, .anilist])
        XCTAssertTrue(refreshItem.reviewTags.contains("metadata-pass-refresh"))
        XCTAssertTrue(refreshItem.reviewTags.contains("metadata-pass-detail"))
        XCTAssertTrue(refreshItem.reviewTags.contains("metadata-provider-ranobedb-series"))
        XCTAssertTrue(refreshItem.reviewTags.contains("metadata-provider-ranobedb-books"))
        XCTAssertTrue(refreshItem.reviewTags.contains("metadata-ranobedb-book-detail-refresh"))
        XCTAssertTrue(refreshItem.reason.contains("newly listed books"))
        XCTAssertTrue(refreshItem.isApplyableComicInfoOperation)

        XCTAssertEqual(groups.flatMap(\.items).filter {
            $0.operation == .refreshComicInfo
                && $0.currentPath == "Light Novels/Quiet Provider"
        }.count, 1)

        let refreshGroupIndex = try XCTUnwrap(groups.firstIndex { $0.title == "Refresh Saved Provider Data" })
        XCTAssertEqual(groups[refreshGroupIndex].stage, .comicInfo)
        XCTAssertNil(groups.firstIndex { $0.title == "Refresh Book Details" })
        XCTAssertNil(groups.firstIndex { $0.title.hasPrefix("Missing Providers -") })
        XCTAssertNil(providerGroups.firstIndex { $0.title == "Missing Providers - MyAnimeList" })
        XCTAssertNotNil(providerGroups.firstIndex { $0.title == "Missing Providers - Open Library" })

        let aniListGroupIndex = try XCTUnwrap(providerGroups.firstIndex { $0.title == "Missing Providers - AniList" })
        let aniListItem = try XCTUnwrap(providerGroups[aniListGroupIndex].items.first)
        XCTAssertEqual(aniListItem.stage, .providerMatches)
        XCTAssertEqual(aniListItem.metadataProviders, [.anilist])
        XCTAssertEqual(aniListItem.decision, .checked)
        XCTAssertFalse(aniListItem.requiresReview)
        XCTAssertTrue(aniListItem.isApplyableComicInfoOperation)
        XCTAssertTrue(aniListItem.reviewTags.contains("ml-training-provider-gap"))
        XCTAssertTrue(aniListItem.reviewTags.contains("metadata-provider-precheck"))
    }

    func testRefreshDropsStaleRanobeDBIDWhenMangaBakaExactTitleConflicts() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Observation Records of My Fiancée The Misadventures of a Self-Proclaimed Villainess (2022) {mb-185873} {rdb-6832}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
              "preferred_title": "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
              "local_title": "Observation Records of My Fiancée The Misadventures of a Self-Proclaimed Villainess",
              "type": "lightNovel",
              "year": 2022,
              "source": "mangabaka, ranobedb",
              "ids": {
                "mangabaka": "185873",
                "ranobedb": "6832"
              },
              "source_freshness": [
                {
                  "provider": "mangabaka",
                  "fetched_at": "2024-01-01T00:00:00Z"
                },
                {
                  "provider": "ranobedb",
                  "fetched_at": "2024-01-01T00:00:00Z"
                }
              ],
              "match_evidence": [
                {
                  "kind": "exactProviderID",
                  "provider": "mangabaka",
                  "value": "185873",
                  "confidence": 1
                },
                {
                  "kind": "exactProviderID",
                  "provider": "ranobedb",
                  "value": "6832",
                  "confidence": 1
                }
              ],
              "_sable": {
                "mangabaka": {
                  "matched_id": "185873",
                  "matched_title": "a Self-Proclaimed Villainess",
                  "titles_v2": [
                    {
                      "language": "en",
                      "title": "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
                      "traits": ["official"]
                    },
                    {
                      "language": "ja-Latn",
                      "title": "Jishou Akuyaku Reijou na Tsuma no Kansatsu Kiroku.",
                      "traits": ["native"]
                    }
                  ]
                },
                "ranobedb": {
                  "series_id": "6832",
                  "series": {
                    "title": "Observation Records of My Fiancée: The Misadventures of a Self-Proclaimed Villainess"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile(
            "\(folder)/Observation Records of My Wife - Vol 01.epub",
            contents: "book",
            root: root
        )

        let mangaBakaResponse = """
        {
          "status": 200,
          "data": {
            "id": 185873,
            "title": "a Self-Proclaimed Villainess",
            "native_title": "自称悪役令嬢な妻の観察記録。",
            "romanized_title": "Jishou Akuyaku Reijou na Tsuma no Kansatsu Kiroku.",
            "type": "novel",
            "year": 2022,
            "titles": [
              {
                "language": "en",
                "title": "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
                "is_primary": true,
                "traits": ["official"]
              },
              {
                "language": "ja-Latn",
                "title": "Jishou Akuyaku Reijou na Tsuma no Kansatsu Kiroku.",
                "is_primary": true,
                "traits": ["native"]
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let mangaBakaURL = try XCTUnwrap(URL(string: "https://api.mangabaka.org/v1/series/185873"))
        await SableLibraryProviderResponseCache.shared.store(
            mangaBakaResponse,
            for: SableLibraryProviderResponseCache.key(provider: .mangabaka, url: mangaBakaURL),
            ttl: 604_800
        )

        let ranobeDBResponse = """
        {
          "series": {
            "id": 6832,
            "title": "Observation Records of My Fiancée: The Misadventures of a Self-Proclaimed Villainess",
            "title_orig": "自称悪役令嬢な婚約者の観察記録。",
            "romaji_orig": "Jishou Akuyaku Reijou na Kon'yakusha no Kansatsu Kiroku.",
            "lang": "en",
            "olang": "ja",
            "publication_status": "completed",
            "c_start_date": 20170504
          },
          "books": []
        }
        """.data(using: .utf8)!
        let ranobeURL = try XCTUnwrap(URL(string: "https://ranobedb.org/api/v0/series/6832"))
        await SableLibraryProviderResponseCache.shared.store(
            ranobeDBResponse,
            for: SableLibraryProviderResponseCache.key(provider: .ranobedb, url: ranobeURL),
            ttl: 604_800
        )

        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .refreshComicInfo,
            currentPath: folder,
            proposedPath: "\(folder)/ComicInfo.json",
            reason: "Refresh saved provider IDs.",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [.mangabaka, .ranobedb],
            manualMangaBakaID: "185873",
            manualRanobeDBID: "6832"
        )
        let plan = LibraryPlan(
            root: root,
            groups: [LibraryPlanGroup(stage: .comicInfo, title: "Refresh Reading Details", summary: "Test", items: [item])]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(plan: plan, service: SableLibraryService())
        XCTAssertEqual(result.appliedCount, 1)

        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let ids = try XCTUnwrap(comicInfo["ids"] as? [String: Any])
        let localWifeTitle = "Observation Records of My Wife- The Misadventures of a Self-Proclaimed Villainess"
        XCTAssertEqual(ids["mangabaka"] as? String, "185873")
        XCTAssertNil(ids["ranobedb"])
        XCTAssertEqual(comicInfo["title"] as? String, localWifeTitle)
        XCTAssertEqual(comicInfo["preferred_title"] as? String, localWifeTitle)
        XCTAssertEqual(comicInfo["local_title"] as? String, localWifeTitle)
        XCTAssertEqual(comicInfo["source"] as? String, "mangabaka")

        let freshness = try XCTUnwrap(comicInfo["source_freshness"] as? [[String: Any]])
        XCTAssertTrue(freshness.contains { $0["provider"] as? String == "mangabaka" })
        XCTAssertFalse(freshness.contains { $0["provider"] as? String == "ranobedb" })
        let evidence = try XCTUnwrap(comicInfo["match_evidence"] as? [[String: Any]])
        XCTAssertTrue(evidence.contains { $0["provider"] as? String == "mangabaka" })
        XCTAssertFalse(evidence.contains { $0["provider"] as? String == "ranobedb" })

        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        XCTAssertNotNil(sable["mangabaka"])
        XCTAssertNil(sable["ranobedb"])
        XCTAssertNil(sable["provider_candidate_review"])
        let availability = try XCTUnwrap(sable["provider_availability"] as? [String: Any])
        let ranobeAvailability = try XCTUnwrap(availability["ranobedb"] as? [String: Any])
        XCTAssertEqual(ranobeAvailability["status"] as? String, "not_available")
        XCTAssertEqual(ranobeAvailability["rejected_candidate_id"] as? String, "6832")
    }

    func testConfirmedManualRanobeDBIDOverridesAnUnrelatedLocalTitleGuard() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/00 - Review & Exceptions/Dan Machi Familia Chronicle - Novel"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Dan Machi Familia Chronicle",
              "preferred_title": "Dan Machi Familia Chronicle",
              "local_title": "Dan Machi Familia Chronicle",
              "type": "Novel",
              "year": 2020,
              "_sable": {
                "provider_candidate_review": {
                  "ranobedb": {
                    "status": "rejected",
                    "provider": "ranobedb",
                    "rejected_candidate_id": "6585",
                    "rejected_candidate_title": "Is It Wrong to Try to Pick Up Girls in a Dungeon? Familia Chronicle",
                    "source": "trusted_title_conflict"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Dan Machi Familia Chronicle - Vol 01.epub", contents: "book", root: root)

        let response = """
        {
          "series": {
            "id": 6585,
            "title": "Is It Wrong to Try to Pick Up Girls in a Dungeon? Familia Chronicle",
            "title_orig": "ダンジョンに出会いを求めるのは間違っているだろうか ファミリアクロニクル",
            "romaji_orig": "Dungeon ni Deai wo Motomeru no wa Machigatteiru Darou ka Familia Chronicle",
            "lang": "en",
            "olang": "ja",
            "publication_status": "ongoing",
            "c_start_date": 20170315
          },
          "books": []
        }
        """.data(using: .utf8)!
        let ranobeURL = try XCTUnwrap(URL(string: "https://ranobedb.org/api/v0/series/6585"))
        await SableLibraryProviderResponseCache.shared.store(
            response,
            for: SableLibraryProviderResponseCache.key(provider: .ranobedb, url: ranobeURL),
            ttl: 604_800
        )

        let item = LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: folder,
            proposedPath: "\(folder)/ComicInfo.json",
            reason: "Use the manually confirmed RanobeDB match.",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [.ranobedb],
            manualRanobeDBID: "6585",
            manualSourceIDs: [SableLibrarySourceID(provider: .ranobedb, value: "6585")],
            reviewTags: ["manual-provider-match", "metadata-provider-manual-match"]
        )
        let plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .providerMatches,
                    title: "Missing Providers - RanobeDB",
                    summary: "Test",
                    items: [item]
                )
            ]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(
            plan: plan,
            stage: .providerMatches,
            service: SableLibraryService()
        )
        XCTAssertEqual(result.appliedCount, 1, result.summary)

        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let ids = try XCTUnwrap(comicInfo["ids"] as? [String: Any])
        XCTAssertEqual(ids["ranobedb"] as? String, "6585")
        XCTAssertEqual(comicInfo["year"] as? Int, 2017)
        XCTAssertEqual(comicInfo["local_title"] as? String, "Dan Machi Familia Chronicle")
        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        XCTAssertNotNil(sable["ranobedb"])
        let confirmations = try XCTUnwrap(sable["provider_identity_confirmations"] as? [String: Any])
        let ranobeConfirmation = try XCTUnwrap(confirmations["ranobedb"] as? [String: Any])
        XCTAssertEqual(ranobeConfirmation["id"] as? String, "6585")
        let availability = sable["provider_availability"] as? [String: Any]
        XCTAssertNil(availability?["ranobedb"])

        let refreshItem = LibraryPlanItem(
            stage: .comicInfo,
            operation: .refreshComicInfo,
            currentPath: folder,
            proposedPath: "\(folder)/ComicInfo.json",
            reason: "Refresh the saved provider identity.",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [.ranobedb],
            reviewTags: ["metadata-ranobedb-series-refresh"]
        )
        let refreshPlan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Refresh Saved Provider Data",
                    summary: "Test",
                    items: [refreshItem]
                )
            ]
        )

        let refreshResult = await SableLibraryStep3ComicInfo().applyChecked(
            plan: refreshPlan,
            stage: .comicInfo,
            service: SableLibraryService()
        )
        XCTAssertEqual(refreshResult.appliedCount, 1, refreshResult.summary)
        let refreshedComicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let refreshedIDs = try XCTUnwrap(refreshedComicInfo["ids"] as? [String: Any])
        XCTAssertEqual(refreshedIDs["ranobedb"] as? String, "6585")
        XCTAssertEqual(refreshedComicInfo["year"] as? Int, 2017)
        let refreshedSable = try XCTUnwrap(refreshedComicInfo["_sable"] as? [String: Any])
        let refreshedConfirmations = try XCTUnwrap(refreshedSable["provider_identity_confirmations"] as? [String: Any])
        XCTAssertNotNil(refreshedConfirmations["ranobedb"])
    }

    func testComicInfoSidecarRelocatesReadingFolderIntoTypeRoot() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Incoming/Raw Hero/ComicInfo.json",
            contents: #"{"title":"The Beginning After the End","preferred_title":"The Beginning After the End","type":"manga","year":2018,"ids":{"mangabaka":"1238"}}"#,
            root: root
        )
        try writeFile("Incoming/Raw Hero/Volume 1.cbz", contents: "book", root: root)
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFolders && item.currentPath == "Incoming/Raw Hero"
        })

        XCTAssertEqual(item.proposedPath, "Manga/The Beginning After the End (2018) {mb-1238}")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.reviewTags.contains("naming-title-change"))
        XCTAssertTrue(item.isApplyableFileOperation)

        var approvedItem = item
        approvedItem.decision = .checked
        let plan = LibraryPlan(
            root: root,
            groups: [LibraryPlanGroup(stage: .canonicalFolders, title: "Folders", summary: "Test", items: [approvedItem])]
        )
        let result = await coordinator.applyChecked(plan, stage: .canonicalFolders)

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertFalse(fileExists("Incoming/Raw Hero/ComicInfo.json", root: root))
        XCTAssertTrue(fileExists("Manga/The Beginning After the End (2018) {mb-1238}/ComicInfo.json", root: root))
        XCTAssertTrue(fileExists("Manga/The Beginning After the End (2018) {mb-1238}/Volume 1.cbz", root: root))
    }

    func testLightInventoryBuildsEvidenceMapWithoutSpecialistRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Loose Statement.pdf", contents: "document", root: root)
        try writeFile("Quiet Hero/Vol 01.cbz", contents: "book", root: root)
        try writeFile("Acchi Kocchi/Acchi Kocchi - S01E01.mkv", contents: "video", root: root)

        let coordinator = SableLibraryPipelineCoordinator(service: SableLibraryService())
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectInventoryAndBuildPlan(root: root, options: options)
        let inspection = try XCTUnwrap(run.context.inspection)

        XCTAssertEqual(run.context.inspectMode, .lightInventory)
        XCTAssertEqual(inspection.bookFileCount, 1)
        XCTAssertEqual(inspection.videoFileCount, 1)
        XCTAssertEqual(inspection.fileTypeCounts["pdf"], 1)
        XCTAssertTrue(run.context.plan.items.isEmpty)
    }

    func testFocusedSpecialistInspectPreparesOnlyRequestedLane() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Loose Statement.pdf", contents: "document", root: root)
        try writeFile("Quiet Hero/Vol 01.cbz", contents: "book", root: root)

        let coordinator = SableLibraryPipelineCoordinator(service: SableLibraryService())
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)

        XCTAssertEqual(run.context.inspectMode, .stageDeepDive(.comicInfo))
        XCTAssertTrue(run.context.plan.items.contains {
            $0.stage == .comicInfo && $0.operation == .createComicInfo && $0.currentPath == "Quiet Hero"
        })
        XCTAssertFalse(run.context.plan.items.contains {
            $0.stage == .prepareRawFiles || $0.currentPath == "Loose Statement.pdf"
        })
    }

    func testBooksLaneSidecarWithoutTypeRenamesAsOrdinaryBook() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Books/A Court Of Wings And Ruin/ComicInfo.json",
            contents: #"{"title":"A Court of Wings and Ruin","preferred_title":"A Court of Wings and Ruin","year":2017}"#,
            root: root
        )
        try writeFile(
            "Books/A Court Of Wings And Ruin/A Court Of Wings And Ruin.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFolders && item.currentPath == "Books/A Court Of Wings And Ruin"
        })

        XCTAssertEqual(item.proposedPath, "Books/A Court of Wings and Ruin (2017)")
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.reason.contains("readable title stays the same"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("naming-punctuation-only"))
        XCTAssertTrue(item.confidenceExplanation.contains("treats it as Book"), item.confidenceExplanation)

        let result = await coordinator.applyChecked(run.context.plan, stage: .canonicalFolders)

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertFalse(fileExists("Books/A Court Of Wings And Ruin/ComicInfo.json", root: root))
        XCTAssertTrue(fileExists("Books/A Court of Wings and Ruin (2017)/ComicInfo.json", root: root))
        XCTAssertTrue(fileExists("Books/A Court of Wings and Ruin (2017)/A Court Of Wings And Ruin.epub", root: root))
    }

    func testOpenLibraryIDDoesNotTurnLightNovelLaneIntoOrdinaryBook() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Quiet Hero/ComicInfo.json",
            contents: #"{"title":"Quiet Hero","preferred_title":"Quiet Hero","year":2018,"ids":{"openlibrary":"/works/OL123W"}}"#,
            root: root
        )
        try writeFile(
            "Light Novels/Quiet Hero/Quiet Hero.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFolders && item.currentPath == "Light Novels/Quiet Hero"
        })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.requiresReview)
        XCTAssertTrue(item.reason.contains("media type is missing"), item.reason)
    }

    func testAnimeInfoSidecarRelocatesSeriesFolderAbovePlexSeasonFolder() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Incoming/Frieren/AnimeInfo.json",
            contents: #"{"title":"Frieren: Beyond Journey's End","preferred_title":"Frieren: Beyond Journey's End","type":"animeTV","year":2023,"ids":{"mal":"52991"}}"#,
            root: root
        )
        try writeFile("Incoming/Frieren/Season 01/Frieren - S01E01.mkv", contents: "video", root: root)
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)

        XCTAssertEqual(Set(run.context.inspection?.videoSeries.map(\.path) ?? []), Set(["Incoming/Frieren"]))
        XCTAssertFalse(run.context.inspection?.missingAnimeInfoSeriesPaths.contains("Incoming/Frieren/Season 01") ?? true)

        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFolders && item.currentPath == "Incoming/Frieren"
        })

        XCTAssertEqual(item.proposedPath, "TV/Frieren Beyond Journey's End (2023)")
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertTrue(item.isApplyableFileOperation)

        let result = await coordinator.applyChecked(run.context.plan, stage: .canonicalFolders)

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertFalse(fileExists("Incoming/Frieren/AnimeInfo.json", root: root))
        XCTAssertTrue(fileExists("TV/Frieren Beyond Journey's End (2023)/AnimeInfo.json", root: root))
        XCTAssertTrue(fileExists("TV/Frieren Beyond Journey's End (2023)/Season 01/Frieren - S01E01.mkv", root: root))
    }

    func testWatchingFolderMoveUsesIMDbButNeverMALInPlexName() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Incoming/Frieren/AnimeInfo.json",
            contents: #"{"title":"Frieren: Beyond Journey's End","preferred_title":"Frieren: Beyond Journey's End","type":"animeTV","year":2023,"ids":{"mal":"52991","imdb":"tt22248376"}}"#,
            root: root
        )
        try writeFile("Incoming/Frieren/Season 01/Frieren - S01E01.mkv", contents: "video", root: root)
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFolders && item.currentPath == "Incoming/Frieren"
        })

        XCTAssertEqual(item.proposedPath, "TV/Frieren Beyond Journey's End (2023) {imdb-tt22248376}")
        XCTAssertFalse(item.proposedPath?.contains("{mal-") ?? true)
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testVideoRawPreparationRunsBeforeAnimeInfoCreation() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Acchi Kocchi - S01E01 [digital].mkv", contents: "video", root: root)
        try writeFile("Acchi Kocchi - S01E01 [digital].eng.forced.srt", contents: "subtitle", root: root)
        try writeFile("Witch Hat Atelier Vol 01 [digital].cbz", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let rawItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles && item.operation == .sortIntoFolder && item.currentPath == "Acchi Kocchi - S01E01 [digital].mkv"
        })

        XCTAssertEqual(rawItem.proposedPath, "Videos/Acchi Kocchi/Acchi Kocchi - S01E01.mkv")
        XCTAssertEqual(rawItem.decision, .checked)
        XCTAssertTrue(run.context.plan.items.contains { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == "Acchi Kocchi - S01E01 [digital].eng.forced.srt"
                && item.proposedPath == "Videos/Acchi Kocchi/Acchi Kocchi - S01E01.eng.forced.srt"
                && item.decision == .checked
        })
        XCTAssertTrue(run.context.plan.items.contains { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == "Witch Hat Atelier Vol 01 [digital].cbz"
                && item.proposedPath == "Manga/Witch Hat Atelier/Witch Hat Atelier - Vol 01.cbz"
                && item.decision == .checked
        })
        XCTAssertFalse(run.context.plan.items.contains { $0.operation == .createAnimeInfo })
    }

    func testVideoRawPreparationGroupsSiteTaggedBareEpisodeNumbers() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("[VideoSite.com] Quiet Show 1.mp4", contents: "video", root: root)
        try writeFile("[VideoSite.com] Quiet Show 2.mp4", contents: "video", root: root)
        try writeFile("[VideoSite.com] Moonlit OVA 01.mp4", contents: "video", root: root)
        try writeFile("[VideoSite.com] Long Title The Animation - 05.mp4", contents: "video", root: root)
        try writeFile("[VideoSite.com] Quiet Movie 2.mp4", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let items = run.context.plan.items.filter { $0.stage == .prepareRawFiles && $0.operation == .sortIntoFolder }
        let proposedPaths = Set(items.compactMap(\.proposedPath))

        XCTAssertTrue(proposedPaths.contains("Videos/Quiet Show/Quiet Show - 01.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Quiet Show/Quiet Show - 02.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Moonlit OVA/Moonlit OVA - 01.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Long Title The Animation/Long Title The Animation - 05.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Quiet Movie 2/Quiet Movie 2.mp4"), proposedPaths.description)
        XCTAssertFalse(proposedPaths.contains { $0.contains("VideoSite") }, proposedPaths.description)
        XCTAssertTrue(items.allSatisfy { $0.decision == .checked })
    }

    func testVideoRawPreparationRepairsSiteTaggedEpisodeWrapperFolders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Videos/[VideoSite.com] Quiet Show 1/[VideoSite.com] Quiet Show 1.mp4", contents: "video", root: root)
        try writeFile("Videos/[VideoSite.com] Quiet Show 2/[VideoSite.com] Quiet Show 2.mp4", contents: "video", root: root)
        try writeFile("Videos/[VideoSite.com] Moonlit OVA 01/[VideoSite.com] Moonlit OVA 01.mp4", contents: "video", root: root)
        try writeFile("Videos/[VideoSite.com] Standalone Special/[VideoSite.com] Standalone Special.mp4", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let repairItems = run.context.plan.items.filter { $0.reviewTags.contains("video-wrapper-folder") }
        let proposedPaths = Set(repairItems.compactMap(\.proposedPath))

        XCTAssertTrue(proposedPaths.contains("Videos/Quiet Show/Quiet Show - 01.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Quiet Show/Quiet Show - 02.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Moonlit OVA/Moonlit OVA - 01.mp4"), proposedPaths.description)
        XCTAssertTrue(proposedPaths.contains("Videos/Standalone Special/Standalone Special.mp4"), proposedPaths.description)
        XCTAssertEqual(repairItems.count, 4)
        XCTAssertTrue(repairItems.allSatisfy { $0.decision == .checked })

        let result = await coordinator.applyChecked(run.context.plan, stage: .prepareRawFiles, options: options)

        XCTAssertEqual(result.skippedCount, 0, result.summary)
        XCTAssertEqual(result.appliedCount, 4, result.summary)
        XCTAssertTrue(fileExists("Videos/Quiet Show/Quiet Show - 01.mp4", root: root))
        XCTAssertTrue(fileExists("Videos/Quiet Show/Quiet Show - 02.mp4", root: root))
        XCTAssertTrue(fileExists("Videos/Moonlit OVA/Moonlit OVA - 01.mp4", root: root))
        XCTAssertTrue(fileExists("Videos/Standalone Special/Standalone Special.mp4", root: root))
        XCTAssertFalse(fileExists("Videos/[VideoSite.com] Quiet Show 1", root: root))
        XCTAssertFalse(fileExists("Videos/[VideoSite.com] Quiet Show 2", root: root))
        XCTAssertFalse(fileExists("Videos/[VideoSite.com] Moonlit OVA 01", root: root))
        XCTAssertFalse(fileExists("Videos/[VideoSite.com] Standalone Special", root: root))
    }

    func testSourceTaggedVideoSeriesFolderCleansBeforeAnimeInfoRefresh() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Videos/[HentaiOcean] Ikusei/AnimeInfo.json",
            contents: """
            {
              "title": "[HentaiOcean] Ikusei",
              "preferred_title": "[HentaiOcean] Ikusei",
              "local_title": "[HentaiOcean] Ikusei",
              "sort_title": "[HentaiOcean] Ikusei",
              "type": "tvShow",
              "source": "local",
              "plex": {
                "title": "[HentaiOcean] Ikusei",
                "series_path": "TV/[HentaiOcean] Ikusei"
              },
              "_sable": {
                "organizer_source": {
                  "folder_name": "[HentaiOcean] Ikusei",
                  "clean_title": "[HentaiOcean] Ikusei"
                }
              }
            }
            """,
            root: root
        )
        try writeFile(
            "Videos/[HentaiOcean] Ikusei/.plexmatch",
            contents: """
            # Generated by Sable's Library from AnimeInfo.json
            title: [HentaiOcean] Ikusei

            """,
            root: root
        )
        try writeFile(
            "Videos/[HentaiOcean] Ikusei/Season 01/[HentaiOcean] Ikusei - S01E01.mp4",
            contents: "video",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let folderItem = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .renameFolder
                && $0.currentPath == "Videos/[HentaiOcean] Ikusei"
        })

        XCTAssertEqual(folderItem.proposedPath, "Videos/Ikusei")
        XCTAssertEqual(folderItem.decision, .checked)
        XCTAssertTrue(folderItem.reviewTags.contains("raw-video-source-folder"))
        XCTAssertFalse(run.context.plan.items.contains { $0.operation == .refreshAnimeInfo })

        let rawResult = await coordinator.applyChecked(run.context.plan, stage: .prepareRawFiles, options: options)

        XCTAssertEqual(rawResult.skippedCount, 0, rawResult.summary)
        XCTAssertTrue(fileExists("Videos/Ikusei/AnimeInfo.json", root: root))
        XCTAssertTrue(fileExists("Videos/Ikusei/.plexmatch", root: root))
        XCTAssertTrue(fileExists("Videos/Ikusei/Season 01/[HentaiOcean] Ikusei - S01E01.mp4", root: root))
        XCTAssertFalse(fileExists("Videos/[HentaiOcean] Ikusei", root: root))

        let refreshRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let cleanerItem = try XCTUnwrap(refreshRun.context.plan.items.first {
            $0.operation == .refreshAnimeInfo && $0.currentPath == "Videos/Ikusei"
        })

        XCTAssertTrue(cleanerItem.reviewTags.contains("metadata-animeinfo-cleaner"))
        XCTAssertFalse(cleanerItem.usedNetworkData)

        let refreshResult = await coordinator.applyChecked(
            planByChecking(cleanerItem.id, in: refreshRun.context.plan),
            stage: .comicInfo,
            options: options
        )
        let animeInfo = try jsonObject("Videos/Ikusei/AnimeInfo.json", root: root)
        let plex = try XCTUnwrap(animeInfo["plex"] as? [String: Any])
        let sable = try XCTUnwrap(animeInfo["_sable"] as? [String: Any])
        let organizer = try XCTUnwrap(sable["organizer_source"] as? [String: Any])

        XCTAssertEqual(refreshResult.appliedCount, 1)
        XCTAssertEqual(animeInfo["preferred_title"] as? String, "Ikusei")
        XCTAssertEqual(animeInfo["title"] as? String, "Ikusei")
        XCTAssertEqual(animeInfo["local_title"] as? String, "Ikusei")
        XCTAssertEqual(plex["title"] as? String, "Ikusei")
        XCTAssertEqual(organizer["folder_name"] as? String, "Ikusei")
        XCTAssertEqual(organizer["clean_title"] as? String, "Ikusei")
        XCTAssertFalse(try stringContents("Videos/Ikusei/.plexmatch", root: root).contains("HentaiOcean"))

        let renameRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let fileItem = try XCTUnwrap(renameRun.context.plan.items.first {
            $0.operation == .renameFile
                && $0.currentPath == "Videos/Ikusei/Season 01/[HentaiOcean] Ikusei - S01E01.mp4"
        })

        XCTAssertEqual(fileItem.proposedPath, "Videos/Ikusei/Season 01/Ikusei - S01E01.mp4")
        XCTAssertTrue(fileItem.isApplyableFileOperation)
    }

    func testNumberedVideoWrapperWithGeneratedAnimeInfoMergesIntoSiblingSeriesAfterReview() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Videos/Nagachichi Nagaisan/AnimeInfo.json",
            contents: #"{"title":"Nagachichi Nagaisan","preferred_title":"Nagachichi Nagaisan","type":"tvShow","source":"local","ids":{}}"#,
            root: root
        )
        try writeFile(
            "Videos/Nagachichi Nagaisan/Season 01/Nagachichi Nagaisan - S01E02.mp4",
            contents: "video",
            root: root
        )
        try writeFile(
            "Videos/Nagachichi Nagaisan 3/AnimeInfo.json",
            contents: #"{"title":"Nagachichi Nagaisan 3","preferred_title":"Nagachichi Nagaisan 3","type":"unknownVideo","source":"local","ids":{},"_sable":{"sidecar":"AnimeInfo.json"}}"#,
            root: root
        )
        try writeFile(
            "Videos/Nagachichi Nagaisan 3/.plexmatch",
            contents: "title: Nagachichi Nagaisan 3\n",
            root: root
        )
        try writeFile(
            "Videos/Nagachichi Nagaisan 3/Nagachichi Nagaisan 3.mp4",
            contents: "video",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath == "Videos/Nagachichi Nagaisan 3/Nagachichi Nagaisan 3.mp4"
                && $0.reviewTags.contains("raw-video-numbered-wrapper")
        })

        XCTAssertEqual(item.proposedPath, "Videos/Nagachichi Nagaisan/Season 01/Nagachichi Nagaisan - S01E03.mp4")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.requiresReview)
        XCTAssertTrue(item.isApplyableFileOperation)

        let result = await coordinator.applyChecked(
            planByChecking(item.id, in: run.context.plan),
            stage: .prepareRawFiles,
            options: options
        )

        XCTAssertEqual(result.skippedCount, 0, result.summary)
        XCTAssertEqual(result.appliedCount, 2, result.summary)
        XCTAssertTrue(fileExists("Videos/Nagachichi Nagaisan/Season 01/Nagachichi Nagaisan - S01E03.mp4", root: root))
        XCTAssertFalse(fileExists("Videos/Nagachichi Nagaisan 3", root: root))
        XCTAssertTrue(fileExists("_Sable's Library Reports/Retired Video Sidecars/Videos/Nagachichi Nagaisan 3/AnimeInfo.json", root: root))
        XCTAssertTrue(fileExists("_Sable's Library Reports/Retired Video Sidecars/Videos/Nagachichi Nagaisan 3/.plexmatch", root: root))
    }

    func testNumberedVideoWrapperUsesTrustedTargetAnimeInfoSeasonZero() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Seifuku wa Kita mama de (2026)/AnimeInfo.json",
            contents: #"{"title":"Seifuku wa Kita mama de","preferred_title":"Seifuku wa Kita mama de","type":"ova","year":2026,"source":"anilist","ids":{"anilist":"185402"}}"#,
            root: root
        )
        try writeFile(
            "TV/Seifuku wa Kita mama de (2026)/Season 00/Seifuku wa Kita mama de (2026) - S00E02.mp4",
            contents: "video",
            root: root
        )
        try writeFile(
            "Videos/Seifuku wa Kita mama de 1/AnimeInfo.json",
            contents: #"{"title":"Seifuku wa Kita mama de 1","preferred_title":"Seifuku wa Kita mama de 1","type":"unknownVideo","source":"local","ids":{},"_sable":{"sidecar":"AnimeInfo.json"}}"#,
            root: root
        )
        try writeFile(
            "Videos/Seifuku wa Kita mama de 1/Seifuku wa Kita mama de 1.mp4",
            contents: "video",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath == "Videos/Seifuku wa Kita mama de 1/Seifuku wa Kita mama de 1.mp4"
                && $0.reviewTags.contains("raw-video-numbered-wrapper")
        })

        XCTAssertEqual(item.proposedPath, "TV/Seifuku wa Kita mama de (2026)/Season 00/Seifuku wa Kita mama de (2026) - S00E01.mp4")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertFalse(run.context.plan.items.contains {
            $0.operation == .refreshAnimeInfo && $0.currentPath == "Videos/Seifuku wa Kita mama de 1"
        })
    }

    func testNumberedVideoWrapperMatchesCompactExistingSeriesTitle() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let targetTitle = "Isekai Kita node Sukebe Skill de Zenryoku Ouka Shiyou to Omou"
        let sourceTitle = "Isekai Kita no de Sukebe Skill de Zenryoku Ouka Shiyou to Omou 7"
        try writeFile(
            "Videos/\(targetTitle)/AnimeInfo.json",
            contents: #"{"title":"\#(targetTitle)","preferred_title":"\#(targetTitle)","type":"tvShow","source":"local","ids":{}}"#,
            root: root
        )
        try writeFile(
            "Videos/\(targetTitle)/Season 01/\(targetTitle) - S01E01.mp4",
            contents: "video",
            root: root
        )
        try writeFile(
            "Videos/\(sourceTitle)/AnimeInfo.json",
            contents: #"{"title":"\#(sourceTitle)","preferred_title":"\#(sourceTitle)","type":"unknownVideo","source":"local","ids":{},"_sable":{"sidecar":"AnimeInfo.json"}}"#,
            root: root
        )
        try writeFile(
            "Videos/\(sourceTitle)/\(sourceTitle).mp4",
            contents: "video",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath == "Videos/\(sourceTitle)/\(sourceTitle).mp4"
                && $0.reviewTags.contains("raw-video-numbered-wrapper")
        })

        XCTAssertEqual(item.proposedPath, "Videos/\(targetTitle)/Season 01/\(targetTitle) - S01E07.mp4")
        XCTAssertEqual(item.decision, .unchecked)
    }

    func testRawBookPreparationRepairsVolumeOlTypo() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let rawPath = "A Livid Lady’s Guide To Getting Even How I Crushed My Homeland With My Mighty Grimoires (2022) - Vol Ol 01.epub"
        try writeFile(rawPath, contents: "book", root: root)

        let service = SableLibraryService()
        XCTAssertEqual(
            service.volumeOrChapterSuffix(in: (rawPath as NSString).deletingPathExtension),
            "Vol 01"
        )

        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == rawPath
        })

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/A Livid Lady’s Guide To Getting Even How I Crushed My Homeland With My Mighty Grimoires (2022)/A Livid Lady’s Guide To Getting Even How I Crushed My Homeland With My Mighty Grimoires (2022) - Vol 01.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Vol Ol") ?? true)
        XCTAssertEqual(item.decision, .checked)
    }

    func testRawCBZPreparationNormalizesVAndStripsArchiveMetadata() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let rawPath = "Witch Hat Atelier v01 [Digital] [danke-Empire].cbz"
        let yearPath = "The Count of Monte Cristo (1844) v01 [digital].cbz"
        let groupedVolumePath = "Given Vol 01 (2020) (shizu).cbz"
        try writeFile(rawPath, contents: "book", root: root)
        try writeFile(yearPath, contents: "book", root: root)
        try writeFile(groupedVolumePath, contents: "book", root: root)

        let service = SableLibraryService()
        let config = service.currentConfig()
        XCTAssertEqual(
            service.bookNameParts(for: (rawPath as NSString).deletingPathExtension, config: config).fileTitle,
            "Witch Hat Atelier - Vol 01"
        )
        XCTAssertEqual(
            service.bookNameParts(for: (groupedVolumePath as NSString).deletingPathExtension, config: config).seriesTitle,
            "Given"
        )
        XCTAssertEqual(
            service.bookNameParts(for: (groupedVolumePath as NSString).deletingPathExtension, config: config).fileTitle,
            "Given - Vol 01"
        )

        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == rawPath
        })

        XCTAssertEqual(
            item.proposedPath,
            "Manga/Witch Hat Atelier/Witch Hat Atelier - Vol 01.cbz"
        )
        XCTAssertFalse(item.proposedPath?.localizedCaseInsensitiveContains("v01") ?? true)
        XCTAssertFalse(item.proposedPath?.localizedCaseInsensitiveContains("danke") ?? true)
        XCTAssertEqual(item.decision, .checked)

        let yearItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == yearPath
        })

        XCTAssertEqual(
            yearItem.proposedPath,
            "Manga/The Count Of Monte Cristo (1844)/The Count Of Monte Cristo (1844) - Vol 01.cbz"
        )
        XCTAssertFalse(yearItem.proposedPath?.localizedCaseInsensitiveContains("v01") ?? true)
        XCTAssertFalse(yearItem.proposedPath?.localizedCaseInsensitiveContains("digital") ?? true)
        XCTAssertTrue(yearItem.proposedPath?.contains("(1844)") ?? false)

        let groupedVolumeItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == groupedVolumePath
        })

        XCTAssertEqual(
            groupedVolumeItem.proposedPath,
            "Manga/Given/Given - Vol 01.cbz"
        )
        XCTAssertFalse(groupedVolumeItem.proposedPath?.localizedCaseInsensitiveContains("shizu") ?? true)
        XCTAssertFalse(groupedVolumeItem.proposedPath?.contains("(2020)") ?? true)
        XCTAssertEqual(groupedVolumeItem.decision, .checked)
    }

    func testLooseVolumeEPUBUsesLightNovelLaneWhenPresent() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: fileURL("Light Novels", root: root),
            withIntermediateDirectories: true
        )
        let rawPath = "7th Time Loop The Villainess Enjoys A Carefree Life Married To Her Worst Enemy! (2020) - Vol Ol 01.epub"
        try writeFile(rawPath, contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == rawPath
        })

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/7th Time Loop The Villainess Enjoys A Carefree Life Married To Her Worst Enemy! (2020)/7th Time Loop The Villainess Enjoys A Carefree Life Married To Her Worst Enemy! (2020) - Vol 01.epub"
        )
        XCTAssertTrue(item.reason.contains("Light Novels"), item.reason)
        XCTAssertFalse(item.proposedPath?.contains("Vol Ol") ?? true)
    }

    func testRawProseYearDoesNotBecomeHugeVolumeNumber() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let rawPath = "Waking The Witch - Vol 2010.epub"
        try writeFile(rawPath, contents: "book", root: root)

        let service = SableLibraryService()
        let config = service.currentConfig()
        XCTAssertNil(service.volumeOrChapterSuffix(in: (rawPath as NSString).deletingPathExtension))
        XCTAssertEqual(
            service.bookNameParts(for: (rawPath as NSString).deletingPathExtension, config: config).fileTitle,
            "Waking The Witch (2010)"
        )

        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .sortIntoFolder
                && item.currentPath == rawPath
        })

        XCTAssertEqual(
            item.proposedPath,
            "Books/Waking The Witch (2010)/Waking The Witch (2010).epub"
        )
        XCTAssertTrue(item.reviewTags.contains("raw-reading-book"))
        XCTAssertFalse(item.reviewTags.contains("raw-reading-lightNovel"))
    }

    func testRawReadingUpdateFolderMovesFilesIntoExistingComicInfoSeries() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let existingFolder = "Light Novels/Demon Lord 2099 (2021) {mb-84435} {rdb-11794}"
        try writeFile(
            "\(existingFolder)/ComicInfo.json",
            contents: """
            {
              "title": "Demon Lord 2099",
              "preferred_title": "Demon Lord 2099",
              "year": 2021,
              "type": "lightNovel",
              "ids": {
                "mangabaka": "84435",
                "ranobedb": "11794"
              }
            }
            """,
            root: root
        )
        try writeFile("\(existingFolder)/Demon Lord 2099, Vol. 1- Cyberpunk City Shinjuku.epub", contents: "book", root: root)
        try writeFile("Light Novels/Demon Lord 2099/Demon Lord 2099 - Vol 04.epub", contents: "book", root: root)
        try writeFile("Light Novels/Demon Lord 2099/Demon Lord 2099 - Vol 05 - Demon Lord City Shibuya.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let updateItems = run.context.plan.items.filter {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath.hasPrefix("Light Novels/Demon Lord 2099/")
        }

        XCTAssertEqual(updateItems.count, 2)
        XCTAssertTrue(updateItems.allSatisfy { $0.decision == .checked })
        XCTAssertTrue(updateItems.allSatisfy { $0.reviewTags.contains("raw-existing-series-update") })
        XCTAssertTrue(updateItems.contains {
            $0.currentPath == "Light Novels/Demon Lord 2099/Demon Lord 2099 - Vol 04.epub"
                && $0.proposedPath == "\(existingFolder)/Demon Lord 2099 - Vol 04.epub"
        })
        XCTAssertTrue(updateItems.contains {
            $0.currentPath == "Light Novels/Demon Lord 2099/Demon Lord 2099 - Vol 05 - Demon Lord City Shibuya.epub"
                && $0.proposedPath == "\(existingFolder)/Demon Lord 2099 - Vol 05 - Demon Lord City Shibuya.epub"
        })

        let result = await coordinator.applyChecked(run.context.plan, stage: .prepareRawFiles, options: options)

        XCTAssertEqual(result.appliedCount, 2, result.summary)
        XCTAssertTrue(fileExists("\(existingFolder)/ComicInfo.json", root: root))
        XCTAssertTrue(fileExists("\(existingFolder)/Demon Lord 2099 - Vol 04.epub", root: root))
        XCTAssertTrue(fileExists("\(existingFolder)/Demon Lord 2099 - Vol 05 - Demon Lord City Shibuya.epub", root: root))
        XCTAssertFalse(fileExists("Light Novels/Demon Lord 2099", root: root))
    }

    func testLooseRootReadingFilePrefersExistingComicInfoSeriesFolder() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let existingFolder = "Light Novels/Kusunoki's Garden of Gods (2021) {mb-133507} {rdb-12813}"
        try writeFile(
            "\(existingFolder)/ComicInfo.json",
            contents: """
            {
              "title": "Kusunoki's Garden of Gods",
              "preferred_title": "Kusunoki's Garden of Gods",
              "year": 2021,
              "type": "lightNovel",
              "ids": {
                "mangabaka": "133507",
                "ranobedb": "12813"
              }
            }
            """,
            root: root
        )
        try writeFile("Kusunoki's Garden Of Gods - Vol 04 - Enju.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath == "Kusunoki's Garden Of Gods - Vol 04 - Enju.epub"
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(existingFolder)/Kusunoki's Garden Of Gods - Vol 04 - Enju.epub"
        )
        XCTAssertTrue(item.reviewTags.contains("raw-existing-series-update"))
        XCTAssertEqual(item.decision, .checked)
    }

    func testLooseRootReadingFileStripsPublisherAndDuplicateVolumeTailBeforeExistingSeriesMatch() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let existingFolder = "Light Novels/So I'm a Spider, So What (2015) {mb-84231} {rdb-5180}"
        try writeFile(
            "\(existingFolder)/ComicInfo.json",
            contents: """
            {
              "title": "So I'm a Spider, So What",
              "preferred_title": "So I'm a Spider, So What",
              "year": 2015,
              "type": "lightNovel",
              "ids": {
                "mangabaka": "84231",
                "ranobedb": "5180"
              }
            }
            """,
            root: root
        )
        try writeFile(
            "\(existingFolder)/So I'm a Spider, So What - Vol 01.epub",
            contents: "book",
            root: root
        )
        let rawPath = "So I'm A Spider, So What Volume 02 [yen Press]{v 2}.epub"
        try writeFile(rawPath, contents: "book", root: root)

        let service = SableLibraryService()
        let config = service.currentConfig()
        let parsed = service.bookNameParts(
            for: (rawPath as NSString).deletingPathExtension,
            config: config
        )
        XCTAssertEqual(parsed.seriesTitle, "So I'm A Spider, So What")
        XCTAssertEqual(parsed.fileTitle, "So I'm A Spider, So What - Vol 02")

        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath == rawPath
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(existingFolder)/So I'm A Spider, So What - Vol 02.epub"
        )
        XCTAssertTrue(item.reviewTags.contains("raw-existing-series-update"))
        XCTAssertEqual(item.decision, .checked)
    }

    func testRawReadingUpdateFolderDoesNotGuessBetweenAmbiguousExistingSeries() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let title = "Observation Records of My Fiancee The Misadventures of a Self-Proclaimed Villainess"
        for (year, id) in [(2017, "83994"), (2022, "185873")] {
            let folder = "Light Novels/\(title) (\(year)) {mb-\(id)}"
            try writeFile(
                "\(folder)/ComicInfo.json",
                contents: """
                {
                  "title": "\(title)",
                  "preferred_title": "\(title)",
                  "year": \(year),
                  "type": "lightNovel",
                  "ids": {
                    "mangabaka": "\(id)"
                  }
                }
                """,
                root: root
            )
            try writeFile("\(folder)/\(title) - Vol 01.epub", contents: "book", root: root)
        }
        try writeFile("Light Novels/\(title)/\(title) - Vol 02.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)

        XCTAssertFalse(run.context.plan.items.contains {
            $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
                && $0.currentPath == "Light Novels/\(title)/\(title) - Vol 02.epub"
                && $0.reviewTags.contains("raw-existing-series-update")
        })
    }

    func testRawReadingUpdateFolderUsesComicInfoVariantsAndUniqueStrongMatches() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fixtures: [(existingFolder: String, sidecar: String, rawFolder: String, fileName: String)] = [
            (
                "Light Novels/30 - Romance/7th Time Loop The Villainess Enjoys a Carefree Life Married to Her Worst Enemy! (2020) {mb-84345}",
                """
                {
                  "title": "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
                  "type": "lightNovel",
                  "title_variants": {
                    "english": ["7th Time Loop: The Villainess Enjoys a Carefree Life"]
                  }
                }
                """,
                "Light Novels/7th Time Loop",
                "7th Time Loop - Vol 06.epub"
            ),
            (
                "Light Novels/20 - Fantasy & Supernatural/I Parry Everything What Do You Mean I'm the Strongest- I'm Not Even an Adventurer Yet! (2020) {mb-83825}",
                """
                {
                  "title": "I Parry Everything: What Do You Mean I'm the Strongest? I'm Not Even an Adventurer Yet!",
                  "type": "lightNovel",
                  "title_variants": {
                    "english": ["I Parry Everything"]
                  }
                }
                """,
                "Light Novels/I Parry Everything",
                "I Parry Everything - Vol 10.epub"
            ),
            (
                "Light Novels/30 - Romance/An Archdemon's Dilemma How to Love Your Elf Bride (2017) {mb-84443}",
                """
                {
                  "title": "An Archdemon's Dilemma: How to Love Your Elf Bride",
                  "type": "lightNovel"
                }
                """,
                "Light Novels/An Archdemon's Dilemma How To Love Your Slave Elf Bride",
                "An Archdemon's Dilemma How To Love Your Slave Elf Bride - Vol 20.epub"
            )
        ]

        for fixture in fixtures {
            try writeFile("\(fixture.existingFolder)/ComicInfo.json", contents: fixture.sidecar, root: root)
            try writeFile("\(fixture.existingFolder)/Existing - Vol 01.epub", contents: "book", root: root)
            try writeFile("\(fixture.rawFolder)/\(fixture.fileName)", contents: "update", root: root)
        }

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: options,
            stage: .prepareRawFiles
        )

        for fixture in fixtures {
            let item = try XCTUnwrap(run.context.plan.items.first {
                $0.currentPath == "\(fixture.rawFolder)/\(fixture.fileName)"
                    && $0.reviewTags.contains("raw-existing-series-update")
            })
            XCTAssertEqual(
                item.proposedPath,
                "\(fixture.existingFolder)/\(fixture.fileName)",
                fixture.rawFolder
            )
        }
    }

    func testRawReadingUpdateFolderUsesCompactRomanizedAliasWithoutMergingSpinOff() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let existingFolder = "Light Novels/20 - Fantasy & Supernatural/Is It Wrong to Try to Pick Up Girls in a Dungeon (2013) {mb-83316}"
        try writeFile(
            "\(existingFolder)/ComicInfo.json",
            contents: """
            {
              "title": "Is It Wrong to Try to Pick Up Girls in a Dungeon?",
              "romanized_title": "DanMachi",
              "type": "lightNovel"
            }
            """,
            root: root
        )
        try writeFile("\(existingFolder)/Existing - Vol 01.epub", contents: "book", root: root)
        try writeFile("Light Novels/Dan Machi/Dan Machi - Vol 19.epub", contents: "update", root: root)
        try writeFile(
            "Light Novels/Dan Machi Familia Chronicle/Dan Machi Familia Chronicle - Vol 03.epub",
            contents: "spin-off",
            root: root
        )

        let service = SableLibraryService()
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: options,
            stage: .prepareRawFiles
        )

        let mainSeriesItem = try XCTUnwrap(run.context.plan.items.first {
            $0.currentPath == "Light Novels/Dan Machi/Dan Machi - Vol 19.epub"
                && $0.reviewTags.contains("raw-existing-series-update")
        })
        XCTAssertEqual(mainSeriesItem.proposedPath, "\(existingFolder)/Dan Machi - Vol 19.epub")
        XCTAssertFalse(run.context.plan.items.contains {
            $0.currentPath.contains("Dan Machi Familia Chronicle")
                && $0.reviewTags.contains("raw-existing-series-update")
                && $0.proposedPath?.hasPrefix(existingFolder) == true
        })
    }

    func testRawBookNamePartsRecoverMalformedReleaseTailsAndDecimalVolume() {
        let service = SableLibraryService()
        let config = service.currentConfig()
        let fixtures: [(raw: String, series: String, file: String)] = [
            (
                "Earl and Fairy - Volume 12 [J-Novel Club][Premium[Zaphkiel]",
                "Earl And Fairy",
                "Earl And Fairy - Vol 12"
            ),
            (
                "The Apothecary Diaries - Volume 16 [J-Novel Club]Premium]",
                "The Apothecary Diaries",
                "The Apothecary Diaries - Vol 16"
            ),
            (
                "The Apothecary Diaries v13 [J-Novel Club] [Premium] [CleanBookGuy] {r}",
                "The Apothecary Diaries",
                "The Apothecary Diaries - Vol 13"
            ),
            (
                "Kuma Kuma Kuma Bear - Volume 20.5 [Seven Seas][Kobo]",
                "Kuma Kuma Kuma Bear",
                "Kuma Kuma Kuma Bear - Vol 20.5"
            )
        ]

        for fixture in fixtures {
            let parsed = service.bookNameParts(for: fixture.raw, config: config)
            XCTAssertEqual(parsed.seriesTitle, fixture.series, fixture.raw)
            XCTAssertEqual(parsed.fileTitle, fixture.file, fixture.raw)
        }
    }

    func testCanonicalFilesRepairsSplitVolumeWrapperFolders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstFolder = "Manga/Given Vol 01 (2020) (shizu)"
        let secondFolder = "Manga/Given Vol 02 (2020) (shizu)"
        let firstFile = "\(firstFolder)/Given Vol 01 (2020) (shizu).cbz"
        let secondFile = "\(secondFolder)/Given Vol 02 (2020) (shizu).cbz"
        try writeFile(firstFile, contents: "vol1", root: root)
        try writeFile(secondFile, contents: "vol2", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let firstItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath == firstFile
        })
        let secondItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath == secondFile
        })

        XCTAssertEqual(firstItem.proposedPath, "Manga/Given/Given - Vol 01.cbz")
        XCTAssertEqual(secondItem.proposedPath, "Manga/Given/Given - Vol 02.cbz")
        XCTAssertEqual(firstItem.decision, .checked)
        XCTAssertEqual(secondItem.decision, .checked)
        XCTAssertTrue(firstItem.reviewTags.contains("volume-wrapper-folder"))
        XCTAssertTrue(secondItem.reviewTags.contains("volume-wrapper-folder"))

        let result = await coordinator.applyChecked(run.context.plan, stage: .canonicalFiles, options: options)
        XCTAssertEqual(result.appliedCount, 2)
        XCTAssertTrue(fileExists("Manga/Given/Given - Vol 01.cbz", root: root))
        XCTAssertTrue(fileExists("Manga/Given/Given - Vol 02.cbz", root: root))
        XCTAssertFalse(fileExists(firstFolder, root: root))
        XCTAssertFalse(fileExists(secondFolder, root: root))
    }

    func testCanonicalFilesDoNotDuplicateVolumeMarkerFromSidecarTitle() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Interspecies Reviewers, Vol. 1 (2018) {mb-101215} {rdb-8844}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Interspecies Reviewers, Vol. 1",
              "preferred_title": "Interspecies Reviewers, Vol. 1",
              "year": 2018,
              "type": "Novel",
              "ids": {
                "mangabaka": "101215",
                "ranobedb": "8844"
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Interspecies Reviewers - Vol 01 - Ecstasy Days.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath.hasSuffix("Vol 01 - Ecstasy Days.epub")
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Interspecies Reviewers (2018) - Vol 01 - Ecstasy Days.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Vol. 1 (2018) - Vol 01") ?? true)
        XCTAssertEqual(item.decision, .checked)
    }

    func testCanonicalFilesPreserveReadingProviderTokensAlreadyInFileName() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ai no Kusabi (1986) {mb-82805}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Ai no Kusabi",
              "preferred_title": "Ai no Kusabi",
              "year": 1986,
              "type": "Novel",
              "ids": {
                "mangabaka": "82805"
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Ai no Kusabi {rdb-42} {mal-123} {al-456} - Vol 01.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath.contains("{rdb-42}")
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Ai no Kusabi (1986) {rdb-42} {mal-123} {al-456} - Vol 01.epub"
        )
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("naming-provider-token-preserved"))
        XCTAssertTrue(item.reviewTags.contains("provider-token-ranobedb"))
        XCTAssertTrue(item.reviewTags.contains("provider-token-myanimelist"))
        XCTAssertTrue(item.reviewTags.contains("provider-token-anilist"))
    }

    func testCanonicalFilesTitleChangesBecomeManualApprovalRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ai no Kusabi (1986) {mb-82805}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Ai no Kusabi - O Espaço Entre",
              "preferred_title": "Ai no Kusabi - O Espaço Entre",
              "year": 1986,
              "type": "Novel",
              "ids": {
                "mangabaka": "82805"
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Ai no Kusabi - Vol 01.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath.hasSuffix("Ai no Kusabi - Vol 01.epub")
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Ai no Kusabi - O Espaço Entre (1986) - Vol 01.epub"
        )
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.requiresReview)
        XCTAssertTrue(item.reviewTags.contains("naming-title-change"))
        XCTAssertTrue(item.isManualApprovalFileOperation)
        XCTAssertTrue(item.needsDecisionReview)
    }

    func testCanonicalFilesKeepFullLocalSeriesTitleWhenProviderTitleIsShortAlias() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fullTitle = "Banished from the Hero's Party, I Decided to Live a Quiet Life in the Countryside"
        let folder = "Light Novels/\(fullTitle) (2017) {mb-85173} {rdb-8215}"
        let currentFile = "\(folder)/Banished from the Hero's Party - Vol 01.epub"
        try writeFile(currentFile, contents: "book", root: root)

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: folder,
                path: folder,
                displayName: fullTitle,
                localTitle: "\(fullTitle), Vol. 4 (light Novel)",
                preferredTitle: "Banished from the Hero's Party",
                mediaType: "lightNovel",
                year: 2017,
                primarySourceID: SableLibrarySourceID(provider: .mangabaka, value: "85173"),
                identityGraph: SableLibraryIdentityGraph(
                    domain: .reading,
                    preferredTitle: "Banished from the Hero's Party",
                    year: 2017,
                    readingType: .lightNovel,
                    sourceIDs: [
                        SableLibrarySourceID(provider: .mangabaka, value: "85173"),
                        SableLibrarySourceID(provider: .ranobedb, value: "8215")
                    ]
                ),
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: 4,
                comicInfoSource: "mangabaka, ranobedb",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]
        inspection.books = [
            LibraryBookSnapshot(
                id: currentFile,
                path: currentFile,
                fileName: "Banished from the Hero's Party - Vol 01.epub",
                fileExtension: "epub",
                seriesID: folder,
                isPackageBook: false
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep5CanonicalFiles().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/\(fullTitle) (2017) - Vol 01.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Vol. 4 (light Novel)") ?? true)
        XCTAssertFalse(item.proposedPath?.hasSuffix("Banished from the Hero's Party (2017) - Vol 01.epub") ?? true)
    }

    func testCanonicalFilesDoNotSpreadRanobeDBBookTitleAcrossOtherVolumes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Dan Machi Familia Chronicle (2020) {rdb-6585}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Is It Wrong to Try to Pick up Girls in a Dungeon? Familia Chronicle, Vol. 2",
              "preferred_title": "Is It Wrong to Try to Pick up Girls in a Dungeon? Familia Chronicle, Vol. 2",
              "local_title": "Dan Machi Familia Chronicle",
              "type": "Novel",
              "year": 2020,
              "ids": {
                "ranobedb": "6585"
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Dan Machi Familia Chronicle - Vol 01.epub", contents: "book", root: root)

        let coordinator = SableLibraryPipelineCoordinator(service: SableLibraryService())
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.operation == .renameFile && item.currentPath.hasSuffix("Vol 01.epub")
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Dan Machi Familia Chronicle (2020) - Vol 01.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Familia Chronicle, Vol. 2") ?? true)
    }

    func testCanonicalFilesPunctuationOnlyTitleCleanupStaysChecked() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/A Livid Lady’s Guide (2022) {mb-83051}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "A Livid Lady's Guide",
              "preferred_title": "A Livid Lady's Guide",
              "year": 2022,
              "type": "Novel",
              "ids": {
                "mangabaka": "83051"
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/A Livid Lady’s Guide - Vol 01.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let item = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath.hasSuffix("A Livid Lady’s Guide - Vol 01.epub")
        })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/A Livid Lady's Guide (2022) - Vol 01.epub"
        )
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.reviewTags.contains("naming-punctuation-only"))
    }

    func testMixedLooseReadingDumpRoutesIntoDetectedReadingLanes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Fake Saint Of The Year (2021) - Vol Ol 02.epub", contents: "book", root: root)
        try writeFile("Witch Hat Atelier Vol 01.cbz", contents: "comic", root: root)
        try writeFile("Solo Leveling Webtoon Vol 01.epub", contents: "book", root: root)
        try writeFile("Manhwa Royal Chef Vol 01.epub", contents: "book", root: root)
        try writeFile("The Long Game.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let prepareItems = run.context.plan.items.filter { $0.stage == .prepareRawFiles }

        XCTAssertTrue(prepareItems.contains { item in
            item.currentPath == "Fake Saint Of The Year (2021) - Vol Ol 02.epub"
                && item.proposedPath == "Light Novels/Fake Saint Of The Year (2021)/Fake Saint Of The Year (2021) - Vol 02.epub"
                && item.decision == .checked
                && item.reviewTags.contains("raw-reading-lightNovel")
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.currentPath == "Witch Hat Atelier Vol 01.cbz"
                && item.proposedPath == "Manga/Witch Hat Atelier/Witch Hat Atelier - Vol 01.cbz"
                && item.decision == .checked
                && item.reviewTags.contains("raw-reading-manga")
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.currentPath == "Solo Leveling Webtoon Vol 01.epub"
                && item.proposedPath == "Manhwa/Solo Leveling Webtoon/Solo Leveling Webtoon - Vol 01.epub"
                && item.decision == .checked
                && item.reviewTags.contains("raw-reading-manhwa")
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.currentPath == "Manhwa Royal Chef Vol 01.epub"
                && item.proposedPath == "Manhwa/Manhwa Royal Chef/Manhwa Royal Chef - Vol 01.epub"
                && item.decision == .checked
                && item.reviewTags.contains("raw-reading-manhwa")
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.currentPath == "The Long Game.epub"
                && item.proposedPath == "Books/The Long Game/The Long Game.epub"
                && item.decision == .checked
                && item.reviewTags.contains("raw-reading-book")
        })
    }

    func testLargeRawReadingBatchStartsAsTrainingMaterial() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 1...260 {
            let number = String(format: "%03d", index)
            try writeFile("Training Lesson Series (2024) - Vol \(number).epub", contents: "book", root: root)
        }

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .prepareRawFiles)
        let placeGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Place raw media" })

        XCTAssertEqual(placeGroup.items.count, 260)
        XCTAssertTrue(placeGroup.reviewPrompt.contains("training material"), placeGroup.reviewPrompt)
        XCTAssertTrue(placeGroup.items.allSatisfy { $0.decision == .unchecked })
        XCTAssertTrue(placeGroup.items.allSatisfy { !$0.needsDecisionReview })
        XCTAssertTrue(placeGroup.items.allSatisfy { $0.reviewTags.contains("training-material") })
        XCTAssertTrue(placeGroup.items.allSatisfy { $0.reviewTags.contains("bulk-raw-review") })
    }

    func testTopLevelMediaSeriesFoldersMoveIntoBroadHomes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Witch Hat Atelier/Witch Hat Atelier Vol 01.cbz", contents: "book", root: root)
        try writeFile("Witch Hat Atelier Vol 02 [digital].cbz", contents: "book", root: root)
        try writeFile("Quiet Show/Quiet Show S01E01.mkv", contents: "video", root: root)
        try writeFile("Quiet Show S01E02.mkv", contents: "video", root: root)
        try writeFile("Manga/Already Sorted/Already Sorted Vol 01.cbz", contents: "book", root: root)
        try writeFile("Light Novels/Already Sorted Novel/Already Sorted Novel Vol 01.epub", contents: "book", root: root)
        try writeFile("TV/Already Sorted Anime/Already Sorted Anime S01E01.mkv", contents: "video", root: root)
        try writeFile("Movies/Already Sorted Anime Movie/Already Sorted Anime Movie.mkv", contents: "video", root: root)
        try writeFile("Movies/Already Sorted Movie/Already Sorted Movie.mkv", contents: "video", root: root)
        try writeFile("TV/Already Sorted Show/Already Sorted Show S01E01.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let prepareItems = run.context.plan.items.filter { $0.stage == .prepareRawFiles }

        XCTAssertTrue(prepareItems.contains { item in
            item.operation == .renameFolder
                && item.currentPath == "Witch Hat Atelier"
                && item.proposedPath == "Manga/Witch Hat Atelier"
                && item.decision == .checked
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.operation == .sortIntoFolder
                && item.currentPath == "Witch Hat Atelier Vol 02 [digital].cbz"
                && item.proposedPath == "Witch Hat Atelier/Witch Hat Atelier - Vol 02.cbz"
                && item.decision == .checked
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.operation == .renameFolder
                && item.currentPath == "Quiet Show"
                && item.proposedPath == "Videos/Quiet Show"
                && item.decision == .checked
        })
        XCTAssertTrue(prepareItems.contains { item in
            item.operation == .sortIntoFolder
                && item.currentPath == "Quiet Show S01E02.mkv"
                && item.proposedPath == "Quiet Show/Quiet Show S01E02.mkv"
                && item.decision == .checked
        })
        XCTAssertFalse(prepareItems.contains { item in
            item.operation == .renameFolder
                && item.currentPath == "Manga"
                && item.proposedPath == "Books/Manga"
        })
        for protectedRoot in ["Manga", "Light Novels", "TV", "Movies"] {
            XCTAssertFalse(prepareItems.contains { item in
                item.operation == .renameFolder
                    && item.currentPath == protectedRoot
            }, "\(protectedRoot) should stay in place during raw preparation.")
        }

        let result = await coordinator.applyChecked(run.context.plan, stage: .prepareRawFiles)

        XCTAssertEqual(result.skippedCount, 0, result.summary)
        XCTAssertTrue(fileExists("Manga/Witch Hat Atelier/Witch Hat Atelier Vol 01.cbz", root: root))
        XCTAssertTrue(fileExists("Manga/Witch Hat Atelier/Witch Hat Atelier - Vol 02.cbz", root: root))
        XCTAssertTrue(fileExists("Videos/Quiet Show/Quiet Show S01E01.mkv", root: root))
        XCTAssertTrue(fileExists("Videos/Quiet Show/Quiet Show S01E02.mkv", root: root))
        XCTAssertFalse(fileExists("Witch Hat Atelier", root: root))
        XCTAssertFalse(fileExists("Quiet Show", root: root))
    }

    func testLegacyWatchingRootsRenameToNeutralPlexHomes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Anime TV/Legacy Show/Legacy Show S01E01.mkv", contents: "video", root: root)
        try writeFile("Anime Movies/Legacy Movie/Legacy Movie.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let prepareItems = run.context.plan.items.filter { $0.stage == .prepareRawFiles }

        XCTAssertTrue(prepareItems.contains {
            $0.operation == .renameFolder
                && $0.currentPath == "Anime TV"
                && $0.proposedPath == "TV"
                && $0.decision == .checked
                && $0.safety == .reversible
        })
        XCTAssertTrue(prepareItems.contains {
            $0.operation == .renameFolder
                && $0.currentPath == "Anime Movies"
                && $0.proposedPath == "Movies"
                && $0.decision == .checked
                && $0.safety == .reversible
        })

        let result = await coordinator.applyChecked(run.context.plan, stage: .prepareRawFiles)

        XCTAssertEqual(result.appliedCount, 2)
        XCTAssertFalse(fileExists("Anime TV/Legacy Show/Legacy Show S01E01.mkv", root: root))
        XCTAssertFalse(fileExists("Anime Movies/Legacy Movie/Legacy Movie.mkv", root: root))
        XCTAssertTrue(fileExists("TV/Legacy Show/Legacy Show S01E01.mkv", root: root))
        XCTAssertTrue(fileExists("Movies/Legacy Movie/Legacy Movie.mkv", root: root))
    }

    func testLegacyWatchingRootsMergeIntoExistingNeutralHomesAfterReview() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Anime TV/Legacy Show/Legacy Show S01E01.mkv", contents: "video", root: root)
        try writeFile("TV/Existing Show/Existing Show S01E01.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let mergeItem = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles
                && $0.operation == .renameFolder
                && $0.currentPath == "Anime TV"
                && $0.proposedPath == "TV"
        })

        XCTAssertEqual(mergeItem.safety, .collision)
        XCTAssertEqual(mergeItem.decision, .unchecked)
        XCTAssertEqual(mergeItem.reason, PlannedMove.manualFolderMergeReason)
        XCTAssertTrue(mergeItem.canMergeIntoExistingFolder)

        let result = await coordinator.applyChecked(planByChecking(mergeItem.id, in: run.context.plan), stage: .prepareRawFiles)

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertFalse(fileExists("Anime TV/Legacy Show/Legacy Show S01E01.mkv", root: root))
        XCTAssertTrue(fileExists("TV/Legacy Show/Legacy Show S01E01.mkv", root: root))
        XCTAssertTrue(fileExists("TV/Existing Show/Existing Show S01E01.mkv", root: root))
    }

    func testLooseGenericFilesMoveIntoBroadTypeFolders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Sample Notes (3).docx", contents: "document", root: root)
        try writeFile("Portrait prompt.webp", contents: "image", root: root)
        try writeFile("Unheard and Unseen.mp3", contents: "audio", root: root)
        try writeFile("Direct Messages.zip", contents: "archive", root: root)
        try writeFile("sample-user.json", contents: "json", root: root)
        try writeFile("ComicInfo.json", contents: "sidecar", root: root)
        try writeFile("AnimeInfo.json", contents: "sidecar", root: root)
        try writeFile("Nested/Notes.docx", contents: "nested document", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let typeGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Sort other root files" })

        XCTAssertEqual(typeGroup.items.count, 6)
        XCTAssertTrue(typeGroup.items.allSatisfy { $0.decision == .checked })
        XCTAssertTrue(typeGroup.items.contains { $0.currentPath == "Sample Notes (3).docx" && $0.proposedPath == "Documents/Word/Sample Notes (3).docx" })
        XCTAssertTrue(typeGroup.items.contains { $0.currentPath == "Portrait prompt.webp" && $0.proposedPath == "Images/WebP/Portrait prompt.webp" })
        XCTAssertTrue(typeGroup.items.contains { $0.currentPath == "Unheard and Unseen.mp3" && $0.proposedPath == "Audio/MP3/Unheard and Unseen.mp3" })
        XCTAssertTrue(typeGroup.items.contains { $0.currentPath == "Direct Messages.zip" && $0.proposedPath == "Archives/ZIP/Direct Messages.zip" })
        XCTAssertTrue(typeGroup.items.contains { $0.currentPath == "sample-user.json" && $0.proposedPath == "Documents/JSON/sample-user.json" })
        XCTAssertTrue(typeGroup.items.contains { $0.currentPath == "Nested" && $0.proposedPath == "Documents/Word/Nested" && $0.operation == .renameFolder })
        XCTAssertFalse(run.context.plan.items.contains { $0.currentPath == "Nested/Notes.docx" })
        XCTAssertFalse(run.context.plan.items.contains { $0.currentPath == "ComicInfo.json" || $0.currentPath == "AnimeInfo.json" })
    }

    func testLocalLearningCanRerouteGenericCleanupKind() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Mood Board Reference.nikki", contents: "custom image-ish asset", root: root)

        var learning = SableLibraryLearningMemory()
        learning.recordCleanupKind(
            path: "Mood Board Asset.nikki",
            proposedPath: "Images/Mood Board Asset.nikki",
            kind: .image
        )
        learning.recordCleanupKind(
            path: "Mood Board Draft.nikki",
            proposedPath: "Images/Mood Board Draft.nikki",
            kind: .image
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions(useLocalLearning: true),
            learning: learning
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "Mood Board Reference.nikki"
        })

        XCTAssertEqual(item.proposedPath, "Images/Other Images/Mood Board Reference.nikki")
        XCTAssertTrue(item.reviewTags.contains("learned-cleanup-kind"))
        XCTAssertTrue(item.reviewTags.contains("cleanup-kind-image"))
        XCTAssertTrue(item.confidenceExplanation.contains("Learned cleanup clue"))
        XCTAssertEqual(item.decision, .checked)
    }

    func testUnknownLooseFilesStayInOtherReviewUntilTaught() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Unsorted Payload.nikki", contents: "unknown local file", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.stage == .prepareRawFiles && $0.currentPath == "Unsorted Payload.nikki"
        })

        XCTAssertEqual(item.proposedPath, "Other/Unsorted Payload.nikki")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.reviewTags.contains("cleanup-kind-other"))
        XCTAssertTrue(item.correctionOptions.contains(.treatAsDocuments))
        XCTAssertTrue(item.correctionOptions.contains(.treatAsImages))
    }

    func testApplyResultCarriesAppliedPathsForLearning() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Sample Notes (3).docx", contents: "document", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let result = await coordinator.applyChecked(run.context.plan, stage: .prepareRawFiles, options: options)

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertTrue(result.appliedPaths.contains {
            $0.currentPath == "Sample Notes (3).docx"
                && $0.proposedPath == "Documents/Word/Sample Notes (3).docx"
                && $0.stage == .prepareRawFiles
                && $0.operation == .sortIntoFolder
        })
    }

    func testWatchingFolderSourceIDHintAllowsLocalAnimeInfoCreation() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Acchi Kocchi {mal-12291}/Acchi Kocchi - S01E01.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let firstRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let rawFolderItem = try XCTUnwrap(firstRun.context.plan.items.first { item in
            item.stage == .prepareRawFiles
                && item.operation == .renameFolder
                && item.currentPath == "Acchi Kocchi {mal-12291}"
        })

        XCTAssertEqual(rawFolderItem.proposedPath, "Videos/Acchi Kocchi {mal-12291}")
        XCTAssertFalse(firstRun.context.plan.items.contains { $0.operation == .createAnimeInfo })

        let rawResult = await coordinator.applyChecked(firstRun.context.plan, stage: .prepareRawFiles, options: options)
        XCTAssertEqual(rawResult.appliedCount, 1)
        XCTAssertTrue(fileExists("Videos/Acchi Kocchi {mal-12291}/Acchi Kocchi - S01E01.mkv", root: root))

        let secondRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let animeInfoItem = try XCTUnwrap(secondRun.context.plan.items.first { item in
            item.stage == .comicInfo && item.operation == .createAnimeInfo && item.currentPath == "Videos/Acchi Kocchi {mal-12291}"
        })

        XCTAssertEqual(animeInfoItem.proposedPath, "Videos/Acchi Kocchi {mal-12291}/AnimeInfo.json")
        XCTAssertFalse(animeInfoItem.usedNetworkData)
        XCTAssertEqual(animeInfoItem.decision, .checked)

        let animeInfoResult = await coordinator.applyChecked(
            planByChecking(animeInfoItem.id, in: secondRun.context.plan),
            stage: .comicInfo,
            options: options
        )
        let animeInfo = try jsonObject("Videos/Acchi Kocchi {mal-12291}/AnimeInfo.json", root: root)
        let ids = animeInfo["ids"] as? [String: Any] ?? [:]

        XCTAssertEqual(animeInfoResult.appliedCount, 1)
        XCTAssertEqual(animeInfo["preferred_title"] as? String, "Acchi Kocchi")
        XCTAssertEqual(ids["mal"] as? String, "12291")
    }

    func testWatchingFolderWithoutProviderHintGetsLocalAnimeInfoCreation() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Videos/Aoharu Snatch/Aoharu Snatch - 01.mp4", contents: "video", root: root)
        try writeFile("Videos/Aoharu Snatch/Aoharu Snatch - 02.mp4", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let animeInfoItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.stage == .comicInfo
                && item.operation == .createAnimeInfo
                && item.currentPath == "Videos/Aoharu Snatch"
        })

        XCTAssertEqual(animeInfoItem.proposedPath, "Videos/Aoharu Snatch/AnimeInfo.json")
        XCTAssertFalse(animeInfoItem.usedNetworkData)
        XCTAssertEqual(animeInfoItem.metadataProviders, [])
        XCTAssertEqual(animeInfoItem.decision, .checked)

        let result = await coordinator.applyChecked(
            planByChecking(animeInfoItem.id, in: run.context.plan),
            stage: .comicInfo,
            options: options
        )
        let animeInfo = try jsonObject("Videos/Aoharu Snatch/AnimeInfo.json", root: root)
        let ids = animeInfo["ids"] as? [String: Any] ?? [:]

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(animeInfo["preferred_title"] as? String, "Aoharu Snatch")
        XCTAssertEqual(animeInfo["source"] as? String, "local")
        XCTAssertEqual(animeInfo["type"] as? String, "tvShow")
        XCTAssertTrue(ids.isEmpty)

        let renameRun = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .canonicalFiles)
        let firstRename = try XCTUnwrap(renameRun.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath == "Videos/Aoharu Snatch/Aoharu Snatch - 01.mp4"
        })
        let secondRename = try XCTUnwrap(renameRun.context.plan.items.first { item in
            item.stage == .canonicalFiles
                && item.operation == .renameFile
                && item.currentPath == "Videos/Aoharu Snatch/Aoharu Snatch - 02.mp4"
        })

        XCTAssertEqual(
            firstRename.proposedPath,
            "Videos/Aoharu Snatch/Season 01/Aoharu Snatch - S01E01.mp4"
        )
        XCTAssertEqual(
            secondRename.proposedPath,
            "Videos/Aoharu Snatch/Season 01/Aoharu Snatch - S01E02.mp4"
        )
        XCTAssertEqual(firstRename.decision, .checked)
        XCTAssertEqual(secondRename.decision, .checked)
    }

    func testLocalAnimeInfoDoesNotDriveWatchingFolderMove() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Cuticle Detective Inaba/AnimeInfo.json",
            contents: #"{"title":"Cuticle Detective Inaba","preferred_title":"Cuticle Detective Inaba","type":"unknownVideo","source":"local"}"#,
            root: root
        )
        try writeFile(
            "Cuticle Detective Inaba/Cuticle Detective Inaba - S01E01.mkv",
            contents: "video",
            root: root
        )
        try writeFile(
            "Local Anime Guess/AnimeInfo.json",
            contents: #"{"title":"Local Anime Guess","preferred_title":"Local Anime Guess","type":"animeTV","source":"local"}"#,
            root: root
        )
        try writeFile(
            "Local Anime Guess/Local Anime Guess - S01E01.mkv",
            contents: "video",
            root: root
        )
        try writeFile(
            "Yuru Yuri/1. Yuru Yuri/Extra/AnimeInfo.json",
            contents: #"{"title":"Extra","preferred_title":"Extra","type":"unknownVideo","source":"local"}"#,
            root: root
        )
        try writeFile("Yuru Yuri/1. Yuru Yuri/Extra/Extra - S00E01.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let folderMoves = run.context.plan.items.filter { $0.stage == .canonicalFolders && $0.operation == .renameFolder }
        let fileRenames = run.context.plan.items.filter { $0.stage == .canonicalFiles && $0.operation == .renameFile }

        XCTAssertFalse(folderMoves.contains { $0.proposedPath?.hasPrefix("Other Videos/") == true })
        XCTAssertFalse(folderMoves.contains { $0.currentPath == "Local Anime Guess" && $0.proposedPath?.hasPrefix("TV/") == true })
        XCTAssertFalse(folderMoves.contains { $0.currentPath == "Yuru Yuri/1. Yuru Yuri/Extra" })
        XCTAssertTrue(fileRenames.contains {
            $0.currentPath == "Local Anime Guess/Local Anime Guess - S01E01.mkv"
                && $0.proposedPath == "Local Anime Guess/Season 01/Local Anime Guess - S01E01.mkv"
                && $0.isApplyableFileOperation
        })
        XCTAssertFalse(fileRenames.contains { $0.currentPath.hasPrefix("Cuticle Detective Inaba/") })
    }

    func testComicInfoRefreshWritesReadingOrganizerTargets() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Quiet Hero/ComicInfo.json",
            contents: """
            {
              "_goblin": {
                "legacy": true
              },
              "title": "Quiet Hero",
              "preferred_title": "Quiet Hero",
              "type": "manga",
              "year": 2018,
              "mangabaka_id": "1238",
              "ids": {
                "mal": "4567"
              },
              "authors": [
                "Quiet Author"
              ],
              "aliases": [
                "Quiet Hero",
                "Quiet Hero",
                "Quiet Author"
              ],
              "match_evidence": [
                {
                  "kind": "titleSimilarity",
                  "provider": "local",
                  "value": "Quiet Hero",
                  "confidence": 0.5
                },
                {
                  "kind": "titleSimilarity",
                  "provider": "local",
                  "value": "Quiet Hero",
                  "confidence": 0.5
                }
              ],
              "last_checked": "2024-01-01T00:00:00Z",
              "source": "local"
            }
            """,
            root: root
        )
        try writeFile("Quiet Hero/Vol 01.cbz", contents: "book", root: root)
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let refreshItems = run.context.plan.items.filter {
            $0.operation == .refreshComicInfo && $0.currentPath == "Quiet Hero"
        }
        XCTAssertEqual(
            refreshItems.count,
            2,
            refreshItems.map { "\($0.stage.rawValue): \($0.reviewTags.joined(separator: ","))" }.joined(separator: "\n")
        )
        XCTAssertTrue(refreshItems.allSatisfy(\.isApplyableComicInfoOperation))

        let result = await coordinator.applyChecked(planByChecking(Set(refreshItems.map(\.id)), in: run.context.plan), stage: .comicInfo)
        let comicInfo = try jsonObject("Quiet Hero/ComicInfo.json", root: root)
        let plex = try XCTUnwrap(comicInfo["plex"] as? [String: Any])
        let targets = try XCTUnwrap(plex["organizer_targets"] as? [String: Any])
        let ids = try XCTUnwrap(comicInfo["ids"] as? [String: Any])
        let evidence = try XCTUnwrap(comicInfo["match_evidence"] as? [[String: Any]])

        XCTAssertEqual(result.appliedCount, 2)
        XCTAssertNil(comicInfo["_goblin"])
        XCTAssertNil(comicInfo["mangabaka_id"])
        XCTAssertEqual(ids["mangabaka"] as? String, "1238")
        XCTAssertEqual(ids["mal"] as? String, "4567")
        XCTAssertEqual(evidence.filter { ($0["provider"] as? String) == "local" }.count, 1)
        XCTAssertNil(comicInfo["aliases"])
        XCTAssertEqual(comicInfo["authors"] as? [String], ["Quiet Author"])
        XCTAssertEqual(plex["library_kind"] as? String, "reading")
        XCTAssertEqual(plex["year"] as? Int, 2018)
        XCTAssertEqual(plex["title_with_year"] as? String, "Quiet Hero (2018)")
        XCTAssertEqual(plex["series_path"] as? String, "Manga/Quiet Hero (2018) {mb-1238}")
        XCTAssertEqual(targets["folder"] as? String, "Manga/Quiet Hero (2018) {mb-1238}")
        XCTAssertNil(targets["volume_folder"])
        XCTAssertNil(targets["chapters_folder"])
        XCTAssertEqual(targets["volume_file"] as? String, "Manga/Quiet Hero (2018) {mb-1238}/Quiet Hero (2018) - Vol 01.ext")
        XCTAssertNil(plex["volume_file_pattern"])
    }

    func testComicInfoRefreshKeepsTrustedFolderProviderIDs() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Quiet Hero (2018) {mb-1238} {rdb-8844}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Hero",
              "preferred_title": "Quiet Hero",
              "type": "lightNovel",
              "year": 2018,
              "ids": {
                "mal": "4567"
              },
              "_sable": {
                "mangabaka": {
                  "manual_series_id": "1238"
                }
              },
              "last_checked": "2024-01-01T00:00:00Z",
              "source": "local"
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Quiet Hero - Vol 01.epub", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(
            run.context.plan.items.first {
                $0.operation == .refreshComicInfo && $0.currentPath == folder
            }
        )
        XCTAssertTrue(item.isApplyableComicInfoOperation)

        let result = await coordinator.applyChecked(planByChecking(item.id, in: run.context.plan), stage: .comicInfo)
        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let ids = try XCTUnwrap(comicInfo["ids"] as? [String: Any])

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(ids["mangabaka"] as? String, "1238")
        XCTAssertEqual(ids["ranobedb"] as? String, "8844")
        XCTAssertEqual(ids["mal"] as? String, "4567")
    }

    func testMangaBakaTitlesKeepLanguageLabelsOutOfAliases() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ai no Kusabi (1986) {mb-82805}"
        try writeFile("\(folder)/Ai No Kusabi (1986) - Vol 01.epub", contents: "book", root: root)

        let response = """
        {
          "status": 200,
          "data": {
            "id": 82805,
            "title": "Ai no Kusabi",
            "native_title": "間の楔",
            "romanized_title": "Ai no Kusabi",
            "type": "novel",
            "year": 1986,
            "authors": ["Rieko Yoshihara"],
            "description": "Series description.",
            "genres": ["legacy drama"],
            "tags": ["legacy submission"],
            "links": ["https://en.wikipedia.org/wiki/Ai_no_Kusabi", "https://mangabaka.org/82805"],
            "links_v2": [
              { "id": "link-1", "url": "https://mangabaka.org/82805", "name": "mangabaka.org", "name_display": "MangaBaka", "type": "info", "language": "en" }
            ],
            "publishers": [
              { "name": "Juné", "type": "English", "note": "8 Volumes - Complete/Print" }
            ],
            "tags_v2": [
              { "id": 1, "name": "Sci-Fi", "name_path": "Settings > Sci-Fi", "is_genre": true, "is_spoiler": false, "is_explicit": true, "content_rating": "safe", "weight": "defining", "series_count": 14775, "implied_by_tag_ids": [99, 100] },
              { "id": 180, "name": "Boys Love", "name_path": "Themes > Boys Love", "is_genre": true, "is_spoiler": false, "is_explicit": true, "content_rating": "safe", "weight": "defining" },
              { "id": 270, "name": "Space", "name_path": "Locations > Space", "is_genre": false, "is_spoiler": false, "is_explicit": true, "content_rating": "safe", "weight": "defining" },
              { "id": 95, "name": "Rape", "name_path": "Sexual Content > Sexual Acts > Rape", "is_genre": false, "is_spoiler": false, "is_explicit": true, "content_rating": "pornographic", "weight": "recurrent" }
            ],
            "genres_v2": [
              { "id": 300, "name": "Drama", "name_path": "Genres > Drama", "is_genre": true, "is_spoiler": false, "is_explicit": false, "content_rating": "safe", "weight": "core", "description": "Public genre weight should reach SSS." }
            ],
            "relationships_v2": [
              { "id": "rel-1", "to_series_id": 215252, "relation_type": "parody", "chronology": "unknown", "published_start_date": "1992-01-01", "is_manual": false }
            ],
            "recommendations_v2": [
              { "id": 991, "series_id": 12345, "title": "Space BL Neighbor", "score": 0.91, "weight": "core", "reason": "boys love sci-fi", "tags": ["Boys Love", "Sci-Fi"] }
            ],
            "titles": [
              { "language": "ja-Latn", "traits": ["native"], "title": "Ai no Kusabi", "is_primary": true },
              { "language": "en", "traits": ["official"], "title": "Ai no Kusabi", "is_primary": true },
              { "language": "en", "traits": [], "title": "Love's Wedge", "is_primary": false },
              { "language": "en", "traits": [], "title": "The Space Between", "is_primary": false },
              { "language": "pt-br", "traits": [], "title": "Ai no Kusabi - O Espaço Entre", "is_primary": true },
              { "language": "it", "traits": [], "title": "Il Cuneo Dell'Amore", "is_primary": true },
              { "language": "pl", "traits": [], "title": "Miłość na uwięzi", "is_primary": true },
              { "language": "ru", "traits": [], "title": "Клин любви", "is_primary": true },
              { "language": "ko", "traits": [], "title": "아이노 쿠사비", "is_primary": true },
              { "language": "zh-hk", "traits": [], "title": "間之楔", "is_primary": true },
              { "language": "th", "traits": [], "title": "รอยลิ่มรัก", "is_primary": true },
              { "language": "ar", "traits": [], "title": "آي نو كوسابي", "is_primary": true },
              { "language": "ja", "traits": ["native"], "title": "間の楔", "is_primary": true }
            ]
          }
        }
        """.data(using: .utf8)!
        let url = try XCTUnwrap(URL(string: "https://api.mangabaka.org/v1/series/82805"))
        await SableLibraryProviderResponseCache.shared.store(
            response,
            for: SableLibraryProviderResponseCache.key(provider: .mangabaka, url: url),
            ttl: 604_800
        )

        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            currentPath: folder,
            proposedPath: "\(folder)/ComicInfo.json",
            reason: "Use exact MangaBaka ID.",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [.mangabaka],
            manualMangaBakaID: "82805"
        )
        let plan = LibraryPlan(
            root: root,
            groups: [LibraryPlanGroup(stage: .comicInfo, title: "Create Reading ComicInfo from MangaBaka", summary: "Test", items: [item])]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(plan: plan, service: SableLibraryService())
        XCTAssertEqual(result.appliedCount, 1)

        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let variants = try XCTUnwrap(comicInfo["title_variants"] as? [String: Any])
        let genres = comicInfo["genres"] as? [String] ?? []
        let tags = comicInfo["tags"] as? [String] ?? []
        let warnings = comicInfo["content_warnings"] as? [String] ?? []
        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        let mangaBaka = try XCTUnwrap(sable["mangabaka"] as? [String: Any])

        XCTAssertNil(comicInfo["aliases"])
        XCTAssertEqual(comicInfo["preferred_title"] as? String, "Ai no Kusabi")
        XCTAssertEqual(comicInfo["mangabaka_url"] as? String, "https://mangabaka.org/82805")
        XCTAssertTrue((variants["native"] as? [String] ?? []).contains("間の楔"))
        XCTAssertTrue((variants["native"] as? [String] ?? []).contains("아이노 쿠사비"))
        XCTAssertTrue((variants["native"] as? [String] ?? []).contains("間之楔"))
        XCTAssertTrue((variants["romanized"] as? [String] ?? []).contains("Ai no Kusabi"))
        XCTAssertTrue((variants["english"] as? [String] ?? []).contains("Love's Wedge"))
        XCTAssertEqual(variants["portuguese_brazil"] as? [String], ["Ai no Kusabi - O Espaço Entre"])
        XCTAssertEqual(variants["italian"] as? [String], ["Il Cuneo Dell'Amore"])
        XCTAssertEqual(variants["polish"] as? [String], ["Miłość na uwięzi"])
        XCTAssertEqual(variants["russian"] as? [String], ["Клин любви"])
        XCTAssertEqual(variants["thai"] as? [String], ["รอยลิ่มรัก"])
        XCTAssertEqual(variants["arabic"] as? [String], ["آي نو كوسابي"])
        XCTAssertFalse((variants["english"] as? [String] ?? []).contains("Ai no Kusabi - O Espaço Entre"))
        XCTAssertTrue(genres.contains("Sci-Fi"))
        XCTAssertTrue(genres.contains("Boys Love"))
        XCTAssertTrue(genres.contains("Legacy Drama"))
        XCTAssertTrue(tags.contains("Space"))
        XCTAssertTrue(tags.contains("Legacy Submission"))
        XCTAssertFalse(tags.contains("Sci-Fi"))
        XCTAssertTrue(warnings.contains("Rape"))
        XCTAssertEqual((mangaBaka["links_v2"] as? [[String: Any]])?.first?["name_display"] as? String, "MangaBaka")
        XCTAssertEqual((mangaBaka["tags_v2"] as? [[String: Any]])?.first?["name"] as? String, "Sci-Fi")
        XCTAssertEqual((mangaBaka["tags_v2"] as? [[String: Any]])?.first?["series_count"] as? Int, 14775)
        XCTAssertEqual((mangaBaka["tags_v2"] as? [[String: Any]])?.first?["implied_by_tag_ids"] as? [Int], [99, 100])
        XCTAssertEqual((mangaBaka["genres_v2"] as? [[String: Any]])?.first?["weight"] as? String, "core")
        XCTAssertEqual((mangaBaka["genres_v2"] as? [[String: Any]])?.first?["description"] as? String, "Public genre weight should reach SSS.")
        XCTAssertEqual((mangaBaka["relationships_v2"] as? [[String: Any]])?.first?["relation_type"] as? String, "parody")
        XCTAssertEqual((mangaBaka["recommendation_neighbors"] as? [[String: Any]])?.first?["weight"] as? String, "core")
        XCTAssertEqual((mangaBaka["recommendation_neighbors"] as? [[String: Any]])?.first?["reason"] as? String, "boys love sci-fi")
        XCTAssertEqual((mangaBaka["titles_v2"] as? [[String: Any]])?.count, 13)
        XCTAssertEqual((mangaBaka["publishers_v2"] as? [[String: Any]])?.first?["type"] as? String, "English")
    }

    func testMangaBakaV2RefreshReasonClearsAfterApply() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ai no Kusabi (1986) {mb-82805}"
        try writeFile("\(folder)/ComicInfo.json", contents: """
        {
          "title": "Ai no Kusabi",
          "preferred_title": "Ai no Kusabi",
          "local_title": "Ai no Kusabi",
          "type": "novel",
          "year": 1986,
          "ids": {
            "mangabaka": "82805"
          },
          "source": "mangabaka",
          "last_checked": "2999-01-01T00:00:00Z",
          "source_freshness": [
            {
              "provider": "mangabaka",
              "fetched_at": "2999-01-01T00:00:00Z",
              "ttl_seconds": 604800
            }
          ],
          "_sable": {
            "mangabaka": {
              "matched_id": "82805",
              "matched_title": "Ai no Kusabi"
            }
          }
        }
        """, root: root)
        try writeFile("\(folder)/Ai No Kusabi (1986) - Vol 01.epub", contents: "book", root: root)

        let response = """
        {
          "status": 200,
          "data": {
            "id": 82805,
            "title": "Ai no Kusabi",
            "native_title": "間の楔",
            "romanized_title": "Ai no Kusabi",
            "type": "novel",
            "year": 1986,
            "authors": ["Rieko Yoshihara"],
            "links": ["https://en.wikipedia.org/wiki/Ai_no_Kusabi", "https://mangabaka.org/82805"],
            "links_v2": [
              { "id": "link-1", "url": "https://mangabaka.org/82805", "name": "mangabaka.org", "name_display": "MangaBaka", "type": "info", "language": "en" }
            ],
            "tags_v2": [
              { "id": 1, "name": "Sci-Fi", "name_path": "Settings > Sci-Fi", "is_genre": true, "is_spoiler": false, "is_explicit": true, "content_rating": "safe", "weight": "defining" },
              { "id": 270, "name": "Space", "name_path": "Locations > Space", "is_genre": false, "is_spoiler": false, "is_explicit": true, "content_rating": "safe", "weight": "defining" }
            ],
            "titles": [
              { "language": "ja-Latn", "traits": ["native"], "title": "Ai no Kusabi", "is_primary": true },
              { "language": "en", "traits": ["official"], "title": "Ai no Kusabi", "is_primary": true },
              { "language": "pt-br", "traits": [], "title": "Ai no Kusabi - O Espaço Entre", "is_primary": true },
              { "language": "ja", "traits": ["native"], "title": "間の楔", "is_primary": true }
            ]
          }
        }
        """.data(using: .utf8)!
        let url = try XCTUnwrap(URL(string: "https://api.mangabaka.org/v1/series/82805"))
        await SableLibraryProviderResponseCache.shared.store(
            response,
            for: SableLibraryProviderResponseCache.key(provider: .mangabaka, url: url),
            ttl: 604_800
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let firstRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let refreshItem = try XCTUnwrap(firstRun.context.plan.items.first { item in
            item.operation == .refreshComicInfo
                && item.reviewTags.contains("metadata-mangabaka-v2-refresh")
        })
        XCTAssertTrue(refreshItem.reason.contains("newer title, tag, and link evidence"), refreshItem.reason)

        let result = await coordinator.applyChecked(planByChecking(refreshItem.id, in: firstRun.context.plan), stage: .comicInfo)
        XCTAssertEqual(result.appliedCount, 1)

        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        let mangaBaka = try XCTUnwrap(sable["mangabaka"] as? [String: Any])
        XCTAssertNotNil(mangaBaka["titles_v2"])
        XCTAssertNotNil(mangaBaka["tags_v2"])
        XCTAssertNotNil(mangaBaka["links_v2"])

        let secondRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        XCTAssertFalse(secondRun.context.plan.items.contains { item in
            item.operation == .refreshComicInfo
                && item.reviewTags.contains("metadata-mangabaka-v2-refresh")
        })
    }

    func testExactIDBatchRefreshUsesSavedMangaBakaID() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ai no Kusabi (1986) {mb-82805}"
        try writeFile("\(folder)/ComicInfo.json", contents: """
        {
          "title": "Ai no Kusabi",
          "preferred_title": "Ai no Kusabi",
          "local_title": "Ai no Kusabi",
          "type": "novel",
          "year": 1986,
          "ids": {
            "mangabaka": "82805"
          },
          "source": "mangabaka",
          "last_checked": "2999-01-01T00:00:00Z",
          "source_freshness": [
            {
              "provider": "mangabaka",
              "fetched_at": "2999-01-01T00:00:00Z",
              "ttl_seconds": 604800
            }
          ],
          "_sable": {
            "mangabaka": {
              "matched_id": "82805",
              "matched_title": "Ai no Kusabi"
            }
          }
        }
        """, root: root)
        try writeFile("\(folder)/Ai No Kusabi (1986) - Vol 01.epub", contents: "book", root: root)

        let response = """
        {
          "status": 200,
          "data": {
            "id": 82805,
            "title": "Ai no Kusabi",
            "native_title": "間の楔",
            "romanized_title": "Ai no Kusabi",
            "type": "novel",
            "year": 1986,
            "authors": ["Rieko Yoshihara"],
            "links": ["https://mangabaka.org/82805"],
            "links_v2": [
              { "id": "link-1", "url": "https://mangabaka.org/82805", "name": "mangabaka.org", "name_display": "MangaBaka", "type": "info", "language": "en" }
            ],
            "tags_v2": [
              { "id": 1, "name": "Sci-Fi", "name_path": "Settings > Sci-Fi", "is_genre": true, "is_spoiler": false, "is_explicit": true, "content_rating": "safe", "weight": "defining" }
            ],
            "titles": [
              { "language": "ja-Latn", "traits": ["native"], "title": "Ai no Kusabi", "is_primary": true },
              { "language": "en", "traits": ["official"], "title": "Ai no Kusabi", "is_primary": true },
              { "language": "pt-br", "traits": [], "title": "Ai no Kusabi - O Espaço Entre", "is_primary": true },
              { "language": "ja", "traits": ["native"], "title": "間の楔", "is_primary": true }
            ]
          }
        }
        """.data(using: .utf8)!
        let url = try XCTUnwrap(URL(string: "https://api.mangabaka.org/v1/series/82805"))
        await SableLibraryProviderResponseCache.shared.store(
            response,
            for: SableLibraryProviderResponseCache.key(provider: .mangabaka, url: url),
            ttl: 604_800
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let firstRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let refreshItem = try XCTUnwrap(firstRun.context.plan.items.first { item in
            item.operation == .refreshComicInfo
                && item.reviewTags.contains("metadata-mangabaka-v2-refresh")
        })
        XCTAssertTrue(refreshItem.isExactIDBatchRefreshCandidate)

        let result = await coordinator.applyExactIDBatch(
            firstRun.context.plan,
            stage: .comicInfo,
            itemIDs: Set([refreshItem.id]),
            options: options
        )
        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertTrue(result.summary.contains("exact-ID metadata refresh"), result.summary)

        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        let mangaBaka = try XCTUnwrap(sable["mangabaka"] as? [String: Any])
        XCTAssertNotNil(mangaBaka["titles_v2"])
        XCTAssertNotNil(mangaBaka["tags_v2"])
        XCTAssertNotNil(mangaBaka["links_v2"])

        let secondRun = await coordinator.inspectAndBuildPlan(root: root, options: options)
        XCTAssertFalse(secondRun.context.plan.items.contains { item in
            item.operation == .refreshComicInfo
                && item.reviewTags.contains("metadata-mangabaka-v2-refresh")
        })
    }

    func testRanobeDBRefreshAddsOnlyMissingBookDetailsAndPreservesExistingVolumes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Delta Series (2020) {rdb-90001}"
        try writeFile("\(folder)/ComicInfo.json", contents: """
        {
          "title": "Delta Series",
          "preferred_title": "Delta Series",
          "local_title": "Delta Series",
          "type": "lightNovel",
          "ids": { "ranobedb": "90001" },
          "source": "ranobedb",
          "volumes": [
            {
              "number": 1,
              "title": "Delta Series, Vol. 1",
              "file_suffix": "Vol 01",
              "source_id": { "provider": "ranobedb", "value": "book-1" },
              "isbn13": ["9780000000001"],
              "pages": 301
            },
            {
              "number": 2,
              "title": "Delta Series, Vol. 2",
              "file_suffix": "Vol 02",
              "source_id": { "provider": "ranobedb", "value": "book-2" },
              "description": "Saved volume two detail."
            }
          ],
          "_sable": {
            "ranobedb": {
              "series_id": "90001",
              "book_detail": {
                "known_book_ids": ["book-1", "book-2"],
                "detailed_book_ids": ["book-1", "book-2"]
              }
            }
          }
        }
        """, root: root)
        try writeFile("\(folder)/Delta Series - Vol 03.epub", contents: "book", root: root)

        let seriesResponse = """
        {
          "series": {
            "id": "90001",
            "title": "Delta Series",
            "lang": "en",
            "olang": "ja",
            "publication_status": "ongoing",
            "books": [
              { "id": "book-1", "title": "Delta Series, Vol. 1", "sort_order": 1, "book_type": "main" },
              { "id": "book-2", "title": "Delta Series, Vol. 2", "sort_order": 2, "book_type": "main" },
              { "id": "book-3", "title": "Delta Series, Vol. 3: New Arrival", "sort_order": 3, "book_type": "main" }
            ]
          }
        }
        """.data(using: .utf8)!
        let bookResponse = """
        {
          "book": {
            "id": "book-3",
            "title": "Delta Series, Vol. 3: New Arrival",
            "sort_order": 3,
            "description": "Fresh volume three detail.",
            "releases": [
              { "id": "release-3", "lang": "en", "release_date": 20260701, "pages": 333 }
            ]
          }
        }
        """.data(using: .utf8)!
        let seriesURL = try XCTUnwrap(URL(string: "https://ranobedb.org/api/v0/series/90001"))
        let bookURL = try XCTUnwrap(URL(string: "https://ranobedb.org/api/v0/book/book-3"))
        await SableLibraryProviderResponseCache.shared.store(
            seriesResponse,
            for: SableLibraryProviderResponseCache.key(provider: .ranobedb, url: seriesURL),
            ttl: 600
        )
        await SableLibraryProviderResponseCache.shared.store(
            bookResponse,
            for: SableLibraryProviderResponseCache.key(provider: .ranobedb, url: bookURL),
            ttl: 600
        )

        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        let refreshItem = try XCTUnwrap(run.context.plan.items.first { item in
            item.currentPath == folder
                && item.reviewTags.contains("metadata-ranobedb-book-detail-refresh")
        })

        let result = await coordinator.applyExactIDBatch(
            run.context.plan,
            stage: .comicInfo,
            itemIDs: [refreshItem.id],
            options: options
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)
        let comicInfo = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let volumes = try XCTUnwrap(comicInfo["volumes"] as? [[String: Any]])
        XCTAssertEqual(volumes.count, 3)
        XCTAssertEqual(volumes.first?["isbn13"] as? [String], ["9780000000001"])
        XCTAssertEqual(volumes.first?["pages"] as? Int, 301)
        XCTAssertEqual(volumes[1]["description"] as? String, "Saved volume two detail.")
        XCTAssertEqual(volumes[2]["description"] as? String, "Fresh volume three detail.")
        XCTAssertEqual(volumes[2]["pages"] as? Int, 333)

        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        let ranobeDB = try XCTUnwrap(sable["ranobedb"] as? [String: Any])
        let bookDetail = try XCTUnwrap(ranobeDB["book_detail"] as? [String: Any])
        XCTAssertEqual(bookDetail["new_release_book_ids"] as? [String], ["book-3"])
        XCTAssertEqual(bookDetail["requested_book_detail_ids"] as? [String], ["book-3"])
        XCTAssertEqual(bookDetail["newly_fetched_book_ids"] as? [String], ["book-3"])
        XCTAssertEqual(Set(bookDetail["detailed_book_ids"] as? [String] ?? []), ["book-1", "book-2", "book-3"])
    }

    func testExactIDBatchLeavesNoIDRefreshRowsOut() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Quiet Shelf/ComicInfo.json",
            contents: #"{"title":"Quiet Shelf","last_checked":"2024-01-01T00:00:00Z","source":"local"}"#,
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let refreshItem = try XCTUnwrap(run.context.plan.items.first { $0.operation == .refreshComicInfo })
        XCTAssertFalse(refreshItem.isExactIDBatchRefreshCandidate)

        let result = await coordinator.applyExactIDBatch(
            run.context.plan,
            stage: .comicInfo,
            itemIDs: Set([refreshItem.id]),
            options: options
        )

        XCTAssertEqual(result.appliedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(result.summary.contains("No exact-ID metadata refresh rows were ready"), result.summary)
    }

    func testWatchingRefreshRowsWithSavedIDsCanUseExactIDBatch() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Frieren/AnimeInfo.json",
            contents: """
            {
              "title": "Frieren: Beyond Journey's End",
              "preferred_title": "Frieren: Beyond Journey's End",
              "type": "animeTV",
              "ids": {
                "anilist": "154587"
              },
              "source": "anilist",
              "last_checked": "2024-01-01T00:00:00Z"
            }
            """,
            root: root
        )
        try writeFile("TV/Frieren/Frieren - S01E01.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let refreshItem = try XCTUnwrap(run.context.plan.items.first { $0.operation == .refreshAnimeInfo })

        XCTAssertTrue(refreshItem.isExactIDBatchRefreshCandidate)
        XCTAssertTrue(refreshItem.manualSourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "154587")))
    }

    func testLegacySubtitlesMigrateToVolumeTitlesDuringComicInfoRefresh() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Manga/Quiet Hero/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Hero",
              "preferred_title": "Quiet Hero",
              "type": "manga",
              "last_checked": "2024-01-01T00:00:00Z",
              "source": "local",
              "subtitles": [
                "Vol 01 - First Light",
                "Vol 02 - Second Flame"
              ]
            }
            """,
            root: root
        )
        try writeFile("Manga/Quiet Hero/Quiet Hero - Vol 01.cbz", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(
            run.context.plan.items.first {
                $0.operation == .refreshComicInfo
                    && $0.currentPath == "Manga/Quiet Hero"
            }
        )
        XCTAssertTrue(item.isApplyableComicInfoOperation)

        let result = await coordinator.applyChecked(planByChecking(item.id, in: run.context.plan), stage: .comicInfo)
        let comicInfo = try jsonObject("Manga/Quiet Hero/ComicInfo.json", root: root)
        let volumeTitles = comicInfo["volume_titles"] as? [String]
        let episodeTitles = comicInfo["episode_titles"] as? [String]

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertNil(comicInfo["subtitles"])
        XCTAssertEqual(volumeTitles, ["Vol 01 - First Light", "Vol 02 - Second Flame"])
        XCTAssertNil(episodeTitles)
    }

    func testComicInfoRefreshCompactsProviderMissesAndAliasDumpedVolumeTitles() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Quiet Hero/ComicInfo.json",
            contents: """
            {
              "_sable": {
                "ml": {
                  "training_ready": false
                },
                "book_snapshot": {
                  "version": 1,
                  "file_count": 1
                }
              },
              "title": "Quiet Hero",
              "preferred_title": "Quiet Hero",
              "local_title": "Quiet Hero",
              "type": "lightNovel",
              "source": "local",
              "last_checked": "2024-01-01T00:00:00Z",
              "aliases": [
                "Quiet Hero",
                "Quiet Hero Alt"
              ],
              "volume_titles": [
                "Quiet Hero",
                "Quiet Hero Alt",
                "Vol 01 - First Light"
              ]
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Quiet Hero/Quiet Hero - Vol 01.cbz", contents: "book", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.refreshComicInfo = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(
            run.context.plan.items.first {
                $0.operation == .refreshComicInfo
                    && $0.currentPath == "Light Novels/Quiet Hero"
                    && $0.reviewTags.contains("metadata-comicinfo-cleaner")
            }
        )
        XCTAssertTrue(item.isApplyableComicInfoOperation)

        let result = await coordinator.applyChecked(planByChecking(item.id, in: run.context.plan), stage: .comicInfo)
        let comicInfo = try jsonObject("Light Novels/Quiet Hero/ComicInfo.json", root: root)
        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(comicInfo["aliases"] as? [String], ["Quiet Hero Alt"])
        XCTAssertEqual(comicInfo["volume_titles"] as? [String], ["Vol 01 - First Light"])
        XCTAssertNil(sable["ml"])
        XCTAssertNotNil(sable["book_snapshot"])
    }

    func testComicInfoCreatePreservesFolderYearAndSeriesReadingTargets() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Manga/Quiet Hero (2018) {mb-1238}/Quiet Hero - Vol 01.cbz",
            contents: "book",
            root: root
        )
        let service = SableLibraryService()
        XCTAssertEqual(service.volumeOrChapterSuffix(in: "The Saga of Tanya the Evil Vol. 1 - Deus lo Vult"), "Vol 01 - Deus lo Vult")
        XCTAssertEqual(service.volumeOrChapterSuffix(in: "Quiet Hero - Ch 01-05"), "Ch 0001-0005")
        XCTAssertEqual(service.volumeOrChapterSuffix(in: "Quiet Hero - Chapter 7: A Calm Morning"), "Ch 0007 - A Calm Morning")
        XCTAssertEqual(service.volumeNumber(in: "Vol 01 - Deus lo Vult"), 1)

        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .createComicInfo })

        XCTAssertEqual(item.currentPath, "Manga/Quiet Hero (2018) {mb-1238}")
        XCTAssertTrue(item.isApplyableComicInfoOperation)

        let result = await coordinator.applyChecked(run.context.plan, stage: .comicInfo)
        let comicInfo = try jsonObject("Manga/Quiet Hero (2018) {mb-1238}/ComicInfo.json", root: root)
        let ids = try XCTUnwrap(comicInfo["ids"] as? [String: Any])
        let plex = try XCTUnwrap(comicInfo["plex"] as? [String: Any])
        let targets = try XCTUnwrap(plex["organizer_targets"] as? [String: Any])
        let sable = try XCTUnwrap(comicInfo["_sable"] as? [String: Any])
        let source = try XCTUnwrap(sable["organizer_source"] as? [String: Any])
        let snapshot = try XCTUnwrap(sable["book_snapshot"] as? [String: Any])

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(comicInfo["preferred_title"] as? String, "Quiet Hero")
        XCTAssertEqual(comicInfo["year"] as? Int, 2018)
        XCTAssertEqual(ids["mangabaka"] as? String, "1238")
        XCTAssertEqual(plex["title_with_year"] as? String, "Quiet Hero (2018)")
        XCTAssertEqual(plex["series_path"] as? String, "Manga/Quiet Hero (2018) {mb-1238}")
        XCTAssertEqual(targets["volume_file"] as? String, "Manga/Quiet Hero (2018) {mb-1238}/Quiet Hero (2018) - Vol 01.ext")
        XCTAssertEqual(targets["chapter_file"] as? String, "Manga/Quiet Hero (2018) {mb-1238}/Quiet Hero (2018) - Ch 0001.ext")
        XCTAssertEqual(targets["volume_title_file"] as? String, "Manga/Quiet Hero (2018) {mb-1238}/Quiet Hero (2018) - Vol 01 - Volume Title.ext")
        XCTAssertEqual(targets["chapter_range_file"] as? String, "Manga/Quiet Hero (2018) {mb-1238}/Quiet Hero (2018) - Ch 0001-0005.ext")
        XCTAssertNil(targets["volume_file_in_volume_folder"])
        XCTAssertNil(targets["chapter_file_in_chapters_folder"])
        XCTAssertEqual(source["folder_name"] as? String, "Quiet Hero (2018) {mb-1238}")
        XCTAssertEqual(source["year"] as? Int, 2018)
        XCTAssertEqual(source["year_preserved"] as? Bool, true)
        XCTAssertEqual(snapshot["file_count"] as? Int, 1)
        XCTAssertNil(snapshot["files"])
    }

    func testProviderBackedComicInfoCreateSkipsWithoutTrustedProviderIdentity() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Crowded Title/Volume 1.cbz", contents: "book", root: root)

        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .createComicInfo,
            currentPath: "Crowded Title",
            proposedPath: "Crowded Title/ComicInfo.json",
            reason: "Try provider-backed ComicInfo creation.",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [.ranobedb]
        )
        let plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Create ComicInfo with RanobeDB",
                    summary: "Test provider create",
                    items: [item]
                )
            ]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(plan: plan, service: SableLibraryService())

        XCTAssertEqual(result.appliedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertFalse(fileExists("Crowded Title/ComicInfo.json", root: root))
        XCTAssertTrue(result.summary.contains("Skipped without writing ComicInfo.json"), result.summary)
    }

    func testMissingLightNovelComicInfoRowsCarryIdentityPassMLTags() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Light Novels/Unclear Reading Thing/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .createComicInfo })

        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.currentPath, "Light Novels/Unclear Reading Thing")
        XCTAssertTrue(item.reviewTags.contains("metadata-pass-identity"))
        XCTAssertTrue(item.reviewTags.contains("metadata-checkpoint-identity"))
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-identity-mangabaka"))
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-ranobedb-series"))
        XCTAssertFalse(item.reviewTags.contains("metadata-provider-ranobedb-books"))
    }

    func testUnclearComicInfoRowsUseMetadataChoiceCheckpoint() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Mystery Shelf/Dracula.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        XCTAssertTrue(run.context.plan.groups.allSatisfy { $0.stage == .comicInfo })
        let choiceGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Choose Metadata Matches" })
        let item = try XCTUnwrap(choiceGroup.items.first { $0.operation == .createComicInfo })

        XCTAssertEqual(item.currentPath, "Mystery Shelf")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.requiresReview)
        XCTAssertTrue(item.reviewTags.contains("metadata-checkpoint-choice"))
        XCTAssertTrue(item.reviewTags.contains("needs-provider-choice"))
        XCTAssertFalse(
            run.context.plan.groups
                .filter { $0.title.contains("Identity Pass") }
                .flatMap(\.items)
                .contains { $0.currentPath == "Mystery Shelf" }
        )
    }

    func testStrongSpecialistProviderCandidateIsCheckedForApply() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/If the Villainess and Villain Met and Fell in Love (2021) {mb-82822}/ComicInfo.json",
            contents: """
            {
              "title": "If the Villainess and Villain Met and Fell in Love",
              "preferred_title": "If the Villainess and Villain Met and Fell in Love",
              "type": "Novel",
              "source": "mangabaka",
              "ids": {
                "mangabaka": "82822"
              },
              "_sable": {
                "provider_candidate_review": {
                  "ranobedb": {
                    "status": "candidate",
                    "provider": "ranobedb",
                    "source": "provider_gap_precheck",
                    "query": "If the Villainess and Villain Met and Fell in Love",
                    "confidence_score": 0.93,
                    "confidence_percent": 93,
                    "candidate_id": "12906",
                    "candidate_title": "If the Villainess and Villain Met and Fell in Love",
                    "candidate_media_type": "lightNovel",
                    "candidate_year": 2021,
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile(
            "Light Novels/If the Villainess and Villain Met and Fell in Love (2021) {mb-82822}/Volume 1.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Missing Providers - RanobeDB" })
        let item = try XCTUnwrap(group.items.first { $0.currentPath.contains("Villainess and Villain") })

        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.confidence, .high)
        XCTAssertEqual(item.manualRanobeDBID, "12906")
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-confident-candidate"))
        XCTAssertTrue(item.confidenceExplanation.contains("93% specialist match"))
    }

    func testWeakerSpecialistProviderCandidateStillNeedsExplicitCheck() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Arifureta Short Stories (2019) {mb-101023}/ComicInfo.json",
            contents: """
            {
              "title": "Arifureta Short Stories",
              "preferred_title": "Arifureta Short Stories",
              "type": "Novel",
              "source": "mangabaka",
              "ids": {
                "mangabaka": "101023"
              },
              "_sable": {
                "provider_candidate_review": {
                  "ranobedb": {
                    "status": "candidate",
                    "provider": "ranobedb",
                    "source": "provider_gap_precheck",
                    "query": "Arifureta Short Stories",
                    "confidence_score": 0.79,
                    "confidence_percent": 79,
                    "candidate_id": "4602",
                    "candidate_title": "Arifureta: From Commonplace to World's Strongest",
                    "candidate_media_type": "lightNovel",
                    "candidate_year": 2015,
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Arifureta Short Stories (2019) {mb-101023}/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Missing Providers - RanobeDB" })
        let item = try XCTUnwrap(group.items.first { $0.currentPath.contains("Arifureta") })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.confidence, .medium)
        XCTAssertEqual(item.manualRanobeDBID, "4602")
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-needs-confirmation"))
    }

    func testKnownMissingProviderRowsAreVisibleButNotApplyableUntilOverridden() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Quiet Missing (2021) {mb-123}/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Missing",
              "preferred_title": "Quiet Missing",
              "type": "Novel",
              "source": "mangabaka",
              "ids": {
                "mangabaka": "123"
              },
              "_sable": {
                "provider_availability": {
                  "ranobedb": {
                    "status": "not_available",
                    "provider": "ranobedb",
                    "source": "manual_no_id",
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Quiet Missing (2021) {mb-123}/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        XCTAssertNil(run.context.plan.groups.first { $0.title == "Missing Providers - RanobeDB" })

        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Saved No ID - RanobeDB" })
        let item = try XCTUnwrap(group.items.first { $0.currentPath.contains("Quiet Missing") })

        XCTAssertEqual(item.stage, .providerMatches)
        XCTAssertEqual(item.operation, .refreshComicInfo)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertFalse(item.requiresReview)
        XCTAssertFalse(item.isApplyableOperation)
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-known-missing"))
        XCTAssertTrue(group.summary.contains("search again"))
        XCTAssertTrue(group.reviewPrompt.contains("Find Match"))
        XCTAssertTrue(item.reason.contains("saved as No ID"))
        XCTAssertTrue(item.confidenceExplanation.contains("stays out of apply"))
    }

    func testKnownMissingMangaBakaAndOpenLibraryRowsStayVisible() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Quiet Missing MangaBaka (2021) {rdb-123}/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Missing MangaBaka",
              "preferred_title": "Quiet Missing MangaBaka",
              "type": "Novel",
              "source": "ranobedb",
              "ids": {
                "ranobedb": "123"
              },
              "_sable": {
                "provider_availability": {
                  "mangabaka": {
                    "status": "not_available",
                    "provider": "mangabaka",
                    "source": "manual_no_id",
                    "updated_at": "2026-06-16T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Quiet Missing MangaBaka (2021) {rdb-123}/Volume 1.epub", contents: "book", root: root)

        try writeFile(
            "Manga/Quiet Missing Open Library (2022) {mb-456}/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Missing Open Library",
              "preferred_title": "Quiet Missing Open Library",
              "type": "Manga",
              "source": "mangabaka",
              "ids": {
                "mangabaka": "456"
              },
              "_sable": {
                "provider_availability": {
                  "openLibrary": {
                    "status": "not_available",
                    "provider": "openLibrary",
                    "source": "manual_no_id",
                    "updated_at": "2026-06-16T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Manga/Quiet Missing Open Library (2022) {mb-456}/Volume 1.cbz", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)

        let mangaBakaGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Saved No ID - MangaBaka" })
        XCTAssertTrue(mangaBakaGroup.items.contains { $0.currentPath.contains("Quiet Missing MangaBaka") })

        let openLibraryGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Saved No ID - Open Library" })
        XCTAssertTrue(openLibraryGroup.items.contains { $0.currentPath.contains("Quiet Missing Open Library") })
    }

    func testKnownMissingWatchingProviderRowsStayVisible() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Movies/Quiet Movie (2020)/AnimeInfo.json",
            contents: """
            {
              "title": "Quiet Movie",
              "preferred_title": "Quiet Movie",
              "type": "movie",
              "year": 2020,
              "source": "local",
              "_sable": {
                "provider_availability": {
                  "wikidata": {
                    "status": "not_available",
                    "provider": "wikidata",
                    "source": "manual_no_id",
                    "updated_at": "2026-06-16T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Movies/Quiet Movie (2020)/Quiet Movie (2020).mp4", contents: "movie", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)

        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Saved No ID Watching - Wikidata" })
        let item = try XCTUnwrap(group.items.first { $0.currentPath.contains("Quiet Movie") })

        XCTAssertEqual(item.operation, .refreshAnimeInfo)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertFalse(item.isApplyableOperation)
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-known-missing"))
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-watching-gap"))
        XCTAssertTrue(group.summary.contains("search again"))
        XCTAssertTrue(group.reviewPrompt.contains("Find Match"))
        XCTAssertTrue(item.reason.contains("saved as No ID"))
    }

    func testMatchedWatchingProviderRowsStayVisibleAlongsideKnownMissingProviders() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Quiet Anime (2021)/AnimeInfo.json",
            contents: """
            {
              "title": "Quiet Anime",
              "preferred_title": "Quiet Anime",
              "type": "animeTV",
              "year": 2021,
              "source": "anilist",
              "ids": {
                "anilist": "101",
                "mal": "202"
              },
              "_sable": {
                "provider_availability": {
                  "tvmaze": {
                    "status": "not_available",
                    "provider": "tvmaze",
                    "source": "manual_no_id",
                    "updated_at": "2026-06-16T12:00:00Z"
                  },
                  "wikidata": {
                    "status": "not_available",
                    "provider": "wikidata",
                    "source": "manual_no_id",
                    "updated_at": "2026-06-16T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("TV/Quiet Anime (2021)/Quiet Anime - S01E01.mp4", contents: "episode", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)

        let aniListGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Matched Watching Providers - AniList" })
        let aniListItem = try XCTUnwrap(aniListGroup.items.first { $0.currentPath.contains("Quiet Anime") })
        XCTAssertEqual(aniListItem.operation, .refreshAnimeInfo)
        XCTAssertEqual(aniListItem.safety, .inspectOnly)
        XCTAssertFalse(aniListItem.isApplyableOperation)
        XCTAssertTrue(aniListItem.reviewTags.contains("metadata-provider-already-matched"))
        XCTAssertTrue(aniListItem.manualSourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "101")))

        let malGroup = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Matched Watching Providers - MyAnimeList" })
        let malItem = try XCTUnwrap(malGroup.items.first { $0.currentPath.contains("Quiet Anime") })
        XCTAssertFalse(malItem.isApplyableOperation)
        XCTAssertTrue(malItem.manualSourceIDs.contains(SableLibrarySourceID(provider: .myAnimeList, value: "202")))

        XCTAssertNil(run.context.plan.groups.first { $0.title == "Missing Watching Providers - AniList" })
        XCTAssertNotNil(run.context.plan.groups.first { $0.title == "Saved No ID Watching - TVmaze" })
        XCTAssertNotNil(run.context.plan.groups.first { $0.title == "Saved No ID Watching - Wikidata" })
    }

    func testWatchingAniListPrecheckRowsAreCheckedForApply() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Quiet Anime (2021)/AnimeInfo.json",
            contents: """
            {
              "title": "Quiet Anime",
              "preferred_title": "Quiet Anime",
              "type": "animeTV",
              "year": 2021,
              "source": "local"
            }
            """,
            root: root
        )
        try writeFile("TV/Quiet Anime (2021)/Quiet Anime - S01E01.mp4", contents: "episode", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Missing Watching Providers - AniList" })
        let item = try XCTUnwrap(group.items.first { $0.currentPath.contains("Quiet Anime") })

        XCTAssertEqual(item.operation, .refreshAnimeInfo)
        XCTAssertEqual(item.metadataProviders, [.anilist])
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.isApplyableComicInfoOperation)
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-precheck"))
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-watching-gap"))
        XCTAssertTrue(item.confidenceExplanation.contains("will not save an ID"))
    }

    func testStrongWatchingProviderCandidateIsCheckedForApply() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Quiet Anime (2021)/AnimeInfo.json",
            contents: """
            {
              "title": "Quiet Anime",
              "preferred_title": "Quiet Anime",
              "type": "animeTV",
              "year": 2021,
              "source": "local",
              "_sable": {
                "provider_candidate_review": {
                  "anilist": {
                    "status": "candidate",
                    "provider": "anilist",
                    "source": "provider_gap_precheck",
                    "query": "Quiet Anime",
                    "confidence_score": 0.96,
                    "confidence_percent": 96,
                    "candidate_id": "101",
                    "candidate_title": "Quiet Anime",
                    "candidate_media_type": "ANIME",
                    "candidate_year": 2021,
                    "schema_version": 4,
                    "updated_at": "2026-06-16T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("TV/Quiet Anime (2021)/Quiet Anime - S01E01.mp4", contents: "episode", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Missing Watching Providers - AniList" })
        let item = try XCTUnwrap(group.items.first { $0.currentPath.contains("Quiet Anime") })

        XCTAssertEqual(item.operation, .refreshAnimeInfo)
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.manualSourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "101")))
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-confident-candidate"))
        XCTAssertTrue(item.reviewTags.contains("metadata-provider-watching-gap"))
    }

    func testStrongMangaBakaAndAniListCandidatesAreCheckedForApply() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Manga/Quiet Hero/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Hero",
              "preferred_title": "Quiet Hero",
              "type": "manga",
              "source": "local",
              "_sable": {
                "provider_candidate_review": {
                  "mangabaka": {
                    "status": "candidate",
                    "provider": "mangabaka",
                    "source": "provider_gap_precheck",
                    "query": "Quiet Hero",
                    "confidence_score": 0.96,
                    "confidence_percent": 96,
                    "candidate_id": "1238",
                    "candidate_title": "Quiet Hero",
                    "candidate_media_type": "manga",
                    "candidate_year": 2018,
                    "updated_at": "2026-06-15T12:00:00Z"
                  },
                  "anilist": {
                    "status": "candidate",
                    "provider": "anilist",
                    "source": "provider_gap_precheck",
                    "query": "Quiet Hero",
                    "confidence_score": 0.95,
                    "confidence_percent": 95,
                    "candidate_id": "77123",
                    "candidate_title": "Quiet Hero",
                    "candidate_media_type": "manga",
                    "candidate_year": 2018,
                    "schema_version": 4,
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Manga/Quiet Hero/Quiet Hero Vol 01.cbz", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let mangaBakaItem = try XCTUnwrap(
            run.context.plan.groups
                .first { $0.title == "Missing Providers - MangaBaka" }?
                .items
                .first { $0.currentPath == "Manga/Quiet Hero" }
        )
        let aniListItem = try XCTUnwrap(
            run.context.plan.groups
                .first { $0.title == "Missing Providers - AniList" }?
                .items
                .first { $0.currentPath == "Manga/Quiet Hero" }
        )
        XCTAssertEqual(mangaBakaItem.decision, .checked)
        XCTAssertEqual(mangaBakaItem.confidence, .high)
        XCTAssertEqual(mangaBakaItem.manualMangaBakaID, "1238")
        XCTAssertEqual(aniListItem.decision, .checked)
        XCTAssertEqual(aniListItem.confidence, .high)
        XCTAssertTrue(aniListItem.manualSourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "77123")))
        XCTAssertNil(run.context.plan.groups.first { $0.title == "Missing Providers - MyAnimeList" })
    }

    func testLightNovelAniListNovelCandidateIsCheckedForApply() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Maiden of the Needle (2019) {mb-83630} {rdb-9334}/ComicInfo.json",
            contents: """
            {
              "title": "Maiden of the Needle",
              "preferred_title": "Maiden of the Needle",
              "type": "Novel",
              "source": "mangabaka",
              "ids": {
                "mangabaka": "83630",
                "ranobedb": "9334"
              },
              "_sable": {
                "provider_candidate_review": {
                  "anilist": {
                    "status": "candidate",
                    "provider": "anilist",
                    "source": "provider_gap_precheck",
                    "query": "Maiden of the Needle",
                    "confidence_score": 0.99,
                    "confidence_percent": 99,
                    "candidate_id": "121394",
                    "candidate_title": "Maiden of the Needle",
                    "candidate_media_type": "NOVEL",
                    "candidate_year": 2019,
                    "schema_version": 4,
                    "updated_at": "2026-06-16T04:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Maiden of the Needle (2019) {mb-83630} {rdb-9334}/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let aniListItem = try XCTUnwrap(
            run.context.plan.groups
                .first { $0.title == "Missing Providers - AniList" }?
                .items
                .first { $0.currentPath.contains("Maiden of the Needle") }
        )

        XCTAssertEqual(aniListItem.decision, .checked)
        XCTAssertEqual(aniListItem.confidence, .high)
        XCTAssertTrue(aniListItem.manualSourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "121394")))
        XCTAssertTrue(aniListItem.reviewTags.contains("metadata-provider-confident-candidate"))
    }

    func testLightNovelAniListMangaCandidateStaysManual() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/False Manga Bridge (2020) {rdb-4444}/ComicInfo.json",
            contents: """
            {
              "title": "False Manga Bridge",
              "preferred_title": "False Manga Bridge",
              "type": "Novel",
              "source": "ranobedb",
              "ids": {
                "ranobedb": "4444"
              },
              "_sable": {
                "provider_candidate_review": {
                  "anilist": {
                    "status": "candidate",
                    "provider": "anilist",
                    "source": "provider_gap_precheck",
                    "query": "False Manga Bridge",
                    "confidence_score": 0.99,
                    "confidence_percent": 99,
                    "candidate_id": "777",
                    "candidate_title": "False Manga Bridge",
                    "candidate_media_type": "MANGA",
                    "candidate_year": 2020,
                    "schema_version": 4,
                    "updated_at": "2026-06-16T04:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/False Manga Bridge (2020) {rdb-4444}/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let aniListItem = try XCTUnwrap(
            run.context.plan.groups
                .first { $0.title == "Missing Providers - AniList" }?
                .items
                .first { $0.currentPath.contains("False Manga Bridge") }
        )

        XCTAssertEqual(aniListItem.decision, .unchecked)
        XCTAssertNotEqual(aniListItem.confidence, .high)
        XCTAssertTrue(aniListItem.manualSourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "777")))
        XCTAssertTrue(aniListItem.reviewTags.contains("metadata-provider-needs-confirmation"))
    }

    func testLegacyMyAnimeListCandidateReviewDoesNotCreateActiveProviderGroup() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Quiet Needle (2019) {rdb-9334}/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Needle",
              "preferred_title": "Quiet Needle",
              "type": "Novel",
              "source": "ranobedb",
              "ids": {
                "ranobedb": "9334"
              },
              "_sable": {
                "provider_candidate_review": {
                  "myAnimeList": {
                    "status": "candidate",
                    "provider": "myAnimeList",
                    "source": "provider_gap_precheck",
                    "query": "Quiet Needle",
                    "confidence_score": 0.96,
                    "confidence_percent": 96,
                    "candidate_id": "123456",
                    "candidate_title": "Quiet Needle",
                    "candidate_media_type": "Light Novel",
                    "candidate_year": 2019,
                    "schema_version": 4,
                    "updated_at": "2026-06-16T08:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Quiet Needle (2019) {rdb-9334}/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        XCTAssertNil(run.context.plan.groups.first { $0.title == "Missing Providers - MyAnimeList" })
    }

    func testLegacyMyAnimeListNoLongerCreatesManualReviewRows() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/False MAL Manga Bridge (2020) {rdb-4444}/ComicInfo.json",
            contents: """
            {
              "title": "False MAL Manga Bridge",
              "preferred_title": "False MAL Manga Bridge",
              "type": "Novel",
              "source": "ranobedb",
              "ids": {
                "ranobedb": "4444"
              },
              "_sable": {
                "provider_candidate_review": {
                  "myAnimeList": {
                    "status": "candidate",
                    "provider": "myAnimeList",
                    "source": "provider_gap_precheck",
                    "query": "False MAL Manga Bridge",
                    "confidence_score": 0.99,
                    "confidence_percent": 99,
                    "candidate_id": "777",
                    "candidate_title": "False MAL Manga Bridge",
                    "candidate_media_type": "Manga",
                    "candidate_year": 2020,
                    "schema_version": 4,
                    "updated_at": "2026-06-16T08:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/False MAL Manga Bridge (2020) {rdb-4444}/Volume 1.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        XCTAssertNil(run.context.plan.groups.first { $0.title == "Missing Providers - MyAnimeList" })
    }

    func testStrongMangaBakaNovelCandidateInLightNovelLaneStaysManual() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Sugar Apple Fairy Tale/ComicInfo.json",
            contents: """
            {
              "title": "Sugar Apple Fairy Tale",
              "preferred_title": "Sugar Apple Fairy Tale",
              "type": "Novel",
              "source": "local",
              "_sable": {
                "provider_candidate_review": {
                  "mangabaka": {
                    "status": "candidate",
                    "provider": "mangabaka",
                    "source": "provider_gap_precheck",
                    "query": "Sugar Apple Fairy Tale",
                    "confidence_score": 0.99,
                    "confidence_percent": 99,
                    "candidate_id": "85341",
                    "candidate_title": "Sugar Apple Fairy Tale: The Silver Sugar Master and the Obsidian Fairy",
                    "candidate_media_type": "Novel",
                    "candidate_year": 2010,
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Sugar Apple Fairy Tale/Sugar Apple Fairy Tale Vol 01.epub", contents: "book", root: root)
        try writeFile("Light Novels/Sugar Apple Fairy Tale/Sugar Apple Fairy Tale Vol 02.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .providerMatches)
        let mangaBakaItem = try XCTUnwrap(
            run.context.plan.groups
                .first { $0.title == "Missing Providers - MangaBaka" }?
                .items
                .first { $0.currentPath == "Light Novels/Sugar Apple Fairy Tale" }
        )

        XCTAssertEqual(mangaBakaItem.decision, .unchecked)
        XCTAssertEqual(mangaBakaItem.confidence, .medium)
        XCTAssertEqual(mangaBakaItem.manualMangaBakaID, "85341")
        XCTAssertTrue(mangaBakaItem.reviewTags.contains("metadata-provider-needs-confirmation"))
    }

    func testFolderSortingFallsBackFromJapanesePreferredTitleToLocalTitle() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/本好きの下剋上ふぁんぶっく (2017) {mb-83709}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "本好きの下剋上ふぁんぶっく",
                localTitle: "Ascendance of a Bookworm Fanbook",
                preferredTitle: "本好きの下剋上ふぁんぶっく",
                mediaType: "lightNovel",
                year: 2017,
                primarySourceID: SableLibrarySourceID(provider: .mangabaka, value: "83709"),
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: nil,
                comicInfoSource: "mangabaka",
                comicInfoLastChecked: "2026-06-15T12:00:00Z",
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(item.currentPath, currentPath)
        XCTAssertEqual(item.proposedPath, "Light Novels/Ascendance of a Bookworm Fanbook (2017) {mb-83709}")
    }

    func testFolderSortingRespectsDisabledSidecarTitles() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Manga/Old Local Name"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Old Local Name",
                localTitle: "Old Local Name",
                preferredTitle: "Preferred Provider Name",
                mediaType: "manga",
                year: nil,
                primarySourceID: nil,
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: nil,
                comicInfoSource: "local",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: nil,
                mangaBakaTypeMatched: nil,
                hasComicInfo: true
            )
        ]

        var stages = LibraryPipelineStageOptions()
        stages.useComicInfoTitles = false
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testFolderSortingKeepsLocalPartMarkerWhenProviderTitleSaysFanbook() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/Ascendance of a Bookworm Fanbook (2017) {mb-100542} {rdb-6581}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Ascendance of a Bookworm Fanbook",
                localTitle: "Ascendance of a Bookworm Part 4",
                preferredTitle: "Ascendance of a Bookworm: Fanbook",
                mediaType: "lightNovel",
                year: 2017,
                primarySourceID: SableLibrarySourceID(provider: .mangabaka, value: "100542"),
                identityGraph: SableLibraryIdentityGraph(
                    domain: .reading,
                    preferredTitle: "Ascendance of a Bookworm: Fanbook",
                    year: 2017,
                    readingType: .lightNovel,
                    sourceIDs: [
                        SableLibrarySourceID(provider: .mangabaka, value: "100542"),
                        SableLibrarySourceID(provider: .ranobedb, value: "6581")
                    ]
                ),
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 9,
                localHighestVolume: 9,
                comicInfoSource: "mangabaka, ranobedb",
                comicInfoLastChecked: "2026-06-15T12:00:00Z",
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(item.currentPath, currentPath)
        XCTAssertEqual(item.proposedPath, "Light Novels/Ascendance of a Bookworm Part 4 (2017) {mb-100542} {rdb-6581}")
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertFalse(item.proposedPath?.contains("Fanbook") ?? true)
        XCTAssertTrue(item.proposedPath?.contains("rdb-6581") ?? false)
        XCTAssertTrue(item.reviewTags.contains("naming-title-change"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingKeepsFullLocalSeriesTitleWhenProviderTitleIsShortAlias() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fullTitle = "Banished from the Hero's Party, I Decided to Live a Quiet Life in the Countryside"
        let currentPath = "Light Novels/\(fullTitle) (2017) {mb-85173} {rdb-8215}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: fullTitle,
                localTitle: "\(fullTitle), Vol. 4 (light Novel)",
                preferredTitle: "Banished from the Hero's Party",
                mediaType: "lightNovel",
                year: 2017,
                primarySourceID: SableLibrarySourceID(provider: .mangabaka, value: "85173"),
                identityGraph: SableLibraryIdentityGraph(
                    domain: .reading,
                    preferredTitle: "Banished from the Hero's Party",
                    year: 2017,
                    readingType: .lightNovel,
                    sourceIDs: [
                        SableLibrarySourceID(provider: .mangabaka, value: "85173"),
                        SableLibrarySourceID(provider: .ranobedb, value: "8215")
                    ]
                ),
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 4,
                localHighestVolume: 4,
                comicInfoSource: "mangabaka, ranobedb",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )

        XCTAssertTrue(groups.flatMap { $0.items }.isEmpty)
    }

    func testFolderSortingPreservesReadingAnimeAndNovelIDsFromFolderName() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Books/Ai no Kusabi (1990) {rdb-1234} {mal-456} {al-789}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Ai no Kusabi",
                localTitle: "Ai no Kusabi",
                preferredTitle: "Ai no Kusabi",
                mediaType: "lightNovel",
                year: 1990,
                primarySourceID: nil,
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: 1,
                comicInfoSource: "local",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: nil,
                mangaBakaTypeMatched: nil,
                hasComicInfo: true
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(item.proposedPath, "Light Novels/Ai no Kusabi (1990) {rdb-1234} {mal-456} {al-789}")
        XCTAssertEqual(item.decision, .checked)
        XCTAssertTrue(item.reviewTags.contains("provider-token-ranobedb"), item.reviewTags.joined(separator: ","))
        XCTAssertTrue(item.reviewTags.contains("provider-token-myanimelist"), item.reviewTags.joined(separator: ","))
        XCTAssertTrue(item.reviewTags.contains("provider-token-anilist"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingDropsProviderTokenRejectedBySidecarReview() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/Observation Records of My Fiancée The Misadventures of a Self-Proclaimed Villainess (2022) {mb-185873} {rdb-6832}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
                localTitle: "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
                preferredTitle: "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
                mediaType: "lightNovel",
                year: 2022,
                primarySourceID: SableLibrarySourceID(provider: .mangabaka, value: "185873"),
                identityGraph: SableLibraryIdentityGraph(
                    domain: .reading,
                    preferredTitle: "Observation Records of My Wife: The Misadventures of a Self-Proclaimed Villainess",
                    year: 2022,
                    readingType: .lightNovel,
                    sourceIDs: [
                        SableLibrarySourceID(provider: .mangabaka, value: "185873"),
                        SableLibrarySourceID(provider: .ranobedb, value: "6832")
                    ]
                ),
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: 1,
                comicInfoSource: "mangabaka",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                providerCandidateReviews: [
                    SableLibraryProviderCandidateReview(
                        provider: .ranobedb,
                        status: .noMatch,
                        confidenceScore: 0,
                        title: "Observation Records of My Fiancée: The Misadventures of a Self-Proclaimed Villainess",
                        year: 2017,
                        mediaType: "lightNovel",
                        sourceID: SableLibrarySourceID(provider: .ranobedb, value: "6832")
                    )
                ],
                hasComicInfo: true
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/Observation Records of My Wife The Misadventures of a Self-Proclaimed Villainess (2022) {mb-185873}"
        )
        XCTAssertFalse(item.proposedPath?.contains("{rdb-6832}") == true)
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reviewTags.contains("naming-provider-token-change"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingDoesNotReattachUnavailableMangaBakaForRanobeOnlySeries() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/Agents Of The Four Seasons (2021) {rdb-12081}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Agents Of The Four Seasons",
                localTitle: "Agents Of The Four Seasons",
                preferredTitle: "Agents Of The Four Seasons",
                mediaType: "lightNovel",
                year: 2021,
                primarySourceID: SableLibrarySourceID(provider: .ranobedb, value: "12081"),
                identityGraph: SableLibraryIdentityGraph(
                    domain: .reading,
                    preferredTitle: "Agents Of The Four Seasons",
                    year: 2021,
                    readingType: .lightNovel,
                    sourceIDs: [
                        SableLibrarySourceID(provider: .mangabaka, value: "85230"),
                        SableLibrarySourceID(provider: .ranobedb, value: "12081"),
                        SableLibrarySourceID(provider: .anilist, value: "131534")
                    ]
                ),
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 6,
                localHighestVolume: 6,
                comicInfoSource: "ranobedb, anilist",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: nil,
                mangaBakaTypeMatched: nil,
                unavailableMetadataProviders: [.mangabaka],
                hasComicInfo: true
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )

        XCTAssertTrue(groups.flatMap { $0.items }.isEmpty)
    }

    func testFolderSortingAutoChecksVerifiedDanMachiProviderAliasUpgrade() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/Dan Machi Familia Chronicle - Novel (2017) {mb-83318} {rdb-6585}"
        let canonicalTitle = "Is It Wrong to Try to Pick Up Girls in a Dungeon? Familia Chronicle"
        try writeFile(
            "\(currentPath)/ComicInfo.json",
            contents: """
            {
              "title": "\(canonicalTitle)",
              "preferred_title": "\(canonicalTitle)",
              "local_title": "Dan Machi Familia Chronicle - Novel",
              "type": "Novel",
              "year": 2017,
              "source": "mangabaka, ranobedb",
              "_sable": {
                "title_source": {
                  "provider": "ranobedb",
                  "priority": 60,
                  "title": "\(canonicalTitle)"
                },
                "mangabaka": {
                  "titles_v2": [
                    { "title": "DanMachi: Familia Chronicle" },
                    { "title": "\(canonicalTitle)" }
                  ]
                },
                "ranobedb": {
                  "api_compact": {
                    "series": {
                      "title": "\(canonicalTitle)",
                      "aliases": ["DanMachi: Orario Stories"]
                    }
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("\(currentPath)/Dan Machi Familia Chronicle - Vol 01.epub", contents: "book", root: root)

        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let inspection = await SableLibraryStep1InspectLibrary().inspect(
            root: root,
            options: options,
            service: SableLibraryService()
        )
        let snapshot = try XCTUnwrap(inspection.series.first { $0.path == currentPath })
        XCTAssertTrue(snapshot.trustedProviderTitles.contains("DanMachi: Familia Chronicle"))
        XCTAssertFalse(snapshot.trustedProviderTitles.contains("Dan Machi Familia Chronicle - Novel"))

        var context = LibraryPipelineContext(root: root, options: options)
        context.inspection = inspection
        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first { $0.currentPath == currentPath })

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/Is It Wrong to Try to Pick Up Girls in a Dungeon- Familia Chronicle (2017) {mb-83318} {rdb-6585}"
        )
        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.reason.contains("saved provider alias"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("naming-provider-alias-upgrade"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingLeavesAiNoKusabiTitleChangesUnchecked() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/Ai no Kusabi (1990) {rdb-1234} {mal-456} {al-789}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Ai no Kusabi",
                localTitle: nil,
                preferredTitle: "Ai no Kusabi The Space Between",
                mediaType: "lightNovel",
                year: 1990,
                primarySourceID: nil,
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: 1,
                comicInfoSource: "ranobedb, mal, anilist",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: nil,
                mangaBakaTypeMatched: nil,
                hasComicInfo: true
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertEqual(item.proposedPath, "Light Novels/Ai no Kusabi The Space Between (1990) {rdb-1234} {mal-456} {al-789}")
        XCTAssertTrue(item.reason.contains("Ai no Kusabi"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("naming-title-change"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingAutoChecksPunctuationOnlyTitleCleanup() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/A Livid Lady’s Guide (2022) {mb-83051} {rdb-13495}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "A Livid Lady’s Guide",
                localTitle: "A Livid Lady’s Guide",
                preferredTitle: "A Livid Lady's Guide",
                mediaType: "lightNovel",
                year: 2022,
                primarySourceID: SableLibrarySourceID(provider: .mangabaka, value: "83051"),
                identityGraph: SableLibraryIdentityGraph(
                    domain: .reading,
                    preferredTitle: "A Livid Lady's Guide",
                    year: 2022,
                    readingType: .lightNovel,
                    sourceIDs: [
                        SableLibrarySourceID(provider: .mangabaka, value: "83051"),
                        SableLibrarySourceID(provider: .ranobedb, value: "13495")
                    ]
                ),
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: 1,
                comicInfoSource: "mangabaka, ranobedb",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: CleanupOptions(),
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(item.decision, .checked)
        XCTAssertEqual(item.safety, .reversible)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.reason.contains("Sable checked it"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("naming-punctuation-only"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingCanAddMainSSSShelfWhenDepthIsShelf() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/ReZERO -Starting Life in Another World (2014) {rdb-3343}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Re:ZERO -Starting Life in Another World-",
                localTitle: "Re:ZERO -Starting Life in Another World-",
                preferredTitle: "Re:ZERO -Starting Life in Another World-",
                mediaType: "lightNovel",
                shelfDescription: "A boy is summoned to another world and survives repeated deaths through a time loop.",
                genres: ["Fantasy", "Psychological"],
                themes: ["Isekai", "Time Loop", "Survival"],
                tags: ["Adapted to Anime"],
                year: 2014,
                primarySourceID: SableLibrarySourceID(provider: .ranobedb, value: "3343"),
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: nil,
                comicInfoSource: "ranobedb",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        var cleanup = CleanupOptions()
        cleanup.readingFolderOrganizationDepth = .shelf
        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: cleanup,
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/21 - Isekai & Other Worlds/ReZERO -Starting Life in Another World (2014) {rdb-3343}"
        )
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.requiresReview)
        XCTAssertTrue(item.reviewTags.contains("sss-folder-depth-shelf"), item.reviewTags.joined(separator: ","))
        XCTAssertTrue(item.reviewTags.contains("sss-21"), item.reviewTags.joined(separator: ","))
        XCTAssertTrue(item.reviewTags.contains("sss-21.7"), item.reviewTags.joined(separator: ","))
    }

    func testFolderSortingCanAddSSSSubShelfWhenDepthIsSubShelf() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/ReZERO -Starting Life in Another World (2014) {rdb-3343}"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Re:ZERO -Starting Life in Another World-",
                localTitle: "Re:ZERO -Starting Life in Another World-",
                preferredTitle: "Re:ZERO -Starting Life in Another World-",
                mediaType: "lightNovel",
                shelfDescription: "A summoned boy returns by death, resets, and fights through psychological horror in another world.",
                genres: ["Fantasy", "Psychological"],
                themes: ["Isekai", "Time Loop", "Survival"],
                tags: ["Based on a Light Novel"],
                year: 2014,
                primarySourceID: SableLibrarySourceID(provider: .ranobedb, value: "3343"),
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: nil,
                comicInfoSource: "ranobedb",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        var cleanup = CleanupOptions()
        cleanup.readingFolderOrganizationDepth = .subShelf
        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: cleanup,
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/21 - Isekai & Other Worlds/21.7 - Survival, Horror & Time Loop Isekai/ReZERO -Starting Life in Another World (2014) {rdb-3343}"
        )
        XCTAssertEqual(item.decision, .checked)
        XCTAssertFalse(item.reviewTags.contains("sss-shelf-review"), item.reviewTags.joined(separator: ","))
        XCTAssertTrue(item.confidenceExplanation.contains("SSS folder depth is Subshelf"))
    }

    func testFolderSortingLeavesWeakSSSSubShelfUncheckedForReview() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPath = "Light Novels/Quiet Untagged - Novel"
        try FileManager.default.createDirectory(
            at: fileURL(currentPath, root: root),
            withIntermediateDirectories: true
        )

        var inspection = LibraryInspection.empty(root: root)
        inspection.series = [
            LibrarySeriesSnapshot(
                id: currentPath,
                path: currentPath,
                displayName: "Quiet Untagged",
                localTitle: "Quiet Untagged",
                preferredTitle: "Quiet Untagged",
                mediaType: "lightNovel",
                year: nil,
                primarySourceID: nil,
                identityGraph: nil,
                sourceFreshness: [],
                finalVolume: nil,
                localBookCount: 1,
                localHighestVolume: nil,
                comicInfoSource: "local",
                comicInfoLastChecked: nil,
                mangaBakaExpectedType: "Novel",
                mangaBakaTypeMatched: true,
                hasComicInfo: true
            )
        ]

        var cleanup = CleanupOptions()
        cleanup.readingFolderOrganizationDepth = .subShelf
        var context = LibraryPipelineContext(
            root: root,
            options: LibraryPipelineOptions(
                cleanup: cleanup,
                stages: LibraryPipelineStageOptions(),
                intelligence: SableLibraryIntelligenceOptions()
            )
        )
        context.inspection = inspection

        let groups = await SableLibraryStep4CanonicalFolders().prepare(
            context: context,
            service: SableLibraryService()
        )
        let item = try XCTUnwrap(groups.flatMap { $0.items }.first)

        XCTAssertEqual(
            item.proposedPath,
            "Light Novels/00 - Review & Exceptions/00.1 - Needs Metadata/Quiet Untagged - Novel"
        )
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.requiresReview)
        XCTAssertEqual(item.safety, .needsChoice)
        XCTAssertTrue(item.reason.contains("Check this shelf"), item.reason)
        XCTAssertTrue(item.isApplyableFileOperation)
        XCTAssertTrue(item.reviewTags.contains("sss-shelf-review"), item.reviewTags.joined(separator: ","))
    }

    func testComicInfoTitleCleanupFindsProviderMarkerConflict() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Ascendance of a Bookworm Fanbook (2017) {mb-100542} {rdb-6581}/ComicInfo.json",
            contents: """
            {
              "title": "Ascendance of a Bookworm: Fanbook",
              "preferred_title": "Ascendance of a Bookworm: Fanbook",
              "local_title": "Ascendance of a Bookworm Part 4",
              "type": "novel",
              "year": 2017,
              "source": "mangabaka, ranobedb",
              "ids": {
                "mangabaka": "100542",
                "ranobedb": "6581"
              }
            }
            """,
            root: root
        )
        try writeFile(
            "Light Novels/Ascendance of a Bookworm Fanbook (2017) {mb-100542} {rdb-6581}/Ascendance Of A Bookworm Part 4 (2017) - Vol 01.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "Clean ComicInfo Titles" })
        let item = try XCTUnwrap(group.items.first)

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertEqual(item.currentPath, "Light Novels/Ascendance of a Bookworm Fanbook (2017) {mb-100542} {rdb-6581}")
        XCTAssertTrue(item.reason.contains("Ascendance of a Bookworm Part 4"), item.reason)
        XCTAssertTrue(item.reviewTags.contains("metadata-title-cleanup"))
    }

    func testComicInfoCleanerKeepsTrustedProviderDataAndTeachesLocalModels() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Manga/Clean Candidate (2021) {mb-678}/ComicInfo.json",
            contents: """
            {
              "title": "Clean Candidate",
              "preferred_title": "Clean Candidate",
              "local_title": "Clean Candidate, Vol. 4 (light Novel)",
              "native_title": "クリーン候補",
              "romanized_title": "Kuriin Kouho",
              "type": "manga",
              "year": 2021,
              "source": "mangabaka, anilist",
              "coverURL": "https://img.example.test/cover.jpg",
              "aliases": [
                "Clean Candidate",
                "Clean Candidate Extra",
                "クリーン候補",
                "Kuriin Kouho",
                "Wrong Series: After Story"
              ],
              "volume_titles": [
                "Clean Candidate",
                "Volume 1"
              ],
              "tags": [
                "romance",
                "school life"
              ],
              "genres": [
                "Romance"
              ],
              "authors": [
                "Author Name"
              ],
              "publishers": [
                "Publisher Name"
              ],
              "ids": {
                "anilist": "12345",
                "mangabaka": "678"
              },
              "title_variants": {
                "english": [
                  "Clean Candidate",
                  "Wrong Series: After Story",
                  "Vol. 4 (light Novel)",
                  "Clean Candidate, Vol. 4 (light Novel)",
                  "Chapter 149.5"
                ],
                "native": [
                  "クリーン候補",
                  "間違った候補"
                ]
              },
              "match_evidence": [
                {
                  "kind": "exactProviderID",
                  "provider": "anilist",
                  "value": "12345",
                  "confidence": 1.0
                },
                {
                  "kind": "titleSimilarity",
                  "provider": "jikan",
                  "value": "Wrong Series: After Story",
                  "confidence": 0.91
                }
              ],
              "source_freshness": [
                {
                  "provider": "mangabaka",
                  "updated_at": "2026-06-15T12:00:00Z"
                },
                {
                  "provider": "jikan",
                  "updated_at": "2026-06-15T12:00:00Z"
                }
              ],
              "classification": {
                "shelf_code": "21",
                "subshelf_code": "21.7",
                "confidence_level": "low"
              },
              "_sable": {
                "mangabaka": {
                  "query": "Clean Candidate",
                  "titles_v2": [
                    {
                      "language": "en",
                      "title": "Clean Candidate Extra"
                    },
                    {
                      "language": "ja",
                      "title": "クリーン候補"
                    }
                  ],
                  "tags_v2": [
                    {
                      "id": "t1",
                      "name": "Romance",
                      "weight": "core",
                      "series_count": 999,
                      "implied_by_tag_ids": [10, 11]
                    }
                  ],
                  "recommendation_neighbors": [
                    {
                      "id": "rec-1",
                      "title": "Clean Neighbor",
                      "reason": "romance fantasy",
                      "weight": "core",
                      "tags": ["Romance", "Fantasy"]
                    }
                  ],
                  "relationships_v2": [
                    {
                      "id": "rel-1",
                      "to_series_id": 123,
                      "relation_type": "side_story"
                    }
                  ]
                },
                "anilist": {
                  "outcome": "leaveUntouched",
                  "reason": "old skipped note"
                },
                "metadata_enrichment": {
                  "outcome": "leaveUntouched",
                  "reason": "old failed refresh"
                },
                "ml": {
                  "scratch": "old"
                },
                "provider_availability": {
                  "anilist": {
                    "status": "not_available"
                  },
                  "ranobedb": {
                    "status": "not_available"
                  }
                },
                "provider_candidate_review": {
                  "anilist": {
                    "status": "candidate",
                    "candidate_id": "12345"
                  },
                  "ranobedb": {
                    "status": "no_match"
                  },
                  "myAnimeList": {
                    "status": "no_match",
                    "provider": "myAnimeList",
                    "source": "trusted_title_conflict",
                    "query": "Clean Candidate",
                    "rejected_candidate_id": "999",
                    "rejected_candidate_title": "Wrong Series: After Story",
                    "reason": "Trusted title conflict",
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile(
            "Manga/Clean Candidate (2021) {mb-678}/Clean Candidate Vol 01.cbz",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "ComicInfo Cleaner" })
        var item = try XCTUnwrap(group.items.first { $0.currentPath == "Manga/Clean Candidate (2021) {mb-678}" })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertFalse(item.usedNetworkData)
        XCTAssertTrue(item.reviewTags.contains("metadata-comicinfo-cleaner"))
        XCTAssertTrue(item.reviewTags.contains("metadata-optional-cleaner"))
        XCTAssertTrue(item.reviewTags.contains("ml-provider-data-cleaner"))

        item.decision = .checked
        let result = await SableLibraryStep3ComicInfo().applyChecked(
            plan: LibraryPlan(root: root, groups: [LibraryPlanGroup(stage: .comicInfo, title: "ComicInfo Cleaner", summary: "Test", items: [item])]),
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1)

        let cleaned = try jsonObject("Manga/Clean Candidate (2021) {mb-678}/ComicInfo.json", root: root)
        let ids = try XCTUnwrap(cleaned["ids"] as? [String: Any])
        XCTAssertEqual(ids["anilist"] as? String, "12345")
        XCTAssertEqual(ids["mangabaka"] as? String, "678")
        XCTAssertEqual(cleaned["local_title"] as? String, "Clean Candidate")
        XCTAssertEqual(cleaned["cover_url"] as? String, "https://img.example.test/cover.jpg")
        XCTAssertNil(cleaned["coverURL"])
        XCTAssertNil(cleaned["classification"])
        XCTAssertNil(cleaned["aliases"])
        let titleVariants = try XCTUnwrap(cleaned["title_variants"] as? [String: Any])
        XCTAssertEqual(titleVariants["english"] as? [String], ["Clean Candidate", "Clean Candidate Extra"])
        XCTAssertEqual(titleVariants["native"] as? [String], ["クリーン候補"])
        XCTAssertEqual(titleVariants["romanized"] as? [String], ["Kuriin Kouho"])
        XCTAssertEqual(cleaned["volume_titles"] as? [String], ["Volume 1"])
        let matchEvidence = try XCTUnwrap(cleaned["match_evidence"] as? [[String: Any]])
        XCTAssertTrue(matchEvidence.contains { $0["provider"] as? String == "anilist" })
        XCTAssertFalse(matchEvidence.contains { $0["provider"] as? String == "jikan" })
        let freshness = try XCTUnwrap(cleaned["source_freshness"] as? [[String: Any]])
        XCTAssertTrue(freshness.contains { $0["provider"] as? String == "mangabaka" })
        XCTAssertFalse(freshness.contains { $0["provider"] as? String == "jikan" })

        let sable = try XCTUnwrap(cleaned["_sable"] as? [String: Any])
        let mangaBaka = try XCTUnwrap(sable["mangabaka"] as? [String: Any])
        XCTAssertNil(mangaBaka["query"])
        XCTAssertNotNil(mangaBaka["titles_v2"])
        XCTAssertNotNil(mangaBaka["tags_v2"])
        XCTAssertEqual((mangaBaka["tags_v2"] as? [[String: Any]])?.first?["weight"] as? String, "core")
        XCTAssertEqual((mangaBaka["tags_v2"] as? [[String: Any]])?.first?["series_count"] as? Int, 999)
        XCTAssertEqual((mangaBaka["tags_v2"] as? [[String: Any]])?.first?["implied_by_tag_ids"] as? [Int], [10, 11])
        XCTAssertEqual((mangaBaka["recommendation_neighbors"] as? [[String: Any]])?.first?["reason"] as? String, "romance fantasy")
        XCTAssertEqual((mangaBaka["relationships_v2"] as? [[String: Any]])?.first?["relation_type"] as? String, "side_story")
        XCTAssertNil(sable["anilist"])
        XCTAssertNil(sable["metadata_enrichment"])
        XCTAssertNil(sable["ml"])
        let availability = try XCTUnwrap(sable["provider_availability"] as? [String: Any])
        XCTAssertNil(availability["anilist"])
        XCTAssertNotNil(availability["ranobedb"])
        let myAnimeListAvailability = try XCTUnwrap(availability["myAnimeList"] as? [String: Any])
        XCTAssertEqual(myAnimeListAvailability["status"] as? String, "not_available")
        XCTAssertEqual(myAnimeListAvailability["rejected_candidate_title"] as? String, "Wrong Series: After Story")

        let trainingEvents = try stringContents("_Sable's Library Reports/_sable_ml_training_events.jsonl", root: root)
        XCTAssertTrue(trainingEvents.contains(#""cleanup_kind":"provider_data_cleaner""#), trainingEvents)
        XCTAssertTrue(trainingEvents.contains(#""has_cover_url":"true""#), trainingEvents)
        XCTAssertTrue(trainingEvents.contains(#""has_title_variants":"true""#), trainingEvents)
        XCTAssertTrue(trainingEvents.contains(#""has_native_title":"true""#), trainingEvents)
        XCTAssertTrue(trainingEvents.contains(#""has_romanized_title":"true""#), trainingEvents)
        XCTAssertTrue(trainingEvents.contains(#""metadata_providers":"anilist,mangabaka""#), trainingEvents)
        XCTAssertTrue(trainingEvents.contains("metadata-comicinfo-cleaner"), trainingEvents)
    }

    func testComicInfoCleanerCompactsRanobeDBRawPayloadWithoutDroppingRefreshEvidence() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Compact Raw Series (2024) {rdb-42}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Compact Raw Series",
              "preferred_title": "Compact Raw Series",
              "type": "lightNovel",
              "year": 2024,
              "description": "A reincarnated librarian tries to survive a strange time loop in another world.",
              "cover_url": "https://img.example.test/compact.jpg",
              "genres": [
                "Fantasy",
                "Psychological"
              ],
              "tags": [
                "Isekai",
                "Time Loop",
                "Anime Tie-in"
              ],
              "authors": [
                "Author Name"
              ],
              "artists": [
                "Artist Name"
              ],
              "ids": {
                "ranobedb": "42"
              },
              "match_evidence": [
                {
                  "kind": "exactProviderID",
                  "provider": "ranobedb",
                  "value": "42",
                  "confidence": 1
                }
              ],
              "source_freshness": [
                {
                  "provider": "ranobedb",
                  "fetched_at": "2026-06-23T12:00:00Z",
                  "ttl_seconds": 604800
                }
              ],
              "_sable": {
                "ranobedb": {
                  "outcome": "safeApply",
                  "confidence_score": 0.98,
                  "series_id": "42",
                  "api": {
                    "schema_version": 1,
                    "series_id": "42",
                    "series": {
                      "id": "42",
                      "title": "Compact Raw Series",
                      "aliases": [
                        "Compact Raw Alias",
                        "Library Loop"
                      ],
                      "description": "A library test series with useful descriptions.",
                      "lang": "en",
                      "olang": "ja",
                      "noisy_provider_blob": {
                        "unneeded": "This field stands in for a large provider response."
                      },
                      "tags": [
                        {
                          "name": "Psychological",
                          "ttype": "theme",
                          "extra": "drop me"
                        }
                      ],
                      "staff": [
                        {
                          "name": "Author Name",
                          "role_type": "author",
                          "person_id": "9001"
                        }
                      ],
                      "publishers": [
                        {
                          "name": "Yen On",
                          "publisher_id": "7"
                        }
                      ],
                      "titles": [
                        {
                          "lang": "en",
                          "title": "Compact Raw Series",
                          "ignored": "drop me"
                        }
                      ]
                    },
                    "book_responses": [
                      {
                        "volume_number": 1,
                        "provider_trace": "drop me",
                        "response": {
                          "book": {
                            "id": "100",
                            "title": "Compact Raw Series, Vol. 1",
                            "aliases": [
                              "Compact Raw Series Book One"
                            ],
                            "sort_order": 1,
                            "description": "Volume one description.",
                            "book_description": {
                              "description": "Detailed volume one description.",
                              "html": "<p>drop me</p>"
                            },
                            "lang": "en",
                            "staff": [
                              {
                                "name": "Translator Name",
                                "role_type": "translator",
                                "staff_id": "8"
                              }
                            ],
                            "publishers": [
                              {
                                "name": "Yen On"
                              }
                            ],
                            "titles": [
                              {
                                "lang": "en",
                                "title": "Compact Raw Series, Vol. 1"
                              }
                            ],
                            "releases": [
                              {
                                "id": "500",
                                "lang": "en",
                                "isbn13": "9780316000001",
                                "description": "Release description.",
                                "release_date": 20240123,
                                "pages": 321,
                                "website": "https://example.test/book"
                              }
                            ]
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("\(folder)/Compact Raw Series - Vol 01.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "ComicInfo Cleaner" })
        var item = try XCTUnwrap(group.items.first { $0.currentPath == folder })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.reviewTags.contains("metadata-optional-cleaner"))
        XCTAssertTrue(item.reason.contains("RanobeDB"), item.reason)

        item.decision = .checked
        let result = await SableLibraryStep3ComicInfo().applyChecked(
            plan: LibraryPlan(root: root, groups: [LibraryPlanGroup(stage: .comicInfo, title: "ComicInfo Cleaner", summary: "Test", items: [item])]),
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1)
        let cleaned = try jsonObject("\(folder)/ComicInfo.json", root: root)
        XCTAssertEqual(cleaned["schema"] as? String, "ComicInfo.SableClean.v1")
        XCTAssertEqual(cleaned["cover_url"] as? String, "https://img.example.test/compact.jpg")
        XCTAssertEqual(cleaned["authors"] as? [String], ["Author Name"])
        XCTAssertEqual(cleaned["artists"] as? [String], ["Artist Name"])

        let creators = try XCTUnwrap(cleaned["creators"] as? [String: Any])
        XCTAssertEqual(creators["authors"] as? [String], ["Author Name"])
        XCTAssertEqual(creators["artists"] as? [String], ["Artist Name"])

        let urls = try XCTUnwrap(cleaned["urls"] as? [String: Any])
        XCTAssertEqual(urls["cover"] as? String, "https://img.example.test/compact.jpg")
        XCTAssertEqual(urls["ranobedb"] as? String, "https://ranobedb.org/series/42")

        let origin = try XCTUnwrap(cleaned["origin"] as? [String: Any])
        XCTAssertEqual(origin["name"] as? String, "Japanese")
        XCTAssertEqual(origin["language"] as? String, "ja")

        XCTAssertNil(cleaned["classification"], "ComicInfo cleanup should not make SSS shelf decisions; folder sorting owns that.")

        let sourceQuality = try XCTUnwrap(cleaned["source_quality"] as? [String: Any])
        XCTAssertEqual(sourceQuality["confidence_score"] as? Double, 0.98)
        let freshness = try XCTUnwrap(sourceQuality["freshness"] as? [String: Any])
        XCTAssertEqual(freshness["ranobedb"] as? String, "2026-06-23T12:00:00Z")
        let sourceEvidence = try XCTUnwrap(sourceQuality["match_evidence"] as? [[String: Any]])
        XCTAssertTrue(sourceEvidence.contains { $0["provider"] as? String == "ranobedb" })

        let sable = try XCTUnwrap(cleaned["_sable"] as? [String: Any])
        let ranobeDB = try XCTUnwrap(sable["ranobedb"] as? [String: Any])
        XCTAssertNil(ranobeDB["api"])

        let compact = try XCTUnwrap(ranobeDB["api_compact"] as? [String: Any])
        let compactSeries = try XCTUnwrap(compact["series"] as? [String: Any])
        XCTAssertEqual(compactSeries["id"] as? String, "42")
        XCTAssertEqual(compactSeries["aliases"] as? [String], ["Compact Raw Alias", "Library Loop"])
        XCTAssertEqual(compactSeries["description"] as? String, "A library test series with useful descriptions.")
        XCTAssertNil(compactSeries["noisy_provider_blob"])

        let compactResponses = try XCTUnwrap(compact["book_responses"] as? [[String: Any]])
        XCTAssertEqual(compactResponses.count, 1)
        let compactResponse = try XCTUnwrap(compactResponses.first)
        XCTAssertEqual(compactResponse["volume_number"] as? Int, 1)
        let response = try XCTUnwrap(compactResponse["response"] as? [String: Any])
        let compactBook = try XCTUnwrap(response["book"] as? [String: Any])
        XCTAssertEqual(compactBook["aliases"] as? [String], ["Compact Raw Series Book One"])
        XCTAssertEqual(compactBook["description"] as? String, "Volume one description.")
        let bookDescription = try XCTUnwrap(compactBook["book_description"] as? [String: Any])
        XCTAssertEqual(bookDescription["description"] as? String, "Detailed volume one description.")
        XCTAssertNil(bookDescription["html"])
        let releases = try XCTUnwrap(compactBook["releases"] as? [[String: Any]])
        XCTAssertTrue(releases.contains { $0["isbn13"] as? String == "9780316000001" })
        XCTAssertTrue(releases.contains { $0["website"] as? String == "https://example.test/book" })

        let summary = try XCTUnwrap(ranobeDB["api_summary"] as? [String: Any])
        XCTAssertEqual(summary["series_id"] as? String, "42")
        XCTAssertEqual(summary["stored_book_payload_count"] as? Int, 1)
        XCTAssertEqual(summary["stored_book_volume_numbers"] as? [Int], [1])
        XCTAssertEqual(summary["raw_payload_stored_in_sidecar"] as? Bool, false)
        XCTAssertNotNil(summary["raw_payload_digest"])
        XCTAssertNotNil(summary["compact_payload_digest"])
        XCTAssertNotNil(summary["raw_payload_bytes"])
        XCTAssertNotNil(summary["compact_payload_bytes"])

        let sourceRanobeDB = try XCTUnwrap(sourceQuality["ranobedb"] as? [String: Any])
        XCTAssertNotNil(sourceRanobeDB["api_summary"])
    }

    func testComicInfoRefreshWritesAlreadyCleanedProviderData() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Quiet Series (2020) {mb-678}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Quiet Series",
              "preferred_title": "Quiet Series",
              "local_title": "Quiet Series",
              "romanized_title": "Kuwaietto Series",
              "type": "lightNovel",
              "year": 2020,
              "ids": {
                "mangabaka": "678"
              },
              "aliases": [
                "Quiet Series",
                "Rejected Noise"
              ],
              "title_variants": {
                "english": [
                  "Quiet Series",
                  "Quiet Series Vol. 1",
                  "Rejected Noise"
                ]
              },
              "_sable": {
                "anilist": {
                  "outcome": "leaveUntouched",
                  "query": "Rejected Noise",
                  "reason": "old failed refresh"
                },
                "provider_candidate_review": {
                  "anilist": {
                    "status": "rejected",
                    "provider": "anilist",
                    "candidate_title": "Rejected Noise",
                    "reason": "Wrong record",
                    "updated_at": "2026-06-18T07:30:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )

        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .refreshComicInfo,
            currentPath: folder,
            proposedPath: "\(folder)/ComicInfo.json",
            reason: "Refresh local sidecar snapshot.",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: false,
            metadataProviders: []
        )
        let plan = LibraryPlan(
            root: root,
            groups: [LibraryPlanGroup(stage: .comicInfo, title: "Refresh Reading Details", summary: "Test", items: [item])]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(plan: plan, service: SableLibraryService())

        XCTAssertEqual(result.appliedCount, 1)
        let cleaned = try jsonObject("\(folder)/ComicInfo.json", root: root)
        let variants = try XCTUnwrap(cleaned["title_variants"] as? [String: Any])
        XCTAssertEqual(variants["english"] as? [String], ["Quiet Series"])
        XCTAssertNil(cleaned["aliases"])

        let sable = try XCTUnwrap(cleaned["_sable"] as? [String: Any])
        XCTAssertNil(sable["anilist"])
        XCTAssertNil(sable["provider_candidate_review"])
        let availability = try XCTUnwrap(sable["provider_availability"] as? [String: Any])
        let aniList = try XCTUnwrap(availability["anilist"] as? [String: Any])
        XCTAssertEqual(aniList["status"] as? String, "not_available")
        XCTAssertEqual(aniList["source"] as? String, "cleaner_rejected_candidate")
    }

    func testBookCatalogProseSidecarsStayOutOfReadingSpecialistProviderGaps() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/Dracula - Novel/ComicInfo.json",
            contents: """
            {
              "title": "Dracula",
              "preferred_title": "Dracula",
              "type": "Novel",
              "source": "openLibrary",
              "ids": {
                "openlibrary": "/works/OL85892W"
              },
              "_sable": {
                "provider_candidate_review": {
                  "ranobedb": {
                    "status": "candidate",
                    "provider": "ranobedb",
                    "source": "provider_gap_precheck",
                    "query": "Dracula",
                    "confidence_score": 0.99,
                    "confidence_percent": 99,
                    "candidate_id": "20569",
                    "candidate_title": "Dark Wars: The Tale of Meiji Dracula",
                    "candidate_media_type": "lightNovel",
                    "candidate_year": 2004,
                    "updated_at": "2026-06-15T12:00:00Z"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Light Novels/Dracula - Novel/Dracula.epub", contents: "book", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMangaBaka = true
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)

        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)

        XCTAssertFalse(
            run.context.plan.groups
                .filter { $0.title.hasPrefix("Missing Providers -") }
                .flatMap(\.items)
                .contains { $0.currentPath == "Light Novels/Dracula - Novel" }
        )
    }

    func testAnimeInfoCleanerKeepsWatchingProviderDataAndPlexHints() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Movies/Quiet Movie (2024) {imdb-tt1000003}/AnimeInfo.json",
            contents: """
            {
              "title": "Quiet Movie",
              "preferred_title": "Quiet Movie",
              "type": "movie",
              "year": 2024,
              "source": "tmdb, wikidata",
              "coverURL": "https://img.example.test/movie.jpg",
              "genres": [
                "Drama"
              ],
              "ids": {
                "imdb": "tt1000003",
                "tmdb": "1003",
                "wikidata": "Q1003"
              },
              "_sable": {
                "wikidata": {
                  "outcome": "leaveUntouched",
                  "reason": "old skipped note"
                },
                "metadata_enrichment": {
                  "outcome": "leaveUntouched",
                  "reason": "old failed refresh"
                },
                "ml": {
                  "scratch": "old"
                },
                "provider_availability": {
                  "wikidata": {
                    "status": "not_available"
                  }
                },
                "provider_candidate_review": {
                  "wikidata": {
                    "status": "candidate",
                    "candidate_id": "Q1003"
                  }
                }
              }
            }
            """,
            root: root
        )
        try writeFile("Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie (2024).mp4", contents: "movie", root: root)

        let service = SableLibraryService()
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let run = await coordinator.inspectStageAndBuildPlan(root: root, options: options, stage: .comicInfo)
        let group = try XCTUnwrap(run.context.plan.groups.first { $0.title == "AnimeInfo Cleaner" })
        var item = try XCTUnwrap(group.items.first { $0.currentPath == "Movies/Quiet Movie (2024) {imdb-tt1000003}" })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertFalse(item.usedNetworkData)
        XCTAssertTrue(item.reviewTags.contains("metadata-animeinfo-cleaner"))
        XCTAssertTrue(item.reviewTags.contains("metadata-optional-cleaner"))
        XCTAssertTrue(item.reviewTags.contains("department.watchinglibrary"))

        item.decision = .checked
        let result = await SableLibraryStep3ComicInfo().applyChecked(
            plan: LibraryPlan(root: root, groups: [LibraryPlanGroup(stage: .comicInfo, title: "AnimeInfo Cleaner", summary: "Test", items: [item])]),
            service: service
        )
        XCTAssertEqual(result.appliedCount, 1)

        let cleaned = try jsonObject("Movies/Quiet Movie (2024) {imdb-tt1000003}/AnimeInfo.json", root: root)
        let ids = try XCTUnwrap(cleaned["ids"] as? [String: Any])
        XCTAssertEqual(ids["imdb"] as? String, "tt1000003")
        XCTAssertEqual(ids["tmdb"] as? String, "1003")
        XCTAssertEqual(ids["wikidata"] as? String, "Q1003")
        XCTAssertEqual(cleaned["cover_url"] as? String, "https://img.example.test/movie.jpg")
        XCTAssertNil(cleaned["coverURL"])
        let sable = cleaned["_sable"] as? [String: Any]
        XCTAssertNil(sable?["wikidata"])
        XCTAssertNil(sable?["metadata_enrichment"])
        XCTAssertTrue(fileExists("Movies/Quiet Movie (2024) {imdb-tt1000003}/.plexmatch", root: root))
    }

    func testProviderBackedAnimeInfoCreateFallsBackToLocalSidecarWithoutProviderIdentity() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Unknown Show/Unknown Show S01E01.mkv", contents: "video", root: root)

        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .createAnimeInfo,
            currentPath: "Unknown Show",
            proposedPath: "Unknown Show/AnimeInfo.json",
            reason: "Try provider-backed AnimeInfo creation.",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: []
        )
        let plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Create AnimeInfo",
                    summary: "Test provider create",
                    items: [item]
                )
            ]
        )

        let result = await SableLibraryStep3ComicInfo().applyChecked(plan: plan, service: SableLibraryService())
        let animeInfo = try jsonObject("Unknown Show/AnimeInfo.json", root: root)
        let ids = animeInfo["ids"] as? [String: Any] ?? [:]

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(animeInfo["preferred_title"] as? String, "Unknown Show")
        XCTAssertEqual(animeInfo["source"] as? String, "local")
        XCTAssertTrue(ids.isEmpty)
        XCTAssertNil(ids["anilist"])
        XCTAssertNil(ids["tvmaze"])
        XCTAssertNil(ids["wikidata"])
    }

    func testAnimeInfoCreateWritesPlexOrganizerTargets() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Frieren Beyond Journey's End (2023) {mal-52991}/Season 01/Frieren - S01E01.mkv",
            contents: "video",
            root: root
        )
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .createAnimeInfo })

        XCTAssertEqual(item.currentPath, "TV/Frieren Beyond Journey's End (2023) {mal-52991}")
        XCTAssertTrue(item.isApplyableComicInfoOperation)

        let result = await coordinator.applyChecked(planByChecking(item.id, in: run.context.plan), stage: .comicInfo)
        let animeInfo = try jsonObject(
            "TV/Frieren Beyond Journey's End (2023) {mal-52991}/AnimeInfo.json",
            root: root
        )
        let ids = try XCTUnwrap(animeInfo["ids"] as? [String: Any])
        let plex = try XCTUnwrap(animeInfo["plex"] as? [String: Any])
        let targets = try XCTUnwrap(plex["organizer_targets"] as? [String: Any])
        let sable = try XCTUnwrap(animeInfo["_sable"] as? [String: Any])
        let snapshot = try XCTUnwrap(sable["video_snapshot"] as? [String: Any])

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(animeInfo["preferred_title"] as? String, "Frieren Beyond Journey's End")
        XCTAssertEqual(animeInfo["type"] as? String, "tvShow")
        XCTAssertEqual(ids["mal"] as? String, "52991")
        XCTAssertEqual(plex["year"] as? Int, 2023)
        XCTAssertEqual(plex["title_with_year"] as? String, "Frieren Beyond Journey's End (2023)")
        XCTAssertEqual(plex["series_path"] as? String, "TV/Frieren Beyond Journey's End (2023)")
        XCTAssertEqual(plex["plex_match_file"] as? String, ".plexmatch")
        XCTAssertEqual(targets["episode_file"] as? String, "TV/Frieren Beyond Journey's End (2023)/Season 01/Frieren Beyond Journey's End (2023) - S01E01 - Episode Title.ext")
        XCTAssertEqual(snapshot["file_count"] as? Int, 1)
        XCTAssertNil(snapshot["files"])
        XCTAssertEqual(
            try stringContents("TV/Frieren Beyond Journey's End (2023) {mal-52991}/.plexmatch", root: root),
            """
            # Generated by Sable's Library from AnimeInfo.json
            title: Frieren Beyond Journey's End
            year: 2023

            """
        )
    }

    func testReadingFileRenameKeepsProviderIDInFolderAndVolumeTitleInFile() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/ComicInfo.json",
            contents: #"{"title":"The Saga of Tanya the Evil","preferred_title":"The Saga of Tanya the Evil","type":"lightNovel","year":2017,"ids":{"mangabaka":"9001"}}"#,
            root: root
        )
        try writeFile(
            "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil Vol. 1 - Deus lo Vult.epub",
            contents: "book",
            root: root
        )
        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })
        let proposedFileName = try XCTUnwrap(item.proposedPath?.split(separator: "/").last.map(String.init))

        XCTAssertEqual(item.currentPath, "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil Vol. 1 - Deus lo Vult.epub")
        XCTAssertEqual(item.proposedPath, "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil (2017) - Vol 01 - Deus lo Vult.epub")
        XCTAssertFalse(proposedFileName.contains("{mb-9001}"))
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testReadingFileRenameUsesRanobeDBVolumeTitleFromComicInfo() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/ComicInfo.json",
            contents: """
            {
              "title": "The Saga of Tanya the Evil",
              "preferred_title": "The Saga of Tanya the Evil",
              "type": "lightNovel",
              "year": 2017,
              "ids": {
                "mangabaka": "9001",
                "ranobedb": "3148"
              },
              "volumes": [
                {
                  "number": 1,
                  "title": "The Saga of Tanya the Evil, Vol. 1: Deus lo Vult",
                  "subtitle": "Deus lo Vult",
                  "file_suffix": "Vol 01 - Deus lo Vult",
                  "isbn13": ["9780316512459", "9780316512442"],
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "11515"
                  }
                }
              ]
            }
            """,
            root: root
        )
        try writeFile(
            "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil Vol. 1.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })
        let proposedFileName = try XCTUnwrap(item.proposedPath?.split(separator: "/").last.map(String.init))

        XCTAssertEqual(item.proposedPath, "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil, Vol. 1- Deus lo Vult.epub")
        XCTAssertFalse(proposedFileName.contains("{mb-9001}"))
        XCTAssertTrue(item.reason.contains("RanobeDB book title"))
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testReadingFileRenameUsesRanobeDBBookTitleWhenSeriesTitleContainsFirstVolumeTitle() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Sugar Apple Fairy Tale The Silver Sugar Master and the Obsidian Fairy (2010) {mb-85341} {rdb-1523}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Sugar Apple Fairy Tale: The Silver Sugar Master and the Obsidian Fairy",
              "preferred_title": "Sugar Apple Fairy Tale: The Silver Sugar Master and the Obsidian Fairy",
              "local_title": "Sugar Apple Fairy Tale The Silver Sugar Master and the Obsidian Fairy",
              "type": "lightNovel",
              "year": 2010,
              "ids": {
                "mangabaka": "85341",
                "ranobedb": "1523"
              },
              "volumes": [
                {
                  "number": 1,
                  "title": "Sugar Apple Fairy Tale, Vol. 1: The Silver Sugar Master and the Obsidian Fairy",
                  "file_suffix": "Vol 01",
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "6211"
                  }
                }
              ]
            }
            """,
            root: root
        )
        try writeFile(
            "\(folder)/Sugar Apple Fairy Tale (2010) - Vol 01.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Sugar Apple Fairy Tale, Vol. 1- The Silver Sugar Master and the Obsidian Fairy.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Sugar Apple Fairy Tale The Silver Sugar Master and the Obsidian Fairy (2010) - Vol 01") ?? true)
        XCTAssertTrue(item.reason.contains("RanobeDB book title"))
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testReadingFileRenameDoesNotRenumberFromShiftedProviderVolumeTitle() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Arifureta From Commonplace to World's Strongest (2015) {mb-82884} {rdb-4602}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Arifureta From Commonplace to World's Strongest",
              "preferred_title": "Arifureta From Commonplace to World's Strongest",
              "local_title": "Arifureta From Commonplace to World's Strongest",
              "type": "lightNovel",
              "year": 2015,
              "ids": {
                "mangabaka": "82884",
                "ranobedb": "4602"
              },
              "volumes": [
                {
                  "number": 11,
                  "title": "Arifureta From Commonplace to World's Strongest: Short Stories",
                  "file_suffix": "Vol 11",
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "short-stories"
                  }
                },
                {
                  "number": 12,
                  "title": "Arifureta From Commonplace to World's Strongest: Volume 11",
                  "file_suffix": "Vol 12",
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "volume-11"
                  }
                },
                {
                  "number": 13,
                  "title": "Arifureta From Commonplace to World's Strongest: Volume 12",
                  "file_suffix": "Vol 13",
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "volume-12"
                  }
                }
              ]
            }
            """,
            root: root
        )
        try writeFile(
            "\(folder)/Arifureta From Commonplace to World's Strongest (2015) - Vol 11.epub",
            contents: "book 11",
            root: root
        )
        try writeFile(
            "\(folder)/Arifureta From Commonplace to World's Strongest (2015) - Vol 12.epub",
            contents: "book 12",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let currentPath = "\(folder)/Arifureta From Commonplace to World's Strongest (2015) - Vol 12.epub"
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile && $0.currentPath == currentPath })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Arifureta From Commonplace to World's Strongest- Volume 12.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Volume 11") ?? true)
    }

    func testReadingFileRenameUsesScopedRanobeDBBookTitleWithoutRenumberingPartLocalFiles() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = "Light Novels/Ascendance of a Bookworm Part 2 (2015) {mb-100477} {rdb-4239}"
        try writeFile(
            "\(folder)/ComicInfo.json",
            contents: """
            {
              "title": "Ascendance of a Bookworm Part 2",
              "preferred_title": "Ascendance of a Bookworm Part 2",
              "local_title": "Ascendance of a Bookworm Part 2",
              "type": "lightNovel",
              "year": 2015,
              "ids": {
                "mangabaka": "100477",
                "ranobedb": "4239"
              },
              "volumes": [
                {
                  "number": 1,
                  "title": "Ascendance of a Bookworm Part 1 Volume 1",
                  "file_suffix": "Vol 01"
                },
                {
                  "number": 4,
                  "title": "Ascendance of a Bookworm: I’ll Do Anything to Become a Librarian! Part 2: Apprentice Shrine Maiden Volume 1",
                  "file_suffix": "Vol 04",
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "part-2-volume-1"
                  }
                },
                {
                  "number": 7,
                  "title": "Ascendance of a Bookworm: I’ll Do Anything to Become a Librarian! Part 2: Apprentice Shrine Maiden Volume 4",
                  "file_suffix": "Vol 07",
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "part-2-volume-4"
                  }
                }
              ]
            }
            """,
            root: root
        )
        try writeFile(
            "\(folder)/Ascendance of a Bookworm Part 2 (2015) - Vol 01.epub",
            contents: "book 01",
            root: root
        )
        try writeFile(
            "\(folder)/Ascendance of a Bookworm Part 2 (2015) - Vol 04.epub",
            contents: "book 04",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let currentPath = "\(folder)/Ascendance of a Bookworm Part 2 (2015) - Vol 04.epub"
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile && $0.currentPath == currentPath })

        XCTAssertEqual(
            item.proposedPath,
            "\(folder)/Ascendance of a Bookworm- I’ll Do Anything to Become a Librarian! Part 2- Apprentice Shrine Maiden Volume 4.epub"
        )
        XCTAssertFalse(item.proposedPath?.contains("Vol 01") ?? true)
        XCTAssertFalse(item.proposedPath?.contains("Vol 07") ?? true)
        XCTAssertTrue(item.reason.contains("RanobeDB book title"))
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testReadingFileRenameFlagsVolumeTitleConflictsForManualReview() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/ComicInfo.json",
            contents: """
            {
              "title": "The Saga of Tanya the Evil",
              "preferred_title": "The Saga of Tanya the Evil",
              "type": "lightNovel",
              "year": 2017,
              "ids": {
                "mangabaka": "9001",
                "ranobedb": "3148"
              },
              "volumes": [
                {
                  "number": 1,
                  "title": "The Saga of Tanya the Evil, Vol. 1: Deus lo Vult",
                  "subtitle": "Deus lo Vult",
                  "file_suffix": "Vol 01 - Deus lo Vult",
                  "isbn13": ["9780316512459", "9780316512442"],
                  "source_id": {
                    "provider": "ranobedb",
                    "value": "11515"
                  }
                }
              ]
            }
            """,
            root: root
        )
        try writeFile(
            "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil Vol. 1 - Different Title.epub",
            contents: "book",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })
        let proposedFileName = try XCTUnwrap(item.proposedPath?.split(separator: "/").last.map(String.init))

        XCTAssertEqual(item.currentPath, "Light Novels/The Saga of Tanya the Evil (2017) {mb-9001}/The Saga of Tanya the Evil Vol. 1 - Different Title.epub")
        XCTAssertEqual(proposedFileName, "The Saga of Tanya the Evil (2017) - Vol 01 - Different Title.epub")
        XCTAssertTrue(item.reason.contains("volume or chapter title differs"))
        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertTrue(item.requiresReview)
        XCTAssertFalse(item.isApplyableFileOperation)
    }

    func testLegacySubtitlesMigrateToEpisodeTitlesDuringAnimeInfoRefresh() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Quiet Drama/AnimeInfo.json",
            contents: """
            {
              "title": "Quiet Drama",
              "preferred_title": "Quiet Drama",
              "type": "animeTV",
              "year": 2023,
              "source": "local",
              "last_checked": "2020-01-01T00:00:00Z",
              "subtitles": [
                "S01E01 - Opening Battle",
                "S01E02 - Quiet Morning"
              ]
            }
            """,
            root: root
        )
        try writeFile("TV/Quiet Drama/clip.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        var stages = LibraryPipelineStageOptions()
        stages.useMetadataProviders = true
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: stages,
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .refreshAnimeInfo })
        XCTAssertTrue(item.isApplyableComicInfoOperation)

        let result = await coordinator.applyChecked(planByChecking(item.id, in: run.context.plan), stage: .comicInfo)
        let animeInfo = try jsonObject("TV/Quiet Drama/AnimeInfo.json", root: root)
        let episodeTitles = animeInfo["episode_titles"] as? [String]
        let volumeTitles = animeInfo["volume_titles"] as? [String]

        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertNil(animeInfo["subtitles"])
        XCTAssertEqual(
            episodeTitles,
            ["S01E01 - Opening Battle", "S01E02 - Quiet Morning"]
        )
        XCTAssertNil(volumeTitles)
    }

    func testWatchingEpisodeRenameUsesAnimeInfoPlexSeasonPath() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Frieren Beyond Journey's End (2023)/AnimeInfo.json",
            contents: #"{"title":"Frieren: Beyond Journey's End","preferred_title":"Frieren: Beyond Journey's End","type":"animeTV","year":2023,"ids":{"mal":"52991"}}"#,
            root: root
        )
        try writeFile(
            "TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.mkv",
            contents: "video",
            root: root
        )
        try writeFile(
            "TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.eng.forced.srt",
            contents: "subtitle",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first {
            $0.operation == .renameFile
                && $0.currentPath == "TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.mkv"
        })
        let subtitleItem = try XCTUnwrap(run.context.plan.items.first {
            $0.operation == .renameFile
                && $0.currentPath == "TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.eng.forced.srt"
        })

        XCTAssertEqual(item.currentPath, "TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.mkv")
        XCTAssertEqual(item.proposedPath, "TV/Frieren Beyond Journey's End (2023)/Season 01/Frieren Beyond Journey's End (2023) - S01E01 - The Journey's End.mkv")
        XCTAssertTrue(item.reason.contains("episode naming"))
        XCTAssertTrue(item.isApplyableFileOperation)
        XCTAssertEqual(subtitleItem.proposedPath, "TV/Frieren Beyond Journey's End (2023)/Season 01/Frieren Beyond Journey's End (2023) - S01E01 - The Journey's End.eng.forced.srt")
        XCTAssertTrue(subtitleItem.isApplyableFileOperation)

        let result = await coordinator.applyChecked(run.context.plan, stage: .canonicalFiles)

        XCTAssertEqual(result.appliedCount, 2)
        XCTAssertFalse(fileExists("TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.mkv", root: root))
        XCTAssertTrue(fileExists("TV/Frieren Beyond Journey's End (2023)/Season 01/Frieren Beyond Journey's End (2023) - S01E01 - The Journey's End.mkv", root: root))
        XCTAssertFalse(fileExists("TV/Frieren Beyond Journey's End (2023)/Frieren - S01E01 - The Journey's End.eng.forced.srt", root: root))
        XCTAssertTrue(fileExists("TV/Frieren Beyond Journey's End (2023)/Season 01/Frieren Beyond Journey's End (2023) - S01E01 - The Journey's End.eng.forced.srt", root: root))
    }

    func testWatchingLooseEpisodeNumbersUseAnimeInfoPlexSeasonPath() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Aoharu Snatch (2023)/AnimeInfo.json",
            contents: #"{"title":"Aoharu Snatch","preferred_title":"Aoharu Snatch","local_title":"Aoharu Snatch","type":"animeTV","year":2023,"source":"local"}"#,
            root: root
        )
        try writeFile("TV/Aoharu Snatch (2023)/Aoharu Snatch - 01.mp4", contents: "video", root: root)
        try writeFile("TV/Aoharu Snatch (2023)/Aoharu Snatch - 02 - Quiet Day.mp4", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let items = run.context.plan.items.filter { $0.operation == .renameFile }

        XCTAssertTrue(items.contains {
            $0.currentPath == "TV/Aoharu Snatch (2023)/Aoharu Snatch - 01.mp4"
                && $0.proposedPath == "TV/Aoharu Snatch (2023)/Season 01/Aoharu Snatch (2023) - S01E01.mp4"
                && $0.isApplyableFileOperation
        })
        XCTAssertTrue(items.contains {
            $0.currentPath == "TV/Aoharu Snatch (2023)/Aoharu Snatch - 02 - Quiet Day.mp4"
                && $0.proposedPath == "TV/Aoharu Snatch (2023)/Season 01/Aoharu Snatch (2023) - S01E02 - Quiet Day.mp4"
                && $0.isApplyableFileOperation
        })
    }

    func testWatchingSingleOvaFileCanInferSeasonZeroEpisodeOne() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Kegareboshi Aka (2025)/AnimeInfo.json",
            contents: #"{"title":"Kegareboshi Aka","preferred_title":"Kegareboshi Aka","local_title":"Kegareboshi Aka","type":"ova","year":2025,"source":"local"}"#,
            root: root
        )
        try writeFile("TV/Kegareboshi Aka (2025)/Kegareboshi Aka.mp4", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })

        XCTAssertEqual(item.proposedPath, "TV/Kegareboshi Aka (2025)/Season 00/Kegareboshi Aka (2025) - S00E01.mp4")
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testWatchingMovieRenameUsesAnimeInfoMovieName() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Movies/Spirited Away (2001) {tmdb-129}/AnimeInfo.json",
            contents: #"{"title":"Spirited Away","preferred_title":"Spirited Away","type":"animeMovie","year":2001,"ids":{"tmdb":"129"}}"#,
            root: root
        )
        try writeFile("Movies/Spirited Away (2001) {tmdb-129}/random release.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })

        XCTAssertEqual(item.proposedPath, "Movies/Spirited Away (2001) {tmdb-129}/Spirited Away (2001) {tmdb-129}.mkv")
        XCTAssertTrue(item.reason.contains("movie naming"))
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testWatchingSplitMovieRenamePreservesPlexPartSuffixes() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Movies/Quiet Movie (2024) {imdb-tt1000003}/AnimeInfo.json",
            contents: #"{"title":"Quiet Movie","preferred_title":"Quiet Movie","type":"movie","year":2024,"ids":{"imdb":"tt1000003"}}"#,
            root: root
        )
        try writeFile("Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie cd1.mkv", contents: "video", root: root)
        try writeFile("Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie cd2.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let items = run.context.plan.items.filter { $0.operation == .renameFile }

        XCTAssertTrue(items.contains {
            $0.currentPath == "Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie cd1.mkv"
                && $0.proposedPath == "Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie (2024) {imdb-tt1000003} - cd1.mkv"
                && $0.isApplyableFileOperation
        })
        XCTAssertTrue(items.contains {
            $0.currentPath == "Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie cd2.mkv"
                && $0.proposedPath == "Movies/Quiet Movie (2024) {imdb-tt1000003}/Quiet Movie (2024) {imdb-tt1000003} - cd2.mkv"
                && $0.isApplyableFileOperation
        })
    }

    func testWatchingMovieRenameDoesNotUseMALInPlexName() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "Movies/Quiet Movie (2024)/AnimeInfo.json",
            contents: #"{"title":"Quiet Movie","preferred_title":"Quiet Movie","type":"animeMovie","year":2024,"ids":{"mal":"60000"}}"#,
            root: root
        )
        try writeFile("Movies/Quiet Movie (2024)/random release.mkv", contents: "video", root: root)

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })

        XCTAssertEqual(item.proposedPath, "Movies/Quiet Movie (2024)/Quiet Movie (2024).mkv")
        XCTAssertFalse(item.proposedPath?.contains("{mal-") ?? true)
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testWatchingSpecialRenameUsesSeasonZero() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Frieren Beyond Journey's End (2023)/AnimeInfo.json",
            contents: #"{"title":"Frieren: Beyond Journey's End","preferred_title":"Frieren: Beyond Journey's End","type":"special","year":2023,"ids":{"mal":"52991"}}"#,
            root: root
        )
        try writeFile(
            "TV/Frieren Beyond Journey's End (2023)/Specials/Frieren - S00E01 - Prelude.mkv",
            contents: "video",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })

        XCTAssertEqual(item.proposedPath, "TV/Frieren Beyond Journey's End (2023)/Season 00/Frieren Beyond Journey's End (2023) - S00E01 - Prelude.mkv")
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testWatchingMultiEpisodeRenamePreservesPlexEpisodeRange() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(
            "TV/Quiet Show (2024) {imdb-tt1000004}/AnimeInfo.json",
            contents: #"{"title":"Quiet Show","preferred_title":"Quiet Show","type":"tvShow","year":2024,"ids":{"imdb":"tt1000004"}}"#,
            root: root
        )
        try writeFile(
            "TV/Quiet Show (2024) {imdb-tt1000004}/Quiet Show - S01E01-E02 - Double Feature.mkv",
            contents: "video",
            root: root
        )

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)
        let item = try XCTUnwrap(run.context.plan.items.first { $0.operation == .renameFile })

        XCTAssertEqual(item.proposedPath, "TV/Quiet Show (2024) {imdb-tt1000004}/Season 01/Quiet Show (2024) - S01E01-E02 - Double Feature.mkv")
        XCTAssertTrue(item.isApplyableFileOperation)
    }

    func testWatchingOvaAndOnaRenameIntoSeasonZero() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let cases = [
            (mediaType: "ova", title: "Quiet OVA", imdb: "tt1000001"),
            (mediaType: "ona", title: "Quiet ONA", imdb: "tt1000002")
        ]

        for testCase in cases {
            let folder = "TV/\(testCase.title) (2024) {imdb-\(testCase.imdb)}"
            try writeFile(
                "\(folder)/AnimeInfo.json",
                contents: #"{"title":"\#(testCase.title)","preferred_title":"\#(testCase.title)","type":"\#(testCase.mediaType)","year":2024,"ids":{"imdb":"\#(testCase.imdb)"}}"#,
                root: root
            )
            try writeFile(
                "\(folder)/\(testCase.title) - S01E02 - Side Story.mkv",
                contents: "video",
                root: root
            )
        }

        let service = SableLibraryService()
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let options = LibraryPipelineOptions(
            cleanup: CleanupOptions(),
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )

        let run = await coordinator.inspectAndBuildPlan(root: root, options: options)

        for testCase in cases {
            let folder = "TV/\(testCase.title) (2024) {imdb-\(testCase.imdb)}"
            let item = try XCTUnwrap(run.context.plan.items.first {
                $0.operation == .renameFile
                    && $0.currentPath == "\(folder)/\(testCase.title) - S01E02 - Side Story.mkv"
            })

            XCTAssertEqual(item.proposedPath, "\(folder)/Season 00/\(testCase.title) (2024) - S00E02 - Side Story.mkv")
            XCTAssertTrue(item.isApplyableFileOperation)
        }
    }

    func testFolderReorganizationRemovesOnlyAbandonedEmptyShelfBranches() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldSeries = "Light Novels/Old Shelf/Old Subshelf/Series"
        let newSeries = "Light Novels/New Shelf/New Subshelf/Series"
        try writeFile("\(oldSeries)/ComicInfo.json", contents: #"{"title":"Series"}"#, root: root)
        try writeFile("Light Novels/Old Shelf/Old Subshelf/.DS_Store", contents: "finder", root: root)
        let item = planItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: oldSeries,
            proposedPath: newSeries,
            decision: .checked
        )
        let plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .canonicalFolders,
                    title: "Folder sorting",
                    summary: "Test plan",
                    items: [item]
                )
            ]
        )

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .canonicalFolders,
            options: nil,
            service: SableLibraryService()
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)
        XCTAssertTrue(fileExists("\(newSeries)/ComicInfo.json", root: root))
        XCTAssertFalse(fileExists("Light Novels/Old Shelf/Old Subshelf", root: root))
        XCTAssertFalse(fileExists("Light Novels/Old Shelf", root: root))
        XCTAssertTrue(fileExists("Light Novels", root: root))
        XCTAssertTrue(result.summary.contains("Removed empty source folders: 2"), result.summary)
    }

    func testFolderReorganizationPreservesOldShelfContainingARealFile() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldSeries = "Manga/Old Shelf/Old Subshelf/Series"
        let newSeries = "Manga/New Shelf/New Subshelf/Series"
        try writeFile("\(oldSeries)/ComicInfo.json", contents: #"{"title":"Series"}"#, root: root)
        try writeFile("Manga/Old Shelf/keep.txt", contents: "keep this", root: root)
        let move = PlannedMove(
            reason: "change shelf organization",
            fromPath: oldSeries,
            toPath: newSeries
        )

        let result = await SableLibraryService().applyPlannedMovesWithApplied(
            root: root,
            moves: [move],
            reportTitle: "Shelf cleanup test",
            reportName: "_shelf_cleanup_test.txt",
            cleanupEmptySourceFolders: true
        )

        XCTAssertEqual(result.applied, [move])
        XCTAssertFalse(fileExists("Manga/Old Shelf/Old Subshelf", root: root))
        XCTAssertTrue(fileExists("Manga/Old Shelf/keep.txt", root: root))
        XCTAssertTrue(fileExists("\(newSeries)/ComicInfo.json", root: root))
    }

    func testFolderReorganizationCleansStaleEmptyBranchWhenDestinationAlreadyExists() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldSeries = "Light Novels/Fantasy/Magic/Already Sorted"
        let newSeries = "Light Novels/Fantasy/Already Sorted"
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(oldSeries).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeFile(
            "Light Novels/Fantasy/Magic/.DS_Store",
            contents: "finder",
            root: root
        )
        try writeFile(
            "\(newSeries)/ComicInfo.json",
            contents: #"{"title":"Already Sorted"}"#,
            root: root
        )

        let result = await SableLibraryService().applyPlannedMovesWithApplied(
            root: root,
            moves: [
                PlannedMove(
                    reason: "change folder depth",
                    fromPath: oldSeries,
                    toPath: newSeries
                )
            ],
            reportTitle: "Stale folder cleanup test",
            reportName: "_stale_folder_cleanup_test.txt",
            cleanupEmptySourceFolders: true
        )

        XCTAssertTrue(result.applied.isEmpty)
        XCTAssertTrue(result.skipped.isEmpty, result.report)
        XCTAssertTrue(result.changedFiles)
        XCTAssertTrue(fileExists("\(newSeries)/ComicInfo.json", root: root))
        XCTAssertFalse(fileExists("Light Novels/Fantasy/Magic", root: root))
        XCTAssertTrue(fileExists("Light Novels/Fantasy", root: root))
        XCTAssertTrue(result.report.contains("Already sorted: 1"), result.report)
        XCTAssertTrue(result.report.contains("Removed empty source folders: 1"), result.report)
    }

    func testFolderSortingSurfacesAndRemovesExistingEmptySSSSubShelf() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let shelf = "Light Novels/20 - Fantasy & Supernatural"
        let staleSubShelf = "\(shelf)/20.3 - Paranormal Life & Supernatural Beings"
        let activeSeries = "\(shelf)/Active Series"
        try writeFile("\(activeSeries)/Active Series - Vol 01.epub", contents: "book", root: root)
        try writeJSONObject(
            [
                "title": "Active Series",
                "type": "lightNovel"
            ],
            to: "\(activeSeries)/ComicInfo.json",
            root: root
        )
        try writeFile("\(staleSubShelf)/.DS_Store", contents: "finder", root: root)

        var cleanup = CleanupOptions()
        cleanup.readingFolderOrganizationDepth = .shelf
        let options = LibraryPipelineOptions(
            cleanup: cleanup,
            stages: LibraryPipelineStageOptions(),
            intelligence: SableLibraryIntelligenceOptions()
        )
        let service = SableLibraryService()
        let run = await SableLibraryPipelineCoordinator(service: service).inspectStageAndBuildPlan(
            root: root,
            options: options,
            stage: .canonicalFolders
        )
        var item = try XCTUnwrap(run.context.plan.items.first {
            $0.isEmptySortingFolderCleanup && $0.currentPath == staleSubShelf
        })

        XCTAssertEqual(item.decision, .unchecked)
        XCTAssertNil(item.proposedPath)
        XCTAssertTrue(item.isApplyableOperation)

        item.decision = .checked
        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: LibraryPlan(
                root: root,
                groups: [
                    LibraryPlanGroup(
                        stage: .canonicalFolders,
                        title: "Empty Sorting Folders",
                        summary: "One stale folder",
                        items: [item]
                    )
                ]
            ),
            stage: .canonicalFolders,
            options: options,
            service: service
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)
        XCTAssertFalse(fileExists(staleSubShelf, root: root))
        XCTAssertTrue(fileExists(activeSeries, root: root))
        XCTAssertTrue(result.summary.contains("Removed empty sorting folders: 1"), result.summary)
    }

    func testRestoreLastApplyMovesAppliedFileBackToOriginalPath() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Series/Old.cbz", contents: "original", root: root)
        let service = SableLibraryService()
        let move = PlannedMove(
            reason: "test rename",
            fromPath: "Series/Old.cbz",
            toPath: "Series/New.cbz"
        )

        let applyResult = await service.applyPlannedMovesWithApplied(
            root: root,
            moves: [move],
            reportTitle: "Test apply",
            reportName: "_test_apply.txt"
        )

        XCTAssertTrue(applyResult.changedFiles)
        XCTAssertEqual(applyResult.applied, [move])
        XCTAssertFalse(fileExists("Series/Old.cbz", root: root))
        XCTAssertTrue(fileExists("Series/New.cbz", root: root))

        let restoreResult = await service.restoreLastApply(root: root)

        XCTAssertEqual(restoreResult.appliedCount, 1)
        XCTAssertEqual(restoreResult.skippedCount, 0)
        XCTAssertNotNil(restoreResult.receiptPath)
        XCTAssertTrue(restoreResult.summary.contains("Restored: 1"))
        XCTAssertFalse(fileExists("Series/New.cbz", root: root))
        XCTAssertTrue(fileExists("Series/Old.cbz", root: root))
        XCTAssertEqual(try stringContents("Series/Old.cbz", root: root), "original")
    }

    func testMoveApplyReportsCompletedChangesWhenUndoAndReceiptCannotBeSaved() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Series/Old.cbz", contents: "original", root: root)
        try writeFile(SableLibraryConfig.fallback.reportFolderName, contents: "blocks report folder", root: root)
        let service = SableLibraryService()
        let move = PlannedMove(
            reason: "test rename",
            fromPath: "Series/Old.cbz",
            toPath: "Series/New.cbz"
        )

        let result = await service.applyPlannedMovesWithApplied(
            root: root,
            moves: [move],
            reportTitle: "Test apply",
            reportName: "_test_apply.txt"
        )

        XCTAssertTrue(result.changedFiles)
        XCTAssertEqual(result.applied, [move])
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertFalse(fileExists("Series/Old.cbz", root: root))
        XCTAssertTrue(fileExists("Series/New.cbz", root: root))
        XCTAssertEqual(try stringContents("Series/New.cbz", root: root), "original")
        XCTAssertTrue(result.report.contains("Recovery warning"), result.report)
        XCTAssertTrue(result.report.contains("Receipt warning"), result.report)
        XCTAssertTrue(result.report.contains("1 change was applied"), result.report)
    }

    func testReviewApplyDoesNotExposeReceiptPathWhenReceiptCannotBeSavedAfterMove() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Series/Old.cbz", contents: "original", root: root)
        try writeFile(SableLibraryConfig.fallback.reportFolderName, contents: "blocks report folder", root: root)
        let item = planItem(
            currentPath: "Series/Old.cbz",
            proposedPath: "Series/New.cbz",
            decision: .checked
        )
        let plan = LibraryPlan(
            root: root,
            groups: [
                LibraryPlanGroup(
                    stage: .canonicalFiles,
                    title: "Book file names",
                    summary: "Test plan",
                    items: [item]
                )
            ]
        )

        let result = await SableLibraryStep6ReviewApply().applyChecked(
            plan: plan,
            stage: .canonicalFiles,
            options: nil,
            service: SableLibraryService()
        )

        XCTAssertEqual(result.appliedCount, 1, result.summary)
        XCTAssertEqual(result.skippedCount, 0, result.summary)
        XCTAssertNil(result.receiptPath)
        XCTAssertFalse(fileExists("Series/Old.cbz", root: root))
        XCTAssertTrue(fileExists("Series/New.cbz", root: root))
        XCTAssertTrue(result.summary.contains("Receipt warning"), result.summary)
        XCTAssertTrue(result.summary.contains("1 change was applied"), result.summary)
    }

    func testRestoreLastApplySkipsWhenOriginalPathIsOccupied() async throws {
        let root = try makeTemporaryLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile("Series/Old.cbz", contents: "original", root: root)
        let service = SableLibraryService()
        let move = PlannedMove(
            reason: "test rename",
            fromPath: "Series/Old.cbz",
            toPath: "Series/New.cbz"
        )

        let applyResult = await service.applyPlannedMovesWithApplied(
            root: root,
            moves: [move],
            reportTitle: "Test apply",
            reportName: "_test_apply.txt"
        )
        XCTAssertEqual(applyResult.applied, [move])

        try writeFile("Series/Old.cbz", contents: "do not overwrite", root: root)

        let restoreResult = await service.restoreLastApply(root: root)

        XCTAssertEqual(restoreResult.appliedCount, 0)
        XCTAssertEqual(restoreResult.skippedCount, 1)
        XCTAssertNotNil(restoreResult.receiptPath)
        XCTAssertTrue(restoreResult.summary.contains("Skipped: 1"))
        XCTAssertTrue(fileExists("Series/New.cbz", root: root))
        XCTAssertTrue(fileExists("Series/Old.cbz", root: root))
        XCTAssertEqual(try stringContents("Series/Old.cbz", root: root), "do not overwrite")
        XCTAssertEqual(try stringContents("Series/New.cbz", root: root), "original")
    }

    private func planItem(
        stage: LibraryPipelineStage = .canonicalFiles,
        operation: LibraryPlanOperation = .renameFile,
        currentPath: String = "/Library/Old.cbz",
        proposedPath: String? = "/Library/New.cbz",
        reason: String = "test suggestion",
        confidence: LibraryPlanConfidence = .high,
        safety: LibraryPlanSafety = .reversible,
        decision: LibraryPlanDecision = .unchecked,
        requiresReview: Bool = false,
        usedNetworkData: Bool = false,
        reviewTags: [String] = []
    ) -> LibraryPlanItem {
        LibraryPlanItem(
            stage: stage,
            operation: operation,
            currentPath: currentPath,
            proposedPath: proposedPath,
            reason: reason,
            confidence: confidence,
            safety: safety,
            decision: decision,
            requiresReview: requiresReview,
            usedNetworkData: usedNetworkData,
            reviewTags: reviewTags
        )
    }

    private func readingSeries(
        path: String,
        displayName: String,
        mediaType: String?,
        bookCount: Int = 1,
        hasComicInfo: Bool = true
    ) -> LibrarySeriesSnapshot {
        LibrarySeriesSnapshot(
            id: path,
            path: path,
            displayName: displayName,
            localTitle: nil,
            preferredTitle: nil,
            mediaType: mediaType,
            year: nil,
            primarySourceID: nil,
            identityGraph: nil,
            sourceFreshness: [],
            finalVolume: nil,
            localBookCount: bookCount,
            localHighestVolume: nil,
            comicInfoSource: hasComicInfo ? "local" : nil,
            comicInfoLastChecked: nil,
            mangaBakaExpectedType: nil,
            mangaBakaTypeMatched: nil,
            hasComicInfo: hasComicInfo
        )
    }

    private func watchingSeries(
        path: String,
        displayName: String,
        mediaType: String?,
        videoCount: Int = 1,
        hasAnimeInfo: Bool = true
    ) -> LibraryVideoSeriesSnapshot {
        LibraryVideoSeriesSnapshot(
            id: path,
            path: path,
            displayName: displayName,
            localTitle: nil,
            preferredTitle: nil,
            mediaType: mediaType,
            year: nil,
            primarySourceID: nil,
            identityGraph: nil,
            sourceFreshness: [],
            localVideoCount: videoCount,
            animeInfoSource: hasAnimeInfo ? "local" : nil,
            animeInfoLastChecked: nil,
            hasAnimeInfo: hasAnimeInfo
        )
    }

    private func makeTemporaryLibraryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFile(_ relativePath: String, contents: String, root: URL) throws {
        let url = fileURL(relativePath, root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    #if canImport(AppKit)
    private func jpegFixtureData(width: Int, height: Int, quality: CGFloat) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "SableLibraryTests", code: 1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(
            starting: NSColor(red: 0.92, green: 0.32, blue: 0.42, alpha: 1),
            ending: NSColor(red: 0.18, green: 0.34, blue: 0.78, alpha: 1)
        )?.draw(in: rect, angle: 35)
        NSColor(white: 1, alpha: 0.18).setFill()
        for index in stride(from: 0, to: width, by: max(width / 24, 1)) {
            NSBezierPath(
                ovalIn: NSRect(
                    x: index,
                    y: (index * 3) % max(height, 1),
                    width: max(width / 9, 1),
                    height: max(height / 14, 1)
                )
            ).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw NSError(domain: "SableLibraryTests", code: 2)
        }
        return data
    }
    #endif

    private func writeJSONObject(_ object: [String: Any], to relativePath: String, root: URL) throws {
        let url = fileURL(relativePath, root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func writeCoverManifest(
        bookFile: String,
        coverPath: String,
        folder: String,
        root: URL
    ) throws {
        let seriesTitle = bookFile.components(separatedBy: " - Vol").first ?? bookFile
        let japanesePath = coverPath.replacingOccurrences(
            of: "_covers/en/",
            with: "_covers/jp/"
        )
        try writeFile("\(folder)/\(japanesePath)", contents: "japanese cover", root: root)
        try writeJSONObject(
            [
                "version": 2,
                "generated_at": "2026-07-20T00:00:00Z",
                "generator": "Sable's Library Tests",
                "series_title": seriesTitle,
                "media_type": "lightNovel",
                "entries": [
                    [
                        "book_file": bookFile,
                        "volume": 1,
                        "covers": [
                            [
                                "language": "en",
                                "source": "BookWalker Global",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": coverPath,
                                "width": 1_400,
                                "height": 2_000,
                                "provider_title": "\(seriesTitle), Vol. 1",
                                "provider_item_id": "\(seriesTitle)-en-1",
                                "provider_volume": 1,
                                "provider_media_type": "novel"
                            ],
                            [
                                "language": "jp",
                                "source": "MangaBaka",
                                "role": "normal",
                                "status": "selected_downloaded",
                                "path": japanesePath,
                                "width": 1_400,
                                "height": 2_000,
                                "provider_title": seriesTitle,
                                "provider_item_id": "\(seriesTitle)-jp-1",
                                "provider_volume": 1,
                                "provider_media_type": "novel"
                            ]
                        ]
                    ]
                ],
                "skipped": []
            ],
            to: "\(folder)/_covers/cover-manifest.json",
            root: root
        )
    }

    private func writeNCXBackedStructureFixture(
        _ relativePath: String,
        root: URL,
        firstChapterLabel: String,
        firstChapterBody: String,
        includeThirdChapter: Bool = true,
        useFragmentTargets: Bool = true
    ) throws {
        let firstTarget = useFragmentTargets ? "chapter.xhtml#chapter-1" : "chapter.xhtml"
        let secondTarget = useFragmentTargets ? "chapter-02.xhtml#chapter-2" : "chapter-02.xhtml"
        let thirdTarget = useFragmentTargets ? "chapter-03.xhtml#chapter-3" : "chapter-03.xhtml"
        let thirdManifest = includeThirdChapter
            ? #"<item id="chapter-3" href="chapter-03.xhtml" media-type="application/xhtml+xml"/>"#
            : ""
        let thirdSpine = includeThirdChapter
            ? #"<itemref idref="chapter-3"/>"#
            : ""
        let thirdNCX = includeThirdChapter
            ? """
              <navPoint id="navPoint-3" playOrder="3">
                <navLabel><text>Chapter 3: Rain</text></navLabel>
                <content src="\(thirdTarget)"/>
              </navPoint>
            """
            : ""
        let thirdNav = includeThirdChapter
            ? #"<li><a href="\#(thirdTarget)">Chapter 3: Rain</a></li>"#
            : ""
        let secondChapterBody = useFragmentTargets
            ? #"<div id="chapter-2" class="chapter-title">Chapter 2: Tea</div><p>Two.</p>"#
            : #"<div class="chapter-title">Chapter 2: Tea</div><p>Two.</p>"#
        let thirdChapterBody = useFragmentTargets
            ? #"<p id="chapter-3" class="chapter-title">Chapter 3: Rain</p><p>Three.</p>"#
            : #"<p class="chapter-title">Chapter 3: Rain</p><p>Three.</p>"#
        var extraFiles: [String: Data] = [
            "OPS/nav.xhtml": Data(
                """
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                  <body>
                    <nav epub:type="toc"><ol>
                      <li><a href="\(firstTarget)">\(firstChapterLabel)</a></li>
                      <li><a href="\(secondTarget)">Chapter 2: Tea</a></li>
                      \(thirdNav)
                    </ol></nav>
                  </body>
                </html>
                """.utf8
            ),
            "OPS/toc.ncx": Data(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <navMap>
                    <navPoint id="navPoint-1" playOrder="1">
                      <navLabel><text>\(firstChapterLabel)</text></navLabel>
                      <content src="\(firstTarget)"/>
                    </navPoint>
                    <navPoint id="navPoint-2" playOrder="2">
                      <navLabel><text>Chapter 2: Tea</text></navLabel>
                      <content src="\(secondTarget)"/>
                    </navPoint>
                    \(thirdNCX)
                  </navMap>
                </ncx>
                """.utf8
            ),
            "OPS/chapter-02.xhtml": Data(
                #"<html xmlns="http://www.w3.org/1999/xhtml"><body>\#(secondChapterBody)</body></html>"#.utf8
            )
        ]
        if includeThirdChapter {
            extraFiles["OPS/chapter-03.xhtml"] = Data(
                #"<html xmlns="http://www.w3.org/1999/xhtml"><body>\#(thirdChapterBody)</body></html>"#.utf8
            )
        }

        try writeEPUBFixture(
            relativePath,
            title: "Structure Needed",
            root: root,
            includeCover: false,
            extraManifestXML: """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="chapter-2" href="chapter-02.xhtml" media-type="application/xhtml+xml"/>
                \(thirdManifest)
            """,
            extraSpineXML: """
                <itemref idref="chapter-2"/>
                \(thirdSpine)
            """,
            chapterText: #"<html xmlns="http://www.w3.org/1999/xhtml"><body>\#(firstChapterBody)</body></html>"#,
            extraFiles: extraFiles
        )
    }

    private func pngHeaderFixtureData(width: UInt32, height: UInt32) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])
        data.append(Data("IHDR".utf8))
        data.append(contentsOf: [
            UInt8((width >> 24) & 0xFF),
            UInt8((width >> 16) & 0xFF),
            UInt8((width >> 8) & 0xFF),
            UInt8(width & 0xFF),
            UInt8((height >> 24) & 0xFF),
            UInt8((height >> 16) & 0xFF),
            UInt8((height >> 8) & 0xFF),
            UInt8(height & 0xFF),
            0x08, 0x02, 0x00, 0x00, 0x00
        ])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        return data
    }

    private func writeEPUBFixture(
        _ relativePath: String,
        title: String,
        root: URL,
        includeCover: Bool = true,
        includeCoverMeta: Bool = true,
        includeAppleMetadata: Bool = false,
        extraTextFileCount: Int = 0,
        coverItemID: String = "cover-image",
        coverHref: String = "cover.jpg",
        coverMediaType: String = "image/jpeg",
        coverProperties: String = "cover-image",
        coverData: Data = Data("cover".utf8),
        language: String = "en",
        packageVersion: String = "3.0",
        spineAttributes: String = "",
        extraMetadataXML: String = "",
        extraManifestXML: String = "",
        extraSpineXML: String = "",
        extraPackageXML: String = "",
        chapterText: String = "<html><body><p>Chapter</p></body></html>",
        extraFiles: [String: Data] = [:]
    ) throws {
        let outputURL = fileURL(relativePath, root: root)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableEPUBFixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workRoot) }

        let opsURL = workRoot.appendingPathComponent("OPS", isDirectory: true)
        let metaURL = workRoot.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: opsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metaURL, withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: workRoot.appendingPathComponent("mimetype"), options: .atomic)
        if includeAppleMetadata {
            try Data("<plist><dict/></plist>".utf8).write(to: workRoot.appendingPathComponent("iTunesMetadata.plist"), options: .atomic)
            try Data("<plist><dict/></plist>".utf8).write(to: workRoot.appendingPathComponent("iTunesMetadata-original.plist"), options: .atomic)
        }
        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8
        ).write(to: metaURL.appendingPathComponent("container.xml"), options: .atomic)
        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="\(packageVersion)" unique-identifier="book-id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="book-id">urn:uuid:fixture</dc:identifier>
                <dc:title>\(title)</dc:title>
                <dc:language>\(language)</dc:language>
                \(includeCover && includeCoverMeta ? #"<meta name="cover" content="\#(coverItemID)"/>"# : "")
                \(extraMetadataXML)
              </metadata>
              <manifest>
                \(includeCover ? #"<item id="\#(coverItemID)" href="\#(coverHref)" media-type="\#(coverMediaType)" properties="\#(coverProperties)"/>"# : "")
                <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
                \(extraManifestXML)
              </manifest>
              <spine\(spineAttributes)>
                <itemref idref="chapter"/>
                \(extraSpineXML)
              </spine>
              \(extraPackageXML)
            </package>
            """.utf8
        ).write(to: opsURL.appendingPathComponent("content.opf"), options: .atomic)
        if includeCover {
            let coverURL = opsURL.appendingPathComponent(coverHref)
            try FileManager.default.createDirectory(
                at: coverURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try coverData.write(to: coverURL, options: .atomic)
        }
        try Data(chapterText.utf8).write(to: opsURL.appendingPathComponent("chapter.xhtml"), options: .atomic)
        for (extraPath, data) in extraFiles {
            let extraURL = workRoot.appendingPathComponent(extraPath)
            try FileManager.default.createDirectory(
                at: extraURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: extraURL, options: .atomic)
        }
        if extraTextFileCount > 0 {
            let extraURL = opsURL.appendingPathComponent("extra", isDirectory: true)
            try FileManager.default.createDirectory(at: extraURL, withIntermediateDirectories: true)
            for index in 0..<extraTextFileCount {
                let name = String(format: "note-%04d.txt", index)
                try Data("extra \(index)".utf8).write(to: extraURL.appendingPathComponent(name), options: .atomic)
            }
        }

        try? FileManager.default.removeItem(at: outputURL)
        try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-X", "-q", "-0", outputURL.path(percentEncoded: false), "mimetype"],
            currentDirectory: workRoot
        )
        try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-X", "-q", "-r", outputURL.path(percentEncoded: false), ".", "-x", "mimetype"],
            currentDirectory: workRoot
        )
    }

    private struct StoredZipEntry {
        var name: String
        var data = Data()
        var externalAttributes: UInt32 = 0
    }

    private func writeStoredZip(entries: [StoredZipEntry], to url: URL) throws {
        var file = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let localOffset = UInt32(file.count)
            let size = UInt32(entry.data.count)

            file.appendLittleEndianUInt32(0x0403_4B50)
            file.appendLittleEndianUInt16(20)
            file.appendLittleEndianUInt16(0)
            file.appendLittleEndianUInt16(0)
            file.appendLittleEndianUInt16(0)
            file.appendLittleEndianUInt16(0)
            file.appendLittleEndianUInt32(0)
            file.appendLittleEndianUInt32(size)
            file.appendLittleEndianUInt32(size)
            file.appendLittleEndianUInt16(UInt16(nameData.count))
            file.appendLittleEndianUInt16(0)
            file.append(nameData)
            file.append(entry.data)

            centralDirectory.appendLittleEndianUInt32(0x0201_4B50)
            centralDirectory.appendLittleEndianUInt16(0x031E)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(0)
            centralDirectory.appendLittleEndianUInt32(size)
            centralDirectory.appendLittleEndianUInt32(size)
            centralDirectory.appendLittleEndianUInt16(UInt16(nameData.count))
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(entry.externalAttributes)
            centralDirectory.appendLittleEndianUInt32(localOffset)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(file.count)
        file.append(centralDirectory)
        file.appendLittleEndianUInt32(0x0605_4B50)
        file.appendLittleEndianUInt16(0)
        file.appendLittleEndianUInt16(0)
        file.appendLittleEndianUInt16(UInt16(entries.count))
        file.appendLittleEndianUInt16(UInt16(entries.count))
        file.appendLittleEndianUInt32(UInt32(centralDirectory.count))
        file.appendLittleEndianUInt32(centralDirectoryOffset)
        file.appendLittleEndianUInt16(0)

        try file.write(to: url, options: .atomic)
    }

    private func fileExists(_ relativePath: String, root: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(relativePath, root: root).path(percentEncoded: false))
    }

    private func stringContents(_ relativePath: String, root: URL) throws -> String {
        try String(contentsOf: fileURL(relativePath, root: root), encoding: .utf8)
    }

    private func jsonObject(_ relativePath: String, root: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL(relativePath, root: root))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func planByChecking(_ itemID: LibraryPlanItem.ID, in plan: LibraryPlan) -> LibraryPlan {
        planByChecking(Set([itemID]), in: plan)
    }

    private func planByChecking(_ itemIDs: Set<LibraryPlanItem.ID>, in plan: LibraryPlan) -> LibraryPlan {
        var checkedPlan = plan
        checkedPlan.groups = checkedPlan.groups.map { group in
            var updatedGroup = group
            updatedGroup.items = updatedGroup.items.map { item in
                guard itemIDs.contains(item.id) else { return item }
                var checkedItem = item
                checkedItem.decision = .checked
                return checkedItem
            }
            return updatedGroup
        }
        return checkedPlan
    }

    private func fileURL(_ relativePath: String, root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }

    private func runProcess(executable: String, arguments: [String], currentDirectory: URL?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "SableLibraryTests.Process",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr]
            )
        }
    }
}

private extension Data {
    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
