# NeoGlossa — Implementation Plan

Working title in the design canvas: **Artikel**. Target: iPhone-only SwiftUI app, iOS 26+,
fully offline, single user. Drills German nouns (word + gender + plural), irregular verbs
(Partizip II + auxiliary) and prepositions (governed case) with FSRS-5 spaced repetition.

Adjective endings are out of scope for v1.

Source documents:
- `GermanVocabAppBuildSpec.md` — product/build spec (behaviour, data, scheduler)
- `Artikel - German vocab app.dc.html` + `_ds/modernist-*` — design canvas and Modernist
  design system (tokens, type scale, motion, gender colour system)

> **Read §0 before starting.** The two documents disagree in five places. Those decisions
> gate work in Phase 1 and Phase 4 and should be settled before that code is written.

---

## 0. Open conflicts between spec and design — decide before coding

| # | Spec says | Design says | Impact | Recommendation |
|---|---|---|---|---|
| C1 | `prepCase` is a **three-button tap**, not typed (Task 2.1) | "Prepositions stay a text field, not case buttons"; demo accepts `genitiv`/`gen`/`+ genitiv` | Review screen + grading path | **Follow the design.** A text field keeps one input affordance across all card types and the accepted-answer array already handles the variants. Blocks Task 4.3. |
| C2 | `governedCase` ∈ {akkusativ, dativ, wechsel} (Task 1.7) | Demo card `wegen` → **Genitiv** | Dataset schema + CHECK constraint | **Add `genitiv`** to the enum. `wegen`, `während`, `trotz`, `wegen` appear at A2. Blocks Task 1.7. |
| C3 | A miss is graded `Again` and rescheduled by FSRS | "Again reinserts the card three positions ahead" — the miss re-enters the same session | Queue builder; interacts with sibling burying | **Follow the design**, implemented as FSRS relearning with a same-session learning step. Reinsertion is exempt from the 15-card separation rule (it is the *same* card, not a sibling). Blocks Task 3.5. |
| C4 | Export the error log as **markdown** for Obsidian | Summary screen offers "Copy list · plain text" (tab-separated) | Post-session screen | **Ship both.** Copy button emits a markdown table; the design's "plain text" label becomes "markdown". One line of code, satisfies the stated Obsidian workflow. |
| C5 | Flip ≈ 0.4 s `.easeInOut` | 560 ms `cubic-bezier(.22,.68,.16,1)`, perspective 0.28, no flip-back | Review screen animation | **Follow the design** — it is the more specified of the two. |

Two further gaps the design does not cover and that this plan fills:
- **`nounPlural` card** has no artboard. Reuses the noun layout; prompt is `der Termin`,
  expected `die Termine`, the plural article always renders in the `die` colour.
- **Settings screen** has no artboard. Build it plain, from Modernist components
  (`.field`, `.input`, `.seg`) — it is not a screen the user looks at twice.

---

## 1. Repository layout

