import SwiftUI

// MARK: - Profile presentation

public extension SoundProfile {
    /// The dot shown next to the profile name. Kept in the UI layer so the
    /// model stays free of SwiftUI.
    var swatch: Color {
        switch self {
        case .red: return Color(red: 0.84, green: 0.25, blue: 0.24)
        case .brown: return Color(red: 0.59, green: 0.40, blue: 0.26)
        case .blue: return Color(red: 0.21, green: 0.47, blue: 0.86)
        case .black: return Color(red: 0.26, green: 0.27, blue: 0.30)
        case .yellow: return Color(red: 0.90, green: 0.70, blue: 0.17)
        }
    }
}

// MARK: - Controls

/// A slider with a title, a live percentage, and the two end labels that tell
/// you what the ends actually mean.
struct LabeledSlider: View {
    let title: String
    let leadingLabel: String
    let trailingLabel: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var accessibilityHint: String = ""
    /// Formats the trailing read-out. Percentage by default.
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
                .accessibilityHint(accessibilityHint)

            HStack {
                Text(leadingLabel)
                Spacer()
                Text(trailingLabel)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
    }
}

/// A row of the form `Label ............ trailing control`.
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Status indicator used for keyboard access and engine health.
struct StatusBadge: View {
    enum Level {
        case good, warning, bad

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .bad: return .red
            }
        }

        var symbol: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .bad: return "xmark.circle.fill"
            }
        }
    }

    let level: Level
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// Section heading used inside the configuration window.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The profile chooser, shared by the popover and the configuration window.
struct ProfilePicker: View {
    @Binding var selection: SoundProfile
    var showsCharacter: Bool = true

    var body: some View {
        Picker("Switch", selection: $selection) {
            ForEach(SoundProfile.allCases) { profile in
                HStack(spacing: 6) {
                    Circle()
                        .fill(profile.swatch)
                        .frame(width: 9, height: 9)
                    Text(profile.displayName)
                    if showsCharacter {
                        Text(profile.character)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(profile)
            }
        }
        .accessibilityLabel("Switch profile")
        .accessibilityValue(selection.displayName)
    }
}

// MARK: - Liquid Glass

extension View {
    /// A Liquid Glass card.
    ///
    /// Used for the raised groups in the popover and the profile list. Glass
    /// is reserved for things that genuinely float above the content — the
    /// settings forms use the system's own grouped style instead, because a
    /// form that is entirely glass is just harder to read.
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
