import SwiftUI

/// Shared visual tokens — Liquid Glass (iOS 26/27) first.
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
        ZStack {
            AppColors.softBackground
            // Subtle depth so Liquid Glass has content to refract.
            RadialGradient(
                colors: [Color.purple.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.pink.opacity(0.14), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

/// Applies Apple Liquid Glass with Reduce Transparency fallback.
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.large
    var interactive: Bool = false
    var tint: Color? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        } else {
            content
                .glassEffect(glassStyle, in: .rect(cornerRadius: cornerRadius))
        }
    }

    private var glassStyle: Glass {
        var style: Glass = .regular
        if let tint {
            style = style.tint(tint)
        }
        if interactive {
            style = style.interactive()
        }
        return style
    }
}

extension View {
    /// Liquid Glass panel (cards, sheets, chrome).
    func liquidGlass(
        cornerRadius: CGFloat = AppRadius.large,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            interactive: interactive,
            tint: tint
        ))
    }

    /// Capsule Liquid Glass control.
    func liquidGlassCapsule(interactive: Bool = true, tint: Color? = .purple) -> some View {
        modifier(LiquidGlassCapsuleModifier(interactive: interactive, tint: tint))
    }
}

private struct LiquidGlassCapsuleModifier: ViewModifier {
    var interactive: Bool
    var tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        } else {
            content.glassEffect(style, in: .capsule)
        }
    }

    private var style: Glass {
        var s: Glass = .regular
        if let tint { s = s.tint(tint) }
        if interactive { s = s.interactive() }
        return s
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
            .background {
                if isDisabled {
                    Capsule().fill(Color.purple.opacity(0.35))
                } else {
                    Capsule()
                        .fill(AppColors.primaryGradient.opacity(configuration.isPressed ? 0.85 : 1))
                }
            }
            .liquidGlassCapsule(interactive: !isDisabled, tint: .purple)
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

/// Shared App Group used by the main app + iOS 27 widgets.
enum AppGroupConfig {
    static let identifier = "group.apple.academy.stylo"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
