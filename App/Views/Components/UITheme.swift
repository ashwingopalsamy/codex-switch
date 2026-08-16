import AppKit
import SwiftUI

// MARK: - Design System Tokens

enum UITheme {
    enum Colors {
        // Semantic status
        static let emerald = Color(red: 0.13, green: 0.77, blue: 0.44)
        static let emeraldBg = Color(red: 0.13, green: 0.77, blue: 0.44).opacity(0.12)

        static let amber = Color(red: 0.96, green: 0.62, blue: 0.15)
        static let amberBg = Color(red: 0.96, green: 0.62, blue: 0.15).opacity(0.12)

        static let coral = Color(red: 0.94, green: 0.33, blue: 0.31)
        static let coralBg = Color(red: 0.94, green: 0.33, blue: 0.31).opacity(0.12)

        static let systemBlue = Color(red: 0.20, green: 0.50, blue: 0.98)
        static let blueBg = Color(red: 0.20, green: 0.50, blue: 0.98).opacity(0.12)

        // Glass surfaces
        static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.45)
        static let cardBorder = Color.primary.opacity(0.08)

        // Controls
        static let buttonSecondaryBg = Color.primary.opacity(0.06)
        static let buttonSecondaryBorder = Color.primary.opacity(0.12)
    }

    enum Typography {
        static let appTitle = Font.system(size: 15, weight: .bold, design: .rounded)
        static let appSubtitle = Font.system(size: 11, weight: .regular)
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        static let cardSubtitle = Font.system(size: 11, weight: .regular)
        static let badge = Font.system(size: 10, weight: .semibold, design: .rounded)
        static let chip = Font.system(size: 10, weight: .medium)
        static let micro = Font.system(size: 10, weight: .regular)
        static let input = Font.system(size: 12, weight: .regular)
    }

    enum Spacing {
        static let windowPadding: CGFloat = 16
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20

        static let cardPaddingHorizontal: CGFloat = 16
        static let cardPaddingVertical: CGFloat = 12

        static let avatarSize: CGFloat = 38
        static let circleButtonSize: CGFloat = 28
    }

    enum Radius {
        static let card: CGFloat = 20
        static let hero: CGFloat = 20
        static let control: CGFloat = 6
        static let chip: CGFloat = 4
    }
    enum Animations {
        static let spring = Animation.spring(response: 0.25, dampingFraction: 0.8)
        static let press = Animation.spring(response: 0.18, dampingFraction: 0.7)
        static let hover = Animation.spring(response: 0.22, dampingFraction: 0.85)
    }
}

// MARK: - Card Surface Modifier

struct CardSurfaceModifier: ViewModifier {
    var radius: CGFloat = UITheme.Radius.card

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(UITheme.Colors.cardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(UITheme.Colors.cardBorder, lineWidth: 0.5)
                    }
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            }
    }
}

extension View {
    func cardSurface(radius: CGFloat = UITheme.Radius.card) -> some View {
        modifier(CardSurfaceModifier(radius: radius))
    }

    func unfocusedControl() -> some View {
        self
            .focusable(false)
            .focusEffectDisabled()
    }
}

// MARK: - Frosted Tactile Button Styles (Capsule)

struct TactileButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
        case subtle
        case destructive
        case emerald
        case emeraldSecondary
        case blue
    }

    @Environment(\.controlSize) private var envControlSize
    var variant: Variant = .secondary
    var explicitSize: ControlSize? = nil

    private var effectiveSize: ControlSize {
        explicitSize ?? envControlSize
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(fontForSize)
            .fontWeight(.medium)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .background(backgroundView(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(UITheme.Animations.press, value: configuration.isPressed)
            .focusable(false)
            .focusEffectDisabled()
    }

    private var fontForSize: Font {
        switch effectiveSize {
        case .mini: return .caption2
        case .small: return .system(size: 11.5, weight: .medium)
        case .regular: return .callout
        case .large: return .body
        case .extraLarge: return .title3
        @unknown default: return .callout
        }
    }

    private var horizontalPadding: CGFloat {
        switch effectiveSize {
        case .mini: return 8
        case .small: return 10
        case .regular: return 14
        case .large: return 18
        case .extraLarge: return 22
        @unknown default: return 14
        }
    }

    private var verticalPadding: CGFloat {
        switch effectiveSize {
        case .mini: return 3
        case .small: return 5
        case .regular: return 7
        case .large: return 9
        case .extraLarge: return 11
        @unknown default: return 7
        }
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary, .blue:
            return Color(nsColor: .windowBackgroundColor)
        case .emerald:
            return .white
        case .emeraldSecondary:
            return UITheme.Colors.emerald
        case .secondary:
            return .primary
        case .subtle:
            return .secondary
        case .destructive:
            return UITheme.Colors.coral
        }
    }

    @ViewBuilder
    private func backgroundView(isPressed: Bool) -> some View {
        switch variant {
        case .primary, .blue:
            Color.primary
                .opacity(isPressed ? 0.85 : 1.0)
        case .emerald:
            UITheme.Colors.emerald
                .opacity(isPressed ? 0.85 : 1.0)
        case .secondary, .destructive, .emeraldSecondary:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                UITheme.Colors.buttonSecondaryBg
                    .opacity(isPressed ? 0.75 : 1.0)
            }
        case .subtle:
            Color.primary.opacity(isPressed ? 0.08 : 0.04)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary, .blue:
            return Color.primary.opacity(0.15)
        case .emerald:
            return Color.white.opacity(0.18)
        case .secondary:
            return UITheme.Colors.buttonSecondaryBorder
        case .emeraldSecondary:
            return UITheme.Colors.emerald.opacity(0.25)
        case .subtle:
            return Color.clear
        case .destructive:
            return UITheme.Colors.coral.opacity(0.25)
        }
    }
}

