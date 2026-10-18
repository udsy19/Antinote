# UI parity with the reference app

This is the element-by-element comparison between Super Notes and the reference macOS notes app (Antinote 2.x as
installed under `/Applications/Setapp`). `ui-reference.md` came from marketing videos and screenshots. This
document comes from the shipping binary itself, so where the two disagree, this one wins.

## How the values were found

Nothing here was measured from pixels unless a row says so. Every value was read from the app bundle without
running the app:

- **Disassembly.** The arm64 slice was disassembled with `objdump -d --no-show-raw-insn`. The helpers then did
  three things. They resolved `objc_msgSend` selector references and imported-symbol stubs (the SwiftUI
  modifiers: `_FrameLayout.init`, `_FlexFrameLayout.init`, `View.padding`, `Font.system(size:weight:design:)`, …).
  They decoded Swift small-string literals built with `mov`/`movk`. And they tracked the float constants loaded
  into `d` registers (`fmov`, literal-pool `ldr`) before each call. Addresses in the table (`0x1005…`) point into
  that disassembly.
- **Theme constructors.** Each built-in theme is a function that builds 24 `NSColor`s with
  `colorWithRed:green:blue:alpha:` and stores them into a static struct: name, an `isDarkTheme` byte, then the
  colours in role order. A small emulator replayed those functions to recover every component exactly.
- **Static tables.** Arrays of doubles in `__TEXT,__const` hold things like the font-size ladder and the list
  paragraph spacing. They were found by following the indexed `ldr d…, [x…, x…, lsl #3]` loads back to their
  tables.
- **Resources.** `Localizable.strings` gave the exact UI labels and `Assets.car` gave the glyph names. The glyphs
  were rendered to scratch PNGs, for reference only: Super Notes draws all of its own glyphs in code, and no reference
  asset, sound, script or long text is copied.

The **fixed?** column says whether Super Notes now matches. "no" always gives the reason, which is usually that the
change needs new behaviour or a product decision rather than a visual fix.

Theme *names* are Super Notes' own on purpose. Each Super Notes theme carries the exact colours of the reference theme
listed next to it. Math results deliberately keep fixed decimals with no primary currency symbol.

## Summary

| Area | Rows | Match now | Partly | Still different |
|---|---|---|---|---|
| Themes | 13 | 13 | 0 | 0 |
| Editor | 35 | 32 | 0 | 3 |
| Window chrome | 34 | 30 | 1 | 3 |
| Menus, status item and onboarding | 21 | 20 | 1 | 0 |
| Settings | 43 | 43 | 0 | 0 |
| Search, The Void and timers | 17 | 16 | 0 | 1 |
| **Total** | **163** | **154** | **2** | **7** |

"Match now" covers rows fixed in this pass and rows that already matched. The rows still open need something
Super Notes can't verify or doesn't have: compiled Metal effects, Liquid Glass content that doesn't render offscreen, a
reference value that wasn't found, or a behaviour change the row explains.

## Themes

Colour values for every role of every built-in theme.

