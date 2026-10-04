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

        let toggle = actionItem("Renklendirme Açık", #selector(toggleEnabled))
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)

        if controller.status == .needsPermission {
            menu.addItem(.separator())
            menu.addItem(actionItem("Ekran Kaydı İzni Ver…", #selector(openScreenRecordingSettings)))
            menu.addItem(actionItem("MenuTint'i Yeniden Başlat", #selector(relaunch)))
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Renk Paleti"))

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
            menu.addItem(disabledItem("Son Kullanılanlar"))
            let recentGrid = ColorGridView(rows: [recents])
            grids.add(recentGrid)
            menu.addItem(viewItem(recentGrid))
        }
        for grid in grids.allObjects {
            grid.selectedHex = selectedHex
            grid.onSelect = onSelect
        }

        let rainbow = actionItem("Gökkuşağı", #selector(selectRainbow))
        rainbow.image = rainbowSwatch()
        rainbow.state = settings.rainbow ? .on : .off
        menu.addItem(rainbow)
        if settings.rainbow {
            menu.addItem(sliderItem(title: "Akış Hızı", value: settings.rainbowSpeed) { [weak self] value in
                Settings.shared.rainbowSpeed = value
                self?.controller.applyStyle()
            })
        }

        let hexItem = actionItem("Renk Kodu Gir…", #selector(enterHexCode))
        if !settings.rainbow {
            hexItem.title = "Renk Kodu Gir…  (\(settings.colorHex))"
            hexItem.image = swatch(settings.color)
        }
        menu.addItem(hexItem)

        menu.addItem(actionItem("Gelişmiş Renk Seçici…", #selector(pickCustomColor)))

        menu.addItem(.separator())
        menu.addItem(sliderItem(title: "Yoğunluk", value: settings.intensity) { [weak self] value in
            Settings.shared.intensity = value
            self?.controller.applyStyle()
        })
        menu.addItem(sliderItem(title: "Hassasiyet", value: settings.sensitivity) { [weak self] value in
            Settings.shared.sensitivity = value
            self?.controller.applyStyle()
        })

        menu.addItem(.separator())
        let login = actionItem("Girişte Başlat", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var statusText: String {
        switch controller.status {
        case .off: return "Kapalı"
        case .starting: return "Başlatılıyor…"
        case .running: return "Çalışıyor"
        case .needsPermission: return "İzin gerekli"
        case .failed(let message): return "Hata: \(message)"
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
            alert.messageText = "Girişte başlatma ayarlanamadı"
            alert.informativeText = "\(error.localizedDescription)\n\nMenuTint.app'i Uygulamalar klasörüne taşıyıp tekrar deneyin."
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
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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

    private func rainbowSwatch() -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            let gradient = NSGradient(colors: [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple])
            gradient?.draw(in: path, angle: 0)
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}
