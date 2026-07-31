//
//  SableLibraryConfig.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryConfig: Decodable, Sendable {
    struct MetadataProvider: Decodable, Sendable {
        var enabled: Bool = true
        var apiBaseURL: String = ""
        var requestDelaySeconds: Double = 1.0
        var timeoutSeconds: Double = 15
        var cacheTTLSeconds: TimeInterval = 604800
        var requiresAPIKey: Bool = false

        enum CodingKeys: String, CodingKey {
            case enabled
            case apiBaseURL = "api_base_url"
            case requestDelaySeconds = "request_delay_seconds"
            case timeoutSeconds = "timeout_seconds"
            case cacheTTLSeconds = "cache_ttl_seconds"
            case requiresAPIKey = "requires_api_key"
        }
    }

    struct MetadataProviders: Decodable, Sendable {
        var ranobeDB = MetadataProvider(apiBaseURL: "https://ranobedb.org/api/v0/", requestDelaySeconds: 1.1)
        var openLibrary = MetadataProvider(apiBaseURL: "https://openlibrary.org/", requestDelaySeconds: 1.0)
        var anilist = MetadataProvider(apiBaseURL: "https://graphql.anilist.co/", requestDelaySeconds: 2.1)
        var tvmaze = MetadataProvider(apiBaseURL: "https://api.tvmaze.com/", requestDelaySeconds: 0.6)
        var wikidata = MetadataProvider(apiBaseURL: "https://query.wikidata.org/sparql", requestDelaySeconds: 1.0)
        var tmdb = MetadataProvider(enabled: false, apiBaseURL: "https://api.themoviedb.org/3/", requestDelaySeconds: 1.0, requiresAPIKey: true)
        var tvdb = MetadataProvider(enabled: false, apiBaseURL: "https://api4.thetvdb.com/v4/", requestDelaySeconds: 1.0, requiresAPIKey: true)

        enum CodingKeys: String, CodingKey {
            case ranobeDB = "ranobedb"
            case openLibrary = "open_library"
            case anilist
            case tvmaze
            case wikidata
            case tmdb
            case tvdb
        }
    }

    struct MangaBaka: Decodable, Sendable {
        var apiBaseURL: String = "https://api.mangabaka.org/v1/"
        var maxSearchResults: Int = 10
        var requestDelaySeconds: Double = 1.0
        var timeoutSeconds: Double = 15
        var preferredType: String = "novel"

        enum CodingKeys: String, CodingKey {
            case apiBaseURL = "api_base_url"
            case maxSearchResults = "max_search_results"
            case requestDelaySeconds = "request_delay_seconds"
            case timeoutSeconds = "timeout_seconds"
            case preferredType = "preferred_type"
        }
    }

    struct Reports: Decodable, Sendable {
        var previewReport: String = "_sable_preview_report.txt"
        var metadataReport: String = "_sable_metadata_candidates.txt"
        var undoPlanJSON: String = "_sable_undo_plan.json"
        var restoreReport: String = "_sable_restore_report.txt"
        var runSummaryReport: String = "_sable_run_summary.txt"
        var catalogJSON: String = "_sable_catalog.json"
        var rootCatalogCSV: String = "Sable Library Catalog.csv"
        var summaryJSON: String = "_sable_run_summary.json"

        enum CodingKeys: String, CodingKey {
            case previewReport = "preview_report"
            case metadataReport = "metadata_report"
            case undoPlanJSON = "undo_plan_json"
            case restoreReport = "restore_report"
            case runSummaryReport = "run_summary_report"
            case catalogJSON = "catalog_json"
            case rootCatalogCSV = "root_catalog_csv"
            case summaryJSON = "summary_json"
        }
    }

    var bookExtensions: [String]
    var videoExtensions: [String]
    var packageExtensions: [String]
    var duplicateFolderName: String
    var missingNumberFolderName: String
    var reportFolderName: String
    var comicInfoFileName: String
    var animeInfoFileName: String
    var ignoreNames: [String]
    var sourceMetadataTerms: [String]
    var reports: Reports
    var mangaBaka: MangaBaka
    var metadataProviders: MetadataProviders

    enum CodingKeys: String, CodingKey {
        case bookExtensions = "book_extensions"
        case videoExtensions = "video_extensions"
        case packageExtensions = "package_extensions"
        case duplicateFolderName = "duplicate_folder_name"
        case missingNumberFolderName = "missing_number_folder_name"
        case reportFolderName = "report_folder_name"
        case comicInfoFileName = "comicinfo_file_name"
        case animeInfoFileName = "animeinfo_file_name"
        case ignoreNames = "ignore_names"
        case sourceMetadataTerms = "source_metadata_terms"
        case reports
        case mangaBaka = "mangabaka"
        case metadataProviders = "metadata_providers"
    }

    static let fallback = SableLibraryConfig(
        bookExtensions: [".epub", ".pdf", ".kepub", ".cbz", ".cbr", ".cb7", ".mobi", ".azw", ".azw3", ".ibooks", ".iba", ".djvu"],
        videoExtensions: [".mkv", ".mp4", ".m4v", ".avi", ".mov", ".wmv", ".webm", ".ts", ".m2ts"],
        packageExtensions: [".epub", ".ibooks", ".iba"],
        duplicateFolderName: "_Possible Duplicates",
        missingNumberFolderName: "_Missing Numbers",
        reportFolderName: "_Sable's Library Reports",
        comicInfoFileName: "ComicInfo.json",
        animeInfoFileName: "AnimeInfo.json",
        ignoreNames: ["_Possible Duplicates", "_Missing Numbers", "_Sable's Library Reports", "_Do Not Touch", "Sable Library Catalog.csv"],
        sourceMetadataTerms: ["digital", "digital edition", "uploaded", "uploader", "scan", "scans", "hentaiocean", "kobo", "kindle", "premium"],
        reports: Reports(),
        mangaBaka: MangaBaka(),
        metadataProviders: MetadataProviders()
    )
}
