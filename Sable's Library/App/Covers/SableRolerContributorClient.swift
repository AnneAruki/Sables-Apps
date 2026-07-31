//
//  SableRolerContributorClient.swift
//  Sable's Covers
//

import AppKit
import Foundation
import SwiftUI
import WebKit

nonisolated struct SableRolerContributorCredentials: Sendable, Equatable {
    var userToken: String
    var sessionID: String

    init(userToken: String, sessionID: String) {
        self.userToken = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isAvailable: Bool {
        !userToken.isEmpty
    }
}

nonisolated struct SableRolerContributorSession: Sendable, Equatable {
    var role: String
    var username: String?
    var userID: String

    var canEdit: Bool {
        ["developer", "contributor", "moderator", "admin"]
            .contains(role.lowercased())
    }

    var accountLabel: String {
        let name = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 }
            ?? "MangaBaka account"
    }
}

nonisolated struct SableRolerSeriesReference: Codable, Sendable, Equatable, Hashable {
    var providerId: String
    var id: String
}

nonisolated struct SableRolerBookVolumeCorrection: Codable, Sendable, Equatable {
    var providerId: String
    var id: String
    var seriesId: String
    var volumeNumber: Double
}

nonisolated struct SableRolerRateLimit: Sendable, Equatable {
    var limit: Int?
    var remaining: Int?
    var resetSeconds: Int?
}

nonisolated struct SableRolerMutationResult: Sendable, Equatable {
    var rateLimit: SableRolerRateLimit
}

nonisolated enum SableRolerMatchShareStatus: Sendable, Equatable {
    case sharing
    case shared
    case failed(String)
}

nonisolated enum SableRolerBookCorrectionStatus: Sendable, Equatable {
    case saving
    case saved
    case localOnly(String)
    case failed(String)
}

nonisolated enum SableRolerContributorError: LocalizedError, Equatable {
    case signInRequired
    case contributorAccessRequired
    case rateLimited(resetSeconds: Int?)
    case rejected(String)
    case invalidResponse

    var errorDescription: String? {
        return switch self {
        case .signInRequired:
            "Sign in to Roler with your MangaBaka contributor account first."
        case .contributorAccessRequired:
            "This MangaBaka account does not currently have BBC contributor edit access."
        case .rateLimited(let seconds):
            if let seconds {
                "Roler is temporarily rate-limited. Try again in \(Self.durationText(seconds))."
            } else {
                "Roler is temporarily rate-limited. Try again later."
            }
        case .rejected(let message):
            message
        case .invalidResponse:
            "Roler returned an unexpected response."
        }
    }

    private static func durationText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(max(1, seconds)) seconds" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        return minutes == 1 ? "about a minute" : "about \(minutes) minutes"
    }
}

