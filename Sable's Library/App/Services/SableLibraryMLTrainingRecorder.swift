//
//  SableLibraryMLTrainingRecorder.swift
//  Sable's Library
//

import Foundation

private let mlTrainingEventWriteLock = NSLock()

extension SableLibraryConfig.Reports {
    var mlTrainingEventsJSONL: String {
        "_sable_ml_training_events.jsonl"
    }
}

extension SableLibraryService {
    func recordMLTrainingEvent(_ event: SableLibraryMLTrainingEvent, root: URL, config: SableLibraryConfig) {
        mlTrainingEventWriteLock.lock()
        defer { mlTrainingEventWriteLock.unlock() }

        do {
            let directory = reportDirectory(root: root, config: config)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(config.reports.mlTrainingEventsJSONL)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(event)
            let line = String(decoding: data, as: UTF8.self) + "\n"
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: url, options: .atomic)
            }
        } catch {
            reportProgress("ML training note could not be saved: \(error.localizedDescription)")
        }
    }
}
