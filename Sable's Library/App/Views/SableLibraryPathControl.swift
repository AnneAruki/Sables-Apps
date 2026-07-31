//
//  SableLibraryPathControl.swift
//  Sable's Library
//

import SwiftUI

#if os(macOS)
import AppKit

struct SableLibraryPathControl: NSViewRepresentable {
    var url: URL
    var onOpen: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.url = url
        control.target = context.coordinator
        control.action = #selector(Coordinator.openPath(_:))
        control.focusRingType = .default
        control.isEditable = false
        control.toolTip = url.path(percentEncoded: false)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel("Selected library folder path")
        control.setAccessibilityValue(url.path(percentEncoded: false))
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        context.coordinator.onOpen = onOpen
        control.url = url
        control.target = context.coordinator
        control.action = #selector(Coordinator.openPath(_:))
        control.toolTip = url.path(percentEncoded: false)
        control.setAccessibilityValue(url.path(percentEncoded: false))
    }

    final class Coordinator: NSObject {
        var onOpen: (URL) -> Void

        init(onOpen: @escaping (URL) -> Void) {
            self.onOpen = onOpen
        }

        @objc func openPath(_ sender: NSPathControl) {
            if let clickedURL = sender.clickedPathItem?.url {
                onOpen(clickedURL)
            } else if let url = sender.url {
                onOpen(url)
            }
        }
    }
}
#else
struct SableLibraryPathControl: View {
    var url: URL
    var onOpen: (URL) -> Void = { _ in }

    var body: some View {
        Text(url.path(percentEncoded: false))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
#endif