nonisolated struct SableRolerContributorClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://c.roler.dev")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func contributorSession(
        credentials: SableRolerContributorCredentials
    ) async throws -> SableRolerContributorSession {
        guard credentials.isAvailable else {
            throw SableRolerContributorError.signInRequired
        }
        var request = URLRequest(
            url: baseURL.appending(path: "user/me")
        )
        request.timeoutInterval = 12
        addAuthentication(credentials, to: &request)
        let (data, response) = try await session.data(for: request)
        let httpResponse = try validatedResponse(response, data: data)
        let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
        let result = SableRolerContributorSession(
            role: envelope.data.role,
            username: envelope.data.username,
            userID: envelope.data.userId
        )
        guard result.canEdit else {
            throw SableRolerContributorError.contributorAccessRequired
        }
        _ = rateLimit(from: httpResponse)
        return result
    }

    func mapSeries(
        _ series: [SableRolerSeriesReference],
        credentials: SableRolerContributorCredentials
    ) async throws -> SableRolerMutationResult {
        guard credentials.isAvailable else {
            throw SableRolerContributorError.signInRequired
        }
        let normalized = Array(
            Set(
                series.compactMap { reference -> SableRolerSeriesReference? in
                    let providerID = reference.providerId
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let seriesID = reference.id
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !providerID.isEmpty, !seriesID.isEmpty else {
                        return nil
                    }
                    return SableRolerSeriesReference(
                        providerId: providerID,
                        id: seriesID
                    )
                }
            )
        )
        .sorted {
            ($0.providerId, $0.id) < ($1.providerId, $1.id)
        }
        guard normalized.count >= 2 else {
            throw SableRolerContributorError.rejected(
                "Roler needs MangaBaka and at least one store series to confirm a match."
            )
        }

        var request = URLRequest(url: baseURL.appending(path: "map"))
        request.httpMethod = "PATCH"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthentication(credentials, to: &request)
        request.httpBody = try JSONEncoder().encode(
            SeriesMutationBody(series: normalized)
        )
        return try await mutationResult(for: request)
    }

    func editBookVolumes(
        _ corrections: [SableRolerBookVolumeCorrection],
        credentials: SableRolerContributorCredentials
    ) async throws -> SableRolerMutationResult {
        guard credentials.isAvailable else {
            throw SableRolerContributorError.signInRequired
        }
        guard !corrections.isEmpty else {
            throw SableRolerContributorError.rejected(
                "Choose at least one confirmed volume-number correction."
            )
        }

        var request = URLRequest(
            url: baseURL.appending(path: "edit/books")
        )
        request.httpMethod = "PATCH"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthentication(credentials, to: &request)
        request.httpBody = try JSONEncoder().encode(
            BookMutationBody(
                books: corrections.map {
                    BookMutation(
                        providerId: $0.providerId,
                        id: $0.id,
                        seriesId: $0.seriesId,
                        volume: BookVolume(
                            number: Self.volumeNumberString(
                                $0.volumeNumber
                            )
                        )
                    )
                }
            )
        )
        return try await mutationResult(for: request)
    }

    func logout(
        credentials: SableRolerContributorCredentials
    ) async {
        guard credentials.isAvailable else { return }
        var request = URLRequest(
            url: baseURL.appending(path: "user/logout")
        )
        request.httpMethod = "POST"
        addAuthentication(credentials, to: &request)
        _ = try? await session.data(for: request)
    }

    private func mutationResult(
        for request: URLRequest
    ) async throws -> SableRolerMutationResult {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try validatedResponse(response, data: data)
        let envelope = try JSONDecoder().decode(
            MutationEnvelope.self,
            from: data
        )
        if let failure = envelope.failures.first {
            throw SableRolerContributorError.rejected(
                "\(failure.providerId)/\(failure.id): \(failure.message)"
            )
        }
        if let error = envelope.failureMessage, !error.isEmpty {
            throw SableRolerContributorError.rejected(error)
        }
        return SableRolerMutationResult(
            rateLimit: rateLimit(from: httpResponse)
        )
    }

    private func validatedResponse(
        _ response: URLResponse,
        data: Data
    ) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw SableRolerContributorError.invalidResponse
        }
        switch response.statusCode {
        case 200..<300:
            return response
        case 401:
            throw SableRolerContributorError.signInRequired
        case 403:
            throw SableRolerContributorError.contributorAccessRequired
        case 429:
            throw SableRolerContributorError.rateLimited(
                resetSeconds: integerHeader(
                    "ratelimit-reset",
                    response: response
                ) ?? integerHeader("retry-after", response: response)
            )
        default:
            let message = (try? JSONDecoder().decode(
                ErrorEnvelope.self,
                from: data
            ))?.error
            throw SableRolerContributorError.rejected(
                message?.isEmpty == false
                    ? message!
                    : "Roler could not save this confirmed match (HTTP \(response.statusCode))."
            )
        }
    }

    private func addAuthentication(
        _ credentials: SableRolerContributorCredentials,
        to request: inout URLRequest
    ) {
        request.setValue(
            credentials.userToken,
            forHTTPHeaderField: "X-User-Token"
        )
        if !credentials.sessionID.isEmpty {
            request.setValue(
                credentials.sessionID,
                forHTTPHeaderField: "X-Session-Id"
            )
        }
    }

    private func rateLimit(
        from response: HTTPURLResponse
    ) -> SableRolerRateLimit {
        SableRolerRateLimit(
            limit: integerHeader("ratelimit-limit", response: response),
            remaining: integerHeader(
                "ratelimit-remaining",
                response: response
            ),
            resetSeconds: integerHeader(
                "ratelimit-reset",
                response: response
            )
        )
    }

    private func integerHeader(
        _ name: String,
        response: HTTPURLResponse
    ) -> Int? {
        guard let value = response.value(forHTTPHeaderField: name) else {
            return nil
        }
        return Int(value)
    }

    private static func volumeNumberString(_ number: Double) -> String {
        let rounded = number.rounded()
        if abs(number - rounded) < 0.000_001,
           rounded >= Double(Int.min),
           rounded <= Double(Int.max) {
            return String(Int(rounded))
        }
        return String(number)
    }

    private struct SessionEnvelope: Decodable {
        var data: SessionData
    }

    private struct SessionData: Decodable {
        var role: String
        var username: String?
        var userId: String
    }

    private struct SeriesMutationBody: Encodable {
        var series: [SableRolerSeriesReference]
    }

    private struct MutationEnvelope: Decodable {
        var data: MutationData?
        var error: String?
        var mappingError: String?
        var mappingFailed: [MutationFailure]?
        var bookError: String?
        var bookFailed: [MutationFailure]?

        var failures: [MutationFailure] {
            (data?.failed ?? [])
                + (mappingFailed ?? [])
                + (bookFailed ?? [])
        }

        var failureMessage: String? {
            [error, mappingError, bookError]
                .compactMap { $0 }
                .first { !$0.isEmpty }
        }

        private enum CodingKeys: String, CodingKey {
            case data
            case error
            case mappingError = "mapping_error"
            case mappingFailed = "mapping_failed"
            case bookError = "book_error"
            case bookFailed = "book_failed"
        }
    }

    private struct MutationData: Decodable {
        var failed: [MutationFailure]?
    }

    private struct MutationFailure: Decodable {
        var providerId: String
        var id: String
        var message: String
    }

    private struct ErrorEnvelope: Decodable {
        var error: String?
    }

    private struct BookMutationBody: Encodable {
        var books: [BookMutation]
    }

    private struct BookMutation: Encodable {
        var providerId: String
        var id: String
        var seriesId: String
        var volume: BookVolume
    }

    private struct BookVolume: Encodable {
        var number: String
    }
}

