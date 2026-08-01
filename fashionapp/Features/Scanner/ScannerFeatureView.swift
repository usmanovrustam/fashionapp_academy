import SwiftUI

struct ScannerFeatureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScannerViewModel
    private let isPresentedModally: Bool

    init(container: AppContainer, plannedDate: Date? = nil, isPresentedModally: Bool = true) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(container: container, plannedDate: plannedDate))
        self.isPresentedModally = isPresentedModally
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        AppColors.brand.opacity(0.05),
                        AppColors.accent.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        header
                        photoSection
                        if let result = viewModel.scanResult {
                            metadataSection(result)
                        }
                        detailsSection
                        saveButton
                        Spacer(minLength: AppSpacing.xl)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresentedModally {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCamera) {
                SystemImagePicker(source: .camera) { result in
                    Task {
                        if case .success(let image) = result {
                            await viewModel.handlePickedImage(image)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } else if case .failure(let error) = result,
                                  !(error is CameraCaptureError && (error as? CameraCaptureError) == .cancelled) {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $viewModel.showLibrary) {
                SystemImagePicker(source: .photoLibrary) { result in
                    Task {
                        if case .success(let image) = result {
                            await viewModel.handlePickedImage(image)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Camera Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(NSLocalizedString("Outfit Saved!", comment: ""), isPresented: $viewModel.didSave) {
                Button("OK") {
                    if isPresentedModally { dismiss() }
                }
            } message: {
                Text("Your clothing item was scanned and saved to your wardrobe.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("AI Clothing Scanner")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.primaryGradient)
            Text("Capture a piece — we isolate it and detect type, color, material, season, and style.")
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private var photoSection: some View {
        VStack(spacing: 20) {
            ZStack {
                if let image = viewModel.previewImage ?? viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 280, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.photo, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.photo, style: .continuous)
                                .stroke(AppColors.primaryGradient, lineWidth: 2)
                        )
                        .overlay(alignment: .topTrailing) {
                            Button {
                                viewModel.resetForm()
                            } label: {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, AppColors.brand)
                                    .padding(12)
                            }
                        }
                        .overlay {
                            if viewModel.isProcessing {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    Text("Scanning…")
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(24)
                                .liquidGlass(cornerRadius: AppRadius.photo)
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: AppRadius.photo, style: .continuous)
                        .strokeBorder(
                            AppColors.primaryGradient,
                            style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                        )
                        .frame(width: 280, height: 320)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.photo, style: .continuous)
                                .fill(AppColors.brand.opacity(0.04))
                        )
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 48))
                                    .foregroundStyle(AppColors.primaryGradient)
                                Text(NSLocalizedString("Tap to take photo", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            Task { await viewModel.openCamera() }
                        }
                }
            }

            SylyoGlassContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.openCamera() }
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .sylyoGlassProminent()

                    Button {
                        viewModel.showLibrary = true
                    } label: {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .sylyoGlass()
                }
            }
        }
    }

    private func metadataSection(_ result: ClothingScanResult) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI Detected")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.primaryGradient)
                labeled("Category", result.detectedCategory.displayName)
                if let sub = result.subcategory { labeled("Type", sub) }
                labeled("Material", result.material.displayName)
                labeled("Color", result.dominantColor ?? "—")
                labeled("Season", result.seasons.map(\.displayName).joined(separator: ", "))
                labeled("Style", result.styleTags.prefix(3).map(\.displayName).joined(separator: ", "))
                labeled("Confidence", "\(Int(result.confidence * 100))%")
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(AppTypography.headline)
            TextField(NSLocalizedString("Outfit Name", comment: ""), text: $viewModel.editableName)
                .padding()
                .liquidGlass(cornerRadius: AppRadius.medium)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            Text("Leave blank to keep the AI suggestion.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            HStack {
                if viewModel.isSaving { ProgressView().controlSize(.small) }
                Text(NSLocalizedString("Save Outfit", comment: ""))
            }
            .frame(maxWidth: .infinity)
        }
        .sylyoGlassProminent(
            disabled: viewModel.selectedImage == nil || viewModel.isProcessing || viewModel.isSaving
        )
    }
}
