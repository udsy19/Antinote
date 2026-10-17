# NoteEngine — behaviour spec

Pure text logic behind note modes. Registered at launch as `Services.analyzer` (`NoteEngine`, a `NoteAnalyzing`).
Everything here is synchronous, side-effect free and cached; the only I/O is `RatesProvider` (exchange rates).

Evidence sources: the original app's tutorial notes and UI strings (`strings.txt`, `ui.txt`), class layout
(`MathManager` ivars `storedVariables`, `duplicateVariables`, `storedAnswers`; `MathPreferences` ivars
`primaryCurrency`, `secondaryCurrency`, `numberOfDecimalPoints`, `useThousandSeparators`, `ansVariableWord`,
`manualCurrencyRates`; `CopyPastePreferences` ivars `removeMarkdown`, `removeBullets`, `removeNumbers`,
`removeLeadingTabs`, `removeEmptyLines`), and antinote.io/user-manual.

## Modes

`NoteMode.detect(firstLine:)` decides the mode; the keyword line itself is never analysed.

| mode | output |
|---|---|
| math | one `LineAnnotation` per line that produces a visible result or a clear error |
| sum / average | `summary` "Sum: $37.25" / "Average: 9.31" |
| count | `summary` "4 items · 5 lines · 8 words · 41 characters" |
| timer | `arguments`; an `.error` annotation on line 0 when the arguments are invalid |
| others | mode + arguments only |

Lines starting with `//` are comments in math, sum, average and count ("Prefix a line with // to comment it out").

## Math

Evidence — tutorial: "math at the top will make it so any line that ends in an equal sign will be calculated",
"240 + (23 / 8) * 6 =", "$4.25 for lychee + $21 for moon cakes =", "89 miles to km =", "4\" 2' to cm =",
"32 oz to lbs =", "$32 USD to JPY =", "$23 =" (primary → secondary), "$5 BTC =" (→ primary);
manual: "evaluate calculations inline as you type, with descriptive text alongside them".

* **When a line is evaluated.** Every line is tried. A line ending in `=` (or containing `=` that is not a
  definition) is *strict*: its result is always shown, and a failure is shown as an error. Other lines are
  *lenient*: a result is shown only when the line performs an operation (operator, function, conversion,
  percentage, unit sum); a lone number (`Rent 1200`) shows nothing; failures are silent unless the line is pure
  math (no descriptive words) and the failure is semantic (division by zero, incompatible units, missing rate).
  Prose never shows errors.
* **Descriptive text.** Unknown words are ignored: `Rent 1200 + groceries 340` → `1,540`.
* **Syntax.** `+ - * / ^`, `×` `·` `÷` `−`, `**`, `x`/`times` between values, `plus`/`minus`, `divided by`,
  `multiplied by`, `mod`; parentheses (a missing `)` at the end is tolerated); implicit multiplication before
  `(`, functions, constants and variables (`2pi`, `2(3+4)`, `3 guests`); unary minus binds looser than `^`.
* **Numbers.** `1,540`, `1.234,56`, `4,25` (comma + 1–2 digits = decimal comma), `.5`, `1.5e3`, `2E-4`,
  scale words `5k`, `2 thousand|million|billion|trillion`. Inside function parentheses commas separate arguments.
* **Percentages.** `20% of 80` = 16, `20% off 80` = 64, `80 + 15%` = 92, `50 - 10%` = 45, `80 * 15%` = 12,
  `80 / 50%` = 160, `5% + 3%` = 8%.
* **Functions / constants.** `sqrt cbrt abs round(x[,digits]) floor ceil sin cos tan asin acos atan log(x[,base])
  log2 ln exp min max`, `√x`; `pi`/`π`, `e`, `tau`. Trig takes radians unless the argument has an angle unit
  (`sin(30°)`, `cos(90 deg)`).
