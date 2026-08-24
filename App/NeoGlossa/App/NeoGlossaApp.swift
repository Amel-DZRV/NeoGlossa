import SwiftUI
import SwiftData
import NeoGlossaCore

@main
struct NeoGlossaApp: App {
    let container: ModelContainer
    let lexicon: Lexicon

    init() {
        do {
            container = try ModelContainer(
                for: CardRecord.self, ReviewLogEntry.self, ErrorLogEntry.self, StudyMeta.self
            )
        } catch {
            fatalError("Could not open the store: \(error)")
        }

        guard let path = Bundle.main.path(forResource: "lexicon", ofType: "sqlite"),
              let opened = try? Lexicon(path: path)
        else {
            fatalError("lexicon.sqlite is missing from the bundle")
        }
        lexicon = opened
    }

    var body: some Scene {
        WindowGroup {
            RootView(lexicon: lexicon)
                .modelContainer(container)
                .preferredColorScheme(nil)  // follow the system
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let lexicon: Lexicon

    @State private var store: StudyStore?
    @State private var screen: Screen = .home

    enum Screen { case home, session, summary }

    var body: some View {
        ZStack {
            Theme.bg(scheme).ignoresSafeArea()

            if let store {
                switch screen {
                case .home:
                    HomeView(store: store) {
                        store.startSession()
                        screen = store.queue.isEmpty ? .summary : .session
                    }
                case .session:
                    ReviewView(store: store) {
                        Backup.write(context: context)
                        screen = .summary
                    }
                case .summary:
                    SummaryView(store: store) { screen = .home }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if store == nil {
                store = StudyStore(context: context, lexicon: lexicon)
            }
        }
    }
}
