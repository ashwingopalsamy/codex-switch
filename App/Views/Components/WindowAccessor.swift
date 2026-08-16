import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = FocusSuppressingNSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.initialFirstResponder = nil
                window.makeFirstResponder(nil)
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            configure(window)
        }
    }
}

private final class FocusSuppressingNSView: NSView {
    override var acceptsFirstResponder: Bool { false }
}
