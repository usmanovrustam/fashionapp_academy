import SwiftUI

struct ScannerFeatureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: ScannerViewModel
    private let isPresentedModally: Bool

    init(container: AppContainer, plannedDate: Date? = nil, isPresentedModally: Bool = true) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(container: container, plannedDate: plannedDate))
        self.isPresentedModally = isPresentedModally
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    header
                    photoSection
                    if viewModel.scanResult != nil {
                        reviewSection
                    }
                    saveButton
                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadProfileGender() }
            .toolbar {
                if isPresentedModally {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                    }
                }
            }
            // Custom AVFoundation photo camera — no UIImagePicker Portrait / BackDual probing.
            .fullScreenCover(isPresented: $viewModel.showCamera) {
                PhotoCameraView { result in
                    viewModel.showCamera = false
                    Task {
                        if case .success(let image) = result {
                            await viewModel.handlePickedImage(image)
                            if !reduceMotion {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
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
                    viewModel.showLibrary = false
                    Task {
                        if case .success(let image) = result {
                            await viewModel.handlePickedImage(image)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .alert(NSLocalizedString("Camera", comment: ""), isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                NSLocalizedString("No outfit found", comment: "No clothing detected title"),
                isPresented: $viewModel.showNoOutfitAlert
            ) {
                Button(NSLocalizedString("Take photo", comment: "")) {
                    viewModel.clearFailedScan()
                    Task { await viewModel.openCamera() }
                }
                Button(NSLocalizedString("Choose from library", comment: "")) {
                    viewModel.clearFailedScan()
                    viewModel.showLibrary = true
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                    viewModel.clearFailedScan()
                }
            } message: {
                Text(
                    NSLocalizedString(
                        "There is no outfit in this photo. Take another photo of a clothing item.",
                        comment: "No clothing detected message"
                    )
                )
            }
            .alert(NSLocalizedString("Saved", comment: ""), isPresented: $viewModel.didSave) {
                Button(NSLocalizedString("OK", comment: "")) {
                    if isPresentedModally { dismiss() }
                }
            } message: {
                Text(NSLocalizedString("Your item was added to your wardrobe.", comment: ""))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("Add clothing", comment: ""))
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(NSLocalizedString("Take a photo or choose one from your library. Nook finds the garment, crops it to a centered square, and suggests details for you to review.", comment: ""))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
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
                        .accessibilityLabel(NSLocalizedString("Selected clothing photo", comment: ""))
                        .overlay(alignment: .topTrailing) {
                            if !viewModel.isProcessing {
                                Button {
                                    viewModel.resetForm()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, AppColors.brand)
                                        .padding(12)
                                }
                                .accessibilityLabel(NSLocalizedString("Retake or choose another photo", comment: ""))
                            }
                        }
                        .overlay {
                            if viewModel.isProcessing {
                                MLProcessOverlay(
                                    stage: viewModel.pipelineStage,
                                    fraction: viewModel.pipelineFraction,
                                    detail: viewModel.pipelineDetail,
                                    stagePreview: viewModel.stagePreview,
                                    reduceMotion: reduceMotion
                                )
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.photo, style: .continuous))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(viewModel.pipelineStage?.displayName
                                    ?? NSLocalizedString("Analyzing outfit", comment: ""))
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
                                    .font(.largeTitle)
                                    .foregroundStyle(AppColors.primaryGradient)
                                    .nookDecorativeSymbol()
                                Text(NSLocalizedString("Tap to take photo", comment: ""))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(NSLocalizedString("Add a clothing photo", comment: ""))
                        .accessibilityAddTraits(.isButton)
                        .onTapGesture {
                            Task { await viewModel.openCamera() }
                        }
                }
            }

            NookGlassContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.openCamera() }
                    } label: {
                        Label(NSLocalizedString("Camera", comment: ""), systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .nookGlassProminent()
                    .disabled(viewModel.isProcessing)

                    Button {
                        viewModel.showLibrary = true
                    } label: {
                        Label(NSLocalizedString("Library", comment: ""), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .nookGlass()
                    .disabled(viewModel.isProcessing)
                }
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Review details", comment: ""))
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(NSLocalizedString("Check every suggested value before saving. Nothing is added until you confirm.", comment: ""))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    reviewField(NSLocalizedString("Name", comment: "")) {
                        TextField(NSLocalizedString("Item name", comment: ""), text: $viewModel.draftName)
                            .textInputAutocapitalization(.words)
                    }

                    reviewPicker(NSLocalizedString("Category", comment: ""), selection: $viewModel.draftCategory) {
                        ForEach(viewModel.selectableCategories) { category in
                            Text(category.displayName).tag(category)
                        }
                    }

                    reviewField(NSLocalizedString("Type", comment: "")) {
                        TextField(NSLocalizedString("e.g. T-Shirt, Midi Dress", comment: ""), text: $viewModel.draftType)
                            .textInputAutocapitalization(.words)
                    }

                    reviewPicker(NSLocalizedString("Material", comment: ""), selection: $viewModel.draftMaterial) {
                        ForEach(Material.allCases, id: \.self) { material in
                            Text(material.displayName).tag(material)
                        }
                    }

                    reviewField(NSLocalizedString("Color", comment: "")) {
                        TextField(NSLocalizedString("e.g. Navy", comment: ""), text: $viewModel.draftColor)
                            .textInputAutocapitalization(.words)
                    }

                    reviewPicker(NSLocalizedString("Season", comment: ""), selection: $viewModel.draftSeason) {
                        ForEach(Season.allCases, id: \.self) { season in
                            Text(season.displayName).tag(season)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("Formality", comment: ""))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Text(formalityLabel(viewModel.draftFormality))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        Slider(value: $viewModel.draftFormality, in: 0...1, step: 0.05)
                            .tint(AppColors.accent)
                            .accessibilityLabel(NSLocalizedString("Formality", comment: ""))
                    }

                    if let confidence = viewModel.scanResult?.confidence {
                        HStack {
                            Text(NSLocalizedString("Match score", comment: ""))
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Text(String(format: NSLocalizedString("%d%%", comment: "Percentage value"), Int(confidence * 100)))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func reviewField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: AppRadius.medium)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    private func reviewPicker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Picker(title, selection: selection, content: content)
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlass(cornerRadius: AppRadius.medium)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    private func formalityLabel(_ value: Double) -> String {
        switch value {
        case ..<0.25: return NSLocalizedString("Casual", comment: "Formality")
        case ..<0.5: return NSLocalizedString("Relaxed", comment: "Formality")
        case ..<0.75: return NSLocalizedString("Smart", comment: "Formality")
        default: return NSLocalizedString("Formal", comment: "Formality")
        }
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            HStack {
                if viewModel.isSaving { ProgressView().controlSize(.small) }
                Text(NSLocalizedString("Save to wardrobe", comment: ""))
            }
            .frame(maxWidth: .infinity)
        }
        .nookGlassProminent(disabled: !viewModel.canSave)
    }
}

/// Live ML process overlay — driven by real `ScanPipelineStage` updates from
/// the on-device pipeline (detect → segment → isolate → cutout → metadata),
/// showing intermediate previews as each Core ML / CV step finishes.
struct MLProcessOverlay: View {
    let stage: ScanPipelineStage?
    let fraction: Double
    let detail: String?
    let stagePreview: UIImage?
    let reduceMotion: Bool

    private var stages: [ScanPipelineStage] { ScanPipelineStage.scanUIStages }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)

            if let stagePreview {
                Image(uiImage: stagePreview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(18)
                    .opacity(stage == .segmentClothing ? 0.92 : 1)
                    .colorMultiply(stage == .segmentClothing ? Color(red: 1, green: 0.45, blue: 0.55) : .white)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stages, id: \.self) { item in
                        stageRow(item)
                    }

                    ProgressView(value: min(1, max(0, fraction)))
                        .tint(AppColors.accent)
                        .padding(.top, 4)

                    Text(stage?.displayName
                         ?? NSLocalizedString("Starting on-device ML…", comment: "ML scan stage"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: AppRadius.medium)
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func stageRow(_ item: ScanPipelineStage) -> some View {
        let current = stage ?? .detectClothing
        let currentIdx = stages.firstIndex(of: current) ?? 0
        let itemIdx = stages.firstIndex(of: item) ?? 0
        let done = itemIdx < currentIdx || (itemIdx == currentIdx && fraction >= 0.99)
        let active = itemIdx == currentIdx

        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "circle.inset.filled" : "circle"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(done || active ? AppColors.accent : .white.opacity(0.35))
                .symbolEffect(.pulse, isActive: active && !reduceMotion)
            Text(item.displayName)
                .font(.caption2.weight(active ? .semibold : .regular))
                .foregroundStyle(active || done ? .white : .white.opacity(0.45))
            Spacer(minLength: 0)
        }
    }
}