nonisolated enum SableRolerContributorSharing {
    static let defaultsKey = "sableLibrary.rolerShareConfirmedMatches"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: defaultsKey)
    }
}

nonisolated struct SableRolerMappingReceiptStore {
    private let key = "sableLibrary.rolerConfirmedMappingReceipts"

    func contains(_ signature: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
            .contains(signature)
    }

    func record(_ signature: String) {
        var signatures = Set(
            UserDefaults.standard.stringArray(forKey: key) ?? []
        )
        signatures.insert(signature)
        UserDefaults.standard.set(
            signatures.sorted(),
            forKey: key
        )
    }
}

nonisolated struct SableStorefrontRelationshipApprovalStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "sableLibrary.approvedStorefrontRelationships"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func containsAll(_ signatures: Set<String>) -> Bool {
        guard !signatures.isEmpty else { return false }
        let saved = Set(defaults.stringArray(forKey: key) ?? [])
        return signatures.isSubset(of: saved)
    }

    func record(_ signatures: Set<String>) {
        guard !signatures.isEmpty else { return }
        var saved = Set(defaults.stringArray(forKey: key) ?? [])
        saved.formUnion(signatures)
        defaults.set(saved.sorted(), forKey: key)
    }

    func remove(_ signatures: Set<String>) {
        guard !signatures.isEmpty else { return }
        var saved = Set(defaults.stringArray(forKey: key) ?? [])
        saved.subtract(signatures)
        defaults.set(saved.sorted(), forKey: key)
    }
}

extension SableLibraryProviderCredentials {
    nonisolated var rolerContributorCredentials:
        SableRolerContributorCredentials {
        SableRolerContributorCredentials(
            userToken: rolerUserToken,
            sessionID: rolerSessionID
        )
    }
}

extension SableLibraryBigBookCoversProvider {
    nonisolated var rolerProviderID: String? {
        switch self {
        case .yes24,
             .kyobo,
             .audibleUS,
             .rakutenKobo,
             .rakutenKoboNetherlands,
             .rakutenKoboJapan,
             .rakutenKoboFrance,
             .rakutenKoboGermany,
             .rakutenKoboItaly,
             .rakutenKoboSpain,
             .rakutenKoboUK,
             .barnesNobleUS,
             .crunchyrollStore:
            nil
        default:
            rawValue
        }
    }
}

struct SableRolerContributorLoginView: View {
    let onAuthenticated: (String, String) -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign In to Roler")
                        .font(.headline)
                    Text(
                        "Use the MangaBaka account that has your contributor role."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            SableRolerContributorWebLogin(
                onAuthenticated: onAuthenticated,
                onFailure: { errorMessage = $0 }
            )

            if let errorMessage {
                Divider()
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
    }
}

private struct SableRolerContributorWebLogin: NSViewRepresentable {
    let onAuthenticated: (String, String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onAuthenticated: onAuthenticated,
            onFailure: onFailure
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(
            URLRequest(
                url: URL(string: "https://c.roler.dev/user/login")!
            )
        )
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onAuthenticated: (String, String) -> Void
        private let onFailure: (String) -> Void
        private var didFinish = false

        init(
            onAuthenticated: @escaping (String, String) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onAuthenticated = onAuthenticated
            self.onFailure = onFailure
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard !didFinish,
                  let url = navigationAction.request.url,
                  let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                  ) else {
                decisionHandler(.allow)
                return
            }
            let query = (components.queryItems ?? []).reduce(
                into: [String: String]()
            ) { values, item in
                values[item.name] = item.value ?? ""
            }
            guard let token = query["user_token"], !token.isEmpty else {
                decisionHandler(.allow)
                return
            }
            didFinish = true
            decisionHandler(.cancel)
            onAuthenticated(token, query["session_id"] ?? "")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            let nsError = error as NSError
            guard !didFinish, nsError.code != NSURLErrorCancelled else {
                return
            }
            onFailure(
                "The Roler sign-in page could not load. Check your connection and try again."
            )
        }
    }
}
