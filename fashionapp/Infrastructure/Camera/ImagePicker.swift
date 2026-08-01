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

/// Photo library picker (still images only). Camera uses `PhotoCameraView` instead of UIImagePickerController.
struct SystemImagePicker: UIViewControllerRepresentable {
    enum Source {
        case photoLibrary
    }

    let source: Source
    let onComplete: (Result<UIImage, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        picker.mediaTypes = [UTType.image.identifier]
        picker.sourceType = .photoLibrary
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

        private func finish(result: Result<UIImage, Error>) {
            guard !didFinish else { return }
            didFinish = true
            onComplete(result)
        }
    }
}

enum CameraAuthorization {
    static func ensureAuthorized() async -> Result<Void, Error> {
        // Prefer real capture hardware over UIImagePicker availability (which can lie on Simulator).
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        guard !discovery.devices.isEmpty else {
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
