//
//  SableMangaBakaCoverClient.swift
//  Sable's Covers
//

import CoreGraphics
import Foundation
import ImageIO
#if canImport(Vision)
import Vision
#endif

nonisolated enum SableMangaBakaCoverClientError: LocalizedError, Sendable {
    case invalidURL
    case missingToken
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(String)
    case noChanges
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Sable could not build a valid MangaBaka request."
        case .missingToken:
            return "Add your MangaBaka personal access token first."
        case .invalidResponse:
            return "MangaBaka returned an unreadable response."
        case .server(let status, let message):
            return "MangaBaka returned \(status): \(message)"
        case .decoding(let message):
            return "Sable could not read MangaBaka's response: \(message)"
        case .noChanges:
            return "The proposed cover set already matches MangaBaka."
        case .timedOut:
            return "MangaBaka did not finish the request within 30 seconds. Nothing was submitted; try the preview again later."
        }
    }
}

actor SableMangaBakaCoverClient {
    private let apiBaseURL = URL(string: "https://api.mangabaka.org")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
        encoder.outputFormatting = [.sortedKeys]
    }

    func searchSeries(_ query: String) async throws -> [SableMangaBakaSeriesSummary] {
        let page = try await browseSeries(
            query: query,
            publisher: nil,
            mediaType: nil,
            page: 1,
            limit: 20,
            sortBy: "relevance_desc"
        )
        return page.series
    }

    func browseSeries(
        query: String,
        publisher: String?,
        mediaType: String?,
        isLicensed: Bool? = nil,
        page: Int,
        limit: Int = 25,
        sortBy: String = "name_asc"
    ) async throws -> SableMangaBakaSeriesPage {
        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("v1/series/search"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "sort_by", value: sortBy)
        ]
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPublisher = publisher?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanMediaType = mediaType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        queryItems[0] = URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))
        if !cleanQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: cleanQuery))
        }
        if !cleanPublisher.isEmpty {
            queryItems.append(URLQueryItem(name: "publisher", value: cleanPublisher))
        }
        if !cleanMediaType.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: cleanMediaType))
        }
        if let isLicensed {
            queryItems.append(
                URLQueryItem(
                    name: "is_licensed",
                    value: isLicensed ? "true" : "false"
                )
            )
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SableMangaBakaCoverClientError.invalidURL
        }
        let response: SearchEnvelope = try await sendPublic(
            URLRequest(url: url),
            retrySeed: page
        )
        return SableMangaBakaSeriesPage(
            series: response.data,
            totalCount: response.pagination?.count ?? response.data.count,
            page: response.pagination?.page ?? page,
            limit: response.pagination?.limit ?? limit,
            hasNextPage: response.pagination?.next != nil,
            hasPreviousPage: response.pagination?.previous != nil
        )
    }

    func series(id: Int) async throws -> SableMangaBakaSeriesSummary {
        let url = apiBaseURL.appendingPathComponent("v1/series/\(id)")
        let response: SeriesEnvelope = try await sendPublic(
            URLRequest(url: url),
            retrySeed: id
        )
        return response.data
    }

    func relatedSeries(
        seriesID: Int
    ) async throws -> [SableMangaBakaRelatedSeriesSummary] {
        let selectedSeries = try await series(id: seriesID)
        let references = Array(selectedSeries.relationshipReferences.prefix(20))
        guard !references.isEmpty else { return [] }

        return await withTaskGroup(
            of: (Int, SableMangaBakaRelatedSeriesSummary?).self
        ) { group in
            var nextIndex = 0
            let initialRequestCount = min(4, references.count)

            for _ in 0..<initialRequestCount {
                let index = nextIndex
                let reference = references[index]
                nextIndex += 1
                group.addTask { [self] in
                    let summary = try? await series(id: reference.seriesID)
                    return (
                        index,
                        summary.map {
                            SableMangaBakaRelatedSeriesSummary(
                                relationType: reference.relationType,
                                series: $0
                            )
                        }
                    )
                }
            }

            var loaded: [(Int, SableMangaBakaRelatedSeriesSummary)] = []
            for await (index, result) in group {
                if let result {
                    loaded.append((index, result))
                }
                guard nextIndex < references.count else { continue }

                let queuedIndex = nextIndex
                let reference = references[queuedIndex]
                nextIndex += 1
                group.addTask { [self] in
                    let summary = try? await series(id: reference.seriesID)
                    return (
                        queuedIndex,
                        summary.map {
                            SableMangaBakaRelatedSeriesSummary(
                                relationType: reference.relationType,
                                series: $0
                            )
                        }
                    )
                }
            }

            return loaded
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    func publicVolumeCoverStats(seriesID: Int) async throws -> SableMangaBakaPublicCoverStats {
        var page = 1
        var totalCount = 0
        var languages = Set<String>()
        var volumeCovers: [SableMangaBakaPublicCoverImage] = []

        while true {
            let response = try await publicImagesPage(
                seriesID: seriesID,
                type: "volume",
                page: page,
                limit: 50
            )
            totalCount = max(totalCount, response.pagination.count)
            languages.formUnion(response.availableLanguages)
            volumeCovers.append(contentsOf: response.data.map(\.publicCoverImage))
            guard response.pagination.next != nil,
                  !response.data.isEmpty else {
                break
            }
            page += 1
        }

        return SableMangaBakaPublicCoverStats(
            volumeCoverCount: max(totalCount, volumeCovers.count),
            availableLanguages: languages.sorted(),
            volumeCovers: volumeCovers
        )
    }

    func publicExpectedMainVolumeCount(
        seriesID: Int,
        language: String
    ) async throws -> Int? {
        let normalizedLanguage = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var page = 1
        var highestSequence = 0

        while true {
            let response = try await publicWorksPage(
                seriesID: seriesID,
                page: page,
                limit: 50
            )
            for work in response.data where work.countType == "main" {
                let licensedCollections = (work.collections ?? []).filter {
                    $0.licensed == true
                        && $0.language?.iso
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased() == normalizedLanguage
                }
                if let collectionCount = licensedCollections.compactMap({
                    $0.countMain.flatMap(Self.positiveWholeNumber)
                }).max() {
                    return collectionCount
                }
                if !licensedCollections.isEmpty,
                   let sequence = work.sequenceNumeric.flatMap(Self.positiveWholeNumber) {
                    highestSequence = max(highestSequence, sequence)
                }
            }
            guard response.pagination.next != nil,
                  !response.data.isEmpty else {
                break
            }
            page += 1
        }
        return highestSequence > 0 ? highestSequence : nil
    }

    func coverSnapshot(seriesID: Int, token: String) async throws -> SableMangaBakaCoverSnapshot {
        try await coverInventory(seriesID: seriesID, token: token).snapshot
    }

    func accountProfile(
        token: String
    ) async throws -> SableMangaBakaAccountProfile {
        let trimmedToken = try validatedToken(token)
        let url = apiBaseURL.appendingPathComponent("v1/my/profile")
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let response: ProfileEnvelope = try await send(
            request,
            token: trimmedToken
        )
        return response.data
    }

    func coverInventory(
        seriesID: Int,
        token: String
    ) async throws -> SableMangaBakaCoverInventory {
        let trimmedToken = try validatedToken(token)
        let url = apiBaseURL.appendingPathComponent("v0/my/submissions/series-images/\(seriesID)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let response: SnapshotEnvelope = try await send(request, token: trimmedToken)
        var snapshot = SableMangaBakaCoverSnapshot(
            seriesID: seriesID,
            images: response.data.data.images,
            version: response.data.version
        )
        let liveImages = (try? await publicCoverImages(seriesID: seriesID)) ?? []
        if !liveImages.isEmpty {
            snapshot.images = Self.hydratingPreviewURLs(
                snapshot.images,
                from: liveImages
            )
        }
        return SableMangaBakaCoverInventory(
            snapshot: snapshot.normalizedForSubmission(),
            liveImages: liveImages.map(\.publicCoverImage)
        )
    }

    private func publicCoverImages(
        seriesID: Int
    ) async throws -> [SableMangaBakaPublicImageRecord] {
        var page = 1
        var images: [SableMangaBakaPublicImageRecord] = []
        while true {
            let response = try await publicImagesPage(
                seriesID: seriesID,
                type: nil,
                page: page,
                limit: 50
            )
            images.append(contentsOf: response.data)
            guard response.pagination.next != nil else { return images }
            page += 1
        }
    }

    private func publicImagesPage(
        seriesID: Int,
        type: String?,
        page: Int,
        limit: Int
    ) async throws -> PublicImagesEnvelope {
        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("v1/series/\(seriesID)/images"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        if let type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SableMangaBakaCoverClientError.invalidURL
        }
        return try await sendPublic(
            URLRequest(url: url),
            retrySeed: seriesID + page
        )
    }

    private func publicWorksPage(
        seriesID: Int,
        page: Int,
        limit: Int
    ) async throws -> PublicWorksEnvelope {
        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("v1/series/\(seriesID)/works"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        guard let url = components?.url else {
            throw SableMangaBakaCoverClientError.invalidURL
        }
        return try await sendPublic(
            URLRequest(url: url),
            retrySeed: seriesID + page
        )
    }

    private static func positiveWholeNumber(_ value: Double) -> Int? {
        let rounded = value.rounded()
        guard rounded >= 1, abs(value - rounded) < 0.001 else { return nil }
        return Int(rounded)
    }

    private static func hydratingPreviewURLs(
        _ editableImages: [SableMangaBakaCoverImage],
        from liveImages: [SableMangaBakaPublicImageRecord]
    ) -> [SableMangaBakaCoverImage] {
        let liveByID = liveImages.reduce(into: [Int: String]()) {
            values, image in
            values[image.id] = values[image.id] ?? image.rawURL
        }
        var liveBySlot = Dictionary(grouping: liveImages) {
            publicImageSlot(
                language: $0.language,
                type: $0.type,
                indexNumeric: $0.indexNumeric
            )
        }

        return editableImages.map { editable in
            var hydrated = editable
            if let id = editable.id, let liveURL = liveByID[id] {
                hydrated.previewURL = liveURL
                return hydrated
            }
            let slot = publicImageSlot(
                language: editable.language,
                type: editable.type,
                indexNumeric: editable.indexNumeric
            )
            if var matches = liveBySlot[slot], !matches.isEmpty {
                hydrated.previewURL = matches.removeFirst().rawURL
                liveBySlot[slot] = matches
            }
            return hydrated
        }
    }

    private static func publicImageSlot(
        language: String,
        type: String,
        indexNumeric: Double
    ) -> String {
        "\(language.lowercased())|\(type.lowercased())|\(indexNumeric)"
    }

    func preview(
        snapshot: SableMangaBakaCoverSnapshot,
        token: String
    ) async throws -> SableMangaBakaSubmissionPreview {
        let trimmedToken = try validatedToken(token)
        let normalized = snapshot.normalizedForSubmission()
        let issues = normalized.validationIssues()
        if !issues.isEmpty {
            throw SableMangaBakaCoverClientError.server(
                status: 400,
                message: issues.joined(separator: " ")
            )
        }

        var request = try makeRequest(
            path: "v0/my/submissions/series-images/\(snapshot.seriesID)/preview",
            method: "POST",
            body: PreviewBody(
                data: SeriesImagesData(images: normalized.images),
                version: normalized.version
            )
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: PreviewEnvelope = try await send(request, token: trimmedToken)
        return SableMangaBakaSubmissionPreview(
            hasChanges: response.data.hasChanges,
            changes: response.data.changes
        )
    }

    func submit(
        snapshot: SableMangaBakaCoverSnapshot,
        note: String,
        mode: SableMangaBakaSaveMode,
        token: String
    ) async throws -> SableMangaBakaSubmissionResult {
        let trimmedToken = try validatedToken(token)
        let normalized = snapshot.normalizedForSubmission()
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNote.isEmpty else {
            throw SableMangaBakaCoverClientError.server(
                status: 400,
                message: "Describe what the cover correction changes."
            )
        }

        var request = try makeRequest(
            path: "v0/my/submissions/series-images/\(snapshot.seriesID)",
            method: "POST",
            body: SaveBody(
                data: SeriesImagesData(images: normalized.images),
                version: normalized.version,
                userNote: cleanNote,
                saveMode: mode.rawValue
            )
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: SubmissionEnvelope = try await send(request, token: trimmedToken)
        return SableMangaBakaSubmissionResult(
            submissionID: response.data.submissionID,
            status: response.data.status,
            changes: response.data.changes
        )
    }

    func downloadImages(
        _ images: [SableMangaBakaCoverImage],
        seriesID: Int,
        destination: URL
    ) async -> SableMangaBakaDownloadResult {
        let batches = stride(from: 0, to: images.count, by: 4).map {
            Array(images[$0..<min($0 + 4, images.count)])
        }
        var saved: [String] = []
        var skipped: [String] = []
        var failed: [String] = []

        for batch in batches {
            await withTaskGroup(of: DownloadOutcome.self) { group in
                for image in batch {
                    group.addTask {
                        await Self.download(
                            image: image,
                            seriesID: seriesID,
                            destination: destination
                        )
                    }
                }
                for await outcome in group {
                    switch outcome {
                    case .saved(let path):
                        saved.append(path)
                    case .skipped(let path):
                        skipped.append(path)
                    case .failed(let message):
                        failed.append(message)
                    }
                }
            }
        }

        return SableMangaBakaDownloadResult(
            saved: saved.sorted(),
            skipped: skipped.sorted(),
            failed: failed.sorted()
        )
    }

    private func validatedToken(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SableMangaBakaCoverClientError.missingToken
        }
        return trimmed
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) throws -> URLRequest {
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func send<Response: Decodable>(
        _ originalRequest: URLRequest,
        token: String?
    ) async throws -> Response {
        var request = originalRequest
        if let token {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
        }

        let first = try await perform(request)
        if let token,
           let response = first.1 as? HTTPURLResponse,
           response.statusCode == 401 {
            var bearerRequest = originalRequest
            bearerRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let second = try await perform(bearerRequest)
            return try decode(second.0, response: second.1)
        }
        return try decode(first.0, response: first.1)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw SableMangaBakaCoverClientError.timedOut
            default:
                throw error
            }
        }
    }

    private func sendPublic<Response: Decodable>(
        _ request: URLRequest,
        retrySeed: Int
    ) async throws -> Response {
        for attempt in 0..<4 {
            do {
                return try await send(request, token: nil)
            } catch let error as SableMangaBakaCoverClientError {
                guard case .server(let status, _) = error,
                      [429, 502, 503, 504].contains(status),
                      attempt < 3 else {
                    throw error
                }
                let delay = UInt64(
                    500
                        + (attempt * 850)
                        + abs(retrySeed % 250)
                )
                try await Task.sleep(nanoseconds: delay * 1_000_000)
            }
        }

        throw SableMangaBakaCoverClientError.invalidResponse
    }

    private func decode<Response: Decodable>(
        _ data: Data,
        response: URLResponse
    ) throws -> Response {
        guard let http = response as? HTTPURLResponse else {
            throw SableMangaBakaCoverClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SableMangaBakaCoverClientError.server(
                status: http.statusCode,
                message: message
            )
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SableMangaBakaCoverClientError.decoding(error.localizedDescription)
        }
    }

    private static func download(
        image: SableMangaBakaCoverImage,
        seriesID: Int,
        destination: URL
    ) async -> DownloadOutcome {
        guard let url = image.imageURL else {
            return .failed("Invalid cover URL: \(image.url)")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  !data.isEmpty else {
                return .failed("Download failed: \(image.url)")
            }
            let pathExtension = preferredExtension(
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                url: url
            )
            let filename = downloadFilename(
                image: image,
                seriesID: seriesID,
                pathExtension: pathExtension
            )
            let fileURL = destination.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                return .skipped(fileURL.path(percentEncoded: false))
            }
            try data.write(to: fileURL, options: [.atomic])
            return .saved(fileURL.path(percentEncoded: false))
        } catch {
            return .failed("\(image.url): \(error.localizedDescription)")
        }
    }

    private static func preferredExtension(contentType: String?, url: URL) -> String {
        switch contentType?.lowercased() {
        case let value? where value.contains("png"):
            return "png"
        case let value? where value.contains("webp"):
            return "webp"
        case let value? where value.contains("avif"):
            return "avif"
        case let value? where value.contains("jpeg") || value.contains("jpg"):
            return "jpg"
        default:
            let value = url.pathExtension.lowercased()
            return ["jpg", "jpeg", "png", "webp", "avif"].contains(value) ? value : "jpg"
        }
    }

    private static func downloadFilename(
        image: SableMangaBakaCoverImage,
        seriesID: Int,
        pathExtension: String
    ) -> String {
        let index = image.volumeLabel
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let type = image.type.replacingOccurrences(of: "_", with: "-")
        return "MB-\(seriesID)-\(image.language)-\(type)-\(index).\(pathExtension)"
    }
}

nonisolated enum SableAudibleCatalogClientError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case server(status: Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Audible search could not be prepared."
        case .invalidResponse:
            "Audible returned an unreadable response."
        case .server(let status):
            "Audible returned \(status)."
        case .decoding(let message):
            "Audible results could not be read: \(message)"
        }
    }
}

nonisolated struct SableAudibleCatalogClient: Sendable {
    struct SeriesEntry: Decodable, Sendable, Equatable {
        var asin: String
        var sequence: String?
        var title: String
        var url: String?
    }

    struct Product: Decodable, Sendable, Equatable {
        var asin: String
        var title: String
        var language: String?
        var productImages: [String: String]?
        var series: [SeriesEntry]?

        enum CodingKeys: String, CodingKey {
            case asin
            case title
            case language
            case productImages = "product_images"
            case series
        }

        var preferredCoverURL: String? {
            productImages?
                .compactMap { key, value in
                    Int(key).map { ($0, value) }
                }
                .max { $0.0 < $1.0 }?
                .1
        }

        var fallbackCoverURLs: [String] {
            let preferred = preferredCoverURL
            return (productImages ?? [:])
                .compactMap { key, value in
                    Int(key).map { ($0, value) }
                }
                .sorted { $0.0 > $1.0 }
                .map(\.1)
                .filter { $0 != preferred }
        }
    }

    private struct CatalogResponse: Decodable {
        var products: [Product]
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    func search(query: String) async throws -> [Product] {
        var components = URLComponents(
            string: "https://api.audible.com/1.0/catalog/products"
        )
        components?.queryItems = [
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "num_results", value: "50"),
            URLQueryItem(name: "products_sort_by", value: "Relevance"),
            URLQueryItem(
                name: "response_groups",
                value: "product_desc,product_extended_attrs,contributors,series,media"
            ),
            URLQueryItem(
                name: "image_sizes",
                value: "500,1024,1215,1600,2048,2400,3000"
            )
        ]
        guard let url = components?.url else {
            throw SableAudibleCatalogClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Sable-Covers/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SableAudibleCatalogClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw SableAudibleCatalogClientError.server(
                status: http.statusCode
            )
        }
        guard !data.isEmpty, data.count <= 8_000_000 else {
            throw SableAudibleCatalogClientError.invalidResponse
        }
        return try Self.products(from: data)
    }

    static func products(from data: Data) throws -> [Product] {
        do {
            return try JSONDecoder().decode(
                CatalogResponse.self,
                from: data
            ).products
        } catch {
            throw SableAudibleCatalogClientError.decoding(
                error.localizedDescription
            )
        }
    }
}

nonisolated enum SableAppleBooksCatalogClientError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case server(status: Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Apple Books search could not be prepared."
        case .invalidResponse:
            "Apple Books returned an unreadable response."
        case .server(let status):
            "Apple Books returned \(status)."
        case .decoding(let message):
            "Apple Books results could not be read: \(message)"
        }
    }
}

nonisolated struct SableAppleBooksCatalogClient: Sendable {
    struct Product: Decodable, Sendable, Equatable {
        var wrapperType: String?
        var collectionID: Int64
        var artistName: String?
        var collectionName: String
        var collectionViewURL: String?
        var artworkURL100: String?

        enum CodingKeys: String, CodingKey {
            case wrapperType
            case collectionID = "collectionId"
            case artistName
            case collectionName
            case collectionViewURL = "collectionViewUrl"
            case artworkURL100 = "artworkUrl100"
        }

        var preferredCoverURL: String? {
            guard let artworkURL100 else { return nil }
            return artworkURL100.replacingOccurrences(
                of: #"/\d+x\d+(?:bb|bb-[^/.]+)?\.(?:jpg|jpeg|png|webp)$"#,
                with: "/10000x0w-999.jpg",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        var fallbackCoverURLs: [String] {
            guard let artworkURL100 else { return [] }
            return [artworkURL100].filter { $0 != preferredCoverURL }
        }
    }

    private struct CatalogResponse: Decodable {
        var results: [Product]
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    func search(query: String) async throws -> [Product] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "media", value: "audiobook"),
            URLQueryItem(name: "entity", value: "audiobook"),
            URLQueryItem(name: "limit", value: "200")
        ]
        return try await products(from: components?.url)
    }

    func lookup(collectionID: String) async throws -> [Product] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: collectionID),
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "entity", value: "audiobook")
        ]
        return try await products(from: components?.url)
    }

    private func products(from url: URL?) async throws -> [Product] {
        guard let url else {
            throw SableAppleBooksCatalogClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Sable-Covers/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SableAppleBooksCatalogClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw SableAppleBooksCatalogClientError.server(status: http.statusCode)
        }
        guard !data.isEmpty, data.count <= 8_000_000 else {
            throw SableAppleBooksCatalogClientError.invalidResponse
        }
        return try Self.products(from: data)
    }

    static func products(from data: Data) throws -> [Product] {
        do {
            return try JSONDecoder().decode(CatalogResponse.self, from: data).results
        } catch {
            throw SableAppleBooksCatalogClientError.decoding(
                error.localizedDescription
            )
        }
    }
}

