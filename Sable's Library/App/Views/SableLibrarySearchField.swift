//
//  SableLibrarySearchField.swift
//  Sable's Library
//

import SwiftUI

#if os(macOS)
import AppKit

struct SableLibrarySearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchFieldDidChange(_:))
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        if searchField.placeholderString != placeholder {
            searchField.placeholderString = placeholder
        }
        context.coordinator.text = $text
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func searchFieldDidChange(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text.wrappedValue = searchField.stringValue
        }
    }
}
#else
struct SableLibrarySearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
    }
}
#endif
