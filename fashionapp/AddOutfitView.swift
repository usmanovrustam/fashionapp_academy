import SwiftUI
import PhotosUI
import CloudKit
import AVFoundation
import CoreML
import Vision

struct AddOutfitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = OutfitCloudKitManager.shared
    @State private var outfitName = ""
    @State private var selectedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var characterCount = 0
    @State private var isProcessing = false
    @FocusState private var isNameFieldFocused: Bool
    
    let selectedDate: Date?
    
    private let maxNameLength = 30
    private let u2netModel = try? u2net(configuration: MLModelConfiguration())
    
    init(selectedDate: Date? = nil) {
        self.selectedDate = selectedDate
    }

    var body: some View {
        NavigationView {
                        ZStack {
                // Modern gradient background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.purple.opacity(0.05),
                        Color.pink.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern header
                                        VStack(spacing: 8) {
                            Text("Create New Outfit")
                                .font(.title.bold())
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.purple, Color.pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("Capture your style and add it to your collection")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Modern photo capture section
                        modernPhotoSection()
                        
                        // Modern outfit details section
                        modernDetailsSection()
                        
                        // Modern save button
                        modernSaveButton()
                        
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCamera) {
                MemoizedImagePicker(sourceType: .camera) { result in
                    switch result {
                    case .success(let img):
                        selectedImage = img
                        // Process image with U2Net
                        processImageWithU2Net(img)
                        // Add haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert(NSLocalizedString("Camera Error", comment: ""), isPresented: .constant(errorMessage != "")) {
                Button(NSLocalizedString("OK", comment: "")) { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
            .alert(NSLocalizedString("Error Saving Outfit", comment: ""), isPresented: .constant(showError)) {
                Button(NSLocalizedString("OK", comment: "")) { showError = false }
            } message: {
                Text(errorMessage)
            }
            .alert(NSLocalizedString("Outfit Saved!", comment: ""), isPresented: $showSuccess) {
                Button(NSLocalizedString("OK", comment: "")) {
                    // Reset form with animation
                    withAnimation(.spring()) {
                        outfitName = ""
                        selectedImage = nil
                        processedImage = nil
                    }
                }
            } message: {
                Text(NSLocalizedString("Your outfit was saved to iCloud.", comment: ""))
            }
            .onAppear {
                manager.checkCloudKitStatus()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    @ViewBuilder
    private func modernPhotoSection() -> some View {
        VStack(spacing: 20) {
            Text("📸 Outfit Photo")
                .font(.headline.bold())
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ZStack {
                if let selectedImage = selectedImage {
                    // Modern image display with overlay controls
                    ZStack {
                        Image(uiImage: processedImage ?? selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 280, height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                        
                        if isProcessing {
                            // Processing overlay
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 280, height: 320)
                            
                            VStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("Processing image...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Floating retake button
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: { checkCameraPermission() }) {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 48, height: 48)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                }
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                .disabled(isProcessing)
                            }
                            Spacer()
                        }
                        .padding(20)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                } else {
                    // Modern camera placeholder
                    Button(action: { checkCameraPermission() }) {
                        VStack(spacing: 20) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.purple.opacity(0.1),
                                                Color.pink.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 280, height: 320)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                style: StrokeStyle(lineWidth: 2, dash: [10])
                                            )
                                    )
                                
                                VStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.purple.opacity(0.2))
                                            .frame(width: 80, height: 80)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 32, weight: .medium))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color.purple, Color.pink],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                    
                                    VStack(spacing: 4) {
                                        Text("Tap to Capture")
                                            .font(.headline.bold())
                                            .foregroundColor(.primary)
                                        
                                        Text("Take a photo of your outfit")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, 4)
    }
    
    @ViewBuilder
    private func modernDetailsSection() -> some View {
        VStack(spacing: 20) {
            Text("✏️ Outfit Details")
                .font(.headline.bold())
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.purple.opacity(isNameFieldFocused ? 0.5 : 0.1), lineWidth: 2)
                        )
                    
                    TextField("Enter outfit name...", text: $outfitName)
                        .focused($isNameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(.body)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .accessibilityLabel(NSLocalizedString("Outfit Name", comment: ""))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isNameFieldFocused)
                
                // Character counter
                HStack {
                    Spacer()
                    Text("\(outfitName.count)/\(maxNameLength)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func modernSaveButton() -> some View {
        Button(action: saveOutfit) {
            HStack(spacing: 12) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                
                Text(isSaving ? "Saving..." : "Save to Wardrobe")
                    .font(.headline.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Group {
                    if outfitName.isEmpty || selectedImage == nil || isSaving {
                        Color.gray.opacity(0.4)
                    } else {
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(
                color: (outfitName.isEmpty || selectedImage == nil || isSaving) ? .clear : Color.purple.opacity(0.4),
                radius: 12,
                x: 0,
                y: 6
            )
            .scaleEffect(isSaving ? 0.95 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSaving)
        }
        .disabled(outfitName.isEmpty || selectedImage == nil || isSaving)
        .buttonStyle(ScaleButtonStyle())
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        errorMessage = NSLocalizedString("Camera access denied. Please enable it in Settings.", comment: "")
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = NSLocalizedString("Camera access denied. Please enable it in Settings.", comment: "")
        @unknown default:
            errorMessage = NSLocalizedString("Unknown camera permission error.", comment: "")
        }
    }

    private func processImageWithU2Net(_ image: UIImage) {
        isProcessing = true
        
        guard let model = u2netModel else {
            errorMessage = "Failed to load U2Net model"
            isProcessing = false
            return
        }
        
        // Resize image to model's expected size
        let targetSize = CGSize(width: 320, height: 320)
        guard let resizedImage = image.resize(to: targetSize) else {
            errorMessage = "Failed to resize image"
            isProcessing = false
            return
        }
        
        // Convert UIImage to CVPixelBuffer
        guard let pixelBuffer = resizedImage.toCVPixelBuffer() else {
            errorMessage = "Failed to convert image to pixel buffer"
            isProcessing = false
            return
        }
        
        do {
            // Convert MLModel to VNCoreMLModel
            let vnModel = try VNCoreMLModel(for: model.model)
            
            // Create a Vision request
            let request = VNCoreMLRequest(model: vnModel)
            request.imageCropAndScaleOption = .scaleFit
            
            // Create a handler
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            // Perform the request
            try handler.perform([request])
            
            // Get the results
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let firstResult = results.first,
                  let maskFeature = firstResult.featureValue.multiArrayValue else {
                errorMessage = "Failed to get mask from model output"
                isProcessing = false
                return
            }
            
            // Convert mask to UIImage
            let maskImage = maskFeature.toUIImage()
            
            // Apply mask to original image
            if let processed = resizedImage.applyMask(maskImage) {
                processedImage = processed
            } else {
                errorMessage = "Failed to apply mask to image"
            }
        } catch {
            errorMessage = "Failed to process image: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }

    private func saveOutfit() {
        guard let imageToSave = processedImage ?? selectedImage, !outfitName.isEmpty else { return }
        
        isSaving = true
        showError = false
        isNameFieldFocused = false
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        print("Attempting to save outfit: \(outfitName)")
        
        manager.saveOutfit(name: outfitName, image: imageToSave, plannedDate: selectedDate) { result in
            DispatchQueue.main.async {
                isSaving = false
                
                switch result {
                case .success(let record):
                    print("Successfully saved outfit with record ID: \(record.recordID)")
                    showSuccess = true
                    
                    // Success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                case .failure(let error):
                    print("Failed to save outfit: \(error.localizedDescription)")
                    showError = true
                    errorMessage = error.localizedDescription
                    
                    // Error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                }
            }
        }
    }
}

// Custom button style for modern interactions
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
                parent.completion(.failure(NSError(domain: "ImagePicker", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("No image found.", comment: "")])))
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - UIImage Extensions
extension UIImage {
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func toCVPixelBuffer() -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                    kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       Int(size.width),
                                       Int(size.height),
                                       kCVPixelFormatType_32ARGB,
                                       attrs,
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                              width: Int(size.width),
                              height: Int(size.height),
                              bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.draw(cgImage!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
    
    func applyMask(_ maskImage: UIImage) -> UIImage? {
        guard let maskCGImage = maskImage.cgImage,
              let originalCGImage = self.cgImage else {
            return nil
        }
        
        let width = originalCGImage.width
        let height = originalCGImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: maskCGImage)
        context.draw(originalCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let outputImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: outputImage)
    }
}

// MARK: - MLMultiArray Extension
extension MLMultiArray {
    func toUIImage() -> UIImage {
        let height = self.shape[1].intValue
        let width = self.shape[2].intValue
        
        var bytes = [UInt8](repeating: 0, count: height * width * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * width + x
                let value = self[offset].floatValue
                let alpha = UInt8(value * 255)
                
                bytes[offset * 4 + 0] = 0
                bytes[offset * 4 + 1] = 0
                bytes[offset * 4 + 2] = 0
                bytes[offset * 4 + 3] = alpha
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let context = CGContext(data: &bytes,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: width * 4,
                              space: colorSpace,
                              bitmapInfo: bitmapInfo.rawValue)
        
        let cgImage = context?.makeImage()
        return UIImage(cgImage: cgImage!)
    }
} 
