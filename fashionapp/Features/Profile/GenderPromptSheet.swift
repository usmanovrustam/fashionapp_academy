import SwiftUI

/// Full-screen or sheet UI to collect required Man / Woman gender.
struct GenderPromptSheet: View {
    var presentsAsSheet: Bool = true
    let onSelect: (UserGender) async throws -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .nookScreenBackground()
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(true)
        }
        .modifier(GenderPresentationModifier(presentsAsSheet: presentsAsSheet))
    }

    private var content: some View {
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
                    "Required. Nook uses this to show the right clothing types and build full outfits for you.",
                    comment: "Gender required subtitle"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.top, presentsAsSheet ? 12 : 40)

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

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct GenderPresentationModifier: ViewModifier {
    var presentsAsSheet: Bool

    func body(content: Content) -> some View {
        if presentsAsSheet {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackgroundInteraction(.disabled)
        } else {
            content
        }
    }
}
