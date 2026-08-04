import SwiftUI

/// Shown when the real Firebase `GoogleService-Info.plist` is missing.
struct FirebaseSetupView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGradient)
                    .padding(28)
                    .liquidGlass(cornerRadius: 40)

                Text(NSLocalizedString("Connect Firebase", comment: ""))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primaryGradient)

                Text(NSLocalizedString(
                    "Nook uses Firebase Authentication for sign-in. Add your project plist to continue.",
                    comment: ""
                ))
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("Configuration place", comment: ""))
                            .font(AppTypography.headline)
                        Text(FirebaseConfig.relativePathInRepo)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(AppColors.brand)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 10)

                        Text(String(
                            format: NSLocalizedString(
                                "Download GoogleService-Info.plist from Firebase Console → Project settings → Your apps (bundle id %@), then put it at the path above and rebuild.",
                                comment: ""
                            ),
                            FirebaseConfig.expectedBundleID
                        ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("Where data lives", comment: ""))
                            .font(AppTypography.headline)
                        labeled(NSLocalizedString("Auth", comment: "Firebase setup row"), "Firebase Authentication")
                        labeled(NSLocalizedString("Wardrobe", comment: ""), "Firestore users/{uid}/wardrobeItems")
                        labeled(NSLocalizedString("Images", comment: "Firebase setup row"), "Storage users/{uid}/images")
                        labeled(NSLocalizedString("Analytics", comment: "Firebase setup row"), "Firebase Analytics → BigQuery")
                    }
                }

                Text(NSLocalizedString("Details: FIREBASE_SETUP.md", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.xl)
        }
        .nookSafeScreenInsets()
        .nookScreenBackground()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