```
NeoGlossa/
├── docs/
│   ├── IMPLEMENTATION_PLAN.md      # this file
│   ├── DESIGN.md                   # extracted tokens, type scale, motion spec
│   └── DATASET.md                  # provenance, parse rules, conflict log notes
├── tools/dataset/                  # Python — build-time only, never ships
│   ├── pyproject.toml
│   ├── src/neoglossa_dataset/
│   │   ├── acquire.py              # 1.1  fetch / parse Goethe lists
│   │   ├── parse.py                # 1.2  lemma → structured row
│   │   ├── plural.py               # 1.2  umlaut + suffix rules
│   │   ├── verify.py               # 1.3  kaikki.org cross-check
│   │   ├── glosses.py              # 1.4  English glosses
│   │   ├── cognates.py             # 1.5  Levenshtein + false-friend override
│   │   ├── examples.py             # 1.6  example sentences
│   │   ├── verbs_preps.py          # 1.7  verb + preposition tables
│   │   ├── emit.py                 # 1.8  → lexicon.sqlite
│   │   └── import_wordtreasury.py  # 1.9  optional warm start
│   ├── data/raw/                   # source PDFs / CSV, committed for audit
│   ├── data/review/                # conflicts.csv, unparsed.log, cognates.csv
│   └── tests/
├── Packages/
│   └── NeoGlossaCore/              # pure Swift package, no UIKit, fully testable
│       ├── Sources/NeoGlossaCore/
│       │   ├── FSRS/               # FSRS-5 implementation
│       │   ├── Cards/              # card types, generation, unlock rules
│       │   ├── Queue/              # queue builder, sibling burying
│       │   ├── Throttle/           # adaptive new-card throttle
│       │   ├── Grading/            # normalisation + comparison
│       │   └── Lexicon/            # read-only SQLite reader
│       └── Tests/NeoGlossaCoreTests/
├── App/
│   ├── NeoGlossa.xcodeproj
│   ├── NeoGlossa/
│   │   ├── App/                    # entry point, SwiftData container
│   │   ├── Models/                 # SwiftData @Model types
│   │   ├── DesignSystem/           # tokens, type scale, components
│   │   ├── Screens/                # Home, Review, Summary, Settings
│   │   ├── Speech/                 # SFSpeechRecognizer + fallback
│   │   ├── Intelligence/           # Foundation Models, gated
│   │   └── Resources/lexicon.sqlite
│   └── NeoGlossaUITests/
└── .github/workflows/ci.yml
```

Rationale for the split: `NeoGlossaCore` has no SwiftUI or SwiftData import, so the
scheduler and queue builder are testable with plain XCTest and no simulator. The spec
calls this out ("Phase 2 as a standalone Swift package with unit tests") and it is the
single highest-leverage structural decision here.

---

## Phase 1 — Dataset

**The dataset is the project's risk. It ships complete and verified before any app code.**
A verified CSV is useful on its own; a scheduler with no data is not.

### 1.1 Acquire the word lists
Search GitHub for parsed Goethe A1/A2 Wortlisten; evaluate quality before trusting any
repo (spot-check 30 entries against the official PDF). Fallback: user supplies the
official goethe.de PDFs, parse with `pdfplumber`.

**Done when:** raw CSV of every A1 and A2 entry exists in `data/raw/`, each row carrying
its original source line for audit.

### 1.2 Parse into structured rows
Emit `lemma, pos, gender, plural, cefr, englishGloss, sourceLine`.

Plural rules — suffix appended to lemma, umlaut applied to the **last** umlautable vowel
in the stem (`a→ä`, `o→ö`, `u→ü`, `au→äu`):

| Source | Plural |
|---|---|
| `der Abend, -e` | `Abende` |
| `die Mutter, ¨-` | `Mütter` |
| `das Mädchen, -` | `Mädchen` |
| `die Brille, -n` | `Brillen` |

Plural-only and singular-only entries are flagged and generate no plural card. Every line
that matches no known pattern is written to `data/review/unparsed.log`. **Nothing is
silently dropped.**

**Done when:** structured CSV emitted, unparsed-line count reported and reviewed.

### 1.3 Cross-verify against Wiktionary
Cross-check every noun's gender and plural against the kaikki.org German Wiktionary
extract. Agreement → `verified`. Disagreement → `data/review/conflicts.csv`. Missing →
`unverified`, keep the Goethe value.

**No auto-resolution.** The user reviews `conflicts.csv` by hand; expect under 50 rows.

**Done when:** `conflicts.csv` is reviewed and empty; every noun is `verified` or
explicitly accepted.

### 1.4 English glosses
Pull from the Wiktionary translations already in the kaikki extract. One to three words —
long glosses make grading ambiguous. Genuinely distinct senses store multiple accepted
answers; grading accepts any of them.

**Done when:** every lexeme has ≥1 gloss; multi-sense words carry all accepted answers.

