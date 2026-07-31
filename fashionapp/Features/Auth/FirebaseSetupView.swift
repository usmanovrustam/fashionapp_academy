import SwiftUI

/// Shown when `GoogleService-Info.plist` from the real Firebase project is missing.
struct FirebaseSetupView: View {
    var body: some View {
        ZStack {
            SoftBackground()
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.primaryGradient)

                Text("Connect Firebase")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primaryGradient)

                Text("Sylyo uses your real Firebase project for Auth, Firestore, Storage, and Analytics → BigQuery. Add the downloaded config file to unlock the app.")
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Setup steps")
                            .font(AppTypography.headline)
                        labeledStep("1", "Open Firebase Console → Project settings → Your apps")
                        labeledStep("2", "Download GoogleService-Info.plist for bundle id apple.academy.stylo")
                        labeledStep("3", "Place it at fashionapp/GoogleService-Info.plist")
                        labeledStep("4", "Enable Email/Password (+ Anonymous if you want guest)")
                        labeledStep("5", "Create Firestore + Storage; deploy rules in repo root")
                        labeledStep("6", "Link Analytics to BigQuery in Firebase console")
                        labeledStep("7", "Rebuild the app")
                    }
                }

                Text("See FIREBASE_SETUP.md and bigquery/ for full instructions.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(AppSpacing.xl)
        }
    }

    private func labeledStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(AppColors.primaryGradient)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}