| Element | Reference truth + evidence | Super Notes before | Fixed? |
|---|---|---|---|
| Theme table: role model | 24 colour roles + `name` + `isDarkTheme`; struct stores name, isDark byte at +0x10, 24 `NSColor` pointers from +0x18 (constructors 0x100580724–0x1005853xx, `colorWithRed:green:blue:alpha:` + `whiteColor`/`blackColor`) | Same 24 roles | yes (unchanged) |
| Default Light (reference "Vancouver") | Exact values per role; `accent2Secondary` #C14DFB at alpha 0.5; grid lines #D9EEFA/#CBE1ED/#ABCBDD at alpha 0.8 (0x100580724) | Same RGB, but every role opaque | yes — alpha now carried as `#RRGGBBAA` |
| Default Dark (reference "Tokyo Drift") | Exact values; `accent2Secondary` #C14DFB at 0.5 (0x100580cac) | Same RGB, opaque | yes |
| Neon Night ↔ "Tokyo Drift" | Identical to the default dark theme in the reference (0x100580cac) | Sampled approximation (#2B2626 bg, #F3ECE5 text, …) | removed — it duplicated Default Dark |
| Mecha ↔ "Gundam Wing" | bg #F5F5F5, text #323232, keyword #E664B4, results #FFBE46, grid alpha 0.6 (0x100581264) | Sampled approximation over default light | yes |
| Masquerade ↔ "Vendetta" | bg #141414, fade #330404, caret/H1 #BA0B0B, pill text black (0x1005817a8) | Sampled approximation | yes |
| Cedar ↔ "Mononoke" | bg #03180C, text #DCDCDC, keyword #289A28, results #DC3C3C (0x100582288) | Sampled approximation (#181818 bg) | yes |
| Arthouse ↔ "A24" | bg #0F1612, text #E3D4B4, keyword #4D7967, results #C55623 (0x100582818) | Sampled approximation | yes |
| Dune ↔ "Agrabah" | bg #0A0A28, text #F0F0F0, keyword #F5DC3C, results #8CC8C8 (0x100582d90) | Sampled approximation | yes |
| Fern ↔ "Piccolo" | bg #F5FFF5, text #323232, keyword #A032B4, results #FF5082, highlight #B3F92C (0x100583ddc) | Sampled approximation | yes |
| Highland ↔ "Tartan" | bg #F3F1EB, text #3C280A, keyword #FF7828, results #7391A8 (0x100584338) | Only bg/text/highlight changed from default light | yes |
| Remaining reference themes | Totoro (light), Knight (dark), Shadow Moses (dark), Muad'Dib (light), Sanrio (light) (0x100581d0c, 0x1005832d8, 0x100583820, 0x1005848b0, 0x100584e5c) | Not shipped | yes — shipped with every role's exact value under Super Notes' own names: Meadow ↔ Totoro (bg #FAF5EB, keyword #557D69), Armor ↔ Knight (bg #0A0A0F, text #585858), Stealth ↔ Shadow Moses (bg #292D2D, text #CADEE8), Spice ↔ Muad'Dib (bg #E1D2B4, text #9F865E), Bubblegum ↔ Sanrio (text #E876B2), in the reference's order (renders theme-*.png) |
| Pill text on dark themes (`typeReverse`) | Black for every dark theme except the default dark (which uses its background) | Followed the background | yes |

## Editor

Text, caret, selection, lists, math, code, links, pills, the `::` list and paper.

| Element | Reference truth + evidence | Super Notes before | Fixed? |
|---|---|---|---|
| Editor font family | Menlo by default (`fontFamily` AppStorage default string 'Menlo', smallstr 0x100253cac) | Menlo | yes (already matched) |
| Text size ladder | XS 10 / S 12 / M 14 / L 16 / XL 18 pt; doubled 20–36 (tables 0x1006f8f20 / 0x1006f8ef8, read by font getter 0x10041aca4); default preset M (`fontSize` default 2, 0x1004128a8) | 11 / 12.5 / 13.5 / 16 / 18 | yes |
| Line height | NSParagraphStyle lineHeightMultiple 1.4, min = max = round(ascender − descender + leading) × 1.4, paragraphSpacing 0, no tab stops, defaultTabInterval 28 (0x1003eb2f4) | 1.6 × font size, tab = 4 advances | yes |
| List-note line height | multiple 1.2 + paragraphSpacing 7/7.5/9/12/16 (by size) on blank paper; 1.4 and 0 spacing on other papers (0x100472a04, table 0x1006f8f48) | 1.35 × size + 0.65 × size spacing | yes |
| Text insets | NSTextView inset 0 inside SwiftUI: top padding 30 (40 in the popover mode, 0x1004a20a8); leading gutter frame 32 pt (42/42/42/45/52 with double size, 0x1004622a0) + default HStack spacing + 5 pt line padding ≈ 45 | 44 pt scaled with font, top tuned to cap at 37 | yes (left 45 at every size; right kept symmetric 45 — see remaining) |
| Caret | accent1Main (theme +0x68), 2 pt wide, radius 1, height capHeight + 7.8, foot on line bottom − leading, plus user caret nudge (0x1004f5694) | ascender…descender around baseline | yes — the nudge is Settings → Editor → Caret height offset (and "… in lists") |
| Selection | selectedTextAttributes = foreground typeMain + background typeHighlight (0x10021b05c) | background only | yes |
| Scroll indicator | custom SwiftUI RoundedRectangle, 4 pt wide, typeHighlight, min length 50, easeInOut 0.2 (0x1002cf1dc, 0x1002cf518) | 3 pt NSScroller knob | yes |
| Keyword colours | sum accent3Main, avg accent4Main, math accent1Main, list accent2Main, paste accent3Main, count accent5Main, code/timer accent4Main (0x100427e04…) | same | yes (already matched) |
| Markdown | H1–H3 accent1Main/Secondary/Tertiary; bold/italic/strike/underline markers typeLight; `//` comments typeLight (regexes at 0x10042a818…, roles 0x10042aac0–0x10042cdc0) | same | yes (already matched) |
| Checkboxes | SF Symbols `square` / `checkmark.square` at the text size (10…18, doubled), regular; unchecked typeMain, checked accent2Secondary (alpha 0.5 in the theme), hover accent2Main (unchecked) / typeMain (checked) (CheckboxView 0x100568d18) | stroked 12.5 pt rounded square drawn in code, checked at extra 50% alpha | yes |
| Marker column | centre x 34/30/28/23/23 pt per size (double: 34/30/30/30/32), + indent (0x100569cd8, tables 0x100704ae8/b10) | box at 20.5 pt scaled with font | yes |
| Bullets | SF Symbol `circle.fill` at 0.4 × text size (4…7.2 pt, table 0x100704a20) | 5 pt dot scaled | yes |
| Numbers | Text in the editor font, right-aligned in a 1.05 × size frame (table 0x1007049d0) | right edge 6 pt before text | yes |
| Done items | checked text typeLight with strike-through (theme-maker role) | typeLight + strike | yes (already matched) |
| Math results | result accent3Main, variable definition accent1Secondary, colon accent2Main, uses accent1Tertiary (0x100437274/0x100437c5c/0x100438594) | same; " " then result after "=" | yes (already matched; fixed decimals kept by design) |
| Sum / avg / count summaries | accent3Secondary / accent4Secondary / accent5Secondary ("Total: ", Flesch strings) (0x100433ac4, 0x100434354, 0x100432824) | same | yes (already matched) |
| Code block background | backgroundFade, union of line fragments inset (−4, −2), radius 3 (RoundedCodeLayoutManager 0x10024dbfc) | full width ±10, ±4, radius 6 | yes |
| Inline code background | glyph box inset (−2, +0.8), offset +3 pt down, radius 3 (0x10024d458) | ascender…descender ±3, radius 4 | yes |
| Shortened links | typeSubtlePlus, expanded/plain typeSubtle, underline typeSuperlight (0x10042ed74–0x10042fe40) | same, dotted underline | yes (already matched) |
| Link hover tip | editor font at editor size, typeReverse on accent1Main, padding 8, shadow black 33% radius 5 y 4, easeInOut 0.1 (CustomTooltipModifier 0x1002e2b28) | bold 10 pt white on typeLight 90% | yes |
| Link tip wording | "⌘+Click to open", "⌘+Click to open \| ⌘⇧+Click to shorten.", "\n⌘+Click to open \| ⌘⇧+Click to expand." (0x1004b2a8c…) | "⌘+Click to open \| Click to expand." | no — Super Notes expands on a plain click; changing the hint needs the ⌘⇧-click behaviour change first |
| `::` list rows | padding 12 × 8; `chevron.right` bold 10 pt in a 12 pt slot; name system 12; tag system 9 padded 4 × 2 on a fill; badge padded 8 × 3, symbol 9 medium + action 10 medium in typeReverse (0x100371458…0x1003727fc) | monospace 12, `›` glyph, unicode arrow badges | yes |
| `::` badge symbols/colours | insert `arrow.down.to.line` accent3Main; replaceLine `arrow.left.arrow.right` accent1Main; replaceAll `doc.text.fill` accent2Main; openURL `link` accent2Main; other `questionmark.circle` typeLight (0x100373cf0) | ↓ accent3 / ↗ accent4 / ⇆ accent1 | yes |
| `::` footer / empty state | "↑↓ to navigate  •  ⇥ or ⏎ to select" system 11 below a divider; "No commands found" 13 medium, "Try a different search term" 11 (0x100372974, 0x10036f8b4) | "↑↓ to navigate · ⇥ or ↩ to select" 10 pt; mono empty state | yes |
| `::` placement | flips above the caret when the caret is past 60% of the note height (0x100462d94) | always below | yes |
| Message pills | Text in the editor font and size (regular), typeReverse, padding 15 × 5, capsule (radius 100); success accent1Main, info typeMain, warning accent4Main, error accent5Main, subtle typeLight; shows 1 s + 0.05 s × characters, in easeInOut 0.1, out easeOut 0.5 (MessagePill 0x1005172f4, colours 0x100346e9c, timing 0x1005183d0) | bold 11 pt, padding 12 × 3.5, radius ≤ 10, 2.2 s, 150/300 ms | yes |
| Pills on macOS 26 | fill at 50% inside clear Liquid Glass (`glassEffect(.clear, in: Capsule())`, 0x100517c50) | solid | no — NSGlassEffectView content does not render offscreen, so it can't be verified; solid pre-26 look kept |
| OCR drop overlay | opaque theme background, `OCRDrag` art 250 pt wide in typeMain, "Drop an image to capture text." in the editor font, typeMain, padding 20 (0x1002d197c) | 94% background, typeLight, 45% width, 12 pt | yes (art redrawn in code to the asset's proportions) |
| Paper | ruled/dot rows at the line pitch, 1 pt under each baseline (per-size −0.24…1.15, table 0x100703da0); big grid = line pitch, small grid = half; dots 1.5 pt (0x10054e6c0…) | lines at fragment tops, fixed 20/40 pt grids | yes |
| Vim status | uppercase grey text, 10 pt from the left, centred in a 30 pt bottom strip (0x100465c84) | 10 pt semibold in a filled capsule | yes (font size not recovered; kept 10 pt semibold mono) |
| Find bar | custom find/replace shelf (FindAndReplaceManager: match case, match type, replace); `find-replace.png`: chevron, field with "Aa" and "Contains ⌄", ‹ ›, Done, then Replace field and Replace \| All, on `backgroundFade` under a hairline; links expand while it is open | system NSTextView find bar | yes — `FindShelf` with those controls and match types Contains / Matches Word / Starts With / Ends With / Regex; matches in `typeHighlight`; short links expand while it is open (renders editor-find*.png) |
| Editor context menu | standard NSTextView menu (no menu override on TextEditorViewWrapper) | standard | yes (already matched) |
| Right text inset | trailing 35 pt frame after the editor (0x1004624d4) | symmetric 44 | no — NSTextView insets are symmetric; kept 45 both sides |
| Slash command palette | Typing "/" on an empty line offers the main keywords inline in the note; a number picks one, "//" makes a comment, Esc closes; the hint "Press enter to run command" is attached as a text attribute (0x1003ecbac, 0x1004c67f8–0x1004c6904) | No inline "/" list; ⌘K opens Super Notes' own palette window | yes — "/" at a line start or after a space lists the keywords (main keyword in its colour, numbered 1–9) and then the ⌘K palette's commands from the same source (`PanelServicing.commands(matching:)`); letters filter, digits pick, "//" and Esc close; math and code notes only open it on an empty line (renders editor-slash*.png) |

## Window chrome

The main window, the hover-revealed top and bottom bars, the slot bar, the latest-note dot and the lock screen.

| Element | Reference truth + evidence | Super Notes before | Fixed? |
|---|---|---|---|
| Main window default size | 350 × 400 pt content when no frame is saved (`setContentSize:` d0=350 d1=400 at 0x100443a60, after the `windowOriginX/windowWidth/windowHeight` defaults lookups) | 337 × 386 (measured from video) | yes |
| Main window min size, corners, shadow | Standard titled window; no explicit min size found | 240 × 180 min, standard corners | no — no reference value found; kept |
| Top bar strip | `CustomTitleBarView` frame (0, 0, titlebar width, 30), autoresizing 0xA, added to the traffic lights' superview (0x1004e76d0, d3=30) | 34 pt hover strip, icon row 17 pt down | yes — 30 pt bar; strip 35 pt so the buttons that hang 5 pt below stay clickable |
| Top bar button row / traffic lights | Button stacks and each traffic light: `centerY = bar.centerY + 5` (0x1002882a8, 0x100288384, 0x10025b8a8) → row 20 pt from the top; traffic-light x left at the system position | Row 17 pt; traffic lights moved to x 13/33/53 | yes — row 20 pt, x untouched |
| Top bar left/right insets | Left stack leading 80 pt when traffic lights show, else 10 (`fcsel` 80/10 at 0x10028821c); right stack trailing −10 (0x100288318) | Settings/Search centres hand-placed at 81/110, New/Pin at W−52/W−24 | yes — 80 / 10 pt |
| Top bar button spacing | `NSStackView.spacing` = 5 on macOS 26, 0 before (`fcsel` at 0x1002875c4) | 3 / 2 pt gaps | yes |
| Chrome button size + glyph | `CustomButton`: 30 × 30 (0x10055092c/96c), image view inset 4 on all sides (0x1005507a0…8d8) → 30-unit artwork drawn at 22 pt | 26 pt button, 13 pt glyph | yes — 30 pt button, glyphs redrawn on a 30-unit canvas at 22 pt |
| Chrome button colours | Tint `typeMain` (theme +0x28, 0x1005506dc); hover bg `typeHyperLight` (+0x58, 0x10054fea8); click bg `typeLight` (+0x48, 0x10054ff24); pinned `accent3Main` (+0x90), pinned hover `accent3Secondary` (+0x98) | Tint `typeMain` at 75%, others same | yes — full-strength `typeMain` |
| Chrome button shape | Layer corner radius 5; on macOS 26 15 with an `NSGlassEffectView` (ButtonGlassBackgroundView) behind the glyph, tinted `typeHyperLight` on hover and the pin colour at 20% (0x1005502b4, 0x100550b08…, 0x100550fa4 alpha 0.2) | Radius 6 fill, no glass | yes — radius 5; round Liquid Glass on macOS 26 (not visible in offscreen renders) |
| Top bar tooltips | "Settings - ⌘+," (literal), "Search Notes - ", "New Note - ", "Pin Antinote to Top - " + shortcut (0x100287698…0x100287e38); shortcut text = ⌘⇧⌥⌃ then upper-cased key, no "+" (0x1004e45e8); pin tooltip never changes | "Settings", "Search Notes", "New Note", "Pin on Top"/"Unpin from Top" | yes — "Settings - ⌘+,", "Search Notes - ⌘⇧F", "New Note - ⌘N", "Pin Super Notes to Top - ⌘⇧P", read live from the menu shortcuts |
| Top/bottom bar fade | Reveal/hide animations 0.3 s (0x1004e7d08…, 0x10025b764; bottom bar `easeInOut(0.3)` 0x100416870) | 0.2 s | yes |
| Glyph: Settings | `IconSettings` 30 pt: three 1.5-unit sliders x 6–24, knobs as pin-holed rings at (15.25, 9.25), (20, 15.25), (12, 20.75), dot at (7, 12) | 16-unit sliders, open knobs | yes — redrawn from the 2× bitmap geometry (renders-chrome/icons-vs-reference.png) |
| Glyph: Search | `IconSearch`: lens ring r≈6.8 at (14.75, 13.5), ringed-planet ellipse 17.8 × 3.2 whose front crosses the lens, handle to (20.6, 24), star at (21.9, 19.4) | similar, smaller ring | yes |
| Glyph: New | `IconNew`: rounded square 6–24 (r 3.5), pen from centre to the top-right corner, star at (24.4, 5.2) | similar | yes |
| Glyph: Pin | `IconPin`: ring r 4.5 at (15.25, 10.75), stick to 22.5, base 6.75–23.25 at 23.25, dot (18.5, 20.5) | similar | yes |
| Glyph: Previous / Next | ◁/▷ outline joined to its bar by a 1-unit line; bars at x 19.5 / 10.75; dots (16.5, 6.75) / (7.75, 22.75) | no joining line | yes |
| Glyph: Front | 1-unit line through a short bar (x 11.5) and a full-height bar (x 15) into ▷ (tip 26.25) | similar | yes |
| Glyph: Export | △ outline on a stem out of a 16.5 × 9 rounded box, stem ending in a dot | similar, no dot | yes |
| Glyph: Delete | Double-lined lid 19.5 wide with a handle dot, round-bottomed body (r 4), three 1.5-unit slots | tapered body, thin slots | yes |
| Bottom bar height & insets | `frame(height: 40)` (0x1004163cc); content `frame(maxWidth: ∞, maxHeight: 20)` + `.padding(.horizontal, 10)` + `.padding(.vertical, 10)` (0x100416a08…a44) → buttons centred 20 pt above the bottom, 10 pt from the sides | 30 pt bar, row 15 pt up, delete centre 16 pt in | yes |
| Bottom bar buttons | SwiftUI `Button` 30 × 30, image padded 4 (`EdgeInsets` 4 at 0x100553408), `PlainButtonStyle`, `.help`; tint `typeMain`; hover `typeHyperLight` (20% glass tint on macOS 26, `Glass.clear.interactive()` 0x100553994) | 26 pt, 28 pt pitch | yes — 30 pt, HStack default 8 pt spacing (no explicit spacing in the binary) |
| Bottom bar order | Delete · date · Previous · Next · First · Export (`IconDelete`, `IconPrevious`, `IconNext`, `IconFront`, `IconExport` at 0x100417c10…dc4) | same | n/a — already matched |
| Bottom bar tooltips | "Delete Note - ", "Previous Note - ", "Next Note - ", "Go to First Note - " + shortcut; export "Quick Export (Markdown)" etc. (0x1004180f0, 0x100418204, 0x100417910, 0x100418414, 0x100417a8c) | "Move to The Void", "Previous Note", "Next Note", "Go to Latest Note", "Export" | yes — same labels with Super Notes' live shortcuts |
| Bottom bar export button | Present only when a Quick Export destination is enabled; clicking runs Quick Export (0x100417a10…) | Always shown; opens an export menu | partly — runs Quick Export with the "Quick Export (…)" tooltip when a destination is set; without one it still offers the menu instead of hiding |
| Bottom bar date / position text | `Date.formatted(date: .abbreviated, time: .shortened/.omitted)`, `Font.subheadline`, `Color.gray`; then a `Text` holding a vertical bar and `Text("%lld of %lld")`, each subheadline gray (0x1004171e4…0x1004177c8) | One 12 pt label in `typeLight`, parts joined by "  ·  " | yes — 11 pt subheadline, system grey, a vertical bar between parts, 8 pt apart |
| Slot bar size | `HStack(spacing: 3)` of planets (0x1004a23e4 = 3.0), `frame(height: 32)`, `.padding(.horizontal, 16)`, `.padding(.bottom, 10)` (0x1004a2564…26b8) → 254 pt wide | 55% of the window wide, 24 pt tall, 16 pt up | yes |
| Slot bar planets | `Image("Planets…")` in 22 pt frames, `typeLight` at 65%; open slot 28 pt frame, `scaleEffect(1.18)`, `accent1Main` (0x1004a42c4…42f4); `easeInOut(0.2)` | Hand-sized bodies (Venus bigger than Earth), no scale | yes — planets redrawn from the 30-unit artwork (renders-chrome/planets-vs-reference.png); size change not animated |
| Slot bar background | macOS 26: `glassEffect(.regular)` in a capsule tinted with the background at 30% (0x1004a2d74); earlier: capsule (radius 100) filled with the background, 1 pt `Color.gray` 15% border, accent1Main 45% glow blurred 7 at 20% (0x1004a31a8…, 0x1004a3848) | Background at 96% with a black 12% shadow | yes |
| Slot bar timing & tooltips | Shown for 2 s after use (`asyncAfter` +2 at 0x1004a3f38), `easeInOut(0.6)`; help text "Slot N" (0x1004a52e4) | 2 s; 0.2 s fade; "Mercury · title" | yes — 0.6 s fade; an immediate tip "Slot N — title" (empty: how to fill it, with the Assign to Slot shortcut) instead of the delayed help tag. Super Notes also fills occupied planets and outlines empty ones, and draws them above the glass so they stay crisp |
| Latest-note indicator | 5 × 5 circle in `accent1Main` (+0x68), `.padding([.bottom, .trailing], 16)`, scale+opacity transition (0x100211000…0x1002115dc) | 5 pt `accent1Main`, 10 pt inset | yes — 16 pt inset |
| Lock screen | VStack spacing 14 (0x1004664b8): `lock.fill` 32 pt medium at 60% opacity, padding bottom 2; "This note is locked" Menlo 14; Button `Label("Unlock", systemImage: "touchid")` Menlo 12, default action; error "Couldn't verify it's you." Menlo 11 at 80%; colour theme +0x30 `typeSubtle` (0x100466490…0x1004671b4) | 28 pt lock in `typeLight`, system 13 medium label in `typeMain`, 10 pt spacing | yes — error line not added (Super Notes reports auth failures elsewhere) |
| Title bar background (translucent) | `NSVisualEffectView` material 13 (hudWindow), blending within window, state active (0x100288d58; macOS 26 builds a glass view instead) behind the bar; Settings "Use solid colors for top and bottom bars when translucent" | none | yes — translucent windows put a hudWindow material (within window) behind the top and bottom bars, or the theme background with the solid-colours setting; opaque windows keep no bar background |
| Split view divider | `Divider` + 1 pt frames found near the find bar, not tied to split view | NSSplitView-style divider | no — not verified |
| Note switch animation | `_swipeDirection`/`_isTransitioning` state; the main content view (with "No notes available") builds `asymmetric(insertion: .move(edge: b ? .leading : .trailing), removal: .move(edge: b ? .trailing : .leading))` from a Bool state and animates with `Animation.default` (0x10049015c–0x1004905b0) | 9 pt slide + fade, 220 ms | no — which state picks the edge, and whether it runs for every switch, isn't confirmed; the recordings show the short slide, so it is kept |

## Menus, status item and onboarding

The menu bar, the status item, the Dock menu and the tutorial notes.

| Element | Reference truth + evidence | Super Notes before | Fixed? |
|---|---|---|---|
| App menu | About, Settings… ⌘,, Services ▸, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q (SwiftUI default; `CommandGroup(replacing: .newItem) {}` in the Settings scene, 0x1004dcae0) | Same items but no Services submenu | yes |
| Menu bar order | App, File, Edit, Appearance, Navigate, Support, Window, Help. `Scene.commands` builder 0x10050dd28–0x10050e3f4: `CommandGroup(after: .newItem)`, `(before: .windowSize)` ×2, `(after: .pasteboard)`, `CommandMenu("Appearance")`, `CommandMenu("Navigate")`, `CommandMenu("Support")`, `CommandGroup(replacing: .help)` | Super Notes, File, Edit, Note, View, Go, Window, Help | yes |
| File menu | Create New Note ⌘N · Move Note to Front ⇧⌘1 · — · Search All Notes ⌘F · — · Find and Replace ⇧⌘F · — · Toggle Split Screen ⇧⌘T · — · Swap Ephemeral vs. Slotted ⌘T · — · Make Read-Only/Allow Editing ⇧⌘R · Archive Note/Unarchive Note ⇧⌘A · Lock Note/Unlock Note ⇧⌘L · (Relock Notes) · — · Delete Note ⌘D · — · Recover Notes from The Void... · Empty The Void · — · Print... ⇧⌘P · Export Note ▸ · — · Close Window ⌘W (content 0x10050e674–0x1005100e0) | New Note, Move to The Void ⌘⌫, Recover from The Void… ⇧⌘⌫, Export ▸, Quick Export ⇧⌘E, Print… ⌘P, Close Window | yes (order, titles, shortcuts; Super Notes keeps Command Palette… ⌘K under Search). Empty The Void and Relock Notes added too (`PanelServicing.emptyVoid()`, `Shell.relockNotes`) |
| State-dependent titles | "Make Read-Only"/"Allow Editing" (`pencil.slash`), "Archive Note"/"Unarchive Note" (`archivebox`), "Lock Note"/"Unlock Note", "Pin Antinote to Top"/"Unpin from Top" (0x100511e18, 0x1005121ac, 0x1005122a0, 0x100513a18) | Static titles with checkmarks ("Read-Only", "Archive", "Pin on Top") | yes (MenuState sets the titles; the old checkmarks and "Unlock Note…" title in Shell are gone) |
| Edit menu | System Edit menu plus "Paste as is" ⇧⌘V after the pasteboard group (0x100513e68–0x100514024) | Find… ⌘F, Find & Replace ⌥⌘F, list/line commands in a separate Note menu | yes, except Paste as is — no: Super Notes' editor has no clean-up bypass command |
| Appearance menu | Increase Text Size ⌘+, Decrease Text Size ⌘- (0x100514098–0x1005142cc) | View menu: Increase ⌘=, Decrease ⌘-, Reset ⌥⌘0, Pin, slots bar, split, full screen | yes (renamed and reordered). ⌘= kept instead of ⌘+ so the unshifted key keeps working |
| Navigate menu | Jump to Front ⌘1 · Show Previous Note ⌘[ · Show Next Note ⌘] · — · Go to Slot 1…9 ⌘1…⌘9, only while `slotNumberShortcutsEnabled` (default off; ⌘1 then leaves Jump to Front) (0x100514408–0x100514f80; range (1,9) at 0x100700cd0; key 0x10051646c) | Go menu: Previous, Next, First Note ⇧⌘L, Ephemeral ⌘0, Slot 1–9 ⌘1–⌘9 always, Search, Palette | yes (new `shellKitSlotNumberShortcuts` key, switched in Settings → Shortcuts by "⌘1–⌘9 jump to slotted notes") |
| Window menu | Pin Antinote to Top ⌘P · Hide/Show Antinote ⌘O · — · Minimize ⌘M · Zoom · Bring All to Front (`before: .windowSize` groups 0x10051385c and 0x100515158) | Show Super Notes, Minimize, Zoom, Bring All to Front | yes |
| Support / Help menus | Both list "User Manual" and "Join Discord Community" (builder 0x100515410, called from 0x100516e30 and 0x100516e68) | Help: Show Tutorial Notes, Keyboard Shortcuts | partly: Support and Help menus now both exist with Super Notes' two items. Super Notes has no manual URL or Discord community |
| Default shortcut table | 33 actions (0x1004e537c): newNote ⌘N, moveNoteToFront ⇧⌘1, deleteNote ⌘D, searchNotes ⌘F, findAndReplace ⇧⌘F, pinNote ⌘P, increase ⌘+, decrease ⌘-, jumpToFront ⌘1, prev ⌘[, next ⌘], hideShowMainWindow ⌘O, globalShowApp ⌥A, quickExport ⌘S, toggleSplitScreen ⇧⌘T, swapMain ⌘T, Markdown bold ⌘B / italic ⌘I / strikethrough ⇧⌘X / underline ⌘U / cycle heading ⇧⌘H, move line ⌥↑/⌥↓, duplicate line ⌥⇧↑/⌥⇧↓, undo ⌘Z, redo ⇧⌘Z, print ⇧⌘P, read-only ⇧⌘R, archive ⇧⌘A, lock ⇧⌘L, check off ⇧⌘K, cycle list ⇧⌘M. Display names at 0x1005241d8 ("Check Off Current Line", "Cycle List Type", "Markdown: Strikethrough", …) | Different keys for promote, delete, search, pin, print, jump, quick export, split, move/duplicate line, lock, check off, cycle list | yes for every action Super Notes has, and every one can be rebound (Settings → Shortcuts). No for Markdown Bold/Italic/Underline/Cycle Heading — Super Notes has no such editor commands |
| Export Note submenu | Quick Export (Destination) ⌘S · — · Plain Text (.txt) · Markdown (.md) · PDF (.pdf) · — · Send to Bear / Obsidian / Notion / Apple Notes / Custom Export (enabled ones only) (0x100512b3c–0x1005133e4) | "Export ▸" listing displayName in enum order (Apple Notes, Obsidian, Bear, …), no Quick Export inside | yes (Notion and Custom URL destinations don't exist in Super Notes) |
| Status item glyph | `MenuIcon`: 16 pt template, outlined equilateral triangle, about 1.5 pt stroke, mitred corners (Assets.car; set at 0x10021312c / 0x1002134cc) | SF Symbol `note.text` | yes (drawn in code, AppIcons.menuBarIcon; side-by-side in renders-menus/menuicon-ref-vs-supernotes.png) |
| Status item clicks | `sendActionOn:` left and right mouse up (mask 0x14); right mouse up builds the menu, otherwise show/hide (0x100215fcc) | Same, plus ⌃-click opens the menu | same (no change) |
| Status item menu | Settings ⌘, · Create New Note · Export Note ▸ · — · Quit ⌘Q (0x1002144cc–0x10021497c) | New Note · Settings… · — · Quit Super Notes | yes (Antinote's "N" key equivalent renders as ⇧⌘N; Super Notes uses ⌘N to match the File menu) |
| Status item timer | Time drawn next to the triangle in the same item: " " + `%02d:%02d` in `monospacedDigitSystemFont(systemFontSize)` (0x100212f40–0x100213118, format 0x1003f7888) | A second status item with SF `timer` (ToolsKit TimerManager) | yes — `MenuBarTimer` (SuperNotesCore) carries the text; the single status item shows " 04:37" beside the triangle in monospaced digits, and the separate timer item is gone |
| Dock menu | No `applicationDockMenu:` on AppDelegate (methods.json) → system default | None → system default | same |
| Bottom-bar Export button menu | Same Export Note menu | Export menu + appended "Quick Export" and "Print…" (Shell.showExportMenu) | yes — the appended duplicate Quick Export is gone; Print... stays after a separator |
| Onboarding order | Welcome · math · conversions · variables · Breathe · list · count · sum · avg · timer · "/" palette · OCR · Finally, then two personal easter-egg notes (cstring order 0x10071cb30 → 0x10071bc50) | … Breathe · sum · avg · count · list · … | yes (order and hints; the "Can't remember something?" note now teaches the "/" list in Super Notes' own words). The easter eggs (the author's personal notes) are not replicated |
| Onboarding finale | ⌘F search, ⌘P pin, ⌘D delete, ⌘1 latest note, ⇧⌘1 promote, hover the top bar, Settings ⌘,, start with ⌘N | ⇧⌘F, ⇧⌘P, ⌘⌫, ⇧⌘L, ⇧⌘T | yes (Super Notes' own wording, keys read from the menu) |
| Slotted onboarding notes | Nine notes "# Hermes" ("first of nine slotted notes … It'll stay with you."), "# Aphrodite", "# Gaia", "# Ares", "# Zeus", "# Cronus", "# Ouranos", "# Poseidon", "# Hades" (0x10071da20; strings-en.json) | One "Slot 1" note describing ⌘1…⌘9 | yes (all nine slots seeded; the first note is reworded) |
| Global hotkey default | ⌥A (`globalShowApp`) | ⌥A | same |

## Settings

The Settings window and every pane.

| Element | Reference truth + evidence | Super Notes before | Fixed? |
|---|---|---|---|
| Settings window size | SwiftUI `TabView` with `.frame(width: 800, height: 500)` (`_FrameLayout` 800/500 @0x1004daaa4); Shortcuts and Timer content `.frame(width: 600)` (@0x1004db444, 0x1004db614) | 780 × 560 content | yes (800 × 500; inner 600 pt column not copied, grouped forms already inset) |
| Settings style | toolbar-tab preferences window (`TabView` + `.tabItem`, 10 items @0x1004dad80…0x1004dbd54) | NSTabViewController `.toolbar` style | yes (already equivalent) |
| Tab order / labels | General, Appearance, Editor, Notes, Keywords, Shortcuts, Timer, Export, Extensions, Privacy (label closures @0x1004dc430…0x1004dc68c); the Setapp build has no Updates tab, the `updates` enum case exists (strings.txt) | same order plus Updates | yes (Updates kept: Super Notes has no Setapp) |
| Tab icons | gearshape, swatchpalette, character.cursor.ibeam, doc.on.doc, **wand.and.stars**, command.square, stopwatch, square.and.arrow.up, puzzlepiece.extension.fill, eye.slash (small-string pairs @0x1004dc440…0x1004dc67c) | Keywords uses `wand.and.sparkles` | yes — Keywords now uses `wand.and.stars` |
| Form style / toggles | `Form{}.formStyle(.grouped)` (@0x10045bbc8); rows are `Toggle(isOn:label:)` + `SwitchToggleStyle`, label = title + `.caption` `.secondary` subtitle (@0x10045c034) | grouped form, switches, `Captioned` subtitles | yes (already matched) |
| General: sections | iCloud (view init @0x10027f4f0 before the sections), Startup, Language, Menu bar & Dock, Window, Navigation (@0x10027f508…0x10027f804) | Window, Menu bar & Dock, iCloud, Global Hotkey | yes (iCloud, Startup, Menu bar & Dock, Window, Navigation; Language n/a) |
| General: iCloud | "Sync notes with iCloud", "Sync preferences with iCloud" + caption (@0x100283b28, 0x100283d38) | sync notes lived in Notes; sync extensions here | yes (both here; Super Notes' status/Sync Now/key buttons kept; sync extensions moved to Extensions like the reference) |
| General: Startup | "Launch Antinote at login", "Start with a new note" (@0x10027fbc0, 0x10027fd54) | launch at login under Menu bar & Dock | yes — "Start with a new note" (`startWithNewNote`): launch opens a fresh note, reusing an empty front note |
| General: Menu bar & Dock | "Show Antinote in" picker + "Dropdown window size" Width/Height fields, 72 pt each (@0x100280a30, 0x100280d18, 0x100281834) | picker only | yes — Width × Height fields (72 pt) size the dropdown window (`dropdownWidth`/`dropdownHeight`, `DropdownLayout`), enabled in dropdown mode |
| General: Window | "Hide Antinote when it loses focus" (caption "Applies only while the window is unpinned."), "Restore pin state on open" (@0x100282038) | same, first section | yes (order) |
| General: Navigation | "Swipe between notes" + caption, "Swipe sensitivity" with caption "Higher values require more deliberate swipes." and a 160 pt slider / 50 pt value (@0x100282564, 0x100282d8c, 0x10027db40) | under Editor › Swiping with Light/Firm labels | yes (moved; 160 pt slider + % readout) |
| General: Global hotkey | lives in Shortcuts ("Global Hotkey - Show Antinote (Beta)" @0x100524310) | duplicated in General and Shortcuts | yes (removed from General) |
| Appearance: sections | Text, Paper, Window, Bottom bar, Themes, App icon (@0x1002d2690…0x1002d2970, App icon view @0x10035d638) | Color theme, Paper, Text, Window, Bars, App icon | yes |
| Appearance: Text | "Font size" segmented, "Double font size" (@0x1002d2e88, 0x1002d3070) | same + Super Notes' extra line spacing | yes |
| Appearance: Paper | "Paper type" segmented, "Paper opacity" segmented, caption when blank (@0x1002d36fc, 0x1002d4074, 0x1002d4170) | labels "Paper" / "Opacity" | yes |
| Appearance: Window | "Make Antinote translucent" (+ "Requires macOS 15…"), "Use solid colors for top and bottom bars when translucent", "Translucency opacity" slider 180 pt + % (@0x1002d42f0…0x1002d5318) | translucency toggle only | yes — solid bars (`solidBarsWhenTranslucent`) and the 180 pt opacity slider (`translucencyOpacity`, the theme colour over the blur; 0% = bare material) |
| Appearance: Bottom bar | "Show bottom bar", "Show note count" (e.g. "14 of 18"), "Show note modified/created time", "Show the note creation date", "Show latest-note indicator" + caption (@0x1002d54bc…0x1002d5bc4) | section "Bars" with two toggles | yes — all five rows; the bar, the count and the created-date choice work live |
| Appearance: theme grid | 2 `GridItem`s spacing 16, grid spacing 16 (@0x1002d6ce8, 0x1002d6ddc); header "Choose a [sun.max.fill] light theme, and a [moon.fill] dark theme." (@0x1002d7220) | adaptive ≥132 pt columns, sun/moon under tile | yes |
| Appearance: theme tile | 250 × 100 pt (500 wide variant) (@0x10033c774); theme background; name in the editor font (`Font.custom(fontName, pointSize)` @0x10033d6b0); 8 swatches 24 × 24 (accent1Main/Secondary/Tertiary, accent2Main, accent3Main, accent4Main, accent5Main, typeHighlight — field loads @0x10033f260); padding 8; sun.max.fill (yellow) / moon.fill (blue) 16 pt badges top-trailing, padding 6, top 7 / trailing 10; selection stroke blue 2 pt (@0x10033e09c…0x10033e8a4) | 70 pt mini note preview | yes |
| Appearance: "Applies to" | segmented Ephemeral/Slotted (max 320 pt) + "Use the Ephemeral themes in Slotted too" (@0x1002d6754, 0x1002d6a54); `selectedSlottedLightTheme`/`…DarkTheme` | none | yes — the grid edits the chosen pair; slotted notes (editor and chrome) use their own pair when set (`slottedLightTheme`/`slottedDarkTheme`, render window-slot-own-theme.png) |
| Appearance: custom themes | "Custom themes" row: Reload, Open Folder, theme-maker link (@0x1002d7c30…0x1002d7fc0) | "Reload Custom Themes", "Open Themes Folder" buttons | yes (labelled row, short buttons; no website link) |
| Appearance: App icon | tiles 110 pt wide, "Custom icon" ("PNG, JPEG or HEIC. Square images look best.") (@0x10035f7ac) | tiles + caption | yes (caption wording) |
| Editor: sections | Typing, Vim mode, Automatic lists, Copy, Clean up pasted text, Links, Code blocks, Typography & language (beta) with footer (@0x1002776fc…0x100277c20) | Typography, Links, Paste, Copy, Automatic lists, Vim mode, Typing, Swiping | yes (Code blocks n/a) |
| Editor: Typing | keep indentation, text replacements, "Check spelling" (@0x100277f70…0x100278184) | two toggles | yes — "Check spelling" (`checkSpelling`; code notes never) |
| Editor: Vim | "Enable vim mode" + caption; "Motion timeout" slider 160 pt + "%.0fms" (@0x100278690, 0x10027900c) | "Vim mode" | yes — the timeout (`vimMotionTimeout`, 200–3000 ms) drops a half-typed command |
| Editor: Automatic lists | Checkboxes / Bullets / Numbered lists toggles with captions, "When an item is checked" (@0x1002791a4…0x10027957c) | continue-lists toggle + picker | yes — each marker kind can be switched off outside list notes (`inlineCheckboxes`/`inlineBullets`/`inlineNumbered`); Super Notes' continue-lists switch kept |
| Editor: Copy | "Auto-copy selected text" + 5 toggles, each with a caption (@0x100279e88…0x10027a464) | 5 toggles, no captions | yes — auto-copy (`autoCopySelection`) copies a selection once it settles |
| Editor: paste section | header "Clean up pasted text" with 5 toggles (@0x100277940, 0x10027ae38…) | "Paste" header + master toggle | yes (header; Super Notes' master switch kept because it gates behaviour) |
| Editor: Typography | Font, Caret height offset (+ in lists), Force RTL, "Reset Font & Offsets to Defaults"; footer caption (@0x10027cc50…0x10027d02c) | first section, caption on top | yes — both caret offsets (−5…5 pt) and the combined reset |
| Notes: sections | Automatic notes, Archive, Locked notes, The Void, Slotted notes, Backups, Antinote 1.1.7 or earlier, Reset (@0x10023673c…0x100236bd8) | iCloud first, Slotted before Locked | yes (iCloud moved to General; Super Notes' Import & export kept before Reset) |
| Notes: rows | "Relock locked notes" + "Immediately require…" caption + "Relock Now"; "Auto-backups to keep" stepper with 50 pt field + caption; "Notes & backups folder" with caption; "Restore from a backup" (@0x100239750, 0x10023d7e8, 0x10023dc20, 0x10023e11c) | "Relock" button, "Backups to keep: N" stepper, long captions | yes |
| Notes: missing rows | Auto-delete unmodified notes, Archive section, Ask to unlock automatically, Delete all notes not modified since, Use slotted notes as main, Backup interval, Empty The Void button | absent | yes — every row works: auto-delete (hourly maintenance), "Show archived notes in the note stack", the Touch ID delay, date + "Move to The Void" with a count confirmation, slotted notes on launch, backup interval, Empty The Void |
| Keywords: layout | custom scroll layout; groups List, Math, Sum, Avg, Count, Code, Timer, General (@0x100589098…0x100589edc) | sum, avg, math, list, count, code, paste, timer + intro caption | yes (order and short titles; Paste kept last; intro caption removed) |
| Keywords: row | "Custom keywords" + "Any of these will … Not case sensitive." + "Separate each keyword with a comma"; "Main keyword" picker "Used for keyword autocompletion." (@0x1005895c0, component @0x1004cc854) | help text, "Built in:" caption, "Additional keywords" field | yes — "Main keyword" picks what the "/" list and the palette insert (`mainKeywords`) |
| Keywords: Math | "Significant digits", thousands separator, "Previous answer word", "Update currency rates daily" (network caption), custom rates, primary symbol, primary, secondary (@0x10058c6e0…0x1005915ac) | "Number of decimal points" first among currencies | yes (labels/order; primary symbol char n/a) |
| Keywords: General | "Enable keywords" switch (@0x100591f8c) | none | yes — off makes every note plain text (`keywordsEnabled`, checked in `NoteMode.detect`) |
| Keywords: List | "Check off items with" (@0x10058a8fc), "Default list style" ("What a plain text line in a list note becomes. Checked lines always get a checkbox.") | style picker, never read by the editor | yes — the style decides what plain lines in list notes become and where Cycle List Type starts; check triggers (`checkTriggers`, default `/x`) typed at the end of an item check it off |
| Shortcuts | editable recorder list, restart caption, ⌘1–⌘9 slot option (@0x10034a088…0x10034c974) | read-only list | yes — a recorder per menu item (Quick Export included), conflicts refused, per-row reset and Restore Defaults; menus change live, no restart (render settings-shortcuts-rebound.png) |
| Timer: sections | General, When a countdown finishes, When a pomodoro ends (footer), Sound (footer, volume slider 180 pt + Test) (@0x10048b1c0…0x10048c4b4) | untitled first section, combined alert section, Pomodoro | yes — notification / full-screen / sound per event, the 30-second rule for pomodoros, volume + Test |
| Export: sections | Destinations (footer), Quick Export (footer), Options, untitled Export all notes (@0x10051f938…0x10051fc7c) | Quick Export first | yes |
| Export: rows | Obsidian vault field 220 pt + caption; "Omit keyword…" caption; "Use first line of note as title"; Apple Notes Shortcut and Custom URL scheme destinations (@0x100521358…0x1005233ec) | vault field without caption | yes — first-line titles (else "Super Notes - <date>") and the Custom URL scheme destination with {TITLE}/{CONTENT}/{DATE}; Apple Notes is reached through AppleScript, so it needs no helper Shortcut |
| Extensions | "Enable extensions" + warning "Extensions are currently disabled…" (exclamationmark.triangle.fill); "iCloud Sync" › "Sync extensions with iCloud"; Custom Extensions › "Enable Extension Logging" (@0x100548de8…0x10054af7c, 0x100301650) | enable + logging only | yes (warning, iCloud Sync, Custom Extensions headers) |
| Privacy | "Network access" + Turn Everything Off, footer about usage data; groups iCloud Sync / Features / Extensions, each a master switch ("Mixed") + "Advanced choices" disclosure listing calls with "Network call: …" (@0x10041cee8, 0x1004e05d0…0x1004e07ec, 0x1003418e4, 0x10034155c) | one flat section | yes (grouped, mixed-state switches, disclosure) |

## Search, The Void and timers

Search (list and cards), The Void and the timer full-screen alerts.

| Element | Reference truth + evidence | Super Notes before | Fixed? |
|---|---|---|---|
| Search field | 16 pt side inset, 38 pt from top, 12 pt above results; inner padding 16 h × [8,10,12,14,16] v by size; RoundedRectangle r8 `typeHyperLight`; magnifier SF at search size in `typeLight`; placeholder "Search" `typeLight` 70 %; query `typeMain` mono; "esc" mono `typeLight` 40 %, click closes (0x100478d50–0x10047a914, tables 0x1006fc9b0, 0x1006fc970/990) | 12 pt inset, 30 pt top, 28 pt fixed height, 11 pt mono, glyph 12 pt, esc 100 % | yes |
| Search text size | Field, rows, toolbar labels one size step below the editor: XS/S 10, M 12, L 14, XL 16 (×2 doubled) (map 0x0302010000 at 0x1004742b4, font fn 0x10041aca4) | fixed 11 pt | yes (`SearchMetrics.textSize`, self-tested) |
| Search list rows | LazyVStack spacing 0, inset 4 h / 8 top / 80 bottom; row padding 12 h × [8..16] v; preview `typeLight`, `typeMain` on keyboard selection; hover wash `typeLight` 8 %; meta mono two steps down (XS–M 10) `typeLight` 50 % (0x10025d344, 0x10025e3c0, 0x10047e758) | 14 pt gaps, 11 pt text in `typeMain`, meta 9 pt `typeSuperlight`, selection `typeHyperLight` 60 % | yes |
| Row promote/delete buttons | glyph 10 pt medium (20 doubled) `typeMain`, frame glyph + 12 = 22 pt, RoundedRectangle r4 `typeLight` 15 %; help "Promote to front" / "Delete note" (0x10025f6c8, 0x10025f948) | 10.5 pt glyph, r5, `typeHyperLight` (list) / `typeSuperlight` 55 % (cards), "Delete" | yes |
| Search cards | LazyVGrid adaptive(min 230, max 340), spacing 12, inset 16 h / 12 top / 80 bottom; card 190 pt high, padding 10, RoundedRectangle r10 `typeHyperLight`, border 1 pt `typeLight` 15 % (2 pt when selected); text mono 10 pt (20 doubled), first line bold (0x10047bb8c GridItem 230/340, 0x1002601d4, 0x100260440) | fixed 3 columns, height max(132, 0.8 w), 9 pt text | yes (1 column in a 337 pt window, 2 from ~560 pt) |
| Search toolbar | Two capsules 16 pt from sides, 14 pt from bottom; capsule `typeHyperLight`, 1 pt `typeLight` 20 % border, shadow black 18 % r8 y2; left group padding 8 h 5 v: [✓ Select] │ [wind Ephemeral / square.grid.3x3.fill Slotted]; items padding 10 h 6 v, mono label + SF glyph at search size; right group padding 6 h 5 v: list.bullet / square.grid.2x2, selected = `typeMain` capsule with glyph in `background`; help "Select multiple notes", "Show slotted notes instead", "List view", "Card view" (0x10047fab0, 0x100481aec–0x100481e90, 0x1004844a4) | separate capsules in `background`, 13 pt system font, 0.14 shadow, slotted icon square.stack.3d.up | yes |
| Search select mode | Select item turns solid (checkmark.circle.fill), "N selected" + promote/delete items replace the scope switch; help "Promote selected to front" (0x100480788 Divider h16, " selected") | "Done" label + separate icon capsules | yes |
| Search empty / no results | "No notes yet", "No slotted notes yet", "Nothing found" mono `typeLight` 50 %; create capsule: return glyph + "Create a note starting with “q”" mono, padding 14 h 8 v, Capsule `typeHyperLight`, text `typeMain` (0x100483058–0x100483c88) | list-style row with "Return to create" meta; no "Nothing found" | yes |
| Search HUD pills | "Note banished to void", "N notes banished to void" (0x10047f8b8, 0x100476404) | "… banished to The Void" | yes |
| The Void window | Black, always-dark; min 450 × 400; "THE VOID" (title2 mono medium, tracking 4) + "N lost souls" (caption mono); rules 1 pt at 30 %; text white 55 % / 40 %; rows "(Empty vessel)" for blank notes, "Lost <relative>"; outlined buttons r4, 1 pt border 25 %/50 % hover, press 0.95: restore (arrow.uturn.backward, white, "Restore from The Void"), destroy (xmark, red 1/0.4/0.4, "Destroy forever"); footer "Empty The Void" (red) + "Return" (default); empty state sparkles 48 pt + "The Void is empty" / "Deleted notes will drift here"; pills "Note restored", "Note permanently deleted", "Emptied N notes from The Void", "Nothing to delete" (0x100403800–0x10040cc00) | system-styled list window 520 × 560, tornado glyph, "Recover"/trash buttons, retention text footer | yes (shader ripple: no, see below) |
| The Void distortion | Metal shaders `voidRipple` (colorEffect on the black field), `voidDistortionSlow` / `voidDistortionBurst` (distortionEffect, max offset 10 × 10) in default.metallib | none | no — needs a compiled .metallib; the Command Line Tools have no `metal` compiler |
| Timer full-screen alert | Ultra-thin material over the screen in system primary/secondary colours; column ≤ 400 pt: logo 80 × 80, title 34 pt bold (+5), "WILDLIFE FACT-FILE" 10 pt thin tracking 2 (+20), fact 14 pt (+10), small standard buttons 12 pt (padding 5 h 2 v) (0x1003ed330 Material.ultraThin, 0x1003eda94 80×80, 0x1003edd88 34, 0x1003edeec 10 thin, 0x1003ee0ac 14) | forced dark #2B2B33 85 % with colour bloom, 72 pt mark, 44 pt title, 13 pt caption tracking 3, 20 pt message, 18 pt grey pills | yes |
| Pomodoro break screen | "Break time remaining:" 10 pt secondary; pause/resume (pause.fill/play.fill 12 pt semibold, padding 8, secondary 10 % circle, help "Pause Break"/"Resume Break"); time 14 pt bold, 50 pt wide; "Sneak a peek" / "End Pomodoro"; "No-Peek Streak: N (Best: N)" 10 pt secondary with bold `accent1Main` numbers (0x1003ef214–0x1003f18d8) | 13 pt caption, 36 pt circle, 22 pt mono time, yellow streak numbers | yes |
| Countdown complete alert | Title "Timer Complete", "WILDLIFE FACT-FILE" + a random fact, one "Nice" button; notification body "Your countdown timer is over." (0x1003edd04, 0x1003ee270, 0x1003f5718) | "Time’s up" / "Countdown" / message + "Breathe" & "Dismiss" | yes |
| Break-over title | "Break Over" (0x1003f5550) | "Break’s over" | yes |
| Command palette | Antinote's palette is the in-note "/" list with the persistent pill "Press enter to run command" (0x1003ecbac, EditorKit scope); `::` command list uses system 12/11/9 pt rows, chevron, "↑↓ to navigate  •  ⇥ or ⏎ to select" (0x10036c000–0x100373400) | Super Notes' ⌘K QuickPanel has no Antinote counterpart | yes — the in-note "/" list now exists (see Editor) and shares the ⌘K palette's command source; ⌘K stays as Super Notes' extra window |
| Menu-bar timer | Time left shown in the app's own status item ("△ 04:37") | separate status item with a `timer` glyph | yes — merged into the app's status item (see Menus) |