### 1.5 Cognate flagging
Normalised Levenshtein distance between lemma and gloss below a threshold produces a
candidate set, then **manual review of that set** — automatic flagging alone is not safe.

Cognates ship with `nounRecognition` **suspended**; production still runs, because the
user still does not know the article.

A false-friend exception list overrides the flag and keeps both cards:
`das Gift` (poison), `bekommen` (receive), `der Chef` (boss), `das Handy` (mobile phone),
`sensibel` (sensitive), `eventuell` (possibly). Extend as found.

**Done when:** cognate list manually reviewed; false-friend override applied.

### 1.6 Example sentences
One sentence per lexeme plus English translation. A1/A2 vocabulary only, under 10 words,
target word in natural context. For nouns, prefer a **non-nominative** case — that is
where article knowledge is actually exercised (`Ich habe den Schlüssel im Büro vergessen`).

Sentences that must be authored are authored **at build time and reviewed**, never
generated on-device.

**Done when:** every lexeme has an example; a random sample of 50 is spot-checked.

### 1.7 Verbs and prepositions
Irregular and separable verbs store `partizipII`, `auxiliary` (haben/sein),
`präteritum3sg`, `isSeparable`. The auxiliary is not optional — `gefahren` alone is
useless; `ist` vs `hat` is what gets missed.

Prepositions store `governedCase`:
- **Dativ:** mit, nach, bei, von, zu, aus, seit, gegenüber
- **Akkusativ:** durch, für, gegen, ohne, um
- **Wechsel:** in, an, auf, über, unter, neben, zwischen, vor, hinter
- **Genitiv:** wegen, während, trotz *(per decision C2)*

**Done when:** both tables complete and verified.

### 1.8 Emit `lexicon.sqlite`
Read-only SQLite, well under 1 MB. Schema per the spec, with the C2 amendment:

```sql
CREATE TABLE lexeme (
  id            INTEGER PRIMARY KEY,
  lemma         TEXT NOT NULL,
  pos           TEXT NOT NULL,   -- noun | verb | preposition | other
  cefr          TEXT NOT NULL,   -- A1 | A2
  glosses       TEXT NOT NULL,   -- JSON array of accepted English answers
  exampleDE     TEXT NOT NULL,
  exampleEN     TEXT NOT NULL,
  isCognate     INTEGER NOT NULL DEFAULT 0,
  isFalseFriend INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE noun_data (
  lexemeId      INTEGER PRIMARY KEY REFERENCES lexeme(id),
  gender        TEXT NOT NULL,   -- der | die | das
  plural        TEXT,            -- NULL if no plural
  pluralPattern TEXT
);

CREATE TABLE verb_data (
  lexemeId       INTEGER PRIMARY KEY REFERENCES lexeme(id),
  partizipII     TEXT NOT NULL,
  auxiliary      TEXT NOT NULL,  -- haben | sein
  praeteritum3sg TEXT,
  isSeparable    INTEGER NOT NULL DEFAULT 0,
  isIrregular    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE prep_data (
  lexemeId     INTEGER PRIMARY KEY REFERENCES lexeme(id),
  governedCase TEXT NOT NULL     -- akkusativ | dativ | wechsel | genitiv
);
```

Add indexes on `lexeme(pos, cefr)` and `lexeme(lemma)`. Ship it `VACUUM`ed and opened
read-only from the app bundle.

**Done when:** file builds, opens, row counts match expectations, sample queries return
correct data.

### 1.9 WordTreasury import *(nice-to-have — does not block Phase 2)*
One-time importer: match existing words by lemma, carry usable review history as an FSRS
warm start, put words absent from the Goethe list into a `custom` table with the same
schema shape.

---

## Phase 2 — Design system in code

Runs in parallel with Phase 1; it has no dependency on the dataset.