nonisolated struct SableMangaBakaStorefrontDiscovery: Sendable {
    enum AutomaticMediaTypeDisposition: Equatable {
        case accepted
        case needsReview
        case rejected
    }

    struct StoreSeriesReference: Sendable, Equatable {
        var provider: SableLibraryBigBookCoversProvider
        var itemID: String
        var itemType: String
        var url: String
        var languageOverride: String? = nil
        var volumeNumberOverride: Double? = nil
        var publisherProvenMediaType: String? = nil
        var publicationTypeOverride: String? = nil
    }

    struct OfficialPublisherReference: Sendable, Equatable {
        var provider: SableLibraryBigBookCoversProvider
        var title: String
        var imageURL: String
        var storeURL: String
        var volumeNumber: Double
        var coverType: String
        var mediaType: String
        var pageURL: String
        var publisherFamily: String = "Seven Seas"
        var imprint: String? = nil
        var providerSeriesID: String? = nil
        var providerItemID: String? = nil
        var language: String = "en"
        var publicationType: String? = nil
        var requiresRelationshipReview: Bool = false
    }

    struct ShueishaSearchPayload: Decodable {
        var datas: [Series]

        struct Series: Decodable {
            var seriesId: Int
            var seriesName: String
            var labelName: String?
            var genreDatas: [String]?
            var itemDatas: [Item]

            private enum CodingKeys: String, CodingKey {
                case seriesId = "series_id"
                case seriesName = "series_name"
                case labelName = "label_name"
                case genreDatas = "genre_datas"
                case itemDatas = "item_datas"
            }
        }

        struct Item: Decodable {
            var isbn: String?
            var itemName: String
            var viewVolumeNumber: String?
            var imageURL: String?

            private enum CodingKeys: String, CodingKey {
                case isbn
                case itemName = "item_name"
                case viewVolumeNumber = "view_volume_number"
                case imageURL = "image_url"
            }
        }
    }

    private struct ShueishaSeriesPayload: Decodable {
        var data: SeriesData

        struct SeriesData: Decodable {
            var seriesData: Metadata
            var itemDatas: [ShueishaSearchPayload.Item]

            private enum CodingKeys: String, CodingKey {
                case seriesData = "series_data"
                case itemDatas = "item_datas"
            }
        }

        struct Metadata: Decodable {
            var seriesId: Int
            var seriesName: String
            var labelName: String?
            var genreDatas: [String]?

            private enum CodingKeys: String, CodingKey {
                case seriesId = "series_id"
                case seriesName = "series_name"
                case labelName = "main_label_name"
                case genreDatas = "genre_datas"
            }
        }
    }

    private struct ProviderResult: Sendable {
        var suggestions: [SableMangaBakaStorefrontCoverSuggestion]
        var notes: [String]
    }

    private struct ValidatedStorefrontImage: Sendable {
        var url: String
        var width: Int
        var height: Int
        var contentRating: String
        var contentRatingWasInferred: Bool
        var detectedVolumeNumbers: [Int]
        var detectedChapterNumbers: [Int]
        var visualSignature: [UInt8]
    }

    private struct StorefrontImageInspection: Sendable {
        var accepted: ValidatedStorefrontImage?
        var backCover: ValidatedStorefrontImage?
        var imageChoices: [SableMangaBakaStorefrontImageChoice]
        var bestRejectedWidth: Int?
        var bestRejectedHeight: Int?
    }

    private struct AmazonProductImageURLs: Sendable {
        var front: [String]
        var back: [String]
    }

    struct BarnesNobleProduct: Sendable, Equatable {
        var id: String
        var title: String
        var imageURL: String
        var storeURL: String
        var seriesIdentity: String
        var volumeNumber: Double
        var mediaType: String?
        var publicationType: String?
    }

    private actor StorefrontPageCache {
        private struct Entry {
            var html: String
            var byteCount: Int
        }

        private let maximumEntryCount = 64
        private let maximumByteCount = 48 * 1_024 * 1_024
        private var pages: [String: Entry] = [:]
        private var accessOrder: [String] = []
        private var byteCount = 0

        func page(for url: String) -> String? {
            guard let entry = pages[url] else { return nil }
            accessOrder.removeAll(where: { $0 == url })
            accessOrder.append(url)
            return entry.html
        }

        func insert(_ page: String, for url: String) {
            let size = page.utf8.count
            guard size <= maximumByteCount else { return }
            if let existing = pages.removeValue(forKey: url) {
                byteCount -= existing.byteCount
            }
            accessOrder.removeAll(where: { $0 == url })
            pages[url] = Entry(html: page, byteCount: size)
            accessOrder.append(url)
            byteCount += size

            while pages.count > maximumEntryCount
                || byteCount > maximumByteCount,
                let oldestURL = accessOrder.first {
                accessOrder.removeFirst()
                if let removed = pages.removeValue(forKey: oldestURL) {
                    byteCount -= removed.byteCount
                }
            }
        }
    }

    private actor StorefrontImageInspectionGate {
        private let limit: Int
        private var active = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) {
            self.limit = max(1, limit)
        }

        func acquire() async {
            if active < limit {
                active += 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if waiters.isEmpty {
                active = max(0, active - 1)
            } else {
                waiters.removeFirst().resume()
            }
        }
    }

    struct KoreanStorefrontProduct: Sendable, Equatable {
        var id: String
        var title: String
        var imageURL: String
        var storeURL: String
        var volumeNumber: Double
        var mediaType: String?
        var seriesID: String? = nil
    }

    struct RakutenBooksProduct: Sendable, Equatable {
        var id: String
        var title: String
        var imageURL: String
        var storeURL: String
        var seriesIdentity: String
        var volumeNumber: Double
        var mediaType: String?
        var publicationType: String
    }

    nonisolated enum ProgressEvent: Sendable {
        case providerStarted(
            provider: SableLibraryBigBookCoversProvider,
            query: String?
        )
        case seriesCandidatesFound(
            provider: SableLibraryBigBookCoversProvider,
            total: Int,
            compatible: Int
        )
        case coverCandidatesFound(
            provider: SableLibraryBigBookCoversProvider,
            count: Int
        )
        case imageInspected(
            provider: SableLibraryBigBookCoversProvider,
            accepted: Bool,
            width: Int?,
            height: Int?
        )
        case providerFinished(
            provider: SableLibraryBigBookCoversProvider,
            accepted: Int,
            detail: String
        )
    }

    private let providerClient = SableLibraryBigBookCoversClient()
    private let bookLiveClient = SableLibraryBookLiveSeriesGroupClient()
    private let audibleClient = SableAudibleCatalogClient()
    private let appleBooksClient = SableAppleBooksCatalogClient()
    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()
    private static let storefrontPageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()
    private static let storefrontPageCache = StorefrontPageCache()
    private static let storefrontImageInspectionGate =
        StorefrontImageInspectionGate(limit: 2)

    func discover(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>? = nil,
        providers selectedProviders: Set<SableLibraryBigBookCoversProvider>? = nil,
        includesSupplementalSources: Bool = true,
        progress: (@Sendable (ProgressEvent) async -> Void)? = nil
    ) async -> SableMangaBakaStorefrontDiscoveryResult {
        let providers = Self.providers(for: languages).filter {
            // Shueisha's BBC lane includes bordered digital-store display
            // images. The direct publisher lane below supplies clean print
            // fronts and matching backs from the same official catalog.
            $0 != .shueisha
                && Self.providerIsEnabled(
                    $0,
                    selectedProviders: selectedProviders
                )
        }
        let rakutenProviders = Self.selectableProviders(for: languages).filter {
            $0 == .rakutenKoboJapan
                && Self.providerIsEnabled(
                    $0,
                    selectedProviders: selectedProviders
                )
        }
        let barnesNobleProviders = Self.selectableProviders(
            for: languages
        ).filter {
            $0.isBarnesNoble
                && (selectedProviders?.contains($0) ?? true)
        }
        let crunchyrollProviders = Self.selectableProviders(
            for: languages
        ).filter {
            $0.isCrunchyrollStore
                && (selectedProviders?.contains($0) ?? true)
        }
        let lanes = Self.providerExecutionLanes(for: providers)
        async let regularLane = discover(
            providers: lanes.regular,
            maxConcurrent: 4,
            for: series,
            progress: progress
        )
        async let crossInfiniteReferences: [StoreSeriesReference] =
            supplementalReferences(
            enabled: includesSupplementalSources
        ) {
            await crossInfiniteWorldAmazonReferences(
                for: series,
                languages: languages
            )
        }
        async let crossInfiniteOfficialReferences: [OfficialPublisherReference] =
            supplementalReferences(enabled: includesSupplementalSources) {
                await crossInfiniteWorldPublisherReferences(
                    for: series,
                    languages: languages
                )
            }
        async let sevenSeasReferences: [OfficialPublisherReference] =
            supplementalReferences(
            enabled: includesSupplementalSources
        ) {
            await self.sevenSeasPublisherReferences(
                for: series,
                languages: languages
            )
        }
        async let kodanshaReferences: [OfficialPublisherReference] =
            supplementalReferences(
            enabled: includesSupplementalSources
        ) {
            await self.kodanshaPublisherReferences(
                for: series,
                languages: languages
            )
        }
        async let vizReferences: [OfficialPublisherReference] =
            supplementalReferences(
            enabled: includesSupplementalSources
        ) {
            await self.vizPublisherReferences(
                for: series,
                languages: languages
            )
        }
        async let darkHorseReferences: [OfficialPublisherReference] =
            supplementalReferences(
            enabled: includesSupplementalSources
        ) {
            await self.darkHorsePublisherReferences(
                for: series,
                languages: languages
            )
        }
        async let squareEnixReferences: [OfficialPublisherReference] =
            supplementalReferences(
            enabled: includesSupplementalSources
        ) {
            await self.squareEnixPublisherReferences(
                for: series,
                languages: languages
            )
        }
        async let shueishaReferences: [OfficialPublisherReference] =
            supplementalReferences(
            enabled: Self.includesShueishaPublisherSource(
                includesSupplementalSources: includesSupplementalSources,
                selectedProviders: selectedProviders
            )
        ) {
            await self.shueishaPublisherReferences(
                for: series,
                languages: languages
            )
        }
        let publisherReferences = (await crossInfiniteReferences).filter {
            Self.providerIsEnabled(
                $0.provider,
                selectedProviders: selectedProviders
            )
        }
        let sevenSeasPublisherReferences = (await sevenSeasReferences).filter {
            Self.providerIsEnabled(
                $0.provider,
                selectedProviders: selectedProviders
            )
        }
        let kodanshaPublisherReferences = (await kodanshaReferences).filter {
            Self.providerIsEnabled(
                $0.provider,
                selectedProviders: selectedProviders
            )
        }
        let vizPublisherReferences = (await vizReferences).filter {
            Self.providerIsEnabled(
                $0.provider,
                selectedProviders: selectedProviders
            )
        }
        let darkHorsePublisherReferences = (await darkHorseReferences).filter {
            Self.providerIsEnabled(
                $0.provider,
                selectedProviders: selectedProviders
            )
        }
        let squareEnixPublisherReferences = (await squareEnixReferences)
            .filter {
                Self.providerIsEnabled(
                    $0.provider,
                    selectedProviders: selectedProviders
                )
            }
        let shueishaPublisherReferences = (await shueishaReferences).filter {
            Self.providerIsEnabled(
                $0.provider,
                selectedProviders: selectedProviders
            )
        }
        let crossInfinitePublisherReferences =
            (await crossInfiniteOfficialReferences).filter {
                Self.providerIsEnabled(
                    $0.provider,
                    selectedProviders: selectedProviders
                )
            }
        let rawOfficialPublisherReferences =
            crossInfinitePublisherReferences
            + sevenSeasPublisherReferences
            + kodanshaPublisherReferences
            + vizPublisherReferences
            + darkHorsePublisherReferences
            + squareEnixPublisherReferences
            + shueishaPublisherReferences
        let officialPublisherReferences = await
            crunchyrollReferencesByLoadingProductArtwork(
                barnesNobleReferencesByLoadingProductArtwork(
                rawOfficialPublisherReferences
                )
            )
        let publisherReferencedProviders = Set(
            publisherReferences.map(\.provider)
                + officialPublisherReferences.map(\.provider)
        )
        let directRakutenProviders = rakutenProviders.filter {
            $0 == .rakutenKoboJapan
                && !publisherReferencedProviders.contains($0)
        }
        let publisherMissingCrunchyrollProviders =
            crunchyrollProviders.filter {
                !publisherReferencedProviders.contains($0)
            }
        async let publisherLane = discover(
            storeSeriesReferences: publisherReferences,
            for: series,
            includesAudiobooks: false,
            progress: progress
        )
        async let officialPublisherLane = officialPublisherResult(
            references: officialPublisherReferences,
            series: series,
            progress: progress
        )
        async let amazonLane = discover(
            providers: lanes.amazon,
            maxConcurrent: Self.amazonProviderConcurrencyLimit,
            for: series,
            progress: progress
        )
        async let rakutenLane = discover(
            providers: directRakutenProviders,
            maxConcurrent: 1,
            for: series,
            progress: progress
        )
        async let barnesNobleLane = discover(
            providers: barnesNobleProviders,
            maxConcurrent: 1,
            for: series,
            progress: progress
        )
        async let unavailableCrunchyrollLane =
            unavailableCrunchyrollResults(
                providers: publisherMissingCrunchyrollProviders,
                progress: progress
            )
        let publisherResult = await publisherLane
        let officialPublisherResult = await officialPublisherLane
        let amazonResults = await amazonLane
        let rakutenResults = await rakutenLane
        let barnesNobleResults = await barnesNobleLane
        let unavailableCrunchyrollResults =
            await unavailableCrunchyrollLane
        let regularResults = await regularLane
        let results = regularResults
            + amazonResults
            + rakutenResults
            + barnesNobleResults
            + unavailableCrunchyrollResults
        var notes = results.flatMap(\.notes)
            + publisherResult.notes
            + officialPublisherResult.notes
        if !publisherReferences.isEmpty {
            notes.append(
                "Cross Infinite World: checked \(publisherReferences.count) official Amazon volume link\(publisherReferences.count == 1 ? "" : "s")."
            )
        }
        if !sevenSeasPublisherReferences.isEmpty {
            let pageCount = Set(
                sevenSeasPublisherReferences.map(\.pageURL)
            ).count
            let imprints = Set(
                sevenSeasPublisherReferences.compactMap(\.imprint)
            )
            .sorted()
            let imprintDetail = imprints.isEmpty
                ? ""
                : " (\(imprints.joined(separator: ", ")))"
            notes.append(
                "Seven Seas\(imprintDetail): checked \(pageCount) official volume page\(pageCount == 1 ? "" : "s") and found \(sevenSeasPublisherReferences.count) linked retailer cover\(sevenSeasPublisherReferences.count == 1 ? "" : "s")."
            )
        }
        for (publisher, references) in [
            ("Kodansha", kodanshaPublisherReferences),
            ("VIZ Media", vizPublisherReferences),
            ("Dark Horse Manga", darkHorsePublisherReferences),
            ("Square Enix Manga & Books", squareEnixPublisherReferences),
            ("Shueisha", shueishaPublisherReferences)
        ] where !references.isEmpty {
            let pageCount = Set(references.map(\.pageURL)).count
            notes.append(
                "\(publisher): checked \(pageCount) official volume page\(pageCount == 1 ? "" : "s") and found \(references.count) linked retailer cover\(references.count == 1 ? "" : "s")."
            )
        }
        if Task.isCancelled {
            notes.append("Storefront scan cancelled.")
        }

        return SableMangaBakaStorefrontDiscoveryResult(
            suggestions: Self.presentationSuggestions(
                from: results.flatMap(\.suggestions)
                    + publisherResult.suggestions
                    + officialPublisherResult.suggestions
            ),
            notes: notes.sorted()
        )
    }

    private func supplementalReferences<T: Sendable>(
        enabled: Bool,
        load: @Sendable () async -> [T]
    ) async -> [T] {
        guard enabled else { return [] }
        return await load()
    }

    static func providerExecutionLanes(
        for providers: [SableLibraryBigBookCoversProvider]
    ) -> (
        regular: [SableLibraryBigBookCoversProvider],
        amazon: [SableLibraryBigBookCoversProvider]
    ) {
        (
            regular: providers.filter { !$0.isAmazon },
            amazon: providers.filter(\.isAmazon)
        )
    }

    static let amazonProviderConcurrencyLimit = 4

    private func discover(
        providers: [SableLibraryBigBookCoversProvider],
        maxConcurrent: Int,
        for series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> [ProviderResult] {
        guard !providers.isEmpty else { return [] }

        let concurrency = min(max(1, maxConcurrent), providers.count)
        let operation:
            @Sendable (Int, SableLibraryBigBookCoversProvider) async
                -> (Int, ProviderResult) = { index, provider in
                    guard !Task.isCancelled else {
                        return (
                            index,
                            ProviderResult(
                                suggestions: [],
                                notes: [
                                    "\(provider.displayName): scan cancelled."
                                ]
                            )
                        )
                    }
                    await progress?(
                        .providerStarted(
                            provider: provider,
                            query: Self.preferredQuery(
                                for: provider,
                                series: series
                            )
                        )
                    )
                    let result = await discover(
                        provider: provider,
                        for: series,
                        progress: progress
                    )
                    guard !Task.isCancelled else {
                        return (index, result)
                    }
                    await progress?(
                        .providerFinished(
                            provider: provider,
                            accepted: result.suggestions.count,
                            detail: result.notes.first ?? "Finished."
                        )
                    )
                    return (index, result)
                }

        return await withTaskGroup(
            of: (Int, ProviderResult).self,
            returning: [ProviderResult].self
        ) { group in
            for index in 0..<concurrency {
                let provider = providers[index]
                group.addTask {
                    await operation(index, provider)
                }
            }

            var nextProviderIndex = concurrency
            var indexedResults: [(Int, ProviderResult)] = []
            indexedResults.reserveCapacity(providers.count)

            while let indexedResult = await group.next() {
                indexedResults.append(indexedResult)

                guard !Task.isCancelled,
                      nextProviderIndex < providers.count else {
                    continue
                }
                let index = nextProviderIndex
                let provider = providers[index]
                nextProviderIndex += 1
                group.addTask {
                    await operation(index, provider)
                }
            }

            return indexedResults
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    func discover(
        storeSeriesURLs: [String],
        for series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)? = nil
    ) async -> SableMangaBakaStorefrontDiscoveryResult {
        let references = storeSeriesURLs.compactMap(Self.storeSeriesReference)
        var notes: [String] = []

        if references.count < storeSeriesURLs.count {
            notes.append(
                "Some links were not recognized as BookLive, BookWalker, Amazon, Barnes & Noble, Audible, Apple Books, YES24, or Kyobo store pages."
            )
        }
        let result = await discover(
            storeSeriesReferences: references,
            for: series,
            includesAudiobooks: true,
            progress: progress
        )
        return SableMangaBakaStorefrontDiscoveryResult(
            suggestions: result.suggestions,
            notes: notes + result.notes
        )
    }

    private func discover(
        storeSeriesReferences references: [StoreSeriesReference],
        for series: SableMangaBakaSeriesSummary,
        includesAudiobooks: Bool,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> SableMangaBakaStorefrontDiscoveryResult {
        var found: [SableMangaBakaStorefrontCoverSuggestion] = []
        var notes: [String] = []

        for reference in references {
            await progress?(
                .providerStarted(
                    provider: reference.provider,
                    query: reference.url
                )
            )
            do {
                guard var selection = try await selectedBooks(
                    from: reference,
                    series: series
                ) else {
                    let detail =
                        "\(reference.provider.displayName): manual relationship and media type accepted, but no readable store entries were found on this page."
                    notes.append(detail)
                    await progress?(
                        .providerFinished(
                            provider: reference.provider,
                            accepted: 0,
                            detail: detail
                        )
                    )
                    continue
                }
                if let volumeNumber = reference.volumeNumberOverride,
                   selection.books.count == 1 {
                    selection.books[0].volumeNumber = volumeNumber
                    selection.books[0].sequenceIndex = max(
                        Int(volumeNumber.rounded()),
                        1
                    )
                }
                await progress?(
                    .seriesCandidatesFound(
                        provider: reference.provider,
                        total: 1,
                        compatible: 1
                    )
                )
                let selectionIsAudiobook =
                    reference.publisherProvenMediaType == "audiobook"
                    || selection.books.contains {
                        $0.bookType?.lowercased().contains("audio") == true
                            || $0.volumeType?.lowercased().contains("audio") == true
                    }
                let standardResult = selectionIsAudiobook
                    ? ProviderResult(suggestions: [], notes: [])
                    : await providerResult(
                        provider: reference.provider,
                        selection: selection,
                        series: series,
                        trustsSelectedSeriesIdentity: true,
                        languageOverride: reference.languageOverride,
                        publisherProvenMediaType:
                            reference.publisherProvenMediaType,
                        progress: progress
                    )
                var audiobookResult = ProviderResult(
                    suggestions: [],
                    notes: []
                )
                if includesAudiobooks,
                   selectionIsAudiobook,
                   Self.shouldDiscoverEnglishAudiobooks(
                    for: series,
                    provider: reference.provider
                ) {
                    audiobookResult = await providerResult(
                        provider: reference.provider,
                        selection: selection,
                        series: series,
                        trustsSelectedSeriesIdentity: true,
                        languageOverride: reference.languageOverride,
                        publisherProvenMediaType:
                            reference.publisherProvenMediaType,
                        expectedMediaType: "audiobook",
                        requestedCoverType: "audiobook",
                        progress: progress
                    )
                }
                let result = ProviderResult(
                    suggestions: standardResult.suggestions
                        + audiobookResult.suggestions,
                    notes: standardResult.notes + audiobookResult.notes
                )
                found.append(contentsOf: result.suggestions)
                notes.append(contentsOf: result.notes)
                await progress?(
                    .providerFinished(
                        provider: reference.provider,
                        accepted: result.suggestions.count,
                        detail: result.notes.first ?? "Exact store link checked."
                    )
                )
            } catch is CancellationError {
                notes.append("\(reference.provider.displayName): scan cancelled.")
                break
            } catch {
                let detail =
                    "\(reference.provider.displayName): \(error.localizedDescription)"
                notes.append(detail)
                await progress?(
                    .providerFinished(
                        provider: reference.provider,
                        accepted: 0,
                        detail: detail
                    )
                )
            }
        }

        return SableMangaBakaStorefrontDiscoveryResult(
            suggestions: Self.presentationSuggestions(from: found),
            notes: notes
        )
    }

    private func crossInfiniteWorldAmazonReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [StoreSeriesReference] {
        let requestedLanguages = languages?.map(Self.normalizedLanguageTag)
        guard requestedLanguages == nil
            || requestedLanguages?.contains("en") == true,
              SableLibraryCoverDownloadPlanner
                .preferredProviderBookTypeForDownload(
                    mediaType: series.type
                ) == "novel",
              let catalogHTML = await Self.storefrontPageHTML(
                  from: "https://www.crossinfworld.com/series.html"
              ),
              let seriesPageURL = Self.crossInfiniteWorldSeriesPageURL(
                  in: catalogHTML,
                  series: series
              ),
              let seriesHTML = await Self.storefrontPageHTML(
                  from: seriesPageURL.absoluteString,
                  referer: "https://www.crossinfworld.com/series.html"
              ) else {
            return []
        }
        return Self.crossInfiniteWorldAmazonReferences(in: seriesHTML)
    }

    static func crossInfiniteWorldSeriesPageURL(
        in catalogHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> URL? {
        let referenceTitles =
            SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            (series.titles ?? [])
                .filter {
                    normalizedLanguageTag($0.language).hasPrefix("en")
                }
                .map(\.title)
                + [
                    series.title,
                    series.displayTitle
                ].compactMap { $0 }
        )
        let references = referenceTitles
        .map(normalizedPublisherCatalogTitle)
        .filter { !$0.isEmpty }
        guard !references.isEmpty else { return nil }

        let html = catalogHTML.replacingOccurrences(
            of: #"(?is)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
        let pattern =
            #"(?is)<a[^>]+href\s*=\s*["']([^"']+\.html)["'][^>]*>\s*<img[^>]+alt\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        var exactMatches: [URL] = []
        var relatedMatches: [URL] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range)
        where match.numberOfRanges > 2 {
            guard let pathRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let url = URL(
                    string: String(html[pathRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    relativeTo: URL(
                        string: "https://www.crossinfworld.com/"
                    )
                  )?.absoluteURL else {
                continue
            }
            let candidateTitle = decodedPublisherHTML(
                String(html[titleRange])
            )
            let candidate = normalizedPublisherCatalogTitle(candidateTitle)
            if references.contains(candidate) {
                exactMatches.append(url)
            } else if referenceTitles.contains(where: {
                officialPublisherCandidateTitle(
                    candidateTitle,
                    matches: $0
                )
                    || publisherCatalogTitlesHaveStrongTokenOverlap(
                        candidateTitle,
                        $0
                    )
            }) {
                relatedMatches.append(url)
            }
        }
        return exactMatches.first
            ?? (relatedMatches.count == 1 ? relatedMatches.first : nil)
    }

    static func crossInfiniteWorldAmazonReferences(
        in seriesHTML: String
    ) -> [StoreSeriesReference] {
        let html = seriesHTML.replacingOccurrences(
            of: #"(?is)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
        let blockPattern =
            #"(?is)<div\s+class\s*=\s*["']col-sm-3["'][^>]*>(.*?)(?=<div\s+class\s*=\s*["']col-sm-3["']|<div\s+class\s*=\s*["']clearfix["'])"#
        guard let blockRegex = try? NSRegularExpression(
            pattern: blockPattern
        ) else {
            return []
        }
        let hrefPattern = #"(?is)href\s*=\s*["']([^"']+)["']"#
        guard let hrefRegex = try? NSRegularExpression(
            pattern: hrefPattern
        ) else {
            return []
        }

        var preferred: [String: StoreSeriesReference] = [:]
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for (offset, match) in blockRegex.matches(
            in: html,
            range: htmlRange
        ).enumerated() where match.numberOfRanges > 1 {
            guard let blockRange = Range(match.range(at: 1), in: html) else {
                continue
            }
            let block = String(html[blockRange])
            let volumeNumber =
                SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                    in: decodedPublisherHTML(block)
                )
                ?? Double(offset + 1)
            let range = NSRange(block.startIndex..<block.endIndex, in: block)
            for linkMatch in hrefRegex.matches(in: block, range: range)
            where linkMatch.numberOfRanges > 1 {
                guard let linkRange = Range(
                    linkMatch.range(at: 1),
                    in: block
                ) else {
                    continue
                }
                let rawURL = decodedPublisherHTML(
                    String(block[linkRange])
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                guard var reference = storeSeriesReference(from: rawURL),
                      reference.provider.isAmazon else {
                    continue
                }
                reference.languageOverride = "en"
                reference.volumeNumberOverride = volumeNumber
                reference.publisherProvenMediaType = "novel"
                let key =
                    "\(reference.provider.rawValue):\(volumeNumber)"
                // Publisher pages list print links before digital links. The
                // later direct ebook product is normally the cleaner cover.
                preferred[key] = reference
            }
        }
        let references: [StoreSeriesReference] = preferred.values.map { $0 }
        return references.sorted(by: {
            (
                lhs: StoreSeriesReference,
                rhs: StoreSeriesReference
            ) -> Bool in
            if lhs.provider.rawValue != rhs.provider.rawValue {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            return (lhs.volumeNumberOverride ?? 0)
                < (rhs.volumeNumberOverride ?? 0)
        })
    }

    private func crossInfiniteWorldPublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        let requestedLanguages = languages?.map(Self.normalizedLanguageTag)
        guard requestedLanguages == nil
            || requestedLanguages?.contains("en") == true,
              SableLibraryCoverDownloadPlanner
                .preferredProviderBookTypeForDownload(
                    mediaType: series.type
                ) == "novel",
              let catalogHTML = await Self.storefrontPageHTML(
                  from: "https://www.crossinfworld.com/series.html"
              ),
              let seriesPageURL = Self.crossInfiniteWorldSeriesPageURL(
                  in: catalogHTML,
                  series: series
              ),
              let seriesHTML = await Self.storefrontPageHTML(
                  from: seriesPageURL.absoluteString,
                  referer: "https://www.crossinfworld.com/series.html"
              ) else {
            return []
        }
        return Self.crossInfiniteWorldPublisherReferences(
            in: seriesHTML,
            pageURL: seriesPageURL
        )
    }

    static func crossInfiniteWorldPublisherReferences(
        in seriesHTML: String,
        pageURL: URL
    ) -> [OfficialPublisherReference] {
        let html = seriesHTML.replacingOccurrences(
            of: #"(?is)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
        let blockPattern =
            #"(?is)<div\s+class\s*=\s*["']col-sm-3["'][^>]*>(.*?)(?=<div\s+class\s*=\s*["']col-sm-3["']|<div\s+class\s*=\s*["']clearfix["'])"#
        guard let blockRegex = try? NSRegularExpression(
            pattern: blockPattern
        ),
              let linkRegex = try? NSRegularExpression(
                pattern:
                    #"(?is)<a[^>]+href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
              ) else {
            return []
        }

        var references: [OfficialPublisherReference] = []
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for (offset, match) in blockRegex.matches(
            in: html,
            range: htmlRange
        ).enumerated() where match.numberOfRanges > 1 {
            guard let blockRange = Range(match.range(at: 1), in: html) else {
                continue
            }
            let block = String(html[blockRange])
            let title = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)<div[^>]+class\s*=\s*["'][^"']*panel-heading[^"']*["'][^>]*>.*?<strong>(.*?)</strong>"#
            )
            .map(decodedPublisherHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            let imagePath = firstPathCapture(
                in: block,
                pattern: #"(?is)<img[^>]+src\s*=\s*["']([^"']+)["']"#
            )
            guard let title,
                  !title.isEmpty,
                  let imagePath,
                  let imageURL = URL(
                    string: decodedPublisherHTML(imagePath),
                    relativeTo: pageURL
                  )?.absoluteURL else {
                continue
            }
            let volumeNumber =
                SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                    in: title
                )
                ?? Double(offset + 1)
            let range = NSRange(
                block.startIndex..<block.endIndex,
                in: block
            )
            var preferred:
                [SableLibraryBigBookCoversProvider:
                    OfficialPublisherReference] = [:]
            for linkMatch in linkRegex.matches(in: block, range: range)
            where linkMatch.numberOfRanges > 2 {
                guard let urlRange = Range(
                    linkMatch.range(at: 1),
                    in: block
                ),
                      let bodyRange = Range(
                        linkMatch.range(at: 2),
                        in: block
                      ),
                      let storeURL = URL(
                        string: decodedPublisherHTML(
                            String(block[urlRange])
                        ),
                        relativeTo: pageURL
                      )?.absoluteURL,
                      let provider = sevenSeasRetailerProvider(
                        label: decodedPublisherHTML(
                            String(block[bodyRange])
                        ),
                        url: storeURL,
                        isAudiobook: false
                      ),
                      provider.isBarnesNoble
                        || provider.isRakutenKobo else {
                    continue
                }
                preferred[provider] = OfficialPublisherReference(
                    provider: provider,
                    title: title,
                    imageURL: imageURL.absoluteString,
                    storeURL: storeURL.absoluteString,
                    volumeNumber: volumeNumber,
                    coverType: "volume",
                    mediaType: "novel",
                    pageURL: pageURL.absoluteString,
                    publisherFamily: "Cross Infinite World",
                    providerItemID:
                        provider.isBarnesNoble
                        ? barnesNobleProductID(from: storeURL)
                        : nil,
                    language: "en",
                    publicationType:
                        provider.isRakutenKobo ? "digital" : nil
                )
            }
            references.append(contentsOf: preferred.values)
        }
        return references.sorted {
            if $0.provider != $1.provider {
                return $0.provider.discoveryPriority
                    < $1.provider.discoveryPriority
            }
            return $0.volumeNumber < $1.volumeNumber
        }
    }

    private func sevenSeasPublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        let requestedLanguages = languages?.map(Self.normalizedLanguageTag)
        let expectedMediaType = SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(mediaType: series.type)
        guard requestedLanguages == nil
            || requestedLanguages?.contains("en") == true,
              expectedMediaType == "manga"
                || expectedMediaType == "novel",
              let seriesPageURL = await sevenSeasSeriesPageURL(
                for: series
              ),
              let seriesHTML = await Self.storefrontPageHTML(
                from: seriesPageURL.absoluteString
              ) else {
            return []
        }

        let pageURLs = Self.sevenSeasVolumePageURLs(
            in: seriesHTML,
            series: series
        )
        let references = await officialPublisherReferences(
            pageURLs: pageURLs,
            referer: seriesPageURL
        ) { html, pageURL in
            Self.sevenSeasPublisherReferences(
                in: html,
                pageURL: pageURL
            )
        }
        return references.sorted {
            if $0.coverType != $1.coverType {
                return $0.coverType < $1.coverType
            }
            if $0.volumeNumber != $1.volumeNumber {
                return $0.volumeNumber < $1.volumeNumber
            }
            return $0.provider.discoveryPriority
                < $1.provider.discoveryPriority
        }
    }

    private func sevenSeasSeriesPageURL(
        for series: SableMangaBakaSeriesSummary
    ) async -> URL? {
        let titles = Self.sevenSeasRequestedTitles(for: series)
        for title in titles.prefix(4) {
            var components = URLComponents(
                string:
                    "https://sevenseasentertainment.com/wp-json/wp/v2/search"
            )
            components?.queryItems = [
                URLQueryItem(name: "search", value: title),
                URLQueryItem(name: "type", value: "post"),
                URLQueryItem(name: "subtype", value: "series"),
                URLQueryItem(name: "per_page", value: "20")
            ]
            guard let url = components?.url,
                  let searchJSON = await Self.storefrontPageHTML(
                    from: url.absoluteString
                  ) else {
                continue
            }
            if let matched = Self.sevenSeasSeriesPageURL(
                in: searchJSON,
                series: series
            ) {
                return matched
            }
        }
        return nil
    }

    static func sevenSeasSeriesPageURL(
        in searchJSON: String,
        series: SableMangaBakaSeriesSummary
    ) -> URL? {
        guard let data = searchJSON.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(
                with: data
              ) as? [[String: Any]] else {
            return nil
        }
        let expectedMediaType = SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(mediaType: series.type)
        let referenceTitles = Set(
            sevenSeasRequestedTitles(for: series)
                .map(sevenSeasBaseTitle)
                .filter { !$0.isEmpty }
        )
        guard !referenceTitles.isEmpty else { return nil }

        var exactMatches: [URL] = []
        var relatedMatches: [URL] = []
        for row in rows {
            guard let rawTitle = row["title"] as? String,
                  let rawURL = row["url"] as? String,
                  let mediaType = sevenSeasMediaType(in: rawTitle)
                    ?? expectedMediaType,
                  mediaType == expectedMediaType,
                  let url = URL(string: rawURL),
                  url.host?.lowercased()
                    == "sevenseasentertainment.com" else {
                continue
            }
            let candidate = sevenSeasBaseTitle(rawTitle)
            if referenceTitles.contains(candidate) {
                exactMatches.append(url)
            } else if referenceTitles.contains(where: {
                officialPublisherCandidateTitle(
                    candidate,
                    matches: $0
                )
            }) {
                relatedMatches.append(url)
            }
        }
        return exactMatches.first
            ?? (relatedMatches.count == 1 ? relatedMatches.first : nil)
    }

    static func sevenSeasVolumePageURLs(
        in seriesHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        let expectedMediaType = SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(mediaType: series.type)
        var referenceTitles = Set(
            sevenSeasRequestedTitles(for: series)
                .map(sevenSeasBaseTitle)
                .filter { !$0.isEmpty }
        )
        if let officialSeriesTitle = firstPathCapture(
            in: seriesHTML,
            pattern:
                #"(?is)<h2[^>]*class\s*=\s*["'][^"']*topper[^"']*["'][^>]*>(.*?)</h2>"#
        )
        .map({
            decodedPublisherHTML($0).replacingOccurrences(
                of: #"(?i)^\s*Series\s*:\s*"#,
                with: "",
                options: .regularExpression
            )
        }) {
            let title = sevenSeasBaseTitle(officialSeriesTitle)
            if !title.isEmpty {
                referenceTitles.insert(title)
            }
        }
        guard !referenceTitles.isEmpty else { return [] }

        let html = seriesHTML.replacingOccurrences(
            of: #"(?is)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
        let pattern =
            #"(?is)<a(?=[^>]*\bclass\s*=\s*["'][^"']*\bseries-volume\b[^"']*["'])[^>]+href\s*=\s*["']([^"']+/(?:books|audio_books)/[^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var pages: [(URL, String, Double)] = []
        var seen = Set<String>()
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range)
        where match.numberOfRanges > 2 {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let title = decodedPublisherHTML(String(html[titleRange]))
            let mediaType = sevenSeasMediaType(in: title)
            let baseTitle = sevenSeasBaseTitle(title)
            let matchesSeries = referenceTitles.contains(baseTitle)
                || referenceTitles.contains {
                    officialPublisherCandidateTitle(
                        baseTitle,
                        matches: $0
                    )
                }
            let isCompatible =
                mediaType == nil
                || mediaType == expectedMediaType
                || (expectedMediaType == "novel"
                    && mediaType == "audiobook")
            guard isCompatible,
                  matchesSeries,
                  let volume = SableLibraryCoverDownloadPlanner
                    .explicitVolumeNumber(in: title),
                  let url = URL(
                    string: decodedPublisherHTML(
                        String(html[urlRange])
                    )
                  ),
                  url.host?.lowercased()
                    == "sevenseasentertainment.com",
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            pages.append((url, mediaType ?? "", volume))
        }
        return pages.sorted {
            if $0.1 != $1.1 {
                return $0.1 < $1.1
            }
            return $0.2 < $1.2
        }
        .map(\.0)
    }

    static func sevenSeasPublisherReferences(
        in pageHTML: String,
        pageURL: URL
    ) -> [OfficialPublisherReference] {
        guard let title = firstPathCapture(
            in: pageHTML,
            pattern:
                #"(?is)<h2[^>]*class\s*=\s*["'][^"']*topper[^"']*["'][^>]*>(.*?)</h2>"#
        )
        .map(decodedPublisherHTML)?
        .replacingOccurrences(
            of: #"(?i)^\s*Book\s*:\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines),
              let mediaType = sevenSeasPageMediaType(
                in: pageHTML,
                title: title
              ),
              let volumeNumber = SableLibraryCoverDownloadPlanner
                .explicitVolumeNumber(in: title),
              let rawImageURL = firstPathCapture(
                in: pageHTML,
                pattern:
                    #"(?is)<div[^>]+id\s*=\s*["']volume-cover["'][^>]*>.*?<img[^>]+src\s*=\s*["']([^"']+)["']"#
              ),
              let imageURL = URL(
                string: decodedPublisherHTML(rawImageURL),
                relativeTo: pageURL
              )?.absoluteURL else {
            return []
        }
        let imprints = sevenSeasImprints(in: pageHTML)
        let imprint = imprints.isEmpty
            ? nil
            : imprints.joined(separator: " + ")

        let linkPattern =
            #"(?is)<a[^>]+href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: linkPattern
        ) else {
            return []
        }
        let isAudiobook = mediaType == "audiobook"
        var preferred:
            [SableLibraryBigBookCoversProvider: OfficialPublisherReference] =
            [:]
        let range = NSRange(
            pageHTML.startIndex..<pageHTML.endIndex,
            in: pageHTML
        )
        for match in regex.matches(in: pageHTML, range: range)
        where match.numberOfRanges > 2 {
            guard let urlRange = Range(match.range(at: 1), in: pageHTML),
                  let bodyRange = Range(match.range(at: 2), in: pageHTML)
            else {
                continue
            }
            let body = String(pageHTML[bodyRange])
            let label = firstPathCapture(
                in: body,
                pattern:
                    #"(?is)(?:alt|title)\s*=\s*["']([^"']+)["']"#
            )
            .map(decodedPublisherHTML)
            ?? decodedPublisherHTML(body)
            let rawURL = decodedPublisherHTML(
                String(pageHTML[urlRange])
            )
            guard let storeURL = URL(
                string: rawURL,
                relativeTo: pageURL
            )?.absoluteURL,
                  let provider = sevenSeasRetailerProvider(
                    label: label,
                    url: storeURL,
                    isAudiobook: isAudiobook
                  ) else {
                continue
            }
            preferred[provider] = OfficialPublisherReference(
                provider: provider,
                title: title,
                imageURL: imageURL.absoluteString,
                storeURL: storeURL.absoluteString,
                volumeNumber: volumeNumber,
                coverType: isAudiobook ? "audiobook" : "volume",
                mediaType: mediaType,
                pageURL: pageURL.absoluteString,
                publisherFamily: "Seven Seas",
                imprint: imprint,
                publicationType:
                    provider.isRakutenKobo ? "digital" : nil
            )
        }
        return preferred.values.sorted {
            $0.provider.discoveryPriority < $1.provider.discoveryPriority
        }
    }

    static func sevenSeasImprints(in pageHTML: String) -> [String] {
        guard let divRegex = try? NSRegularExpression(
            pattern: #"(?is)<div\b([^>]*)>"#
        ),
              let idRegex = try? NSRegularExpression(
                pattern: #"\bid\s*=\s*["']([^"']+-block)["']"#
              ),
              let classRegex = try? NSRegularExpression(
                pattern: #"\bclass\s*=\s*["'][^"']*\bage-rating\b[^"']*["']"#
              ) else {
            return []
        }
        let knownImprints = [
            "as-block": "Airship",
            "danmei-block": "Danmei",
            "gs-block": "Ghost Ship",
            "siren-block": "Siren",
            "ss-block": "Steamship",
            "waves-block": "Waves of Color",
            "waves-of-color-block": "Waves of Color",
            "webtoons-block": "Webtoons"
        ]
        var imprints: [String] = []
        var seen = Set<String>()
        let range = NSRange(
            pageHTML.startIndex..<pageHTML.endIndex,
            in: pageHTML
        )
        for match in divRegex.matches(in: pageHTML, range: range)
        where match.numberOfRanges > 1 {
            guard let attributesRange = Range(
                match.range(at: 1),
                in: pageHTML
            ) else {
                continue
            }
            let attributes = String(pageHTML[attributesRange])
            let attributeSearchRange = NSRange(
                attributes.startIndex..<attributes.endIndex,
                in: attributes
            )
            guard classRegex.firstMatch(
                in: attributes,
                range: attributeSearchRange
            ) != nil,
                  let idMatch = idRegex.firstMatch(
                    in: attributes,
                    range: attributeSearchRange
                  ),
                  idMatch.numberOfRanges > 1,
                  let idRange = Range(
                    idMatch.range(at: 1),
                    in: attributes
                  ) else {
                continue
            }
            let identifier = String(attributes[idRange]).lowercased()
            guard let imprint = knownImprints[identifier],
                  seen.insert(imprint).inserted else {
                continue
            }
            imprints.append(imprint)
        }
        return imprints
    }

    private func kodanshaPublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        guard Self.officialEnglishMangaCatalogIsRequested(
            for: series,
            languages: languages
        ) else {
            return []
        }

        var seriesPageURL: URL?
        var volumePageURLs: [URL] = []
        let titles = Self.sevenSeasRequestedTitles(for: series)
        for title in titles.prefix(4) {
            let slug = Self.officialPublisherCatalogSlug(title)
            guard !slug.isEmpty,
                  let candidateURL = URL(
                    string: "https://kodansha.us/series/\(slug)/"
                  ),
                  let html = await Self.storefrontPageHTML(
                    from: candidateURL.absoluteString
                  ) else {
                continue
            }
            let pages = Self.kodanshaVolumePageURLs(
                in: html,
                series: series
            )
            if !pages.isEmpty {
                seriesPageURL = candidateURL
                volumePageURLs = pages
                break
            }
        }
        guard let seriesPageURL else { return [] }
        return await officialPublisherReferences(
            pageURLs: volumePageURLs,
            referer: seriesPageURL
        ) { html, pageURL in
            Self.kodanshaPublisherReferences(
                in: html,
                pageURL: pageURL
            )
        }
    }

    static func kodanshaVolumePageURLs(
        in seriesHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        guard seriesHTML.range(
            of: "digital manga series",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil,
              let catalogTitle = firstPathCapture(
                in: seriesHTML,
                pattern:
                    #"(?is)<h1[^>]+class\s*=\s*["'][^"']*series__single__title[^"']*["'][^>]*>(.*?)</h1>"#
              )
              .map(decodedPublisherHTML),
              officialPublisherTitle(
                catalogTitle,
                matches: series
              ) else {
            return []
        }

        let pattern =
            #"(?is)href\s*=\s*["'](https://kodansha\.us/series/[^"']+/volume-[^"'#?]+/?)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var pages: [(URL, Double)] = []
        var seen = Set<String>()
        let range = NSRange(
            seriesHTML.startIndex..<seriesHTML.endIndex,
            in: seriesHTML
        )
        for match in regex.matches(in: seriesHTML, range: range)
        where match.numberOfRanges > 1 {
            guard let urlRange = Range(match.range(at: 1), in: seriesHTML),
                  let url = URL(
                    string: decodedPublisherHTML(
                        String(seriesHTML[urlRange])
                    )
                  ),
                  let volumeText = firstPathCapture(
                    in: url.path,
                    pattern: #"(?i)/volume-([0-9]+(?:\.[0-9]+)?)/?$"#
                  ),
                  let volume = Double(volumeText),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            pages.append((url, volume))
        }
        return pages.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static func kodanshaPublisherReferences(
        in pageHTML: String,
        pageURL: URL
    ) -> [OfficialPublisherReference] {
        guard let rawTitle = publisherMetaContent(
            "og:title",
            in: pageHTML
        ),
              let rawImageURL = publisherMetaContent(
                "og:image",
                in: pageHTML
              ),
              let imageURL = URL(
                string: decodedPublisherHTML(rawImageURL),
                relativeTo: pageURL
              )?.absoluteURL else {
            return []
        }
        let title = decodedPublisherHTML(rawTitle)
            .replacingOccurrences(
                of: #"\s*\|\s*Kodansha\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return officialRetailerReferences(
            title: title,
            imageURL: imageURL,
            pageHTML: pageHTML,
            pageURL: pageURL,
            mediaType: "manga",
            publisherFamily: "Kodansha"
        )
    }

    private func vizPublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        guard Self.officialEnglishMangaCatalogIsRequested(
            for: series,
            languages: languages
        ) else {
            return []
        }
        var searchURL: URL?
        var volumePageURLs: [URL] = []
        for title in Self.sevenSeasRequestedTitles(for: series).prefix(4) {
            var components = URLComponents(
                string: "https://www.viz.com/search"
            )
            components?.queryItems = [
                URLQueryItem(name: "search", value: title),
                URLQueryItem(name: "category", value: "Manga"),
                URLQueryItem(name: "all", value: "100")
            ]
            guard let candidateURL = components?.url,
                  let html = await Self.storefrontPageHTML(
                    from: candidateURL.absoluteString
                  ) else {
                continue
            }
            let pages = Self.vizVolumePageURLs(
                in: html,
                series: series
            )
            if !pages.isEmpty {
                searchURL = candidateURL
                volumePageURLs = Self
                    .officialPublisherAnchorPageURLs(from: pages)
                break
            }
        }
        guard let searchURL else { return [] }
        return await officialPublisherReferences(
            pageURLs: Self.vizRetailerPageURLs(from: volumePageURLs),
            referer: searchURL,
            sampleAnchorPages: false
        ) { html, pageURL in
            Self.vizPublisherReferences(
                in: html,
                pageURL: pageURL
            )
        }
    }

    static func vizVolumePageURLs(
        in searchHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        let pattern =
            #"(?is)<a[^>]+href\s*=\s*["'](/manga-books/manga/[^"']+/product/\d+)["'][^>]*>(.*?)</a>"#
        return officialPublisherVolumePageURLs(
            in: searchHTML,
            pattern: pattern,
            baseURL: URL(string: "https://www.viz.com"),
            series: series
        )
    }

    static func vizRetailerPageURLs(from pageURLs: [URL]) -> [URL] {
        officialPublisherAnchorPageURLs(from: pageURLs).flatMap { pageURL in
            [
                pageURL.appendingPathComponent("paperback"),
                pageURL.appendingPathComponent("digital")
            ]
        }
    }

    static func vizPublisherReferences(
        in pageHTML: String,
        pageURL: URL
    ) -> [OfficialPublisherReference] {
        guard let rawTitle = publisherMetaContent(
            "og:title",
            in: pageHTML
        ),
              let rawImageURL = publisherMetaContent(
                "og:image",
                in: pageHTML
              ),
              let imageURL = URL(
                string: decodedPublisherHTML(rawImageURL),
                relativeTo: pageURL
              )?.absoluteURL else {
            return []
        }
        let title = decodedPublisherHTML(rawTitle)
            .replacingOccurrences(
                of: #"(?i)^\s*VIZ\s*:\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)^\s*Read a Free Preview of\s+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return officialRetailerReferences(
            title: title,
            imageURL: imageURL,
            pageHTML: pageHTML,
            pageURL: pageURL,
            mediaType: "manga",
            publisherFamily: "VIZ Media"
        )
    }

    private func darkHorsePublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        guard Self.officialEnglishMangaCatalogIsRequested(
            for: series,
            languages: languages
        ) else {
            return []
        }
        var searchURL: URL?
        var volumePageURLs: [URL] = []
        for title in Self.sevenSeasRequestedTitles(for: series).prefix(4) {
            var components = URLComponents(
                string: "https://www.darkhorse.com/search/"
            )
            components?.queryItems = [
                URLQueryItem(name: "s", value: title)
            ]
            guard let candidateURL = components?.url,
                  let html = await Self.storefrontPageHTML(
                    from: candidateURL.absoluteString
                  ) else {
                continue
            }
            let pages = Self.darkHorseVolumePageURLs(
                in: html,
                series: series
            )
            if !pages.isEmpty {
                searchURL = candidateURL
                volumePageURLs = pages
                break
            }
        }
        guard let searchURL else { return [] }
        return await officialPublisherReferences(
            pageURLs: volumePageURLs,
            referer: searchURL
        ) { html, pageURL in
            Self.darkHorsePublisherReferences(
                in: html,
                pageURL: pageURL
            )
        }
    }

    static func darkHorseVolumePageURLs(
        in searchHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        let pattern =
            #"(?is)<a[^>]+href\s*=\s*["'](/books/[^"']+)["'][^>]*>(.*?)</a>"#
        return officialPublisherVolumePageURLs(
            in: searchHTML,
            pattern: pattern,
            baseURL: URL(string: "https://www.darkhorse.com"),
            series: series
        )
    }

    static func darkHorsePublisherReferences(
        in pageHTML: String,
        pageURL: URL
    ) -> [OfficialPublisherReference] {
        guard pageHTML.range(
            of: #"/search/genre:manga/"#,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil,
              let rawTitle = publisherMetaContent(
                "og:title",
                in: pageHTML
              ),
              let rawImageURL = publisherMetaContent(
                "og:image",
                in: pageHTML
              ),
              let imageURL = URL(
                string: decodedPublisherHTML(rawImageURL),
                relativeTo: pageURL
              )?.absoluteURL else {
            return []
        }
        let title = decodedPublisherHTML(rawTitle)
            .replacingOccurrences(
                of: #"(?is)\s*::\s*Profile.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\s+TPB\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return officialRetailerReferences(
            title: title,
            imageURL: imageURL,
            pageHTML: pageHTML,
            pageURL: pageURL,
            mediaType: "manga",
            publisherFamily: "Dark Horse Manga"
        )
    }

    private func squareEnixPublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        let requestedLanguages = languages?.map(Self.normalizedLanguageTag)
        let expectedMediaType = SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(mediaType: series.type)
        guard (requestedLanguages == nil
            || requestedLanguages?.contains("en") == true),
              expectedMediaType == "manga"
                || expectedMediaType == "novel",
              let indexURL = URL(
                string:
                    "https://squareenixmangaandbooks.square-enix-games.com/en-us/series"
              ),
              let indexHTML = await Self.storefrontPageHTML(
                from: indexURL.absoluteString
              ) else {
            return []
        }

        for seriesPageURL in Self.squareEnixSeriesPageURLs(
            in: indexHTML,
            series: series
        ).prefix(2) {
            guard let seriesHTML = await Self.storefrontPageHTML(
                from: seriesPageURL.absoluteString,
                referer: indexURL.absoluteString
            ) else {
                continue
            }
            let productURLs = Self.squareEnixVolumePageURLs(
                in: seriesHTML,
                series: series
            )
            guard !productURLs.isEmpty else { continue }
            return await officialPublisherReferences(
                pageURLs: productURLs,
                referer: seriesPageURL
            ) { html, pageURL in
                Self.squareEnixPublisherReferences(
                    in: html,
                    pageURL: pageURL
                )
            }
        }
        return []
    }

    static func squareEnixSeriesPageURLs(
        in indexHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        let pattern =
            #"(?is)<a[^>]+href\s*=\s*["'](/en-us/series/[^"']+)["'][^>]*>.*?<img[^>]+alt\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var pages: [URL] = []
        var seen = Set<String>()
        let range = NSRange(
            indexHTML.startIndex..<indexHTML.endIndex,
            in: indexHTML
        )
        for match in regex.matches(in: indexHTML, range: range)
        where match.numberOfRanges > 2 {
            guard let pathRange = Range(
                match.range(at: 1),
                in: indexHTML
            ),
            let titleRange = Range(
                match.range(at: 2),
                in: indexHTML
            ),
            officialPublisherTitle(
                decodedPublisherHTML(String(indexHTML[titleRange])),
                matches: series
            ),
            let pageURL = URL(
                string: decodedPublisherHTML(
                    String(indexHTML[pathRange])
                ),
                relativeTo: URL(
                    string:
                        "https://squareenixmangaandbooks.square-enix-games.com"
                )
            )?.absoluteURL,
            seen.insert(pageURL.absoluteString).inserted else {
                continue
            }
            pages.append(pageURL)
        }
        return pages
    }

    static func squareEnixVolumePageURLs(
        in seriesHTML: String,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        officialPublisherVolumePageURLs(
            in: seriesHTML,
            pattern:
                #"(?is)<a[^>]+href\s*=\s*["'](/en-us/product/\d+)["'][^>]*>.*?<img[^>]+alt\s*=\s*["']([^"']+)["']"#,
            baseURL: URL(
                string:
                    "https://squareenixmangaandbooks.square-enix-games.com"
            ),
            series: series
        )
    }

    static func squareEnixPublisherReferences(
        in pageHTML: String,
        pageURL: URL
    ) -> [OfficialPublisherReference] {
        guard let rawTitle = publisherMetaContent(
            "og:title",
            in: pageHTML
        ),
        let rawImageURL = firstPathCapture(
            in: pageHTML,
            pattern:
                #"(?is)<img[^>]+class\s*=\s*["'][^"']*\bw-full\b[^"']*["'][^>]+src\s*=\s*["']([^"']+)["']"#
        ),
        let imageURL = URL(
            string: decodedPublisherHTML(rawImageURL),
            relativeTo: pageURL
        )?.absoluteURL,
        let category = firstPathCapture(
            in: pageHTML,
            pattern:
                #"(?is)>\s*category:\s*</span>\s*<span[^>]*>([^<]+)</span>"#
        )
        .map(decodedPublisherHTML),
        let mediaType = sevenSeasMediaType(in: category) else {
            return []
        }
        let title = decodedPublisherHTML(rawTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return officialRetailerReferences(
            title: title,
            imageURL: squareEnixHighResolutionImageURL(imageURL),
            pageHTML: pageHTML,
            pageURL: pageURL,
            mediaType: mediaType,
            publisherFamily: "Square Enix Manga & Books"
        )
    }

    private static func squareEnixHighResolutionImageURL(
        _ url: URL
    ) -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.host?.lowercased() == "fyre.cdn.sewest.net" else {
            return url
        }
        var queryItems = components.queryItems ?? []
        if let widthIndex = queryItems.firstIndex(where: {
            $0.name.caseInsensitiveCompare("width") == .orderedSame
        }) {
            queryItems[widthIndex].value = "1600"
        } else {
            queryItems.append(URLQueryItem(name: "width", value: "1600"))
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func shueishaPublisherReferences(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) async -> [OfficialPublisherReference] {
        guard languages?.contains("ja") ?? true,
              SableLibraryCoverDownloadPlanner
                .providerMediaTypeIsCompatible(
                    series.type,
                    isCompatibleWith: "manga"
                ) else {
            return []
        }
        let hasPublisherEvidence = Self.shueishaPublisherIsTrusted(
            for: series
        )
        for title in Self.shueishaRequestedTitles(for: series).prefix(4) {
            guard var components = URLComponents(
                string:
                    "https://www.shueisha.co.jp/books/search/search.html"
            ) else {
                continue
            }
            components.queryItems = [
                URLQueryItem(name: "titleauthor", value: title)
            ]
            guard let searchURL = components.url,
                  let html = await Self.storefrontPageHTML(
                    from: searchURL.absoluteString
                  ),
                  let payload = Self.shueishaSearchPayload(in: html),
                  let matchedSeries = Self.shueishaMatchedSeries(
                    in: payload,
                    for: series
                  ) else {
                continue
            }

            var completeSeries = matchedSeries
            var referenceURL = searchURL
            if var seriesComponents = URLComponents(
                string:
                    "https://www.shueisha.co.jp/books/search/search.html"
            ) {
                seriesComponents.queryItems = [
                    URLQueryItem(
                        name: "seriesid",
                        value: String(matchedSeries.seriesId)
                    )
                ]
                if let seriesURL = seriesComponents.url,
                   let seriesHTML = await Self.storefrontPageHTML(
                    from: seriesURL.absoluteString
                   ),
                   let fullSeries = Self.shueishaFullSeries(
                    in: seriesHTML
                   ),
                   fullSeries.seriesId == matchedSeries.seriesId {
                    completeSeries = fullSeries
                    referenceURL = seriesURL
                }
            }
            return Self.shueishaPublisherReferences(
                from: completeSeries,
                searchURL: referenceURL,
                requiresRelationshipReview: !hasPublisherEvidence
            )
        }
        return []
    }

    static func shueishaSearchPayload(
        in html: String
    ) -> ShueishaSearchPayload? {
        guard let json = firstPathCapture(
            in: html,
            pattern:
                #"(?s)var\s+ssd\s*=\s*(\{.*?\});\s*var\s+order\s*="#
        ) else {
            return nil
        }
        return try? JSONDecoder().decode(
            ShueishaSearchPayload.self,
            from: Data(json.utf8)
        )
    }

    static func shueishaFullSeries(
        in html: String
    ) -> ShueishaSearchPayload.Series? {
        guard let json = firstPathCapture(
            in: html,
            pattern:
                #"(?s)var\s+ssd\s*=\s*(\{.*?\});\s*var\s+order\s*="#
        ),
        let payload = try? JSONDecoder().decode(
            ShueishaSeriesPayload.self,
            from: Data(json.utf8)
        ) else {
            return nil
        }
        return ShueishaSearchPayload.Series(
            seriesId: payload.data.seriesData.seriesId,
            seriesName: payload.data.seriesData.seriesName,
            labelName: payload.data.seriesData.labelName,
            genreDatas: payload.data.seriesData.genreDatas,
            itemDatas: payload.data.itemDatas
        )
    }

    private static func shueishaMatchedSeries(
        in payload: ShueishaSearchPayload,
        for series: SableMangaBakaSeriesSummary
    ) -> ShueishaSearchPayload.Series? {
        let requestedTitles = shueishaRequestedTitles(for: series)
        return payload.datas
            .filter { candidate in
                requestedTitles.contains {
                    officialPublisherCandidateTitle(
                        candidate.seriesName,
                        matches: $0
                    )
                }
            }
            .sorted { lhs, rhs in
                let lhsExact = requestedTitles.contains {
                    normalizedPublisherCatalogTitle(lhs.seriesName)
                        == normalizedPublisherCatalogTitle($0)
                }
                let rhsExact = requestedTitles.contains {
                    normalizedPublisherCatalogTitle(rhs.seriesName)
                        == normalizedPublisherCatalogTitle($0)
                }
                if lhsExact != rhsExact {
                    return lhsExact
                }
                return lhs.itemDatas.count > rhs.itemDatas.count
            }
            .first
    }

    static func shueishaPublisherReferences(
        from series: ShueishaSearchPayload.Series,
        searchURL: URL,
        requiresRelationshipReview: Bool
    ) -> [OfficialPublisherReference] {
        let mediaType = shueishaMediaType(
            label: series.labelName,
            genres: series.genreDatas
        )
        return series.itemDatas.flatMap { item -> [OfficialPublisherReference] in
            guard let volumeText = item.viewVolumeNumber?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let volumeNumber = Double(volumeText),
                  let rawImageURL = item.imageURL,
                  let frontURL = shueishaHighResolutionImageURL(
                    rawImageURL
                  ),
                  let isbn = item.isbn.map(shueishaISBNKey),
                  !isbn.isEmpty,
                  var pageComponents = URLComponents(
                    string:
                        "https://www.shueisha.co.jp/books/items/contents.html"
                  ) else {
                return []
            }
            pageComponents.queryItems = [
                URLQueryItem(name: "isbn", value: item.isbn)
            ]
            guard let pageURL = pageComponents.url else { return [] }
            let shared = (
                title: item.itemName,
                pageURL: pageURL.absoluteString
            )
            let front = OfficialPublisherReference(
                provider: .shueisha,
                title: shared.title,
                imageURL: frontURL,
                storeURL: shared.pageURL,
                volumeNumber: volumeNumber,
                coverType: "volume",
                mediaType: mediaType,
                pageURL: shared.pageURL,
                publisherFamily: "Shueisha",
                imprint: series.labelName,
                language: "ja",
                publicationType: "physical",
                requiresRelationshipReview:
                    requiresRelationshipReview
            )
            guard let backURL = shueishaBackCoverImageURL(frontURL)
            else {
                return [front]
            }
            let back = OfficialPublisherReference(
                provider: .shueisha,
                title: shared.title,
                imageURL: backURL,
                storeURL: shared.pageURL,
                volumeNumber: volumeNumber,
                coverType: "volume_back",
                mediaType: mediaType,
                pageURL: shared.pageURL,
                publisherFamily: "Shueisha",
                imprint: series.labelName,
                language: "ja",
                publicationType: "physical",
                requiresRelationshipReview:
                    requiresRelationshipReview
            )
            return [front, back]
        }
    }

    private static func shueishaRequestedTitles(
        for series: SableMangaBakaSeriesSummary
    ) -> [String] {
        let japaneseTitles = (series.titles ?? [])
            .filter {
                normalizedLanguageTag($0.language).hasPrefix("ja")
            }
            .map(\.title)
        return SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            [
                series.nativeTitle
            ].compactMap { $0 } + japaneseTitles + [
                series.title,
                series.romanizedTitle
            ].compactMap { $0 }
        )
    }

    private static func shueishaPublisherIsTrusted(
        for series: SableMangaBakaSeriesSummary
    ) -> Bool {
        let publisherText = (series.publishers ?? []).flatMap {
            [$0.name, $0.type, $0.note].compactMap { $0 }
        }
        .joined(separator: " ")
        .lowercased()
        return [
            "shueisha",
            "集英社",
            "jump comics",
            "ジャンプコミックス",
            "young jump",
            "ヤングジャンプ"
        ].contains {
            publisherText.contains($0.lowercased())
        }
    }

    private static func shueishaMediaType(
        label: String?,
        genres: [String]?
    ) -> String {
        let proof = ([label].compactMap { $0 } + (genres ?? []))
            .joined(separator: " ")
        return proof.contains("コミックス") ? "manga" : "novel"
    }

    private static func shueishaHighResolutionImageURL(
        _ value: String
    ) -> String? {
        guard var components = URLComponents(string: value),
              components.host?.lowercased()
                == "dosbg3xlm0x1t.cloudfront.net" else {
            return nil
        }
        components.path = components.path.replacingOccurrences(
            of: "/240/",
            with: "/1200/"
        )
        return components.url?.absoluteString
    }

    private static func shueishaBackCoverImageURL(
        _ frontURL: String
    ) -> String? {
        guard var components = URLComponents(string: frontURL) else {
            return nil
        }
        let extensionStart = components.path.lastIndex(of: ".")
        guard let extensionStart else { return nil }
        components.path.insert(contentsOf: "_130", at: extensionStart)
        return components.url?.absoluteString
    }

    private static func shueishaISBNKey(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private func officialPublisherReferences(
        pageURLs: [URL],
        referer: URL,
        sampleAnchorPages: Bool = true,
        parser: @escaping @Sendable (
            String,
            URL
        ) -> [OfficialPublisherReference]
    ) async -> [OfficialPublisherReference] {
        let pageURLs =
            sampleAnchorPages
            ? Self.officialPublisherAnchorPageURLs(from: pageURLs)
            : pageURLs
        var references: [OfficialPublisherReference] = []
        for batchStart in stride(from: 0, to: pageURLs.count, by: 3) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                pageURLs[
                    batchStart..<min(batchStart + 3, pageURLs.count)
                ]
            )
            let found = await withTaskGroup(
                of: (
                    URL,
                    Bool,
                    [OfficialPublisherReference]
                ).self
            ) { group in
                for pageURL in batch {
                    group.addTask {
                        guard let html = await Self.storefrontPageHTML(
                            from: pageURL.absoluteString,
                            referer: referer.absoluteString
                        ) else {
                            return (pageURL, false, [])
                        }
                        return (
                            pageURL,
                            true,
                            parser(html, pageURL)
                        )
                    }
                }
                var found:
                    [(
                        URL,
                        Bool,
                        [OfficialPublisherReference]
                    )] = []
                for await pageResult in group {
                    found.append(pageResult)
                }
                return found
            }
            references.append(
                contentsOf: found.flatMap(\.2)
            )

            let failedURLs = found
                .filter { !$0.1 }
                .map(\.0)
            if !failedURLs.isEmpty {
                try? await Task.sleep(
                    nanoseconds: 900_000_000
                )
                for pageURL in failedURLs {
                    guard !Task.isCancelled else { break }
                    if let html = await Self.storefrontPageHTML(
                        from: pageURL.absoluteString,
                        referer: referer.absoluteString
                    ) {
                        references.append(
                            contentsOf: parser(html, pageURL)
                        )
                    }
                    try? await Task.sleep(
                        nanoseconds: 250_000_000
                    )
                }
            }
            if batchStart + batch.count < pageURLs.count {
                try? await Task.sleep(
                    nanoseconds: 400_000_000
                )
            }
        }
        return references.sorted {
            if $0.volumeNumber != $1.volumeNumber {
                return $0.volumeNumber < $1.volumeNumber
            }
            return $0.provider.discoveryPriority
                < $1.provider.discoveryPriority
        }
    }

    private static func officialEnglishMangaCatalogIsRequested(
        for series: SableMangaBakaSeriesSummary,
        languages: Set<String>?
    ) -> Bool {
        let requestedLanguages = languages?.map(normalizedLanguageTag)
        let mediaType = SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(mediaType: series.type)
        return (requestedLanguages == nil
            || requestedLanguages?.contains("en") == true)
            && mediaType == "manga"
    }

    private static func officialPublisherCatalogSlug(
        _ value: String
    ) -> String {
        decodedPublisherHTML(value)
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(
                of: #"['’]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func officialPublisherTitle(
        _ value: String,
        matches series: SableMangaBakaSeriesSummary
    ) -> Bool {
        let candidate = normalizedPublisherCatalogTitle(
            officialPublisherSeriesTitle(from: value)
        )
        guard !candidate.isEmpty else { return false }
        return sevenSeasRequestedTitles(for: series).contains {
            normalizedPublisherCatalogTitle(
                officialPublisherSeriesTitle(from: $0)
            ) == candidate
        }
    }

    private static func officialPublisherVolumePageURLs(
        in html: String,
        pattern: String,
        baseURL: URL?,
        series: SableMangaBakaSeriesSummary
    ) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var pages: [(URL, Double)] = []
        var seen = Set<String>()
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range)
        where match.numberOfRanges > 2 {
            guard let pathRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let title = decodedPublisherHTML(String(html[bodyRange]))
            guard officialPublisherTitle(title, matches: series),
                  let volumeNumber = SableLibraryCoverDownloadPlanner
                    .explicitVolumeNumber(in: title),
                  let url = URL(
                    string: decodedPublisherHTML(
                        String(html[pathRange])
                    ),
                    relativeTo: baseURL
                  )?.absoluteURL,
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            pages.append((url, volumeNumber))
        }
        return pages.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static func officialPublisherAnchorPageURLs(
        from pageURLs: [URL]
    ) -> [URL] {
        guard pageURLs.count > 3 else { return pageURLs }
        let anchors = [
            pageURLs[0],
            pageURLs[1],
            pageURLs[pageURLs.count - 1]
        ]
        var seen = Set<String>()
        return anchors.filter {
            seen.insert($0.absoluteString).inserted
        }
    }

    private static func officialRetailerReferences(
        title: String,
        imageURL: URL,
        pageHTML: String,
        pageURL: URL,
        mediaType: String,
        publisherFamily: String,
        imprint: String? = nil
    ) -> [OfficialPublisherReference] {
        guard let volumeNumber = SableLibraryCoverDownloadPlanner
            .explicitVolumeNumber(in: title),
              let regex = try? NSRegularExpression(
                pattern:
                    #"(?is)<a[^>]+href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
              ) else {
            return []
        }
        var preferred:
            [SableLibraryBigBookCoversProvider: OfficialPublisherReference] =
            [:]
        let range = NSRange(
            pageHTML.startIndex..<pageHTML.endIndex,
            in: pageHTML
        )
        for match in regex.matches(in: pageHTML, range: range)
        where match.numberOfRanges > 2 {
            guard let urlRange = Range(match.range(at: 1), in: pageHTML),
                  let bodyRange = Range(match.range(at: 2), in: pageHTML),
                  let storeURL = URL(
                    string: decodedPublisherHTML(
                        String(pageHTML[urlRange])
                    ),
                    relativeTo: pageURL
                  )?.absoluteURL,
                  let provider = sevenSeasRetailerProvider(
                    label: decodedPublisherHTML(
                        String(pageHTML[bodyRange])
                    ),
                    url: storeURL,
                    isAudiobook: mediaType == "audiobook"
                  ) else {
                continue
            }
            let normalizedStoreURL: URL
            if provider.isBarnesNoble,
               let canonical = canonicalBarnesNobleStoreURL(
                storeURL.absoluteString
               ),
               let canonicalURL = URL(string: canonical) {
                normalizedStoreURL = canonicalURL
            } else {
                normalizedStoreURL = storeURL
            }
            preferred[provider] = OfficialPublisherReference(
                provider: provider,
                title: title,
                imageURL: imageURL.absoluteString,
                storeURL: normalizedStoreURL.absoluteString,
                volumeNumber: volumeNumber,
                coverType:
                    mediaType == "audiobook" ? "audiobook" : "volume",
                mediaType: mediaType,
                pageURL: pageURL.absoluteString,
                publisherFamily: publisherFamily,
                imprint: imprint,
                providerItemID:
                    provider.isBarnesNoble
                    ? barnesNobleProductID(from: normalizedStoreURL)
                    : provider.isCrunchyrollStore
                        ? crunchyrollProductID(from: normalizedStoreURL)
                        : nil,
                publicationType:
                    provider.isRakutenKobo ? "digital" : nil
            )
        }
        return preferred.values.sorted {
            $0.provider.discoveryPriority < $1.provider.discoveryPriority
        }
    }

    private static func publisherMetaContent(
        _ property: String,
        in html: String
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(
            for: property
        )
        return firstPathCapture(
            in: html,
            pattern:
                #"(?is)<meta[^>]+(?:property|name)\s*=\s*["']\#(escaped)["'][^>]+content\s*=\s*["']([^"']+)["']"#
        ) ?? firstPathCapture(
            in: html,
            pattern:
                #"(?is)<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+(?:property|name)\s*=\s*["']\#(escaped)["']"#
        )
    }

    private func barnesNobleReferencesByLoadingProductArtwork(
        _ references: [OfficialPublisherReference]
    ) async -> [OfficialPublisherReference] {
        var enriched = references
        let indexes = references.indices.filter {
            references[$0].provider.isBarnesNoble
        }
        for batchStart in stride(from: 0, to: indexes.count, by: 4) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                indexes[
                    batchStart..<min(batchStart + 4, indexes.count)
                ]
            )
            let products = await withTaskGroup(
                of: (Int, String?, String?, String?).self
            ) { group in
                for index in batch {
                    let reference = references[index]
                    group.addTask {
                        guard let html = await Self.storefrontPageHTML(
                            from: reference.storeURL,
                            referer: reference.pageURL
                        ) else {
                            return (index, nil, nil, nil)
                        }
                        return (
                            index,
                            Self.publisherMetaContent(
                                "og:title",
                                in: html
                            ),
                            Self.publisherMetaContent(
                                "og:image",
                                in: html
                            ),
                            URL(string: reference.storeURL).flatMap {
                                Self.barnesNobleProductID(from: $0)
                            }
                        )
                    }
                }
                var values: [(Int, String?, String?, String?)] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }
            for (index, title, imageURL, productID) in products {
                if let title = title.map(Self.decodedPublisherHTML),
                   !title.isEmpty {
                    enriched[index].title = title
                }
                if let imageURL = imageURL.map(Self.decodedPublisherHTML),
                   URL(string: imageURL) != nil {
                    enriched[index].imageURL = imageURL
                }
                if let productID, !productID.isEmpty {
                    enriched[index].providerItemID = productID
                }
            }
        }
        return enriched
    }

    private func crunchyrollReferencesByLoadingProductArtwork(
        _ references: [OfficialPublisherReference]
    ) async -> [OfficialPublisherReference] {
        var expanded: [OfficialPublisherReference] = []
        for reference in references {
            guard reference.provider.isCrunchyrollStore else {
                expanded.append(reference)
                continue
            }
            guard let html = await Self.storefrontPageHTML(
                from: reference.storeURL,
                referer: reference.pageURL
            ) else {
                expanded.append(reference)
                continue
            }
            let productReferences = Self.crunchyrollProductReferences(
                in: html,
                reference: reference
            )
            expanded.append(
                contentsOf:
                    productReferences.isEmpty
                    ? [reference]
                    : productReferences
            )
        }
        return expanded
    }

    static func crunchyrollProductReferences(
        in pageHTML: String,
        reference: OfficialPublisherReference
    ) -> [OfficialPublisherReference] {
        guard let rawArray = firstPathCapture(
            in: pageHTML,
            pattern: #"(?s)"images"\s*:\s*(\[\s*\{.*?\}\s*\])"#
        ),
        let data = rawArray.data(using: .utf8),
        let images = try? JSONSerialization.jsonObject(with: data)
            as? [[String: Any]] else {
            return []
        }
        var imageURLs: [String] = []
        var seen = Set<String>()
        for image in images {
            let rawURL = (image["disBaseLink"] as? String)
                ?? (image["link"] as? String)
            guard let rawURL,
                  let url = URL(string: rawURL),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            imageURLs.append(url.absoluteString)
        }
        guard !imageURLs.isEmpty else { return [] }
        let productID = URL(string: reference.storeURL).flatMap {
            crunchyrollProductID(from: $0)
        }
        var references: [OfficialPublisherReference] = []
        references.append(
            OfficialPublisherReference(
                provider: reference.provider,
                title: reference.title,
                imageURL: imageURLs[0],
                storeURL: reference.storeURL,
                volumeNumber: reference.volumeNumber,
                coverType: reference.coverType,
                mediaType: reference.mediaType,
                pageURL: reference.pageURL,
                publisherFamily: reference.publisherFamily,
                imprint: reference.imprint,
                providerSeriesID: reference.providerSeriesID,
                providerItemID: productID ?? reference.providerItemID,
                language: reference.language,
                publicationType: reference.publicationType,
                requiresRelationshipReview:
                    reference.requiresRelationshipReview
            )
        )
        if imageURLs.count > 1 {
            references.append(
                OfficialPublisherReference(
                    provider: reference.provider,
                    title: reference.title,
                    imageURL: imageURLs[1],
                    storeURL: reference.storeURL,
                    volumeNumber: reference.volumeNumber,
                    coverType: "volume_back",
                    mediaType: reference.mediaType,
                    pageURL: reference.pageURL,
                    publisherFamily: reference.publisherFamily,
                    imprint: reference.imprint,
                    providerSeriesID: reference.providerSeriesID,
                    providerItemID: productID ?? reference.providerItemID,
                    language: reference.language,
                    publicationType: reference.publicationType,
                    requiresRelationshipReview: true
                )
            )
        }
        return references
    }

    static func barnesNobleProductID(from url: URL) -> String? {
        let queryItems = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        if let ean = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("ean") == .orderedSame
        })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !ean.isEmpty {
            return ean
        }
        return firstPathCapture(
            in: url.path,
            pattern: #"/([0-9]{8,15})(?:/|$)"#
        )
    }

    static func barnesNobleSeriesID(from url: URL) -> String? {
        firstPathCapture(
            in: url.path,
            pattern: #"(?i)^/series/([^/?#]+)(?:/|$)"#
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func crunchyrollProductID(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return nil }
        return firstPathCapture(
            in: name,
            pattern: #"([0-9]{8,15})$"#
        ) ?? name
    }

    private func resolvedOfficialPublisherReferences(
        _ references: [OfficialPublisherReference],
        series: SableMangaBakaSeriesSummary
    ) async -> [OfficialPublisherReference] {
        var resolved = references
        var expanded: [OfficialPublisherReference] = []
        let groupedIndexes = Dictionary(
            grouping: references.indices
        ) { index in
            let reference = references[index]
            return [
                reference.provider.rawValue,
                reference.mediaType
            ]
            .joined(separator: ":")
        }

        for indexes in groupedIndexes.values {
            guard !Task.isCancelled,
                  let firstIndex = indexes.first else {
                continue
            }
            let sample = references[firstIndex]
            guard sample.provider.rolerProviderID != nil else {
                continue
            }
            let query = Self.officialPublisherSeriesTitle(
                from: sample.title
            )
            guard !query.isEmpty,
                  let candidates = try? await providerClient.search(
                    query: query,
                    provider: sample.provider
                  ) else {
                continue
            }
            let primaryRanked = SableLibraryCoverDownloadPlanner
                .rankedSeriesCandidates(
                    for: query,
                    requestedSeriesTitle: query,
                    in: candidates,
                    mediaType: sample.mediaType
                )
                .filter { candidate in
                    guard let bookType = candidate.bookType else {
                        return true
                    }
                    return SableLibraryCoverDownloadPlanner
                        .providerMediaTypeIsCompatible(
                            bookType,
                            isCompatibleWith: sample.mediaType
                        )
                }
            let primaryIDs = Set(
                primaryRanked.map {
                    "\($0.provider.rawValue):\($0.id)"
                }
            )
            let publisherAnchoredSeries = candidates.filter { candidate in
                guard candidate.type?.lowercased() == "series",
                      !primaryIDs.contains(
                        "\(candidate.provider.rawValue):\(candidate.id)"
                      ),
                      Self.officialPublisherCandidateTitle(
                        candidate.title,
                        matches: query
                      ) else {
                    return false
                }
                guard let bookType = candidate.bookType else {
                    return true
                }
                return SableLibraryCoverDownloadPlanner
                    .providerMediaTypeIsCompatible(
                        bookType,
                        isCompatibleWith: sample.mediaType
                    )
            }
            let ranked = primaryRanked + publisherAnchoredSeries

            var bestReferences: [OfficialPublisherReference]?
            var bestBooks: [SableLibraryBigBookCoversBookCandidate] = []
            var bestProviderSeriesID: String?
            var bestResolvedCount = 0
            let limit = sample.provider.isAmazon ? 2 : 5
            for candidate in ranked.prefix(limit) {
                guard !Task.isCancelled,
                      SableLibraryCoverDownloadPlanner.providerTitle(
                        candidate.title,
                        belongsTo: query
                      )
                        || (
                            candidate.type?.lowercased() == "series"
                                && Self.officialPublisherCandidateTitle(
                                    candidate.title,
                                    matches: query
                                )
                        ) else {
                    continue
                }
                var books = (
                    try? await providerClient.books(
                        itemID: candidate.id,
                        itemType: candidate.type ?? "series",
                        provider: sample.provider,
                        maximumPages:
                            sample.provider.isAmazon ? 1 : nil
                    )
                ) ?? []
                if books.isEmpty,
                   sample.provider.isAmazon,
                   candidate.type?.lowercased() == "series" {
                    books = (
                        try? await providerClient.books(
                            itemID: candidate.id,
                            itemType: "book",
                            provider: sample.provider
                        )
                    ) ?? []
                }
                guard !books.isEmpty else { continue }

                let providerSeriesIDs: Set<String> = Set(
                    books.compactMap { book -> String? in
                        guard let seriesID = book.seriesID else {
                            return nil
                        }
                        let trimmed = seriesID.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        return trimmed.isEmpty ? nil : trimmed
                    }
                )
                let providerSeriesID =
                    providerSeriesIDs.count == 1
                    ? providerSeriesIDs.first
                    : candidate.id
                let laneReferences = indexes.map { references[$0] }
                let attached = Self.applyingOfficialPublisherIdentity(
                    to: laneReferences,
                    providerSeriesID: providerSeriesID,
                    books: books
                )
                let resolvedCount = attached.filter {
                    $0.providerItemID != nil
                }.count
                if resolvedCount > bestResolvedCount {
                    bestReferences = attached
                    bestBooks = books
                    bestProviderSeriesID = providerSeriesID
                    bestResolvedCount = resolvedCount
                }
                if resolvedCount == indexes.count {
                    break
                }
            }

            guard let bestReferences else { continue }
            for (index, reference) in zip(indexes, bestReferences) {
                resolved[index] = reference
            }
            if bestResolvedCount > 0 {
                expanded.append(
                    contentsOf: Self
                        .expandedOfficialPublisherReferences(
                            anchor: bestReferences[0],
                            providerSeriesID: bestProviderSeriesID,
                            books: bestBooks
                        )
                )
            }
        }

        var merged: [OfficialPublisherReference] = []
        var indexByKey: [String: Int] = [:]
        for reference in resolved + expanded {
            let key = [
                reference.provider.rawValue,
                reference.coverType,
                String(format: "%.6f", reference.volumeNumber)
            ]
            .joined(separator: ":")
            if let index = indexByKey[key] {
                merged[index] = reference
            } else {
                indexByKey[key] = merged.count
                merged.append(reference)
            }
        }
        return merged.sorted {
            if $0.provider != $1.provider {
                return $0.provider.discoveryPriority
                    < $1.provider.discoveryPriority
            }
            return $0.volumeNumber < $1.volumeNumber
        }
    }

    static func applyingOfficialPublisherIdentity(
        to references: [OfficialPublisherReference],
        providerSeriesID: String?,
        books: [SableLibraryBigBookCoversBookCandidate]
    ) -> [OfficialPublisherReference] {
        references.map { reference in
            var resolved = reference
            let directItemID = storeSeriesReference(
                from: reference.storeURL
            )
            .flatMap { storeReference -> String? in
                storeReference.provider == reference.provider
                    ? storeReference.itemID
                    : nil
            }
            let compatibleBooks = books.filter { book in
                guard book.provider == reference.provider else {
                    return false
                }
                if let bookType = book.bookType,
                   !SableLibraryCoverDownloadPlanner
                    .providerMediaTypeIsCompatible(
                        bookType,
                        isCompatibleWith: reference.mediaType
                    ) {
                    return false
                }
                return true
            }
            let exactBook = directItemID.flatMap { itemID in
                compatibleBooks.first {
                    $0.id.caseInsensitiveCompare(itemID) == .orderedSame
                }
            }
            let numberedBooks = compatibleBooks.filter { book in
                let explicit = SableLibraryCoverDownloadPlanner
                    .explicitVolumeNumber(in: book.title)
                let number = explicit ?? book.volumeNumber
                return number.map {
                    abs($0 - reference.volumeNumber) < 0.000_001
                } == true
            }
            let scopedBooks = numberedBooks.filter {
                SableLibraryCoverDownloadPlanner.providerTitle(
                    $0.title,
                    belongsTo: officialPublisherSeriesTitle(
                        from: reference.title
                    )
                )
            }
            let matchedBook =
                exactBook
                ?? (scopedBooks.count == 1 ? scopedBooks.first : nil)
                ?? (numberedBooks.count == 1 ? numberedBooks.first : nil)
            guard let matchedBook else { return resolved }

            let matchedSeriesID = matchedBook.seriesID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackSeriesID = providerSeriesID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            resolved.providerSeriesID =
                matchedSeriesID?.isEmpty == false
                ? matchedSeriesID
                : (fallbackSeriesID?.isEmpty == false
                    ? fallbackSeriesID
                    : nil)
            let itemID = matchedBook.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            resolved.providerItemID = itemID.isEmpty ? nil : itemID
            return resolved
        }
    }

    static func expandedOfficialPublisherReferences(
        anchor: OfficialPublisherReference,
        providerSeriesID: String?,
        books: [SableLibraryBigBookCoversBookCandidate]
    ) -> [OfficialPublisherReference] {
        let seriesTitle = officialPublisherSeriesTitle(
            from: anchor.title
        )
        var referencesByVolume:
            [String: OfficialPublisherReference] = [:]
        for book in books.sorted(by: {
            $0.sequenceIndex < $1.sequenceIndex
        }) {
            guard book.provider == anchor.provider,
                  book.bookType.map({
                    SableLibraryCoverDownloadPlanner
                        .providerMediaTypeIsCompatible(
                            $0,
                            isCompatibleWith: anchor.mediaType
                        )
                  }) != false,
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    book.title,
                    belongsTo: seriesTitle
                  ),
                  let volumeNumber =
                    SableLibraryCoverDownloadPlanner
                    .explicitVolumeNumber(in: book.title)
                    ?? book.volumeNumber,
                  !book.coverURL.isEmpty else {
                continue
            }
            let seriesID = book.seriesID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackSeriesID = providerSeriesID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            referencesByVolume[
                String(format: "%.6f", volumeNumber)
            ] = OfficialPublisherReference(
                provider: anchor.provider,
                title: book.title,
                imageURL: book.coverURL,
                storeURL: book.url ?? anchor.storeURL,
                volumeNumber: volumeNumber,
                coverType: anchor.coverType,
                mediaType: anchor.mediaType,
                pageURL: anchor.pageURL,
                publisherFamily: anchor.publisherFamily,
                imprint: anchor.imprint,
                providerSeriesID:
                    seriesID?.isEmpty == false
                    ? seriesID
                    : fallbackSeriesID,
                providerItemID: book.id,
                language: anchor.language,
                publicationType: anchor.publicationType,
                requiresRelationshipReview:
                    anchor.requiresRelationshipReview
            )
        }
        return referencesByVolume.values.sorted {
            $0.volumeNumber < $1.volumeNumber
        }
    }

    static func officialPublisherSeriesTitle(
        from value: String
    ) -> String {
        decodedPublisherHTML(value)
            .replacingOccurrences(
                of: #"(?i)\s*[（(](?:manga|light novel|novel|audio|audiobook)[）)]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of:
                    #"(?i)\s*,?\s*(?:vol(?:ume)?\.?\s*\d+(?:\.\d+)?).*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?is)\s+Release Date\s*:.*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func officialPublisherCandidateTitle(
        _ candidateTitle: String,
        matches query: String
    ) -> Bool {
        if SableLibraryCoverDownloadPlanner.providerTitle(
            candidateTitle,
            belongsTo: query
        ) {
            return true
        }
        let candidate = normalizedPublisherCatalogTitle(candidateTitle)
        let requested = normalizedPublisherCatalogTitle(query)
        guard requested.count >= 4, candidate.count >= 4 else {
            return false
        }
        return candidate.contains(requested)
            || requested.contains(candidate)
    }

    private static func publisherCatalogTitlesHaveStrongTokenOverlap(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        let ignoredTokens = Set(["cover"])
        let lhsTokens = scopeTokens(lhs).subtracting(ignoredTokens)
        let rhsTokens = scopeTokens(rhs).subtracting(ignoredTokens)
        let smallerCount = min(lhsTokens.count, rhsTokens.count)
        guard smallerCount >= 4 else { return false }
        let overlap = lhsTokens.intersection(rhsTokens).count
        return Double(overlap) / Double(smallerCount) >= 0.8
    }

    private func officialPublisherResult(
        references rawReferences: [OfficialPublisherReference],
        series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        guard !rawReferences.isEmpty else {
            return ProviderResult(suggestions: [], notes: [])
        }
        let references = Self.bbcAnchoredOfficialPublisherReferences(
            await resolvedOfficialPublisherReferences(
                rawReferences,
                series: series
            )
        )
        guard !references.isEmpty else {
            return ProviderResult(suggestions: [], notes: [])
        }
        let grouped = Dictionary(grouping: references, by: \.provider)
        let publisherFamilies = Set(
            references.map(\.publisherFamily)
        )
        .sorted()
        let publisherLabel = publisherFamilies.joined(separator: " + ")
        for provider in grouped.keys {
            await progress?(
                .providerStarted(
                    provider: provider,
                    query: "\(publisherLabel) official volume pages"
                )
            )
            await progress?(
                .seriesCandidatesFound(
                    provider: provider,
                    total: 1,
                    compatible: 1
                )
            )
            await progress?(
                .coverCandidatesFound(
                    provider: provider,
                    count: grouped[provider]?.count ?? 0
                )
            )
        }

        let imageURLs = Array(Set(references.map(\.imageURL))).sorted()
        var inspectedImages: [String: ValidatedStorefrontImage] = [:]
        for batchStart in stride(from: 0, to: imageURLs.count, by: 4) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                imageURLs[
                    batchStart..<min(batchStart + 4, imageURLs.count)
                ]
            )
            let images = await withTaskGroup(
                of: (String, ValidatedStorefrontImage?).self
            ) { group in
                for imageURL in batch {
                    group.addTask {
                        (
                            imageURL,
                            await downloadedStorefrontImage(from: imageURL)
                        )
                    }
                }
                var images:
                    [(String, ValidatedStorefrontImage?)] = []
                for await image in group {
                    images.append(image)
                }
                return images
            }
            for (url, image) in images {
                if let image {
                    inspectedImages[url] = image
                }
            }
        }

        var suggestions: [SableMangaBakaStorefrontCoverSuggestion] = []
        for reference in references {
            let image = inspectedImages[reference.imageURL]
            let accepted = image.map {
                Self.sevenSeasImageHasExpectedShape(
                    width: $0.width,
                    height: $0.height,
                    coverType: reference.coverType
                )
            } == true
            await progress?(
                .imageInspected(
                    provider: reference.provider,
                    accepted: accepted,
                    width: image?.width,
                    height: image?.height
                )
            )
            guard accepted, let image else { continue }
            suggestions.append(
                SableMangaBakaStorefrontCoverSuggestion(
                    provider: reference.provider,
                    providerSeriesID: reference.providerSeriesID,
                    providerItemID: reference.providerItemID,
                    title: reference.title,
                    imageURL: image.url,
                    imageChoices: [
                        SableMangaBakaStorefrontImageChoice(
                            url: image.url,
                            width: image.width,
                            height: image.height
                        )
                    ],
                    storeURL: reference.storeURL,
                    volumeNumber: reference.volumeNumber,
                    language: reference.language,
                    coverType: reference.coverType,
                    requiresRelationshipReview:
                        reference.requiresRelationshipReview,
                    automaticMatchConfidence:
                        reference.requiresRelationshipReview ? 0.75 : 1,
                    expectedMediaType:
                        reference.coverType == "audiobook"
                        ? "audiobook"
                        : series.type,
                    detectedMediaType: reference.mediaType,
                    usesPublisherMediaTypeProof: true,
                    width: image.width,
                    height: image.height,
                    contentRating: image.contentRating,
                    contentRatingWasInferred:
                        image.contentRatingWasInferred,
                    detectedVolumeNumbers:
                        image.detectedVolumeNumbers,
                    detectedChapterNumbers:
                        image.detectedChapterNumbers,
                    publicationType: reference.publicationType
                )
            )
        }

        for provider in grouped.keys {
            let count = suggestions.filter {
                $0.provider == provider
            }.count
            await progress?(
                .providerFinished(
                    provider: provider,
                    accepted: count,
                    detail: count == 0
                        ? "\(publisherLabel) linked no usable covers."
                        : "\(publisherLabel) confirmed \(count) official cover\(count == 1 ? "" : "s")."
                )
            )
        }
        return ProviderResult(
            suggestions: suggestions,
            notes: []
        )
    }

    private static func sevenSeasRequestedTitles(
        for series: SableMangaBakaSeriesSummary
    ) -> [String] {
        SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            (series.titles ?? [])
                .filter {
                    normalizedLanguageTag($0.language).hasPrefix("en")
                }
                .map(\.title)
                + [
                    series.title,
                    series.displayTitle,
                    series.romanizedTitle
                ].compactMap { $0 }
        )
    }

    private static func sevenSeasBaseTitle(_ value: String) -> String {
        normalizedPublisherCatalogTitle(
            decodedPublisherHTML(value)
                .replacingOccurrences(
                    of: #"(?is)\s+Release Date\s*:.*$"#,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of:
                        #"(?i)\s*[（(](?:manga|manhwa|manhua|comic|light novel|novel|audiobook)[）)]"#,
                    with: "",
                    options: .regularExpression
                )
        )
    }

    private static func sevenSeasMediaType(
        in value: String
    ) -> String? {
        let normalized = decodedPublisherHTML(value).lowercased()
        let format = normalized.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if format == "audiobook" || format == "audio" {
            return "audiobook"
        }
        if ["manga", "manhwa", "manhua", "comic"].contains(format) {
            return "manga"
        }
        if format == "light novel" || format == "novel" {
            return "novel"
        }
        if normalized.contains("(audiobook)")
            || normalized.contains("format: audiobook") {
            return "audiobook"
        }
        if normalized.contains("(manga)")
            || normalized.contains("(manhwa)")
            || normalized.contains("(manhua)")
            || normalized.contains("(comic)")
            || normalized.contains("format: manga") {
            return "manga"
        }
        if normalized.contains("format: manhwa")
            || normalized.contains("format: manhua")
            || normalized.contains("format: comic") {
            return "manga"
        }
        if normalized.contains("(light novel)")
            || normalized.contains("(novel)")
            || normalized.contains("format: light novel")
            || normalized.contains("format: novel") {
            return "novel"
        }
        return nil
    }

    private static func sevenSeasPageMediaType(
        in pageHTML: String,
        title: String
    ) -> String? {
        if let titleType = sevenSeasMediaType(in: title) {
            return titleType
        }
        let format = firstPathCapture(
            in: pageHTML,
            pattern:
                #"(?is)<b>\s*Format\s*:\s*</b>\s*([^<]+)"#
        )
        return format.flatMap(sevenSeasMediaType)
    }

    private static func sevenSeasRetailerProvider(
        label: String,
        url: URL,
        isAudiobook: Bool
    ) -> SableLibraryBigBookCoversProvider? {
        let normalizedLabel = label.lowercased()
        let host = url.host?.lowercased() ?? ""
        if let provider = rakutenKoboProvider(for: url) {
            return provider
        }
        if host == "barnesandnoble.com"
            || host.hasSuffix(".barnesandnoble.com")
            || normalizedLabel.contains("barnes & noble")
            || normalizedLabel.contains("barnes and noble")
            || normalizedLabel.contains("nook") {
            return .barnesNobleUS
        }
        if host == "store.crunchyroll.com"
            || host.hasSuffix(".store.crunchyroll.com")
            || normalizedLabel.contains("crunchyroll") {
            return .crunchyrollStore
        }
        if isAudiobook {
            if normalizedLabel.contains("audible")
                || host.contains("audible.") {
                return .audibleUS
            }
            if normalizedLabel.contains("bookwalker")
                || normalizedLabel.contains("book walker")
                || host.contains("bookwalker.") {
                return .bookWalkerGlobal
            }
            return nil
        }
        if let provider = amazonProvider(for: host) {
            return provider
        }
        if normalizedLabel.contains("bookwalker")
            || normalizedLabel.contains("book walker")
            || host.contains("bookwalker.") {
            return .bookWalkerGlobal
        }
        return nil
    }

    private static func rakutenKoboProvider(
        for url: URL
    ) -> SableLibraryBigBookCoversProvider? {
        let host = url.host?.lowercased() ?? ""
        if host == "books.rakuten.co.jp"
            || host.hasSuffix(".books.rakuten.co.jp") {
            return .rakutenKoboJapan
        }
        guard host == "kobo.com"
            || host.hasSuffix(".kobo.com")
            || host == "kobobooks.com"
            || host.hasSuffix(".kobobooks.com") else {
            return nil
        }
        let region = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first?
            .lowercased()
        switch region {
        case "nl":
            return .rakutenKoboNetherlands
        case "jp":
            return .rakutenKoboJapan
        case "fr":
            return .rakutenKoboFrance
        case "de":
            return .rakutenKoboGermany
        case "it":
            return .rakutenKoboItaly
        case "es":
            return .rakutenKoboSpain
        case "gb", "uk":
            return .rakutenKoboUK
        default:
            return .rakutenKobo
        }
    }

    private static func sevenSeasImageHasExpectedShape(
        width: Int,
        height: Int,
        coverType: String
    ) -> Bool {
        guard width > 0, height > 0 else { return false }
        if SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
            width: width,
            height: height
        ) {
            return true
        }
        let aspectRatio = Double(height) / Double(width)
        return coverType == "audiobook"
            && (0.8...1.25).contains(aspectRatio)
    }

    private static func normalizedPublisherCatalogTitle(
        _ value: String
    ) -> String {
        normalizedScopeTitle(
            value
                .replacingOccurrences(
                    of: #"(?i)\s+(?:vol(?:ume)?\.?\s*\d+\s+)?cover\s*$"#,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"(?i)\s+vol(?:ume)?\.?\s*\d+\s*$"#,
                    with: "",
                    options: .regularExpression
                )
        )
    }

    private static func decodedPublisherHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&ldquo;", with: "\"")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
            .replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "&mdash;", with: "-")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(
                of: #"(?is)<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
    }

    static func storeSeriesReference(
        from rawValue: String
    ) -> StoreSeriesReference? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value)
                ?? URL(string: value.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ) ?? ""),
              let host = url.host?.lowercased() else {
            return nil
        }

        if host == "booklive.jp" || host.hasSuffix(".booklive.jp") {
            if let groupID = SableLibraryBookLiveSeriesGroupClient.tagID(from: value) {
                return StoreSeriesReference(
                    provider: .bookLiveJP,
                    itemID: groupID,
                    itemType: "seriesGroup",
                    url: value
                )
            }
            if let titleID = SableLibraryBookLiveSeriesGroupClient.titleID(from: value) {
                return StoreSeriesReference(
                    provider: .bookLiveJP,
                    itemID: titleID,
                    itemType: "productFamily",
                    url: value
                )
            }
            return nil
        }

        if let provider = amazonProvider(for: host),
           let asin = firstPathCapture(
            in: url.path,
            pattern: #"(?i)/(?:dp|gp/product|gp/aw/d|kindle-dbs/product)/([A-Z0-9]{10})(?:/|$)"#
           ) {
            let queryItems = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []
            let isSeriesPage = url.path.lowercased().contains(
                "/kindle-dbs/product/"
            )
                || queryItems.contains {
                    $0.name.caseInsensitiveCompare("binding") == .orderedSame
                }
            let publicationTypeOverride = amazonPublicationTypeOverride(
                from: queryItems
            )
            return StoreSeriesReference(
                provider: provider,
                itemID: asin.uppercased(),
                itemType: isSeriesPage ? "series" : "book",
                url: value,
                publicationTypeOverride: publicationTypeOverride
            )
        }

        if (host == "barnesandnoble.com"
            || host.hasSuffix(".barnesandnoble.com")) {
            if let seriesID = barnesNobleSeriesID(from: url) {
                return StoreSeriesReference(
                    provider: .barnesNobleUS,
                    itemID: seriesID,
                    itemType: "series",
                    url: value
                )
            }
            if let productID = barnesNobleProductID(from: url) {
                return StoreSeriesReference(
                    provider: .barnesNobleUS,
                    itemID: productID,
                    itemType: "book",
                    url: value
                )
            }
        }

        if (host == "audible.com" || host.hasSuffix(".audible.com")),
           let asin = audibleProductID(from: url) {
            return StoreSeriesReference(
                provider: .audibleUS,
                itemID: asin,
                itemType: "book",
                url: value,
                languageOverride: "en",
                publisherProvenMediaType: "audiobook"
            )
        }

        if (host == "books.apple.com" || host.hasSuffix(".books.apple.com")),
           let collectionID = firstPathCapture(
            in: value,
            pattern: #"(?i)/id([0-9]+)(?:[/?#]|$)"#
           ) ?? firstPathCapture(
            in: value,
            pattern: #"/([0-9]{8,14})(?:[/?#]|$)"#
           ) ?? url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init)
            .flatMap({ $0.allSatisfy(\.isNumber) ? $0 : nil }) {
            return StoreSeriesReference(
                provider: .appleBooksUS,
                itemID: collectionID,
                itemType: "book",
                url: value,
                languageOverride: "en",
                publisherProvenMediaType: "audiobook"
            )
        }

        if (host == "yes24.com" || host.hasSuffix(".yes24.com")),
           let goodsID = firstPathCapture(
            in: url.path,
            pattern: #"(?i)/product/goods/([0-9]+)(?:/|$)"#
           ) {
            return StoreSeriesReference(
                provider: .yes24,
                itemID: goodsID,
                itemType: "book",
                url: value,
                languageOverride: "ko"
            )
        }

        if (host == "kyobobook.co.kr"
            || host.hasSuffix(".kyobobook.co.kr")),
           let productID = firstPathCapture(
            in: url.path,
            pattern:
                #"(?i)/(?:detail|dig/epd/[^/]+)/([A-Z][A-Z0-9]+)(?:/|$)"#
           ) {
            return StoreSeriesReference(
                provider: .kyobo,
                itemID: productID,
                itemType: "book",
                url: value,
                languageOverride: "ko",
                publicationTypeOverride:
                    host.contains("ebook") ? "digital" : nil
            )
        }

        if host == "bookwalker.com"
            || host.hasSuffix(".bookwalker.com")
            || host == "global.bookwalker.jp" {
            if let volumeID = firstPathCapture(
                in: url.path,
                pattern: #"(?i)/volume/([A-Z0-9-]+)(?:/|$)"#
            ) ?? firstPathCapture(
                in: url.path,
                pattern:
                    #"(?i)^/([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})(?:/|$)"#
            ) {
                return StoreSeriesReference(
                    provider: .bookWalkerGlobal,
                    itemID: volumeID,
                    itemType: "book",
                    url: value
                )
            }
        }
        if (host == "bookwalker.jp" || host.hasSuffix(".bookwalker.jp")),
           let volumeID = firstPathCapture(
            in: url.path,
            pattern:
                #"(?i)^/([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})(?:/|$)"#
           ) {
            return StoreSeriesReference(
                provider: .bookWalkerJP,
                itemID: volumeID,
                itemType: "book",
                url: value
            )
        }

        guard let seriesID = firstPathCapture(
            in: url.path,
            pattern: #"(?i)/series/([A-Z0-9]+)"#
        ) else {
            return nil
        }
        if host == "bookwalker.com" || host.hasSuffix(".bookwalker.com") {
            return StoreSeriesReference(
                provider: .bookWalkerGlobal,
                itemID: seriesID.hasPrefix("CNT_") ? seriesID : "CNT_\(seriesID)",
                itemType: "series",
                url: value
            )
        }
        if host == "bookwalker.jp" || host.hasSuffix(".bookwalker.jp") {
            return StoreSeriesReference(
                provider: .bookWalkerJP,
                itemID: seriesID,
                itemType: "series",
                url: value
            )
        }
        return nil
    }

    private static func amazonProvider(
        for host: String
    ) -> SableLibraryBigBookCoversProvider? {
        let storefronts: [
            (String, SableLibraryBigBookCoversProvider)
        ] = [
            ("amazon.co.jp", .amazonJP),
            ("amazon.co.uk", .amazonUK),
            ("amazon.fr", .amazonFrance),
            ("amazon.de", .amazonGermany),
            ("amazon.it", .amazonItaly),
            ("amazon.es", .amazonSpain),
            ("amazon.nl", .amazonNetherlands),
            ("amazon.com", .amazon)
        ]
        return storefronts.first { domain, _ in
            host == domain || host.hasSuffix(".\(domain)")
        }?.1
    }

    private static func firstPathCapture(
        in value: String,
        pattern: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[captureRange])
    }

    static func audibleProductID(from url: URL) -> String? {
        firstPathCapture(
            in: url.path,
            pattern: #"(?i)/(B[A-Z0-9]{9})(?:/|$)"#
        )?
        .uppercased()
    }

    static func providers(
        for languages: Set<String>?
    ) -> [SableLibraryBigBookCoversProvider] {
        SableLibraryBigBookCoversProvider.allCases
            .filter(\.usesBigBookCoversAPI)
            .filter { languages?.contains($0.languageCode) ?? true }
            .sorted {
                $0.discoveryPriority < $1.discoveryPriority
            }
    }

    static func selectableProviders(
        for languages: Set<String>?
    ) -> [SableLibraryBigBookCoversProvider] {
        (
            providers(for: languages)
                + SableLibraryBigBookCoversProvider.allCases.filter {
                    $0.isBarnesNoble
                        && (languages?.contains($0.languageCode) ?? true)
                }
        )
        .sorted {
            $0.discoveryPriority < $1.discoveryPriority
        }
    }

    static func recommendedProviders(
        for languages: Set<String>?,
        mediaType: String
    ) -> [SableLibraryBigBookCoversProvider] {
        let requestedLanguages = languages.map {
            Set($0.map(normalizedLanguageTag))
        } ?? Set(["ja", "en", "ko", "fr", "de", "it", "es"])
        var providers: [SableLibraryBigBookCoversProvider] = []

        if requestedLanguages.contains("ja") {
            providers += [
                .bookLiveJP,
                .bookWalkerJP,
                .amazonJP,
                .shueisha
            ]
        }
        if requestedLanguages.contains("en") {
            providers += [.bookWalkerGlobal, .amazon, .amazonUK]
            if SableLibraryCoverDownloadPlanner
                .preferredProviderBookTypeForDownload(mediaType: mediaType)
                == "novel" {
                providers += [.audibleUS, .appleBooksUS]
            }
        }
        if requestedLanguages.contains("ko") {
            providers += [.yes24, .kyobo, .aladin, .ridibooks]
        }
        if requestedLanguages.contains("fr") {
            providers.append(.amazonFrance)
        }
        if requestedLanguages.contains("de") {
            providers.append(.amazonGermany)
        }
        if requestedLanguages.contains("it") {
            providers.append(.amazonItaly)
        }
        if requestedLanguages.contains("es") {
            providers.append(.amazonSpain)
        }

        return providers
    }

    static func includesShueishaPublisherSource(
        includesSupplementalSources: Bool,
        selectedProviders: Set<SableLibraryBigBookCoversProvider>?
    ) -> Bool {
        if let selectedProviders {
            return selectedProviders.contains(.shueisha)
        }
        return includesSupplementalSources
    }

    static func providerIsEnabled(
        _ provider: SableLibraryBigBookCoversProvider,
        selectedProviders: Set<SableLibraryBigBookCoversProvider>?
    ) -> Bool {
        if provider.isRakutenKobo, provider != .rakutenKoboJapan {
            return false
        }
        return selectedProviders?.contains(provider) ?? true
    }

    static func shouldDiscoverEnglishAudiobooks(
        for series: SableMangaBakaSeriesSummary,
        provider: SableLibraryBigBookCoversProvider
    ) -> Bool {
        [.audibleUS, .appleBooksUS, .bookWalkerGlobal].contains(provider)
            && SableLibraryCoverDownloadPlanner
                .preferredProviderBookTypeForDownload(
                    mediaType: series.type
                ) == "novel"
    }

    private func discover(
        provider: SableLibraryBigBookCoversProvider,
        for series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        guard let query = Self.preferredQuery(for: provider, series: series) else {
            return ProviderResult(
                suggestions: [],
                notes: ["\(provider.displayName): no suitable title was available."]
            )
        }

        if provider == .audibleUS {
            return await discoverAudible(
                query: query,
                series: series,
                progress: progress
            )
        }

        if provider == .appleBooksUS {
            return await discoverAppleBooks(
                query: query,
                series: series,
                progress: progress
            )
        }

        if provider == .yes24 || provider == .kyobo {
            return await discoverKoreanStorefront(
                provider: provider,
                query: query,
                series: series,
                progress: progress
            )
        }

        if provider == .rakutenKoboJapan {
            return await discoverRakutenBooks(
                query: query,
                series: series,
                progress: progress
            )
        }

        if provider == .barnesNobleUS {
            return await discoverBarnesNoble(
                query: query,
                series: series,
                progress: progress
            )
        }

        do {
            var candidates: [SableLibraryBigBookCoversSeriesCandidate] = []
            var seenCandidates = Set<String>()
            for searchQuery in Self.providerSearchQueries(
                for: provider,
                series: series
            ) {
                let searchResults = try await providerClient.search(
                    query: searchQuery,
                    provider: provider
                )
                candidates.append(contentsOf: searchResults.filter {
                    seenCandidates.insert(
                        "\($0.provider.rawValue):\($0.id)"
                    ).inserted
                })
            }
            let ranked = SableLibraryCoverDownloadPlanner.rankedSeriesCandidates(
                for: query,
                in: candidates,
                mediaType: series.type
            )
            let audiobookRanked = ranked.filter {
                Self.shouldDiscoverEnglishAudiobooks(
                    for: series,
                    provider: provider
                )
                    && $0.bookTypeWasExplicit
                    && $0.bookType?.lowercased().contains("audio") == true
            }
            let compatibleRanked = ranked.filter {
                !$0.bookTypeWasExplicit
                    || $0.bookType?.lowercased().contains("audio") != true
            }
            .filter {
                Self.automaticMediaTypeDisposition(
                    detectedMediaType: Self.bbcSeriesMediaType($0),
                    expectedMediaType: series.type
                ) != .rejected
            }
            let candidateLanes = Self.automaticSeriesCandidateLanes(
                compatibleRanked + audiobookRanked
            )
            var results: [ProviderResult] = []
            if let selection = await selectedBooks(
                from: candidateLanes.volumes,
                provider: provider,
                series: series
            ) {
                results.append(
                    await providerResult(
                        provider: provider,
                        selection: selection,
                        series: series,
                        offersMediaTypeMismatchForReview:
                            provider.isAmazon,
                        progress: progress
                    )
                )
            }
            if let chapterSelection = await selectedBooks(
                from: candidateLanes.chapters,
                provider: provider,
                series: series
            ) {
                results.append(
                    await providerResult(
                        provider: provider,
                        selection: chapterSelection,
                        series: series,
                        offersMediaTypeMismatchForReview: false,
                        progress: progress
                    )
                )
            }
            if let audiobookSelection = await selectedBooks(
                from: candidateLanes.audiobooks,
                provider: provider,
                series: series,
                expectedMediaType: "audiobook"
            ) {
                results.append(
                    await providerResult(
                        provider: provider,
                        selection: audiobookSelection,
                        series: series,
                        trustsSelectedSeriesIdentity: true,
                        expectedMediaType: "audiobook",
                        requestedCoverType: "audiobook",
                        progress: progress
                    )
                )
            }
            if results.isEmpty {
                results.append(
                    ProviderResult(
                        suggestions: [],
                        notes: [
                            candidates.isEmpty
                                ? "\(provider.displayName): BBC returned no search results."
                                : compatibleRanked.isEmpty
                                    ? "\(provider.displayName): no title-safe series matched the requested media type."
                                    : "\(provider.displayName): the best matching BBC series exposed no readable cover rows."
                        ]
                    )
                )
            }

            await progress?(
                .seriesCandidatesFound(
                    provider: provider,
                    total: candidates.count,
                    compatible: ranked.count
                )
            )
            return ProviderResult(
                suggestions: results.flatMap(\.suggestions),
                notes: results.flatMap(\.notes)
            )
        } catch is CancellationError {
            return ProviderResult(
                suggestions: [],
                notes: ["\(provider.displayName): scan cancelled."]
            )
        } catch {
            return ProviderResult(
                suggestions: [],
                notes: ["\(provider.displayName): \(error.localizedDescription)"]
            )
        }
    }

    static func automaticSeriesCandidateLanes(
        _ candidates: [SableLibraryBigBookCoversSeriesCandidate]
    ) -> (
        volumes: [SableLibraryBigBookCoversSeriesCandidate],
        chapters: [SableLibraryBigBookCoversSeriesCandidate],
        audiobooks: [SableLibraryBigBookCoversSeriesCandidate]
    ) {
        var volumes: [SableLibraryBigBookCoversSeriesCandidate] = []
        var chapters: [SableLibraryBigBookCoversSeriesCandidate] = []
        var audiobooks: [SableLibraryBigBookCoversSeriesCandidate] = []
        for candidate in candidates {
            if candidate.bookTypeWasExplicit,
               candidate.bookType?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .contains("audio") == true {
                audiobooks.append(candidate)
            } else if SableLibraryProviderCandidateParser
                .storefrontTitleIsChapterSerial(candidate.title) {
                chapters.append(candidate)
            } else {
                volumes.append(candidate)
            }
        }
        return (volumes, chapters, audiobooks)
    }

    private static func bbcSeriesMediaType(
        _ candidate: SableLibraryBigBookCoversSeriesCandidate
    ) -> String? {
        candidate.bookTypeWasExplicit ? candidate.bookType : nil
    }

    private func discoverAudible(
        query: String,
        series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        guard Self.shouldDiscoverEnglishAudiobooks(
            for: series,
            provider: .audibleUS
        ) else {
            return ProviderResult(
                suggestions: [],
                notes: [
                    "Audible: companion covers are only searched for novel series."
                ]
            )
        }

        do {
            let products = try await audibleClient.search(query: query)
            let requestedTitles = Self.audibleRequestedTitles(
                for: series,
                fallback: query
            )
            let selection = Self.audibleSeriesSelection(
                from: products,
                requestedTitles: requestedTitles,
                series: series,
                query: query
            )
            await progress?(
                .seriesCandidatesFound(
                    provider: .audibleUS,
                    total: products.count,
                    compatible: selection == nil ? 0 : 1
                )
            )
            guard let selection else {
                return ProviderResult(
                    suggestions: [],
                    notes: [
                        "Audible: no matching English audiobook series was found."
                    ]
                )
            }

            return await providerResult(
                provider: .audibleUS,
                selection: selection,
                series: series,
                trustsSelectedSeriesIdentity: true,
                expectedMediaType: "audiobook",
                requestedCoverType: "audiobook",
                progress: progress
            )
        } catch is CancellationError {
            return ProviderResult(
                suggestions: [],
                notes: ["Audible: scan cancelled."]
            )
        } catch {
            return ProviderResult(
                suggestions: [],
                notes: ["Audible: \(error.localizedDescription)"]
            )
        }
    }

    private func discoverAppleBooks(
        query: String,
        series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        guard Self.shouldDiscoverEnglishAudiobooks(
            for: series,
            provider: .appleBooksUS
        ) else {
            return ProviderResult(
                suggestions: [],
                notes: [
                    "Apple Books: companion covers are only searched for novel series."
                ]
            )
        }

        do {
            let products = try await appleBooksClient.search(query: query)
            let requestedTitles = Self.audibleRequestedTitles(
                for: series,
                fallback: query
            )
            let selection = Self.appleBooksSeriesSelection(
                from: products,
                requestedTitles: requestedTitles,
                series: series,
                query: query
            )
            await progress?(
                .seriesCandidatesFound(
                    provider: .appleBooksUS,
                    total: products.count,
                    compatible: selection == nil ? 0 : 1
                )
            )
            guard let selection else {
                return ProviderResult(
                    suggestions: [],
                    notes: [
                        "Apple Books: no matching English audiobook series was found."
                    ]
                )
            }
            return await providerResult(
                provider: .appleBooksUS,
                selection: selection,
                series: series,
                trustsSelectedSeriesIdentity: true,
                expectedMediaType: "audiobook",
                requestedCoverType: "audiobook",
                progress: progress
            )
        } catch is CancellationError {
            return ProviderResult(
                suggestions: [],
                notes: ["Apple Books: scan cancelled."]
            )
        } catch {
            return ProviderResult(
                suggestions: [],
                notes: ["Apple Books: \(error.localizedDescription)"]
            )
        }
    }

    static func appleBooksSeriesSelection(
        from products: [SableAppleBooksCatalogClient.Product],
        requestedTitles: [String],
        series: SableMangaBakaSeriesSummary,
        query: String,
        fallbackProviderSeriesID: String? = nil
    ) -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        let matches = products.compactMap { product -> (
            product: SableAppleBooksCatalogClient.Product,
            volume: Double,
            coverURL: String
        )? in
            guard product.wrapperType?.lowercased() == "audiobook",
                  let coverURL = product.preferredCoverURL,
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    product.collectionName,
                    belongsToAny: requestedTitles
                  ),
                  let volume = explicitProviderVolumeNumber(
                    in: product.collectionName,
                    series: series,
                    language: "en"
                  ) else {
                return nil
            }
            return (product, volume, coverURL)
        }
        .sorted {
            if $0.volume != $1.volume { return $0.volume < $1.volume }
            return $0.product.collectionID < $1.product.collectionID
        }

        let providerSeriesID = fallbackProviderSeriesID
            ?? "apple-books-\(normalizedScopeTitle(requestedTitles.first ?? query))"
        let books = matches.enumerated().map { offset, match in
            SableLibraryBigBookCoversBookCandidate(
                provider: .appleBooksUS,
                id: String(match.product.collectionID),
                seriesID: providerSeriesID,
                title: match.product.collectionName,
                url: match.product.collectionViewURL
                    ?? "https://books.apple.com/us/audiobook/id\(match.product.collectionID)",
                coverURL: match.coverURL,
                coverFallbackURLs: match.product.fallbackCoverURLs,
                volumeNumber: match.volume,
                volumeType: "audiobook",
                sequenceIndex: offset,
                bookType: "audiobook"
            )
        }
        guard !books.isEmpty else { return nil }
        return (requestedTitles.first ?? series.displayTitle, providerSeriesID, books)
    }

    static func appleBooksExactSelection(
        from products: [SableAppleBooksCatalogClient.Product],
        series: SableMangaBakaSeriesSummary,
        fallbackProviderSeriesID: String
    ) -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        let requestedTitles = audibleRequestedTitles(
            for: series,
            fallback: series.displayTitle
        )
        if let matched = appleBooksSeriesSelection(
            from: products,
            requestedTitles: requestedTitles,
            series: series,
            query: series.displayTitle,
            fallbackProviderSeriesID: fallbackProviderSeriesID
        ) {
            return matched
        }

        let books = products.enumerated().compactMap { offset, product ->
            SableLibraryBigBookCoversBookCandidate? in
            guard let coverURL = product.preferredCoverURL else { return nil }
            let volumeNumber = explicitProviderVolumeNumber(
                in: product.collectionName,
                series: series,
                language: "en"
            ) ?? Double(offset + 1)
            return SableLibraryBigBookCoversBookCandidate(
                provider: .appleBooksUS,
                id: String(product.collectionID),
                seriesID: fallbackProviderSeriesID,
                title: product.collectionName,
                url: product.collectionViewURL
                    ?? "https://books.apple.com/us/audiobook/id\(product.collectionID)",
                coverURL: coverURL,
                coverFallbackURLs: product.fallbackCoverURLs,
                volumeNumber: volumeNumber,
                volumeType: "audiobook",
                sequenceIndex: offset,
                bookType: "audiobook"
            )
        }
        guard !books.isEmpty else { return nil }
        return (series.displayTitle, fallbackProviderSeriesID, books)
    }

    static func audibleSeriesSelection(
        from products: [SableAudibleCatalogClient.Product],
        requestedTitles: [String],
        series: SableMangaBakaSeriesSummary,
        query: String,
        fallbackProviderSeriesID: String? = nil
    ) -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        struct Match {
            var product: SableAudibleCatalogClient.Product
            var seriesID: String
            var seriesTitle: String
            var volume: Double
            var coverURL: String
        }

        let realMatches = products.compactMap { product -> Match? in
            guard audibleProductIsEnglish(product),
                  let coverURL = product.preferredCoverURL,
                  let audibleSeries = audibleSeriesEntry(
                    for: product,
                    requestedTitles: requestedTitles
                  ),
                  let volume = audibleSeries.sequence.flatMap(Double.init)
            else {
                return nil
            }
            return Match(
                product: product,
                seriesID: audibleSeries.asin,
                seriesTitle: audibleSeries.title,
                volume: volume,
                coverURL: coverURL
            )
        }
        let bestRealGroup = Dictionary(grouping: realMatches) {
            $0.seriesID
        }
        .max { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count < rhs.value.count
            }
            return lhs.key > rhs.key
        }

        let fallbackSeriesID = bestRealGroup?.key
            ?? fallbackProviderSeriesID
            ?? audibleSyntheticSeriesID(for: requestedTitles.first ?? query)
        let fallbackSeriesTitle = bestRealGroup?.value.first?.seriesTitle
            ?? requestedTitles.first
            ?? series.displayTitle
        let titleMatches = products.compactMap { product -> Match? in
            guard audibleProductIsEnglish(product),
                  let coverURL = product.preferredCoverURL,
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    product.title,
                    belongsToAny: requestedTitles
                  ),
                  let volume = explicitProviderVolumeNumber(
                    in: product.title,
                    series: series,
                    language: "en"
                  )
            else {
                return nil
            }
            let seriesEntry = audibleSeriesEntry(
                for: product,
                requestedTitles: requestedTitles
            )
            return Match(
                product: product,
                seriesID: seriesEntry?.asin ?? fallbackSeriesID,
                seriesTitle: seriesEntry?.title ?? fallbackSeriesTitle,
                volume: seriesEntry?.sequence.flatMap(Double.init) ?? volume,
                coverURL: coverURL
            )
        }
        var matchesByASIN: [String: Match] = [:]
        for match in titleMatches {
            matchesByASIN[match.product.asin] = match
        }
        for match in realMatches {
            matchesByASIN[match.product.asin] = match
        }

        let bestSeries = Dictionary(grouping: Array(matchesByASIN.values)) {
            $0.seriesID
        }
        .max { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count < rhs.value.count
            }
            return lhs.key > rhs.key
        }?
        .value ?? []
        let ordered = bestSeries.sorted {
            if $0.volume != $1.volume {
                return $0.volume < $1.volume
            }
            return $0.product.title.localizedStandardCompare(
                $1.product.title
            ) == .orderedAscending
        }
        let books = ordered.enumerated().map { offset, match in
            SableLibraryBigBookCoversBookCandidate(
                provider: .audibleUS,
                id: match.product.asin,
                seriesID: match.seriesID,
                title: match.product.title,
                url: "https://www.audible.com/pd/\(match.product.asin)",
                coverURL: match.coverURL,
                coverFallbackURLs: match.product.fallbackCoverURLs,
                volumeNumber: match.volume,
                volumeType: "audiobook",
                sequenceIndex: offset,
                bookType: "audiobook"
            )
        }
        guard let first = ordered.first, !books.isEmpty else { return nil }
        return (first.seriesTitle, first.seriesID, books)
    }

    static func audibleExactSelection(
        from products: [SableAudibleCatalogClient.Product],
        series: SableMangaBakaSeriesSummary,
        fallbackProviderSeriesID: String
    ) -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        let requestedTitles = audibleRequestedTitles(
            for: series,
            fallback: series.displayTitle
        )
        if let matched = audibleSeriesSelection(
            from: products,
            requestedTitles: requestedTitles,
            series: series,
            query: fallbackProviderSeriesID,
            fallbackProviderSeriesID: fallbackProviderSeriesID
        ) {
            return matched
        }

        var providerSeriesID = fallbackProviderSeriesID
        var providerSeriesTitle = series.displayTitle
        let books: [SableLibraryBigBookCoversBookCandidate] =
            products.enumerated().compactMap { element in
            let (offset, product) = element
            guard let coverURL = product.preferredCoverURL else { return nil }
            let seriesEntry = product.series?.first
            providerSeriesID = seriesEntry?.asin ?? providerSeriesID
            providerSeriesTitle = seriesEntry?.title ?? providerSeriesTitle
            let volumeNumber =
                seriesEntry?.sequence.flatMap(Double.init)
                ?? explicitProviderVolumeNumber(
                    in: product.title,
                    series: series,
                    language: "en"
                )
                ?? Double(offset + 1)
            return SableLibraryBigBookCoversBookCandidate(
                provider: .audibleUS,
                id: product.asin,
                seriesID: providerSeriesID,
                title: product.title,
                url: "https://www.audible.com/pd/\(product.asin)",
                coverURL: coverURL,
                coverFallbackURLs: product.fallbackCoverURLs,
                volumeNumber: volumeNumber,
                volumeType: "audiobook",
                sequenceIndex: offset,
                bookType: "audiobook"
            )
        }
        guard !books.isEmpty else { return nil }
        return (providerSeriesTitle, providerSeriesID, books)
    }

    private static func audibleProductIsEnglish(
        _ product: SableAudibleCatalogClient.Product
    ) -> Bool {
        product.language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("english") != false
    }

    private static func audibleSeriesEntry(
        for product: SableAudibleCatalogClient.Product,
        requestedTitles: [String]
    ) -> SableAudibleCatalogClient.SeriesEntry? {
        product.series?.first {
            SableLibraryCoverDownloadPlanner.providerTitle(
                $0.title,
                belongsToAny: requestedTitles
            )
        }
    }

    private static func audibleSyntheticSeriesID(for title: String) -> String {
        let slug = normalizedPublisherCatalogTitle(title)
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "audible-title" : "audible-title-\(slug)"
    }

    static func audibleRequestedTitles(
        for series: SableMangaBakaSeriesSummary,
        fallback: String
    ) -> [String] {
        let englishTitles = (series.titles ?? [])
            .filter {
                normalizedLanguageTag($0.language).hasPrefix("en")
            }
            .map(\.title)
        return SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            englishTitles + [
                series.title,
                series.romanizedTitle,
                fallback
            ].compactMap { $0 }
        )
    }

    private func providerResult(
        provider: SableLibraryBigBookCoversProvider,
        selection: (
            title: String,
            providerSeriesID: String,
            books: [SableLibraryBigBookCoversBookCandidate]
        ),
        series: SableMangaBakaSeriesSummary,
        trustsSelectedSeriesIdentity: Bool = false,
        languageOverride: String? = nil,
        publisherProvenMediaType: String? = nil,
        expectedMediaType: String? = nil,
        requestedCoverType: String? = nil,
        offersMediaTypeMismatchForReview: Bool = false,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        let language = languageOverride ?? provider.languageCode
        let targetMediaType = expectedMediaType ?? series.type
        let providerBooks = Self.providerBooksForReview(
            selection.books,
            series: series,
            language: language,
            trustsSelectedSeriesIdentity: trustsSelectedSeriesIdentity
        )
        guard !providerBooks.books.isEmpty else {
            return ProviderResult(
                suggestions: [],
                notes: [
                    "\(provider.displayName): the store series contained no readable books."
                ]
            )
        }
        var requiresRelationshipReview =
            providerBooks.requiresRelationshipReview
        let parsedCandidates = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: providerBooks.books,
            source: provider.source,
            language: language,
            mediaType: nil
        )
        let parsedVolumeCandidates: [SableLibraryProviderCoverCandidate]
        if requestedCoverType != "audiobook" {
            parsedVolumeCandidates = Self.exactStoreVolumeCandidates(
                from: providerBooks.books,
                language: language
            )
        } else {
            parsedVolumeCandidates = parsedCandidates.filter {
                if requestedCoverType == "audiobook" {
                    return $0.isAudiobookCover
                }
                return $0.role == .normal && !$0.isAudiobookCover
            }
        }
        let volumeCandidates = Self.volumeCandidatesForMediaReview(
            from: parsedVolumeCandidates,
            targetMediaType: targetMediaType,
            trustsSelectedSeriesIdentity: trustsSelectedSeriesIdentity,
            offersMediaTypeMismatchForReview:
                offersMediaTypeMismatchForReview,
            requiresRelationshipReview: &requiresRelationshipReview
        )
        let parsedChapterCandidates: [SableLibraryProviderCoverCandidate] =
            requestedCoverType == "audiobook"
            ? []
            : Self.exactStoreChapterCandidates(
                from: providerBooks.books,
                source: provider.source,
                language: language
            )
        let chapterCandidates = parsedChapterCandidates
        let chapterReviewURLs = Set(
            chapterCandidates.filter {
                Self.automaticMediaTypeDisposition(
                    detectedMediaType: $0.mediaType,
                    expectedMediaType: series.type
                ) == .needsReview
            }
            .map(\.imageURL)
        )
        let coverCandidates = volumeCandidates.map {
            ($0, requestedCoverType ?? "volume")
        }
            + chapterCandidates.map { ($0, "chapter") }
        await progress?(
            .coverCandidatesFound(
                provider: provider,
                count: coverCandidates.count
            )
        )

        guard !coverCandidates.isEmpty else {
            let detail: String
            if trustsSelectedSeriesIdentity {
                detail = Self.exactStoreSeriesNoVolumeCoverNote(
                    provider: provider,
                    books: providerBooks.books,
                    language: language
                )
            } else {
                detail =
                    "\(provider.displayName): the matched storefront group "
                    + "contained chapters or editions, but no standard "
                    + "\(language.uppercased()) volume covers."
            }
            return ProviderResult(
                suggestions: [],
                notes: [detail]
            )
        }

        var suggestions: [SableMangaBakaStorefrontCoverSuggestion] = []
        var rejectedQualityNotes: [String] = []
        var inspections: [Int: StorefrontImageInspection] = [:]
        // Provider networking remains parallel, while image OCR and
        // classification stay deliberately bounded so SwiftUI remains fluid.
        let inspectionBatchSize = 6
        for batchStart in stride(
            from: 0,
            to: coverCandidates.count,
            by: inspectionBatchSize
        ) {
            guard !Task.isCancelled else { break }
            let upperBound = min(
                batchStart + inspectionBatchSize,
                coverCandidates.count
            )
            let inspected = await withTaskGroup(
                of: (Int, StorefrontImageInspection).self
            ) { group in
                for index in batchStart..<upperBound {
                    let (candidate, coverType) = coverCandidates[index]
                    group.addTask {
                        (
                            index,
                            await inspectedStorefrontImage(
                                for: candidate,
                                acceptsSquareArtwork:
                                    coverType == "audiobook",
                                acceptsAnyArtworkShape:
                                    trustsSelectedSeriesIdentity,
                                loadsAmazonProductGallery:
                                    trustsSelectedSeriesIdentity
                                        && coverCandidates.count == 1
                            )
                        )
                    }
                }
                var values: [(Int, StorefrontImageInspection)] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }
            for (index, inspection) in inspected {
                inspections[index] = inspection
                await progress?(
                    .imageInspected(
                        provider: provider,
                        accepted: inspection.accepted != nil,
                        width: inspection.accepted?.width
                            ?? inspection.bestRejectedWidth,
                        height: inspection.accepted?.height
                            ?? inspection.bestRejectedHeight
                    )
                )
            }
        }
        for (index, coverCandidate) in coverCandidates.enumerated() {
            let (candidate, coverType) = coverCandidate
            guard let inspection = inspections[index] else { continue }
            if inspection.accepted == nil,
               let width = inspection.bestRejectedWidth,
               let height = inspection.bestRejectedHeight {
                let volume = candidate.volumeNumber
                    .map { $0.rounded() == $0 ? String(Int($0)) : String($0) }
                    ?? candidate.volumeIndex
                    ?? "?"
                rejectedQualityNotes.append(
                    "\(coverType) \(volume) was \(width) x \(height); shown for review"
                )
            } else if inspection.accepted == nil {
                let volume = candidate.volumeNumber
                    .map { $0.rounded() == $0 ? String(Int($0)) : String($0) }
                    ?? candidate.volumeIndex
                    ?? "?"
                rejectedQualityNotes.append(
                    "\(coverType) \(volume) quality could not be measured; shown for review"
                )
            }
            let imageURL = inspection.accepted?.url
                ?? inspection.imageChoices.first?.url
                ?? Self.archivalStorefrontImageURL(
                    from: candidate.imageURL
                )
            guard !imageURL.isEmpty else {
                let number = candidate.volumeNumber
                    .map { $0.rounded() == $0 ? String(Int($0)) : String($0) }
                    ?? candidate.volumeIndex
                    ?? "?"
                rejectedQualityNotes.append(
                    "\(coverType) \(number) had no readable image URL"
                )
                continue
            }
            let candidateNumber = candidate.volumeNumber
                ?? Double(candidate.volumeIndex ?? "")
                ?? 0
            let effectiveCoverType = coverType
            let effectiveNumber = candidateNumber
            let suggestionRequiresRelationshipReview =
                requiresRelationshipReview
                || (
                    !trustsSelectedSeriesIdentity
                    && Self.automaticMediaTypeDisposition(
                        detectedMediaType: candidate.mediaType,
                        expectedMediaType: targetMediaType
                    ) != .accepted
                )
                || chapterReviewURLs.contains(candidate.imageURL)
            let automaticMatchConfidence =
                suggestionRequiresRelationshipReview
                    && !chapterReviewURLs.contains(candidate.imageURL)
                ? Self.automaticMatchConfidence(
                    providerTitles: [
                        candidate.title,
                        selection.title
                    ].compactMap { $0 },
                    series: series,
                    language: language,
                    detectedMediaType: candidate.mediaType,
                    expectedMediaType: targetMediaType
                )
                : 0
            suggestions.append(
                SableMangaBakaStorefrontCoverSuggestion(
                    provider: provider,
                    providerSeriesID: candidate.providerSeriesID
                        ?? selection.providerSeriesID,
                    providerItemID: candidate.providerItemID,
                    title: candidate.title ?? selection.title,
                    imageURL: imageURL,
                    imageChoices: inspection.imageChoices,
                    storeURL: candidate.storeURLs.first,
                    volumeNumber: effectiveNumber,
                    language: language,
                    coverType: effectiveCoverType,
                    requiresRelationshipReview:
                        suggestionRequiresRelationshipReview,
                    automaticMatchConfidence: automaticMatchConfidence,
                    expectedMediaType: targetMediaType,
                    detectedMediaType:
                        publisherProvenMediaType ?? candidate.mediaType,
                    usesManualMediaTypeOverride:
                        trustsSelectedSeriesIdentity
                            && publisherProvenMediaType == nil,
                    usesPublisherMediaTypeProof:
                        publisherProvenMediaType != nil,
                    width: inspection.accepted?.width
                        ?? inspection.bestRejectedWidth,
                    height: inspection.accepted?.height
                        ?? inspection.bestRejectedHeight,
                    contentRating:
                        inspection.accepted?.contentRating ?? "safe",
                    contentRatingWasInferred:
                        inspection.accepted?
                            .contentRatingWasInferred ?? false,
                    detectedVolumeNumbers:
                        inspection.accepted?
                            .detectedVolumeNumbers ?? [],
                    detectedChapterNumbers:
                        inspection.accepted?
                            .detectedChapterNumbers ?? [],
                    publicationType: candidate.publicationType,
                    visualSignature:
                        inspection.accepted?.visualSignature ?? []
                )
            )
            if effectiveCoverType == "volume",
               candidate.publicationType != "digital",
               let backCover = inspection.backCover {
                await progress?(
                    .imageInspected(
                        provider: provider,
                        accepted: true,
                        width: backCover.width,
                        height: backCover.height
                    )
                )
                suggestions.append(
                    SableMangaBakaStorefrontCoverSuggestion(
                        provider: provider,
                        providerSeriesID: candidate.providerSeriesID
                            ?? selection.providerSeriesID,
                        providerItemID: candidate.providerItemID,
                        title: candidate.title ?? selection.title,
                        imageURL: backCover.url,
                        imageChoices: [
                            SableMangaBakaStorefrontImageChoice(
                                url: backCover.url,
                                width: backCover.width,
                                height: backCover.height
                            )
                        ],
                        storeURL: candidate.storeURLs.first,
                        volumeNumber: candidateNumber,
                        language: language,
                        coverType: "volume_back",
                        requiresRelationshipReview:
                            suggestionRequiresRelationshipReview,
                        automaticMatchConfidence: automaticMatchConfidence,
                        expectedMediaType: targetMediaType,
                        detectedMediaType:
                            publisherProvenMediaType ?? candidate.mediaType,
                        usesManualMediaTypeOverride:
                            trustsSelectedSeriesIdentity
                                && publisherProvenMediaType == nil,
                        usesPublisherMediaTypeProof:
                            publisherProvenMediaType != nil,
                        width: backCover.width,
                        height: backCover.height,
                        contentRating: backCover.contentRating,
                        contentRatingWasInferred:
                            backCover.contentRatingWasInferred,
                        detectedVolumeNumbers:
                            backCover.detectedVolumeNumbers,
                        detectedChapterNumbers:
                            backCover.detectedChapterNumbers,
                        publicationType: candidate.publicationType,
                        visualSignature: backCover.visualSignature
                    )
                )
            }
        }

        guard !suggestions.isEmpty else {
            let qualityDetail = rejectedQualityNotes.isEmpty
                ? ""
                : " \(rejectedQualityNotes.prefix(3).joined(separator: "; "))."
            return ProviderResult(
                suggestions: [],
                notes: [
                    "\(provider.displayName): no readable book or audiobook cover was found.\(qualityDetail)"
                ]
            )
        }

        var resultNotes = rejectedQualityNotes.isEmpty
            ? []
            : [
                "\(provider.displayName): kept \(rejectedQualityNotes.count) cover\(rejectedQualityNotes.count == 1 ? "" : "s") with unmeasured or unusual image quality for your review."
            ]
        let relationshipReviewCount = suggestions.filter {
            $0.requiresRelationshipReview
                && !$0.qualifiesForAutomaticAcceptance
        }.count
        if relationshipReviewCount > 0 {
            resultNotes.append(
                "\(provider.displayName): showing \(relationshipReviewCount) related store result\(relationshipReviewCount == 1 ? "" : "s") for review. They are unchecked because the store did not prove the exact series relationship or media type."
            )
        }
        let numberingReviewCount = suggestions.filter(
            \.requiresNumberingReview
        ).count
        if numberingReviewCount > 0 {
            resultNotes.append(
                "\(provider.displayName): \(numberingReviewCount) cover"
                    + "\(numberingReviewCount == 1 ? "" : "s") need"
                    + "\(numberingReviewCount == 1 ? "s" : "") "
                    + "a volume or chapter number check and remain unchecked."
            )
        }
        return ProviderResult(
            suggestions: suggestions,
            notes: resultNotes
        )
    }

    private func discoverKoreanStorefront(
        provider: SableLibraryBigBookCoversProvider,
        query: String,
        series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        let products: [KoreanStorefrontProduct]
        switch provider {
        case .yes24:
            products = await yes24Products(
                query: query,
                expectedMediaType: series.type
            )
        case .kyobo:
            products = await kyoboProducts(
                query: query,
                expectedMediaType: series.type
            )
        default:
            products = []
        }

        let compatibleCount = products.filter {
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                $0.mediaType,
                isCompatibleWith: series.type
            )
        }.count
        await progress?(
            .seriesCandidatesFound(
                provider: provider,
                total: products.count,
                compatible: compatibleCount
            )
        )
        await progress?(
            .coverCandidatesFound(
                provider: provider,
                count: products.count
            )
        )
        guard !products.isEmpty else {
            return ProviderResult(
                suggestions: [],
                notes: [
                    "\(provider.displayName): no Korean storefront covers were returned."
                ]
            )
        }

        var suggestions: [SableMangaBakaStorefrontCoverSuggestion] = []
        var unmeasured = 0
        for product in products {
            let image = await downloadedStorefrontImage(from: product.imageURL)
            let accepted = image.map {
                SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
                    width: $0.width,
                    height: $0.height
                )
            } == true
            await progress?(
                .imageInspected(
                    provider: provider,
                    accepted: accepted,
                    width: image?.width,
                    height: image?.height
                )
            )
            if !accepted {
                unmeasured += 1
            }
            let imageURL = image?.url
                ?? Self.archivalStorefrontImageURL(from: product.imageURL)
            suggestions.append(
                SableMangaBakaStorefrontCoverSuggestion(
                    provider: provider,
                    providerSeriesID: product.seriesID ?? query,
                    providerItemID: product.id,
                    title: product.title,
                    imageURL: imageURL,
                    imageChoices: [
                        SableMangaBakaStorefrontImageChoice(
                            url: imageURL,
                            width: image?.width,
                            height: image?.height
                        )
                    ],
                    storeURL: product.storeURL,
                    volumeNumber: product.volumeNumber,
                    language: "ko",
                    requiresRelationshipReview:
                        Self.automaticMediaTypeDisposition(
                            detectedMediaType: product.mediaType,
                            expectedMediaType: series.type
                        ) != .accepted,
                    expectedMediaType: series.type,
                    detectedMediaType: product.mediaType,
                    width: image?.width,
                    height: image?.height,
                    contentRating: image?.contentRating ?? "safe",
                    contentRatingWasInferred:
                        image?.contentRatingWasInferred ?? false,
                    detectedVolumeNumbers:
                        image?.detectedVolumeNumbers ?? [],
                    detectedChapterNumbers:
                        image?.detectedChapterNumbers ?? []
                )
            )
        }

        let notes = unmeasured > 0
            ? [
                "\(provider.displayName): kept \(unmeasured) cover\(unmeasured == 1 ? "" : "s") with unmeasured or unusual image quality for your review."
            ]
            : []
        return ProviderResult(
            suggestions: suggestions,
            notes: notes
        )
    }

    private func discoverRakutenBooks(
        query: String,
        series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        let provider = SableLibraryBigBookCoversProvider.rakutenKoboJapan
        let products = await rakutenBooksProducts(query: query)
        let eligible = products.filter {
            Self.automaticMediaTypeDisposition(
                detectedMediaType: $0.mediaType,
                expectedMediaType: series.type
            ) != .rejected
        }
        await progress?(
            .seriesCandidatesFound(
                provider: provider,
                total: products.count,
                compatible: eligible.count
            )
        )
        await progress?(
            .coverCandidatesFound(
                provider: provider,
                count: eligible.count
            )
        )
        guard !eligible.isEmpty else {
            return ProviderResult(
                suggestions: [],
                notes: [
                    "\(provider.displayName): no title-and-media-type-safe Rakuten Books covers matched."
                ]
            )
        }

        var inspectedImages: [String: ValidatedStorefrontImage] = [:]
        let imageURLs = Array(Set(eligible.map(\.imageURL))).sorted()
        for batchStart in stride(from: 0, to: imageURLs.count, by: 6) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                imageURLs[
                    batchStart..<min(batchStart + 6, imageURLs.count)
                ]
            )
            let images = await withTaskGroup(
                of: (String, ValidatedStorefrontImage?).self
            ) { group in
                for imageURL in batch {
                    group.addTask {
                        (
                            imageURL,
                            await downloadedStorefrontImage(from: imageURL)
                        )
                    }
                }
                var found: [(String, ValidatedStorefrontImage?)] = []
                for await image in group {
                    found.append(image)
                }
                return found
            }
            for (imageURL, image) in images {
                if let image {
                    inspectedImages[imageURL] = image
                }
            }
        }

        var suggestions: [SableMangaBakaStorefrontCoverSuggestion] = []
        for product in eligible {
            let image = inspectedImages[product.imageURL]
            let accepted = image.map {
                SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
                    width: $0.width,
                    height: $0.height
                )
                    && SableLibraryCoverDownloadPlanner
                        .coverDimensionsAreArchiveUsable(
                            width: $0.width,
                            height: $0.height
                        )
            } == true
            await progress?(
                .imageInspected(
                    provider: provider,
                    accepted: accepted,
                    width: image?.width,
                    height: image?.height
                )
            )
            guard accepted, let image else { continue }
            let mediaDisposition = Self.automaticMediaTypeDisposition(
                detectedMediaType: product.mediaType,
                expectedMediaType: series.type
            )
            let requiresReview =
                product.publicationType == "digital"
                || mediaDisposition != .accepted
            suggestions.append(
                SableMangaBakaStorefrontCoverSuggestion(
                    provider: provider,
                    providerSeriesID: product.seriesIdentity,
                    providerItemID: product.id,
                    title: product.title,
                    imageURL: image.url,
                    imageChoices: [
                        SableMangaBakaStorefrontImageChoice(
                            url: image.url,
                            width: image.width,
                            height: image.height
                        )
                    ],
                    storeURL: product.storeURL,
                    volumeNumber: product.volumeNumber,
                    language: "ja",
                    requiresRelationshipReview: requiresReview,
                    automaticMatchConfidence: requiresReview ? 0.80 : 0.97,
                    expectedMediaType: series.type,
                    detectedMediaType: product.mediaType,
                    width: image.width,
                    height: image.height,
                    contentRating: image.contentRating,
                    contentRatingWasInferred:
                        image.contentRatingWasInferred,
                    detectedVolumeNumbers:
                        image.detectedVolumeNumbers,
                    detectedChapterNumbers:
                        image.detectedChapterNumbers,
                    publicationType: product.publicationType,
                    visualSignature: image.visualSignature
                )
            )
        }

        let rejectedCount = eligible.count - suggestions.count
        var notes: [String] = []
        if rejectedCount > 0 {
            notes.append(
                "\(provider.displayName): rejected \(rejectedCount) low-resolution or non-book-shaped storefront image\(rejectedCount == 1 ? "" : "s")."
            )
        }
        return ProviderResult(
            suggestions: suggestions,
            notes: notes
        )
    }

    private func discoverBarnesNoble(
        query: String,
        series: SableMangaBakaSeriesSummary,
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> ProviderResult {
        let provider = SableLibraryBigBookCoversProvider.barnesNobleUS
        let products = await barnesNobleProducts(query: query)
        let titleMatched = products.filter {
            SableLibraryCoverDownloadPlanner.providerTitle(
                $0.title,
                belongsTo: query
            )
                || Self.automaticRelationshipTitleConfidence(
                    providerTitles: [$0.title],
                    series: series,
                    language: provider.languageCode
                ) >= 0.90
        }
        let eligible = titleMatched.filter {
            Self.automaticMediaTypeDisposition(
                detectedMediaType: $0.mediaType,
                expectedMediaType: series.type
            ) != .rejected
        }
        await progress?(
            .seriesCandidatesFound(
                provider: provider,
                total: products.count,
                compatible: eligible.count
            )
        )
        await progress?(
            .coverCandidatesFound(
                provider: provider,
                count: eligible.count
            )
        )
        guard !eligible.isEmpty else {
            return ProviderResult(
                suggestions: [],
                notes: [
                    "\(provider.displayName): no title-and-media-type-safe direct search covers matched."
                ]
            )
        }

        let books = eligible.enumerated().map { offset, product in
            SableLibraryBigBookCoversBookCandidate(
                provider: provider,
                id: product.id,
                seriesID: product.seriesIdentity,
                title: product.title,
                url: product.storeURL,
                coverURL: product.imageURL,
                coverFallbackURLs: [],
                volumeNumber: product.volumeNumber,
                volumeType: "volume",
                sequenceIndex: offset,
                bookType: product.mediaType,
                publicationType: product.publicationType
            )
        }
        return await providerResult(
            provider: provider,
            selection: (
                title: query,
                providerSeriesID: query,
                books: books
            ),
            series: series,
            progress: progress
        )
    }

    private func unavailableRakutenResults(
        providers: [SableLibraryBigBookCoversProvider],
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> [ProviderResult] {
        var results: [ProviderResult] = []
        for provider in providers {
            let detail =
                "\(provider.displayName): no verified official publisher link was available; Kobo blocks direct desktop-app catalog requests."
            await progress?(
                .providerStarted(provider: provider, query: nil)
            )
            await progress?(
                .seriesCandidatesFound(
                    provider: provider,
                    total: 0,
                    compatible: 0
                )
            )
            await progress?(
                .coverCandidatesFound(provider: provider, count: 0)
            )
            await progress?(
                .providerFinished(
                    provider: provider,
                    accepted: 0,
                    detail: detail
                )
            )
            results.append(
                ProviderResult(suggestions: [], notes: [detail])
            )
        }
        return results
    }

    private func unavailableCrunchyrollResults(
        providers: [SableLibraryBigBookCoversProvider],
        progress: (@Sendable (ProgressEvent) async -> Void)?
    ) async -> [ProviderResult] {
        var results: [ProviderResult] = []
        for provider in providers {
            let detail =
                "\(provider.displayName): no exact official publisher product link was available, so the large store catalogue was not crawled."
            await progress?(
                .providerStarted(provider: provider, query: nil)
            )
            await progress?(
                .seriesCandidatesFound(
                    provider: provider,
                    total: 0,
                    compatible: 0
                )
            )
            await progress?(
                .coverCandidatesFound(provider: provider, count: 0)
            )
            await progress?(
                .providerFinished(
                    provider: provider,
                    accepted: 0,
                    detail: detail
                )
            )
            results.append(
                ProviderResult(suggestions: [], notes: [detail])
            )
        }
        return results
    }

    private func barnesNobleProducts(
        query: String
    ) async -> [BarnesNobleProduct] {
        guard var components = URLComponents(
            string: "https://www.barnesandnoble.com/search"
        ) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        guard let searchURL = components.url,
              let html = await Self.storefrontPageHTML(
                from: searchURL.absoluteString
              ) else {
            return []
        }
        let embeddedProducts = Self.barnesNobleProducts(
            from: html,
            pageURL: searchURL.absoluteString,
            query: query
        )
        let embeddedIDs = Set(embeddedProducts.map(\.id))
        let productURLs = Array(
            Self.barnesNobleProductURLs(from: html, query: query)
                .filter {
                    guard let id = URL(string: $0).flatMap(
                        Self.barnesNobleProductID
                    ) else {
                        return true
                    }
                    return !embeddedIDs.contains(id)
                }
                .prefix(max(0, 24 - embeddedProducts.count))
        )
        let fetchedProducts = await barnesNobleProducts(
            productURLs: productURLs,
            query: query,
            referer: searchURL.absoluteString
        )
        return Self.deduplicatedBarnesNobleProducts(
            embeddedProducts + fetchedProducts
        )
    }

    private func barnesNobleProducts(
        productURLs: [String],
        query: String,
        referer: String?
    ) async -> [BarnesNobleProduct] {
        var products: [BarnesNobleProduct] = []
        for batchStart in stride(from: 0, to: productURLs.count, by: 6) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                productURLs[
                    batchStart..<min(batchStart + 6, productURLs.count)
                ]
            )
            let batchProducts = await withTaskGroup(
                of: BarnesNobleProduct?.self
            ) { group in
                for productURL in batch {
                    group.addTask {
                        guard let html = await Self.storefrontPageHTML(
                            from: productURL,
                            referer: referer
                        ) else {
                            return nil
                        }
                        return Self.barnesNobleProduct(
                            from: html,
                            storeURL: productURL,
                            query: query
                        )
                    }
                }
                var values: [BarnesNobleProduct] = []
                for await product in group {
                    if let product {
                        values.append(product)
                    }
                }
                return values
            }
            products.append(contentsOf: batchProducts)
        }

        return Self.deduplicatedBarnesNobleProducts(products)
    }

    static func barnesNobleProducts(
        from html: String,
        pageURL: String,
        query: String
    ) -> [BarnesNobleProduct] {
        let normalized = normalizedBarnesNobleHTML(html)
        let pageTitle = publisherMetaContent("og:title", in: normalized)
            .map(barnesNobleCleanTitle)
        let pageMediaType = storefrontMediaTypeProof(
            title: [pageTitle, query].compactMap { $0 }.joined(separator: " "),
            html: normalized
        )
        guard let urlRegex = try? NSRegularExpression(
            pattern:
                #"(?i)(?:https://www\.barnesandnoble\.com)?/w/[^\\\"'<>\s]+"#
        ) else {
            return []
        }
        let range = NSRange(
            normalized.startIndex..<normalized.endIndex,
            in: normalized
        )
        var products: [BarnesNobleProduct] = []
        for match in urlRegex.matches(in: normalized, range: range) {
            guard let matchRange = Range(match.range, in: normalized),
                  let canonicalStoreURL = canonicalBarnesNobleStoreURL(
                    String(normalized[matchRange])
                  ),
                  let id = URL(string: canonicalStoreURL).flatMap(
                    Self.barnesNobleProductID
                  ),
                  let title = barnesNobleProductGridTitle(
                    before: matchRange.lowerBound,
                    in: normalized
                  ),
                  !barnesNobleProductIsClearlyNotBook(
                    title: title,
                    html: normalized
                  ),
                  let volumeNumber =
                    SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                        in: title,
                        afterSeriesTitle: query
                    )
                    ?? SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                        in: title
                    ),
                  let imageURL = barnesNobleProductGridImageURL(
                    after: matchRange.upperBound,
                    matching: id,
                    in: normalized
                  ) else {
                continue
            }
            let publicationType = barnesNobleEmbeddedPublicationType(
                id: id,
                title: title,
                storeURL: canonicalStoreURL
            )
            let mediaType = publicationType == "audio"
                ? "audiobook"
                : storefrontMediaTypeProof(
                    title: [title, pageTitle].compactMap { $0 }
                        .joined(separator: " "),
                    html: normalized
                ) ?? pageMediaType
            products.append(
                BarnesNobleProduct(
                    id: id,
                    title: title,
                    imageURL: imageURL,
                    storeURL: canonicalStoreURL,
                    seriesIdentity: pageTitle ?? query,
                    volumeNumber: volumeNumber,
                    mediaType: mediaType,
                    publicationType: publicationType
                )
            )
        }
        return deduplicatedBarnesNobleProducts(products)
    }

    private static func deduplicatedBarnesNobleProducts(
        _ products: [BarnesNobleProduct]
    ) -> [BarnesNobleProduct] {
        var seen = Set<String>()
        return products
            .filter { product in
                seen.insert(
                    "\(product.id):\(product.publicationType ?? "unknown")"
                ).inserted
            }
            .sorted {
                if $0.volumeNumber != $1.volumeNumber {
                    return $0.volumeNumber < $1.volumeNumber
                }
                return Self.barnesNoblePublicationTypeRank($0.publicationType)
                    < Self.barnesNoblePublicationTypeRank($1.publicationType)
            }
    }

    static func barnesNobleProductURLs(
        from html: String,
        query: String? = nil
    ) -> [String] {
        let normalized = normalizedBarnesNobleHTML(html)
        guard let regex = try? NSRegularExpression(
            pattern:
                #"(?i)(?:https://www\.barnesandnoble\.com)?/w/[^\\\"'<>\s]+"#
        ) else {
            return []
        }
        let range = NSRange(
            normalized.startIndex..<normalized.endIndex,
            in: normalized
        )
        var seen = Set<String>()
        let candidates = regex.matches(in: normalized, range: range)
            .enumerated()
            .compactMap { offset, match -> (String, Int, Int)? in
                guard let matchRange = Range(match.range, in: normalized) else {
                    return nil
                }
                let rawURL = String(normalized[matchRange])
                guard let canonical = canonicalBarnesNobleStoreURL(rawURL),
                      URL(string: canonical).flatMap(barnesNobleProductID)
                        != nil,
                      seen.insert(canonical).inserted else {
                    return nil
                }
                return (
                    canonical,
                    barnesNobleProductURLSearchRank(
                        rawURL: rawURL,
                        canonicalURL: canonical,
                        query: query
                    ),
                    offset
                )
            }
        return candidates
            .sorted {
                if $0.1 != $1.1 {
                    return $0.1 < $1.1
                }
                return $0.2 < $1.2
            }
            .map(\.0)
    }

    private static func barnesNobleProductURLSearchRank(
        rawURL: String,
        canonicalURL: String,
        query: String?
    ) -> Int {
        guard query != nil else { return 0 }
        guard let url = URL(string: canonicalURL) else { return 5 }
        let path = url.path
        let pathTitle = path
            .split(separator: "/")
            .dropFirst()
            .first
            .map { $0.replacingOccurrences(of: "-", with: " ") } ?? ""
        if let query,
           SableLibraryCoverDownloadPlanner.providerTitle(
            pathTitle,
            belongsTo: query
           ) {
            return 0
        }
        if let id = barnesNobleProductID(from: url),
           barnesNobleURLPathUsesISBNOnly(path, id: id) {
            return rawURL.hasPrefix("/w/") ? 1 : 2
        }
        let hasEAN = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.contains {
            $0.name.caseInsensitiveCompare("ean") == .orderedSame
        } == true
        return hasEAN ? 3 : 4
    }

    private static func barnesNobleURLPathUsesISBNOnly(
        _ path: String,
        id: String
    ) -> Bool {
        path.range(
            of:
                #"/w/\#(NSRegularExpression.escapedPattern(for: id))(?:/\#(NSRegularExpression.escapedPattern(for: id)))?(?:/|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func normalizedBarnesNobleHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func barnesNobleProductGridTitle(
        before index: String.Index,
        in html: String
    ) -> String? {
        let start = html.index(
            index,
            offsetBy: -2_500,
            limitedBy: html.startIndex
        ) ?? html.startIndex
        let fragment = String(html[start..<index])
        guard let regex = try? NSRegularExpression(
            pattern:
                #""([^"]*?(?:Vol\.|Volume)\s*[0-9]+(?:\.[0-9]+)?[^"]*?)""#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)
        return regex.matches(in: fragment, range: range).compactMap {
            match -> String? in
            guard let titleRange = Range(match.range(at: 1), in: fragment) else {
                return nil
            }
            let title = barnesNobleCleanTitle(String(fragment[titleRange]))
            guard !title.isEmpty,
                  SableLibraryCoverDownloadPlanner
                    .explicitVolumeNumber(in: title) != nil else {
                return nil
            }
            return title
        }.last
    }

    private static func barnesNobleProductGridImageURL(
        after index: String.Index,
        matching id: String,
        in html: String
    ) -> String? {
        let end = html.index(
            index,
            offsetBy: 3_000,
            limitedBy: html.endIndex
        ) ?? html.endIndex
        let fragment = String(html[index..<end])
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        return firstPathCapture(
            in: fragment,
            pattern:
                #""(https://cdn\.shopify\.com/s/files/[^"]*/\#(escapedID)_p0\.[^"]+)""#
        )
        .flatMap(normalizedStorefrontAssetURL)
    }

    private static func barnesNobleEmbeddedPublicationType(
        id: String,
        title: String,
        storeURL: String
    ) -> String? {
        let normalized = "\(title) \(storeURL)"
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
        if id.hasPrefix("294")
            || normalized.contains("nook")
            || normalized.contains("ebook")
            || normalized.contains("e-book")
            || normalized.contains("digital") {
            return "digital"
        }
        if normalized.contains("audiobook")
            || normalized.contains("audio cd")
            || normalized.contains("mp3 cd") {
            return "audio"
        }
        return "physical"
    }

    static func barnesNobleProduct(
        from html: String,
        storeURL rawStoreURL: String,
        query: String
    ) -> BarnesNobleProduct? {
        let rawTitle =
            publisherMetaContent("og:title", in: html)
            ?? firstPathCapture(
                in: html,
                pattern: #"(?is)<title[^>]*>(.*?)</title>"#
            )
        guard let rawTitle else { return nil }
        let title = barnesNobleCleanTitle(rawTitle)
        guard !title.isEmpty,
              !barnesNobleProductIsClearlyNotBook(title: title, html: html),
              let volumeNumber =
                SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                    in: title,
                    afterSeriesTitle: query
                )
                ?? SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                    in: title
                ),
              let rawImageURL =
                publisherMetaContent("og:image", in: html)
                ?? firstPathCapture(
                    in: html,
                    pattern: #"(?is)"(?:image|url)"\s*:\s*"([^"]+_p0\.[^"]+)""#
                ),
              let imageURL = normalizedStorefrontAssetURL(rawImageURL),
              URL(string: imageURL) != nil,
              let storeURL = canonicalBarnesNobleStoreURL(rawStoreURL),
              let id = URL(string: storeURL)
                .flatMap(barnesNobleProductID)
                ?? barnesNobleProductIDFromImageURL(imageURL) else {
            return nil
        }
        let publicationType = barnesNoblePublicationType(
            in: html,
            storeURL: storeURL
        )
        let mediaType = publicationType == "audio"
            ? "audiobook"
            : storefrontMediaTypeProof(title: title, html: html)
        let seriesIdentity =
            firstPathCapture(
                in: html,
                pattern:
                    #"(?is)"(?:seriesName|mfield_bnb__seriesName)"\s*:\s*"([^"]+)""#
            )
            .map(barnesNobleCleanTitle)
                ?? query
        return BarnesNobleProduct(
            id: id,
            title: title,
            imageURL: imageURL,
            storeURL: storeURL,
            seriesIdentity: seriesIdentity,
            volumeNumber: volumeNumber,
            mediaType: mediaType,
            publicationType: publicationType
        )
    }

    private static func barnesNobleBookCandidate(
        _ product: BarnesNobleProduct,
        provider: SableLibraryBigBookCoversProvider,
        sequenceIndex: Int
    ) -> SableLibraryBigBookCoversBookCandidate {
        SableLibraryBigBookCoversBookCandidate(
            provider: provider,
            id: product.id,
            seriesID: product.seriesIdentity,
            title: product.title,
            url: product.storeURL,
            coverURL: product.imageURL,
            coverFallbackURLs: [],
            volumeNumber: product.volumeNumber,
            volumeType: "volume",
            sequenceIndex: sequenceIndex,
            bookType: product.mediaType,
            publicationType: product.publicationType
        )
    }

    private static func canonicalBarnesNobleStoreURL(
        _ rawValue: String
    ) -> String? {
        var value = decodedPublisherHTML(rawValue)
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"'<>;,)]}")
                )
            )
        if value.hasPrefix("/w/") {
            value = "https://www.barnesandnoble.com\(value)"
        }
        guard let url = URL(string: value),
              let host = url.host?.lowercased(),
              host == "barnesandnoble.com"
                || host.hasSuffix(".barnesandnoble.com"),
              var components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        components.scheme = "https"
        components.host = "www.barnesandnoble.com"
        components.fragment = nil
        let ean = components.queryItems?.first {
            $0.name.caseInsensitiveCompare("ean") == .orderedSame
        }
        components.queryItems = ean.map { [$0] }
        return components.url?.absoluteString
    }

    private static func normalizedStorefrontAssetURL(
        _ rawValue: String
    ) -> String? {
        let value = decodedPublisherHTML(rawValue)
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(
                url.scheme?.lowercased() ?? ""
              ) else {
            return nil
        }
        return url.absoluteString
    }

    private static func barnesNobleCleanTitle(_ rawValue: String) -> String {
        decodedPublisherHTML(rawValue)
            .replacingOccurrences(
                of: #"(?i)\s*\|\s*Barnes\s*&\s*Noble.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func barnesNobleProductIsClearlyNotBook(
        title: String,
        html: String
    ) -> Bool {
        let normalized = "\(title) \(barnesNobleSelectedFormat(in: html) ?? "")"
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
        if normalized.contains("nook book")
            || normalized.contains("ebook")
            || normalized.contains("e-book") {
            return false
        }
        return [
            "4k ultra hd",
            "blu-ray",
            "dvd",
            "game",
            "gift card",
            "nook glowlight",
            "puzzle",
            "tablet",
            "toy",
            "vinyl"
        ].contains {
            normalized.contains($0)
        }
    }

    private static func barnesNoblePublicationType(
        in html: String,
        storeURL: String
    ) -> String? {
        let format = barnesNobleSelectedFormat(in: html)?
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            ) ?? ""
        if URL(string: storeURL).flatMap(barnesNobleProductID)?
            .hasPrefix("294") == true {
            return "digital"
        }
        if format.contains("nook")
            || format.contains("ebook")
            || format.contains("e-book")
            || format.contains("digital") {
            return "digital"
        }
        if format.contains("audiobook")
            || format.contains("audio cd")
            || format.contains("mp3 cd") {
            return "audio"
        }
        if format.contains("paperback")
            || format.contains("hardcover")
            || format.contains("leather bound")
            || format.contains("signed book") {
            return "physical"
        }
        return nil
    }

    private static func amazonPublicationTypeOverride(
        from queryItems: [URLQueryItem]
    ) -> String? {
        let values = queryItems.reduce(into: [String: String]()) {
            result,
            item in
            result[item.name.lowercased()] = item.value?.lowercased()
        }
        if values["storetype"] == "ebooks"
            || values["binding"]?.contains("kindle") == true {
            return "digital"
        }
        if let binding = values["binding"],
           binding.contains("paperback")
            || binding.contains("hardcover")
            || binding.contains("print") {
            return "physical"
        }
        return nil
    }

    private static func barnesNobleSelectedFormat(in html: String) -> String? {
        firstPathCapture(
            in: html,
            pattern:
                #"(?is)<button[^>]+aria-checked\s*=\s*["']true["'][^>]*>\s*([^<]+)"#
        )
        .map(barnesNobleCleanTitle)
    }

    private static func barnesNobleProductIDFromImageURL(
        _ imageURL: String
    ) -> String? {
        firstPathCapture(
            in: imageURL,
            pattern: #"/([0-9]{8,15})_p0\."#
        )
    }

    private static func barnesNoblePublicationTypeRank(
        _ publicationType: String?
    ) -> Int {
        switch publicationType {
        case "physical": 0
        case "digital": 1
        case "audio": 2
        default: 3
        }
    }

    private func rakutenBooksProducts(
        query: String
    ) async -> [RakutenBooksProduct] {
        await withTaskGroup(
            of: [RakutenBooksProduct].self
        ) { group in
            for offset in [0, 30, 60] {
                group.addTask {
                    guard var components = URLComponents(
                        string: "https://books.rakuten.co.jp/search"
                    ) else {
                        return []
                    }
                    var queryItems = [
                        URLQueryItem(name: "sitem", value: query)
                    ]
                    if offset > 0 {
                        queryItems.append(
                            URLQueryItem(name: "o", value: String(offset))
                        )
                    }
                    components.queryItems = queryItems
                    guard let url = components.url,
                          let html = await Self.storefrontPageHTML(
                            from: url.absoluteString
                          ) else {
                        return []
                    }
                    return Self.rakutenBooksProducts(
                        from: html,
                        query: query
                    )
                }
            }
            var products: [RakutenBooksProduct] = []
            for await pageProducts in group {
                products.append(contentsOf: pageProducts)
            }
            var seen = Set<String>()
            return products
                .filter {
                    seen.insert(
                        "\($0.publicationType):\($0.volumeNumber):\($0.imageURL)"
                    ).inserted
                }
                .sorted {
                    if $0.volumeNumber != $1.volumeNumber {
                        return $0.volumeNumber < $1.volumeNumber
                    }
                    return $0.publicationType < $1.publicationType
                }
        }
    }

    static func rakutenBooksProducts(
        from html: String,
        query: String
    ) -> [RakutenBooksProduct] {
        let marker = #"<div class="rbcomp__item-list__item""#
        return html.components(separatedBy: marker).dropFirst().compactMap {
            fragment in
            let block = marker + fragment
            guard let rawTitle = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)rbcomp__item-list__item__title[^>]*>(.*?)</span>"#
            ),
            let rawStoreURL = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)rbcomp__item-list__item__image.*?<a[^>]+href\s*=\s*["']([^"']+)["']"#
            ),
            let rawImageURL = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)rbcomp__item-list__item__image.*?<img[^>]+src\s*=\s*["']([^"']+)["']"#
            ) else {
                return nil
            }
            let title = decodedPublisherHTML(rawTitle)
            guard !rakutenBooksProductIsClearlyNotABook(title) else {
                return nil
            }
            let seriesTitle = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)シリーズ名\s*：\s*<a[^>]*>(.*?)</a>"#
            )
            .map(decodedPublisherHTML)
            let matchesTitle =
                SableLibraryCoverDownloadPlanner.providerTitle(
                    title,
                    belongsTo: query
                )
                || seriesTitle.map {
                    SableLibraryCoverDownloadPlanner.providerTitle(
                        $0,
                        belongsTo: query
                    )
                } == true
            guard matchesTitle,
                  let volumeNumber =
                    SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                        in: title,
                        afterSeriesTitle: seriesTitle ?? query
                    )
                    ?? SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                        in: title,
                        afterSeriesTitle: query
                    ) else {
                return nil
            }

            let storeURL = decodedPublisherHTML(rawStoreURL)
            let imageURL = decodedPublisherHTML(rawImageURL)
                .replacingOccurrences(
                    of: #"\?.*$"#,
                    with: "",
                    options: .regularExpression
                )
            guard let canonicalStoreURL = URL(string: storeURL).map({
                url -> String in
                var components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
                components?.query = nil
                return components?.url?.absoluteString ?? storeURL
            }),
            let itemID = firstPathCapture(
                in: canonicalStoreURL,
                pattern: #"(?i)/(?:rb|rk)/([^/?]+)"#
            ) else {
                return nil
            }
            let categoryClass = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)class\s*=\s*["']rbcomp__category\s+([^"']+)["']"#
            )?
            .lowercased() ?? ""
            let publicationType = categoryClass.contains("e-book")
                ? "digital"
                : "physical"
            let mediaType = rakutenBooksMediaType(
                title: title,
                block: block
            )
            let seriesIdentity = firstPathCapture(
                in: block,
                pattern:
                    #"(?is)シリーズ名\s*：\s*<a[^>]+href\s*=\s*["']([^"']+)["']"#
            )
            .map(decodedPublisherHTML)
                ?? seriesTitle
                ?? query
            return RakutenBooksProduct(
                id: itemID,
                title: title,
                imageURL: imageURL,
                storeURL: canonicalStoreURL,
                seriesIdentity: seriesIdentity,
                volumeNumber: volumeNumber,
                mediaType: mediaType,
                publicationType: publicationType
            )
        }
    }

    private static func rakutenBooksProductIsClearlyNotABook(
        _ title: String
    ) -> Bool {
        let normalized = title
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
        let nonBookMarkers = [
            "blu-ray",
            "ブルーレイ",
            "dvd",
            "cd",
            "ゲーム",
            "フィギュア",
            "アクリルスタンド",
            "キーホルダー",
            "ぬいぐるみ"
        ]
        return nonBookMarkers.contains {
            normalized.contains($0)
        }
    }

    private static func rakutenBooksMediaType(
        title: String,
        block: String
    ) -> String? {
        let value = "\(title) \(decodedPublisherHTML(block))"
            .lowercased()
        if value.contains("漫画")
            || value.contains("コミック")
            || value.contains("コミックス") {
            return "manga"
        }
        if value.contains("ライトノベル")
            || value.contains("小説")
            || value.contains("文庫")
            || value.contains("文学")
            || value.contains("ノベル") {
            return "novel"
        }
        return nil
    }

    static func bbcAnchoredOfficialPublisherReferences(
        _ references: [OfficialPublisherReference]
    ) -> [OfficialPublisherReference] {
        references.filter { reference in
            guard reference.provider == .shueisha else {
                return true
            }
            return reference.providerSeriesID?.isEmpty == false
                && reference.providerItemID?.isEmpty == false
        }
    }

    private func yes24Products(
        query: String,
        expectedMediaType: String
    ) async -> [KoreanStorefrontProduct] {
        guard var components = URLComponents(
            string: "https://www.yes24.com/Product/Search"
        ) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "domain", value: "ALL"),
            URLQueryItem(name: "query", value: query)
        ]
        guard let url = components.url,
              let html = await Self.storefrontPageHTML(from: url.absoluteString) else {
            return []
        }
        return Self.yes24Products(
            from: html,
            query: query
        )
        .filter {
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                $0.mediaType,
                isCompatibleWith: expectedMediaType
            )
        }
    }

    static func yes24Products(
        from html: String,
        query: String
    ) -> [KoreanStorefrontProduct] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<input[^>]+id\s*=\s*[\"']ordOpt_([0-9]+)[\"'][^>]+value\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: html),
                  let valueRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let id = String(html[idRange])
            let decoded = decodedKoreanStorefrontText(String(html[valueRange]))
            guard let data = decoded.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let title = object["goods_name"] as? String,
                  !title.contains("세트"),
                  !title.contains("합본"),
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    title,
                    belongsTo: query
                  ),
                  let volume = koreanVolumeNumber(in: title, query: query) else {
                return nil
            }
            let category = (object["goodsSortNm"] as? String) ?? ""
            let mediaType = koreanMediaType(category: category)
            return KoreanStorefrontProduct(
                id: id,
                title: title,
                imageURL: "https://image.yes24.com/goods/\(id)/XL",
                storeURL: "https://www.yes24.com/Product/Goods/\(id)",
                volumeNumber: volume,
                mediaType: mediaType
            )
        }
    }

    static func yes24Product(
        from html: String,
        goodsID: String,
        storeURL: String
    ) -> KoreanStorefrontProduct? {
        guard let rawTitle = publisherMetaContent("title", in: html)
                ?? publisherMetaContent("og:title", in: html) else {
            return nil
        }
        let title = decodedPublisherHTML(rawTitle)
            .replacingOccurrences(
                of: #"\s*[|｜].*?예스24\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let volumeNumber = koreanExactVolumeNumber(in: title) ?? 1
        let genre = firstPathCapture(
            in: html,
            pattern: #"(?is)"genre"\s*:\s*\[([^\]]+)\]"#
        )
        let mediaType = koreanMediaType(
            category: "\(title) \(genre ?? "")"
        )
        guard !title.isEmpty else {
            return nil
        }
        let imageURL = publisherMetaContent("og:image", in: html)
            .map(decodedPublisherHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredImageURL = imageURL.flatMap { URL(string: $0) }.map {
            $0.absoluteString
        } ?? "https://image.yes24.com/goods/\(goodsID)/XL"
        return KoreanStorefrontProduct(
            id: goodsID,
            title: title,
            imageURL: preferredImageURL,
            storeURL: storeURL,
            volumeNumber: volumeNumber,
            mediaType: mediaType,
            seriesID: firstPathCapture(
                in: html,
                pattern: #"(?i)SeriesNumber=([0-9]+)"#
            )
        )
    }

    static func kyoboProduct(
        from html: String,
        productID: String,
        storeURL: String
    ) -> KoreanStorefrontProduct? {
        guard let rawTitle = publisherMetaContent("title", in: html)
                ?? publisherMetaContent("og:title", in: html) else {
            return nil
        }
        let title = decodedPublisherHTML(rawTitle)
            .replacingOccurrences(
                of: #"(?s)\s*[|｜].*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let rawImageURL = publisherMetaContent("og:image", in: html)
            .map(decodedPublisherHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let barcode = firstPathCapture(
            in: html,
            pattern:
                #"(?is)value\s*=\s*["']([0-9]{10,13})["'][^>]+id\s*=\s*["']introCverBarcd["']"#
        )
        let imageURL = rawImageURL?
            .replacingOccurrences(
                of: #"/fit-in/[0-9]+x[0-9]+/"#,
                with: "/fit-in/3000x0/",
                options: .regularExpression
            )
            ?? barcode.map {
                "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/\($0).jpg"
            }
        guard let imageURL, URL(string: imageURL) != nil else {
            return nil
        }

        return KoreanStorefrontProduct(
            id: productID,
            title: title,
            imageURL: imageURL,
            storeURL: storeURL,
            volumeNumber: koreanExactVolumeNumber(in: title) ?? 1,
            mediaType: kyoboMediaType(from: html)
        )
    }

    static func kyoboPrintProduct(
        fromSearchHTML html: String,
        productID: String,
        storeURL: String
    ) -> KoreanStorefrontProduct? {
        let escapedProductID = NSRegularExpression.escapedPattern(
            for: productID
        )
        guard let input = firstPathCapture(
            in: html,
            pattern:
                #"(?is)(<input\b[^>]*\bdata-pid\s*=\s*["']\#(escapedProductID)["'][^>]*>)"#
        ),
        let isbn = firstPathCapture(
            in: input,
            pattern: #"\bdata-bid\s*=\s*["']([0-9]{10,13})["']"#
        ),
        let rawTitle = firstPathCapture(
            in: input,
            pattern: #"\bdata-name\s*=\s*["']([^"']+)["']"#
        ) else {
            return nil
        }
        let title = decodedKoreanStorefrontText(rawTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let productObject = firstPathCapture(
            in: html,
            pattern:
                #"(?s)(\{[^{}]*"dq_ID"\s*:\s*"\#(escapedProductID)"[^{}]*\})"#
        )
        let categoryCode: String? = productObject.flatMap { value in
            guard let data = value.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(
                      with: data
                  ) as? [String: Any] else {
                return nil
            }
            return object["sale_CMDT_CLST_CODE3"] as? String
        }

        return KoreanStorefrontProduct(
            id: productID,
            title: title,
            imageURL:
                "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/\(isbn).jpg",
            storeURL: storeURL,
            volumeNumber: koreanExactVolumeNumber(in: title) ?? 1,
            mediaType: categoryCode.flatMap {
                kyoboMediaType(categoryCode: $0)
            }
        )
    }

    private func kyoboProducts(
        query: String,
        expectedMediaType: String
    ) async -> [KoreanStorefrontProduct] {
        guard var components = URLComponents(
            string: "https://search.kyobobook.co.kr/search"
        ) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "keyword", value: query),
            URLQueryItem(name: "gbCode", value: "KOR"),
            URLQueryItem(name: "target", value: "total")
        ]
        guard let url = components.url,
              let html = await Self.storefrontPageHTML(from: url.absoluteString) else {
            return []
        }
        let candidates = Array(
            Self.kyoboProducts(from: html, query: query).prefix(20)
        )
        return await withTaskGroup(
            of: KoreanStorefrontProduct?.self
        ) { group in
            for candidate in candidates {
                group.addTask {
                    guard let html = await Self.storefrontPageHTML(
                        from: candidate.storeURL,
                        referer: url.absoluteString
                    ),
                    let mediaType = Self.kyoboMediaType(from: html),
                    SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                        mediaType,
                        isCompatibleWith: expectedMediaType
                    ) else {
                        return nil
                    }
                    var proven = candidate
                    proven.mediaType = mediaType
                    return proven
                }
            }
            var products: [KoreanStorefrontProduct] = []
            for await product in group {
                if let product {
                    products.append(product)
                }
            }
            return products.sorted {
                $0.volumeNumber < $1.volumeNumber
            }
        }
    }

    static func kyoboProducts(
        from html: String,
        query: String
    ) -> [KoreanStorefrontProduct] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<input[^>]+data-pid\s*=\s*[\"']([^\"']+)[\"'][^>]+data-bid\s*=\s*[\"']([0-9]{10,13})[\"'][^>]+data-name\s*=\s*[\"']([^\"']+)[\"'][^>]+data-code\s*=\s*[\"']KOR[\"'][^>]*>"#
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: html),
                  let isbnRange = Range(match.range(at: 2), in: html),
                  let titleRange = Range(match.range(at: 3), in: html) else {
                return nil
            }
            let id = String(html[idRange])
            let isbn = String(html[isbnRange])
            let title = decodedKoreanStorefrontText(String(html[titleRange]))
            guard !title.contains("세트"),
                  !title.contains("합본"),
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    title,
                    belongsTo: query
                  ),
                  let volume = koreanVolumeNumber(in: title, query: query) else {
                return nil
            }
            return KoreanStorefrontProduct(
                id: id,
                title: title,
                imageURL: "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/\(isbn).jpg",
                storeURL: "https://product.kyobobook.co.kr/detail/\(id)",
                volumeNumber: volume,
                mediaType: nil
            )
        }
    }

    static func kyoboMediaType(from html: String) -> String? {
        if let activeCategories = try? NSRegularExpression(
            pattern:
                #"(?is)<li[^>]+class\s*=\s*["'][^"']*\bactive\b[^"']*["'][^>]*>.*?<a[^>]*>(.*?)</a>"#
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            let labels = activeCategories.matches(
                in: html,
                range: range
            ).compactMap { match -> String? in
                guard match.numberOfRanges > 1,
                      let labelRange = Range(
                        match.range(at: 1),
                        in: html
                      ) else {
                    return nil
                }
                return decodedPublisherHTML(String(html[labelRange]))
            }
            if let mediaType = koreanMediaType(
                category: labels.joined(separator: " ")
            ) {
                return mediaType
            }
        }
        let patterns = [
            #"saleCmdtClstCode\\?":\\?"([0-9]+)"#,
            #""saleCmdtClstCode"\s*:\s*"([0-9]+)""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range)
            where match.numberOfRanges > 1 {
                guard let codeRange = Range(match.range(at: 1), in: html) else {
                    continue
                }
                let code = String(html[codeRange])
                if let mediaType = kyoboMediaType(categoryCode: code) {
                    return mediaType
                }
            }
        }
        return SableLibraryCoverDownloadPlanner.providerPageMediaType(
            from: html
        )
    }

    private static func kyoboMediaType(
        categoryCode: String
    ) -> String? {
        if categoryCode.hasPrefix("010508") {
            return "novel"
        }
        if categoryCode.hasPrefix("47") {
            return "manga"
        }
        return nil
    }

    private static func koreanMediaType(category: String) -> String? {
        let normalized = category.lowercased()
        if normalized.contains("오디오")
            || normalized.contains("audiobook") {
            return "audiobook"
        }
        if normalized.contains("라이트노벨")
            || normalized.contains("라이트 노벨")
            || normalized.contains("소설")
            || normalized.contains("소설/시/희곡")
            || normalized.contains("장르소설")
            || normalized.contains("웹소설") {
            return "novel"
        }
        if normalized.contains("만화")
            || normalized.contains("웹툰")
            || normalized.contains("코믹")
            || normalized.contains("그래픽노블")
            || normalized.contains("그래픽 노블") {
            return "manga"
        }
        return nil
    }

    private static func koreanExactVolumeNumber(
        in title: String
    ) -> Double? {
        let normalized = normalizedScopeTitle(title)
        let patterns = [
            #"([0-9]+(?:\.[0-9]+)?)\s*(?:권|학년)\s*$"#,
            #"([0-9]+(?:\.[0-9]+)?)\s*$"#
        ]
        for pattern in patterns {
            if let value = firstPathCapture(
                in: normalized,
                pattern: pattern
            ).flatMap(Double.init) {
                return value
            }
        }
        return nil
    }

    private static func koreanVolumeNumber(
        in title: String,
        query: String
    ) -> Double? {
        let normalizedTitle = normalizedScopeTitle(title)
        let normalizedQuery = normalizedScopeTitle(query)
        if normalizedTitle == normalizedQuery {
            return 1
        }

        guard !normalizedQuery.isEmpty,
              let seriesRange = normalizedTitle.range(of: normalizedQuery) else {
            return nil
        }
        var remainder = normalizedTitle
        remainder.removeSubrange(seriesRange)

        // Automatic scans only accept the main series plus its volume number.
        // Extra words here normally mean a fanbook, side story, guide, manga
        // adaptation, anthology, or another sibling publication.
        guard let match = remainder.wholeMatch(
            of: /([0-9]+(?:\.[0-9]+)?)(?:권)?/
        ) else {
            return nil
        }
        return Double(match.1)
    }

    private static func decodedKoreanStorefrontText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func preferredQuery(
        for provider: SableLibraryBigBookCoversProvider,
        series: SableMangaBakaSeriesSummary
    ) -> String? {
        let requestedLanguage = provider.languageCode
        let wantsJapanese = requestedLanguage == "ja"
        let titles = series.titles ?? []
        let exactLanguageTitles = titles.filter {
            normalizedLanguageTag($0.language) == requestedLanguage
        }
        let regionalLanguageTitles = titles.filter { title in
            let language = normalizedLanguageTag(title.language)
            return language.hasPrefix("\(requestedLanguage)-")
                && !language.hasSuffix("-latn")
        }
        let languageTitles = exactLanguageTitles.isEmpty
            ? regionalLanguageTitles
            : exactLanguageTitles
        let preferred = languageTitles.first(where: {
            $0.isPrimary == true || $0.traits.contains("official")
        }) ?? languageTitles.first
        let japaneseScriptTitle = wantsJapanese
            ? languageTitles.first(where: {
                containsJapaneseScript($0.title)
            })
            : nil
        let japaneseNativeTitle = wantsJapanese
            ? series.nativeTitle?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            : nil
        let nativeJapaneseScriptTitle =
            japaneseNativeTitle.flatMap {
                containsJapaneseScript($0) && !$0.isEmpty ? $0 : nil
            }

        let fallbacks: [String?] = wantsJapanese
            ? [
                nativeJapaneseScriptTitle,
                japaneseScriptTitle?.title,
                preferred?.title,
                series.romanizedTitle,
                series.title
            ]
            : [
                preferred?.title,
                requestedLanguage == "en" ? series.title : nil,
                series.romanizedTitle,
                series.title,
                series.nativeTitle
            ]
        return fallbacks
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    static func providerSearchQueries(
        for provider: SableLibraryBigBookCoversProvider,
        series: SableMangaBakaSeriesSummary
    ) -> [String] {
        guard let preferred = preferredQuery(
            for: provider,
            series: series
        ) else {
            return []
        }
        guard provider.languageCode == "en",
              let concise = conciseEnglishProviderQuery(preferred) else {
            return [preferred]
        }
        return [preferred, concise]
    }

    private static func conciseEnglishProviderQuery(
        _ title: String
    ) -> String? {
        let separators = [" -", " –", " —", ": "]
        let boundary = separators.compactMap {
            title.range(of: $0)?.lowerBound
        }
        .min()
        guard let boundary else { return nil }

        let concise = title[..<boundary]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard concise.count >= 3,
              normalizedScopeTitle(concise)
                != normalizedScopeTitle(title) else {
            return nil
        }
        return concise
    }

    private static func containsJapaneseScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF,
                 0xFF66...0xFF9F:
                true
            default:
                false
            }
        }
    }

    static func rolerSearchURL(
        for series: SableMangaBakaSeriesSummary,
        language: String
    ) -> URL? {
        let normalizedLanguage = normalizedLanguageTag(language)
        let provider: SableLibraryBigBookCoversProvider
        let locale: String
        let providerIDs: [String]

        switch normalizedLanguage {
        case "ja":
            provider = .bookLiveJP
            locale = "ja"
            providerIDs = [
                "bl",
                "bw",
                "bl-r",
                "bw-r",
                "bw-wa",
                "bw-war",
                "amz-jp",
                "ebj",
                "cmoa"
            ]
        case "en":
            provider = .bookWalkerGlobal
            locale = "en"
            providerIDs = [
                "bw-g",
                "bw-gr",
                "amz",
                "amz-uk"
            ]
        case "ko":
            provider = .aladin
            locale = "ko"
            providerIDs = [
                "aladin",
                "ridi"
            ]
        default:
            return nil
        }

        guard let query = preferredQuery(for: provider, series: series) else {
            return nil
        }
        var components = URLComponents(string: "https://covers.roler.dev/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "providerLocale", value: locale)
        ] + providerIDs.map {
            URLQueryItem(name: "provider", value: $0)
        }
        return components?.url
    }

    static func koreanStoreSearchURL(
        for series: SableMangaBakaSeriesSummary,
        provider: SableLibraryBigBookCoversProvider
    ) -> URL? {
        guard provider == .yes24 || provider == .kyobo,
              let query = preferredQuery(for: provider, series: series) else {
            return nil
        }

        switch provider {
        case .yes24:
            var components = URLComponents(
                string: "https://www.yes24.com/Product/Search"
            )
            components?.queryItems = [
                URLQueryItem(name: "domain", value: "ALL"),
                URLQueryItem(name: "query", value: query)
            ]
            return components?.url
        case .kyobo:
            var components = URLComponents(
                string: "https://search.kyobobook.co.kr/search"
            )
            components?.queryItems = [
                URLQueryItem(name: "keyword", value: query),
                URLQueryItem(name: "gbCode", value: "KOR"),
                URLQueryItem(name: "target", value: "total")
            ]
            return components?.url
        default:
            return nil
        }
    }

    static func booksScopedToSelectedSeries(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        series: SableMangaBakaSeriesSummary,
        language: String
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        let ordered = books.sorted {
            if $0.sequenceIndex != $1.sequenceIndex {
                return $0.sequenceIndex < $1.sequenceIndex
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        .map { book in
            var numberedBook = book
            if let explicitNumber = explicitProviderVolumeNumber(
                in: book.title,
                series: series,
                language: language
            ) {
                numberedBook.volumeNumber = explicitNumber
            }
            return numberedBook
        }
        guard !ordered.isEmpty else { return [] }

        let shouldUseFinalVolume =
            series.status == nil || series.hasClosedVolumeCount
        let expectedCount = shouldUseFinalVolume
            ? series.finalVolume
                .flatMap(Double.init)
                .map { max(Int($0.rounded(.up)), 1) }
            : nil
        let seriesIsScoped = hasSpecificSeriesScope(series)
        guard seriesIsScoped else {
            return expectedCount.map { Array(ordered.prefix($0)) } ?? ordered
        }

        let scopedTitles = localizedScopedTitles(
            for: series,
            language: language
        )
        guard !scopedTitles.isEmpty else { return [] }
        let matching = scopedTitles.lazy.map { scopedTitle in
            ordered.filter {
                title($0.title, belongsToScopedTitle: scopedTitle)
            }
        }
        .first {
            !$0.isEmpty
        } ?? []
        guard !matching.isEmpty else { return [] }

        let limited = expectedCount.map { Array(matching.prefix($0)) } ?? matching
        return limited.enumerated().map { offset, book in
            var localBook = book
            let explicitNumber = explicitProviderVolumeNumber(
                in: book.title,
                series: series,
                language: language
            )
            let providerNumber = book.volumeNumber
            let providerNumberFitsClosedSeries = expectedCount.map { count in
                guard let providerNumber else { return false }
                return providerNumber >= 1
                    && providerNumber <= Double(count)
            } ?? true
            localBook.volumeNumber = explicitNumber
                ?? (providerNumberFitsClosedSeries ? providerNumber : nil)
                ?? Double(offset + 1)
            localBook.sequenceIndex = offset
            return localBook
        }
    }

    static func booksScopedToExactStoreSeries(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        series: SableMangaBakaSeriesSummary? = nil,
        language: String? = nil
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        var numbered = books.sorted {
            if $0.sequenceIndex != $1.sequenceIndex {
                return $0.sequenceIndex < $1.sequenceIndex
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        .map { book in
            var numberedBook = book
            if let series, let language {
                numberedBook.volumeNumber = explicitProviderVolumeNumber(
                    in: book.title,
                    series: series,
                    language: language
                )
                    ?? book.volumeNumber
            }
            return numberedBook
        }

        var usedWholeNumbers = Set(
            numbered.compactMap { book -> Int? in
                guard let number = book.volumeNumber,
                      number.rounded() == number,
                      number >= 1 else {
                    return nil
                }
                return Int(number)
            }
        )
        var nextUnusedNumber = 1
        for index in numbered.indices {
            if numbered[index].volumeNumber == nil {
                while usedWholeNumbers.contains(nextUnusedNumber) {
                    nextUnusedNumber += 1
                }
                numbered[index].volumeNumber = Double(nextUnusedNumber)
                usedWholeNumbers.insert(nextUnusedNumber)
                nextUnusedNumber += 1
            }
            numbered[index].sequenceIndex = index
        }
        return numbered
    }

    static func providerBooksForReview(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        series: SableMangaBakaSeriesSummary,
        language: String,
        trustsSelectedSeriesIdentity: Bool
    ) -> (
        books: [SableLibraryBigBookCoversBookCandidate],
        requiresRelationshipReview: Bool
    ) {
        if trustsSelectedSeriesIdentity {
            return (
                booksScopedToExactStoreSeries(
                    books,
                    series: series,
                    language: language
                ),
                false
            )
        }

        let scoped = booksScopedToSelectedSeries(
            books,
            series: series,
            language: language
        )
        if !scoped.isEmpty {
            return (scoped, false)
        }

        return (
            booksScopedToExactStoreSeries(
                books,
                series: series,
                language: language
            ),
            true
        )
    }

    private static func explicitProviderVolumeNumber(
        in title: String,
        series: SableMangaBakaSeriesSummary,
        language: String
    ) -> Double? {
        if let explicit =
            SableLibraryCoverDownloadPlanner.explicitVolumeNumber(in: title) {
            return explicit
        }

        let requestedLanguage = normalizedLanguageTag(language)
        let localizedTitles = (series.titles ?? [])
            .filter {
                let candidate = normalizedLanguageTag($0.language)
                return candidate == requestedLanguage
                    || candidate.hasPrefix("\(requestedLanguage)-")
            }
            .map(\.title)
        let fallbackTitles: [String?] = requestedLanguage == "ja"
            ? [
                series.nativeTitle,
                localizedScopedTitle(for: series, language: language),
                series.title,
                series.romanizedTitle
            ]
            : [
                localizedScopedTitle(for: series, language: language),
                series.title,
                series.romanizedTitle,
                series.nativeTitle
            ]
        let anchors = (localizedTitles + fallbackTitles.compactMap { $0 })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for anchor in anchors {
            if let explicit =
                SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                    in: title,
                    afterSeriesTitle: anchor
                ) {
                return explicit
            }
        }
        return nil
    }

    static func exactStoreChapterCandidates(
        from books: [SableLibraryBigBookCoversBookCandidate],
        source: SableLibraryCoverSource,
        language: String
    ) -> [SableLibraryProviderCoverCandidate] {
        var seenRows = Set<String>()
        return books
            .filter(Self.isChapterBook)
            .filter {
                seenRows.insert(
                    "\($0.id.lowercased()):\($0.coverURL.lowercased())"
                ).inserted
            }
            .map { book in
                let chapterNumber = Self.chapterNumber(in: book.title)
                    ?? book.volumeNumber
                    ?? Double(book.sequenceIndex)
                return SableLibraryProviderCoverCandidate(
                    provider: .local,
                    providerSeriesID: book.seriesID,
                    providerItemID: book.id,
                    title: book.title,
                    volumeIndex: chapterNumber.rounded() == chapterNumber
                        ? String(Int(chapterNumber))
                        : String(chapterNumber),
                    volumeNumber: chapterNumber,
                    mediaType: book.bookType,
                    language: language,
                    role: .normal,
                    providerType: "chapter",
                    editionNote: "Chapter cover",
                    imageURL: book.coverURL,
                    width: nil,
                    height: nil,
                    byteCount: nil,
                    storeURLs: [book.url].compactMap { $0 },
                    quality: .unknown,
                    fallbackImageURLs: book.coverFallbackURLs
                )
            }
    }

    static func exactStoreVolumeCandidates(
        from books: [SableLibraryBigBookCoversBookCandidate],
        language: String
    ) -> [SableLibraryProviderCoverCandidate] {
        var seenRows = Set<String>()
        return books
            .filter { !Self.isChapterBook($0) }
            .filter {
                SableLibraryCoverDownloadPlanner
                    .preferredProviderBookTypeForDownload(
                        mediaType: $0.bookType
                    ) != "audiobook"
            }
            .filter {
                seenRows.insert(
                    "\($0.id.lowercased()):\($0.coverURL.lowercased())"
                ).inserted
            }
            .map { book in
                let volumeNumber =
                    book.volumeNumber ?? Double(max(book.sequenceIndex, 1))
                return SableLibraryProviderCoverCandidate(
                    provider: .local,
                    providerSeriesID: book.seriesID,
                    providerItemID: book.id,
                    title: book.title,
                    volumeIndex: volumeNumber.rounded() == volumeNumber
                        ? String(Int(volumeNumber))
                        : String(volumeNumber),
                    volumeNumber: volumeNumber,
                    mediaType: book.bookType,
                    language: language,
                    role: .normal,
                    providerType: book.bookType,
                    editionNote: nil,
                    imageURL: book.coverURL,
                    width: nil,
                    height: nil,
                    byteCount: nil,
                    storeURLs: [book.url].compactMap { $0 },
                    quality: .unknown,
                    fallbackImageURLs: book.coverFallbackURLs,
                    publicationType: book.publicationType
                )
            }
    }

    private static func isChapterBook(
        _ book: SableLibraryBigBookCoversBookCandidate
    ) -> Bool {
        if book.volumeType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("chapter") == .orderedSame {
            return true
        }
        return chapterNumber(in: book.title) != nil
            || SableLibraryProviderCandidateParser
                .storefrontTitleIsChapterSerial(book.title)
    }

    private static func chapterNumber(in title: String) -> Double? {
        let normalized = title.applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        ) ?? title
        let patterns = [
            #"(?i)\bchapter\s*(\d+(?:\.\d+)?)\b"#,
            #"第?\s*(\d+(?:\.\d+)?)\s*話"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(
                normalized.startIndex..<normalized.endIndex,
                in: normalized
            )
            guard let match = regex.firstMatch(in: normalized, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(
                    match.range(at: 1),
                    in: normalized
                  ),
                  let number = Double(normalized[valueRange]) else {
                continue
            }
            return number
        }
        return nil
    }

    static func exactStoreSeriesNoVolumeCoverNote(
        provider: SableLibraryBigBookCoversProvider,
        books: [SableLibraryBigBookCoversBookCandidate],
        language: String
    ) -> String {
        let chapterCount = books.filter(Self.isChapterBook).count
        if chapterCount > 0, chapterCount == books.count {
            let noun = chapterCount == 1 ? "chapter edition" : "chapter editions"
            return "\(provider.displayName): manual relationship and media type accepted. This store page contains \(chapterCount) \(noun), but none exposed a usable chapter-cover image."
        }
        return "\(provider.displayName): manual relationship and media type accepted, but the store returned no standard \(language.uppercased()) volume covers."
    }

    static func preferredSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        manualReviewEvaluator: ((
            SableMangaBakaStorefrontCoverSuggestion
        ) -> Bool)? = nil
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        let sorted = rankedSuggestions(
            mangaBakaSubmissionSuggestions(from: suggestions),
            manualReviewEvaluator: manualReviewEvaluator
        )

        var seenSlots = Set<String>()
        return sorted.filter { suggestion in
            let slot = [
                suggestion.language,
                suggestion.coverType,
                String(suggestion.volumeNumber)
            ].joined(separator: ":")
            return seenSlots.insert(slot).inserted
        }
    }

    static func compositeSlots(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        selectedSuggestionIDs: Set<String> = [],
        manualReviewEvaluator: ((
            SableMangaBakaStorefrontCoverSuggestion
        ) -> Bool)? = nil
    ) -> [SableMangaBakaStorefrontCompositeSlot] {
        let ranked = rankedSuggestions(
            mangaBakaSubmissionSuggestions(from: suggestions),
            manualReviewEvaluator: manualReviewEvaluator
        )
        let grouped = Dictionary(grouping: ranked) { suggestion in
            [
                normalizedLanguageTag(suggestion.language),
                suggestion.coverType,
                String(suggestion.volumeNumber)
            ]
            .joined(separator: ":")
        }

        return grouped.values.compactMap { groupedSuggestions in
            guard let best = groupedSuggestions.first else { return nil }
            let selected = groupedSuggestions.first {
                selectedSuggestionIDs.contains($0.id)
            }
            return SableMangaBakaStorefrontCompositeSlot(
                language: best.language,
                coverType: best.coverType,
                volumeNumber: best.volumeNumber,
                suggestions: groupedSuggestions,
                winner: selected ?? best
            )
        }
        .sorted {
            let lhsLanguage = normalizedLanguageTag($0.language)
            let rhsLanguage = normalizedLanguageTag($1.language)
            if lhsLanguage != rhsLanguage {
                return lhsLanguage < rhsLanguage
            }
            if $0.coverType != $1.coverType {
                return $0.coverType < $1.coverType
            }
            return $0.volumeNumber < $1.volumeNumber
        }
    }

    static func mangaBakaSubmissionSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        struct ChapterArtworkCluster {
            var language: String
            var visualSignature: [UInt8]
            var imageIdentity: String
            var earliestChapterNumber: Double
        }

        let chapters = suggestions
            .filter { $0.coverType == "chapter" }
            .sorted {
                let lhsLanguage = normalizedLanguageTag($0.language)
                let rhsLanguage = normalizedLanguageTag($1.language)
                if lhsLanguage != rhsLanguage {
                    return lhsLanguage < rhsLanguage
                }
                return $0.volumeNumber < $1.volumeNumber
            }

        var clusters: [ChapterArtworkCluster] = []
        var includedChapterIDs = Set<String>()

        for chapter in chapters {
            let language = normalizedLanguageTag(chapter.language)
            let imageIdentity =
                SableMangaBakaCoverSnapshot.coverURLIdentity(
                    chapter.imageURL
                )
            let matchingClusterIndex = clusters.firstIndex { cluster in
                guard cluster.language == language else { return false }
                if visualSignaturesAreEquivalent(
                    cluster.visualSignature,
                    chapter.visualSignature
                ) {
                    return true
                }
                return !imageIdentity.isEmpty
                    && cluster.imageIdentity == imageIdentity
            }

            guard let matchingClusterIndex else {
                clusters.append(
                    ChapterArtworkCluster(
                        language: language,
                        visualSignature: chapter.visualSignature,
                        imageIdentity: imageIdentity,
                        earliestChapterNumber: chapter.volumeNumber
                    )
                )
                includedChapterIDs.insert(chapter.id)
                continue
            }

            let earliestChapterNumber =
                clusters[matchingClusterIndex].earliestChapterNumber
            if abs(chapter.volumeNumber - earliestChapterNumber) < 0.001 {
                includedChapterIDs.insert(chapter.id)
            }
        }

        return suggestions.filter {
            $0.coverType != "chapter"
                || includedChapterIDs.contains($0.id)
        }
    }

    static func mangaBakaSubmissionRepresentative(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion,
        among suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> SableMangaBakaStorefrontCoverSuggestion? {
        let prepared = mangaBakaSubmissionSuggestions(from: suggestions)
        if let exact = prepared.first(where: { $0.id == suggestion.id }) {
            return exact
        }
        guard suggestion.coverType == "chapter" else { return nil }

        let language = normalizedLanguageTag(suggestion.language)
        let imageIdentity = SableMangaBakaCoverSnapshot.coverURLIdentity(
            suggestion.imageURL
        )
        let matchingRepresentatives = prepared.filter { candidate in
            guard candidate.coverType == "chapter",
                  normalizedLanguageTag(candidate.language) == language else {
                return false
            }
            if visualSignaturesAreEquivalent(
                candidate.visualSignature,
                suggestion.visualSignature
            ) {
                return true
            }
            return !imageIdentity.isEmpty
                && SableMangaBakaCoverSnapshot.coverURLIdentity(
                    candidate.imageURL
                ) == imageIdentity
        }
        return matchingRepresentatives.first {
            $0.provider == suggestion.provider
        } ?? matchingRepresentatives.first
    }

    private static func rankedSuggestions(
        _ suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        manualReviewEvaluator: ((
            SableMangaBakaStorefrontCoverSuggestion
        ) -> Bool)?
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        suggestions.sorted { lhs, rhs in
            if lhs.language != rhs.language {
                return lhs.language < rhs.language
            }
            if lhs.coverType != rhs.coverType {
                return lhs.coverType < rhs.coverType
            }
            if lhs.volumeNumber != rhs.volumeNumber {
                return lhs.volumeNumber < rhs.volumeNumber
            }
            let lhsNeedsReview =
                manualReviewEvaluator?(lhs) ?? lhs.requiresManualReview
            let rhsNeedsReview =
                manualReviewEvaluator?(rhs) ?? rhs.requiresManualReview
            if lhsNeedsReview != rhsNeedsReview {
                return !lhsNeedsReview
            }
            if lhs.reachesClinicMinimum != rhs.reachesClinicMinimum {
                return lhs.reachesClinicMinimum
            }
            let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
            let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
            if lhsPixels != rhsPixels {
                return lhsPixels > rhsPixels
            }
            let order = SableLibraryCoverSourcePolicy.storeQualityUpgradeOrder(
                language: lhs.language
            )
            let lhsRank = order.firstIndex(of: lhs.provider.source) ?? order.count
            let rhsRank = order.firstIndex(of: rhs.provider.source) ?? order.count
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.provider.discoveryPriority < rhs.provider.discoveryPriority
        }
    }

    static func presentationSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        let sorted = suggestions.sorted { lhs, rhs in
            if lhs.language != rhs.language {
                return lhs.language < rhs.language
            }
            if lhs.provider.discoveryPriority != rhs.provider.discoveryPriority {
                return lhs.provider.discoveryPriority
                    < rhs.provider.discoveryPriority
            }
            if lhs.coverType != rhs.coverType {
                return lhs.coverType < rhs.coverType
            }
            if lhs.volumeNumber != rhs.volumeNumber {
                return lhs.volumeNumber < rhs.volumeNumber
            }
            if lhs.requiresManualReview != rhs.requiresManualReview {
                return !lhs.requiresManualReview
            }
            if lhs.reachesClinicMinimum != rhs.reachesClinicMinimum {
                return lhs.reachesClinicMinimum
            }
            let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
            let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
            if lhsPixels != rhsPixels {
                return lhsPixels > rhsPixels
            }
            return lhs.imageURL < rhs.imageURL
        }

        var seenProviderSlots = Set<String>()
        return sorted.filter { suggestion in
            let slot = [
                suggestion.language,
                suggestion.provider.rawValue,
                suggestion.coverType,
                suggestion.normalizedPublicationType ?? "unspecified",
                String(suggestion.volumeNumber)
            ].joined(separator: ":")
            return seenProviderSlots.insert(slot).inserted
        }
    }

    static func visualSignaturesAreEquivalent(
        _ lhs: [UInt8],
        _ rhs: [UInt8]
    ) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return false
        }
        var squaredDifference = 0.0
        var comparedChannelCount = 0
        for offset in stride(from: 0, to: lhs.count, by: 4)
        where offset + 2 < lhs.count {
            for channel in 0..<3 {
                let difference =
                    Double(Int(lhs[offset + channel]) - Int(rhs[offset + channel]))
                    / 255.0
                squaredDifference += difference * difference
                comparedChannelCount += 1
            }
        }
        let distance = sqrt(
            squaredDifference / Double(max(1, comparedChannelCount))
        )
        return distance <= 0.055
    }

    private func inspectedStorefrontImage(
        for candidate: SableLibraryProviderCoverCandidate,
        acceptsSquareArtwork: Bool = false,
        acceptsAnyArtworkShape: Bool = false,
        loadsAmazonProductGallery: Bool = false
    ) async -> StorefrontImageInspection {
        var bestBookImage: ValidatedStorefrontImage?
        var bestRejectedDimensions: (width: Int, height: Int)?
        var seenURLs = Set<String>()
        var validatedDimensions: [String: (width: Int, height: Int)] = [:]
        var candidateURLs: [String] = []
        let amazonGalleryURL = loadsAmazonProductGallery
            ? candidate.storeURLs.first(
                where: Self.amazonStoreURLSupportsPageGallery
            )
            : nil
        if let amazonGalleryURL {
            let productImages = await amazonProductImageURLs(
                from: amazonGalleryURL,
                expectedItemID: candidate.providerItemID
            )
            candidateURLs.append(contentsOf: productImages.front)
        }
        candidateURLs.append(candidate.imageURL)
        candidateURLs.append(contentsOf: candidate.fallbackImageURLs)
        candidateURLs = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            candidateURLs
        )
        let shouldCompareAllChoices = candidateURLs.count > 1
        var resolvedChoiceURLs: [String] = []
        var inspectedMaximumURLs: [String: ValidatedStorefrontImage] = [:]
        var failedMaximumURLs = Set<String>()

        for sourceURL in candidateURLs
        where seenURLs.insert(sourceURL).inserted {
            var bestSourceImage: ValidatedStorefrontImage?
            let inspectedURLs = Self.usesLocalMaximumImageResolution(
                for: sourceURL
            )
                ? Self.maximumImageURLCandidates(from: sourceURL)
                : [sourceURL]
            for maximumURL in inspectedURLs {
                let image: ValidatedStorefrontImage
                if let inspected = inspectedMaximumURLs[maximumURL] {
                    image = inspected
                } else {
                    guard !failedMaximumURLs.contains(maximumURL),
                          let downloaded = await downloadedStorefrontImageCandidate(
                            from: maximumURL
                          ) else {
                        failedMaximumURLs.insert(maximumURL)
                        continue
                    }
                    inspectedMaximumURLs[maximumURL] = downloaded
                    image = downloaded
                }
                if image.width * image.height
                    > (bestSourceImage?.width ?? 0)
                        * (bestSourceImage?.height ?? 0) {
                    bestSourceImage = image
                }
            }
            guard let image = bestSourceImage else {
                continue
            }
            resolvedChoiceURLs.append(image.url)
            validatedDimensions[image.url] = (image.width, image.height)
            let hasAcceptedShape = Self.storefrontImageShapeIsAccepted(
                width: image.width,
                height: image.height,
                acceptsSquareArtwork: acceptsSquareArtwork,
                acceptsAnyArtworkShape: acceptsAnyArtworkShape
            )
            let reachesPreferredMinimum = acceptsSquareArtwork
                ? image.width >= 800
                    && image.height >= 800
                    && image.width * image.height >= 850_000
                : SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
                    width: image.width,
                    height: image.height
                )
            if hasAcceptedShape {
                if image.width * image.height
                    > (bestBookImage?.width ?? 0) * (bestBookImage?.height ?? 0) {
                    bestBookImage = image
                }
                if reachesPreferredMinimum, !shouldCompareAllChoices {
                    break
                }
                continue
            }
            if image.width * image.height
                > (bestRejectedDimensions?.width ?? 0)
                    * (bestRejectedDimensions?.height ?? 0) {
                bestRejectedDimensions = (image.width, image.height)
            }
        }

        return StorefrontImageInspection(
            accepted: bestBookImage,
            backCover: nil,
            imageChoices: Self.storefrontImageChoices(
                from: resolvedChoiceURLs,
                validatedDimensions: validatedDimensions
            ),
            bestRejectedWidth: bestRejectedDimensions?.width,
            bestRejectedHeight: bestRejectedDimensions?.height
        )
    }

    static func usesLocalMaximumImageResolution(for rawURL: String) -> Bool {
        guard let host = URL(string: rawURL)?.host?.lowercased() else {
            return false
        }
        return [
            "media-amazon.com",
            "ssl-images-amazon.com",
            "mzstatic.com",
            "yes24.com",
            "kyobobook.co.kr",
            "ridicdn.net",
            "aladin.co.kr",
            "kobo.com",
            "shueisha.online"
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func storefrontImageShapeIsAccepted(
        width: Int,
        height: Int,
        acceptsSquareArtwork: Bool,
        acceptsAnyArtworkShape: Bool
    ) -> Bool {
        guard !storefrontImageIsObviousPlaceholder(
            width: width,
            height: height
        ) else {
            return false
        }
        if acceptsAnyArtworkShape {
            return true
        }
        if SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
            width: width,
            height: height
        ) {
            return true
        }
        let aspectRatio = Double(height) / Double(max(width, 1))
        return acceptsSquareArtwork && (0.8...1.25).contains(aspectRatio)
    }

    private func amazonProductImageURLs(
        from rawStoreURL: String,
        expectedItemID: String?
    ) async -> AmazonProductImageURLs {
        guard let url = URL(string: rawStoreURL),
              let host = url.host?.lowercased(),
              host.contains("amazon.") else {
            return AmazonProductImageURLs(front: [], back: [])
        }
        let pageItemID = Self.firstPathCapture(
            in: url.path,
            pattern:
                #"(?i)/(?:dp|gp/product|gp/aw/d|kindle-dbs/product)/([A-Z0-9]{10})(?:/|$)"#
        )?.uppercased()
        let expectedItemID = expectedItemID?.uppercased()
        if let expectedItemID,
           let pageItemID,
           expectedItemID != pageItemID {
            return AmazonProductImageURLs(front: [], back: [])
        }

        let html = await Self.storefrontPageHTML(from: rawStoreURL)
        guard let html else {
            return AmazonProductImageURLs(front: [], back: [])
        }
        let itemID = expectedItemID ?? pageItemID
        return AmazonProductImageURLs(
            front: Self.amazonPreferredFrontImageURLs(
                in: html,
                host: host,
                expectedItemID: itemID
            ),
            back: Self.amazonPreferredBackImageURLs(
                in: html,
                expectedItemID: itemID
            )
        )
    }

    static func amazonStoreURLSupportsPageGallery(
        _ rawStoreURL: String
    ) -> Bool {
        guard let host = URL(string: rawStoreURL)?.host else {
            return false
        }
        return host.lowercased().split(separator: ".").contains("amazon")
    }

    static func amazonPreferredFrontImageURLs(
        in html: String,
        host: String?,
        expectedItemID: String? = nil
    ) -> [String] {
        let primaryGallery = amazonPrimaryProductGallerySource(
            in: html,
            expectedItemID: expectedItemID
        )
        let primaryURLs = primaryGallery.map {
            amazonHighResolutionImageURLs(in: $0)
        } ?? []
        let landingURLs = amazonLandingImageURLs(in: html)
        let regular: [String]
        let gallerySource: String
        if !primaryURLs.isEmpty {
            regular = primaryURLs
            gallerySource = primaryGallery ?? html
        } else if expectedItemID != nil {
            regular = landingURLs
            gallerySource = ""
        } else {
            regular = amazonHighResolutionImageURLs(in: html)
            gallerySource = html
        }
        guard amazonHostPrefersSecondGalleryImage(host) else {
            return regular
        }

        let grouped = gallerySource.isEmpty
            ? []
            : amazonFrontGalleryImageURLGroups(in: gallerySource)
        let prioritized: [String]
        if grouped.count > 1 {
            prioritized =
                grouped.dropFirst().flatMap { $0 }
                + grouped.prefix(1).flatMap { $0 }
        } else if regular.count > 1 {
            prioritized = Array(regular.dropFirst()) + [regular[0]]
        } else {
            prioritized = regular
        }
        return uniqueAmazonImageURLs(prioritized + regular)
    }

    private static func amazonPrimaryProductGallerySource(
        in html: String,
        expectedItemID: String?
    ) -> String? {
        guard let markerRegex = try? NSRegularExpression(
            pattern:
                #"(?i)["']colorImages["']\s*:\s*\{\s*["']initial["']\s*:\s*(\[)"#
        ) else {
            return nil
        }
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = markerRegex.matches(
            in: html,
            range: htmlRange
        )

        for match in matches {
            guard match.numberOfRanges > 1,
                  let openingRange = Range(match.range(at: 1), in: html) else {
                continue
            }
            let openingBracket = openingRange.lowerBound
            if let expectedItemID {
                let distance = html.distance(
                    from: html.startIndex,
                    to: openingBracket
                )
                let contextStart = html.index(
                    openingBracket,
                    offsetBy: -min(distance, 2_000)
                )
                let context = String(html[contextStart..<openingBracket])
                let escapedItemID = NSRegularExpression.escapedPattern(
                    for: expectedItemID
                )
                guard context.range(
                    of:
                        #"(?i)["']asin["']\s*:\s*["']\#(escapedItemID)["']"#,
                    options: .regularExpression
                ) != nil else {
                    continue
                }
            }

            var index = openingBracket
            var depth = 0
            var quote: Character?
            var isEscaped = false

            while index < html.endIndex {
                let character = html[index]
                if let activeQuote = quote {
                    if isEscaped {
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == activeQuote {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(html[openingBracket...index])
                    }
                }
                index = html.index(after: index)
            }
        }
        return nil
    }

    private static func amazonLandingImageURLs(in html: String) -> [String] {
        guard let imageRegex = try? NSRegularExpression(
            pattern:
                #"<img\b[^>]*(?:id\s*=\s*["']landingImage["']|data-a-image-name\s*=\s*["']landingImage["'])[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let imageTags = imageRegex.matches(in: html, range: htmlRange)
            .compactMap { match -> String? in
                guard let range = Range(match.range, in: html) else {
                    return nil
                }
                return String(html[range])
            }
        return uniqueAmazonImageURLs(
            imageTags.flatMap {
                amazonImageURLs(
                    in: $0,
                    patterns: [
                        #"data-old-hires\s*=\s*["'](https:[^"']+)["']"#
                    ]
                )
            }
        )
    }

    private static func amazonPreferredBackImageURLs(
        in html: String,
        expectedItemID: String?
    ) -> [String] {
        if let expectedItemID {
            guard let gallery = amazonPrimaryProductGallerySource(
                in: html,
                expectedItemID: expectedItemID
            ) else {
                return []
            }
            return amazonBackCoverImageURLs(in: gallery)
        }
        return amazonBackCoverImageURLs(in: html)
    }

    static func amazonHighResolutionImageURLs(in html: String) -> [String] {
        let patterns = [
            #""hiRes"\s*:\s*"(https:[^"]+)""#,
            #""large"\s*:\s*"(https:[^"]+)""#,
            #"data-old-hires\s*=\s*["'](https:[^"']+)["']"#
        ]
        let backCoverURLs = Set(amazonBackCoverImageURLs(in: html))
        return amazonImageURLs(
            in: html,
            patterns: patterns,
            excluding: backCoverURLs
        )
    }

    static func amazonBackCoverImageURLs(in html: String) -> [String] {
        let patterns = [
            #"variant-BACK[\s\S]{0,2000}?data-old-hires\s*=\s*["'](https:[^"']+)["']"#,
            #""variant"\s*:\s*"BACK"[\s\S]{0,2000}?"hiRes"\s*:\s*"(https:[^"]+)""#
        ]
        return amazonImageURLs(in: html, patterns: patterns)
    }

    private static func amazonFrontGalleryImageURLGroups(
        in html: String
    ) -> [[String]] {
        guard let objectRegex = try? NSRegularExpression(
            pattern: #"\{[^{}]*(?:"hiRes"|"large")[^{}]*\}"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let patterns = [
            #""hiRes"\s*:\s*"(https:[^"]+)""#,
            #""large"\s*:\s*"(https:[^"]+)""#
        ]
        let backCoverURLs = Set(amazonBackCoverImageURLs(in: html))
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return objectRegex.matches(in: html, range: htmlRange)
            .compactMap { match in
                guard let objectRange = Range(match.range, in: html) else {
                    return nil
                }
                let urls = amazonImageURLs(
                    in: String(html[objectRange]),
                    patterns: patterns,
                    excluding: backCoverURLs
                )
                return urls.isEmpty ? nil : urls
            }
    }

    private static func amazonImageURLs(
        in html: String,
        patterns: [String],
        excluding excludedURLs: Set<String> = []
    ) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            for match in regex.matches(in: html, range: htmlRange) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: html) else {
                    continue
                }
                let value = decodedAmazonImageURL(String(html[valueRange]))
                if !excludedURLs.contains(value),
                   seen.insert(value).inserted {
                    urls.append(value)
                }
            }
        }
        return urls
    }

    private static func decodedAmazonImageURL(_ rawURL: String) -> String {
        rawURL
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func uniqueAmazonImageURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private static func amazonHostPrefersSecondGalleryImage(
        _ host: String?
    ) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "amazon.de" || host.hasSuffix(".amazon.de")
    }

    static func storefrontImageChoices(
        from rawURLs: [String],
        validatedDimensions: [String: (width: Int, height: Int)]
    ) -> [SableMangaBakaStorefrontImageChoice] {
        var choices: [SableMangaBakaStorefrontImageChoice] = []
        var seen = Set<String>()
        for rawURL in rawURLs {
            let url = rawURL
            let identity = SableMangaBakaCoverSnapshot.coverURLIdentity(url)
            guard !identity.isEmpty,
                  seen.insert(identity).inserted else {
                continue
            }
            let dimensions = validatedDimensions[url]
            if let dimensions,
               storefrontImageIsObviousPlaceholder(
                width: dimensions.width,
                height: dimensions.height
               ) {
                continue
            }
            choices.append(
                SableMangaBakaStorefrontImageChoice(
                    url: url,
                    width: dimensions?.width,
                    height: dimensions?.height
                )
            )
        }
        return choices
    }

    static func storefrontImageIsObviousPlaceholder(
        width: Int,
        height: Int
    ) -> Bool {
        width < 32
            || height < 32
            || width * height < 1_024
    }

    func inspectDirectCoverURLs(
        _ rawURLs: [String]
    ) async -> [SableMangaBakaDirectCoverInspection] {
        let urls = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(rawURLs)
        var inspectionsByURL: [
            String: SableMangaBakaDirectCoverInspection
        ] = [:]

        for batchStart in stride(from: 0, to: urls.count, by: 4) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                urls[
                    batchStart..<min(batchStart + 4, urls.count)
                ]
            )
            let results = await withTaskGroup(
                of: (String, ValidatedStorefrontImage?).self
            ) { group in
                for rawURL in batch {
                    group.addTask {
                        (
                            rawURL,
                            await downloadedStorefrontImage(from: rawURL)
                        )
                    }
                }
                var values:
                    [(String, ValidatedStorefrontImage?)] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }
            for (rawURL, image) in results {
                guard let image else { continue }
                inspectionsByURL[rawURL] =
                    SableMangaBakaDirectCoverInspection(
                        url: image.url,
                        width: image.width,
                        height: image.height
                    )
            }
        }

        return urls.compactMap { inspectionsByURL[$0] }
    }

    private func downloadedStorefrontImage(
        from rawURL: String
    ) async -> ValidatedStorefrontImage? {
        var best: ValidatedStorefrontImage?
        for candidateURL in Self.maximumImageURLCandidates(from: rawURL) {
            guard !Task.isCancelled else { break }
            guard let image = await downloadedStorefrontImageCandidate(
                from: candidateURL
            ) else {
                continue
            }
            if image.width * image.height
                > (best?.width ?? 0) * (best?.height ?? 0) {
                best = image
            }
        }
        return best
    }

    private func downloadedStorefrontImageCandidate(
        from rawURL: String
    ) async -> ValidatedStorefrontImage? {
        guard let url = URL(string: rawURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        guard let (data, response) = try? await Self.imageSession.data(for: request),
              data.count <= 25 * 1_024 * 1_024,
              (response as? HTTPURLResponse).map({
                  (200..<300).contains($0.statusCode)
              }) != false else {
            return nil
        }

        await Self.storefrontImageInspectionGate.acquire()
        guard !Task.isCancelled else {
            await Self.storefrontImageInspectionGate.release()
            return nil
        }
        let validated = Self.validatedStorefrontImage(
            from: data,
            archivalURL: rawURL
        )
        await Self.storefrontImageInspectionGate.release()
        return validated
    }

    private static func validatedStorefrontImage(
        from data: Data,
        archivalURL: String
    ) -> ValidatedStorefrontImage? {
        guard
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        return ValidatedStorefrontImage(
            url: archivalURL,
            width: width.intValue,
            height: height.intValue,
            contentRating: "safe",
            contentRatingWasInferred: false,
            detectedVolumeNumbers: [],
            detectedChapterNumbers: [],
            visualSignature: coverVisualSignature(from: data)
        )
    }

    static func archivalStorefrontImageURL(from rawURL: String) -> String {
        maximumImageURLCandidates(from: rawURL).first ?? rawURL
    }

    static func maximumImageURLCandidates(from rawURL: String) -> [String] {
        guard let original = URLComponents(string: rawURL),
              let host = original.host?.lowercased() else {
            return [rawURL]
        }
        var candidates: [String] = []
        var seen = Set<String>()
        func append(_ value: String?) {
            guard let value,
                  !value.isEmpty,
                  seen.insert(value).inserted else { return }
            candidates.append(value)
        }
        func replacingPath(
            _ components: URLComponents,
            pattern: String,
            replacement: String
        ) -> String? {
            var updated = components
            updated.path = components.path.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
            return updated.url?.absoluteString
        }

        if host.contains("media-amazon.com")
            || host.contains("ssl-images-amazon.com") {
            append(amazonOriginalImageURL(from: rawURL))
        }

        if host.hasSuffix("mzstatic.com"),
           original.path.contains("/image/thumb/") {
            var sized = original
            var sizedParts = sized.path.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            if !sizedParts.isEmpty {
                sizedParts[sizedParts.count - 1] = "10000x0w-999.jpg"
                sized.path = sizedParts.joined(separator: "/")
                append(sized.url?.absoluteString)
            }
        }

        if host.hasSuffix("res.booklive.jp") {
            append(replacingPath(
                original,
                pattern: #"(?i)/thumbnail/[^/.]+\.(jpe?g|png|webp)$"#,
                replacement: "/thumbnail/X.$1"
            ))
        }

        if host.hasSuffix("img.sos-dan.net") {
            var updated = original
            var parts = updated.path.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            if parts.count >= 2 {
                parts[0] = "original"
                let name = String(parts[parts.count - 1])
                    .replacingOccurrences(
                        of: #"\.(?:webp|jpe?g|png)$"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )
                parts[parts.count - 1] = Substring(name)
                updated.path = "/" + parts.joined(separator: "/")
                append(updated.url?.absoluteString)
            }
        }

        if host.hasSuffix("rimg.bookwalker.jp") {
            var updated = original
            let parts = updated.path.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            let recognizedThumbnailTokens = [
                "BM2j7K0aiKyzud2kfkni6g__",
                "eUnObgIVNjRTJtVUNQrbaQ__",
                "OWWPXNVne2Og5o9nA6tp3Q__",
                "WYSt3oZAsOZeWLNOG6XDcw__",
                "UwdNlrHZZCAtX4RcoBwrFg__",
                "frDGCemG5kX9EBY8IrbThQ__",
                "Jja0QZS03nidtl5yTloDoQ__"
            ]
            if parts.count >= 2,
               let key = parts.first,
               recognizedThumbnailTokens.contains(where: {
                   parts[1].hasPrefix($0)
               }) {
                updated.host = "c.bookwalker.jp"
                let originalExtension = (original.path as NSString).pathExtension
                let fileExtension = originalExtension.isEmpty
                    ? "jpg"
                    : originalExtension
                updated.path = "/\(key)/t_700x780.\(fileExtension)"
                append(updated.url?.absoluteString)
            }
        }

        if host.hasSuffix("c.bookwalker.jp") {
            let parts = original.path.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            if let numericKey = parts.first,
               numericKey.allSatisfy(\.isNumber),
               let reversed = Int(String(numericKey.reversed())) {
                var updated = original
                let originalExtension = (original.path as NSString).pathExtension
                let fileExtension = originalExtension.isEmpty
                    ? "jpg"
                    : originalExtension
                updated.path = "/coverImage_\(max(0, reversed - 1)).\(fileExtension)"
                updated.query = nil
                append(updated.url?.absoluteString)
            }
        }

        if host.hasSuffix("image.yes24.com") {
            append(replacingPath(
                original,
                pattern: #"(?i)(/goods/[0-9]+)(?:/[^/]+)?$"#,
                replacement: "$1/"
            ))
            append(replacingPath(
                original,
                pattern: #"(?i)(/goods/[0-9]+)(?:/[^/]+)?$"#,
                replacement: "$1/XL"
            ))
        }

        if host == "mobile.kyobobook.co.kr",
           let wrappedValue = original.queryItems?.first(where: {
               $0.name.lowercased() == "url"
           })?.value {
            append(wrappedValue)
        }
        if host.hasSuffix("contents.kyobobook.co.kr") {
            append(replacingPath(
                original,
                pattern: #"(?i)/sih/(?:fit-in/[^/]+/)?pdt/"#,
                replacement: "/pdt/"
            ))
        }
        if host.hasSuffix("image.kyobobook.co.kr") {
            var updated = original
            updated.path = updated.path.replacingOccurrences(
                of: "/images/book/large/",
                with: "/images/book/xlarge/",
                options: .caseInsensitive
            )
            updated.path = updated.path.replacingOccurrences(
                of: #"/l([0-9Xx]+\.(?:jpe?g|png))$"#,
                with: "/x$1",
                options: [.regularExpression, .caseInsensitive]
            )
            append(updated.url?.absoluteString)
        }

        if host.hasSuffix("img.ridicdn.net") {
            var updated = original
            if let coverID = firstPathCapture(
                in: updated.path,
                pattern: #"(?i)^/cover/([^/]+)"#
            ) {
                updated.path = "/cover/\(coverID)/xxlarge"
                updated.queryItems = [
                    URLQueryItem(name: "dpi", value: "xxxhdpi"),
                    URLQueryItem(name: "format", value: "png")
                ]
                append(updated.url?.absoluteString)
            }
        }

        if host.hasSuffix("image.aladin.co.kr") {
            var unqueried = original
            unqueried.query = nil
            append(unqueried.url?.absoluteString)
            append(replacingPath(
                unqueried,
                pattern: #"(?i)/(?:coversum|cover100|cover150|covermini)/"#,
                replacement: "/cover500/"
            ))
        }

        if host.hasSuffix("cdn.kobo.com") {
            var parts = original.path.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            if parts.count >= 7,
               parts[0].lowercased() == "book-images",
               Int(parts[2]) != nil,
               Int(parts[3]) != nil {
                var source = original
                parts.removeSubrange(2...5)
                source.path = "/" + parts.joined(separator: "/")
                append(source.url?.absoluteString)
            }
        }

        if host.hasSuffix("assets.shueisha.online") {
            append(replacingPath(
                original,
                pattern: #"(?i)^/image/([^/]+(?:/[^/]+)*)/[0-9]+/([^/]+)$"#,
                replacement: "/image/-/$1/0/$2"
            ))
        }

        append(rawURL)
        return candidates
    }

    private static func coverVisualSignature(from data: Data) -> [UInt8] {
        let width = 32
        let height = 48
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions
        ) else {
            return []
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            return []
        }

        var rgba = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        return rendered ? rgba : []
    }

    private static func coverInspectionMetadata(
        from data: Data
    ) -> (
        contentRating: String,
        volumeNumbers: [Int],
        chapterNumbers: [Int]
    ) {
        #if canImport(Vision)
        var recognizedText = ""
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let textHandler = VNImageRequestHandler(data: data, options: [:])
        if (try? textHandler.perform([textRequest])) != nil {
            recognizedText = (textRequest.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }

        var classifications: [String] = []
        if #available(macOS 12.0, *) {
            let classificationRequest = VNClassifyImageRequest()
            let classificationHandler = VNImageRequestHandler(
                data: data,
                options: [:]
            )
            if (try? classificationHandler.perform(
                [classificationRequest]
            )) != nil {
                classifications = (classificationRequest.results ?? [])
                    .filter { $0.confidence >= 0.12 }
                    .map(\.identifier)
            }
        }

        return (
            contentRating: inferredCoverContentRating(
                from: classifications
            ),
            volumeNumbers: SableLibraryAppleBooksCompatibilityRepairer
                .explicitCoverVolumeNumbers(in: recognizedText)
                .sorted(),
            chapterNumbers: explicitChapterNumbers(in: recognizedText)
                .sorted()
        )
        #else
        return ("safe", [], [])
        #endif
    }

    static func inferredCoverContentRating(
        from classificationIdentifiers: [String]
    ) -> String {
        let labels = classificationIdentifiers.map {
            $0.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }
        let pornographicMarkers = [
            "pornography", "pornographic", "sexual activity", "sex act",
            "genitalia", "penis", "vulva", "semen", "sex toy", "nsfw"
        ]
        if labels.contains(where: { label in
            pornographicMarkers.contains(where: label.contains)
        }) {
            return "pornographic"
        }

        let eroticaMarkers = [
            "nudity", "nude", "topless", "bottomless", "bare breast",
            "buttocks"
        ]
        if labels.contains(where: { label in
            eroticaMarkers.contains(where: label.contains)
        }) {
            return "erotica"
        }

        let suggestiveMarkers = [
            "lingerie", "underwear", "bikini", "swimsuit", "swimwear",
            "cleavage", "provocative pose", "implied nudity"
        ]
        if labels.contains(where: { label in
            suggestiveMarkers.contains(where: label.contains)
        }) {
            return "suggestive"
        }
        return "safe"
    }

    static func explicitChapterNumbers(in text: String) -> Set<Int> {
        let normalized = text.applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        ) ?? text
        let patterns = [
            #"(?i)\b(?:chapter|ch\.?)\s*[\.:#-]?\s*(\d{1,4})\b"#,
            #"(?:第\s*)?(\d{1,4})\s*話"#,
            #"(\d{1,4})\s*화"#
        ]
        var values = Set<Int>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(
                normalized.startIndex..<normalized.endIndex,
                in: normalized
            )
            for match in regex.matches(in: normalized, range: range)
            where match.numberOfRanges > 1 {
                guard let valueRange = Range(
                    match.range(at: 1),
                    in: normalized
                ),
                let value = Int(normalized[valueRange]) else {
                    continue
                }
                values.insert(value)
            }
        }
        return values
    }

    private static func hasSpecificSeriesScope(
        _ series: SableMangaBakaSeriesSummary
    ) -> Bool {
        let grouped = Dictionary(grouping: (series.titles ?? []).filter {
            !normalizedLanguageTag($0.language).hasSuffix("-latn")
        }) {
            normalizedLanguageTag($0.language)
        }
        return grouped.values.contains { titles in
            scopedTitle(in: titles.map(\.title)) != nil
        }
    }

    private static func localizedScopedTitle(
        for series: SableMangaBakaSeriesSummary,
        language: String
    ) -> String? {
        localizedScopedTitles(for: series, language: language).first
    }

    private static func localizedScopedTitles(
        for series: SableMangaBakaSeriesSummary,
        language: String
    ) -> [String] {
        let requested = normalizedLanguageTag(language)
        let allTitles = series.titles ?? []
        let exact = allTitles.filter {
            normalizedLanguageTag($0.language) == requested
        }
        let regional = allTitles.filter {
            let candidate = normalizedLanguageTag($0.language)
            return candidate.hasPrefix("\(requested)-")
                && !candidate.hasSuffix("-latn")
        }
        let localized = exact.isEmpty ? regional : exact
        var ranked: [(title: String, priority: Int)] = []
        var bestPriorityByTitle: [String: Int] = [:]

        func append(_ rawTitle: String?, priority: Int) {
            guard let title = rawTitle?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
                  !title.isEmpty else {
                return
            }
            let key = normalizedScopeTitle(title)
            guard !key.isEmpty else { return }
            if let existing = bestPriorityByTitle[key] {
                guard priority < existing else { return }
                bestPriorityByTitle[key] = priority
                if let index = ranked.firstIndex(where: {
                    normalizedScopeTitle($0.title) == key
                }) {
                    ranked[index] = (title, priority)
                }
                return
            }
            bestPriorityByTitle[key] = priority
            ranked.append((title, priority))
        }

        if requested == "ja", let nativeTitle = series.nativeTitle {
            append(nativeTitle, priority: 0)
        }
        localized.filter { $0.isPrimary == true }.forEach {
            append($0.title, priority: 0)
        }
        localized.filter { $0.traits.contains("official") }.forEach {
            append($0.title, priority: 1)
        }
        localized.filter { $0.traits.contains("native") }.forEach {
            append($0.title, priority: 2)
        }
        localized.forEach {
            append($0.title, priority: 3)
        }

        let scopedKeys = Set(
            scopedTitles(in: ranked.map(\.title)).map(normalizedScopeTitle)
        )
        var canonicalKeys = Set<String>()
        if let canonicalTitle = series.title {
            canonicalKeys.insert(normalizedScopeTitle(canonicalTitle))
        }
        if requested == "ja", let nativeTitle = series.nativeTitle {
            canonicalKeys.insert(normalizedScopeTitle(nativeTitle))
        }
        let candidates = ranked.filter {
            scopedKeys.contains(normalizedScopeTitle($0.title))
                || canonicalKeys.contains(normalizedScopeTitle($0.title))
        }
        let chosen = candidates.isEmpty
            ? scopedTitles(in: ranked.map(\.title)).map { (title: $0, priority: 4) }
            : candidates
        return chosen
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority < $1.priority
                }
                return normalizedScopeTitle($0.title).count
                    > normalizedScopeTitle($1.title).count
            }
            .map(\.title)
    }

    private static func scopedTitle(in titles: [String]) -> String? {
        scopedTitles(in: titles).first
    }

    private static func scopedTitles(in titles: [String]) -> [String] {
        let unique = Dictionary(
            titles.map { ($0.trimmingCharacters(in: .whitespacesAndNewlines), true) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        .keys
        .filter { !$0.isEmpty }
        let scoped = unique.filter { candidate in
            let normalizedCandidate = normalizedScopeTitle(candidate)
            guard normalizedCandidate.count >= 4 else { return false }
            return unique.contains { alias in
                let normalizedAlias = normalizedScopeTitle(alias)
                let candidateWithoutContributor = normalizedScopeTitle(
                    removingTrailingContributorDisambiguator(candidate)
                )
                let aliasWithoutContributor = normalizedScopeTitle(
                    removingTrailingContributorDisambiguator(alias)
                )
                return normalizedAlias.count >= 3
                    && normalizedAlias.count + 2 <= normalizedCandidate.count
                    && normalizedCandidate.contains(normalizedAlias)
                    && candidateWithoutContributor != aliasWithoutContributor
            }
        }
        return scoped.sorted {
            normalizedScopeTitle($0).count > normalizedScopeTitle($1).count
        }
    }

    private static func title(
        _ providerTitle: String,
        belongsToScopedTitle scopedTitle: String
    ) -> Bool {
        let provider = normalizedScopeTitle(providerTitle)
        let scoped = normalizedScopeTitle(scopedTitle)
        guard !provider.isEmpty, !scoped.isEmpty else { return false }
        if provider.contains(scoped) || scoped.contains(provider) {
            return true
        }

        let ignored = Set([
            "a", "an", "and", "book", "edition", "light", "novel", "of",
            "part", "the", "vol", "volume"
        ])
        let providerTokens = scopeTokens(providerTitle).subtracting(ignored)
        let scopedTokens = scopeTokens(scopedTitle).subtracting(ignored)
        guard scopedTokens.count >= 2 else { return false }
        let overlap = providerTokens.intersection(scopedTokens).count
        return Double(overlap) / Double(scopedTokens.count) >= 0.72
    }

    private static func normalizedLanguageTag(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func normalizedScopeTitle(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[\p{P}\p{S}\s]+"#,
                with: "",
                options: .regularExpression
            )
    }

    private static func removingTrailingContributorDisambiguator(
        _ value: String
    ) -> String {
        value.replacingOccurrences(
            of: #"\s*[\(（][A-Z][A-Za-z'’.-]*(?:\s+[A-Z][A-Za-z'’.-]*){0,3}[\)）]\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func scopeTokens(_ value: String) -> Set<String> {
        let normalized = value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[\p{P}\p{S}]+"#,
                with: " ",
                options: .regularExpression
            )
        return Set(normalized.split(separator: " ").map(String.init))
    }

    private func selectedBooks(
        from candidates: [SableLibraryBigBookCoversSeriesCandidate],
        provider: SableLibraryBigBookCoversProvider,
        series: SableMangaBakaSeriesSummary,
        expectedMediaType: String? = nil
    ) async -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        let targetMediaType = expectedMediaType ?? series.type
        if provider == .bookLiveJP {
            for candidate in candidates.prefix(6) {
                guard let productURL = candidate.url,
                      let titleID = SableLibraryBookLiveSeriesGroupClient.titleID(
                        from: productURL
                      ) else {
                    continue
                }
                let bbcBooks = (
                    try? await providerClient.booksWithPreviewAlternatives(
                        itemID: titleID,
                        itemType: candidate.type ?? "series",
                        provider: provider
                    )
                ) ?? []
                var books = bbcBooks
                if books.isEmpty {
                    books = (
                        try? await bookLiveClient.books(
                            productURL: productURL,
                            expectedMediaType: nil
                        )
                    ) ?? []
                }
                guard !books.isEmpty else { continue }
                let declaredMediaType =
                    books.compactMap(\.bookType).first ?? candidate.bookType
                if bbcBooks.isEmpty {
                    books = await expandedBookLiveProductBooksIfNeeded(
                        books,
                        titleID: titleID,
                        declaredMediaType: declaredMediaType,
                        targetMediaType: targetMediaType
                    )
                } else {
                    books = await booksWithStorefrontMediaProof(
                        books,
                        expectedMediaType: targetMediaType,
                        sampleLimit: 2
                    )
                }
                return (candidate.title, titleID, books)
            }

            let matches = await bookLiveClient.manualMatches(
                from: Array(candidates.prefix(6)),
                expectedMediaType: nil
            )
            guard let match = matches.first(where: {
                $0.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame
            }) ?? matches.first else {
                return nil
            }
            do {
                let books: [SableLibraryBigBookCoversBookCandidate]
                if match.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame {
                    books = try await bookLiveClient.books(
                        groupID: match.providerID,
                        expectedMediaType: nil
                    )
                } else {
                    books = try await providerClient.books(
                        itemID: match.providerID,
                        itemType: match.itemType,
                        provider: provider
                    )
                }
                guard !books.isEmpty else { return nil }
                return (match.title, match.providerID, books)
            } catch {
                return nil
            }
        }

        if provider.isAmazon {
            var seenCandidateIDs = Set<String>()
            let seriesCandidates = candidates.filter {
                $0.type?.caseInsensitiveCompare("series") == .orderedSame
            }
            let candidateLimit = provider == .amazonJP ? 1 : 4
            let candidatesToLoad = (
                seriesCandidates.isEmpty
                    ? candidates
                    : seriesCandidates
            )
            .filter { seenCandidateIDs.insert($0.id).inserted }
            .prefix(candidateLimit)

            for candidate in candidatesToLoad {
                let candidateMediaType = candidate.bookType
                    ?? Self.storefrontMediaTypeProof(
                        title: candidate.title,
                        html: nil
                    )
                guard !Task.isCancelled,
                      var rawBooks = try? await providerClient.books(
                        itemID: candidate.id,
                        itemType: candidate.type ?? "series",
                        provider: provider
                      ) else {
                    continue
                }
                for index in rawBooks.indices
                where rawBooks[index].seriesID == nil {
                    rawBooks[index].seriesID = candidate.id
                }
                if let candidateMediaType {
                    for index in rawBooks.indices
                    where rawBooks[index].bookType == nil {
                        rawBooks[index].bookType = candidateMediaType
                    }
                }
                guard !rawBooks.isEmpty else { continue }
                let books = Self.amazonBooksByAddingDirectResults(
                    rawBooks,
                    from: candidates,
                    selectedSeriesID: candidate.id,
                    series: series,
                    language: provider.languageCode
                )
                return (
                    candidate.title,
                    candidate.id,
                    books
                )
            }
            return nil
        }

        guard let candidate = candidates.first else { return nil }
        do {
            var books: [SableLibraryBigBookCoversBookCandidate]
            if provider == .bookWalkerJP || provider == .bookWalkerGlobal {
                books = try await providerClient.booksWithPreviewAlternatives(
                    itemID: candidate.id,
                    itemType: candidate.type ?? "series",
                    provider: provider
                )
            } else {
                books = try await providerClient.books(
                    itemID: candidate.id,
                    itemType: candidate.type ?? "series",
                    provider: provider
                )
            }
            if provider == .bookWalkerJP || provider == .bookWalkerGlobal {
                if candidate.bookTypeWasExplicit,
                   candidate.bookType?.lowercased().contains("audio") == true {
                    for index in books.indices {
                        books[index].bookType = "audiobook"
                        books[index].volumeType = "audiobook"
                    }
                } else {
                    books = await booksWithStorefrontMediaProof(
                        books,
                        expectedMediaType: targetMediaType,
                        sampleLimit: 2
                    )
                }
            }
            guard !books.isEmpty else { return nil }
            return (candidate.title, candidate.id, books)
        } catch {
            return nil
        }
    }

    private func selectedBooks(
        from reference: StoreSeriesReference,
        series: SableMangaBakaSeriesSummary
    ) async throws -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        if reference.provider == .bookLiveJP {
            var books: [SableLibraryBigBookCoversBookCandidate]
            if reference.itemType == "seriesGroup" {
                books = try await bookLiveClient.books(
                    groupID: reference.itemID,
                    expectedMediaType: nil
                )
            } else {
                let bbcBooks = (
                    try? await providerClient.booksWithPreviewAlternatives(
                        itemID: reference.itemID,
                        itemType: reference.itemType,
                        provider: reference.provider
                    )
                ) ?? []
                let storefrontBooks = (
                    try? await bookLiveClient.books(
                        productURL: reference.url,
                        expectedMediaType: nil
                    )
                ) ?? []
                let fallbackMediaType =
                    storefrontBooks.compactMap(\.bookType).first
                    ?? bbcBooks.compactMap(\.bookType).first
                    ?? series.type
                books = Self.mergedBookLiveProductFamilyBooks(
                    storefrontBooks: storefrontBooks,
                    bbcBooks: bbcBooks,
                    fallbackMediaType: fallbackMediaType
                )
            }
            guard !books.isEmpty else { return nil }
            return (series.displayTitle, reference.itemID, books)
        }

        if reference.provider == .barnesNobleUS {
            if reference.itemType == "book" {
                guard let html = await Self.storefrontPageHTML(
                        from: reference.url
                      ),
                      let product = Self.barnesNobleProduct(
                        from: html,
                        storeURL: reference.url,
                        query: series.displayTitle
                      ) else {
                    return nil
                }
                return (
                    series.displayTitle,
                    reference.itemID,
                    [
                        Self.barnesNobleBookCandidate(
                            product,
                            provider: reference.provider,
                            sequenceIndex: max(
                                1,
                                Int(product.volumeNumber.rounded())
                            )
                        )
                    ]
                )
            }
            guard reference.itemType == "series",
                  let html = await Self.storefrontPageHTML(from: reference.url)
            else {
                return nil
            }
            let embeddedProducts = Self.barnesNobleProducts(
                from: html,
                pageURL: reference.url,
                query: series.displayTitle
            )
            let embeddedIDs = Set(embeddedProducts.map(\.id))
            let productURLs = Array(
                Self.barnesNobleProductURLs(
                    from: html,
                    query: series.displayTitle
                )
                .filter {
                    guard let id = URL(string: $0).flatMap(
                        Self.barnesNobleProductID
                    ) else {
                        return true
                    }
                    return !embeddedIDs.contains(id)
                }
                .prefix(max(0, 80 - embeddedProducts.count))
            )
            let fetchedProducts = await barnesNobleProducts(
                productURLs: productURLs,
                query: series.displayTitle,
                referer: reference.url
            )
            let products = Self.deduplicatedBarnesNobleProducts(
                embeddedProducts + fetchedProducts
            )
            let titleMatched = products.filter {
                SableLibraryCoverDownloadPlanner.providerTitle(
                    $0.title,
                    belongsTo: series.displayTitle
                )
                    || SableLibraryCoverDownloadPlanner.providerTitle(
                        $0.seriesIdentity,
                        belongsTo: series.displayTitle
                    )
            }
            let acceptedProducts = titleMatched.isEmpty
                ? products
                : titleMatched
            let books = acceptedProducts.enumerated().map { offset, product in
                Self.barnesNobleBookCandidate(
                    product,
                    provider: reference.provider,
                    sequenceIndex: offset
                )
            }
            guard !books.isEmpty else { return nil }
            return (series.displayTitle, reference.itemID, books)
        }

        if reference.provider == .audibleUS {
            guard reference.itemType == "book" else { return nil }
            let products = try await audibleClient.search(
                query: reference.itemID
            )
            let exactProducts = products.filter {
                $0.asin.caseInsensitiveCompare(reference.itemID)
                    == .orderedSame
            }
            return Self.audibleExactSelection(
                from: exactProducts.isEmpty ? products : exactProducts,
                series: series,
                fallbackProviderSeriesID: reference.itemID
            )
        }

        if reference.provider == .appleBooksUS {
            guard reference.itemType == "book" else { return nil }
            let products: [SableAppleBooksCatalogClient.Product]
            if reference.itemID.count <= 11,
               reference.itemID.allSatisfy(\.isNumber) {
                products = try await appleBooksClient.lookup(
                    collectionID: reference.itemID
                )
            } else {
                let searched = try await appleBooksClient.search(
                    query: series.displayTitle
                )
                let exactArtworkMatches = searched.filter {
                    $0.artworkURL100?.contains(reference.itemID) == true
                }
                products = exactArtworkMatches.isEmpty
                    ? searched
                    : exactArtworkMatches
            }
            return Self.appleBooksExactSelection(
                from: products,
                series: series,
                fallbackProviderSeriesID: reference.itemID
            )
        }

        if reference.provider == .yes24 {
            guard reference.itemType == "book",
                  let html = await Self.storefrontPageHTML(
                    from: reference.url
                  ),
                  let product = Self.yes24Product(
                    from: html,
                    goodsID: reference.itemID,
                    storeURL: reference.url
                  ) else {
                return nil
            }
            let providerSeriesID = product.seriesID ?? reference.itemID
            return (
                product.title,
                providerSeriesID,
                [
                    SableLibraryBigBookCoversBookCandidate(
                        provider: .yes24,
                        id: product.id,
                        seriesID: providerSeriesID,
                        title: product.title,
                        url: product.storeURL,
                        coverURL: product.imageURL,
                        coverFallbackURLs: [],
                        volumeNumber: product.volumeNumber,
                        volumeType: "volume",
                        sequenceIndex: max(
                            1,
                            Int(product.volumeNumber.rounded())
                        ),
                        bookType: product.mediaType,
                        publicationType: "physical"
                    )
                ]
            )
        }

        if reference.provider == .kyobo {
            guard reference.itemType == "book",
                  let product = await kyoboExactProduct(
                    for: reference
                  ) else {
                return nil
            }
            return (
                product.title,
                reference.itemID,
                [
                    SableLibraryBigBookCoversBookCandidate(
                        provider: .kyobo,
                        id: product.id,
                        seriesID: reference.itemID,
                        title: product.title,
                        url: product.storeURL,
                        coverURL: product.imageURL,
                        coverFallbackURLs: [],
                        volumeNumber: product.volumeNumber,
                        volumeType: "volume",
                        sequenceIndex: max(
                            1,
                            Int(product.volumeNumber.rounded())
                        ),
                        bookType: product.mediaType,
                        publicationType:
                            reference.publicationTypeOverride
                    )
                ]
            )
        }

        guard reference.provider == .bookWalkerJP
            || reference.provider == .bookWalkerGlobal
            || reference.provider.isAmazon else {
            return nil
        }
        var books: [SableLibraryBigBookCoversBookCandidate]
        if reference.provider == .bookWalkerJP
            || reference.provider == .bookWalkerGlobal {
            books = try await providerClient.booksWithPreviewAlternatives(
                itemID: reference.itemID,
                itemType: reference.itemType,
                provider: reference.provider
            )
        } else {
            books = try await providerClient.books(
                itemID: reference.itemID,
                itemType: reference.itemType,
                provider: reference.provider
            )
        }
        books = Self.booksScopedToExactStoreReference(
            books,
            reference: reference
        )
        if reference.provider == .bookWalkerGlobal {
            let audiobookProof = await booksWithStorefrontMediaProof(
                books,
                expectedMediaType: "audiobook",
                sampleLimit: 2
            )
            if audiobookProof.contains(where: {
                $0.bookType?.lowercased().contains("audio") == true
            }) {
                books = audiobookProof
            }
        }
        if reference.provider.isAmazon,
           books.isEmpty,
           reference.itemType == "series" {
            books = try await providerClient.books(
                itemID: reference.itemID,
                itemType: "book",
                provider: reference.provider
            )
        }
        if reference.provider.isAmazon,
           !books.isEmpty,
           let query = Self.preferredQuery(
               for: reference.provider,
               series: series
           ),
           let candidates = try? await providerClient.search(
               query: query,
               provider: reference.provider
           ) {
            books = Self.amazonBooksByAddingDirectResults(
                books,
                from: candidates,
                selectedSeriesID: reference.itemID,
                series: series,
                language: reference.provider.languageCode
            )
        }
        guard !books.isEmpty else { return nil }
        return (series.displayTitle, reference.itemID, books)
    }

    static func booksScopedToExactStoreReference(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        reference: StoreSeriesReference
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        guard reference.provider.isAmazon,
              reference.itemType.caseInsensitiveCompare("book")
                == .orderedSame else {
            return books
        }
        return books.compactMap { book in
            guard book.id.caseInsensitiveCompare(reference.itemID)
                == .orderedSame else {
                return nil
            }
            var exactBook = book
            exactBook.id = reference.itemID.uppercased()
            exactBook.seriesID = exactBook.seriesID ?? reference.itemID
            exactBook.url = reference.url
            exactBook.publicationType =
                reference.publicationTypeOverride
                    ?? exactBook.publicationType
            return exactBook
        }
    }

    static func amazonBooksByAddingDirectResults(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        from candidates: [SableLibraryBigBookCoversSeriesCandidate],
        selectedSeriesID: String,
        series: SableMangaBakaSeriesSummary,
        language: String
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        let bookCandidates = candidates.filter {
            $0.type?.caseInsensitiveCompare("book") == .orderedSame
                && $0.thumbnailURL != nil
        }
        var merged = books.map { book in
            guard let imageCandidate = bookCandidates.first(where: {
                $0.id.caseInsensitiveCompare(book.id) == .orderedSame
            }) ?? bookCandidates.first(where: {
                normalizedScopeTitle($0.title)
                    == normalizedScopeTitle(book.title)
            }),
                  let thumbnailURL = imageCandidate.thumbnailURL else {
                return book
            }

            var enriched = book
            let rescueURLs = [
                amazonOriginalImageURL(from: thumbnailURL),
                thumbnailURL
            ].compactMap { $0 }
            var seenURLs = Set(
                ([book.coverURL] + book.coverFallbackURLs).map {
                    $0.lowercased()
                }
            )
            enriched.coverFallbackURLs.append(
                contentsOf: rescueURLs.filter {
                    seenURLs.insert($0.lowercased()).inserted
                }
            )
            return enriched
        }
        var seenIDs = Set(books.map(\.id))
        var seenEditionSlots = Set(
            books.compactMap { book -> String? in
                guard let number = book.volumeNumber else { return nil }
                return "\(book.publicationType ?? "unknown"):\(number)"
            }
        )

        for candidate in candidates {
            guard candidate.type?.lowercased() == "book",
                  let coverURL = candidate.thumbnailURL,
                  let volumeNumber = explicitProviderVolumeNumber(
                    in: candidate.title,
                    series: series,
                    language: language
                  ),
                  !amazonTitleIsMultiBookCollection(candidate.title) else {
                continue
            }
            let publicationType = candidate.publicationType
                ?? amazonPublicationType(itemID: candidate.id)
                ?? "unknown"
            let editionSlot = "\(publicationType):\(volumeNumber)"
            guard seenIDs.insert(candidate.id).inserted,
                  seenEditionSlots.insert(editionSlot).inserted else {
                continue
            }
            let originalCoverURL =
                amazonOriginalImageURL(from: coverURL) ?? coverURL
            merged.append(
                SableLibraryBigBookCoversBookCandidate(
                    provider: candidate.provider,
                    id: candidate.id,
                    seriesID: selectedSeriesID,
                    title: candidate.title,
                    url: candidate.url,
                    coverURL: originalCoverURL,
                    coverFallbackURLs:
                        originalCoverURL == coverURL ? [] : [coverURL],
                    volumeNumber: volumeNumber,
                    volumeType: "volume",
                    sequenceIndex: max(1, Int(volumeNumber.rounded())),
                    bookType: candidate.bookType
                        ?? storefrontMediaTypeProof(
                            title: candidate.title,
                            html: nil
                        ),
                    publicationType: publicationType
                )
            )
        }
        return merged
    }

    static func amazonOriginalImageURL(from rawURL: String) -> String? {
        guard var components = URLComponents(string: rawURL),
              let host = components.host?.lowercased(),
              host.hasSuffix("media-amazon.com"),
              components.path.contains("/images/I/") else {
            return nil
        }
        let fileName = components.path.split(separator: "/").last.map(String.init)
        guard let fileName,
              let modifierRange = fileName.range(of: "._"),
              let extensionSeparator = fileName.lastIndex(of: "."),
              modifierRange.lowerBound < extensionSeparator else {
            return rawURL
        }
        let originalFileName =
            String(fileName[..<modifierRange.lowerBound])
            + String(fileName[extensionSeparator...])
        components.path = components.path.replacingOccurrences(
            of: fileName,
            with: originalFileName
        )
        return components.url?.absoluteString ?? rawURL
    }

    private static func amazonPublicationType(itemID: String) -> String? {
        if itemID.range(
            of: #"^[0-9]{9}[0-9Xx]$"#,
            options: .regularExpression
        ) != nil {
            return "physical"
        }
        if itemID.range(
            of: #"^B[0-9A-Z]{9}$"#,
            options: .regularExpression
        ) != nil {
            return "digital"
        }
        return nil
    }

    private func kyoboExactProduct(
        for reference: StoreSeriesReference
    ) async -> KoreanStorefrontProduct? {
        if let html = await Self.storefrontPageHTML(
            from: reference.url
        ),
        let product = Self.kyoboProduct(
            from: html,
            productID: reference.itemID,
            storeURL: reference.url
        ) {
            return product
        }

        guard reference.itemID.uppercased().hasPrefix("S"),
              var components = URLComponents(
                string: "https://search.kyobobook.co.kr/search"
              ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "keyword", value: reference.itemID),
            URLQueryItem(name: "gbCode", value: "KOR"),
            URLQueryItem(name: "target", value: "total")
        ]
        guard let searchURL = components.url,
              let html = await Self.storefrontPageHTML(
                from: searchURL.absoluteString
              ) else {
            return nil
        }
        return Self.kyoboPrintProduct(
            fromSearchHTML: html,
            productID: reference.itemID,
            storeURL: reference.url
        )
    }

    private static func amazonTitleIsMultiBookCollection(
        _ title: String
    ) -> Bool {
        let normalized = title.lowercased()
        return normalized.contains("collection")
            || normalized.contains("box set")
            || normalized.contains("books set")
            || normalized.range(
                of: #"\bvol(?:ume)?s?\.?\s*\d+\s*[-–—]\s*\d+\b"#,
                options: .regularExpression
            ) != nil
            || normalized.range(
                of: #"\(\s*\d+\s+books?\s*\)"#,
                options: .regularExpression
            ) != nil
    }

    private func amazonBooksIncludingPhysicalEditions(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        maximumCompanions: Int
    ) async -> [SableLibraryBigBookCoversBookCandidate] {
        guard maximumCompanions > 0 else { return books }
        let physicalVolumes = Set(
            books.compactMap {
                $0.publicationType == "physical" ? $0.volumeNumber : nil
            }
        )
        let digitalBooks = Array(
            books.lazy.filter {
                $0.publicationType == "digital"
                    && $0.volumeNumber.map {
                        !physicalVolumes.contains($0)
                    } != false
            }
            .prefix(maximumCompanions)
        )
        guard !digitalBooks.isEmpty else { return books }

        var companions: [SableLibraryBigBookCoversBookCandidate] = []
        for batchStart in stride(
            from: 0,
            to: digitalBooks.count,
            by: 6
        ) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                digitalBooks[
                    batchStart..<min(batchStart + 6, digitalBooks.count)
                ]
            )
            let found = await withTaskGroup(
                of: SableLibraryBigBookCoversBookCandidate?.self
            ) { group in
                for book in batch {
                    group.addTask {
                        guard let html = await Self.storefrontPageHTML(
                            from: book.url
                        ),
                        let physicalID = Self.amazonPhysicalFormatIdentifier(
                            in: html
                        ),
                        let storeURL = Self.amazonProductURL(
                            matching: book.url,
                            itemID: physicalID
                        ) else {
                            return nil
                        }
                        var physical = book
                        physical.id = physicalID
                        physical.url = storeURL
                        physical.coverURL =
                            "https://m.media-amazon.com/images/P/"
                            + "\(physicalID).01.MAIN._SCRM_.jpg"
                        physical.coverFallbackURLs = []
                        physical.publicationType = "physical"
                        physical.title = Self.amazonPhysicalEditionTitle(
                            from: physical.title
                        )
                        physical.bookType = physical.bookType
                            ?? Self.amazonPhysicalFormatMediaType(in: html)
                        return physical
                    }
                }
                var values: [SableLibraryBigBookCoversBookCandidate] = []
                for await value in group {
                    if let value {
                        values.append(value)
                    }
                }
                return values
            }
            companions.append(contentsOf: found)
        }

        var seenIDs = Set(books.map(\.id))
        return books + companions.filter {
            seenIDs.insert($0.id).inserted
        }
    }

    static func amazonPhysicalFormatIdentifier(
        in html: String
    ) -> String? {
        let swatchMarkerPattern =
            #"(?is)id=["']tmm-grid-swatch-[^"']+["']"#
        if let markerRegex = try? NSRegularExpression(
            pattern: swatchMarkerPattern
        ) {
            let htmlRange = NSRange(
                html.startIndex..<html.endIndex,
                in: html
            )
            let markers = markerRegex.matches(in: html, range: htmlRange)
            for (offset, marker) in markers.enumerated() {
                guard let markerRange = Range(marker.range, in: html) else {
                    continue
                }
                let nextMarker = markers.indices.contains(offset + 1)
                    ? Range(markers[offset + 1].range, in: html)?.lowerBound
                    : nil
                let maximumBound = html.index(
                    markerRange.lowerBound,
                    offsetBy: 12_000,
                    limitedBy: html.endIndex
                ) ?? html.endIndex
                let upperBound = min(
                    nextMarker ?? html.endIndex,
                    maximumBound
                )
                let block = String(html[markerRange.lowerBound..<upperBound])
                guard amazonFormatTextIsPhysical(block),
                      let identifier = amazonProductIdentifier(in: block) else {
                    continue
                }
                return identifier
            }
        }

        let printEditionPattern =
            #"(?is)based\s+on\s+(?:the\s+)?print\s+edition.{0,240}?ISBN\s*([0-9X]{10})"#
        if let regex = try? NSRegularExpression(
            pattern: printEditionPattern
        ) {
            let range = NSRange(
                html.startIndex..<html.endIndex,
                in: html
            )
            if let match = regex.firstMatch(in: html, range: range),
               match.numberOfRanges > 1,
               let identifierRange = Range(
                match.range(at: 1),
                in: html
               ) {
                return String(html[identifierRange]).uppercased()
            }
        }

        let linkPattern =
            #"(?is)<a\b[^>]*href=["'][^"']*/dp/([A-Z0-9]{10})[^"']*["'][^>]*>([\s\S]{0,2000}?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 2,
                  let idRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            if amazonFormatTextIsPhysical(String(html[labelRange])) {
                return String(html[idRange])
            }
        }
        return nil
    }

    private static func amazonFormatTextIsPhysical(_ value: String) -> Bool {
        let normalized = value
            .lowercased()
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
        return normalized.contains("paperback")
            || normalized.contains("hardcover")
            || normalized.contains("comic (paper)")
            || normalized.contains("comics (paper)")
            || normalized.contains("コミック (紙)")
            || normalized.contains("コミック（紙）")
            || normalized.contains("ペーパーバック")
            || normalized.contains("単行本")
    }

    private static func amazonProductIdentifier(
        in html: String
    ) -> String? {
        let pattern =
            #"(?is)href=["'][^"']*/dp/([A-Z0-9]{10})(?:/|[^A-Z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let identifierRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[identifierRange])
    }

    static func amazonPhysicalEditionTitle(from title: String) -> String {
        title
            .replacingOccurrences(
                of: #"(?i)DIGITAL"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\(\s*\)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s{2,}"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func amazonPhysicalFormatMediaType(
        in html: String
    ) -> String? {
        let normalized = html
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
        if normalized.contains("comic (paper)")
            || normalized.contains("コミック (紙)")
            || normalized.contains("コミック（紙）") {
            return "manga"
        }
        return nil
    }

    private static func amazonProductURL(
        matching rawURL: String?,
        itemID: String
    ) -> String? {
        guard let rawURL,
              var components = URLComponents(string: rawURL),
              let host = components.host,
              host.lowercased().contains("amazon.") else {
            return nil
        }
        components.path = "/dp/\(itemID)"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    static func inferredSeriesMediaType(
        from books: [SableLibraryBigBookCoversBookCandidate]
    ) -> String? {
        if let declared = books.compactMap(\.bookType).first {
            return declared
        }
        let volumeTypes = books
            .compactMap(\.volumeType)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        guard !volumeTypes.isEmpty else { return nil }
        if volumeTypes.allSatisfy({ $0 == "chapter" }) {
            return "manga"
        }
        return nil
    }

    private func booksWithStorefrontMediaProof(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        expectedMediaType: String,
        sampleLimit: Int
    ) async -> [SableLibraryBigBookCoversBookCandidate] {
        var proven = books
        var unknownIndexes: [Int] = []

        for index in proven.indices {
            if proven[index].bookType != nil {
                continue
            }
            if let mediaType = Self.storefrontMediaTypeProof(
                title: proven[index].title,
                html: nil
            ) {
                proven[index].bookType = mediaType
            } else {
                unknownIndexes.append(index)
            }
        }

        let sampledIndexes = Array(unknownIndexes.prefix(max(sampleLimit, 1)))
        let sampledProof = await withTaskGroup(
            of: (Int, String?).self
        ) { group in
            for index in sampledIndexes {
                let book = proven[index]
                group.addTask {
                    let html = await Self.storefrontPageHTML(from: book.url)
                    return (
                        index,
                        Self.storefrontMediaTypeProof(
                            title: book.title,
                            html: html
                        )
                    )
                }
            }
            var values: [(Int, String?)] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        for (index, mediaType) in sampledProof {
            proven[index].bookType = mediaType
        }

        let normalizedExpected = SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(mediaType: expectedMediaType)
        let sampleTypes = Set(
            sampledProof
                .compactMap(\.1)
                .filter {
                    normalizedExpected == "audiobook"
                        || $0 != "audiobook"
                }
        )
        let safeSeriesProof = sampleTypes.count == 1
            && sampleTypes.first == normalizedExpected
            ? sampleTypes.first
            : nil

        if let safeSeriesProof {
            for index in unknownIndexes where proven[index].bookType == nil {
                proven[index].bookType = safeSeriesProof
            }
        }
        return proven
    }

    static func automaticMediaTypeDisposition(
        detectedMediaType: String?,
        expectedMediaType: String?
    ) -> AutomaticMediaTypeDisposition {
        guard SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(
                mediaType: expectedMediaType
            ) != nil else {
            return .accepted
        }
        guard SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(
                mediaType: detectedMediaType
            ) != nil else {
            return .needsReview
        }
        return SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
            detectedMediaType,
            isCompatibleWith: expectedMediaType
        )
            ? .accepted
            : .rejected
    }

    static func volumeCandidatesForMediaReview(
        from candidates: [SableLibraryProviderCoverCandidate],
        targetMediaType: String?,
        trustsSelectedSeriesIdentity: Bool,
        offersMediaTypeMismatchForReview: Bool,
        requiresRelationshipReview: inout Bool
    ) -> [SableLibraryProviderCoverCandidate] {
        // BBC and explicit user choices decide which provider rows are worth
        // seeing. Local media inference only marks uncertainty for review.
        candidates
    }

    static func automaticMatchConfidence(
        providerTitles: [String],
        series: SableMangaBakaSeriesSummary,
        language: String,
        detectedMediaType: String?,
        expectedMediaType: String?
    ) -> Double {
        guard SableLibraryCoverDownloadPlanner
            .preferredProviderBookTypeForDownload(
                mediaType: detectedMediaType
            ) != nil,
              automaticMediaTypeDisposition(
                detectedMediaType: detectedMediaType,
                expectedMediaType: expectedMediaType
              ) == .accepted else {
            return 0
        }

        return automaticRelationshipTitleConfidence(
            providerTitles: providerTitles,
            series: series,
            language: language
        )
    }

    static func shouldOfferMediaTypeMismatchForManualReview(
        providerTitles: [String],
        series: SableMangaBakaSeriesSummary,
        language: String
    ) -> Bool {
        automaticRelationshipTitleConfidence(
            providerTitles: providerTitles,
            series: series,
            language: language
        ) >= 0.90
    }

    static func automaticRelationshipTitleConfidence(
        providerTitles: [String],
        series: SableMangaBakaSeriesSummary,
        language: String
    ) -> Double {
        let references = automaticRelationshipReferenceTitles(
            for: series,
            language: language
        )
        guard !references.isEmpty else { return 0 }

        let ignoredTokens = Set([
            "a", "an", "and", "book", "edition", "light", "novel", "of",
            "part", "the", "vol", "volume"
        ])
        var bestConfidence = 0.0
        for providerTitle in providerTitles {
            let provider = normalizedScopeTitle(providerTitle)
            guard provider.count >= 4 else { continue }

            for referenceTitle in references {
                let reference = normalizedScopeTitle(referenceTitle)
                guard reference.count >= 4 else { continue }
                if provider == reference {
                    bestConfidence = max(bestConfidence, 0.99)
                    continue
                }
                if provider.contains(reference) {
                    bestConfidence = max(bestConfidence, 0.96)
                    continue
                }

                let providerTokens = scopeTokens(providerTitle)
                    .subtracting(ignoredTokens)
                    .filter { Double($0) == nil }
                let referenceTokens = scopeTokens(referenceTitle)
                    .subtracting(ignoredTokens)
                    .filter { Double($0) == nil }
                guard referenceTokens.count >= 3 else { continue }
                let overlap = Set(providerTokens)
                    .intersection(Set(referenceTokens))
                    .count
                let coverage = Double(overlap)
                    / Double(referenceTokens.count)
                if coverage >= 0.90 {
                    bestConfidence = max(bestConfidence, 0.92)
                }
            }
        }
        return bestConfidence
    }

    private static func automaticRelationshipReferenceTitles(
        for series: SableMangaBakaSeriesSummary,
        language: String
    ) -> [String] {
        if hasSpecificSeriesScope(series) {
            return localizedScopedTitle(
                for: series,
                language: language
            )
            .map { [$0] } ?? []
        }

        let requested = normalizedLanguageTag(language)
        let allTitles = series.titles ?? []
        let localized = allTitles.filter {
            let candidate = normalizedLanguageTag($0.language)
            return candidate == requested
                || (
                    candidate.hasPrefix("\(requested)-")
                        && !candidate.hasSuffix("-latn")
                )
        }
        .map(\.title)

        var references = localized
        if requested == "ja", let nativeTitle = series.nativeTitle {
            references.append(nativeTitle)
        } else if requested == "en" {
            if let title = series.title {
                references.append(title)
            }
            if let romanizedTitle = series.romanizedTitle {
                references.append(romanizedTitle)
            }
        }
        return Array(
            Set(
                references
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                    .filter { normalizedScopeTitle($0).count >= 4 }
            )
        )
    }

    static func storefrontMediaTypeProof(
        title: String,
        html: String?
    ) -> String? {
        let normalizedTitle = title
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        if normalizedTitle.contains("audiobook")
            || normalizedTitle.contains("audible audio")
            || normalizedTitle.contains("audio edition")
            || normalizedTitle.contains("オーディオブック")
            || normalizedTitle.contains("オーディオ版")
            || normalizedTitle.contains("朗読版") {
            return "audiobook"
        }
        if let html,
           let pageType = SableLibraryCoverDownloadPlanner.providerPageMediaType(
            from: html
           ) {
            return pageType
        }

        let mangaTitle = normalizedTitle
            .replacingOccurrences(of: "light novel", with: "")
        if mangaTitle.contains("(manga)")
            || mangaTitle.contains("[manga]")
            || mangaTitle.contains("graphic novel")
            || mangaTitle.contains("コミックス")
            || mangaTitle.contains("コミック")
            || mangaTitle.contains("マンガ")
            || mangaTitle.contains("漫画")
            || mangaTitle.range(
                of: #"\bmanga\b"#,
                options: .regularExpression
            ) != nil {
            return "manga"
        }
        if normalizedTitle.contains("light novel")
            || normalizedTitle.contains("(novel)")
            || normalizedTitle.contains("[novel]")
            || normalizedTitle.contains("ライトノベル")
            || normalizedTitle.contains("ラノベ")
            || normalizedTitle.contains("ノベル")
            || normalizedTitle.contains("文庫")
            || normalizedTitle.contains("小説") {
            return "novel"
        }
        return nil
    }

    private static func storefrontPageHTML(
        from rawURL: String?,
        referer: String? = nil
    ) async -> String? {
        guard !Task.isCancelled,
              let rawURL,
              let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        if referer == nil,
           let cached = await storefrontPageCache.page(for: rawURL) {
            return cached
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            (
                url.host?.lowercased().contains("amazon.co.jp") == true
                    || url.host?.lowercased()
                        .contains("books.rakuten.co.jp") == true
            )
                ? "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7"
                : "en-US,en;q=0.9",
            forHTTPHeaderField: "Accept-Language"
        )
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        guard let (data, response) = try? await Self.storefrontPageSession.data(
            for: request
        ),
        !Task.isCancelled,
        data.count <= 6 * 1_024 * 1_024,
        (response as? HTTPURLResponse).map({
            (200..<300).contains($0.statusCode)
        }) != false else {
            return nil
        }
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        if referer == nil, let html {
            await storefrontPageCache.insert(html, for: rawURL)
        }
        return html
    }

    private func compatibleSelection(
        title: String,
        providerSeriesID: String,
        declaredMediaType: String?,
        books: [SableLibraryBigBookCoversBookCandidate],
        expectedMediaType: String
    ) -> (
        title: String,
        providerSeriesID: String,
        books: [SableLibraryBigBookCoversBookCandidate]
    )? {
        if let declaredMediaType,
           !SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
            declaredMediaType,
            isCompatibleWith: expectedMediaType
           ) {
            return nil
        }

        let compatibleBooks = books.compactMap { book -> SableLibraryBigBookCoversBookCandidate? in
            let effectiveBookType = book.bookType ?? declaredMediaType
            guard SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                effectiveBookType,
                isCompatibleWith: expectedMediaType
            ) else {
                return nil
            }
            var typedBook = book
            typedBook.bookType = effectiveBookType
            return typedBook
        }
        guard !compatibleBooks.isEmpty else { return nil }
        return (title, providerSeriesID, compatibleBooks)
    }

    private func expandedBookLiveProductBooksIfNeeded(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        titleID: String,
        declaredMediaType: String?,
        targetMediaType: String?
    ) async -> [SableLibraryBigBookCoversBookCandidate] {
        let fallbackMediaType =
            declaredMediaType ?? books.compactMap(\.bookType).first ?? targetMediaType
        let typedBooks = books.map { book in
            var typedBook = book
            typedBook.bookType = typedBook.bookType ?? fallbackMediaType
            return typedBook
        }
        guard let expandedBooks = try? await providerClient
            .booksWithPreviewAlternatives(
                itemID: titleID,
                itemType: "series",
                provider: .bookLiveJP
              ) else {
            return typedBooks
        }

        let typedExpandedBooks = expandedBooks.map { book in
            var typedBook = book
            typedBook.bookType = typedBook.bookType ?? fallbackMediaType
            return typedBook
        }
        guard typedExpandedBooks.count > typedBooks.count else {
            return SableLibraryBigBookCoversClient
                .booksByMergingImageAlternatives(
                    primary: typedBooks,
                    variants: [typedExpandedBooks]
                )
        }
        return typedExpandedBooks
    }

    static func mergedBookLiveProductFamilyBooks(
        storefrontBooks: [SableLibraryBigBookCoversBookCandidate],
        bbcBooks: [SableLibraryBigBookCoversBookCandidate],
        fallbackMediaType: String?
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        func typed(
            _ books: [SableLibraryBigBookCoversBookCandidate]
        ) -> [SableLibraryBigBookCoversBookCandidate] {
            books.map { book in
                var resolved = book
                resolved.bookType = resolved.bookType ?? fallbackMediaType
                return resolved
            }
        }

        let storefront = typed(storefrontBooks)
        let bbc = typed(bbcBooks)
        guard !storefront.isEmpty else { return bbc }

        var merged = SableLibraryBigBookCoversClient
            .booksByMergingImageAlternatives(
                primary: storefront,
                variants: [bbc]
            )
        var seenIDs = Set(merged.map { $0.id.lowercased() })
        merged.append(
            contentsOf: bbc.filter {
                seenIDs.insert($0.id.lowercased()).inserted
            }
        )
        return merged.sorted {
            let lhsNumber = $0.volumeNumber ?? .greatestFiniteMagnitude
            let rhsNumber = $1.volumeNumber ?? .greatestFiniteMagnitude
            if lhsNumber != rhsNumber { return lhsNumber < rhsNumber }
            if $0.sequenceIndex != $1.sequenceIndex {
                return $0.sequenceIndex < $1.sequenceIndex
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

}

private extension SableMangaBakaCoverClient {
    struct Pagination: Decodable {
        var count: Int
        var page: Int
        var limit: Int
        var next: String?
        var previous: String?
    }

    struct SearchEnvelope: Decodable {
        var data: [SableMangaBakaSeriesSummary]
        var pagination: Pagination?
    }

    struct SeriesEnvelope: Decodable {
        var data: SableMangaBakaSeriesSummary
    }

    struct ProfileEnvelope: Decodable {
        var data: SableMangaBakaAccountProfile
    }

    struct PublicImagesEnvelope: Decodable {
        var data: [SableMangaBakaPublicImageRecord]
        var pagination: Pagination
        var availableLanguages: [String]

        enum CodingKeys: String, CodingKey {
            case data
            case pagination
            case availableLanguages = "available_languages"
        }
    }

    struct PublicWorksEnvelope: Decodable {
        var data: [PublicWorkRecord]
        var pagination: Pagination
    }

    struct PublicWorkRecord: Decodable {
        var countType: String?
        var sequenceNumeric: Double?
        var collections: [PublicWorkCollection]?

        enum CodingKeys: String, CodingKey {
            case countType = "count_type"
            case sequenceNumeric = "sequence_numeric"
            case collections
        }
    }

    struct PublicWorkCollection: Decodable {
        struct Language: Decodable {
            var iso: String
        }

        var language: Language?
        var licensed: Bool?
        var countMain: Double?

        enum CodingKeys: String, CodingKey {
            case language
            case licensed
            case countMain = "count_main"
        }
    }

    struct SableMangaBakaPublicImageRecord: Decodable, Sendable {
        struct Image: Decodable, Sendable {
            struct Raw: Decodable, Sendable {
                var url: String
                var width: Int
                var height: Int
            }

            var raw: Raw
        }

        var id: Int
        var indexNumeric: Double
        var language: String
        var type: String
        var contentRating: String?
        var image: Image

        enum CodingKeys: String, CodingKey {
            case id
            case indexNumeric = "index_numeric"
            case language
            case type
            case contentRating = "content_rating"
            case image
        }

        var rawURL: String {
            image.raw.url
        }

        var publicCoverImage: SableMangaBakaPublicCoverImage {
            SableMangaBakaPublicCoverImage(
                id: id,
                indexNumeric: indexNumeric,
                language: language,
                type: type,
                rawURL: image.raw.url,
                width: image.raw.width,
                height: image.raw.height,
                contentRating: contentRating ?? "safe"
            )
        }
    }

    struct SeriesImagesData: Codable {
        var images: [SableMangaBakaCoverImage]
    }

    struct SnapshotEnvelope: Decodable {
        struct Payload: Decodable {
            var data: SeriesImagesData
            var version: Int64
        }

        var data: Payload
    }

    struct PreviewBody: Encodable {
        var data: SeriesImagesData
        var version: Int64
    }

    struct SaveBody: Encodable {
        var data: SeriesImagesData
        var version: Int64
        var userNote: String
        var saveMode: String

        enum CodingKeys: String, CodingKey {
            case data
            case version
            case userNote = "user_note"
            case saveMode = "save_mode"
        }
    }

    struct PreviewEnvelope: Decodable {
        struct Payload: Decodable {
            var hasChanges: Bool
            var changes: [SableMangaBakaSubmissionDiff]

            enum CodingKeys: String, CodingKey {
                case hasChanges = "has_changes"
                case changes
            }
        }

        var data: Payload
    }

    struct SubmissionEnvelope: Decodable {
        struct Payload: Decodable {
            var submissionID: Int
            var status: String
            var changes: [SableMangaBakaSubmissionDiff]

            enum CodingKeys: String, CodingKey {
                case submissionID = "submission_id"
                case status
                case changes
            }
        }

        var data: Payload
    }

    struct ErrorEnvelope: Decodable {
        var message: String?
    }

    enum DownloadOutcome: Sendable {
        case saved(String)
        case skipped(String)
        case failed(String)
    }
}

extension SableMangaBakaCoverClient {
    static func seriesID(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed), id > 0 {
            return id
        }
        guard let url = URL(string: trimmed) else { return nil }
        let components = url.pathComponents
        if let seriesIndex = components.firstIndex(of: "series"),
           components.indices.contains(seriesIndex + 1),
           let id = Int(components[seriesIndex + 1]) {
            return id
        }
        return components.reversed().compactMap(Int.init).first
    }
}
