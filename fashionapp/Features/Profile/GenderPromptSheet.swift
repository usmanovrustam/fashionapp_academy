import SwiftUI

/// Required Man / Woman picker as a liquid-glass dialog (not a full screen).
struct GenderPromptSheet: View {
    let onSelect: (UserGender) async throws -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppColors.olive)
                    .accessibilityHidden(true)

                Text(NSLocalizedString("What’s your gender?", comment: "Gender prompt title"))
                    .font(AppTypography.title2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString(
                    "Required. Nook uses this to show the right clothing types and build full outfits for you.",
                    comment: "Gender required subtitle"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
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

            if isSaving {
                ProgressView()
                    .tint(AppColors.olive)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color(.systemRed))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .frame(maxWidth: 360)
        .liquidGlass(cornerRadius: AppRadius.xxLarge, interactive: false)
        .padding(.horizontal, 28)
        .accessibilityAddTraits(.isModal)
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

/// Dimmed backdrop + centered liquid-glass gender dialog.
struct GenderRequiredDialogOverlay: View {
    let onSelect: (UserGender) async throws -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            GenderPromptSheet(onSelect: onSelect)
        }
        .transition(.opacity)
    }
}
