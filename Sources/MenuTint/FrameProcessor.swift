import CoreImage
import CoreMedia
import IOSurface
import ScreenCaptureKit

/// Receives the two menu bar captures (scene + items-only) from ScreenCaptureKit
/// and renders the tinted overlay on its own queue.
final class FrameProcessor: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "MenuTint.frames", qos: .userInteractive)

    private let renderer: TintRenderer
    private let onFrame: @Sendable (IOSurface) -> Void
    private let onStop: @Sendable (Error) -> Void

    /// Set before capture starts; used to tell the two streams apart.
    weak var sceneStream: SCStream?
    weak var itemsStream: SCStream?

    /// Latest frames, kept so style changes show up even while the menu bar is
    /// static (ScreenCaptureKit only delivers frames when something changes).
    private var lastScene: CIImage?
    /// Pixels from the left edge that hold the app menus (Finder, File, Edit…).
    private var appMenuWidth: CGFloat = 0

    /// Rendering is coalesced: both streams often deliver a frame for the same
    /// change, and at most one render happens per `minimumDrawInterval`.
    private static let minimumDrawInterval = DispatchTimeInterval.milliseconds(50)
    private var drawScheduled = false
    private var lastDraw = DispatchTime(uptimeNanoseconds: 0)
    private var lastItems: CIImage?

    init(
        maskCube: Data,
        fill: TintRenderer.Fill,
        onFrame: @escaping @Sendable (IOSurface) -> Void,
        onStop: @escaping @Sendable (Error) -> Void
    ) {
        renderer = TintRenderer(maskCube: maskCube, fill: fill)
        self.onFrame = onFrame
        self.onStop = onStop
        super.init()
    }

    func update(maskCube: Data, fill: TintRenderer.Fill) {
        queue.async {
            self.renderer.setMaskCube(maskCube)
            self.renderer.fill = fill
            self.scheduleDraw()
        }
    }

    func update(appMenuWidth: CGFloat) {
        queue.async {
            guard self.appMenuWidth != appMenuWidth else { return }
            self.appMenuWidth = appMenuWidth
            self.scheduleDraw()
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              Self.frameStatus(of: sampleBuffer) == .complete,
              Self.hasChanges(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        if stream === itemsStream {
            lastItems = frame
        } else if stream === sceneStream {
            lastScene = frame
        }
        scheduleDraw()
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("MenuTint: capture stopped: \(error.localizedDescription)")
        onStop(error)
    }

    // MARK: Private

    private func scheduleDraw() {
        guard !drawScheduled else { return }
        drawScheduled = true
        let earliest = lastDraw + Self.minimumDrawInterval
        let now = DispatchTime.now()
        queue.asyncAfter(deadline: earliest > now ? earliest : now) {
            self.drawScheduled = false
            self.lastDraw = .now()
            self.draw()
        }
    }

    private func draw() {
        guard let scene = lastScene, let items = lastItems, scene.extent == items.extent else { return }
        if let image = renderer.render(scene: scene, items: items, appMenuWidth: appMenuWidth) {
            onFrame(image)
        }
    }

    /// False when ScreenCaptureKit reports that nothing inside the captured
    /// area changed (it can deliver frames for changes elsewhere on screen).
    private static func hasChanges(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let dirtyRects = attachments.first?[.dirtyRects] as? [NSDictionary]
        else { return true }
        return dirtyRects.contains { dictionary in
            guard let rect = CGRect(dictionaryRepresentation: dictionary) else { return true }
            return !rect.isEmpty
        }
    }

    private static func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int
        else { return nil }
        return SCFrameStatus(rawValue: rawStatus)
    }
}
