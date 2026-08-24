import SwiftUI

/// Every colour in the app. Nothing outside this file names a hex value.
///
/// The palette is the Modernist design system's, adapted to a dark ground
/// with a light variant. Radius is 0 everywhere and is not a token, because
/// there is nothing to vary.
public enum Theme {

    // MARK: - Ground and ink

    public static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x161514) : Color(hex: 0xF3F2F2)
    }
    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x211F1E) : Color(hex: 0xE7E5E5)
    }
    public static func raise(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2B2827) : Color(hex: 0xDCD9D9)
    }
    public static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF6F4F3) : Color(hex: 0x201E1D)
    }
    public static func ink2(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(scheme == .dark ? 0.58 : 0.62)
    }
    public static func ink3(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(scheme == .dark ? 0.34 : 0.40)
    }
    public static func rule(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(scheme == .dark ? 0.22 : 0.30)
    }
    public static func hair(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(scheme == .dark ? 0.11 : 0.14)
    }

    // MARK: - Accent

    /// Red means exactly one thing: wrong. Plus the two destructive-adjacent
    /// primaries, Again and Start. No gender is red, so colour never competes
    /// with the correctness signal.
    public static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xEC3013) : Color(hex: 0xDD2B0F)
    }
    public static func wrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xFF563C) : Color(hex: 0xC22A0F)
    }

    // MARK: - Spacing

    public enum Space {
        public static let gutter: CGFloat = 26
        public static let safeTop: CGFloat = 88
        public static let safeBottom: CGFloat = 46
        public static let xs: CGFloat = 8
        public static let s: CGFloat = 16
        public static let m: CGFloat = 24
        public static let l: CGFloat = 40
        public static let primaryActionHeight: CGFloat = 62
        public static let ratingHeight: CGFloat = 64
        public static let articleTargetHeight: CGFloat = 96
        public static let hairline: CGFloat = 1
        public static let ruleWidth: CGFloat = 2
    }
}

/// The three genders, their colours and their non-colour cues.
///
/// Blue / amber / violet: no red-green pair, so protanopia and deuteranopia
/// keep all three separable, and the rule cue underneath covers tritanopia,
/// where blue and violet converge. None of the three is red or green, so
/// none can be misread as right or wrong.
public enum Gender: String, CaseIterable, Sendable {
    case der, die, das

    public var label: String {
        switch self {
        case .der: "masculine"
        case .die: "feminine"
        case .das: "neuter"
        }
    }

    public func color(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.der, .dark): Color(hex: 0x6FA8FF)   // 7.7:1
        case (.der, _):     Color(hex: 0x1B5FCC)   // 5.4:1
        case (.die, .dark): Color(hex: 0xE3B341)   // 9.5:1
        case (.die, _):     Color(hex: 0x7A5A00)   // 5.8:1
        case (.das, .dark): Color(hex: 0xC79BF2)   // 8.2:1
        case (.das, _):     Color(hex: 0x6A3AB2)   // 6.6:1
        }
    }

    /// The rule drawn under the article, so the system survives greyscale
    /// and any form of colour blindness.
    public enum Cue { case solid, double, dashed }

    public var cue: Cue {
        switch self {
        case .der: .solid
        case .die: .double
        case .das: .dashed
        }
    }

    public init?(article: String?) {
        guard let article else { return nil }
        self.init(rawValue: article.lowercased())
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
