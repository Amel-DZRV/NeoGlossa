import Foundation
import SwiftData

/// Renders misses as markdown, for the notes the user keeps in Obsidian.
///
/// The format matters because it mirrors a process already run by hand — a
/// table pastes straight into a note without reformatting.
enum ErrorLogExport {

    static func markdown(for misses: [StudyStore.Miss], on date: Date = Date()) -> String {
        guard !misses.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = ["## \(formatter.string(from: date)) — \(misses.count) missed", ""]
        lines.append("| Prompt | Correct | I said |")
        lines.append("| --- | --- | --- |")
        for miss in misses {
            let note = miss.correctedLater ? " _(second pass correct)_" : ""
            lines.append("| \(escape(miss.prompt)) | \(escape(miss.word)) | \(escape(miss.given))\(note) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The whole persisted log, newest day first.
    static func fullLog(context: ModelContext) -> String {
        let entries = (try? context.fetch(
            FetchDescriptor<ErrorLogEntry>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        )) ?? []
        guard !entries.isEmpty else { return "# NeoGlossa error log\n\nNothing logged yet.\n" }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        var output = ["# NeoGlossa error log", ""]
        var currentDay: Date?
        for entry in entries {
            let day = calendar.startOfDay(for: entry.occurredAt)
            if day != currentDay {
                currentDay = day
                output.append("")
                output.append("## \(formatter.string(from: day))")
                output.append("")
                output.append("| Prompt | Correct | I said |")
                output.append("| --- | --- | --- |")
            }
            output.append(
                "| \(escape(entry.prompt)) | \(escape(entry.correctAnswer)) | \(escape(entry.given)) |"
            )
        }
        return output.joined(separator: "\n") + "\n"
    }

    /// A pipe inside a cell would break the table.
    private static func escape(_ text: String) -> String {
        text.isEmpty ? "—" : text.replacingOccurrences(of: "|", with: "\\|")
    }
}
