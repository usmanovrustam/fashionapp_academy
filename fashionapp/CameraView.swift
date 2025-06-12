import SwiftUI
import AVFoundation

struct CameraView: View {
    @Environment(\.presentationMode) private var presentationMode
    let onPhoto: (UIImage?) -> Void
    @StateObject private var camera = CameraModel()

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        camera.takePhoto()
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(Circle().stroke(Color.gray, lineWidth: 2))
                    }
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            if let error = camera.error {
                Color.black.opacity(0.6)
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    Text(error.localizedDescription)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
                .padding()
            }
        }
        .onAppear { camera.startSession() }
        .onDisappear { camera.stopSession() }
        .onChange(of: camera.capturedImage) {
            
            if let image = camera.capturedImage {
                onPhoto(image)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedImage: UIImage?
    @Published var error: Error?
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var isSessionConfigured = false

    func startSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
            session.startRunning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configureSession()
                        self.session.startRunning()
                    } else {
                        self.error = NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied."])
                    }
                }
            }
        case .denied, .restricted:
            error = NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied. Please enable it in Settings."])
        @unknown default:
            error = NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown camera permission error."])
        }
    }

    func stopSession() {
        session.stopRunning()
    }

    private func configureSession() {
        guard !isSessionConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            error = NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "No camera available."])
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        isSessionConfigured = true
    }

    func takePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.error = error }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.error = NSError(domain: "Camera", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to capture photo."])
            }
            return
        }
        DispatchQueue.main.async { self.capturedImage = image }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
} 
