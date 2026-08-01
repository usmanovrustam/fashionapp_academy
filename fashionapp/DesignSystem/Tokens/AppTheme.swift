import SwiftUI

/// Soft pastel sky atmosphere + solid blue CTAs. App is light-mode only.
/// Text uses separate matte neutrals — never treat text colors as brand.
enum AppColors {
    // MARK: Brand (atmosphere / accents only — not body text)
    /// Soft sky wash for backgrounds.
    static let brand = Color(red: 0.52, green: 0.74, blue: 0.94)
    /// Soft powder-blue accent.
    static let accent = Color(red: 0.72, green: 0.86, blue: 0.96)
    /// Airy cloud-blue highlight.
    static let blush = Color(red: 0.86, green: 0.93, blue: 0.99)

    // MARK: Actions (solid blue — not pastel)
    /// Primary button / interactive blue.
    static let buttonBlue = Color(red: 0.13, green: 0.45, blue: 0.95)
    /// Slightly deeper blue for pressed / secondary fills.
    static let buttonBlueDark = Color(red: 0.08, green: 0.35, blue: 0.85)

    // MARK: Text (matte neutrals — not core brand)
    /// Matte pastel black for titles / primary copy.
    static let textPrimary = Color(red: 0.16, green: 0.17, blue: 0.19)
    /// Soft grey for secondary copy.
    static let textSecondary = Color(red: 0.45, green: 0.47, blue: 0.50)
    /// Cool blue-grey for tertiary / muted labels.
    static let textTertiary = Color(red: 0.50, green: 0.56, blue: 0.64)
    /// Light grey for field placeholders and hint text.
    static let placeholder = Color(red: 0.72, green: 0.74, blue: 0.78)

    /// Legacy alias → matte primary text.
    static let ink = textPrimary

    static let backgroundTop = Color(red: 0.96, green: 0.98, blue: 1.0)
    static let backgroundBottom = Color(red: 0.92, green: 0.96, blue: 0.99)

    static let primaryGradient = LinearGradient(
        colors: [buttonBlue, buttonBlueDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let softBackground = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardShadow = Color.black.opacity(0.06)
    static let brandShadow = brand.opacity(0.16)

    // Legacy aliases.
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
                colors: [AppColors.brand.opacity(0.20), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [AppColors.accent.opacity(0.22), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [AppColors.blush.opacity(0.28), Color.clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Extra breathing room above the floating tab bar / home indicator.
    /// Prefer `.background { SoftBackground() }` over a ZStack sibling so the
    /// system safe area (nav + tab bar) still insets content correctly.
    func sylyoSafeScreenInsets() -> some View {
        self.safeAreaPadding(.bottom, AppSpacing.sm)
    }

    /// Full-bleed atmosphere without pulling foreground content under chrome.
    func sylyoScreenBackground() -> some View {
        background { SoftBackground() }
    }
}

/// Groups glass elements on iOS 26+; identity wrapper on earlier OS versions.
struct SylyoGlassContainer<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

/// Applies Liquid Glass on iOS 26+, material fallback otherwise.
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
        } else if #available(iOS 26.0, *) {
            content.glassEffect(makeGlass(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
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

    /// Capsule Liquid Glass control (untinted / clear by default).
    func liquidGlassCapsule(interactive: Bool = true, tint: Color? = nil) -> some View {
        modifier(LiquidGlassCapsuleModifier(interactive: interactive, tint: tint))
    }

    /// Morphing ID for Liquid Glass (no-op below iOS 26).
    @ViewBuilder
    func sylyoGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
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
        } else if #available(iOS 26.0, *) {
            content.glassEffect(makeGlass(), in: .capsule)
        } else {
            content.background(Capsule().fill(.ultraThinMaterial))
        }
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        var s: Glass = .regular
        if let tint { s = s.tint(tint) }
        if interactive { s = s.interactive() }
        return s
    }
}

/// Solid blue CTA (not pastel). `tint` overrides fill (e.g. destructive red).
struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var tint: Color? = nil
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background {
                capsuleFill
                    .opacity(isDisabled ? 0.45 : (configuration.isPressed ? 0.88 : 1))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }

    @ViewBuilder
    private var capsuleFill: some View {
        if let tint {
            Capsule().fill(tint.opacity(prominent ? 0.95 : 0.82))
        } else if prominent {
            Capsule().fill(
                LinearGradient(
                    colors: [AppColors.buttonBlue, AppColors.buttonBlueDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            Capsule().fill(AppColors.buttonBlue.opacity(0.90))
        }
    }
}

/// Fallback alias kept for older call sites.
struct GradientPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        LiquidGlassButtonStyle(prominent: true, isDisabled: isDisabled)
            .makeBody(configuration: configuration)
    }
}

extension View {
    /// Primary glass-styled control.
    func sylyoGlassProminent(disabled: Bool = false) -> some View {
        self
            .buttonStyle(LiquidGlassButtonStyle(prominent: true, isDisabled: disabled))
            .disabled(disabled)
    }

    /// Secondary glass-styled control.
    func sylyoGlass(disabled: Bool = false) -> some View {
        self
            .buttonStyle(LiquidGlassButtonStyle(prominent: false, isDisabled: disabled))
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

/// Shared App Group used by the main app + widgets.
enum AppGroupConfig {
    static let identifier = "group.apple.academy.stylo"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
