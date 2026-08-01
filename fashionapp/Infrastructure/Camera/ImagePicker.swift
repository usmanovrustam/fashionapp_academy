import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

enum CameraCaptureError: LocalizedError, Equatable {
    case denied
    case cancelled
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return NSLocalizedString(
                "Camera access is turned off. You can enable it in Settings to photograph clothing.",
                comment: "Camera permission denied"
            )
        case .cancelled:
            return NSLocalizedString("No photo selected.", comment: "Picker cancelled")
        case .unavailable:
            return NSLocalizedString(
                "Camera isn’t available on this device. Choose a photo from your library instead.",
                comment: "Camera unavailable"
            )
        }
    }
}

/// Camera capture using photo mode only (avoids Portrait / dual-camera session errors).
struct SystemImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onComplete: (Result<UIImage, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen

        // Still images only — reduces Portrait / dual-camera (BackDual) session probes.
        picker.mediaTypes = [UTType.image.identifier]

        switch source {
        case .camera:
            // Caller should gate with `CameraAuthorization`; still photo only (no Portrait / dual-cam).
            picker.sourceType = .camera
            if UIImagePickerController.isCameraDeviceAvailable(.rear) {
                picker.cameraDevice = .rear
            }
            picker.cameraCaptureMode = .photo
            picker.showsCameraControls = true
            picker.cameraFlashMode = .auto
        case .photoLibrary:
            picker.sourceType = .photoLibrary
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (Result<UIImage, Error>) -> Void
        private var didFinish = false

        init(onComplete: @escaping (Result<UIImage, Error>) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(result: .failure(CameraCaptureError.cancelled))
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image {
                finish(result: .success(image))
            } else {
                finish(result: .failure(CameraCaptureError.cancelled))
            }
        }

        /// Parent SwiftUI presentation (`fullScreenCover` / `sheet`) owns dismiss.
        private func finish(result: Result<UIImage, Error>) {
            guard !didFinish else { return }
            didFinish = true
            onComplete(result)
        }
    }
}

enum CameraAuthorization {
    static func ensureAuthorized() async -> Result<Void, Error> {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .failure(CameraCaptureError.unavailable)
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .success(())
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .success(()) : .failure(CameraCaptureError.denied)
        case .denied, .restricted:
            return .failure(CameraCaptureError.denied)
        @unknown default:
            return .failure(CameraCaptureError.unavailable)
        }
    }
}
