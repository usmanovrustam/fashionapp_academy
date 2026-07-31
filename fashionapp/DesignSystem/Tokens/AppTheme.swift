import SwiftUI

/// Shared visual tokens preserved from the original Sylyo UI.
enum AppColors {
    static let backgroundTop = Color(red: 0.95, green: 0.95, blue: 1.0)
    static let backgroundBottom = Color(red: 1.0, green: 0.95, blue: 0.98)
    static let brandPurple = Color.purple
    static let brandPink = Color.pink
    static let primaryGradient = LinearGradient(
        colors: [brandPurple, brandPink],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let softBackground = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardShadow = Color.black.opacity(0.08)
    static let purpleShadow = Color.purple.opacity(0.15)
}

enum AppRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 28
    static let photo: CGFloat = 32
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AppTypography {
    static let title = Font.title.bold()
    static let title2 = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    static let roundedMedium = Font.system(size: 18, weight: .medium, design: .rounded)
}

struct SoftBackground: View {
    var body: some View {
        AppColors.softBackground.ignoresSafeArea()
    }
}

struct GradientPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppColors.primaryGradient.opacity(isDisabled ? 0.45 : (configuration.isPressed ? 0.85 : 1)))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
