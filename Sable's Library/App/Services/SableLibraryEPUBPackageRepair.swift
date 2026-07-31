//
//  SableLibraryEPUBPackageRepair.swift
//  Sable's Library
//

import Foundation

struct LibraryEpubPackageRepairApplyResult: Sendable {
    let applied: [String]
    let skipped: [String]
    let failed: [String: String]
    let report: String
    let changedFiles: Bool
}

extension SableLibraryService {
    func applyEpubPackageRepairs(
        root: URL,
        paths: [String],
        reportTitle: String,
        reportName: String
    ) async -> LibraryEpubPackageRepairApplyResult {
        let config = currentConfig()
        var applied: [String] = []
        var skipped: [String] = []
        var failed: [String: String] = [:]

        let orderedPaths = paths.sorted()
        let totalCount = orderedPaths.count
        let startedAt = Date()

        for (index, path) in orderedPaths.enumerated() {
            let completedCount = index + 1
            do {
                try checkForCancellation()
                let timing = SableLibraryWorkTiming.summary(
                    startedAt: startedAt,
                    completedCount: index,
                    totalCount: totalCount,
                    unit: "EPUB"
                )
                reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: "Applying EPUB repairs",
                    message: "Repairing EPUB package \(completedCount) of \(totalCount). \(timing) Current: \(path)",
                    completedUnitCount: index,
                    totalUnitCount: totalCount
                ))
                reportProgress("Repairing EPUB package: \(path)")

                let url = root.appendingPathComponent(path)
                let outcome = try repairEpubPackage(at: url)
                switch outcome {
                case .applied:
                    applied.append(path)
                case .skipped(let reason):
                    skipped.append("\(path): \(reason)")
                }
            } catch {
                failed[path] = error.localizedDescription
            }

