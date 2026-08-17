import SwiftUI

/// Shared surface treatment.
///
/// Built against the macOS 26 SDK, so stock controls pick up Liquid Glass on
/// their own. These helpers cover the custom surfaces — cards, bars, overlays —
/// and fall back to materials on older systems rather than dropping to a flat
/// fill, so the app looks deliberate either way.
extension View {

    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0.opacity(0.55)) } ?? Glass.regular
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
        }
    }

    /// For notices that must read as an interruption without shouting.
    @ViewBuilder
    func noticeSurface(_ tint: Color, cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.28)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }

    /// Prominent call to action.
    @ViewBuilder
    func primaryActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Groups nearby glass surfaces so they blend into one another instead of
/// stacking into a frosted mess.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Status

extension RunState {
    var tint: Color {
        switch self {
        case .stopped: return .secondary
        case .running: return .green
        case .paused: return .orange
        case .suspended: return .purple
        case .unknown: return .orange
        }
    }
}

/// State shown as icon *and* word.
///
/// The previous build encoded this as a coloured dot with a tooltip. A dot is
/// unreadable to anyone with a colour vision deficiency, and a tooltip does not
/// exist for keyboard or VoiceOver users — for the one value that decides
/// whether a disk may be written, that is not good enough.
struct StateChip: View {
    let state: RunState
    var compact = false

    var body: some View {
        Label {
            if !compact { Text(state.label) }
        } icon: {
            Image(systemName: state.symbolName)
                .symbolRenderingMode(.hierarchical)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(state.tint)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 3)
        .background {
            if !compact {
                Capsule().fill(state.tint.opacity(0.14))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
        .help(state.label)
    }
}
