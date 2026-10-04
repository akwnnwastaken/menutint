import AppKit
import IOSurface
import ScreenCaptureKit

/// Borderless window that may sit on top of the menu bar.
private final class OverlayWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Recolours the menu bar of one screen: captures the menu bar strip and shows
/// the tinted result in a transparent, click-through window right on top of it.
@MainActor
final class MenuBarTinter {
    let displayID: CGDirectDisplayID
    let window: NSWindow

    var onStreamStopped: (() -> Void)?

    private let hostLayer: CALayer
    /// Menu bar area in display-local points (top-left origin), as ScreenCaptureKit expects.
    private let captureRect: CGRect
    private let scale: CGFloat
    /// The menu bar as it looks on screen (minus MenuTint's own overlays).
    private var sceneStream: SCStream?
    /// Only the menu bar's own windows, over black.
    private var itemsStream: SCStream?
    private var processor: FrameProcessor?
    private var stopped = false
    private var display: SCDisplay?
    private var currentWindowIDs: Set<CGWindowID> = []

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let height = Self.menuBarHeight(on: screen)
        // Screens without a visible menu bar (or with an auto-hiding one) are skipped.
        guard height > 0 else { return nil }

        displayID = CGDirectDisplayID(number.uint32Value)
        scale = screen.backingScaleFactor
        captureRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
        let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let layer = CALayer()
        layer.contentsGravity = .resize
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.layer = layer
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()

        self.window = window
        self.hostLayer = layer
    }

    /// Starts both captures of this display's menu bar strip.
    func start(display: SCDisplay, content: SCShareableContent, overlays: [SCWindow], maskCube: Data, fill: TintRenderer.Fill) async throws {
        guard !stopped else { return }

        let overlayIDs = Set(overlays.map(\.windowID))
        let items = menuBarWindows(in: content, display: display, overlayIDs: overlayIDs)
        currentWindowIDs = Set(items.map(\.windowID))
        self.display = display

        let processor = FrameProcessor(
            maskCube: maskCube,
            fill: fill,
            onFrame: { [weak self] image in
                DispatchQueue.main.async { self?.present(image) }
            },
            onStop: { [weak self] _ in
                DispatchQueue.main.async { self?.onStreamStopped?() }
            }
        )
        // Never capture the overlays themselves, or they would feed back into the result.
        let sceneStream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: overlays),
            configuration: makeConfiguration(),
            delegate: processor
        )
        let itemsConfig = makeConfiguration()
        itemsConfig.backgroundColor = Self.black
        let itemsStream = SCStream(
            filter: SCContentFilter(display: display, including: items),
            configuration: itemsConfig,
            delegate: processor
        )
        try sceneStream.addStreamOutput(processor, type: .screen, sampleHandlerQueue: processor.queue)
        try itemsStream.addStreamOutput(processor, type: .screen, sampleHandlerQueue: processor.queue)
        processor.sceneStream = sceneStream
        processor.itemsStream = itemsStream
        self.sceneStream = sceneStream
        self.itemsStream = itemsStream
        self.processor = processor
        processor.update(appMenuWidth: appMenuWidth(content: content, display: display, overlayIDs: overlayIDs))

        try await itemsStream.startCapture()
        try await sceneStream.startCapture()
        if stopped {
            try? await itemsStream.stopCapture()
            try? await sceneStream.stopCapture()
        }
    }

    /// Picks up status items that appeared or disappeared since the last call.
    func refreshWindows(content: SCShareableContent, overlayIDs: Set<CGWindowID>) {
        guard !stopped, let itemsStream, let display else { return }
        processor?.update(appMenuWidth: appMenuWidth(content: content, display: display, overlayIDs: overlayIDs))
        let windows = menuBarWindows(in: content, display: display, overlayIDs: overlayIDs)
        let ids = Set(windows.map(\.windowID))
        guard ids != currentWindowIDs else { return }
        currentWindowIDs = ids
        itemsStream.updateContentFilter(SCContentFilter(display: display, including: windows)) { error in
            if let error {
                NSLog("MenuTint: could not update capture filter: \(error.localizedDescription)")
            }
        }
    }

    private func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = captureRect
        config.width = Int((captureRect.width * scale).rounded())
        config.height = Int((captureRect.height * scale).rounded())
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        // The menu bar rarely changes; 20 fps keeps updates prompt but cheap.
        config.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        config.queueDepth = 4
        return config
    }

    /// Width in pixels of the app menu area: from the left edge up to the first
    /// status item (MenuTint's own status item always exists, so there is one).
    private func appMenuWidth(content: SCShareableContent, display: SCDisplay, overlayIDs: Set<CGWindowID>) -> CGFloat {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let firstStatusItemX = menuBarWindows(in: content, display: display, overlayIDs: overlayIDs)
            .filter { $0.windowLayer == statusLevel && $0.frame.width < display.frame.width / 2 }
            .map { $0.frame.minX - display.frame.minX }
            .min() ?? captureRect.width / 2
        return max(0, firstStatusItemX - 6) * scale
    }

    /// Windows that live entirely inside this display's menu bar strip:
    /// the menu bar itself (app menus) and every status item.
    private func menuBarWindows(in content: SCShareableContent, display: SCDisplay, overlayIDs: Set<CGWindowID>) -> [SCWindow] {
        // SCWindow / SCDisplay frames use global coordinates with a top-left origin.
        let strip = CGRect(
            x: display.frame.minX,
            y: display.frame.minY,
            width: display.frame.width,
            height: captureRect.height
        ).insetBy(dx: 0, dy: -2)
        return content.windows.filter { window in
            !overlayIDs.contains(window.windowID)
                && window.isOnScreen
                && (20..<100).contains(window.windowLayer)
                && window.frame.width > 0
                && window.frame.height > 0
                && strip.contains(window.frame)
        }
    }

    func update(maskCube: Data, fill: TintRenderer.Fill) {
        processor?.update(maskCube: maskCube, fill: fill)
    }

    func stop() {
        stopped = true
        let stoppingProcessor = processor
        for stream in [sceneStream, itemsStream].compactMap({ $0 }) {
            stream.stopCapture { _ in
                withExtendedLifetime(stoppingProcessor) {}
            }
        }
        sceneStream = nil
        itemsStream = nil
        processor = nil
        window.orderOut(nil)
    }

    private func present(_ image: IOSurface) {
        guard !stopped else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer.contents = image
        CATransaction.commit()
    }

    /// `SCStreamConfiguration.backgroundColor` does not retain the colour it is
    /// given, so it must outlive every configuration that uses it.
    private static let black = CGColor(gray: 0, alpha: 1)

    private static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return reserved > 0 ? ceil(reserved) : 0
    }
}
