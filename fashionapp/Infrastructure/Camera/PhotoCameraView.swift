import SwiftUI
@preconcurrency import AVFoundation
import UIKit

/// Photo-only camera using a single wide-angle device.
/// Avoids `UIImagePickerController`, which probes Portrait / BackDual and logs FigCapture errors.
struct PhotoCameraView: View {
    let onComplete: (Result<UIImage, Error>) -> Void

    @StateObject private var model = PhotoCaptureModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.isSessionRunning {
                CameraPreview(session: model.previewSession)
                    .ignoresSafeArea()
            } else if let message = model.setupError {
                VStack(spacing: 16) {
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(NSLocalizedString("Close", comment: "")) {
                        model.finish(.failure(CameraCaptureError.unavailable))
                    }
                    .sylyoGlassProminent()
                    .padding(.horizontal, 40)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Button(NSLocalizedString("Cancel", comment: "")) {
                        model.finish(.failure(CameraCaptureError.cancelled))
                    }
                    .foregroundStyle(.white)
                    .padding()
                    Spacer()
                }
                Spacer()
                Button {
                    model.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(.white)
                            .frame(width: 62, height: 62)
                    }
                }
                .disabled(!model.isSessionRunning || model.isCapturing || model.hasFinished)
                .padding(.bottom, 36)
                .accessibilityLabel(NSLocalizedString("Take photo", comment: ""))
            }
        }
        .task {
            await model.start()
        }
        .onDisappear {
            model.stop()
        }
        // Watch a UUID token — `Result<UIImage, Error>` is not Equatable.
        .onChange(of: model.finishToken) { _, token in
            guard token != nil, let result = model.finishedResult else { return }
            onComplete(result)
        }
    }
}

/// Owns AVCapture objects off the main actor. UI state stays on `PhotoCaptureModel`.
private final class CameraSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let queue = DispatchQueue(label: "sylyo.photo.camera.session")
    private var configured = false

    func configureIfNeeded() throws {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw CameraCaptureError.unavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraCaptureError.unavailable
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CameraCaptureError.unavailable
        }
        session.addOutput(photoOutput)

        if let connection = photoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = false
        }
        if photoOutput.isPortraitEffectsMatteDeliverySupported {
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = false
        }
        photoOutput.maxPhotoQualityPrioritization = .balanced

        session.commitConfiguration()
        configured = true
    }

    func startRunning() {
        session.startRunning()
    }

    func stopRunning() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    var isRunning: Bool { session.isRunning }

    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        queue.async { [photoOutput] in
            let settings = AVCapturePhotoSettings()
            if let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first,
               device.hasFlash,
               device.isFlashAvailable {
                settings.flashMode = .auto
            } else {
                settings.flashMode = .off
            }
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

@MainActor
final class PhotoCaptureModel: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var isCapturing = false
    @Published var setupError: String?
    @Published var hasFinished = false
    /// Bumps when a terminal result is ready (`finishedResult`). Equatable for `onChange`.
    @Published private(set) var finishToken: UUID?
    private(set) var finishedResult: Result<UIImage, Error>?

    private let sessionBox = CameraSessionBox()

    /// Preview layer binds to this session (safe to read from main).
    var previewSession: AVCaptureSession { sessionBox.session }

    func finish(_ result: Result<UIImage, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        isCapturing = false
        finishedResult = result
        finishToken = UUID()
        stop()
    }

    func start() async {
        let auth = await CameraAuthorization.ensureAuthorized()
        if case .failure(let error) = auth {
            setupError = error.localizedDescription
            return
        }

        let box = sessionBox
        box.queue.async { [weak self] in
            do {
                try box.configureIfNeeded()
                box.startRunning()
                let running = box.isRunning
                Task { @MainActor in
                    guard let self else { return }
                    self.isSessionRunning = running
                    if !running {
                        self.setupError = CameraCaptureError.unavailable.localizedDescription
                    }
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    self?.setupError = message
                }
            }
        }
    }

    func stop() {
        let box = sessionBox
        box.queue.async { [weak self] in
            box.stopRunning()
            Task { @MainActor in
                self?.isSessionRunning = false
            }
        }
    }

    func capturePhoto() {
        guard !isCapturing, !hasFinished else { return }
        isCapturing = true
        sessionBox.capturePhoto(delegate: self)
    }
}

extension PhotoCaptureModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.finish(.failure(error))
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.finish(.failure(CameraCaptureError.unavailable))
            }
            return
        }

        // Bake EXIF so downstream resize / Core ML never sees a sideways buffer.
        let upright = ImageProcessing.orientedUp(image)
        Task { @MainActor in
            self.finish(.success(upright))
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // layerClass guarantees this cast.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
