// HANDCAMERA.SWIFT RUNS THE FRONT CAMERA AND FINDS THE HAND IN EACH FRAME WITH APPLE VISION
// IT REPORTS THE GAP BETWEEN THUMB AND FINGER FOR EACH FRAME, AND DRAWS THE HAND OVER THE CAMERA PREVIEW

import AVFoundation
import SwiftUI
import UIKit
import Vision

// Runs the front camera and reports the time, the finger gap and which hand for every frame
final class HandCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    // The camera session and the preview layer that shows it
    let session = AVCaptureSession()
    let preview = AVCaptureVideoPreviewLayer()

    // Runs for every frame with the time, the gap, and "left", "right" or nil for the hand
    var onFrame: @MainActor (Double, Double?, String?) -> Void = { _, _, _ in }

    // Runs for every frame with the points of each finger and the frame's size
    var onJoints: @MainActor ([[CGPoint?]], CGSize) -> Void = { _, _ in }

    // Where the camera sends its frames
    private let output = AVCaptureVideoDataOutput()

    // The queue the frames are handled on, at the highest priority
    private let queue = DispatchQueue(label: "hand-camera", qos: .userInteractive)

    // The Vision request that finds the hand
    private let request = VNDetectHumanHandPoseRequest()

    // Tracks which way the iPad is turned
    private var rotation: AVCaptureDevice.RotationCoordinator?

    // Watchers that run when the iPad turns
    private var turning: [NSKeyValueObservation] = []

    // Ask to use the camera and give back whether it was allowed
    static func allowed() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    // Set up and start the camera, and give back false if there is no front camera
    func start() -> Bool {

        // Get the front camera, or stop if there isn't one
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        // Look for one hand at most
        request.maximumHandCount = 1

        // Use 640 by 480 frames, drop late frames, and send every frame to this class on the queue
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        if session.canAddInput(input) { session.addInput(input) }
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        // Turn off mirroring on the frames
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        session.commitConfiguration()

        // Show the camera in the preview, filling the box
        preview.session = session
        preview.videoGravity = .resizeAspectFill

        // Turn the preview and the frames each time the iPad turns
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotation = coordinator
        turning = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview) { [weak self] _, _ in DispatchQueue.main.async { self?.syncRotation() } },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture) { [weak self] _, _ in DispatchQueue.main.async { self?.syncRotation() } },
        ]
        syncRotation()

        // Start the camera on the queue
        queue.async { self.session.startRunning() }
        return true
    }

    // Stop the camera
    func stop() { queue.async { self.session.stopRunning() } }

    // Start the camera again if it isn't running
    func resume() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }

    // Set the preview and the frames to the angles that keep them upright
    func syncRotation() {
        guard let rotation else { return }
        preview.connection?.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelPreview
        output.connection(with: .video)?.videoRotationAngle = rotation.videoRotationAngleForHorizonLevelCapture
    }

    // Runs for every camera frame
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        // The frame's time in seconds, and empty results to fill in
        let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        var gap: Double?
        var which: String?
        var fingers: [[CGPoint?]] = []
        var size = CGSize.zero

        // Run Vision on the upright frame, and if it finds a hand, get the gap, which hand, the finger points and the frame size
        if let pixels = CMSampleBufferGetImageBuffer(buffer),
           (try? VNImageRequestHandler(cmSampleBuffer: buffer, orientation: .up).perform([request])) != nil,
           let hand = request.results?.first {
            gap = Self.gap(hand, width: Double(CVPixelBufferGetWidth(pixels)), height: Double(CVPixelBufferGetHeight(pixels)))
            which = hand.chirality == .left ? "left" : hand.chirality == .right ? "right" : nil
            fingers = Self.skeleton(hand)
            size = CGSize(width: CGFloat(CVPixelBufferGetWidth(pixels)), height: CGFloat(CVPixelBufferGetHeight(pixels)))
        }

        // Hand the results to onFrame and onJoints on the main thread
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onFrame(t, gap, which)
                self.onJoints(fingers, size)
            }
        }
    }

    // The joints of each finger from the wrist out to the tip
    static let fingerJoints: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    // Vision's point for every joint, or nil where its confidence is 0.3 or less
    static func skeleton(_ hand: VNHumanHandPoseObservation) -> [[CGPoint?]] {
        fingerJoints.map { finger in
            finger.map { joint in
                guard let point = try? hand.recognizedPoint(joint), point.confidence > 0.3 else { return nil }
                return point.location
            }
        }
    }

    // The distance between the thumb tip and index tip, divided by the distance from the wrist to the middle knuckle
    static func gap(_ hand: VNHumanHandPoseObservation, width: Double, height: Double) -> Double? {

        // Get the four points, and stop unless all four have a confidence above 0.3
        let joints: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .wrist, .middleMCP]
        let p = joints.compactMap { try? hand.recognizedPoint($0) }.filter { $0.confidence > 0.3 }
        guard p.count == 4 else { return nil }

        // The distance between two points in pixels
        func d(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> Double {
            hypot(Double(a.location.x - b.location.x) * width, Double(a.location.y - b.location.y) * height)
        }

        // Divide the fingertip distance by the hand size, or give back nil if the hand size is 0
        let size = d(p[2], p[3])
        return size > 0 ? d(p[0], p[1]) / size : nil
    }
}