### 2.1 Tokens
Port the canvas tokens to a Swift `Theme` with dark and light variants. Dark is the
default. Never hard-code a colour or spacing value outside this file.

| Role | Dark | Light |
|---|---|---|
| `bg` | `#161514` | `#f3f2f2` |
| `surface` | `#211F1E` | `#E7E5E5` |
| `raise` | `#2B2827` | `#DCD9D9` |
| `ink` | `#F6F4F3` | `#201E1D` |
| `ink2` | ink @ 58% | ink @ 62% |
| `ink3` | ink @ 34% | ink @ 40% |
| `rule` | ink @ 22% | ink @ 30% |
| `hair` | ink @ 11% | ink @ 14% |
| `accent` | `#EC3013` | `#DD2B0F` |
| `wrong` | `#FF563C` | `#C22A0F` |

### 2.2 The gender colour system
The single most important visual rule in the app. **Colour is never the only signal** —
each gender carries a rule cue drawn under the article.

| Gender | Dark | Light | Contrast | Rule cue |
|---|---|---|---|---|
| `der` (masc) | `#6FA8FF` | `#1B5FCC` | 7.7:1 / 5.4:1 | solid 4–5 px |
| `die` (fem) | `#E3B341` | `#7A5A00` | 9.5:1 / 5.8:1 | double 4–5 px |
| `das` (neut) | `#C79BF2` | `#6A3AB2` | 8.2:1 / 6.6:1 | dashed 4–5 px |

Blue / amber / violet — no red-green pair, so protanopia and deuteranopia keep all three
separable; the rule cue covers tritanopia, where blue and violet converge.

**Red is reserved for one meaning: wrong** (plus the two destructive-adjacent primaries,
Again and Start). No gender is red, so colour never competes with the correctness signal.
Correctness has its own vocabulary: hairline `✓` in plain ink, `✕` in accent red, always
paired with the word **Correct** / **Incorrect**.

Verbs and prepositions get **no colour at all** — their answer sits in plain ink with a
neutral `ink3` underline, which makes the coloured nouns read as a category rather than
decoration.

### 2.3 Type scale
Archivo 400 / 800, tracking tightens as size grows. Register the font; fall back to
`system-ui`.

| Role | Size / line / weight / tracking |
|---|---|
| Answer | 46 / 1.05 / 800 / −.03em |
| Prompt | 44 / 1.02 / 800 |
| Stat | 40 / 800 |
| Example DE | 19 / 1.35 / 400 |
| Action | 18 / 800 |
| Example EN, secondary | 14 |
| Label | 11 / .14em / uppercase |

### 2.4 Spacing, targets, components
4 pt base. Screen gutter 26. Safe top/bottom 88 / 46. Stack rhythm 8 · 16 · 24 · 40.
Primary action 60–64 tall. Rating button 64 × 110. `der/die/das` target 96 tall.
Hairline 1 px, rule 2 px. **Corner radius 0 everywhere** — this is not negotiable in
Modernist.

Everything is flush left — headings, copy, and labels inside wide buttons — **except** the
card prompt and revealed answer, which are centred. That is a deliberate, documented
deviation: a flashcard is read at arm's length and the eye should land in the same place
every time.

Build: `PrimaryButton`, `RatingButton`, `GenderArticle`, `Rule`, `Label`, `StatBlock`,
`ProgressRail`.

**Done when:** a token gallery screen renders every component in both themes, and the
gender ramps pass contrast checks at Dynamic Type XL.

---

## Phase 3 — Core engine (`NeoGlossaCore`)

Pure Swift package, no UI imports, unit-tested throughout. This is where the subtle bugs
live; the spec is explicit that the queue builder is the easiest thing to get wrong.

### 3.1 Card types

| Type | Prompt | Expected answer | Notes |
|---|---|---|---|
| `nounProduction` | "appointment" | `der Termin` | Article required |
| `nounRecognition` | `der Termin` | "appointment" | Suspended for cognates |
| `nounPlural` | `der Termin` | `die Termine` | Locked until parent matures |
| `verbPartizip` | "to become" | `ist geworden` | Auxiliary required |
| `prepCase` | "wegen" | `Genitiv` | Typed (decision C1) |

