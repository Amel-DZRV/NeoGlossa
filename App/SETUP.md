# Building NeoGlossa in Xcode

The app sources are here, but there is no `.xcodeproj` in the repository. A
project file is thousands of lines of generated UUIDs that cannot be
validated without Xcode, and a broken one is harder to fix than a five
minute setup. These steps produce the same result reliably.

## 1. Create the project

Xcode → File → New → Project → iOS → App.

| Field | Value |
|---|---|
| Product Name | `NeoGlossa` |
| Interface | SwiftUI |
| Language | Swift |
| Storage | None |
| Minimum Deployment | iOS 18.0 or later |

Save it at the repository root so the folder sits next to `App/` and
`Packages/`.

## 2. Add the core package

File → Add Package Dependencies → Add Local… → select
`Packages/NeoGlossaCore`. Then in the target's **General → Frameworks,
Libraries and Embedded Content**, add `NeoGlossaCore`.

## 3. Add the sources

Delete the generated `ContentView.swift` and `NeoGlossaApp.swift`, then drag
these folders from `App/NeoGlossa/` into the project, choosing **Create
groups**:

- `App/` `DesignSystem/` `Models/` `Screens/` `Services/`

## 4. Add the lexicon

Drag `App/NeoGlossa/Resources/lexicon.sqlite` in, with **Copy items if
needed** ticked, and confirm it appears under **Build Phases → Copy Bundle
Resources**. Without this the app traps on launch with "lexicon.sqlite is
missing from the bundle", which is deliberate — a silent empty deck would be
worse.

## 5. Permissions for speech input

In the target's **Info** tab add two keys, or dictation crashes on first use:

| Key | Value |
|---|---|
| `NSMicrophoneUsageDescription` | Answer cards by speaking. |
| `NSSpeechRecognitionUsageDescription` | Recognises German answers on device. |

Recognition is on-device only (`requiresOnDeviceRecognition = true`), so the
app still makes no network calls. iOS may need to download the German
offline model once, under Settings → General → Keyboard → Dictation.

## 6. Optional: the Archivo font

The type scale asks for Archivo and falls back to the system face if it is
absent, so this is optional. To add it: download the family from Google
Fonts, drag the `.ttf` files in, and list them under `UIAppFonts` in the
target's Info tab.

## 7. Run

Select your iPhone and run. On first launch the store is empty, so Start
introduces the first batch of new cards and goes straight into a session.

## Tests

`Packages/NeoGlossaCore/Tests` holds 40 tests covering the scheduler, the
queue builder and grading. Product → Test runs them. They are the parts that
fail silently — a wrong FSRS interval does not crash, it just schedules
badly for months.

## If progress ever disappears

Every session end writes `neoglossa-backup.json` to the app's Documents
directory (reachable in the Files app under *On My iPhone → NeoGlossa*). It
holds the full scheduler state for every card. `Backup.restore(into:)` reads
it back. This exists because a SwiftData migration going wrong is the one
failure in this app that is not fixable after the fact.
