//
//  SableCoversWorkspaceView.swift
//  Sable's Covers
//

import SwiftUI

private enum SableCoversWorkspace: String, CaseIterable, Identifiable {
    case library
    case mangaBaka

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "My Library"
        case .mangaBaka: "MangaBaka Studio"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .mangaBaka: "globe"
        }
    }
}

struct SableCoversWorkspaceView: View {
    @Environment(\.sableLibraryPalette) private var palette
    @State private var workspace = SableCoversWorkspace.library

    var body: some View {
        VStack(spacing: 0) {
            workspaceBar
            Divider()

            switch workspace {
            case .library:
                ContentView(mode: .covers)
            case .mangaBaka:
                SableMangaBakaCoverStudioView()
            }
        }
        .frame(minWidth: 1160, minHeight: 740)
        .sableLibraryAmbientBackground()
    }

    private var workspaceBar: some View {
        HStack(spacing: 12) {
            Label("Sable's Covers", systemImage: "photo.stack")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            Picker("Workspace", selection: $workspace) {
                ForEach(SableCoversWorkspace.allCases) { workspace in
                    Label(workspace.title, systemImage: workspace.symbol)
                        .tag(workspace)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(palette.surface)
    }
}