### 3.2 Card generation and unlock
On first import of a lexeme:
- Noun → `nounProduction` + `nounRecognition` (both new), plus `nounPlural` **locked**.
  `nounRecognition` is created **suspended** when `isCognate == 1 && isFalseFriend == 0`.
- Irregular verb → `verbPartizip`
- Preposition → `prepCase`

`nounPlural` unlocks when its parent `nounProduction` reaches **stability ≥ 21 days**. The
plural depends on knowing the gender; do not grade the plural before the gender is solid.

### 3.3 FSRS-5
Implement directly in Swift from the published FSRS-5 spec and default parameter set —
a few hundred lines, no dependency.

```swift
struct SchedulerState {
    var stability: Double
    var difficulty: Double
    var due: Date
    var lastReview: Date?
    var reps: Int
    var lapses: Int
    var state: CardState   // new | learning | review | relearning
}
```

Target retention 0.9, exposed as a setting, not hardcoded.

**Weekday shifting:** after FSRS returns a due date, roll it forward to the next weekday if
it lands on Saturday or Sunday. Without this, Monday becomes permanently ~2.4× heavier
than Thursday.

Validate against the reference FSRS test vectors before trusting any scheduling output.

### 3.4 Grading
Two paths that must never be confused:
- **Wrong → automatic `Again`.** No rating buttons. The user does not get to rate a miss.
- **Right → Hard / Good / Easy.** `Again` is not offered on a correct answer.

Normalisation before comparison, and nothing more: trim outer whitespace, collapse
internal whitespace runs, strip trailing `.`/`!`/`?`.

**Explicitly not normalised** — case (`termin` fails; German nouns are always capitalised
and drilling this is the point), umlauts (`Bucher` fails for `Bücher`; `ae`/`oe`/`ue` are
not accepted), article (`Termin` fails for `der Termin`).

`nounRecognition` accepts any gloss in the stored array, case-insensitively — it is
English, capitalisation carries no information there.

### 3.5 Queue builder with sibling burying
The problem: `EN → der Termin` immediately followed by `der Termin → EN` is not recall.
The answer is still in working memory. That is one long rep, not two.

1. **Introduction day.** When a noun is introduced only one of its two translation cards
   is due that day; the sibling is seeded due at +1 day. Both cards exist from day one —
   they just do not both appear on day one.
2. **Minimum separation: 15 cards** between translation siblings due the same day.
3. **Defer if it does not fit.** Too short a session pushes the second sibling to tomorrow.
4. **Plural siblings are exempt.** `nounProduction` and `nounPlural` may appear close
   together — the plural depends on the gender, so the pair reinforces rather than leaks.
   Flag this by card type.
5. **Same-card reinsertion is exempt** (decision C3): a missed card returns three positions
   ahead in the same session. It is the same card, not a sibling.

```
1. Collect due cards (excluding suspended and locked).
2. Shuffle.
3. Walk the list. If a card's translation sibling appeared within the
   last 15 slots, move it back 15 positions.
4. If it cannot fit in the session, defer to tomorrow.
5. Spread new cards evenly through the session — never front-load.
```

Step 5 matters: twenty new words in a block at the start is a wall; spread through, they
act as breaks between reviews. Do not sort by card type or lexeme — interleave nouns,
verbs and prepositions.

### 3.6 Adaptive new-card throttle
No hardcoded new-cards-per-day. One setting: **target daily minutes** (default 45).

```
1. Serve all due reviews first.
2. Maintain a rolling 14-day average of seconds-per-card.
3. remaining = targetSeconds − (dueReviewCount × avgSeconds)
4. newCards = clamp(remaining / 25, 0, dailyCap)
```