            let timing = SableLibraryWorkTiming.summary(
                startedAt: startedAt,
                completedCount: completedCount,
                totalCount: totalCount,
                unit: "EPUB"
            )
            reportProgressSnapshot(SableLibraryProgressSnapshot(
                title: "Applying EPUB repairs",
                message: "Checked EPUB package \(completedCount) of \(totalCount). \(timing) Last finished: \(path)",
                completedUnitCount: completedCount,
                totalUnitCount: totalCount
            ))
        }

        if !applied.isEmpty {
            invalidateScanCache(for: root)
        }

        let report = epubPackageRepairReport(
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

        return LibraryEpubPackageRepairApplyResult(
            applied: applied,
            skipped: skipped,
            failed: failed,
            report: report,
            changedFiles: !applied.isEmpty
        )
    }

    private enum EpubPackageRepairOutcome {
        case applied
        case skipped(String)
    }

    private func repairEpubPackage(at packageURL: URL) throws -> EpubPackageRepairOutcome {
        let packagePath = packageURL.path(percentEncoded: false)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: packagePath, isDirectory: &isDirectory) else {
            return .skipped("The source path no longer exists.")
        }
        guard isDirectory.boolValue else {
            return .skipped("Already a normal EPUB file.")
        }

        try SableLibraryEPUBPackageArchiver.preflightPackage(at: packageURL)

        let token = UUID().uuidString
        let tempURL = packageURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(packageURL.lastPathComponent).repack-\(token).tmp")
        let backupURL = packageURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(packageURL.lastPathComponent).expanded-backup-\(token)")

        do {
            try SableLibraryEPUBPackageArchiver.writeZip(from: packageURL, to: tempURL)
            try SableLibraryEPUBPackageArchiver.validateZip(at: tempURL)

            try fileManager.moveItem(at: packageURL, to: backupURL)
            do {
                try fileManager.moveItem(at: tempURL, to: packageURL)
                try SableLibraryEPUBPackageArchiver.validateZip(at: packageURL)
                try fileManager.removeItem(at: backupURL)
            } catch {
                try? fileManager.removeItem(at: packageURL)
                if fileManager.fileExists(atPath: backupURL.path(percentEncoded: false)) {
                    try? fileManager.moveItem(at: backupURL, to: packageURL)
                }
                throw error
            }

            return .applied
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private func epubPackageRepairReport(
        title: String,
        applied: [String],
        skipped: [String],
        failed: [String: String]
    ) -> String {
        var lines = [
            title,
            String(repeating: "=", count: title.count),
            "",
            "Repaired EPUB packages: \(applied.count)",
            "Skipped: \(skipped.count)",
            "Failed: \(failed.count)"
        ]

        if !applied.isEmpty {
            lines.append("\nRepaired:")
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
}

private enum SableLibraryEPUBPackageArchiver {
    private static let mimetypeEntryName = "mimetype"
    private static let containerEntryName = "META-INF/container.xml"
    private static let mimetypeData = Data("application/epub+zip".utf8)
    private static let utf8Flag: UInt16 = 0x0800
    private static let storedMethod: UInt16 = 0

    struct ZipEntry {
        let name: String
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let method: UInt16
        let localOffset: UInt32
    }

    static func preflightPackage(at packageURL: URL) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: packageURL.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw EPUBPackageRepairError.notExpandedPackage
        }

        let mimetypeURL = packageURL.appendingPathComponent(mimetypeEntryName)
        let containerURL = packageURL.appendingPathComponent(containerEntryName)
        guard let rawMimetype = try? Data(contentsOf: mimetypeURL),
              rawMimetype.trimmedASCIIWhitespace == mimetypeData else {
            throw EPUBPackageRepairError.invalidMimetype
        }
        guard FileManager.default.fileExists(atPath: containerURL.path(percentEncoded: false)) else {
            throw EPUBPackageRepairError.missingContainer
        }
    }

    static func writeZip(from packageURL: URL, to outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let entries = try packageEntries(in: packageURL)
        guard entries.contains(where: { $0.entryName == containerEntryName }) else {
            throw EPUBPackageRepairError.missingContainer
        }

        FileManager.default.createFile(atPath: outputURL.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        var centralDirectory = Data()
        var centralRecords: [ZipEntry] = []

        try writeEntry(
            name: mimetypeEntryName,
            data: mimetypeData,
            handle: handle,
            centralRecords: &centralRecords,
            centralDirectory: &centralDirectory
        )

        for entry in entries where entry.entryName != mimetypeEntryName {
            let data = try Data(contentsOf: entry.url)
            try writeEntry(
                name: entry.entryName,
                data: data,
                handle: handle,
                centralRecords: &centralRecords,
                centralDirectory: &centralDirectory
            )
        }

        let centralOffset = try checkedUInt32(handle.offset(), label: "central directory offset")
        try handle.write(contentsOf: centralDirectory)
        let centralSize = try checkedUInt32(UInt64(centralDirectory.count), label: "central directory size")

        var end = Data()
        end.appendLittleEndianUInt32(0x06054b50)
        end.appendLittleEndianUInt16(0)
        end.appendLittleEndianUInt16(0)
        end.appendLittleEndianUInt16(try checkedUInt16(centralRecords.count, label: "entry count"))
        end.appendLittleEndianUInt16(try checkedUInt16(centralRecords.count, label: "entry count"))
        end.appendLittleEndianUInt32(centralSize)
        end.appendLittleEndianUInt32(centralOffset)
        end.appendLittleEndianUInt16(0)
        try handle.write(contentsOf: end)
    }

    static func validateZip(at zipURL: URL) throws {
        let entries = try readCentralDirectory(at: zipURL)
        guard let first = entries.first, first.name == mimetypeEntryName else {
            throw EPUBPackageRepairError.invalidZip("mimetype is not the first entry")
        }
        guard entries.contains(where: { $0.name == containerEntryName }) else {
            throw EPUBPackageRepairError.invalidZip("META-INF/container.xml is missing")
        }

        let handle = try FileHandle(forReadingFrom: zipURL)
        defer { try? handle.close() }

        for entry in entries {
            let data = try readStoredEntry(entry, from: handle)
            guard CRC32.checksum(data) == entry.crc else {
                throw EPUBPackageRepairError.invalidZip("CRC check failed for \(entry.name)")
            }
            if entry.name == mimetypeEntryName, data != mimetypeData {
                throw EPUBPackageRepairError.invalidZip("mimetype content is not exact")
            }
        }
    }

    private struct PackageEntry {
        let entryName: String
        let url: URL
    }

    private static func packageEntries(in packageURL: URL) throws -> [PackageEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw EPUBPackageRepairError.notExpandedPackage
        }

        let rootPath = packageURL.standardizedFileURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var entries: [PackageEntry] = []

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard path.hasPrefix(rootPrefix) else { continue }
            let relative = String(path.dropFirst(rootPrefix.count))
            guard !relative.isEmpty else { continue }
            entries.append(PackageEntry(entryName: relative, url: url))
        }

        return entries.sorted { lhs, rhs in
            if lhs.entryName == mimetypeEntryName { return true }
            if rhs.entryName == mimetypeEntryName { return false }
            return lhs.entryName.localizedStandardCompare(rhs.entryName) == .orderedAscending
        }
    }

    private static func writeEntry(
        name: String,
        data: Data,
        handle: FileHandle,
        centralRecords: inout [ZipEntry],
        centralDirectory: inout Data
    ) throws {
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(data)
        let size = try checkedUInt32(UInt64(data.count), label: "\(name) size")
        let localOffset = try checkedUInt32(handle.offset(), label: "\(name) offset")

        var local = Data()
        local.appendLittleEndianUInt32(0x04034b50)
        local.appendLittleEndianUInt16(20)
        local.appendLittleEndianUInt16(utf8Flag)
        local.appendLittleEndianUInt16(storedMethod)
        local.appendLittleEndianUInt16(0)
        local.appendLittleEndianUInt16(0)
        local.appendLittleEndianUInt32(crc)
        local.appendLittleEndianUInt32(size)
        local.appendLittleEndianUInt32(size)
        local.appendLittleEndianUInt16(try checkedUInt16(nameData.count, label: "\(name) name length"))
        local.appendLittleEndianUInt16(0)
        local.append(nameData)

        try handle.write(contentsOf: local)
        try handle.write(contentsOf: data)

        var central = Data()
        central.appendLittleEndianUInt32(0x02014b50)
        central.appendLittleEndianUInt16(20)
        central.appendLittleEndianUInt16(20)
        central.appendLittleEndianUInt16(utf8Flag)
        central.appendLittleEndianUInt16(storedMethod)
        central.appendLittleEndianUInt16(0)
        central.appendLittleEndianUInt16(0)
        central.appendLittleEndianUInt32(crc)
        central.appendLittleEndianUInt32(size)
        central.appendLittleEndianUInt32(size)
        central.appendLittleEndianUInt16(try checkedUInt16(nameData.count, label: "\(name) name length"))
        central.appendLittleEndianUInt16(0)
        central.appendLittleEndianUInt16(0)
        central.appendLittleEndianUInt16(0)
        central.appendLittleEndianUInt16(0)
        central.appendLittleEndianUInt32(0)
        central.appendLittleEndianUInt32(localOffset)
        central.append(nameData)
        centralDirectory.append(central)

        centralRecords.append(
            ZipEntry(
                name: name,
                crc: crc,
                compressedSize: size,
                uncompressedSize: size,
                method: storedMethod,
                localOffset: localOffset
            )
        )
    }

    private static func readCentralDirectory(at zipURL: URL) throws -> [ZipEntry] {
        let handle = try FileHandle(forReadingFrom: zipURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else {
            throw EPUBPackageRepairError.invalidZip("file is too small")
        }

        let tailSize = min(Int(fileSize), 65_557)
        try handle.seek(toOffset: fileSize - UInt64(tailSize))
        let tail = handle.readData(ofLength: tailSize)
        guard let eocdOffset = tail.lastRange(of: Data([0x50, 0x4b, 0x05, 0x06]))?.lowerBound else {
            throw EPUBPackageRepairError.invalidZip("end of central directory is missing")
        }

        let entryCount = Int(try tail.littleEndianUInt16(at: eocdOffset + 10))
        let centralSize = Int(try tail.littleEndianUInt32(at: eocdOffset + 12))
        let centralOffset = UInt64(try tail.littleEndianUInt32(at: eocdOffset + 16))
        guard centralOffset + UInt64(centralSize) <= fileSize else {
            throw EPUBPackageRepairError.invalidZip("central directory points outside the file")
        }

        try handle.seek(toOffset: centralOffset)
        let central = handle.readData(ofLength: centralSize)
        guard central.count == centralSize else {
            throw EPUBPackageRepairError.invalidZip("central directory could not be read")
        }

        var entries: [ZipEntry] = []
        var offset = 0
        while offset < central.count {
            guard offset + 46 <= central.count,
                  try central.littleEndianUInt32(at: offset) == 0x02014b50 else {
                throw EPUBPackageRepairError.invalidZip("central directory entry is malformed")
            }

            let method = try central.littleEndianUInt16(at: offset + 10)
            let crc = try central.littleEndianUInt32(at: offset + 16)
            let compressedSize = try central.littleEndianUInt32(at: offset + 20)
            let uncompressedSize = try central.littleEndianUInt32(at: offset + 24)
            let nameLength = Int(try central.littleEndianUInt16(at: offset + 28))
            let extraLength = Int(try central.littleEndianUInt16(at: offset + 30))
            let commentLength = Int(try central.littleEndianUInt16(at: offset + 32))
            let localOffset = try central.littleEndianUInt32(at: offset + 42)
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= central.count,
                  let name = String(data: central[nameStart..<nameEnd], encoding: .utf8) else {
                throw EPUBPackageRepairError.invalidZip("entry name is malformed")
            }

            entries.append(
                ZipEntry(
                    name: name,
                    crc: crc,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    method: method,
                    localOffset: localOffset
                )
            )
            offset = nameEnd + extraLength + commentLength
        }

        guard entries.count == entryCount else {
            throw EPUBPackageRepairError.invalidZip("central directory count mismatch")
        }
        return entries
    }

    private static func readStoredEntry(_ entry: ZipEntry, from handle: FileHandle) throws -> Data {
        guard entry.method == storedMethod else {
            throw EPUBPackageRepairError.invalidZip("\(entry.name) uses unsupported compression")
        }

        try handle.seek(toOffset: UInt64(entry.localOffset))
        let header = handle.readData(ofLength: 30)
        guard header.count == 30,
              try header.littleEndianUInt32(at: 0) == 0x04034b50 else {
            throw EPUBPackageRepairError.invalidZip("\(entry.name) local header is missing")
        }

        let nameLength = UInt64(try header.littleEndianUInt16(at: 26))
        let extraLength = UInt64(try header.littleEndianUInt16(at: 28))
        try handle.seek(toOffset: UInt64(entry.localOffset) + 30 + nameLength + extraLength)
        let data = handle.readData(ofLength: Int(entry.compressedSize))
        guard data.count == Int(entry.compressedSize),
              data.count == Int(entry.uncompressedSize) else {
            throw EPUBPackageRepairError.invalidZip("\(entry.name) size mismatch")
        }
        return data
    }

    private static func checkedUInt16(_ value: Int, label: String) throws -> UInt16 {
        guard value <= Int(UInt16.max) else { throw EPUBPackageRepairError.sizeLimit(label) }
        return UInt16(value)
    }

    private static func checkedUInt32(_ value: UInt64, label: String) throws -> UInt32 {
        guard value <= UInt64(UInt32.max) else { throw EPUBPackageRepairError.sizeLimit(label) }
        return UInt32(value)
    }
}

private enum EPUBPackageRepairError: LocalizedError {
    case notExpandedPackage
    case invalidMimetype
    case missingContainer
    case invalidZip(String)
    case sizeLimit(String)

    var errorDescription: String? {
        switch self {
        case .notExpandedPackage:
            "This is not an expanded EPUB package."
        case .invalidMimetype:
            "The EPUB package does not have a valid mimetype marker."
        case .missingContainer:
            "The EPUB package is missing META-INF/container.xml."
        case .invalidZip(let detail):
            "The repaired EPUB did not pass validation: \(detail)."
        case .sizeLimit(let label):
            "The EPUB is too large for the built-in ZIP repair at \(label)."
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    var trimmedASCIIWhitespace: Data {
        var start = startIndex
        var end = endIndex
        while start < end, self[start].isASCIIWhitespace {
            start = index(after: start)
        }
        while end > start {
            let previous = index(before: end)
            guard self[previous].isASCIIWhitespace else { break }
            end = previous
        }
        return self[start..<end]
    }

    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    func littleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else {
            throw EPUBPackageRepairError.invalidZip("unexpected end of data")
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw EPUBPackageRepairError.invalidZip("unexpected end of data")
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x09 || self == 0x0a || self == 0x0d || self == 0x20
    }
}
