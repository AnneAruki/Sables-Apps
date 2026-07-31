//
//  SableLibraryFileOperations.swift
//  Sable's Library
//

import Foundation

struct LibraryItem: Sendable {
    let url: URL
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let fileSize: Int64
    let modificationDate: Date?
}

struct PlannedMove: Codable, Sendable, Identifiable, Hashable {
    var id: String { "\(fromPath)->\(toPath)" }
    let reason: String
    let fromPath: String
    let toPath: String
}

struct LibraryFileMoveApplyResult: Sendable {
    let applied: [PlannedMove]
    let skipped: [String]
    let report: String
    let changedFiles: Bool
}

struct LibraryEmptyFolderCleanupApplyResult: Sendable {
    let removed: [String]
    let skipped: [String]
    let report: String
}

extension PlannedMove {
    static let manualNameCollisionReason = "manual review: name collision"
    static let manualFolderMergeReason = "manual review: merge folder into existing"
    static let duplicateReviewReason = "manual review: duplicate move aside"
    static let volumeWrapperFolderReason = "cleanup review: collapse volume wrapper folder"
    static let rawVideoNumberedWrapperReason = "manual review: collapse numbered video wrapper"
    static let rawUpdateFolderReason = "cleanup review: move update into existing series folder"

    var needsManualReview: Bool {
        reason.hasPrefix("manual review")
    }

    var toPathLooksLikeCollision: Bool {
        toPath.contains(" 2.") || toPath.hasSuffix(" 2")
    }
}

struct UndoPlan: Codable, Sendable {
    let createdAt: Date
    let moves: [PlannedMove]
}