25 s is the assumed cost of a first exposure; refine from real data once it exists.

**Ramp cap:** weeks 1–2 → 15/day, weeks 3–4 → 10/day, week 5+ → 8/day. Week one at 25/day
feels effortless because there are no reviews yet; week five that same rate is 100+ minutes
daily and the user quits. The cap exists to prevent exactly that.

**Ordering:** A1 before A2, and A1+A2 finish entirely before any B1 content is considered.
Hard gate, not a setting.

**Known load spike:** plural cards unlock at 21 days stability, so they are invisible for
three weeks and then land. Expect daily load to rise ~40% around week four. The adaptive
throttle absorbs this by cutting new words — that is the correct trade, do not override it.

**Done when:** the full test checklist in §6 passes.

---

## Phase 4 — App

### 4.1 Stack
SwiftUI, iOS 26 minimum. **SwiftData** for user state (scheduler state, review log,
settings). **Bundled read-only SQLite** for the lexicon — never loaded into SwiftData, it
never changes. No network calls. No third-party dependencies unless justified.

SwiftData models: `CardRecord` (lexemeId, type, `SchedulerState`, suspended, locked),
`ReviewLogEntry` (cardId, timestamp, rating, given answer, elapsed ms), `ErrorLogEntry`,
`Settings` (targetMinutes, targetRetention, theme).

### 4.2 Home screen
Kicker (`GOETHE A2`), then three stats and one action. Sparse by design.
- **Learned** — cards with stability > 21 days, shown as `340 / 1,300 words learned`
- **Due today**
- **Streak** — weekday-aware; a skipped weekend does not break it
- **Start** — full-width, accent-filled, flush-left label with a trailing `→`

### 4.3 Review screen
Top: a **progress rail** of one bar per queued card (past = ink, current = ink2, upcoming =
hair) with a `3 / 6` counter. The rail grows as misses are reinserted — failing visibly
lengthens the session, which is honest.

**Front:** kind label (`noun` / `verb · past participle` / `preposition · case`), centred
prompt, hint line (`article + noun`), text field with inline mic button, mic hint, Submit.

