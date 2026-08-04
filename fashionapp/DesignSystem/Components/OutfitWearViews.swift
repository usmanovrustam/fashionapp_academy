import SwiftUI

/// Collage preview for a full daily outfit (hides bottom for dresses).
struct FullOutfitPreview: View {
    let slots: OutfitSlotAssignment
    let storage: ImageStorage
    var onTapSlot: ((OutfitWearSlot) -> Void)? = nil
    var highlightsMissing: Bool = false

    /// When true, show dress + shoes even if the dress slot is still empty.
    var preferDressLayout: Bool = false

    var body: some View {
        Group {
            if preferDressLayout || slots.isDressLook {
                dressLayout
            } else {
                separatesLayout
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous))
    }

    private var dressLayout: some View {
        VStack(spacing: 6) {
            slotImage(slots.body, slot: .body, height: 150)
            slotImage(slots.shoes, slot: .shoes, height: 64)
        }
    }

    private var separatesLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                slotImage(slots.top, slot: .top, height: 100)
                slotImage(slots.bottom, slot: .bottom, height: 100)
            }
            slotImage(slots.shoes, slot: .shoes, height: 64)
        }
    }

    @ViewBuilder
    private func slotImage(_ item: WardrobeItem?, slot: OutfitWearSlot, height: CGFloat) -> some View {
        let missing = highlightsMissing && item == nil
        let content = ZStack(alignment: .bottomLeading) {
            if let item {
                StoredImageView(
                    path: item.transparentImagePath ?? item.originalImagePath,
                    fallbackPath: item.originalImagePath,
                    storage: storage,
                    height: height,
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color(.systemGray6))
            } else {
                Color(.systemGray6)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                            Text(slot.displayName)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(missing ? AppColors.olive : AppColors.textTertiary)
                    }
            }

            if item != nil {
                Text(slot.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(missing ? AppColors.olive.opacity(0.7) : Color.clear, lineWidth: 2)
        )

        if let onTapSlot {
            Button {
                onTapSlot(slot)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Compact wear chips for a saved day look.
struct OutfitWearChipRow: View {
    let slots: OutfitSlotAssignment

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slots.orderedItems) { item in
                if let slot = OutfitWearSlot.slot(for: item.category) {
                    Text(slot.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.olive.opacity(0.12), in: Capsule())
                        .foregroundStyle(AppColors.olive)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
