import SwiftUI

/// A 2px rule. The system organises by alignment and the strength of its
/// dividers, so these are never softened into hairlines.
struct Rule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(Theme.rule(scheme))
            .frame(height: Theme.Space.ruleWidth)
    }
}

/// The full-width primary action. Its label is flush left, per the system —
/// a button wider than its label starts the text at the left padding edge.
struct PrimaryButton: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var trailing: String?
    var tint: Color?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(TypeScale.action)
                Spacer()
                if let trailing {
                    Text(trailing).font(TypeScale.action).opacity(0.7)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.Space.primaryActionHeight)
            .background(background)
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var background: Color {
        guard isEnabled else { return Theme.surface(scheme) }
        return tint ?? Theme.ink(scheme)
    }
    private var foreground: Color {
        isEnabled ? Theme.bg(scheme) : Theme.ink3(scheme)
    }
}

/// One of Hard / Good / Easy, with the interval it would schedule.
struct RatingButton: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let interval: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(TypeScale.action)
                Text(interval).font(TypeScale.secondary).foregroundStyle(Theme.ink3(scheme))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Space.ratingHeight)
            .overlay(Rectangle().stroke(Theme.rule(scheme), lineWidth: Theme.Space.hairline))
            .foregroundStyle(Theme.ink(scheme))
        }
        .buttonStyle(.plain)
    }
}

/// An article rendered in its gender colour, over its gender's rule cue.
///
/// Verbs and prepositions pass `gender: nil` and render in plain ink with a
/// neutral underline, which is what makes the coloured nouns read as a
/// category rather than decoration.
struct GenderArticle: View {
    @Environment(\.colorScheme) private var scheme
    let article: String
    let gender: Gender?

    var body: some View {
        Text(article)
            .foregroundStyle(gender?.color(scheme) ?? Theme.ink(scheme))
            .overlay(alignment: .bottom) { cue.offset(y: 6) }
            .padding(.bottom, 6)
    }

    @ViewBuilder private var cue: some View {
        let color = gender?.color(scheme) ?? Theme.ink3(scheme)
        switch gender?.cue {
        case .double:
            VStack(spacing: 2) {
                Rectangle().fill(color).frame(height: 3)
                Rectangle().fill(color).frame(height: 3)
            }
        case .dashed:
            Rectangle()
                .fill(.clear)
                .frame(height: 5)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 5, dash: [7, 5]))
                        .foregroundStyle(color)
                        .clipped()
                )
        default:
            Rectangle().fill(color).frame(height: 5)
        }
    }
}

/// The session progress rail: one bar per queued card. It grows as misses
/// are reinserted, so failing visibly lengthens the session.
struct ProgressRail: View {
    @Environment(\.colorScheme) private var scheme
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    .fill(color(for: index))
                    .frame(height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: total)
    }

    private func color(for index: Int) -> Color {
        if index < current { Theme.ink(scheme) }
        else if index == current { Theme.ink2(scheme) }
        else { Theme.hair(scheme) }
    }
}

/// A home-screen figure with its caption.
struct StatBlock: View {
    @Environment(\.colorScheme) private var scheme
    let value: String
    var suffix: String?
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(TypeScale.stat).foregroundStyle(Theme.ink(scheme))
                if let suffix {
                    Text(suffix).font(TypeScale.secondary).foregroundStyle(Theme.ink3(scheme))
                }
            }
            Text(caption).labelStyle(Theme.ink3(scheme))
        }
    }
}
