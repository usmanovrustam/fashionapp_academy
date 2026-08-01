import SwiftUI
import AVFoundation
import UIKit

/// Photo-only camera using a single wide-angle device.
/// Avoids `UIImagePickerController`, which probes Portrait / BackDual and logs FigCapture errors.
struct PhotoCameraView: View {
    let onComplete: (Result<UIImage, Error>) -> Void

    @StateObject private var model = PhotoCaptureModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.isSessionRunning {
                CameraPreview(session: model.session)
                    .ignoresSafeArea()
            } else if let message = model.setupError {
                VStack(spacing: 16) {
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(NSLocalizedString("Close", comment: "")) {
                        onComplete(.failure(CameraCaptureError.unavailable))
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
                        onComplete(.failure(CameraCaptureError.cancelled))
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
                .disabled(!model.isSessionRunning || model.isCapturing)
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
        .onChange(of: model.capturedImage) { _, image in
            guard let image else { return }
            onComplete(.success(image))
        }
        .onChange(of: model.captureError) { _, error in
            guard let error else { return }
            onComplete(.failure(error))
        }
    }
}

@MainActor
final class PhotoCaptureModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isSessionRunning = false
    @Published var isCapturing = false
    @Published var setupError: String?
    @Published var capturedImage: UIImage?
    @Published var captureError: Error?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "sylyo.photo.camera.session")
    private var configured = false

    func start() async {
        let auth = await CameraAuthorization.ensureAuthorized()
        if case .failure(let error) = auth {
            setupError = error.localizedDescription
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSessionIfNeeded()
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                    if !self.session.isRunning {
                        self.setupError = CameraCaptureError.unavailable.localizedDescription
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.setupError = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        // Still JPEG only — never enable depth / Portrait delivery on the capture request.
        if let device = session.inputs
            .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
            .first,
           device.hasFlash,
           device.isFlashAvailable {
            settings.flashMode = .auto
        } else {
            settings.flashMode = .off
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Single wide-angle back camera — never virtual dual / Portrait devices.
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
}

extension PhotoCaptureModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.isCapturing = false
                self.captureError = error
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.isCapturing = false
                self.captureError = CameraCaptureError.unavailable
            }
            return
        }

        Task { @MainActor in
            self.isCapturing = false
            self.capturedImage = image
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
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
