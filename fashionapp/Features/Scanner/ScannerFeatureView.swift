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
                                ScanningShimmerOverlay(image: image, reduceMotion: reduceMotion)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.photo, style: .continuous))
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(NSLocalizedString("Analyzing outfit", comment: ""))
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

/// CNN-style analyzing overlay: a convolution kernel raster-scans the image,
/// revealing it as colored pixel blocks with an accent activation trail — like
/// a network reading the image pixel by pixel.
struct ScanningShimmerOverlay: View {
    let image: UIImage?
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            CNNPixelScan(image: image, reduceMotion: reduceMotion)

            VStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                Text(NSLocalizedString("Analyzing outfit…", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(20)
            .liquidGlass(cornerRadius: AppRadius.medium)
        }
    }
}

/// Convolution-style pixel scan. Samples the image into a grid of colored
/// blocks and reveals them in raster order behind a sliding 3×3 kernel window,
/// with a fading accent "activation" trail just behind the kernel.
struct CNNPixelScan: View {
    let image: UIImage?
    let reduceMotion: Bool
    private let cols = 18
    private let rows = 20
    private let period: TimeInterval = 2.6

    @State private var colors: [Color] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let cellW = size.width / CGFloat(cols)
                let cellH = size.height / CGFloat(rows)
                let cells = cols * rows

                let progress: Double
                if reduceMotion {
                    progress = 0.66
                } else {
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    progress = t.truncatingRemainder(dividingBy: period) / period
                }
                let scanIndex = progress * Double(cells)

                for r in 0..<rows {
                    for c in 0..<cols {
                        let idx = r * cols + c
                        let rect = CGRect(
                            x: CGFloat(c) * cellW,
                            y: CGFloat(r) * cellH,
                            width: cellW,
                            height: cellH
                        ).insetBy(dx: 0.5, dy: 0.5)
                        let cell = Path(rect)

                        if Double(idx) <= scanIndex {
                            // Revealed pixel block.
                            let color = colors.indices.contains(idx) ? colors[idx] : Color.gray
                            context.fill(cell, with: .color(color))
                            // Fading activation glow just behind the kernel.
                            let behind = scanIndex - Double(idx)
                            if behind < Double(cols) {
                                let g = 1 - behind / Double(cols)
                                context.fill(cell, with: .color(AppColors.accent.opacity(0.55 * g)))
                            }
                        } else {
                            // Not yet scanned — dark with faint grid.
                            context.fill(cell, with: .color(.black.opacity(0.5)))
                            context.stroke(cell, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                        }
                    }
                }

                // Sliding 3×3 convolution kernel window.
                let ki = min(cells - 1, max(0, Int(scanIndex)))
                let kc = ki % cols
                let kr = ki / cols
                let krect = CGRect(
                    x: CGFloat(kc - 1) * cellW,
                    y: CGFloat(kr - 1) * cellH,
                    width: cellW * 3,
                    height: cellH * 3
                )
                context.stroke(
                    Path(roundedRect: krect, cornerRadius: 2),
                    with: .color(.white.opacity(0.95)),
                    lineWidth: 2
                )
            }
            .allowsHitTesting(false)
        }
        .onAppear { colors = Self.colorGrid(from: image, cols: cols, rows: rows) }
    }

    /// Downsamples the image to a cols×rows grid of average colors.
    static func colorGrid(from image: UIImage?, cols: Int, rows: Int) -> [Color] {
        let fallback = Array(repeating: Color.gray.opacity(0.6), count: cols * rows)
        guard let image, let cg = ImageProcessing.cgImage(from: image) else { return fallback }
        var bytes = [UInt8](repeating: 0, count: cols * rows * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: cols * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        var out: [Color] = []
        out.reserveCapacity(cols * rows)
        for i in 0..<(cols * rows) {
            let o = i * 4
            out.append(Color(
                red: Double(bytes[o]) / 255,
                green: Double(bytes[o + 1]) / 255,
                blue: Double(bytes[o + 2]) / 255
            ))
        }
        return out
    }
}
