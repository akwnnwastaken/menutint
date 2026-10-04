import AppKit
import ScreenCaptureKit

/// Owns one `MenuBarTinter` per screen and keeps them in sync with the settings.
@MainActor
final class TintController: NSObject {
    enum Status: Equatable {
        case off
        case starting
        case running(screens: Int)
        case needsPermission
        case failed(String)
    }

    private(set) var status: Status = .off

    private var tinters: [MenuBarTinter] = []
    private var generation = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(environmentChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(environmentChanged), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(environmentChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    /// Tears everything down and starts again from the current settings.
    @objc func reload() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(reload), object: nil)
        generation += 1
        let currentGeneration = generation

        tinters.forEach { $0.stop() }
        tinters = []

        guard Settings.shared.enabled else {
            status = .off
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            status = .needsPermission
            // Check again shortly, in case the user grants access in System Settings.
            perform(#selector(reload), with: nil, afterDelay: 3)
            return
        }

        let created = NSScreen.screens.compactMap { MenuBarTinter(screen: $0) }
        for tinter in created {
            tinter.onStreamStopped = { [weak self] in self?.scheduleReload(after: 3) }
        }
        tinters = created
        status = .starting

        Task {
            await startCapture(for: created, generation: currentGeneration)
        }
    }

    /// Pushes the current colour / sensitivity / intensity to the running overlays.
    func applyStyle() {
        let cube = Self.currentMaskCube()
        let fill = Self.currentFill()
        tinters.forEach { $0.update(maskCube: cube, fill: fill) }
    }

    // MARK: Private

    @objc private func environmentChanged() {
        scheduleReload(after: 1)
    }

    private func scheduleReload(after delay: TimeInterval) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(reload), object: nil)
        perform(#selector(reload), with: nil, afterDelay: delay)
    }

    private var overlayIDs: Set<CGWindowID> {
        Set(tinters.map { CGWindowID($0.window.windowNumber) })
    }

    private func startCapture(for tinters: [MenuBarTinter], generation currentGeneration: Int) async {
        let overlayIDs = self.overlayIDs

        // The freshly ordered-in overlay windows can take a moment to show up in
        // the shareable content, and capturing without excluding them would
        // feed the overlay back into itself.
        for _ in 0..<10 {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            } catch {
                guard currentGeneration == generation else { return }
                status = .failed(error.localizedDescription)
                return
            }
            guard currentGeneration == generation else { return }

            let overlays = content.windows.filter { overlayIDs.contains($0.windowID) }
            guard overlays.count == overlayIDs.count else {
                try? await Task.sleep(nanoseconds: 150_000_000)
                continue
            }

            var started = 0
            for tinter in tinters {
                guard let display = content.displays.first(where: { $0.displayID == tinter.displayID }) else { continue }
                do {
                    try await tinter.start(
                        display: display,
                        content: content,
                        overlays: overlays,
                        maskCube: Self.currentMaskCube(),
                        fill: Self.currentFill()
                    )
                    started += 1
                } catch {
                    NSLog("MenuTint: could not start capture: \(error.localizedDescription)")
                }
                guard currentGeneration == generation else { return }
            }
            status = started > 0 ? .running(screens: started) : .failed("Ekran yakalama başlatılamadı")
            if started > 0 {
                scheduleWindowRefresh()
            }
            return
        }

        guard currentGeneration == generation else { return }
        status = .failed("Kaplama pencereleri bulunamadı")
    }

    // New status items appear when apps launch; keep the captured window list current.
    private func scheduleWindowRefresh() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshWindows), object: nil)
        perform(#selector(refreshWindows), with: nil, afterDelay: 2)
    }

    @objc private func refreshWindows() {
        guard case .running = status else { return }
        let currentGeneration = generation
        Task {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard currentGeneration == generation else { return }
            if let content {
                let overlayIDs = self.overlayIDs
                tinters.forEach { $0.refreshWindows(content: content, overlayIDs: overlayIDs) }
            }
            scheduleWindowRefresh()
        }
    }

    private static func currentMaskCube() -> Data {
        MaskLUT.make(floor: Settings.shared.whitenessFloor, intensity: Settings.shared.intensity)
    }

    private static func currentFill() -> TintRenderer.Fill {
        if Settings.shared.rainbow {
            return .rainbow
        }
        let color = Settings.shared.color.usingColorSpace(.sRGB) ?? .white
        return .solid(CIColor(cgColor: color.cgColor))
    }
}