// MARK: - Frosted Tactile Circular Icon Button Style (28×28pt)

struct TactileCircleButtonStyle: ButtonStyle {
    enum Variant {
        case secondary
        case blue
        case emerald
        case destructive
        case primary
    }

    var variant: Variant = .secondary
    var size: CGFloat = UITheme.Spacing.circleButtonSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .background(backgroundView(isPressed: configuration.isPressed))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(UITheme.Animations.press, value: configuration.isPressed)
            .focusable(false)
            .focusEffectDisabled()
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary, .blue:
            return Color(nsColor: .windowBackgroundColor)
        case .emerald:
            return .white
        case .secondary:
            return .primary
        case .destructive:
            return UITheme.Colors.coral
        }
    }

    @ViewBuilder
    private func backgroundView(isPressed: Bool) -> some View {
        switch variant {
        case .primary, .blue:
            Color.primary.opacity(isPressed ? 0.85 : 1.0)
        case .emerald:
            UITheme.Colors.emerald.opacity(isPressed ? 0.85 : 1.0)
        case .secondary, .destructive:
            ZStack {
                Circle().fill(.ultraThinMaterial)
                UITheme.Colors.buttonSecondaryBg.opacity(isPressed ? 0.75 : 1.0)
            }
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary, .blue:
            return Color.primary.opacity(0.15)
        case .emerald:
            return Color.white.opacity(0.18)
        case .secondary:
            return UITheme.Colors.buttonSecondaryBorder
        case .destructive:
            return UITheme.Colors.coral.opacity(0.25)
        }
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == TactileButtonStyle {
    static var tactilePrimary: TactileButtonStyle { TactileButtonStyle(variant: .primary) }
    static var tactileSecondary: TactileButtonStyle { TactileButtonStyle(variant: .secondary) }
    static var tactileSubtle: TactileButtonStyle { TactileButtonStyle(variant: .subtle) }
    static var tactileDestructive: TactileButtonStyle { TactileButtonStyle(variant: .destructive) }
    static var tactileEmerald: TactileButtonStyle { TactileButtonStyle(variant: .emerald) }
    static var tactileEmeraldSecondary: TactileButtonStyle { TactileButtonStyle(variant: .emeraldSecondary) }
    static var tactileBlue: TactileButtonStyle { TactileButtonStyle(variant: .blue) }
    static func tactile(variant: TactileButtonStyle.Variant, size: ControlSize? = nil) -> TactileButtonStyle {
        TactileButtonStyle(variant: variant, explicitSize: size)
    }
}

extension ButtonStyle where Self == TactileCircleButtonStyle {
    static var tactileCircleSecondary: TactileCircleButtonStyle { TactileCircleButtonStyle(variant: .secondary) }
    static var tactileCircleBlue: TactileCircleButtonStyle { TactileCircleButtonStyle(variant: .blue) }
    static var tactileCircleEmerald: TactileCircleButtonStyle { TactileCircleButtonStyle(variant: .emerald) }
    static var tactileCircleDestructive: TactileCircleButtonStyle { TactileCircleButtonStyle(variant: .destructive) }
    static var tactileCirclePrimary: TactileCircleButtonStyle { TactileCircleButtonStyle(variant: .primary) }
    static func tactileCircle(variant: TactileCircleButtonStyle.Variant, size: CGFloat = UITheme.Spacing.circleButtonSize) -> TactileCircleButtonStyle {
        TactileCircleButtonStyle(variant: variant, size: size)
    }
}
