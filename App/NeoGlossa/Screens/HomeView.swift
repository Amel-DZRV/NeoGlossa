import SwiftUI
import NeoGlossaCore

/// Four elements, one action. Deliberately sparse.
struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    let store: StudyStore
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Goethe A1 · A2").labelStyle(Theme.ink3(scheme))

            Spacer()

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                StatBlock(
                    value: "\(store.learnedCount)",
                    suffix: "/ \(store.totalWordCount)",
                    caption: "words learned"
                )
                StatBlock(value: "\(store.dueTodayCount)", caption: "due today")
                StatBlock(value: "\(store.streak)", caption: "weekdays")
            }

            Spacer()

            PrimaryButton(
                title: "Start",
                trailing: "→",
                tint: Theme.accent(scheme),
                action: onStart
            )
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.safeTop)
        .padding(.bottom, Theme.Space.safeBottom)
    }
}