* **Variables** ("Use a colon to define a variable", "Variables can be calculations too", "Variables cannot be
  defined multiple times"). `name: expr` or `name = expr`; names start with a letter, may contain spaces
  (`cost per guest: $34`), and are matched case-insensitively, longest name first. Definitions only affect later
  lines; every edit re-analyses the whole note, so changing `hourly rate` updates `daily earnings` and
  `monthly salary`. A literal definition shows nothing; a computed one (`Coffee: $4.50 × 20`) shows its value.
  Defining a name twice shows `Already defined` (only when the line is clearly math). Reserved names
  (functions, constants, answer words, `total`/`sum`/`average`) are treated as labels.
* **Previous answer** ("Previous answer word"): `ans`, `prev` and the configurable word
  (`Defaults[.answerWord]`, default `ans`) refer to the last shown result.
* **Totals.** A line consisting only of `total`, `sum`, `subtotal` (or `average`, `avg`, `mean`), optionally with
  `:`/`=`, sums (averages) the values of the lines above in the same block. A block ends at an empty line or at a
  total line. Values are lines with a shown result plus lone values (`Rent 1200`); literal definitions and
  percentages are excluded; units/currencies convert to the first value's unit, incompatible ones are skipped.
* **Units** (convert with `in`, `to`, `as`, `into` followed by a unit at the end of the line): length (nm µm mm
  cm m km in ft yd mi nmi ly, `'` `"`), mass (µg mg g kg t oz lb st ton), volume (ml cl dl l m³ cm³/cc gal qt pt
  cup fl oz tbsp tsp ft³ in³ imperial gallon), area (mm² cm² m² km² ha acre in² ft² yd² mi², `sqft`, `sq ft`,
  `square feet`), temperature (°C/C/celsius, °F/F/fahrenheit, K/kelvin, with offsets), time (ns ms s min h day
  week month year), data (b bit, B byte, KB MB GB TB PB, KiB MiB GiB TiB, Mbit Gbit), speed (m/s km/h mph knot
  ft/s), angle (rad deg °). A unit word only counts directly after a number or after a conversion keyword, and
  `in` only means inches when not followed by a word. Adjacent quantities of one dimension add (`5 ft 3 in`,
  `4" 2'`, `1h 30min`). Arithmetic: same-dimension `+ −` convert the right operand to the left unit;
  `quantity × number`; `length × length` → area; `length ÷ time` → speed (km/h, mph, ft/s or m/s);
  same-dimension `÷` → plain ratio. Mixing dimensions is an error (`Can't combine ft and kg`).
* **Currencies.** ISO codes (upper case; common ones also lower case), names (`dollars`, `euros`, `yen`,
  `rupees`, `bitcoin`, `bucks`…), symbols before or after the number (`$ € £ ¥ ₹ ₩ ₽ ₺ ₫ ₱ ₪ ₴ ₦ ฿ ₿ ₡ ₸`, `R$`,
  `A$`, `CA$`, `NZ$`, `HK$`, `S$`, `US$`, `MX$`, `NT$`). `$` is the primary currency when it is a dollar
  currency, otherwise USD; `¥` is CNY when CNY is primary, otherwise JPY; a code after the number overrides the
  symbol (`$5 BTC`). Crypto: BTC ETH SOL DOGE ADA XRP DOT LTC BNB USDT USDC AVAX LINK SHIB TRX ATOM XLM NEAR PEPE
  TON BCH XMR ALGO POL ETC UNI AAVE ARB OP SUI APT HBAR FIL DAI. A strict line that is a single currency amount
  converts primary → secondary, anything else → primary.
* **Results** (`LineAnnotation.text` is the bare value, e.g. `1,540`, `$90.00`, `30.48 cm`, `25%`; the editor adds
  any `=` decoration). Plain numbers are rounded to `Defaults[.significantDigits]` significant digits (whole parts
  are never rounded away), trailing zeros trimmed, scientific notation beyond 1e15 / below 1e-9. Grouping follows
  `Defaults[.thousandsSeparator]` ("Use a thousands separator") with the locale's separators. Fiat
  amounts use 2 decimals (0 for JPY, KRW, VND, CLP, ISK, UGX, PYG); the primary currency and unambiguous
  currencies print their symbol (`-$5.00`, `€3.50`), others print the code (`12.00 AUD`, `0.5 BTC`).

## Exchange rates — `RatesProvider`

Evidence: "Automatically update conversion rates daily", "Custom currency rates — These override live currency
rates", "Fetching currency rates blocked by user preferences", "Failed to fetch latest currency rates. Using saved
rates with manual overrides."

* Fetches only when `Defaults[.allowCurrencyRates]`: fiat from `https://open.er-api.com/v6/latest/USD` (no key),
  crypto from CoinGecko `simple/price?vs_currencies=usd`.
* Rates are "units per 1 USD"; cached to `SuperNotesPaths.support/exchange-rates.json` with a timestamp. On start the
  cache loads; a refresh runs when there are no rates, or when `Defaults[.autoUpdateRates]` and the cache is older
  than 24 h (checked hourly). Failures keep the saved rates.
* `Defaults[.customRates]` (units per USD, e.g. `["XYZ": 2.5]` = 1 USD is 2.5 XYZ) override fetched rates.
* Posts `RatesProvider.didUpdate` (main queue) after a fetch or when custom rates change; the editor re-analyses.

## Sum, average, count

Evidence: "All the numbers in the text you write will be added together", tutorial
"$2 for apples, $25 for bus tickets, $6 for coffee and $4.25 for a bagel.", manual "strips punctuation and symbols".

* Every number delimited by non-letters is taken (`$2`, `-5`, `1,200`, `4,25`, `20%` → 20); `abc123` and `5kg` are
  not. Currency symbols/codes next to numbers make the total a currency: values convert to the first currency seen
  when rates exist, plain numbers count as that currency.
* Average divides by the count of numbers. Summary: `Sum: $37.25`, `Average: $9.31`.
* Count ("Any of these will count all non-empty lines"): items = non-empty lines, lines = all lines, words,
  characters (no newlines) — excluding the keyword line and `//` lines.

## Lists

List markers are parsed and edited by the editor (`EditorKit`'s `ListLine` and `EditorLogic.Lists`, see
editorkit.md): `[ ]`, `[x]`/`[X]`, `- `, `* `, `• `, `1. `. Settings → Keywords → List → "Default list style"
decides what plain lines in a list note become and where "Cycle List Type" starts.

## Paste cleaning — `PasteCleaner`

Settings → Copy & Paste (`cleanPaste` master switch, off = unchanged). Always: CRLF → LF, NBSP → space,
zero-width characters dropped, runs of spaces collapsed, trailing whitespace trimmed ("Extra spaces removed on
paste."). `pasteRemoveMarkdown`: headers, emphasis (`**`, `__`, `*`, `_`, `~~`), inline code, blockquotes,
images/links (`[t](u)` → `t (u)`, `![a](u)` → `a`). `pasteRemoveBullets`: `- * • + ◦ ▪ ‣` and checkboxes.
`pasteRemoveNumbering`: `1.` `1)` `(1)`. `pasteRemoveLeadingWhitespace`. `pasteRemoveEmptyLines`.

## Links

`LinkShortener.shorten(_:)` — scheme, `www.`, trailing slash and fragment dropped, percent-escapes decoded. Kept
whole when ≤ 24 characters; otherwise `host/…/ending`, where the ending is the last path component, or the last two
when the last is numeric or ≤ 4 characters (`github.com/…/pull/42`); endings over 28 characters are cut with `…`; a
query string becomes `?…`. `LinkShortener.detect(in:)` finds http(s)/`www.` links and bare domains
(`NSDataDetector`) and returns `NSRange` + URL.

## Timers — `TimerSpec`

Evidence (tutorial): `timer` is a stopwatch, `timer 5` a 5-minute countdown, `timer 3:30` a countdown,
`timer pomo` a classic pomodoro, `timer 57 11` a custom pomodoro, `timer p` pause/resume, `timer r` restart,
`timer s` stop; errors "Timer only accepts 2 numbers", "Cannot countdown zero minutes"; manual: timers can be named.

`TimerSpec.parse(_:)` accepts the arguments with or without a leading timer keyword. Durations: bare numbers are
minutes, `m:ss`, `h:mm:ss`, `25m`, `90s`, `1h30m`, `1.5h`, `2 min`. `stopwatch` keyword → stopwatch;
`pomodoro`/`pomo` → pomodoro (defaults from Settings); 1 duration → countdown; 2 → pomodoro (work, break);
other words → the name. `TimerSpec.command(_:)` recognises `p`/`pause`/`resume`, `r`/`restart`, `s`/`stop`.
