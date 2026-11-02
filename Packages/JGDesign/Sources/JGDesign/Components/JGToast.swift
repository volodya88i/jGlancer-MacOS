import SwiftUI

/// A non-modal message at the bottom of the window (docs/DESIGN.md §7): one short line, an optional action
/// ("Undo"), an optional progress bar with a stop button for long batches. Radius large, `bg.raised`; one soft
/// shadow in light mode only (DESIGN §2.6).
public struct JGToast: View {
    private let message: Text
    private let actionTitle: Text?
    private let action: (() -> Void)?
    private let progress: Double?
    private let stop: (label: Text, action: () -> Void)?
    private let dismiss: (label: Text, action: () -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        _ message: Text, actionTitle: Text? = nil, action: (() -> Void)? = nil, progress: Double? = nil,
        stop: (label: Text, action: () -> Void)? = nil,
        dismiss: (label: Text, action: () -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.progress = progress
        self.stop = stop
        self.dismiss = dismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            HStack(spacing: JGSpacing.m) {
                message
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) { actionTitle }
                        .buttonStyle(.jg(.secondary))
                }
                if let stop {
                    Button(action: stop.action) {
                        Image(systemName: "stop.fill").foregroundStyle(JGColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(stop.label)
                    .accessibilityLabel(stop.label)
                }
                if let dismiss {
                    Button(action: dismiss.action) {
                        Image(systemName: "xmark").foregroundStyle(JGColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(dismiss.label)
                    .accessibilityLabel(dismiss.label)
                }
            }
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(JGColor.accent)
            }
        }
        .padding(.horizontal, JGSpacing.m)
        .padding(.vertical, JGSpacing.s)
        .background(JGColor.bgRaised, in: JGShape(.large))
        .overlay(JGShape(.large).strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth))
        .shadow(
            color: colorScheme == .light ? .black.opacity(JGMetrics.toastShadowOpacity) : .clear,
            radius: JGMetrics.toastShadowRadius,
            y: 2
        )
        .frame(maxWidth: JGMetrics.readableTextWidth)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: JGSpacing.m) {
        JGToast(Text(verbatim: "Moved 12 items"), actionTitle: Text(verbatim: "Undo"), action: {})
        JGToast(Text(verbatim: "Moving 40 of 400…"), progress: 0.1, stop: (Text(verbatim: "Stop"), {}))
    }
    .padding(JGSpacing.xl)
    .background(JGColor.bgBase)
}
