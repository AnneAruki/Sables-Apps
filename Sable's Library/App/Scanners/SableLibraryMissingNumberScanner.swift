//
//  SableLibraryMissingNumberReviewner.swift
//  Sable's Library
//

import Foundation

extension SableLibraryService {
    func missingNumberItems(root: URL, config: SableLibraryConfig) throws -> [LibraryItem] {
        try missingNumberItems(root: root, config: config, cleanupOptions: CleanupOptions(treatPDFsAsBooks: true))
    }

    func missingNumberItems(
        root: URL,
        config: SableLibraryConfig,
        cleanupOptions: CleanupOptions
    ) throws -> [LibraryItem] {
        let items = try enumerateItems(root: root, config: config)
        let readingPaths = Set(bookItems(in: items, root: root, config: config, cleanupOptions: cleanupOptions).map(\.relativePath))
        let regex = try NSRegularExpression(pattern: #"(?i)\b(vol(?:ume)?|ch(?:apter)?)\s*(?=$|[-_.)\]])"#)
        return items.filter { item in
            if Task.isCancelled { return false }
            reportProgress("Checking missing number marker: \(item.relativePath)")
            guard readingPaths.contains(item.relativePath) else { return false }
            let name = item.url.deletingPathExtension().lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            return regex.firstMatch(in: name, range: range) != nil
        }
    }
}
