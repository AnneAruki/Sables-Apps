//
//  SableLibrarySubtitleAttachmentPlanner.swift
//  Sable's Library
//

import Foundation

struct SableLibrarySubtitleAttachmentPlanner: Sendable {
    private let subtitleExtensions: Set<String> = [
        "srt",
        "ass",
        "ssa",
        "sub",
        "idx",
        "vtt",
        "smi"
    ]

    func planItems(
        followingVideoMoveFrom currentVideoPath: String,
        to proposedVideoPath: String,
        allItems: [LibraryItem],
        stage: LibraryPipelineStage,
        operation: LibraryPlanOperation,
        requiresReview: Bool,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService,
        reason: String
    ) -> [LibraryPlanItem] {
        let currentVideoParent = parentPath(currentVideoPath)
        let currentVideoBase = baseName(currentVideoPath)
        let proposedVideoParent = parentPath(proposedVideoPath)
        let proposedVideoBase = baseName(proposedVideoPath)
        guard !currentVideoBase.isEmpty, !proposedVideoBase.isEmpty else { return [] }

        return allItems.compactMap { item in
            guard !item.isDirectory,
                  subtitleExtensions.contains(item.url.pathExtension.lowercased()),
                  let subtitleLocation = subtitleLocation(for: item.relativePath, videoParent: currentVideoParent),
                  let suffix = subtitleSuffix(for: item.relativePath, videoBase: currentVideoBase) else {
                return nil
            }

            let extensionSuffix = item.url.pathExtension.lowercased()
            let cleanName = service.sanitizeFilename("\(proposedVideoBase)\(suffix).\(extensionSuffix)")
            let targetParent = subtitleLocation.subfolder.map {
                proposedVideoParent.isEmpty ? $0 : service.joinedRelativePath(proposedVideoParent, $0)
            } ?? proposedVideoParent
            let proposedPath = targetParent.isEmpty ? cleanName : service.joinedRelativePath(targetParent, cleanName)
            guard proposedPath != item.relativePath,
                  proposedPath.lowercased() != item.relativePath.lowercased() else {
                return nil
            }

            let proposedURL = root.appendingPathComponent(proposedPath)
            let hasCollision = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false))
                || plannedDestinations.contains(proposedPath)
            plannedDestinations.insert(proposedPath)

            let needsReview = requiresReview || hasCollision
            let safety: LibraryPlanSafety = hasCollision ? .collision : (requiresReview ? .needsChoice : .reversible)
            return LibraryPlanItem(
                stage: stage,
                operation: operation,
                currentPath: item.relativePath,
                proposedPath: proposedPath,
                reason: hasCollision
                    ? "Subtitle target already exists. Review duplicate handling before applying."
                    : reason,
                confidence: needsReview ? .medium : .high,
                safety: safety,
                decision: needsReview ? .unchecked : .checked,
                requiresReview: needsReview,
                confidenceExplanation: hasCollision
                    ? "Another file already uses the target subtitle name, so this stays out of quiet apply."
                    : "The subtitle basename matches the video exactly; the rename keeps Plex language, forced, SDH, or CC tags after the video title.",
                correctionOptions: [.keepTitle, .custom],
                receipt: "\(item.relativePath) -> \(proposedPath)"
            )
        }
    }

    private func subtitleLocation(for subtitlePath: String, videoParent: String) -> SubtitleLocation? {
        let subtitleParent = parentPath(subtitlePath)
        if subtitleParent == videoParent {
            return SubtitleLocation(subfolder: nil)
        }

        let folderName = lastPathComponent(subtitleParent).lowercased()
        guard folderName == "subs" || folderName == "subtitles",
              parentPath(subtitleParent) == videoParent else {
            return nil
        }
        return SubtitleLocation(subfolder: lastPathComponent(subtitleParent))
    }

    private func subtitleSuffix(for subtitlePath: String, videoBase: String) -> String? {
        let subtitleBase = baseName(subtitlePath)
        let lowerSubtitleBase = subtitleBase.lowercased()
        let lowerVideoBase = videoBase.lowercased()

        if lowerSubtitleBase == lowerVideoBase {
            return ""
        }

        guard lowerSubtitleBase.hasPrefix("\(lowerVideoBase).") else {
            return nil
        }

        let suffixStart = subtitleBase.index(subtitleBase.startIndex, offsetBy: videoBase.count)
        return String(subtitleBase[suffixStart...])
    }

    private func parentPath(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    private func baseName(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private struct SubtitleLocation {
        var subfolder: String?
    }
}
