# Antinote 2.x: visual UI reference for Jotter

This is a pixel-level reference for rebuilding the Antinote (antinote.io, v2.0–2.1.x, macOS) interface in Jotter.
It covers what things look like. Behaviour belongs in the per-kit specs (`editorkit.md`, `shellkit.md`, ...).

> `ui-parity.md` has the values read from the shipping app's binary. Where the two disagree, `ui-parity.md` wins.

## Evidence tags

- **[V]** Verified from an image or video frame: antinote.io feature videos, changelog images, theme screenshots,
  the official 2.0 YouTube video (`-tyOgBTZbxw`), or bundle images rendered from `Assets.car`.
- **[S]** From the app bundle: `Localizable.strings`, binary strings, class/ivar names, `Assets.car` names. Also
  from antinote.io's own source: the theme-maker JS and the user-manual text.
- **[U]** Unverified inference. Treat as a sensible default and adjust if better evidence turns up.

### How measurements were made

The marketing clips are screen recordings of the real app at a fixed zoom. Scale came from the macOS traffic
lights. In `hotkey.mp4` their 20 pt centre-to-centre spacing measures 56 px, so 1 pt ≈ 2.8 px. In the
1888×2160 clips (`math`, `swipe`, `checklist`, `conversions`, `plaintext`) the monospace advance is exactly 2× the
hotkey clip, so 1 pt ≈ 5.6 px. A 2× retina changelog screenshot (`comments.png`) gave the same numbers within
±1 pt. All point values below are derived this way and are **±1 pt**.

Some marketing clips predate 2.0: the 1.x bottom bar in `export.mp4`, and a glyph set whose zero has no slash.
Where 1.x and 2.x differ, this doc says so.

---

## 0. Design tokens (the theme model)

Every colour in the UI comes from one theme object. The JSON keys come from the bundle (`ThemeHexJSON`,
`ColorTheme`) and from the theme-maker source **[S]**. The **default light and dark values** are the theme-maker
base themes **[S]**. Sampling the light-theme marketing videos returned the same light values **[V]** (`math`
keyword (5,72,107) ≈ `#0B486B`, results (82,158,46) ≈ `#4DA425`, list keyword (174,89,210) ≈ `#C14DFB`, text
(66,61,58) ≈ `#473F37` after antialiasing).

| Key | Theme-maker meaning (verbatim) [S] | Default light | Default dark |
|---|---|---|---|
| `background` | Main background color | `#FFFFFF` | `#2A2626` |
| `backgroundFade` | For inline code and code blocks | `#ECECEC` | `#302F2F` |
| `typeMain` | Primary text color for content | `#473F37` | `#EBE3DB` |
| `typeSubtle` | Hyperlinks | `#1F4F79` | `#B2E2EC` |
| `typeSubtlePlus` | Shortened hyperlinks | `#085EA3` | `#97DDD6` |
| `typeHighlight` | Highlighted text background, scrollbar color | `#FFEBCF` | `#746550` |
| `typeLight` | Checked items, strikethrough text, search secondary, UI Button click, etc. | `#B2B2B2` | `#7B7B7B` |
| `typeSuperlight` | Check '/x' tag, hyperlink underline, etc. | `#DAD9D7` | `#524D4D` |
| `typeHyperLight` | UI Button hover, search bar background, etc. | `#F2F2F2` | `#343434` |
| `typeReverse` | Text color in message pills and other opposite backgrounds | `#FFFFFF` | `#2A2626` |
| `accent1Main` | 'math' keyword, text cursor/caret, success pills, H1, stopwatch milestone | `#0B486B` | `#58C2FF` |
| `accent1Secondary` | Variable assignment, H2 | `#0F8C8C` | `#0F8C8C` |
| `accent1Tertiary` | Variable use, H3 | `#417863` | `#73B0B0` |
| `accent2Main` | 'list' keyword, Variable colon, timer time, checkbox hover | `#C14DFB` | `#DA93FE` |
| `accent2Secondary` | Checkbox checked | `#C14DFB` | `#C14DFB` |
| `accent3Main` | Pinned button, 'sum' keyword, math total, 'paste' keyword, pomo break time, pomo cycle count | `#4DA425` | `#39DB62` |
| `accent3Secondary` | Pinned button hover, sum total | `#3C7F1C` | `#469521` |
| `accent4Main` | Warning pills, 'average' keyword, 'code' keyword, 'timer' keyword | `#FF9E3C` | `#FF9E3C` |
| `accent4Secondary` | Average total | `#CE741A` | `#CE741A` |
| `accent5Main` | Error pills, 'count' keyword | `#FF3B30` | `#FF7C75` |
| `accent5Secondary` | Count total | `#AC2E27` | `#C95B55` |
| `gridSuperlight` | Subtle grid lines | `#D9EEFA` | `#303336` |
| `gridClear` | Clear grid lines | `#CBE1ED` | `#404448` |
| `gridBold` | Bold grid lines | `#ABCBDD` | `#575B5F` |

Each theme also has `name` (string) and `isDarkTheme` (bool) **[S]**. A theme file is that flat JSON object. The
theme maker downloads it as `<name lowercased, spaces→->.json` **[S]**.

In the recordings the window background is `#FDFDFD` rather than pure `#FFFFFF`. That is probably video encoding or
a paper overlay **[V]**, so use the token value.

### Typography tokens

- **Editor font: Menlo** by default **[S]**. The `MiscPreferences` defaults block reads `checkbox`, `keep`, `Menlo`,
  `fontFamily` in that order. The user can pick any installed family under Settings › Editor › Typography &
  language (beta) **[S]** (`availableFontFamilies`).
- Code fonts are separate: `codeFont`, `boldCodeFont`, `italicCodeFont` (Highlightr) **[S]**.
- Size presets are **XS | S | M | L | XL** plus a "Double font size" toggle, and ⌘+/⌘− step through them **[S]**.
  In the default recordings the monospace advance is **8.1–8.45 pt**, which with Menlo's 0.602 em advance means
  **M ≈ 13.5–14 pt** **[V]**. Suggested ladder: XS 11, S 12.5, M 14, L 16, XL 18 pt **[U]**.
- **Line pitch ≈ 21.8–23 pt at M**, about **1.6× font size** **[V]**. The 1888 px clips measure 122 px per line at
  5.6 px/pt, and `comments.png` measures 46 px at 2×.
- UI chrome text (settings, bottom-bar date, search meta, alerts) uses the system font, SF Pro **[V]**. The
  bottom-bar date is about 11–12 pt regular in `typeLight` **[V]**.
- Message pills and link tooltips use the editor monospace in bold at about 11 pt **[V]**.
- Other font identifiers in the binary: `monoFont`, `monoFontSmall`, `monoFontTitle` **[S]**.

### Message pills ("toasts")

Class `PersistentPillManager`: `message`, `showMessage`, `messageType` **[S]**.

- **Shape** **[V]**: a fully rounded capsule (radius = height / 2), centred horizontally, bottom edge about
  **20 pt** above the window bottom. Height ≈ **20 pt**, horizontal padding ≈ 12 pt. Width hugs the text: "Empty
  note deleted" ≈ 133 pt; the 2-line "Markdown removed from pasted content.\nChange in settings." ≈ 64% of the
  window width.