**Back:** verdict row (`✓ Correct` / `✕ Incorrect` plus the user's answer in quotes), the
answer with the article colour-coded and rule-cued by gender, gender label
(`masculine · der`), example DE with EN below, then the rating buttons — Hard / Good / Easy
each showing its projected interval (`1 D` / `4 D` / `9 D`) when correct, a single
full-width **Again** showing `3 cards from now` when wrong.

**The flip:** Y axis, 0° → 180°, one direction only. 560 ms `cubic-bezier(.22,.68,.16,1)` —
fast off the mark, long settle, so it reads as mass rather than a wipe. In SwiftUI:
`rotation3DEffect(.degrees(deg), axis: (0, 1, 0), perspective: 0.28)`, or
`.interpolatingSpring(stiffness: 90, damping: 15)` for the spring feel. No shadow, no
scale bump, no bounce past 180°. Both faces pre-rendered so nothing pops.

Advancing does **not** flip back: the card fades out over 170 ms, the deck resets to 0°,
the new front fades in.

**Reduce Motion:** cross-fade the faces in 120 ms, no rotation.

### 4.4 Speech input
`SFSpeechRecognizer(locale: "de-DE")` with `requiresOnDeviceRecognition = true`. Pass the
expected answer's article and lemma as `contextualStrings` to bias the decoder.

**Swallowed-article fallback — build this from day one, it is not an edge case:**
1. Transcribe. Show the transcript (`heard "Termin" · article missing`). Do not grade yet.
2. Transcript contains **no article** → do not fail it. Show three 96 pt-tall buttons —
   **der / die / das**, each in its gender colour with its rule cue. Grade the tap.
3. Transcript contains the **wrong** article → a genuine miss. Fail it.

Step 2 separates "the mic did not hear it" from "the user did not know it". Getting this
wrong makes speech mode unusable, and it will be blamed on the recogniser.

### 4.5 Post-session screen
Show **only the misses** — not a summary of everything. Per miss: prompt, correct answer
with the gender colouring, and what the user gave (`you said "Termin"`, plus
`· second pass correct` when the reinserted card was later answered right). No example
sentence here.

Headline reads `3 words missed`, sub-line `Only the misses are listed. 9 cards seen,
6 unique.` Nothing missed → `Nothing missed`.

Two actions: **Copy list** (markdown, per decision C4 — appends to the persistent error
log and copies for Obsidian) and **Back to home**.

### 4.6 Settings
Target daily minutes (default 45), target retention (default 0.9), theme (dark/light),
export full error log, and a debug section showing rolling average seconds-per-card and
today's throttle computation.

### 4.7 On-device LLM (Foundation Models)
The on-device model is ~3B parameters. It will get `der`/`die`/`das` wrong often enough to
matter, and that is precisely the content this app exists to teach.

**Permitted** — anywhere a mistake is cheap: post-reveal explanation on request ("why `dem`
here?"), extra example sentences on demand **clearly labelled as generated**, clustering the
error log into patterns.

**Forbidden** — anywhere a mistake teaches something false: gender, plural, Partizip II,
auxiliary, governed case. Every one of these comes from the bundled dataset. No exceptions.

Enforce structurally: the LLM layer is given no API that can return a gender, a plural, an
auxiliary or a case. It receives already-correct facts as context and may only produce
prose.

---

## 5. Build order

1. **Phase 1 fully, before any app code.** The dataset is the risk.
2. **Phase 2** in parallel — no dataset dependency.
3. **Phase 3** as a standalone package with unit tests. Test the queue builder and sibling
   burying properly.
4. **Phase 4** on top.
5. Phase 1.9 (WordTreasury import) last, if at all.

---

## 6. Test checklist

Ships as executable tests, not a manual list.

**Core (`NeoGlossaCoreTests`)**
- [ ] Sibling burying: translation siblings never appear within 15 cards of each other
- [ ] Introduction day: only one translation sibling appears
- [ ] Plural siblings are exempt from burying
- [ ] Same-card reinsertion after a miss is exempt from burying
- [ ] Plural card stays locked until parent stability ≥ 21 days
- [ ] Weekday shift: no card is ever due on a Saturday or Sunday
- [ ] New cards are spread evenly, never front-loaded
- [ ] Adaptive throttle yields zero new cards on a heavy review day
- [ ] Daily cap respects the 15 / 10 / 8 ramp by week
- [ ] A1 is exhausted before any A2 card is introduced
- [ ] FSRS-5 matches the reference test vectors
- [ ] `termin` fails, `Termin` fails, `der Termin` passes
- [ ] `Bucher` fails for `Bücher`; `ae`/`oe`/`ue` are not accepted
- [ ] `nounRecognition` accepts any stored gloss, case-insensitively
- [ ] Wrong answer offers no rating buttons; correct answer offers no Again

**Dataset (`tools/dataset/tests`)**
- [ ] Plural derivation covers every pattern in §1.2, umlaut on the last vowel
- [ ] `conflicts.csv` is empty at build time
- [ ] Every lexeme has ≥1 gloss and an example sentence
- [ ] Cognate recognition cards are suspended; false-friend ones are not
- [ ] Row counts match the reviewed source CSV — nothing dropped

**App**
- [ ] Full offline: airplane mode, everything works
- [ ] Speech with a swallowed article shows der/die/das, does not fail the card
- [ ] Speech with the wrong article fails the card
- [ ] Gender colours pass contrast in both themes at Dynamic Type XL
- [ ] Rule cues render, so the gender system survives greyscale
- [ ] Reduce Motion replaces the flip with a 120 ms cross-fade
- [ ] Error log export round-trips into Obsidian as valid markdown
