import SwiftUI
import UIKit
import AVFoundation

enum CameraCaptureError: LocalizedError, Equatable {
    case denied
    case cancelled
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return NSLocalizedString("Camera access denied. Please enable it in Settings.", comment: "")
        case .cancelled:
            return NSLocalizedString("No image found.", comment: "")
        case .unavailable:
            return NSLocalizedString("Unknown camera permission error.", comment: "")
        }
    }
}

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
        switch source {
        case .camera:
            picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        case .photoLibrary:
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (Result<UIImage, Error>) -> Void

        init(onComplete: @escaping (Result<UIImage, Error>) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.onComplete(.failure(CameraCaptureError.cancelled))
            }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            picker.dismiss(animated: true) {
                if let image {
                    self.onComplete(.success(image))
                } else {
                    self.onComplete(.failure(CameraCaptureError.cancelled))
                }
            }
        }
    }
}

enum CameraAuthorization {
    static func ensureAuthorized() async -> Result<Void, Error> {
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