- **Text** **[V]**: bold monospace, about 11 pt, `typeReverse`, left-aligned when on 2 lines.
- **Colour by type** **[V][S]**:
  - Neutral/info ("Empty note deleted", "Timer paused", "Timer restarted", "Markdown removed…"): `typeMain`
    fill, measured `#453D35`.
  - Success ("Stopwatch started", "25/5 Pomodoro started", "Extracted text.", "AutoPasting clipboard...", "Line
    converted to uppercase."): `accent1Main` fill (navy).
  - Warning: `accent4Main`. Error: `accent5Main` (theme-maker preview) **[S]**.
- **Animation** **[V]**: fades in from a pale `typeHyperLight` capsule to full colour over ~150 ms, holds about
  2–2.5 s, then fades out over ~300 ms through grey to nothing. There is no vertical slide.

---

## 1. Main note window

### Size and frame

- **Default content size ≈ 337 × 386 pt**, aspect ≈ 0.873 **[V]**. Three sources agree: the recordings, the
  "Dock" and "Pseudo menu bar" mode images on antinote.io (both 0.874), and the translucency clip (0.875). The
  window is resizable; changelog screenshots show it at about 400–560 pt wide **[V]**.
- **Corners**: standard macOS window rounding, about 10 pt on Sequoia, larger on Tahoe **[V approx.]**.
  **Shadow**: the standard window shadow **[V]**.
- **Chrome**: no visible title bar and no title text. The note fills the window edge to edge, and the top bar
  floats over the note **[V]**. Classes: `CustomTitleBarView`, `WindowTopBar` (`buttonVisibilityState`,
  `isHovered`), `WindowButtonCustomizer`, `MainWindowDelegate` **[S]**. Build it as a full-size-content-view
  window with a transparent, hidden title and hidden traffic lights until hover **[U, implementation]**.

### Top bar (revealed on hover)

The top bar is hidden at rest. Moving the mouse into the top strip of the window fades it in **[V]** (hotkey
and translucency clips). Onboarding copy: "Or mouse over the top part of Antinote to click cool sci-fi buttons."
**[S]** Setting: `showTopBarUI` **[S]**.

- **Height ≈ 34 pt** (icon row centred about 17 pt from the window top) **[V]**. It overlaps the note's first line
  area. In the translucency clip the bar sits just above the keyword line.
- **Background**: transparent over the note on Sequoia. With translucency on macOS 26 it is a Liquid Glass strip,
  or solid if "Use solid colors for top and bottom bars when translucent" is on **[S]**. Buttons use
  `ButtonGlassBackgroundView : NSGlassEffectView` **[S]**.

Contents, left to right **[V]** (positions are icon centres from the window edge):

| # | Element | x (pt) | Asset [S] | Glyph [V] | Suggested SF Symbol |
|---|---|---|---|---|---|
| 1–3 | Traffic lights (close, minimise, zoom) | 13, 33, 53 | system | standard, ~12 pt diameter, 20 pt pitch | system |
| 4 | Settings | ~81 | `IconSettings` | three horizontal sliders (knobs at different x) plus a tiny sparkle dot | `slider.horizontal.3` |
| 5 | Search | ~110 | `IconSearch` | magnifier whose lens is a ringed planet (Saturn-style ellipse), plus a sparkle | `magnifyingglass` |
| — | flexible space | | | | |
| 6 | New note | right − 52 | `IconNew` | rounded square with a diagonal "pen" stroke from centre to the top-right, plus a sparkle star | `square.and.pencil` |
| 7 | Pin | right − 24 | `IconPin` | circle on a short stick over a baseline (a pushpin seen from the side) with a sparkle | `pin` |

Selectors on `CustomTitleBarView` confirm the buttons: `settingsButtonClicked`, `searchButtonClicked`,
`newButtonClicked`, `pinButtonClicked` **[S]**.

- **Icon style** **[V]**: a custom 30×30 pt template drawn at about 12 pt glyph size, line weight ~1.5 pt, rounded
  caps. Every icon carries a small "sparkle" dot or star, which is the brand's "sci-fi" motif. Tint ≈ `#5B5B5B` in
  the light theme, roughly `typeMain` at 75% opacity **[V]**. Hit target about 26×26 pt **[U]**.
- **States** (`CustomButton`: `buttonHoverBgColor`, `buttonClickBgColor`, `isPinButton`, `isPinned`) **[S]**:
  - Hover: rounded-rect background `typeHyperLight`, radius about 6 pt **[V]** (export button in `export.mp4`).
  - Pressed: background `typeLight` (theme-maker text "UI Button click") **[S]**.
  - Pinned: pin icon tinted `accent3Main`; hover while pinned uses `accent3Secondary` **[S]**.
- **Animation**: opacity 0 → 1 over ~200 ms on enter and back on exit. The traffic lights fade with the bar
  **[V]** (they appear and disappear together).

### Bottom bar (revealed on hover)

Setting `showBottomBarUI` **[S]**. It appears on hover near the bottom edge **[V]** (`export.mp4`, a 1.x build).

- **Layout** **[V]**: height about 30 pt, with icons at about 12 pt from the window bottom.
  - Left: one action icon. In 1.x this was a broken "X" of four diagonal ticks around a centre dot, the delete
    action.
  - Centre: the note date, e.g. "Jan 23, 2025", in `typeLight` SF Pro at about 12 pt.
  - Right, at about 28 pt spacing: **Previous**, **Next**, **Front**, **Export**.
- **2.x assets** **[S]** (rendered from `Assets.car` **[V]**):
  - `IconPrevious`: ◁ pointing left, a vertical bar to its right, a sparkle dot top-left.
  - `IconNext`: a vertical bar with ▷ to its right, a sparkle dot bottom-left.
  - `IconFront`: a horizontal line crossing two vertical bars into ▷ ("jump to latest").
  - `IconPromote`: a looping curved arrow from a small circle into ▷ with a sparkle.
  - `IconDelete`: a trash can with a lid handle and three vertical slots.
  - `IconExport`: ▲ on a stem rising out of a rounded box.
  - `IconImage`: a photo frame with mountains.
  - SF Symbol stand-ins: `backward.end`, `forward.end`, `forward.end.alt`, `arrow.uturn.up`, `trash`,
    `square.and.arrow.up`, `photo`.
- **Date text**: "Show note modified/created time" and "Show the note creation date" **[S]**. 2.0 added "timestamp
  in the bottom bar" **[S]**.
- **Note-position indicator**: the "Show note count" preference (`showNoteCountStorage`) shows text like **"14 of
  18"** **[S]** ('e.g. "14 of 18".'). Place it in the bottom bar next to the date, in `typeLight` **[U]**.
- **Latest-note indicator**: "Show latest-note indicator — Marks the most recent note on the bottom right."
  **[S]** Draw it as a small `accent1Main` dot (~5 pt) at the bottom-right corner, inset 10 pt, visible only on
  the front note **[U]**.

---

## 2. Editor

### Text area

- **Font**: Menlo, about 14 pt (M), regular, `typeMain` **[S][V]**. Line pitch ≈ 22 pt (~1.6×). Paragraphs are
  separated only by empty lines. There is no extra paragraph spacing outside lists **[V]**.
- **Insets** **[V]**: left/right text inset **44 pt**, which leaves about 5.4 monospace advances of gutter on the
  left; the gutter holds checkboxes and timers. The first line's cap-top sits about **37 pt** below the window top.
  The right inset matches the left (the wrap width in the clips is about 31 characters in a 337 pt window).
  > Note: `editorkit.md` currently specifies 28 pt sides and 22 pt top. Antinote measures about 44 / 37.
- **Wrapping**: soft wrap at the container width. Wrapped lines align with the text start, not with list markers
  **[V]**.
- **Caret** **[V]**:
  - Colour `accent1Main`. Width ≈ **2 pt** with rounded ends.
  - Height ≈ the full line box (~1.25× the cap height). It extends above the ascenders and below the descenders.
  - Blinks with the system timing. `drawInsertionPointInRect` is overridden **[S]**.
  - Vertical nudge settings: "Caret height offset" and "Caret height offset in lists" **[S]**.
- **Selection**: `typeHighlight` background (light theme `#FFEBCF`, peach), not the system accent. The fill covers
  the full line box with square corners. ⌘A shows a solid peach block over the whole text **[V]**.
- **Scrollbar**: a thin rounded bar about **3 pt** wide in `typeHighlight` near the right edge. It shows only while
  content overflows or while scrolling **[V]** (`swipe.mp4`).
- **Empty new note**: a blank page with the caret at the first-line origin **[V]**.

### First-line keyword

- A keyword on line 1 turns on a mode: `list`, `math`, `sum`, `avg`, `count`, `code` **[S]**. `paste` and `timer`
  are commands that work on any line **[S]**.
- **Styling** **[V][S]**: only the keyword word is coloured, same weight and size as the body. An optional
  `: Title` follows: the colon and the title stay `typeMain`. Examples: "`math`: SpaceGarden beds",
  "`list`: My groceries".
- **Keyword colours**:

  | Keyword | Colour |
  |---|---|
  | math | `accent1Main` |
  | list | `accent2Main` |
  | sum | `accent3Main` |
  | paste | `accent3Main` |
  | avg | `accent4Main` |
  | code | `accent4Main` |
  | timer | `accent4Main` |
  | count | `accent5Main` |

- A `timer …` command line is coloured `accent4Main` in full while being typed (e.g. "timer 0.2 .1") **[V]**.
- Custom keywords are allowed. Multiple triggers map to one main keyword **[S]**.

### Checkboxes (list keyword and inline `[]` / `- [ ]`)

Classes `CheckboxAttachmentManager`, `ChecklistManager`, `ChecklistItem` (`verticalPosition`, `indentOffset`,
`isHidden`) **[S]**.

- **Box** **[V]**: a square of **12.5 pt** outlined in `typeMain`, stroke ≈ **1.4 pt**, corner radius ≈ 2 pt.
  Its left edge sits at **20.5 pt** from the window edge, so it lives in the left gutter. Text stays at the 44 pt
  inset, giving a ~11 pt gap between box and text. The box is vertically centred on the item's first line.
- **Hover**: stroke turns `accent2Main` **[S]**.
- **Checked** **[V]**: box stroke and checkmark in `accent2Secondary` at reduced opacity (measured lavender
  `#D0AFD1` on white). The checkmark is a thin ✓ inside the box. The item text gets a strikethrough and turns
  `typeLight` (`#B2B2B2`), and the strike line uses the same colour.
- **The `/x` check trigger**: typing `/x` at the end of a line checks the item. The `/x` stays visible, drawn in
  `typeSuperlight` after a space **[V]** (`checklist.mp4`: "forget to SEAL) /x"). In 2.x the trigger "disappears
  as you type it" **[S]** (user manual). Implement the 2.x behaviour and keep the theme-preview style ("/x" in
  `typeSuperlight`) for legacy notes **[U]**.
