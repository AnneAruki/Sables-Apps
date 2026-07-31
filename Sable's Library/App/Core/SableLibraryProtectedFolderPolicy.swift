//
//  SableLibraryProtectedFolderPolicy.swift
//  Sable's Library
//

import Foundation

struct SableLibraryProtectedFolderScope: Sendable, Equatable {
    let paths: Set<String>

    var count: Int {
        paths.count
    }

    func contains(_ relativePath: String) -> Bool {
        let normalized = Self.normalized(relativePath)
        guard !normalized.isEmpty else { return false }
        return paths.contains { protectedPath in
            normalized == protectedPath || normalized.hasPrefix(protectedPath + "/")
        }
    }

    func allowingOnlyMutableItems(_ items: [LibraryItem]) -> [LibraryItem] {
        items.filter { !contains($0.relativePath) }
    }

    static func normalized(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
    }
}

enum SableLibraryProtectedFolderPolicy {
    static func scope(
        in items: [LibraryItem],
        config: SableLibraryConfig,
        fileManager: FileManager
    ) -> SableLibraryProtectedFolderScope {
        var protectedPaths: [String] = []

        for item in items where item.isDirectory {
            let path = SableLibraryProtectedFolderScope.normalized(item.relativePath)
            guard !path.isEmpty,
                  !protectedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }),
                  protectionReason(
                    folderName: item.name,
                    folderURL: item.url,
                    config: config,
                    fileManager: fileManager
                  ) != nil else {
                continue
            }
            protectedPaths.append(path)
        }

        return SableLibraryProtectedFolderScope(paths: Set(protectedPaths))
    }

    static func protectionReason(
        folderName: String,
        folderURL: URL,
        config: SableLibraryConfig,
        fileManager: FileManager
    ) -> String? {
        let normalizedName = folderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if protectedUserRootFolderNames.contains(normalizedName) {
            return "This is a top-level user folder, not a raw cleanup item."
        }

        if protectedInfrastructureFolderNames.contains(normalizedName)
            || normalizedName.hasSuffix(".noindex") {
            return "This is a build, cache, or tool-generated folder."
        }

        if protectedProjectFolderExtensions.contains(folderURL.pathExtension.lowercased()) {
            return "This is a project, app, or game package."
        }

        func childExists(_ name: String) -> Bool {
            fileManager.fileExists(atPath: folderURL.appendingPathComponent(name).path(percentEncoded: false))
        }

        if childExists(config.reportFolderName) {
            return "This folder contains Sable reports and looks like an existing library root."
        }
        if childExists(".git") || childExists(".hg") || childExists(".svn") {
            return "This folder contains source control metadata."
        }
        if childExists(".codex") {
            return "This folder contains Codex project configuration."
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return nil
        }

        let childNames = Set(children.map { $0.lastPathComponent.lowercased() })
        if childNames.contains(where: { protectedProjectManifestNames.contains($0) }) {
            return "This folder contains a project manifest."
        }
        if children.contains(where: { protectedProjectFolderExtensions.contains($0.pathExtension.lowercased()) }) {
            return "This folder contains a project, app, or game package."
        }
        if children.contains(where: { protectedGameExecutableExtensions.contains($0.pathExtension.lowercased()) }) {
            return "This folder contains a game or app executable."
        }
        if childNames.contains("assets"), childNames.contains("projectsettings") {
            return "This folder looks like a Unity project."
        }
        if childNames.contains("content"), childNames.contains("config"),
           children.contains(where: { $0.pathExtension.caseInsensitiveCompare("uproject") == .orderedSame }) {
            return "This folder looks like an Unreal project."
        }
        if childNames.contains(".gitignore"),
           childNames.contains(where: { $0 == "readme" || $0.hasPrefix("readme.") }) {
            return "This folder looks like a source project."
        }

        return nil
    }

    private static let protectedUserRootFolderNames: Set<String> = [
        "applications",
        "desktop",
        "developer",
        "documents",
        "downloads",
        "library",
        "movies",
        "music",
        "pictures",
        "projects",
        "public"
    ]

    private static let protectedInfrastructureFolderNames: Set<String> = [
        ".build",
        ".swiftpm",
        "build",
        "cache",
        "caches",
        "carthage",
        "compilationcache.noindex",
        "deriveddata",
        "dist",
        "index.noindex",
        "modulecache.noindex",
        "node_modules",
        "pods",
        "sdkstatcaches.noindex",
        "sourcepackages",
        "xcbuilddata",
        "xcuserdata"
    ]

    private static let protectedProjectFolderExtensions: Set<String> = [
        "app",
        "gmx",
        "gmx2",
        "love",
        "mlpackage",
        "noindex",
        "playground",
        "playgroundbook",
        "swiftpm",
        "unity",
        "uproject",
        "xcresult",
        "xcworkspace",
        "xcodeproj"
    ]

    private static let protectedProjectManifestNames: Set<String> = [
        "build.gradle",
        "cartfile",
        "cmakelists.txt",
        "composer.json",
        "game.project",
        "go.mod",
        "makefile",
        "package.json",
        "package.swift",
        "podfile",
        "pom.xml",
        "project.godot",
        "project.yml",
        "pyproject.toml",
        "settings.gradle",
        "steam_appid.txt",
        "tuist.swift"
    ]

    private static let protectedGameExecutableExtensions: Set<String> = [
        "exe"
    ]
}
