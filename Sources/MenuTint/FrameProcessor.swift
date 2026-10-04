import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Receives menu bar frames from ScreenCaptureKit and renders the tinted overlay
/// on its own queue.
final class FrameProcessor: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "MenuTint.frames", qos: .userInteractive)

    private let renderer: TintRenderer
    private let onFrame: @Sendable (CGImage) -> Void
    private let onStop: @Sendable (Error) -> Void

    /// Last captured frame, so style changes show up even while the menu bar is static
    /// (ScreenCaptureKit only delivers frames when something changes).
    private var lastFrame: CIImage?

    init(
        maskCube: Data,
        fill: TintRenderer.Fill,
        onFrame: @escaping @Sendable (CGImage) -> Void,
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
            if let frame = self.lastFrame {
                self.draw(frame)
            }
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              Self.frameStatus(of: sampleBuffer) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        lastFrame = frame
        draw(frame)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("MenuTint: capture stopped: \(error.localizedDescription)")
        onStop(error)
    }

    // MARK: Private

    private func draw(_ frame: CIImage) {
        if let image = renderer.render(frame) {
            onFrame(image)
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