- **Item spacing (list mode)** **[V]**: wrapped continuation lines inside one item use about 19 pt line pitch.
  Items are separated by about **8 pt extra**. "Line spacing for lists when using lined paper differ than when
  using blank paper." **[S]**
- **Headers inside lists**: `# Monday` renders bold in `accent1Main` with the `#` kept visible **[V]**
  (`markdown.png`). The line gets no checkbox, and a blank line precedes it.
- **Comments** (`// Drinks`): italic `typeLight`, no checkbox **[V]**.
- **Optional list title** "list: Optional title" sits on line 1 **[S]**.
- **When an item is checked**: "Stays in place | Moves to the bottom | Is deleted" **[S]**.
- **Default list style**: Checkboxes | Bullets | Numbered **[S]**.

### Bullets and numbered lists (inline, 2.0+)

- `- ` becomes a bullet glyph • and `1. ` becomes a number. Markers are drawn in the gutter like the checkboxes and
  the marker characters are hidden ("Inline checkbox, bullet and numbering markers are hidden in the note") **[S]**.
  In the 2.0 video, bullets show as small filled dots and numbers as "1." / "2." in `typeMain` **[V]**.
- Nested numbering runs **1. → a. → i.** **[S]**. Indent step is one tab ≈ 4 monospace advances, about 32 pt
  **[U]**.
- Shortcuts: ⌘⇧M cycles checkbox/bullet/number and ⌘⇧K checks off the current line **[S]**.

### Math notes

- **Results appear inline, right after `=`**, on the same line **[V]**. They are not right-aligned in a column.
  - Format: a space, then the result in `accent3Main`, e.g. `12 beds x 8 plants = 96.00`.
  - Two decimals by default ("Number of significant digits 0-7", thousands separator on: "1,904.00") **[V][S]**.
  - Long expressions wrap and the result follows on the wrapped line **[V]**.
- **Conversions**: the result carries its unit in `accent3Main`, e.g. "= 107.83 km", "= 24.25 L",
  "= 2' 6 11/16\"", "= 218.07 USD" **[V]**.
- **Variables** **[V]**: in `name: value`, the name is `accent1Secondary` (teal) and the colon is `accent2Main`
  (pink/purple). Later uses of the variable are `accent1Tertiary` (muted green-teal).
- Results are read-only: "Calculated results can't be edited." / "Prevent editing answers in math mode" **[S]**.
- "Previous answer word" setting (`ansVariableWord`) **[S]**.

### Sum / Avg / Count summaries

- **sum** **[V]** (`comments.png`): the note ends with a blank line, then a generated summary line `Total: $40`
  drawn in `accent3Secondary`. The caret can sit right after it, but the line is computed and read-only.
- **avg**: same pattern in `accent4Secondary` **[S]**. The label is likely "Average:" **[U]**.
- **count**: summary in `accent5Secondary` **[S]**. It reports items, words and characters plus reading ease and
  grade level (user manual) **[S]**. Exact label layout is **[U]**.
- `//` comment lines are excluded from all of these and drawn italic in `typeLight` **[V]**.

### Shortened links ("antilinks")

Class `AntilinkManager` **[S]**.

- **Display** **[V]**: `+docs.google.com/...fotien/+`, meaning a "+" prefix, the host, "/...", the last ~6 path
  characters, then "+".
  - Colour `typeSubtlePlus`, with a **dotted underline** in `typeSuperlight` (dots ~1 pt, gap ~2 pt, 2 pt below
    the baseline).
  - A full (expanded) link uses `typeSubtle` with the same underline.
  - Duplicate URLs get a "[#]" suffix **[S]**.
- **Hover tooltip** **[V]**: a rounded rectangle (~6 pt radius) filled with `typeLight` grey at ~90%, about 8 pt
  inside padding, white bold monospace at ~10 pt. It shows the full URL on 1–2 lines, then
  `⌘+Click to open | ⌘⇧+Click to expand.` It appears below the link, right-aligned to the hover point.
- **Behaviour**: links shorten only after the caret leaves them **[S]**. ⌘⇧-click expands a link, and the
  expanded text wraps across lines **[V]**. Edit blocks show "Cannot edit within shortened links. Expand before
  editing." **[S]**

### Code notes and inline code

- **The `code` keyword**: `code: bash` (keyword `accent4Main`, colon and language `typeMain`). The body is
  syntax-highlighted with Highlightr, using separate light and dark syntax themes **[V][S]**. In `code.png`:
  comments are grey, keywords purple, strings green, variables orange-red, commands amber.
- **Inline code and fenced blocks**: `RoundedCodeLayoutManager` fills the background with `backgroundFade` in a
  rounded rect **[S]**. The theme preview uses padding 2×4 px and radius 4 px **[S]**. Fenced blocks get one
  rounded rect spanning the block's lines, about 6 pt radius **[U]**.
  - Copy feedback pills: "Code block copied" / "Inline code copied" **[S]**.
  - Default language: "Used when no language is specified after triple backticks." **[S]**
- Code notes turn off link shortening and paste stripping **[S]**.

