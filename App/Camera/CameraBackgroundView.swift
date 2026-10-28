import AVFoundation
import SwiftUI

/// Full-screen preview of the rear camera, so the phone looks see-through.
struct CameraBackgroundView: UIViewRepresentable {
    let feed: CameraFeed

    func makeUIView(context _: Context) -> CameraPreviewView {
        CameraPreviewView(session: feed.controller.session)
    }

    func updateUIView(_: CameraPreviewView, context _: Context) {}
}

final class CameraPreviewView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        // The app is portrait-only; rotate the sensor's landscape image upright.
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
