//
//  SableLibraryProviderGraph.swift
//  Sable's Library
//

import Foundation

struct SableLibraryProviderRequest: Sendable, Equatable {
    var provider: SableLibraryMetadataProvider
    var url: URL
    var requiresAPIKey: Bool
    var timeoutSeconds: Double
    var cacheTTLSeconds: TimeInterval
}

struct SableLibraryProviderGraphPlanner: Sendable {
    func readingProviders(config: SableLibraryConfig) -> [SableLibraryMetadataProvider] {
        [.mangabaka, .ranobedb, .openLibrary, .wikidata, .anilist]
            .filter { providerConfig(for: $0, config: config)?.enabled ?? true }
    }

    func watchingProviders(config: SableLibraryConfig) -> [SableLibraryMetadataProvider] {
        [.anilist, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb]
            .filter { providerConfig(for: $0, config: config)?.enabled ?? true }
    }

    func searchRequest(provider: SableLibraryMetadataProvider, query: String, config: SableLibraryConfig) -> SableLibraryProviderRequest? {
        let searchQuery = SableLibraryProviderQueryCleaner.searchTitle(from: query) ?? query
        guard let providerConfig = providerConfig(for: provider, config: config),
              providerConfig.enabled,
              let url = searchURL(provider: provider, query: searchQuery, config: config, providerConfig: providerConfig) else {
            return nil
        }
        return SableLibraryProviderRequest(
            provider: provider,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    func providerConfig(for provider: SableLibraryMetadataProvider, config: SableLibraryConfig) -> SableLibraryConfig.MetadataProvider? {
        switch provider {
        case .mangabaka:
            SableLibraryConfig.MetadataProvider(
                apiBaseURL: config.mangaBaka.apiBaseURL,
                requestDelaySeconds: config.mangaBaka.requestDelaySeconds,
                timeoutSeconds: config.mangaBaka.timeoutSeconds
            )
        case .ranobedb:
            config.metadataProviders.ranobeDB
        case .openLibrary:
            config.metadataProviders.openLibrary
        case .myAnimeList:
            nil
        case .anilist:
            config.metadataProviders.anilist
        case .tvmaze:
            config.metadataProviders.tvmaze
        case .wikidata:
            config.metadataProviders.wikidata
        case .tmdb:
            config.metadataProviders.tmdb
        case .tvdb:
            config.metadataProviders.tvdb
        case .imdb, .local:
            nil
        }
    }

    private func searchURL(
        provider: SableLibraryMetadataProvider,
        query: String,
        config: SableLibraryConfig,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> URL? {
        var base = providerConfig.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }

        switch provider {
        case .mangabaka:
            return url(baseURL: baseURL, path: ["series", "search"], queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "\(max(1, min(config.mangaBaka.maxSearchResults, 10)))")
            ])
        case .ranobedb:
            return url(baseURL: baseURL, path: ["releases"], queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "rl", value: "en"),
                URLQueryItem(name: "limit", value: "10")
            ])
        case .openLibrary:
            return url(baseURL: baseURL, path: ["search.json"], queryItems: [
                URLQueryItem(name: "title", value: query),
                URLQueryItem(name: "lang", value: "en"),
                URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn,edition_key,publisher,subject,language,editions,editions.key,editions.title,editions.language"),
                URLQueryItem(name: "limit", value: "10")
            ])
        case .tmdb:
            return url(baseURL: baseURL, path: ["search", "multi"], queryItems: [
                URLQueryItem(name: "query", value: query)
            ])
        case .tvdb:
            return url(baseURL: baseURL, path: ["search"], queryItems: [
                URLQueryItem(name: "query", value: query)
            ])
        case .tvmaze:
            return url(baseURL: baseURL, path: ["singlesearch", "shows"], queryItems: [
                URLQueryItem(name: "q", value: query)
            ])
        case .myAnimeList:
            return nil
        case .anilist, .wikidata, .imdb, .local:
            return baseURL
        }
    }

    private func url(baseURL: URL, path: [String], queryItems: [URLQueryItem]) -> URL? {
        let endpoint = path.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url
    }
}
