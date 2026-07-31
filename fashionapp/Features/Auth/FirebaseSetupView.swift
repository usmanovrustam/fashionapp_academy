import SwiftUI

/// Shown when the real Firebase `GoogleService-Info.plist` is missing.
/// This replaced the old iCloud / CloudKit wardrobe gate.
struct FirebaseSetupView: View {
    var body: some View {
        ZStack {
            SoftBackground()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.primaryGradient)

                    Text("Connect Firebase")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.primaryGradient)

                    Text("CloudKit wardrobe storage was removed. Sylyo now stores users, wardrobe items, and images in your Firebase project.")
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Configuration place")
                                .font(AppTypography.headline)
                            Text(FirebaseConfig.relativePathInRepo)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.purple)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlass(cornerRadius: 10, tint: .purple)

                            Text("Download GoogleService-Info.plist from Firebase Console → Project settings → Your apps (bundle id \(FirebaseConfig.expectedBundleID)), then put it at the path above and rebuild.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Where wardrobe data lives")
                                .font(AppTypography.headline)
                            labeled("Auth", "Firebase Authentication")
                            labeled("Wardrobe", "Firestore users/{uid}/wardrobeItems")
                            labeled("Images", "Storage users/{uid}/images")
                            labeled("Analytics", "Firebase Analytics → BigQuery")
                        }
                    }

                    Text("Details: FIREBASE_SETUP.md")
                        .font(.footnote)
                        .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
