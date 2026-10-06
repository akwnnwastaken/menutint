import AppKit
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = makeEditMenu()
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private var statusItem: NSStatusItem!
    private let controller = TintController()
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: "MenuTint")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        statusItem.menu = menu

        if !CGPreflightScreenCaptureAccess() {
            // Shows the system prompt and adds MenuTint to the Screen Recording list.
            CGRequestScreenCaptureAccess()
        }
        controller.reload()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    // MARK: Menu

    private func rebuildMenu() {
        menu.removeAllItems()
        let settings = Settings.shared

        menu.addItem(disabledItem("MenuTint — \(statusText)"))

        let toggle = actionItem("Tinting Enabled", #selector(toggleEnabled))
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)

        if controller.status == .needsPermission {
            menu.addItem(.separator())
            menu.addItem(actionItem("Grant Screen Recording Permission…", #selector(openScreenRecordingSettings)))
            menu.addItem(actionItem("Restart MenuTint", #selector(relaunch)))
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Color Palette"))

        // Colours picked from the system picker or typed as a code end up in "recent".
        if !settings.rainbow && !Self.paletteContains(settings.colorHex) {
            settings.addRecentColor(settings.colorHex)
        }
        let selectedHex = settings.rainbow ? nil : settings.colorHex

        // Weak, so the grids' closures don't keep the grids alive after the menu is rebuilt.
        let grids = NSHashTable<ColorGridView>.weakObjects()
        let onSelect: (String) -> Void = { [weak self] hex in
            grids.allObjects.forEach { $0.selectedHex = hex }
            self?.applyColor(hex)
        }
        let paletteGrid = ColorGridView(rows: ColorGridView.palette)
        grids.add(paletteGrid)
        menu.addItem(viewItem(paletteGrid))

        let recents = settings.recentColors
        if !recents.isEmpty {
            menu.addItem(disabledItem("Recent Colors"))
            let recentGrid = ColorGridView(rows: [recents])
            grids.add(recentGrid)
            menu.addItem(viewItem(recentGrid))
        }
        for grid in grids.allObjects {
            grid.selectedHex = selectedHex
            grid.onSelect = onSelect
        }

        let rainbow = actionItem("Rainbow", #selector(selectRainbow))
        rainbow.image = gradientSwatch(settings.rainbowStyle, width: 14)
        rainbow.state = settings.rainbow ? .on : .off
        menu.addItem(rainbow)
        if settings.rainbow {
            let styleItem = NSMenuItem(title: "Rainbow Style: \(settings.rainbowStyle.title)", action: nil, keyEquivalent: "")
            let styles = NSMenu()
            for style in RainbowStyle.allCases {
                let item = actionItem(style.title, #selector(selectRainbowStyle(_:)))
                item.representedObject = style.rawValue
                item.image = gradientSwatch(style, width: 28)
                item.state = style == settings.rainbowStyle ? .on : .off
                styles.addItem(item)
            }
            styleItem.submenu = styles
            styleItem.image = gradientSwatch(settings.rainbowStyle, width: 28)
            menu.addItem(styleItem)

            menu.addItem(sliderItem(title: "Flow Speed", value: settings.rainbowSpeed) { [weak self] value in
                Settings.shared.rainbowSpeed = value
                self?.controller.applyStyle()
            })

            let reverse = actionItem("Reverse Direction (right to left)", #selector(toggleRainbowReversed))
            reverse.state = settings.rainbowReversed ? .on : .off
            menu.addItem(reverse)
        }

        let hexItem = actionItem("Enter Color Code…", #selector(enterHexCode))
        if !settings.rainbow {
            hexItem.title = "Enter Color Code…  (\(settings.colorHex))"
            hexItem.image = swatch(settings.color)
        }
        menu.addItem(hexItem)

        menu.addItem(actionItem("Advanced Color Picker…", #selector(pickCustomColor)))

        menu.addItem(.separator())
        menu.addItem(sliderItem(title: "Intensity", value: settings.intensity) { [weak self] value in
            Settings.shared.intensity = value
            self?.controller.applyStyle()
        })
        menu.addItem(sliderItem(title: "Sensitivity", value: settings.sensitivity) { [weak self] value in
            Settings.shared.sensitivity = value
            self?.controller.applyStyle()
        })

        menu.addItem(.separator())
        let login = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MenuTint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var statusText: String {
        switch controller.status {
        case .off: return "Off"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .needsPermission: return "Permission needed"
        case .failed(let message): return "Error: \(message)"
        }
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
        controller.reload()
    }

    private func applyColor(_ hex: String) {
        Settings.shared.colorHex = hex
        Settings.shared.rainbow = false
        controller.applyStyle()
    }

    @objc private func enterHexCode() {
        let settings = Settings.shared
        let originalHex = settings.colorHex
        let originalRainbow = settings.rainbow
        let chosen = HexEntry.run(initialHex: originalHex) { [weak self] hex in
            self?.applyColor(hex)
        }
        if let chosen {
            applyColor(chosen)
            if !Self.paletteContains(chosen) {
                settings.addRecentColor(chosen)
            }
        } else {
            // Cancelled: undo the live preview.
            settings.colorHex = originalHex
            settings.rainbow = originalRainbow
            controller.applyStyle()
        }
    }

    @objc private func selectRainbow() {
        Settings.shared.rainbow = true
        controller.applyStyle()
    }

    @objc private func selectRainbowStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = RainbowStyle(rawValue: raw) else { return }
        Settings.shared.rainbowStyle = style
        Settings.shared.rainbow = true
        controller.applyStyle()
    }

    @objc private func toggleRainbowReversed() {
        Settings.shared.rainbowReversed.toggle()
        controller.applyStyle()
    }

    @objc private func pickCustomColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = Settings.shared.color
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        applyColor(sender.color.hexString)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove MenuTint.app to the Applications folder and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private static func paletteContains(_ hex: String) -> Bool {
        ColorGridView.palette.contains { row in
            row.contains { $0.caseInsensitiveCompare(hex) == .orderedSame }
        }
    }

    /// Menu bar apps have no visible main menu, but text fields still need
    /// it for Cmd+X / Cmd+C / Cmd+V / Cmd+A / Cmd+Z.
    private static func makeEditMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        return mainMenu
    }

    private func sliderItem(title: String, value: Double, onChange: @escaping (Double) -> Void) -> NSMenuItem {
        let view = SliderMenuView(title: title, value: value)
        view.onChange = onChange
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    private func gradientSwatch(_ style: RainbowStyle, width: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: width, height: 14), flipped: false) { rect in
            let shape = rect.insetBy(dx: 1, dy: 1)
            let path = width > 14
                ? NSBezierPath(roundedRect: shape, xRadius: 3, yRadius: 3)
                : NSBezierPath(ovalIn: shape)
            NSGradient(colors: style.cycle + [style.cycle[0]])?.draw(in: path, angle: 0)
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}
