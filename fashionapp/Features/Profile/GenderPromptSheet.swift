import SwiftUI

/// Blocking prompt when gender was never chosen (Apple Sign In, older accounts).
struct GenderPromptSheet: View {
    let onSelect: (UserGender) async throws -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.olive)
                        .accessibilityHidden(true)

                    Text(NSLocalizedString("What’s your gender?", comment: "Gender prompt title"))
                        .font(AppTypography.title2)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString(
                        "This helps Nook suggest full outfits — for example when a dress can replace a separate top and bottom.",
                        comment: "Gender prompt subtitle"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 12) {
                    ForEach(UserGender.allCases) { gender in
                        Button {
                            Task { await select(gender) }
                        } label: {
                            Text(gender.displayName)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LiquidGlassButtonStyle(
                            prominent: true,
                            isDisabled: isSaving
                        ))
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color(.systemRed))
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .nookScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func select(_ gender: UserGender) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onSelect(gender)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
