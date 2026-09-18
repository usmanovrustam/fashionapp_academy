import SwiftUI
import UIKit

/// Manual mask touch-up: paint / erase on a grayscale garment mask, then apply to the photo.
struct MaskEditorView: View {
    let sourceImage: UIImage
    let initialMask: UIImage
    var onDone: (UIImage /* cutout */) -> Void
    var onCancel: () -> Void

    @State private var mask: UIImage
    @State private var brushRadius: CGFloat = 28
    @State private var isErasing = false
    @State private var preview: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        sourceImage: UIImage,
        initialMask: UIImage,
        onDone: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceImage = sourceImage
        self.initialMask = initialMask
        self.onDone = onDone
        self.onCancel = onCancel
        _mask = State(initialValue: initialMask)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let fit = aspectFitSize(for: sourceImage.size, in: geo.size)
                    ZStack {
                        Image(uiImage: preview ?? sourceImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)

                        // Invisible hit target matching the fitted image.
                        Color.clear
                            .frame(width: fit.width, height: fit.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        paint(
                                            at: value.location,
                                            viewSize: fit,
                                            origin: CGPoint(
                                                x: (geo.size.width - fit.width) / 2,
                                                y: (geo.size.height - fit.height) / 2
                                            )
                                        )
                                    }
                            )
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Toggle(isOn: $isErasing) {
                        Text(isErasing
                             ? NSLocalizedString("Erase", comment: "Mask editor")
                             : NSLocalizedString("Paint", comment: "Mask editor"))
                    }
                    .toggleStyle(.button)

                    Slider(value: $brushRadius, in: 8...64) {
                        Text(NSLocalizedString("Brush", comment: "Mask editor"))
                    }
                }
                .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    Button(NSLocalizedString("Reset", comment: "")) {
                        mask = initialMask
                        refreshPreview()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(NSLocalizedString("Apply cutout", comment: "")) {
                        if let cutout = try? ImageProcessing.applyMask(image: sourceImage, mask: mask) {
                            onDone(cutout)
                        } else {
                            onDone(sourceImage)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle(NSLocalizedString("Edit mask", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: ""), action: onCancel)
                }
            }
            .onAppear { refreshPreview() }
        }
    }

    private func paint(at viewPoint: CGPoint, viewSize: CGSize, origin: CGPoint) {
        let local = CGPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)
        guard local.x >= 0, local.y >= 0, local.x <= viewSize.width, local.y <= viewSize.height else { return }
        guard let cg = ImageProcessing.cgImage(from: mask) else { return }

        let scaleX = CGFloat(cg.width) / max(viewSize.width, 1)
        let scaleY = CGFloat(cg.height) / max(viewSize.height, 1)
        let pixel = CGPoint(x: local.x * scaleX, y: local.y * scaleY)
        let radius = brushRadius * ((scaleX + scaleY) / 2)

        mask = ImageProcessing.applyBrushStroke(
            to: mask,
            at: pixel,
            radius: radius,
            add: !isErasing
        )
        refreshPreview()
    }

    private func refreshPreview() {
        preview = try? ImageProcessing.applyMask(image: sourceImage, mask: mask)
    }

    private func aspectFitSize(for image: CGSize, in bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / max(image.width, 1), bounds.height / max(image.height, 1))
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
