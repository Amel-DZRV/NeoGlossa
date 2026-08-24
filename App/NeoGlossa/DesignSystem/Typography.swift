import SwiftUI

/// Archivo 400 / 800, tracking tightening as size grows.
///
/// Falls back to the system face if Archivo is not bundled, so the app still
/// renders correctly before the font is added.
public enum TypeScale {
    private static func archivo(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom("Archivo", size: size).weight(weight)
    }

    /// 46 / 800 / -.03em — the revealed answer.
    public static let answer = archivo(46, .heavy)
    /// 44 / 800 — the prompt on the front of the card.
    public static let prompt = archivo(44, .heavy)
    /// 40 / 800 — the home screen statistics.
    public static let stat = archivo(40, .heavy)
    /// 19 / 400 — the German example sentence.
    public static let exampleDE = archivo(19, .regular)
    /// 18 / 800 — button labels.
    public static let action = archivo(18, .heavy)
    /// 14 — the English translation and other secondary text.
    public static let secondary = archivo(14, .regular)
    /// 11 / .14em / uppercase — every small label.
    public static let label = archivo(11, .heavy)
}

extension View {
    /// The uppercase, wide-tracked label used throughout.
    func labelStyle(_ color: Color) -> some View {
        self.font(TypeScale.label)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(color)
    }

    func answerTracking() -> some View { self.tracking(-1.4) }
}
