//
//  SableLibraryPDFTriageClassifier.swift
//  Sable's Library
//

import Foundation

struct SableLibraryPDFTriageClassification: Sendable, Equatable {
    var choice: SableLibraryPDFTriageChoice?
    var confidence: LibraryPlanConfidence
    var explanation: String
    var reviewTags: [String]
}

struct SableLibraryPDFTriageClassifier: Sendable {
    var learningMemory: SableLibraryLearningMemory
    var useLocalLearning: Bool

    init(
        learningMemory: SableLibraryLearningMemory = SableLibraryLearningMemory(),
        useLocalLearning: Bool = false
    ) {
        self.learningMemory = learningMemory
        self.useLocalLearning = useLocalLearning
    }

    func classify(path: String, proposedPath: String?, isWrapperFolder: Bool) -> SableLibraryPDFTriageClassification {
        let text = normalizedText([path, proposedPath ?? ""].joined(separator: " "))
        var documentScore = 0.0
        var bookScore = 0.0
        var evidence: [String] = []
        var tags = ["pdf-triage"]

        addTermEvidence(
            from: text,
            terms: strongDocumentTerms,
            weight: 3,
            label: "document wording",
            score: &documentScore,
            evidence: &evidence
        )
        addTermEvidence(
            from: text,
            terms: mediumDocumentTerms,
            weight: 1.6,
            label: "possible document wording",
            score: &documentScore,
            evidence: &evidence
        )
        addTermEvidence(
            from: text,
            terms: strongBookTerms,
            weight: 3,
            label: "book wording",
            score: &bookScore,
            evidence: &evidence
        )
        addTermEvidence(
            from: text,
            terms: mediumBookTerms,
            weight: 1.5,
            label: "possible book wording",
            score: &bookScore,
            evidence: &evidence
        )

        if containsVolumePattern(text) {
            bookScore += 2.4
            evidence.append("volume/chapter pattern")
        }
        if isWrapperFolder {
            documentScore += 0.4
            tags.append("pdf-wrapper-folder")
            evidence.append("single-PDF folder")
        }

        if useLocalLearning {
            for signal in learningMemory.pdfTriageSignals(path: path, proposedPath: proposedPath) {
                let weight = signal.confidence == .high ? 2.8 : 1.6
                switch signal.choice {
                case .document:
                    documentScore += weight
                case .book:
                    bookScore += weight
                }
                tags.append("learned-pdf-triage")
                evidence.append(signal.detail)
            }
        }

        let classification = resolvedChoice(documentScore: documentScore, bookScore: bookScore)
        switch classification {
        case .document:
            tags.append("likely-document")
            return SableLibraryPDFTriageClassification(
                choice: .document,
                confidence: documentScore >= 5.5 ? .high : .medium,
                explanation: explanation(
                    lead: "Likely document PDF.",
                    documentScore: documentScore,
                    bookScore: bookScore,
                    evidence: evidence
                ),
                reviewTags: tags
            )
        case .book:
            tags.append("likely-book")
            return SableLibraryPDFTriageClassification(
                choice: .book,
                confidence: bookScore >= 5.0 ? .high : .medium,
                explanation: explanation(
                    lead: "Looks book-like. Keep it out of document moves unless you decide otherwise.",
                    documentScore: documentScore,
                    bookScore: bookScore,
                    evidence: evidence
                ),
                reviewTags: tags
            )
        case nil:
            tags.append("unsure-pdf")
            return SableLibraryPDFTriageClassification(
                choice: nil,
                confidence: .low,
                explanation: explanation(
                    lead: "No strong PDF type signal yet.",
                    documentScore: documentScore,
                    bookScore: bookScore,
                    evidence: evidence
                ),
                reviewTags: tags
            )
        }
    }

    private func resolvedChoice(documentScore: Double, bookScore: Double) -> SableLibraryPDFTriageChoice? {
        if documentScore >= 3.2, documentScore >= bookScore + 1.1 {
            return .document
        }
        if bookScore >= 3.0, bookScore >= documentScore + 0.8 {
            return .book
        }
        return nil
    }

    private func explanation(
        lead: String,
        documentScore: Double,
        bookScore: Double,
        evidence: [String]
    ) -> String {
        let evidenceText = evidence.isEmpty
            ? "No strong filename or folder clues were found."
            : Array(evidence.prefix(4)).joined(separator: "; ")
        return "\(lead) Evidence: \(evidenceText). Scores: document \(formatted(documentScore)), book \(formatted(bookScore))."
    }

    private func addTermEvidence(
        from text: String,
        terms: [String],
        weight: Double,
        label: String,
        score: inout Double,
        evidence: inout [String]
    ) {
        let matches = terms.filter { text.contains($0) }
        guard !matches.isEmpty else { return }
        score += Double(matches.count) * weight
        evidence.append("\(label): \(matches.prefix(3).joined(separator: ", "))")
    }

    private func containsVolumePattern(_ text: String) -> Bool {
        let patterns = [
            #"\bchapter\s+\d+\b"#,
            #"\bhoofdstuk\s+\d+\b"#,
            #"\bvol(?:ume)?\s*\d+\b"#,
            #"\bpart\s+\d+\b"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func normalizedText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func formatted(_ score: Double) -> String {
        String(format: "%.1f", score)
    }

    private var strongDocumentTerms: [String] {
        [
            "invoice", "factuur", "receipt", "loonstrook", "belasting", "inkomensverklaring",
            "formulier", "form fillable", "machtigen", "cv ", "resume", "sollicitatie",
            "stagebezoekformulier", "beoordelingsformulier", "proof of participation",
            "tax interview", "order", "plattegrond", "schoolgids", "tarief", "verklaring",
            "payslip", "payroll", "statement", "bank statement", "contract", "certificate",
            "policy", "bill", "insurance", "permit", "application"
        ]
    }

    private var mediumDocumentTerms: [String] {
        [
            "handleiding", "gebruikershandleiding", "kerndoelen", "aanbodsdoelen",
            "verslag", "solution", "onderwijs", "werkplekleren", "adviseur",
            "onderzoeker", "daglijst", "vermoeidheid", "mentale belasting",
            "manual", "guide", "school guide", "syllabus", "worksheet", "lesson plan",
            "government", "municipality", "benefit", "pickup"
        ]
    }

    private var strongBookTerms: [String] {
        [
            "chapter ", "hoofdstuk ", "volume ", " vol ", " light novel", "manga",
            "comic", "novel", "epilogue", "memoirs", "oceanofpdf", "oceanof pdf"
        ]
    }

    private var mediumBookTerms: [String] {
        [
            "dungeons", "dragons", "adventure", "tome", "class", "race",
            "character sheet", "story", "stories", "premium ver", "bookworm",
            "drivethrurpg", "dtrpg", "player", "campaign", "quest"
        ]
    }
}