### Simple Markdown

- **Headings `#` / `##` / `###`**: bold, coloured `accent1Main` / `accent1Secondary` / `accent1Tertiary` **[S]**.
  The hash marks stay visible in the same colour **[V]**. The heading is the same size as the body **[V]**
  (`markdown.png`).
- `**bold**`: the text is bold and the `**` markers stay visible, dimmed to `typeLight` **[V]**.
- `*italic*`, `~~strike~~` and `__underline__` follow the same pattern: dimmed markers plus the style **[U]**.
- `//` comments: italic `typeLight` **[V]**.

### Timers (in-note display)

- **Location** **[V]**: the left gutter. Centre x ≈ **22 pt**, using small monospace digits at about 10 pt.
  - **Stopwatch**:
    - The label "10s" (milestone unit) sits at the top, level with the first line, in `typeSuperlight`.
    - Below it a **vertical dotted track** (~1.5 pt dots, ~4 pt pitch, colour `gridClear`) runs down to above the
      bottom margin.
    - A filling segment of the same dots in **`accent2Main`** grows upward from the bottom as seconds pass and
      resets at each 10 s milestone.
    - Elapsed time is stacked **minutes over seconds** ("00 / 02") at the bottom of the track in `accent3Main`
      at ~70% opacity. The milestone flash uses `accent1Main` **[S]**.
  - **Countdown / pomodoro**:
    - The top of the gutter shows the cycle count "0x" in `accent3Main`, then remaining **minutes over seconds**
      ("24 / 58") in `typeLight` **[V]**.
    - The dotted track runs below and the filled part shows progress.
    - Break time uses `accent3Main` **[S]**. The text "timer time" is `accent2Main` **[S]**.
- **Interaction**: click to pause, double-click to stop ("Click to pause. Double-click to stop.") **[S]**. Esc stops
  the timer.
- **Command pills** **[V][S]**: "Stopwatch started", "Countdown started", "25/5 Pomodoro started", "Pomodoro
  started for …", "Timer paused", "Timer restarted", "Breathing started".
- **Menu bar**: "Show time left in the menu bar" shows `△ 04:37` next to the menu icon, with digits in system
  monospaced-digit font and a stable width **[V][S]** (`timerbar.png`).

### AutoPaste state

- Typing `paste` then Return starts it **[S]**. A pill reads **"AutoPasting clipboard..."** (`accent1Main` fill)
  **[V]**.
- A small **clipboard glyph in `accent3Main`** sits in the left gutter at the first line (x ≈ 20 pt) and
  **blinks** (about 1 s period, opacity 1 ↔ 0.3) while monitoring **[V]**. Each copied item is appended as a new
  line. Clicking the glyph, pressing Esc, or typing `paste` again stops it **[S]**. Suggested SF Symbol:
  `doc.on.clipboard.fill` (present in the binary) **[S]**.
- A custom delimiter is possible: `paste(, )` **[S]**.

### Paste and copy feedback

Pill texts **[V][S]**:

- "Markdown removed from pasted content.\nChange in settings."
- "Pasted content optimized."
- "Extra spaces removed on paste."
- "Removed keyword from copied text."
- "Copied list items as unchecked."
- "Copied to clipboard"
- "Copied all to clipboard"

The paste pills append "Change in settings or use ⌘⇧V to bypass." **[S]**

### Image drop (OCR)

- While an image is dragged over the window, the note area shows the `OCRDrag` illustration **[V][S]**:
  - A dashed elliptical orbit with a small square holding a filled dot (700×479 pt source, drawn ~45% width,
    `typeLight` strokes).
  - Below it, **"Drop an image to capture text."** in `typeLight` monospace.
- On drop a pill reads "Extracted text." (`accent1Main`) **[V]**.

### Extension autocomplete (`::`)

[V] from the 2.0 video, [S] for strings.

- **Popover**: anchored just below the caret line, left-aligned near the caret. Width ≈ 60% of the window.
  Background `background` with a 1 px `typeSuperlight` border, radius about 8 pt, and a soft shadow.
- **Rows**: about 28 pt tall.
  - The selected row has a `typeHyperLight` background and a `›` chevron at the left.
  - Command name in monospace `typeMain` (e.g. `uppercase_line`).
  - A right-aligned faint category tag (e.g. `line_format`, `dice`) in `typeSuperlight`.
  - An action badge: a rounded 4 pt rect.
    - Navy `accent1Main` "⇆ replaceLine".
    - Green `accent3Main` "↓ insert".
- **Footer**: "↑↓ to navigate · ⇥ or ↩ to select" in `typeLight`, small. "No commands found" / "Try a different
  search term" when empty **[S]**.
- **Parameter hints**: "Press ⇥ for next param", "Press ↩ to finish", "Please type a value" **[S]**.

---

## 3. Note navigation

### Swipe between notes

- **Gesture**: a two-finger horizontal trackpad swipe (`SwipeGestureDetector`) **[S]**. Settings: "Swipe between
  notes" and "Swipe sensitivity" ("Higher values require more deliberate swipes.") **[S]**. Keys: ⌘[ / ⌘].
- **Animation** **[V]** (`swipe.mp4` at 6 fps):
  - The outgoing note **slides horizontally about 8–10 pt** in the swipe direction while fading out.
  - The incoming note slides in from the opposite side by the same small offset while fading in.
  - Total ≈ **200–250 ms**, ease-out. It is not a full-width page slide: the page stays put and the content
    shifts slightly.
- **Swiping past the newest note** creates a new empty note **[S]**. **Swiping away from an empty note** deletes it
  and shows the "Empty note deleted" pill **[V]**.
- **Entering a note after navigating**: the caret is hidden until an arrow key is pressed. ↓/→ puts it at the
  start and ↑/← at the end **[S]**.
- **Other keys**: ⌘1 "Jumped to latest" and ⌘⇧1 "Promoted note to front" **[S]**.

### Slotted notes and the slot bar

