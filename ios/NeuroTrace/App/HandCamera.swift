import AVFoundation
import SwiftUI
import UIKit
import Vision

// Front camera + Apple Vision hand pose. Reports (time, gap, which hand) per frame and never keeps a frame
final class HandCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let preview = AVCaptureVideoPreviewLayer()
    // The hand is "left" or "right" when Vision can tell, nil when it can't or no hand is found
    var onFrame: @MainActor (Double, Double?, String?) -> Void = { _, _, _ in }
    // Every finger Vision found this frame, and the frame's size, for the hand drawn over the preview
    var onJoints: @MainActor ([[CGPoint?]], CGSize) -> Void = { _, _ in }
    private let output = AVCaptureVideoDataOutput()
    // Frames are handled here. User interactive, so hand tracking gets the time it needs to keep up
    private let queue = DispatchQueue(label: "hand-camera", qos: .userInteractive)
    private let request = VNDetectHumanHandPoseRequest()
    private var rotation: AVCaptureDevice.RotationCoordinator?
    // Watches the iPad turn, so the preview and the frames turn with it
    private var turning: [NSKeyValueObservation] = []

    static func allowed() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    func start() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        request.maximumHandCount = 1
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        if session.canAddInput(input) { session.addInput(input) }
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        // Frames as the camera sees them, not mirrored like the preview, so Vision's left and right are the
        // person's own left and right
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        session.commitConfiguration()
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotation = coordinator
        turning = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview) { [weak self] _, _ in DispatchQueue.main.async { self?.syncRotation() } },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture) { [weak self] _, _ in DispatchQueue.main.async { self?.syncRotation() } },
        ]
        syncRotation()
        queue.async { self.session.startRunning() }
        return true
    }

    func stop() { queue.async { self.session.stopRunning() } }

    // Starts the camera again after stop
    func resume() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }

    // Frames arrive upright, so Vision gets .up and the gap is measured in real pixels
    func syncRotation() {
        guard let rotation else { return }
        preview.connection?.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelPreview
        output.connection(with: .video)?.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelCapture
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        var gap: Double?
        var which: String?
        var fingers: [[CGPoint?]] = []
        var size = CGSize.zero
        if let pixels = CMSampleBufferGetImageBuffer(buffer),
           (try? VNImageRequestHandler(cmSampleBuffer: buffer, orientation: .up).perform([request])) != nil,
           let hand = request.results?.first {
            gap = Self.gap(hand, width: Double(CVPixelBufferGetWidth(pixels)), height: Double(CVPixelBufferGetHeight(pixels)))
            which = hand.chirality == .left ? "left" : hand.chirality == .right ? "right" : nil
            fingers = Self.skeleton(hand)
            size = CGSize(width: CGFloat(CVPixelBufferGetWidth(pixels)), height: CGFloat(CVPixelBufferGetHeight(pixels)))
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onFrame(t, gap, which)
                self.onJoints(fingers, size)
            }
        }
    }

    // Each finger from the wrist out to the tip
    static let fingerJoints: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    // Vision's point for every joint, nil where it isn't sure enough to draw
    static func skeleton(_ hand: VNHumanHandPoseObservation) -> [[CGPoint?]] {
        fingerJoints.map { finger in
            finger.map { joint in
                guard let point = try? hand.recognizedPoint(joint), point.confidence > 0.3 else { return nil }
                return point.location
            }
        }
    }

    // Fingertip distance / wrist-to-middle-knuckle distance, so how close the hand is cancels out
    static func gap(_ hand: VNHumanHandPoseObservation, width: Double, height: Double) -> Double? {
        let joints: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .wrist, .middleMCP]
        let p = joints.compactMap { try? hand.recognizedPoint($0) }.filter { $0.confidence > 0.3 }
        guard p.count == 4 else { return nil }
        func d(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> Double {
            hypot(Double(a.location.x - b.location.x) * width, Double(a.location.y - b.location.y) * height)
        }
        let size = d(p[2], p[3])
        return size > 0 ? d(p[0], p[1]) / size : nil
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: HandCamera

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.setUp(camera)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        var camera: HandCamera?
        // The hand Vision sees, drawn over the picture. A white edge under each line keeps it clear on any background
        private let edge = CAShapeLayer()
        private let bones = CAShapeLayer()
        private let joints = CAShapeLayer()
        private var fingers: [[CGPoint?]] = []
        private var frameSize = CGSize.zero

        func setUp(_ camera: HandCamera) {
            self.camera = camera
            layer.addSublayer(camera.preview)
            for shape in [edge, bones, joints] {
                shape.lineCap = .round
                shape.lineJoin = .round
                layer.addSublayer(shape)
            }
            edge.fillColor = nil
            bones.fillColor = nil
            edge.lineWidth = 7
            bones.lineWidth = 3.5
            joints.lineWidth = 2.5
            camera.onJoints = { [weak self] fingers, size in self?.draw(fingers, size) }
        }

        // Runs on rotation too, so the preview and the frames follow the iPad
        override func layoutSubviews() {
            super.layoutSubviews()
            camera?.preview.frame = bounds
            for shape in [edge, bones, joints] { shape.frame = bounds }
            camera?.syncRotation()
            draw(fingers, frameSize)
        }

        // Vision's points are on the upright frame, measured from the bottom left and not mirrored. The preview is
        // mirrored and fills the box, so each point is flipped and scaled the same way to land on the hand
        func draw(_ fingers: [[CGPoint?]], _ size: CGSize) {
            self.fingers = fingers
            frameSize = size
            let lines = CGMutablePath(), dots = CGMutablePath()
            if size.width > 0 && size.height > 0 {
                let scale = max(bounds.width / size.width, bounds.height / size.height)
                let left = (bounds.width - size.width * scale) / 2, top = (bounds.height - size.height * scale) / 2
                for finger in fingers {
                    var last: CGPoint? = nil
                    for point in finger {
                        guard let point else {
                            last = nil
                            continue
                        }
                        let spot = CGPoint(x: left + (1 - point.x) * size.width * scale, y: top + (1 - point.y) * size.height * scale)
                        if let last {
                            lines.move(to: last)
                            lines.addLine(to: spot)
                        }
                        dots.addEllipse(in: CGRect(x: spot.x - 4.5, y: spot.y - 4.5, width: 9, height: 9))
                        last = spot
                    }
                }
            }
            let accent = Palette.current.accent.ui
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            edge.strokeColor = UIColor.white.withAlphaComponent(0.75).cgColor
            bones.strokeColor = accent.cgColor
            joints.fillColor = UIColor.white.cgColor
            joints.strokeColor = accent.cgColor
            edge.path = lines
            bones.path = lines
            joints.path = dots
            CATransaction.commit()
        }
    }
}
