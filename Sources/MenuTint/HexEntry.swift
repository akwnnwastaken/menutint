import AppKit

/// Small dialog for typing a colour code (#RRGGBB / RRGGBB / #RGB) with a live preview.
@MainActor
final class HexEntry: NSObject, NSTextFieldDelegate {
    private let field = NSTextField(frame: NSRect(x: 34, y: 0, width: 186, height: 24))
    private let preview = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    private let onPreview: (String) -> Void

    private init(initialHex: String, onPreview: @escaping (String) -> Void) {
        self.onPreview = onPreview
        super.init()
        field.stringValue = initialHex
        field.placeholderString = "#FF8800"
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.delegate = self

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 5
        preview.layer?.borderWidth = 0.5
        preview.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
        updatePreview()
    }

    /// Shows the dialog. Returns the chosen hex, or nil if cancelled.
    /// `onPreview` is called with every valid code while typing.
    static func run(initialHex: String, onPreview: @escaping (String) -> Void) -> String? {
        let entry = HexEntry(initialHex: initialHex, onPreview: onPreview)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        accessory.addSubview(entry.preview)
        accessory.addSubview(entry.field)

        let alert = NSAlert()
        alert.messageText = "Enter Color Code"
        alert.informativeText = "For example: #FF8800, FF8800 or #F80"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = entry.field

        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            if let color = NSColor(hex: entry.field.stringValue) {
                return color.hexString
            }
            NSSound.beep()
            alert.informativeText = "“\(entry.field.stringValue)” is not a valid color code. For example: #FF8800"
        }
        return nil
    }

    func controlTextDidChange(_ notification: Notification) {
        updatePreview()
        if let color = NSColor(hex: field.stringValue) {
            onPreview(color.hexString)
        }
    }

    private func updatePreview() {
        let color = NSColor(hex: field.stringValue)
        preview.layer?.backgroundColor = (color ?? .clear).cgColor
        preview.alphaValue = color == nil ? 0.3 : 1
    }
}
