//
//  SableCoverSafetyVisionClassifier.swift
//  Sable's Covers
//

import CoreGraphics
import Foundation
#if canImport(CoreML) && canImport(Vision)
import CoreML
import Vision
#endif

nonisolated final class SableCoverSafetyVisionClassifier: @unchecked Sendable {
    static let shared = SableCoverSafetyVisionClassifier()

    struct Prediction: Sendable, Equatable {
        var rating: String
        var confidence: Float
    }

    #if canImport(CoreML) && canImport(Vision)
    private final class BundleToken: NSObject {}

    private let modelLock = NSLock()
    private var cachedModel: VNCoreMLModel?
    private var didAttemptModelLoad = false
    #endif

    private init() {}

    func contentRating(for image: CGImage) -> String? {
        guard let prediction = prediction(for: image) else { return nil }
        return Self.reviewedContentRating(for: prediction)
    }

    static func reviewedContentRating(for prediction: Prediction) -> String {
        if prediction.rating == "safe" {
            return "safe"
        }
        return prediction.confidence >= Self.minimumRaiseConfidence
            ? "suggestive"
            : "safe"
    }

    func prediction(for image: CGImage) -> Prediction? {
        #if canImport(CoreML) && canImport(Vision)
        guard let model = visionModel() else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = (request.results as? [VNClassificationObservation])?
                .first,
              Self.supportedRatings.contains(observation.identifier) else {
            return nil
        }
        return Prediction(
            rating: observation.identifier,
            confidence: observation.confidence
        )
        #else
        return nil
        #endif
    }

    #if canImport(CoreML) && canImport(Vision)
    private func visionModel() -> VNCoreMLModel? {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cachedModel { return cachedModel }
        guard !didAttemptModelLoad else { return nil }
        didAttemptModelLoad = true

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        for bundle in Self.modelResourceBundles {
            if let compiledURL = bundle.url(
                forResource: "SableLibraryCoverSafetyHumanClassifier",
                withExtension: "mlmodelc"
            ),
               let model = try? MLModel(
                   contentsOf: compiledURL,
                   configuration: configuration
               ),
               let visionModel = try? VNCoreMLModel(for: model) {
                cachedModel = visionModel
                return visionModel
            }
        }
        return nil
    }

    private static var modelResourceBundles: [Bundle] {
        var bundles: [Bundle] = [Bundle.main, Bundle(for: BundleToken.self)]
        var seen = Set<String>()
        bundles = bundles.filter {
            seen.insert($0.bundleURL.standardizedFileURL.path).inserted
        }
        return bundles
    }
    #endif

    private static let supportedRatings = Set([
        "safe", "suggestive", "erotica", "pornographic",
    ])
    private static let minimumRaiseConfidence: Float = 0.90
}
