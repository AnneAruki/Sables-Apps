//
//  SableMangaBakaRemoteThumbnail.swift
//  Sable's Covers
//

import AppKit
import ImageIO
import SwiftUI

struct SableMangaBakaRemoteThumbnail: View {
    @Environment(\.sableLibraryPalette) private var palette

    let url: URL?
    let width: CGFloat
    let height: CGFloat

    @State private var image: CGImage?
    @State private var didFail = false

    private var maximumPixelSize: Int {
        max(
            72,
            min(
                420,
                Int(ceil(max(width, height) * 2))
            )
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else if didFail || url == nil {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                    Text(url == nil ? "No image URL" : "Source unavailable")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border))
        .accessibilityElement(children: didFail || url == nil ? .combine : .ignore)
        .accessibilityLabel(
            url == nil
                ? "No cover image URL"
                : didFail
                    ? "Cover image source unavailable"
                    : "Cover image"
        )
        .task(id: "\(url?.absoluteString ?? "none"):\(maximumPixelSize)") {
            image = nil
            didFail = false
            guard let url else {
                didFail = true
                return
            }
            image = await SableMangaBakaThumbnailRepository.shared.thumbnail(
                for: url,
                maximumPixelSize: maximumPixelSize
            )
            didFail = image == nil
        }
    }
}

private struct SableMangaBakaThumbnailCacheKey: Hashable {
    var url: URL
    var maximumPixelSize: Int
}

private actor SableMangaBakaThumbnailLoadGate {
    static let shared = SableMangaBakaThumbnailLoadGate(limit: 2)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var activeIDs: Set<UUID> = []
    private var cancelledIDs: Set<UUID> = []
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire(id: UUID) async -> Bool {
        if Task.isCancelled || cancelledIDs.remove(id) != nil {
            return false
        }
        if activeIDs.count < limit {
            activeIDs.insert(id)
            return true
        }
        return await withCheckedContinuation { continuation in
            if Task.isCancelled || cancelledIDs.remove(id) != nil {
                continuation.resume(returning: false)
            } else {
                waiters.append(
                    Waiter(id: id, continuation: continuation)
                )
            }
        }
    }

    func cancel(id: UUID) {
        if activeIDs.contains(id) {
            return
        }
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else {
            cancelledIDs.insert(id)
        }
    }

    func release(id: UUID) {
        guard activeIDs.remove(id) != nil else { return }
        resumeNextWaiter()
    }

    private func resumeNextWaiter() {
        while activeIDs.count < limit, !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            if cancelledIDs.remove(waiter.id) != nil {
                waiter.continuation.resume(returning: false)
                continue
            }
            activeIDs.insert(waiter.id)
            waiter.continuation.resume(returning: true)
        }
    }
}

private actor SableMangaBakaThumbnailRepository {
    static let shared = SableMangaBakaThumbnailRepository()

    private var cache: [SableMangaBakaThumbnailCacheKey: CGImage] = [:]
    private var cacheCosts: [SableMangaBakaThumbnailCacheKey: Int] = [:]
    private var cacheOrder: [SableMangaBakaThumbnailCacheKey] = []
    private var cachedBytes = 0
    private let maximumCachedImages = 48
    private let maximumCachedBytes = 32 * 1_024 * 1_024
    private nonisolated static let thumbnailSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    func thumbnail(
        for url: URL,
        maximumPixelSize: Int
    ) async -> CGImage? {
        let key = SableMangaBakaThumbnailCacheKey(
            url: url,
            maximumPixelSize: maximumPixelSize
        )
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        guard !Task.isCancelled else { return nil }
        let image = await Self.loadThumbnail(
            from: url,
            maximumPixelSize: maximumPixelSize
        )
        guard !Task.isCancelled else { return nil }

        if let image {
            let cost = max(0, image.bytesPerRow * image.height)
            if let previousCost = cacheCosts[key] {
                cachedBytes -= previousCost
            }
            cache[key] = image
            cacheCosts[key] = cost
            cachedBytes += cost
            touch(key)
            while cacheOrder.count > maximumCachedImages
                || cachedBytes > maximumCachedBytes {
                removeOldestCachedImage()
            }
        }
        return image
    }

    private func touch(_ key: SableMangaBakaThumbnailCacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func removeOldestCachedImage() {
        guard !cacheOrder.isEmpty else { return }
        let expired = cacheOrder.removeFirst()
        cache[expired] = nil
        cachedBytes -= cacheCosts.removeValue(forKey: expired) ?? 0
    }

    private nonisolated static func loadThumbnail(
        from url: URL,
        maximumPixelSize: Int
    ) async -> CGImage? {
        let permitID = UUID()
        let acquired = await withTaskCancellationHandler {
            await SableMangaBakaThumbnailLoadGate.shared.acquire(
                id: permitID
            )
        } onCancel: {
            Task {
                await SableMangaBakaThumbnailLoadGate.shared.cancel(
                    id: permitID
                )
            }
        }
        guard acquired else { return nil }
        guard !Task.isCancelled else {
            await SableMangaBakaThumbnailLoadGate.shared.release(
                id: permitID
            )
            return nil
        }

        let image = await loadThumbnailWithPermit(
            from: url,
            maximumPixelSize: maximumPixelSize
        )
        await SableMangaBakaThumbnailLoadGate.shared.release(
            id: permitID
        )
        return image
    }

    private nonisolated static func loadThumbnailWithPermit(
        from url: URL,
        maximumPixelSize: Int
    ) async -> CGImage? {
        for candidateURL in candidateURLs(for: url) {
            guard !Task.isCancelled else { return nil }
            var request = URLRequest(
                url: candidateURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 20
            )
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue(
                "image/avif,image/webp,image/*,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            if let referer = referer(for: candidateURL) {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }

            do {
                let (data, response) = try await thumbnailSession.data(for: request)
                guard !Task.isCancelled else { return nil }
                guard !data.isEmpty,
                      data.count <= 24 * 1_024 * 1_024 else {
                    continue
                }
                if let response = response as? HTTPURLResponse,
                   !(200..<300).contains(response.statusCode) {
                    continue
                }
                if let image = await Task.detached(
                    priority: .utility,
                    operation: {
                        downsampledImage(
                            from: data,
                            maximumPixelSize: maximumPixelSize
                        )
                    }
                ).value {
                    return image
                }
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
        }
        return nil
    }

    private nonisolated static func candidateURLs(for url: URL) -> [URL] {
        guard url.host?.caseInsensitiveCompare("images.mangabaka.dev") == .orderedSame,
              let data = url.absoluteString.data(using: .utf8) else {
            return [url]
        }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let proxyURL = URL(
            string: "https://cdn.mangabaka.dev/imgproxy/plain/x350@2/\(encoded)"
        ) else {
            return [url]
        }
        return [proxyURL, url]
    }

    private nonisolated static func referer(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "c.bookwalker.jp"
            || host.hasSuffix(".bookwalker.jp") {
            return "https://bookwalker.jp/"
        }
        if host == "res.booklive.jp"
            || host.hasSuffix(".booklive.jp") {
            return "https://booklive.jp/"
        }
        return nil
    }

    private nonisolated static func downsampledImage(
        from data: Data,
        maximumPixelSize: Int
    ) -> CGImage? {
        autoreleasepool {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(
                data as CFData,
                sourceOptions
            ) else {
                return nil
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            )
        }
    }
}
