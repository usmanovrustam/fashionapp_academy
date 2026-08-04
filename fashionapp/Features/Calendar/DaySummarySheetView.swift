import SwiftUI

/// First sheet when tapping a date: review plans, then add / edit / delete.
struct DaySummarySheetView: View {
    let date: Date
    let events: [CalendarEvent]
    let wardrobeItems: [WardrobeItem]
    @Binding var packingListsByID: [UUID: PackingList]
    let onAdd: () -> Void
    let onEdit: (CalendarEvent) -> Void
    let onDelete: (CalendarEvent) -> Void
    let onMarkWashed: (CalendarEvent) -> Void
    let onTogglePacked: (CalendarEvent, UUID) -> Void
    let onClose: () -> Void

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if events.isEmpty {
                        Text(NSLocalizedString("Nothing planned yet for this day.", comment: ""))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .liquidGlass(cornerRadius: AppRadius.medium)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    } else {
                        Text(NSLocalizedString("Plans", comment: ""))
                            .font(AppTypography.headline)

                        ForEach(events) { event in
                            DaySummaryPlanCard(
                                event: event,
                                linkedItems: linkedItems(for: event),
                                packingList: event.packingListID.flatMap { packingListsByID[$0] },
                                onEdit: { onEdit(event) },
                                onDelete: { onDelete(event) },
                                onMarkWashed: event.kind == .laundry ? { onMarkWashed(event) } : nil,
                                onTogglePacked: event.kind == .travel
                                    ? { itemID in onTogglePacked(event, itemID) }
                                    : nil
                            )
                        }
                    }

                    Button(action: onAdd) {
                        Label(NSLocalizedString("Add plan", comment: ""), systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.brand)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppColors.olive)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .padding(.top, AppSpacing.sm)
                }
                .padding()
            }
            .nookScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: ""), action: onClose)
                }
            }
        }
    }

    private func linkedItems(for event: CalendarEvent) -> [WardrobeItem] {
        let ids = Set(event.wardrobeItemIDs + event.suggestedItemIDs)
        return wardrobeItems.filter { ids.contains($0.id) }
    }
}

private struct DaySummaryPlanCard: View {
    let event: CalendarEvent
    let linkedItems: [WardrobeItem]
    let packingList: PackingList?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMarkWashed: (() -> Void)?
    let onTogglePacked: ((UUID) -> Void)?

    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: event.kind.systemImage)
                        .font(.title3)
                        .foregroundStyle(AppColors.olive)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                        Text(NSLocalizedString("Tap to edit", comment: ""))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppColors.olive)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if let onTogglePacked, !linkedItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Packing checklist", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    ForEach(linkedItems) { item in
                        let packed = packingList?.packedItemIDs.contains(item.id) == true
                        Button {
                            onTogglePacked(item.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: packed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(packed ? AppColors.olive : AppColors.textTertiary)
                                Text(item.name)
                                    .font(.subheadline)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .strikethrough(packed, color: AppColors.textSecondary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !linkedItems.isEmpty {
                Text(linkedItems.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if let onMarkWashed {
                    Button(action: onMarkWashed) {
                        Label(NSLocalizedString("Mark washed", comment: ""), systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.olive)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.brand.opacity(0.45))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .confirmationDialog(
            NSLocalizedString("Delete this plan?", comment: ""),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Delete plan", comment: ""), role: .destructive, action: onDelete)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var subtitle: String {
        if let summary = event.weatherSummary, !summary.isEmpty { return summary }
        if let dress = event.dressCode, !dress.isEmpty { return dress }
        if let notes = event.notes, !notes.isEmpty { return notes }
        return event.kind.title
    }

    private var deleteMessage: String {
        switch event.kind {
        case .laundry:
            return NSLocalizedString("This also clears the need-to-wash mark on the linked pieces.", comment: "")
        case .donate:
            return NSLocalizedString("This also removes the donate mark from the linked pieces.", comment: "")
        case .knownOutfit:
            return NSLocalizedString("This removes the look from this day.", comment: "")
        default:
            return NSLocalizedString("This removes the plan from your calendar.", comment: "")
        }
    }
}
