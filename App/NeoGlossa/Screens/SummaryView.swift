import SwiftUI
import SwiftData
import UIKit
import NeoGlossaCore

/// Only the misses. Not a summary of everything.
struct SummaryView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    let store: StudyStore
    let onDone: () -> Void

    @State private var copied = false

    private var misses: [StudyStore.Miss] { store.uniqueMisses }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session ended").labelStyle(Theme.ink3(scheme))
                .padding(.bottom, Theme.Space.m)

            Text(headline)
                .font(TypeScale.stat)
                .foregroundStyle(Theme.ink(scheme))
            Text(subline)
                .font(TypeScale.secondary)
                .foregroundStyle(Theme.ink2(scheme))
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(misses) { miss in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(miss.prompt).labelStyle(Theme.ink3(scheme))
                            HStack(spacing: 6) {
                                if let article = miss.article {
                                    GenderArticle(article: article, gender: Gender(article: article))
                                        .font(TypeScale.exampleDE)
                                }
                                Text(miss.word)
                                    .font(TypeScale.exampleDE)
                                    .foregroundStyle(Theme.ink(scheme))
                            }
                            Text(givenLine(miss))
                                .font(TypeScale.secondary)
                                .foregroundStyle(Theme.ink3(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Space.s)
                        Rectangle().fill(Theme.hair(scheme)).frame(height: 1)
                    }
                }
            }
            .padding(.top, Theme.Space.m)

            VStack(spacing: Theme.Space.xs) {
                PrimaryButton(
                    title: copied ? "Copied" : "Copy list",
                    trailing: "markdown",
                    isEnabled: !misses.isEmpty
                ) {
                    UIPasteboard.general.string = ErrorLogExport.markdown(for: misses)
                    copied = true
                }
                Button("Back to home", action: onDone)
                    .font(TypeScale.action)
                    .foregroundStyle(Theme.ink2(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.safeTop)
        .padding(.bottom, Theme.Space.safeBottom)
    }

    private var headline: String {
        if store.cardsSeen == 0 { return "Nothing due" }
        return misses.isEmpty
            ? "Nothing missed"
            : "\(misses.count) word\(misses.count == 1 ? "" : "s") missed"
    }

    private var subline: String {
        if store.cardsSeen == 0 {
            return "No cards are due today, and the daily budget is already spent."
        }
        return misses.isEmpty
            ? "All \(store.cardsSeen) answered on the first try."
            : "Only the misses are listed. \(store.cardsSeen) cards seen."
    }

    private func givenLine(_ miss: StudyStore.Miss) -> String {
        let base = "you said “\(miss.given)”"
        return miss.correctedLater ? base + " · second pass correct" : base
    }
}
