import SwiftUI
import PhotosUI
import CloudKit
import AVFoundation

struct AddOutfitView: View {
    @State private var outfitName = ""
    @State private var image: UIImage? = nil
    @State private var showCamera = false
    @State private var cameraError: Error? = nil
    @FocusState private var nameFieldFocused: Bool
    @State private var isSaving = false
    @State private var saveError: Error? = nil
    @State private var showSuccess = false
    @State private var isCheckingPermission = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Outfit Details", comment: ""))) {
                    TextField(NSLocalizedString("Outfit Name", comment: ""), text: $outfitName)
                        .focused($nameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .accessibilityLabel(NSLocalizedString("Outfit Name", comment: ""))
                }
                Section(header: Text(NSLocalizedString("Photo", comment: ""))) {
                    HStack {
                        Spacer()
                        ZStack {
                            if let image = image {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .shadow(radius: 8)
                                    .onTapGesture { checkCameraPermission() }
                                    .accessibilityLabel(NSLocalizedString("Outfit photo. Tap to retake.", comment: ""))
                            } else {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 160, height: 160)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "camera")
                                                .font(.system(size: 40, weight: .medium))
                                                .foregroundColor(.accentColor)
                                            Text(NSLocalizedString("Tap to take photo", comment: ""))
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    )
                                    .onTapGesture { checkCameraPermission() }
                                    .accessibilityLabel(NSLocalizedString("Tap to take outfit photo", comment: ""))
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    Button(action: saveOutfit) {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(NSLocalizedString("Save Outfit", comment: ""), systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(outfitName.isEmpty || image == nil || isSaving)
                    .accessibilityLabel(NSLocalizedString("Save Outfit", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("Add Outfit", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCamera) {
                MemoizedImagePicker(sourceType: .camera) { result in
                    switch result {
                    case .success(let img):
                        image = img
                    case .failure(let error):
                        cameraError = error
                    }
                }
            }
            .alert(NSLocalizedString("Camera Error", comment: ""), isPresented: .constant(cameraError != nil)) {
                Button(NSLocalizedString("OK", comment: "")) { cameraError = nil }
            } message: {
                Text(cameraError?.localizedDescription ?? NSLocalizedString("Unknown error", comment: ""))
            }
            .alert(NSLocalizedString("Error Saving Outfit", comment: ""), isPresented: .constant(saveError != nil)) {
                Button(NSLocalizedString("OK", comment: "")) { saveError = nil }
            } message: {
                Text(saveError?.localizedDescription ?? NSLocalizedString("Unknown error", comment: ""))
            }
            .alert(NSLocalizedString("Outfit Saved!", comment: ""), isPresented: $showSuccess) {
                Button(NSLocalizedString("OK", comment: "")) {
                    outfitName = ""
                    image = nil
                }
            } message: {
                Text(NSLocalizedString("Your outfit was saved to iCloud.", comment: ""))
            }
        }
    }

    private func checkCameraPermission() {
        isCheckingPermission = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        cameraError = NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied."])
                    }
                }
            }
        case .denied, .restricted:
            cameraError = NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied. Please enable it in Settings."])
        @unknown default:
            cameraError = NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown camera permission error."])
        }
        isCheckingPermission = false
    }

    private func saveOutfit() {
        guard let image = image, !outfitName.isEmpty else { return }
        isSaving = true
        saveError = nil
        nameFieldFocused = false
        let record = CKRecord(recordType: "Outfit")
        record["name"] = outfitName
        DispatchQueue.global(qos: .userInitiated).async {
            // Temporarily comment out image saving for debugging
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                do {
                    try imageData.write(to: tempURL)
                    let asset = CKAsset(fileURL: tempURL)
                    record["image"] = asset
                } catch {
                    DispatchQueue.main.async {
                        isSaving = false
                        saveError = error
                        print("Image file write error:", error)
                    }
                    return
                }
            }
            CKContainer.default().privateCloudDatabase.save(record) { record, error in
                DispatchQueue.main.async {
                    isSaving = false
                    if let error = error {
                        print("CloudKit Save Error:", error)
                        saveError = error
                    } else {
                        print("CloudKit Save Success", record)
                        showSuccess = true
                    }
                }
            }
        }
    }
}

struct MemoizedImagePicker: UIViewControllerRepresentable {
    enum PickerResult {
        case success(UIImage)
        case failure(Error)
    }
    var sourceType: UIImagePickerController.SourceType
    var completion: (PickerResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MemoizedImagePicker
        init(_ parent: MemoizedImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.completion(.success(image))
            } else {
                parent.completion(.failure(NSError(domain: "ImagePicker", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image found."])))
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
} 
