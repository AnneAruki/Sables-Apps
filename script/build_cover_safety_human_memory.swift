import Foundation

private struct JudgmentExport: Decodable {
    var ruleVersion: String?
    var items: [Judgment]
}

private struct Judgment: Decodable {
    var id: String
    var imageURL: String
    var index: String?
    var language: String?
    var seriesID: String
    var sha256: String
    var sourceURL: String?
    var type: String?
    var rating: String
}

private struct Memory: Encodable {
    var schemaVersion = 1
    var ruleVersions: [String]
    var credit: String
    var items: [Item]
}

private struct Item: Encodable {
    var seriesID: Int
    var imageID: Int?
    var sha256: String
    var sourceURL: String?
    var type: String?
    var index: String?
    var language: String?
    var rating: String
}

private let supportedRatings = Set([
    "safe", "suggestive", "erotica", "pornographic",
])

private enum GeneratorError: LocalizedError {
    case conflictingRating(String)

    var errorDescription: String? {
        switch self {
        case let .conflictingRating(hash):
            "Conflicting human ratings for \(hash)"
        }
    }
}

private func imageID(for judgment: Judgment, seriesID: Int) -> Int? {
    let components = judgment.id.split(separator: "-")
    if components.contains(Substring(String(seriesID))),
       let suffix = components.last,
       let imageID = Int(suffix) {
        return imageID
    }
    guard let url = URL(string: judgment.imageURL),
          url.pathExtension.lowercased() == "jpg" else {
        return nil
    }
    return Int(url.deletingPathExtension().lastPathComponent)
}

@main
private enum BuildHumanMemory {
    static func main() throws {
        guard CommandLine.arguments.count >= 4 else {
            fputs(
                "usage: build_cover_safety_human_memory INPUT.json [INPUT.json ...] OUTPUT.json\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }
        let inputPaths = CommandLine.arguments.dropFirst().dropLast()
        let outputURL = URL(fileURLWithPath: CommandLine.arguments.last!)
        let decoder = JSONDecoder()
        let exports = try inputPaths.map { path in
            try decoder.decode(
                JudgmentExport.self,
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
        }

        var itemsByHash: [String: Item] = [:]
        for judgment in exports.flatMap(\.items) {
            guard let seriesID = Int(judgment.seriesID),
                  supportedRatings.contains(judgment.rating),
                  judgment.sha256.count == 64 else {
                continue
            }
            let item = Item(
                seriesID: seriesID,
                imageID: imageID(for: judgment, seriesID: seriesID),
                sha256: judgment.sha256.lowercased(),
                sourceURL: judgment.sourceURL,
                type: judgment.type,
                index: judgment.index,
                language: judgment.language,
                rating: judgment.rating
            )
            if let existing = itemsByHash[item.sha256],
               existing.rating != item.rating {
                throw GeneratorError.conflictingRating(item.sha256)
            }
            itemsByHash[item.sha256] = item
        }

        let memory = Memory(
            ruleVersions: exports.compactMap(\.ruleVersion).sorted(),
            credit: "Human cover-level safety judgments contributed by the Sable's Library project owner.",
            items: itemsByHash.values.sorted {
                if $0.seriesID != $1.seriesID { return $0.seriesID < $1.seriesID }
                if ($0.imageID ?? Int.max) != ($1.imageID ?? Int.max) {
                    return ($0.imageID ?? Int.max) < ($1.imageID ?? Int.max)
                }
                return $0.sha256 < $1.sha256
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(memory).write(to: outputURL, options: .atomic)
        print("Wrote \(memory.items.count) human cover judgments to \(outputURL.path)")
        print("Image IDs available: \(memory.items.filter { $0.imageID != nil }.count)")
    }
}
