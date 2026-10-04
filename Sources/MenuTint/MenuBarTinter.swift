import AppKit
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
    private var stream: SCStream?
    private var processor: FrameProcessor?
    private var stopped = false

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

    /// Starts capturing. `overlays` are the SCWindows of all MenuTint overlays,
    /// which must be excluded so the overlay never captures itself.
    func start(display: SCDisplay, excluding overlays: [SCWindow], maskCube: Data, fill: TintRenderer.Fill) async throws {
        guard !stopped else { return }

        let config = SCStreamConfiguration()
        config.sourceRect = captureRect
        config.width = Int((captureRect.width * scale).rounded())
        config.height = Int((captureRect.height * scale).rounded())
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5

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
        let filter = SCContentFilter(display: display, excludingWindows: overlays)
        let stream = SCStream(filter: filter, configuration: config, delegate: processor)
        try stream.addStreamOutput(processor, type: .screen, sampleHandlerQueue: processor.queue)
        self.stream = stream
        self.processor = processor

        try await stream.startCapture()
        if stopped {
            try? await stream.stopCapture()
        }
    }

    func update(maskCube: Data, fill: TintRenderer.Fill) {
        processor?.update(maskCube: maskCube, fill: fill)
    }

    func stop() {
        stopped = true
        if let stream {
            let processor = self.processor
            stream.stopCapture { _ in
                withExtendedLifetime(processor) {}
            }
        }
        stream = nil
        processor = nil
        window.orderOut(nil)
    }

    private func present(_ image: CGImage) {
        guard !stopped else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer.contents = image
        CATransaction.commit()
    }

    private static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return reserved > 0 ? ceil(reserved) : 0
    }
}
