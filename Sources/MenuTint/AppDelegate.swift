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
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private struct Preset {
        let name: String
        let hex: String
    }

    private let presets = [
        Preset(name: "Kırmızı", hex: "#FF453A"),
        Preset(name: "Turuncu", hex: "#FF9F0A"),
        Preset(name: "Sarı", hex: "#FFD60A"),
        Preset(name: "Altın", hex: "#E6C35C"),
        Preset(name: "Yeşil", hex: "#30D158"),
        Preset(name: "Nane", hex: "#63E6BE"),
        Preset(name: "Turkuaz", hex: "#32ADE6"),
        Preset(name: "Mavi", hex: "#0A84FF"),
        Preset(name: "Mor", hex: "#BF5AF2"),
        Preset(name: "Pembe", hex: "#FF375F"),
    ]

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
        menu.addItem(disabledItem("Renk"))

        var matchedPreset = false
        for preset in presets {
            let item = actionItem(preset.name, #selector(selectPreset(_:)))
            item.representedObject = preset.hex
            item.image = swatch(NSColor(hex: preset.hex) ?? .white)
            if !settings.rainbow && settings.colorHex.caseInsensitiveCompare(preset.hex) == .orderedSame {
                item.state = .on
                matchedPreset = true
            }
            menu.addItem(item)
        }

        let rainbow = actionItem("Gökkuşağı", #selector(selectRainbow))
        rainbow.image = rainbowSwatch()
        rainbow.state = settings.rainbow ? .on : .off
        menu.addItem(rainbow)

        let custom = actionItem("Özel Renk…", #selector(pickCustomColor))
        if !settings.rainbow && !matchedPreset {
            custom.state = .on
            custom.image = swatch(settings.color)
        }
        menu.addItem(custom)

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

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        Settings.shared.colorHex = hex
        Settings.shared.rainbow = false
        controller.applyStyle()
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
        Settings.shared.colorHex = sender.color.hexString
        Settings.shared.rainbow = false
        controller.applyStyle()
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
