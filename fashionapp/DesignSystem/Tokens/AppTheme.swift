import SwiftUI

/// Nook palette (Huemint): `#fee697` · `#312628` · `#594f27` · `#f59629`
/// Light-mode only. Soft gold atmosphere + olive CTAs + amber accents.
enum AppColors {
    // MARK: Brand (atmosphere)
    /// Soft gold wash — `#fee697`.
    static let brand = Color(hex: 0xFEE697)
    /// Amber accent — `#f59629`.
    static let accent = Color(hex: 0xF59629)
    /// Lighter gold highlight (brand mixed toward white).
    static let blush = Color(hex: 0xFFF1C8)
    /// Olive brown — `#594f27`.
    static let olive = Color(hex: 0x594F27)
    /// Espresso — `#312628`.
    static let espresso = Color(hex: 0x312628)

    // MARK: Actions (olive primary — not blue)
    /// Primary button / tab / control fill (`#594f27`).
    static let buttonBlue = olive
    /// Pressed / deeper fill (`#312628`).
    static let buttonBlueDark = espresso

    // MARK: Text
    /// Primary copy on gold backgrounds (`#312628`).
    static let textPrimary = espresso
    /// Muted warm secondary.
    static let textSecondary = Color(hex: 0x6B5E3A)
    /// Tertiary / tab unselected.
    static let textTertiary = Color(hex: 0x8A7D5C)
    /// Placeholders.
    static let placeholder = Color(hex: 0xB8A97A)

    /// Legacy alias → primary text.
    static let ink = textPrimary

    /// Soft cream-gold screen wash.
    static let backgroundTop = Color(hex: 0xFFF8E8)
    static let backgroundBottom = Color(hex: 0xFEE697)

    /// Decorative gradient: amber → olive.
    static let primaryGradient = LinearGradient(
        colors: [accent, olive],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let softBackground = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardShadow = espresso.opacity(0.10)
    static let brandShadow = olive.opacity(0.18)

    // Legacy aliases.
    static let brandPurple = brand
    static let brandPink = accent
    static let purpleShadow = brandShadow
}

private extension Color {
    /// sRGB hex initializer (`0xRRGGBB`).
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
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
    /// Prefer semantic text styles so Dynamic Type scales (HIG Typography).
    static let largeTitle = Font.largeTitle.weight(.semibold)
    static let title = Font.title.weight(.bold)
    static let title2 = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let roundedMedium = Font.system(.body, design: .rounded).weight(.medium)
    static let brandHero = Font.system(.largeTitle, design: .rounded).weight(.semibold)
}

struct SoftBackground: View {
    var body: some View {
        ZStack {
            AppColors.softBackground
            RadialGradient(
                colors: [AppColors.brand.opacity(0.55), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [AppColors.accent.opacity(0.16), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [AppColors.olive.opacity(0.08), Color.clear],
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
    func nookSafeScreenInsets() -> some View {
        self.safeAreaPadding(.bottom, AppSpacing.sm)
    }

    /// Full-bleed atmosphere without pulling foreground content under chrome.
    func nookScreenBackground() -> some View {
        background { SoftBackground() }
    }
}

/// Groups glass elements on iOS 26+; identity wrapper on earlier OS versions.
struct NookGlassContainer<Content: View>: View {
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
    func nookGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
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

/// Solid olive CTA (`#594f27`). `tint` overrides fill (e.g. destructive red).
struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var tint: Color? = nil
    var isDisabled: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
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
    func nookGlassProminent(disabled: Bool = false) -> some View {
        self
            .buttonStyle(LiquidGlassButtonStyle(prominent: true, isDisabled: disabled))
            .disabled(disabled)
    }

    /// Secondary glass-styled control.
    func nookGlass(disabled: Bool = false) -> some View {
        self
            .buttonStyle(LiquidGlassButtonStyle(prominent: false, isDisabled: disabled))
            .disabled(disabled)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

extension View {
    /// Hide decorative SF Symbols from VoiceOver (HIG Icons / SF Symbols).
    func nookDecorativeSymbol() -> some View {
        accessibilityHidden(true)
    }
}

/// Shared App Group used by the main app + widgets.
enum AppGroupConfig {
    static let identifier = "group.apple.academy.stylo"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