- **Nine permanent slots**. Their default first lines are Greek gods: `# Hermes` ("This is your **first of nine**
  slotted notes. It'll stay with you."), `# Aphrodite`, `# Gaia`, `# Ares`, `# Zeus`, `# Cronus`, `# Ouranos`,
  `# Poseidon`, `# Hades` **[S]**. These follow planet order: Mercury → Hermes ... Pluto → Hades **[U mapping]**.
- **Slot bar** **[V]** (2.0 video):
  - A floating **capsule** centred at the bottom, about 55% of the window width and about 24 pt tall, bottom inset
    about 16 pt.
  - Fill: translucent `background` / `typeHyperLight`, blurred, with a soft 8 pt shadow.
  - Holds **nine planet glyphs** in order **Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune, Pluto**
    (assets `PlanetsMercury` … `PlanetsPluto`, 30×30 template images **[S]**). Glyphs are drawn at relative sizes:
    Mercury and Pluto are tiny dots (~3 pt), Earth, Mars and Neptune ~9 pt, Jupiter ~14 pt with a spot, Saturn
    with its ring, Uranus with a vertical ring.
  - Inactive planets: `typeLight` grey. **Active slot: `accent1Main`** **[V]**. Hovering a planet shows its name
    **[S]**.
  - The bar fades out about 2 s after the last interaction and returns on hover near the bottom. "Always show the
    slotted notes bar" keeps it visible **[S]**.
- **Split screen** (⌘⇧T): ephemeral and slotted panes side by side, or stacked when "Split horizontally" is on
  **[S]**. Each pane can use its own theme ("Use the Ephemeral themes in Slotted too") **[S]**. Hint pill on first
  entry: "⌘T" to get back **[S]**.

---

## 4. Menu bar item and dropdown modes

- **Status item icon**: `MenuIcon`, a 16×16 template **outlined equilateral triangle △** with ~1.5 pt stroke
  **[V][S]**. SF stand-in: `triangle`.
  - When a timer runs and "Show time left in the menu bar" is on, it shows `△ 04:37` **[V]**.
- **Modes** ("Show Antinote in") **[S]**:
  1. Dock Only.
  2. Pseudo Menu Bar: "app will hide/show when you click the menu bar".
  3. Dock and Pseudo Menu Bar.
  4. Traditional Menu Bar: "with a fixed notes popover window. Works with fullscreen apps."
  5. Nothing: "Can only be accessed via the Global Hotkey shortcut, Spotlight, or equivalent".

  Changing the mode asks for a restart: "Restart Required" **[S]**.
- **Pseudo menu bar** **[V]** (`pseudomenu.webp`): the normal note window, same size and corners, appears **right
  under the menu bar**. Its top edge is about 8 pt below the bar, its right edge about 15 pt right of the △ icon,
  so the window hangs under the icon. There is no arrow, and the full window shadow is visible.
- **Traditional dropdown** **[V]** (`dropdown.webp`): an **NSPopover-style panel with an arrow** pointing at the △
  icon.
  - Light material background, light grey on a light desktop.
  - Corners ~10 pt. Default size ≈ 310×400 pt, configurable as "Dropdown window size" Width × Height
    (`popoverWidth`, `popoverHeight`) **[S]**.
  - Editor text inside renders at a smaller default size (about 12 pt) **[V]**.
- **Status-item click** (`StatusItemManager`: `handleClick:`, `showHideMainWindow`, `createNewNote`,
  `showSettings`, `exportMenuItemAction:`) **[S]**. A left click toggles the window or popover. The right-click
  menu items are "Hide/Show Antinote", New Note, Export, Settings, and "Quit" **[U]** (strings present:
  "Hide/Show Antinote", "Back Up & Quit Antinote").
- **Global hotkey** default **⌥A** ("Global Hotkey - Show Antinote (Beta)") **[S]**. The window appears on the
  active Space with no animation beyond the standard fade **[V]**.

---

## 5. Settings window

- **Style** **[V]**: a standard macOS **toolbar-tab preferences window**. The title is the tab name, centred and
  bold. A row of icon-over-label tabs fills the toolbar. The selected tab gets a rounded-rect highlight (8 pt
  radius, `controlBackground` slightly lighter) and an **accent-blue icon and label**. The body is a SwiftUI
  `Form` with `.grouped` style: section headers in bold 13 pt, rounded 10 pt group cards, rows separated by
  hairlines, subtitles in secondary 11 pt. The window follows system appearance (dark in the video). Width ≈ 680
  pt **[U]**.
- **Tabs, in order** **[V][S]**: the 2.0 notes list the same order, "General, Appearance, Editor, Notes, Keywords,
  Shortcuts, Timer, Export, Extensions, Privacy, and Updates" **[S]**.

| # | Tab | Icon seen [V] | SF Symbol |
|---|---|---|---|
| 1 | General | gear | `gearshape` |
| 2 | Appearance | colour-swatch fan | `swatchpalette` |
| 3 | Editor | "A" + text cursor | `character.cursor.ibeam` **[S]** |
| 4 | Notes | two stacked pages | `doc.on.doc` |
| 5 | Keywords | magic wand with sparkles | `wand.and.sparkles` |
| 6 | Shortcuts | ⌘ in a rounded square | `command.square` |
| 7 | Timer | stopwatch | `stopwatch` |
| 8 | Export | share arrow | `square.and.arrow.up` **[S]** |
| 9 | Extensions | puzzle piece (filled) | `puzzlepiece.extension.fill` **[S]** |
| 10 | Privacy | crossed-out eye | `eye.slash` |
| 11 | Updates | ↓ in a circle | `arrow.down.circle` |

### Tab contents (labels verbatim [S] unless noted)

**General**

- **Window**: "Hide Antinote when it loses focus" ("Applies only while the window is unpinned."), "Restore pin
  state on open".
- **Menu bar & Dock**: "Show Antinote in" (5 options above), "Dropdown window size".
- "Launch Antinote at login", "Start with a new note".
- **iCloud**: "Sync notes with iCloud", "Sync preferences with iCloud" ("Keeps settings, keywords, themes, and
  keyboard shortcuts the same on your other Macs.").
- "Global Hotkey - Show Antinote (Beta)" recorder, showing "Press shortcut..." / "Capturing shortcut...".
- Language picker ("Antinote now speaks your language").

**Appearance**

- **Color theme**: separate light and dark picks via **Sun / Moon icons** (`sun.max`, `moon`) **[S]**. A grid of
  theme preview tiles (`ThemePreviewView`) **[S]**, the link "Create your own at antinote.io/theme-maker", and
  "Reload Custom Themes" plus an "open themes folder" button.
- **Slotted**: "Use the Ephemeral themes in Slotted too" / "Slotted currently follows the Ephemeral themes — pick
  one below to give it its own."
- **Paper**: Blank | Lines | Dots | Small Grid | Large grid. Opacity: Subtle | Clear | Bold. "Select a non-blank
  paper type to enable opacity options."
- **Text**: Font size XS–XL, "Double font size".
- **Window**: "Make Antinote translucent" ("Requires macOS 15 (Sequoia) or later."), "Translucency opacity"
  ("0% uses the most translucent macOS material."), "Use solid colors for top and bottom bars when translucent"
  ("Takes effect after restarting Antinote.").
- **Bars**: "Show note modified/created time", "Show the note creation date", "Show latest-note indicator", note
  count (e.g. "14 of 18").
- **App icon**: Default | Classic | Custom ("Choose Image…", "Replace…", "Remove"). Messages: "App icon updated",
  "The icon couldn't be saved."

**Editor**

- **Typography & language (beta)**: "For non-English typography: pick a font that supports your language, and
  adjust the caret if it sits too high or low." Then font family, "Caret height offset", "Caret height offset in
  lists", "Force right-to-left (RTL) layout", and "Reset Font & Offsets to Defaults".
- **Code blocks**: "Default language", "Dark syntax theme", "Light syntax theme".
- **Links**: "Detect and highlight links" ("Turning this off disables all link features."), "Shorten long links
  automatically".
- **Paste ("Clean up pasted text")**: "Remove leading spaces and tabs from new lines", "Remove list numbering (1. 2.
  3.)", "Remove list bullets", "Remove Markdown formatting", "Remove empty lines".
- **Copy**: "Auto-copy selected text" ("Highly efficient but takes some getting used to."), "Copy entire note when
  nothing is selected", "Cut current line when nothing is selected", "Skip keyword when copying a whole note",
  "Copy list items as unchecked", "Skip checkboxes and bullets when copying".
- **Automatic lists**: checkbox ('Start a line with "[]" or "- [ ]".'), bullet ('Start a line with "-".'), numbered
  ('Start a line with "1." — items renumber themselves as the list changes.'), "When an item is checked".
- **Vim mode**: "Modal editing with Normal, Insert, and Visual modes. Press Escape to return to Normal mode." The
  motion timeout is described as "How long to wait for the next keypress while composing a multi-key motion."
- Other toggles: "Keep indentation of the previous line when pressing Return", "Allow macOS text replacements",
  "Swipe between notes", "Swipe sensitivity", spell check, autocorrect.

**Notes** **[V]** (frame of the 2.0 video)

- **iCloud**: "Sync notes with iCloud" (toggle).
- **Automatic notes**: "Create a new note after" ("Timer starts whenever the window loses focus.", popup default
  "Never"; options 10 mins / 3 hrs / 12 hrs / 3 days / 1 week / 1 month). "Auto-delete unmodified notes after"
  (popup "Never").
- **The Void**: "Auto-empty The Void after" ("Deleted notes are permanently removed after this period.", default
  **30 days**). "Recently deleted notes" ("Recover them, or erase them permanently.") with buttons **"Recover
  Notes…"** and **"Empty The Void"**. "Delete all notes not modified since" uses a date stepper and a "Delete…"
  button.
- **Slotted notes**: "Use slotted notes as your main notes", "Split horizontally", "Always show the slotted notes
  bar", "Create new notes in the ephemeral pane when in slotted view", and the ⌘1–⌘9 slot jumps.
- **Locked notes**: "Require Touch ID or password again after", "Ask to unlock automatically", "Relock locked
  notes".
- "Show archived notes in the note stack".
- **Backups**: "Backups are timestamped copies stored next to your notes database.", quantity and interval, and
  "Restore From a Backup" ("Pick a backup. Antinote quits, and reopening it replaces your notes with the
  backup."). "Notes & backups folder".
- **Legacy**: "Import notes from Antinote 1.1.7 or earlier", "Export for Antinote 1.1.7", "Restore note order from
  Antinote 1.1.7".

**Keywords**

- One group per keyword (sum, avg, math, list, count, code, paste, timer, check). Each has a main keyword,
  "Additional keywords" ("Separate each keyword with a comma"), and help text such as "Any of these will enable
  calculations in your note."
- **Math**: "Primary currency", "Secondary currency", "Primary currency symbol", "Significant digits", "Use a
  thousands separator", "Previous answer word", "Update currency rates daily", "Custom currency rates" ("These
  override live currency rates. Full list of supported codes: antinote.io/docs/currency").
- **List**: "Default list style", "Check off items with".
- "Disable all keywords" master switch (`disableAllKeywordsStorage`).

**Shortcuts**

- A list of rows (action label + recorder). Labels include "Show Command Palette", "Find and Replace", "Search All
  Notes", "Toggle Split Screen", "Swap Ephemeral vs. Slotted", "Toggle Read-Only", "Lock/Unlock Note", "Check Off
  Current Line", "Duplicate Line Up/Down", "Indent/Outdent List Line", "Increase/Decrease Text Size", "Go to First
  Note", "Show Previous Note", "Strikethrough Text", "Turn line into comment".
- "Some shortcuts will require an app restart to apply."

**Timer**

- "Pause timer when quitting the app", "Show time left in the menu bar" ("Only in Pseudo Menu or Traditional Menu
  mode.").
- "When a countdown finishes" / "When a pomodoro ends" ("Applies to pomodoros longer than 30 seconds."), each with
  "Show a notification", "Show a full-screen alert", and "Play a sound".
- Alert volume slider with a Test button ("Affects both countdown and pomodoro alert sounds.").

**Export**

- "Quick Export destination" ("Quick Export in the File menu sends the current note straight to this
  destination.").
- Destinations: Plain Text (.txt), Markdown, Bear, Obsidian (vault), Apple Notes ("Apple Notes helper Shortcut"),
  Notion, and a "Custom URL scheme" ("Send notes to any app that accepts a URL scheme.").
- "Omit keyword in exported notes", "Use first line of note as title", "Export all notes" ("Saves every note as a
  .zip archive of .txt files.").
- "Enabled destinations appear as export commands in the File menu."

**Extensions** **[V]** (2.0 video)

- "Enable extensions" toggle, then a two-column "Loaded Extensions" browser.
  - Left list: package names with command counts, a selected row highlighted in system blue.
  - Right side: detail cards with command name, an orange "replaceLine"/"insert" badge, parameters, and examples.
- "Browse community extensions" button, plus "Install from GitHub", "Reload Extensions", "Choose Extensions
  Folder", "Enable Extension Logging", and "API Keys".
- Also the "AI Extension Builder" page: "Back to Extensions", numbered blue step circles, and "Copy Prompt to
  Clipboard".

**Privacy**

- Groups of toggles, each listing its endpoint ("Calls antinote.io/api/currencies."): "Automatically update
  conversion rates daily", "Allow CloudKit sync", "Check GitHub for extension updates", "Let extensions call
  their own APIs", "Query urgent alerts", "Enable updater".
- "Allow these network calls", plus a **"Turn Everything Off"** button.

**Updates**: auto-check toggle and a "Check for updates" button ("Checking for updates...", "Already on latest").

---

## 6. Command palette (slash palette)

- **Trigger**: type **`/` at the start of any empty line** ('What if I forget?! Just type "/" on any empty line.
  <3') **[S]**.
- **Behaviour** **[S]**:
  - Lists the *main* keyword for each mode, numbered. Pressing a number pastes that keyword onto line 1,
    replacing any existing keyword ("Choose command palette quick option").
  - Any other non-number, non-`/` key closes it ("Close command palette due to non number and non '/' keypress").
  - `//` makes the line a comment instead ("Double slash makes a comment while palette is open").
  - Esc closes it ("Esc closes command palette").
- **Visual** **[U]** (no frame found): reuse the `::` autocomplete popover (§2).
  - Anchored under the `/`.
  - Rows show `1  math`, `2  list`, `3  sum`, `4  avg`, `5  count`, `6  code`, `7  paste`, `8  timer`, with the
    number in `typeLight` and each keyword in its keyword colour.
  - Footer: "Press enter to run command" **[S]**.
- Extension commands use the separate `::` palette ("Search extensions, commands, or descriptions...") **[S]**.

---

## 7. The Void (recover UI)

- **Opening it**: File › "Recover Notes from The Void..." or the Settings › Notes buttons **[S]**.
- **Strings** **[S]**:
  - Empty state: "The Void is empty" / "Deleted notes will drift here".
  - Actions: "Restore from The Void" (`arrow.uturn.backward`), "Delete from The Void?" (confirm: "There is no
    recovery beyond The Void."), "Note permanently deleted", "Nothing to delete".
  - Easter egg: "… notes. There are no turtles beyond The Void."
  - Delete pills: "Note banished to void", "N notes banished to void", "Impermanence will set you free."
  - Delete confirm: "Send to The Void" with "Don't ask again.".
- **Animation identifiers**: `voidDistortionSlow`, `voidDistortionBurst` **[S]**. Notes drift with a slow,
  continuous wavy distortion (a Metal shader; the bundle ships `default.metallib`). Restoring or destroying fires
  a short burst **[S/U]**.
- **Suggested layout** **[U]**:
  - A sheet or window styled like the search pane (§8) on a dark field.
  - Rows show a note preview (2 lines, `typeMain`) plus "Deleted N days ago" (`typeLight`).
  - Row buttons: restore (`arrow.uturn.backward`) and destroy (`trash`), each 24 pt with a `typeHyperLight`
    hover.
  - Empty state is centred, with "The Void is empty" in title weight and "Deleted notes will drift here" in
    `typeLight`.

---

## 8. Search (⌘F)

[V] from the 2.0 video, [S] for strings. The search pane **replaces the note inside the same window**.

- **Search field**:
  - Full-width rounded rect (radius ~8 pt) about 12 pt from the window sides and ~30 pt from the top, height ~26
    pt, fill `typeHyperLight`.
  - Leading 🔍 `magnifyingglass` and placeholder "Search", both in `typeLight` monospace.
  - A trailing **"esc"** hint in `typeLight`.
- **List view** (default):
  - Results flow edge to edge with no separators.
  - Each result: up to 3 lines of note text in `typeLight`/`typeMain` monospace, with line breaks shown as
    "  |  ", then the meta line "Edited 6 hours ago" / "August 12" in `typeSuperlight`.
  - Right side: two 22 pt square buttons with `typeHyperLight` fill and radius 5. **Promote** (↑ to a bar,
    `arrow.up.to.line`) and **Delete** (`trash`).
  - Rows are spaced about 14 pt apart.
- **Card view**:
  - A 3-column grid with ~10 pt gaps.
  - Cards: radius ~10 pt, `typeHyperLight` fill, 1 px `typeSuperlight` border. Each shows a miniature of the note
    (~70% text size), **keeping keyword colours** (e.g. `list` in purple).
  - The meta line and promote/delete buttons sit at the card bottom.
- **Bottom toolbar** (floating over results):
  - Bottom-left: a capsule **"✓ Select"** (`checkmark.circle`) and a capsule **"Ephemeral"** with a wind/stack
    icon (toggles to "Slotted"). Both have `background` fill and a soft shadow.
  - Bottom-right: a segmented capsule with list (`list.bullet`) and grid (`square.grid.2x2`; the binary has
    `square.grid.3x3.fill`). The selected segment has a dark `typeMain` fill with a white icon.
- **Behaviours** **[S]**:
  - Drag to reorder ("Clear the search to rearrange notes"; "Slotted notes stay in their slots").
  - "Promote selected to front"; "No slotted notes yet".
  - No results → "Create a note starting with …".
  - Typing "archived" browses archived notes.

### Find and Replace (⌘⇧F)

[V] `find-replace.png`. A **shelf docked to the window bottom**, full width, ~2 rows × 28 pt, with a darker
`backgroundFade` fill and a top hairline.

- **Row 1**: disclosure chevron ⌄ (expands Replace); the search field holding the current term; an **"Aa"** toggle
  segment; a **"Contains ⌄"** popup (Contains / Matches Word / Starts With / Ends With / Regex); a ‹ › segmented
  pair; then **"Done"**.
- **Row 2**: a "Replace" field, then a **"Replace" | "All"** segmented pair.
- Matches are highlighted with a `typeHighlight` background **[V]**. Opening the shelf expands all links **[S]**.

---

## 9. Timer full-screen alert and Breathe

### Full-screen alert

[V] `timer-fullscreen.png`, [S] `TimerCompleteAlertController`, an overlay window on every screen.

- **Background**: a dark translucent full-screen overlay (`#2B2B33` ≈ 85%) over a blurred desktop, with soft
  colour bloom in the corners (purple bottom-right, blue-grey bottom-left).
- **Centred stack, top to bottom**:
  1. The **logo** (`LogoStandalone`, an orbit ellipse plus a small circle on it plus a triangle), ~110 pt wide, in
     brand mint **`#03EEA0`**, drawn slightly desaturated (`#6FD3A0`-ish) on dark.
  2. ~70 pt gap, then the title **"Break Time"** in SF Pro **Bold ~44 pt**, `#E6E6E6`.
  3. **"WILDLIFE FACT-FILE"**, SF Pro ~13 pt, tracking +3, `#BDBDBD`.
  4. ~40 pt gap, then the fact sentence (e.g. "Ostriches can run faster than horses.") at SF Pro ~20 pt, `#EDEDED`.
     The fact is picked at random from ~600 animal facts in the bundle.
  5. "Break time remaining:" at ~13 pt in `#9A9A9A`, then a row with a **circular pause button** (~36 pt, fill
     white at 8%, ⏸ glyph) and the countdown **"04:51"** in monospaced bold ~22 pt.
  6. Two buttons, **"Sneak a peek"** and **"End Pomodoro"**: standard rounded bezel buttons, ~18 pt text, grey
     fill at 25% white.
  7. "No-Peek Streak: **0** (Best: **0**)". The numbers are bold in yellow `#F5D90A`, the rest `#9A9A9A`.
- **Other title and message variants** **[S]**:
  - "Work Session Complete" / "Take some time for yourself."
  - "Your countdown timer is over." (with the "Dismiss" button)
  - The pomodoro "back to work" lines rotate: "Time to work. Or not. I'm not your boss.", "Ready to continue?",
    "Back in action!", "Here we go again!", "Time to refocus." and others.
- **Interaction**: Esc closes it ("Esc closes timer alert overlay") **[S]**. Fade in about 300 ms **[U]**.
- **Sounds**: `countdowndone.m4a`, `workdone.m4a`, `backtowork.m4a` **[S]**.

### Breathe

- The command is **`timer breathe`** ("timer breathe - to chill") and shows the pill "Breathing started" **[S]**.
- Onboarding copy: "Breathe in. / Breathe outtttttt. / Nice." **[S]**
- **Visual** **[U]**: reuse the timer gutter. The dotted track fills over 4 s and drains over 6 s in a loop, in
  `accent1Main`. Optionally a centred line in the note area cycles "Breathe in." / "Breathe outtttttt." in
  `typeLight`.

---

## 10. Themes, paper, icons, translucency

### Built-in theme names [S]

Strings from the binary's theme constructors, in order: **Vancouver, Tokyo Drift, Gundam W(ing), Vendetta, Totoro,
Mononoke, A24, Agrabah, Knight, Shadow Moses, Piccolo, Tartan, Muad'Dib, Sanrio**. There is also an earlier
constructor whose name was not recoverable; it is the default theme pair (values in §0). The website gallery
labels "Mononoke, Gundam, Tokyo Drift, Vendetta, Piccolo, A24, Brave, Agrabah". "Brave" is not in the binary
strings, so it may be a display alias **[U]**. The design intent is "Offer beautiful themes inspired by my
childhood." **[S]**

Colours below were sampled from antinote.io theme screenshots **[V]** (dominant pixels after antialiasing, so
treat them as ±8 per channel):

| Theme | Dark? | background | typeMain | Keyword | Variable | Result | Other observed |
|---|---|---|---|---|---|---|---|
| Mononoke | dark | `#181818` | `#FCFCFC`* | dark green `#285C44` | teal `#3C5860` | red `#D44848` | scrollbar orange-red* |
| Gundam | light (small grid) | `#F6F6F6` | dark grey* | navy `#08346C` | blue `#6894B8` | amber `#F0BC5C` | links red `#B81838` |
| Tokyo Drift | dark | `#2B2626` | `#F0E8E4` | teal `#1C8888` | teal `#1C8888` | green `#48D86C` | colon pink `#DC98FC` |
| Vendetta | dark | `#141414` | `#E0E0E0` | — | — | — | caret red* |
| Piccolo | light (lined + timer) | `#F5FFF5` | `#594F4C` | purple `#8C5898` | green `#4CB840` | pink-red `#E8507C` | highlight lime `#B0F82C` |
| A24 | dark | `#0E1511` | `#E8E0C8` | `#847C6A` | — | orange `#B85C30` | — |
| Brave | light (grid, double font) | `#F4F1EB` | dark brown `#5C4C38`* | — | — | — | highlight peach `#F4BC9C` |
| Agrabah | dark | `#0B0B28` | `#FCFCFC` | yellow `#FCF880` | yellow `#FCF880` | cyan* | link teal `#004C5C`, highlight magenta `#983054` |

Vancouver, Totoro, Knight, Shadow Moses, Tartan, Muad'Dib and Sanrio have no public screenshots, so their colours
are **[U]**. Cells marked * were read by eye rather than pixel-sampled. Ship the unseen themes as placeholders derived from their namesakes, or omit them.

### Theme picker

- One theme for light mode and one for dark (Sun/Moon), with an optional separate pair for the slotted pane
  **[S]**.
- Custom themes are JSON files in a themes folder ("Failed to Create Themes Directory", "Theme Decoding Failed")
  with "Reload Custom Themes" **[S]**.
- The theme maker (antinote.io/theme-maker) shows a live note preview. Its sample text is "This is a sample note
  showing how your theme will look in Antinote. / Call mom at 3pm / Conf code: 584903 / Massive attack - Solsbury
  Hill" **[S]**.

### Paper types [S][V]

- **Types**: `blank`, `lines`, `dots`, `smallGrid`, `bigGrid`, shown as "Blank | Lines | Dots | Small Grid | Large
  grid".
- **Opacity**: Subtle | Clear | Bold, mapping to `gridSuperlight` | `gridClear` | `gridBold`.
- **Rendering**: a cached tile pattern (`GridTileCache`, `GridOverlayView`) **[S]**. Lines are 1 px.
  - Small grid pitch = **20 pt** (theme-maker CSS `background-size: 20px 20px`) **[S]**.
  - Big grid ≈ 40 pt **[U]**.
  - Lines pitch = line height, aligned to text baselines **[U]**.
  - Dots: 1.5 pt dots on the 20 pt lattice **[U]**.
- Paper scrolls with text **[U]**. 2.0 video frames show a light blue small grid under the text **[V]**.

### App icon options [S][V]

- **Default**: an iOS 26-style icon (`AntinoteiOS26Icons`, layered Icon Composer asset). It is a **mint-green
  rounded triangle**, top face lighter (gradient), with an orbit ring and a small circle, on a white/light
  squircle (2.0 video intro and `appicon-light.png`).
- **Classic**: `AppIconClassic` from 1.1.7. A black-gradient squircle (`#030303` → `#3A3A3A` top-right) with a
  **mint `#39EBA6` orbit ellipse, a small circle on it and an outlined triangle**.
- **Custom**: any PNG/JPEG/HEIC.
- **Brand mint**: `#03EEA0` (`LogoStandalone`) / `#39EBA6` (classic icon).

### Translucent mode [S][V]

- "Make Antinote translucent" uses an `NSVisualEffectView` behind-window material. The theme background is
  layered on top at "Translucency opacity" 0–90% (the theme maker previews 10–90%, step 10, default 50) **[S]**.
- **Look** **[V]**: the desktop shows through strongly blurred (theme maker: `blur(20px) saturate(180%)`). Text stays
  fully opaque, and theme accents (keyword, results) remain vivid.
- On macOS 26 the top and bottom bars and buttons become Liquid Glass unless "Use solid colors…" is on **[S]**.
- "Hide when unfocused" option (`hideWhenUnfocused`) **[S]**.

---

## 11. Onboarding / tutorial notes

- **Format** **[S]**: onboarding is ordinary notes pre-seeded into the stack (oldest → newest). The user swipes
  back (⌘[) through them. Each ends with a **`[←] hint`** line pointing to the previous note. Copy is plain,
  conversational, lower-key, and uses the keyword features live (`math`, `sum`, `list`, …) so each note
  demonstrates itself. Locale variants switch the decimal comma (`$4,25` vs `$4.25`).
- **Sequence** **[S]**, shown in navigation order starting at the front note:
  1. "Welcome to Antinote!\n\nThe best way to use Antinote is to never title a note, delete a note, organize a note,
     or worry about a note.\n\nEmbrace impermanence (and bad spelling).\n\n[←] Swipe or ⌘+[ to see the previous
     note."
  2. "math\n\nActivate features by typing a keyword in the first line.\n\nIn this case, "math" at the top will make
     it so any line that ends in an equal sign will be calculated.\n\n240 + (23 / 8) * 6 =\n\n$4.25 for lychee +
     $21 for moon cakes =\n\nBut wait, there's more.\n\n[←] Swipe."
  3. "math\n\nThe math keyword also enables conversions.\n\n89 miles to km =\n4" 2' to cm =\n32 oz to lbs =\n\n$32
     USD to JPY =\n\nBy default, USD is primary and CAD is secondary. You can quickly convert from primary to
     secondary like this:\n\n$23 =\n(note the dollar sign)\n\nor from any currency into your primary like
     this:\n\n$5 BTC =\n(note the dollar sign)\n\nChange your primary and secondary currency in settings.\n\n[←] My
     favorite feature is coming up."
  4. "math\n\nAntinote also supports variables. You can define a variable by using a colon followed by a
     number.\n\nguests: 5\ncost per guest: $34\n\n… guests * cost per guest =\n\n… hourly rate: 23.75\n\ndaily
     earnings: hourly rate * 8 =\n\nmonthly salary: daily earnings * 20 =\n\n…\n\n[←] Time for some mental rest."
  5. "Breathe in.\n\nBreathe outtttttt.\n\nNice.\n\n\n\n[←]"
  6. "sum\n\nThis will add all of the numbers in the text.\n\n$2 for apples, $25 for bus tickets, $6 for coffee
     and $4.25 for a bagel.\n\n[←] Next"
  7. "avg\n\nSame, but average.\n\n…\n\n[←] Almost at the end!"
  8. "count\nTed Bluderfield\nSadie Lafleur\nCarl Sagos\nAndrea Xi\n[←] Connie Tinue"
  9. "list: Optional title\n- [ ] Every line is automatically a new item.\n\n# Break up lists with headers\n- [ ]
     Doesn't it feel good\n- [ ] to check things off\n- [ ] check the box, or type "/x" at the end of an item\n-
     [x] to check it off\n- [ ] like that ^\n\n[←] great job!"
  10. 'Try this. Type "timer 5" on the next empty line and press enter.\n\n\n^^^ Type it right here!\n\n"timer" is a
      stopwatch\n"timer 5" is a countdown\n"timer 3:30" is a countdown\n"timer pomo" is a classic pomo\n"timer 57
      11" is a custom pomo\n\n"timer p" will pause/resume\n"timer r" will restart\n"timer s" or esc will
      stop\n\nYou can try and stop it now.\n\n[←] 2 more!'
  11. 'What if I forget?!\n\nJust type "/" on any empty line. <3\n\n\n^^^ Try it here\n[←] 1 more!'
  12. "\n\nLast trick - I promise!\n\nTake a screenshot of some text, and drag or paste it in here.\n\n\n[←]"
  13. "Finally!\n\n⌘ + F : Search notes\n\n⌘ + P : Pin Antinote to top\n\n⌘ + D : Delete note\n\n⌘ + 1 : Go to
      latest note\n\n⌘⇧ + 1 : Promote note to front\n\nOr mouse over the top part of Antinote to click cool sci-fi
      buttons.\n\nGo to Settings [⌘ + ,] to find themes, custom keywords, privacy settings and more.\n\nThe full
      user manual can be found at antinote.io/user-manual.\n\nFor now, start your first note with [⌘ +
      N].\n\nTo infinity, and beyond!"
  14. Easter eggs: "Have you ever played The Stanley Parable? …" and "Wow, even ads won't turn you away eh? … I'm
      Johnson. I made Antinote. …"
- **Notes the reader can't see**: the order above is inferred from the "[←] N more!" countdown and the "Almost at
  the end!" hints **[U order]**. Completion pill: "The tutorial is over. You can start using the app now." **[S]**.
  Slotted onboarding uses the Greek-god notes (§3) **[S]**.
- Locale variants: `$4,25` / `23,75` in comma-decimal locales **[S]**.

---

## Appendix A: Asset inventory (`Assets.car`) [S]

`AppIcon`, `AppIconClassic`, `AntinoteiOS26Icons` (+ `_Assets/Color-1…11`, `Gradient-1/2`, `orbital 2`, `Asset
3`), `IconDelete`, `IconExport`, `IconFront`, `IconImage`, `IconNew`, `IconNext`, `IconPin`, `IconPrevious`,
`IconPromote`, `IconSearch`, `IconSettings` (all 30×30, non-template, black line art), `LogoStandalone` (50×22,
mint), `MenuIcon` (16×16 template triangle), `OCRDrag` (700×479), `PlanetsMercury…PlanetsPluto` (30×30 templates).

Jotter must draw its own equivalents and must not copy these files. The glyph descriptions in §1, §3 and §4 are
enough to redraw them.