// Puts the camera preview and the drawn hand inside a SwiftUI screen
struct CameraPreview: UIViewRepresentable {

    // The camera to show
    let camera: HandCamera

    // Make the preview view and connect it to the camera
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.setUp(camera)
        return view
    }

    // Nothing changes on updates
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    // The view that shows the camera and draws the hand over it
    final class PreviewView: UIView {

        // The camera it shows
        var camera: HandCamera?

        // The layers for the white edge under the lines, the finger lines, and the joint dots
        private let edge = CAShapeLayer()
        private let bones = CAShapeLayer()
        private let joints = CAShapeLayer()

        // The last finger points and frame size, kept to redraw them
        private var fingers: [[CGPoint?]] = []
        private var frameSize = CGSize.zero

        // Add the camera preview and the hand layers, and draw the hand each frame
        func setUp(_ camera: HandCamera) {
            self.camera = camera
            layer.addSublayer(camera.preview)

            // Round ends and corners on every hand layer
            for shape in [edge, bones, joints] {
                shape.lineCap = .round
                shape.lineJoin = .round
                layer.addSublayer(shape)
            }

            // No fill on the lines, and set the line widths
            edge.fillColor = nil
            bones.fillColor = nil
            edge.lineWidth = 7
            bones.lineWidth = 3.5
            joints.lineWidth = 2.5

            // Draw the hand whenever the camera sends new points
            camera.onJoints = { [weak self] fingers, size in self?.draw(fingers, size) }
        }

        // Make the preview and the hand layers fill the view, turn them, and redraw the hand
        override func layoutSubviews() {
            super.layoutSubviews()
            camera?.preview.frame = bounds
            for shape in [edge, bones, joints] { shape.frame = bounds }
            camera?.syncRotation()
            draw(fingers, frameSize)
        }

        // Draw the hand's lines and dots over the preview
        func draw(_ fingers: [[CGPoint?]], _ size: CGSize) {

            // Keep the points and size, and start empty paths for the lines and dots
            self.fingers = fingers
            frameSize = size
            let lines = CGMutablePath(), dots = CGMutablePath()
            if size.width > 0 && size.height > 0 {

                // Scale the frame to fill the view and center it
                let scale = max(bounds.width / size.width, bounds.height / size.height)
                let left = (bounds.width - size.width * scale) / 2, top = (bounds.height - size.height * scale) / 2
                for finger in fingers {
                    var last: CGPoint? = nil
                    for point in finger {

                        // Break the line where a joint is missing
                        guard let point else {
                            last = nil
                            continue
                        }

                        // Flip the point side to side and top to bottom, and scale it onto the view
                        let spot = CGPoint(x: left + (1 - point.x) * size.width * scale, y: top + (1 - point.y) * size.height * scale)

                        // Draw a line from the last joint, and a dot on this one
                        if let last {
                            lines.move(to: last)
                            lines.addLine(to: spot)
                        }
                        dots.addEllipse(in: CGRect(x: spot.x - 4.5, y: spot.y - 4.5, width: 9, height: 9))
                        last = spot
                    }
                }
            }

            // Set the colors and paths with no animation
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
