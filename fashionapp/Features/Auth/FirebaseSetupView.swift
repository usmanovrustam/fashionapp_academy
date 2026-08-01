import SwiftUI

/// Shown when the real Firebase `GoogleService-Info.plist` is missing.
struct FirebaseSetupView: View {
    var body: some View {
        ZStack {
            SoftBackground()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(AppColors.primaryGradient)
                        .padding(28)
                        .liquidGlass(cornerRadius: 40)

                    Text("Connect Firebase")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.primaryGradient)

                    Text("Sylyo uses Firebase Authentication for sign-in. Add your project plist to continue.")
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Configuration place")
                                .font(AppTypography.headline)
                            Text(FirebaseConfig.relativePathInRepo)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(AppColors.brand)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlass(cornerRadius: 10)

                            Text("Download GoogleService-Info.plist from Firebase Console → Project settings → Your apps (bundle id \(FirebaseConfig.expectedBundleID)), then put it at the path above and rebuild.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Where data lives")
                                .font(AppTypography.headline)
                            labeled("Auth", "Firebase Authentication")
                            labeled("Wardrobe", "Firestore users/{uid}/wardrobeItems")
                            labeled("Images", "Storage users/{uid}/images")
                            labeled("Analytics", "Firebase Analytics → BigQuery")
                        }
                    }

                    Text("Details: FIREBASE_SETUP.md")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(AppSpacing.xl)
            }
        }
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
