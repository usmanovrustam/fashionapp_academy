import SwiftUI

/// Fashion brand tokens — rosewood + champagne (no purple).
enum AppColors {
    /// Deep rosewood — editorial fashion primary.
    static let brand = Color(red: 0.55, green: 0.22, blue: 0.30)
    /// Soft champagne gold accent.
    static let accent = Color(red: 0.76, green: 0.62, blue: 0.45)
    /// Soft ink for emphasis.
    static let ink = Color(red: 0.14, green: 0.12, blue: 0.13)

    static let backgroundTop = Color(red: 0.98, green: 0.96, blue: 0.95)
    static let backgroundBottom = Color(red: 0.95, green: 0.93, blue: 0.91)

    static let primaryGradient = LinearGradient(
        colors: [brand, accent],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let softBackground = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardShadow = Color.black.opacity(0.08)
    static let brandShadow = brand.opacity(0.16)

    // Legacy aliases so older call sites keep compiling during migration.
    static let brandPurple = brand
    static let brandPink = accent
    static let purpleShadow = brandShadow
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
            RadialGradient(
                colors: [AppColors.brand.opacity(0.16), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [AppColors.accent.opacity(0.18), Color.clear],
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
    func liquidGlassCapsule(interactive: Bool = true, tint: Color? = AppColors.brand) -> some View {
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

/// True translucent Liquid Glass CTA — fashion rosewood tint.
struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var tint: Color? = AppColors.brand
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundStyle(prominent ? AppColors.ink : AppColors.brand)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .liquidGlassCapsule(
                interactive: !isDisabled,
                tint: prominent ? (tint ?? AppColors.brand) : tint
            )
            .opacity(isDisabled ? 0.45 : (configuration.isPressed ? 0.86 : 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Fallback alias kept for older call sites.
struct GradientPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonStyle(prominent: true, tint: AppColors.brand, isDisabled: isDisabled)
            .makeBody(configuration: configuration)
    }
}

extension View {
    /// iOS 27 Liquid Glass primary control.
    func sylyoGlassProminent(disabled: Bool = false) -> some View {
        self
            .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: AppColors.brand, isDisabled: disabled))
            .disabled(disabled)
    }

    /// iOS 27 Liquid Glass secondary control.
    func sylyoGlass(disabled: Bool = false) -> some View {
        self
            .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: AppColors.brand, isDisabled: disabled))
            .disabled(disabled)
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
