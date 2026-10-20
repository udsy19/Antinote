"use strict";
/* Super Notes website. Engine: an eval-free copy of what the app does with a note (first-line keywords, math with
   units and currencies, sum/avg/count, timers, a few :: commands). Page: the live window, copy buttons and motion. */

const Engine = (() => {
  // Fixed sample rates (units per 1 USD); the app downloads daily rates instead.
  const RATES = { USD: 1, EUR: 0.92, GBP: 0.79, JPY: 150 };
  const SYMBOLS = { "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY" };
  const SIGNS = { USD: "$", EUR: "€", GBP: "£", JPY: "¥" };
  const PRIMARY = "USD", SECONDARY = "EUR", PLACES = 2;

  // "id dimension size-in-base-unit label[/plural] other names…"
  const UNITS = {}, NAMES = {};
  `mm length .001 mm millimeter millimeters
cm length .01 cm centimeter centimeters
m length 1 m meter meters metre metres
km length 1000 km kilometer kilometers
in length .0254 in inch inches
ft length .3048 ft foot feet
yd length .9144 yd yard yards
mi length 1609.344 mi mile miles
g mass .001 g gram grams
kg mass 1 kg kilogram kilograms kilo kilos
oz mass .028349523125 oz ounce ounces
lb mass .45359237 lb lbs pound pounds
ml volume .001 ml milliliter milliliters
l volume 1 l liter liters litre litres
cup volume .2365882365 cup/cups cups
gal volume 3.785411784 gal gallon gallons
s time 1 s sec secs second seconds
min time 60 min mins minute minutes
h time 3600 h hr hrs hour hours
day time 86400 day/days days
week time 604800 week/weeks weeks
C temp 1 °C °c celsius
F temp 1 °F °f fahrenheit
USD money 1 USD usd dollar dollars
EUR money 1 EUR eur euro euros
GBP money 1 GBP gbp
JPY money 1 JPY jpy yen`.split("\n").forEach((row) => {
    const [id, dim, f, label, ...names] = row.split(" ");
    UNITS[id] = { dim, f: +f, label };
    if (dim !== "temp") NAMES[id.toLowerCase()] = id;
    names.forEach((n) => { NAMES[n] = id; });
  });

  const FUNCS = { sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil, log: Math.log10, ln: Math.log };
  const KEEP_UNIT = ["abs", "round", "floor", "ceil"];
  const CONSTS = { pi: Math.PI, tau: 2 * Math.PI, e: Math.E };
  const TOTAL = ["total", "sum"], AVERAGE = ["average", "avg", "mean"];
  const RESERVED = [...Object.keys(FUNCS), ...Object.keys(CONSTS), "ans", "prev", ...TOTAL, ...AVERAGE];

  // First-line keywords → modes.
  const KEYWORDS = {};
  Object.entries({ list: "list todo checklist tasks", math: "math calc", sum: "sum", avg: "avg average", count: "count",
    timer: "timer stopwatch countdown pomodoro pomo breathe", code: "code snippet", paste: "paste autopaste" })
    .forEach(([mode, words]) => words.split(" ").forEach((w) => { KEYWORDS[w] = mode; }));

  const fail = (message, semantic = false) => Object.assign(new Error(message), { semantic });
  const syntax = () => fail("Invalid expression");
  const short = (u) => UNITS[u].label.split("/")[0];
  const incompatible = (a, b) => fail(`Can't combine ${short(a)} and ${short(b)}`, true);

  // ---------- Formatting (fixed places, grouped thousands, the primary currency without its symbol) ----------

  function number(v, places = PLACES) {
    if (!Number.isFinite(v)) return Number.isNaN(v) ? "NaN" : v < 0 ? "-∞" : "∞";
    const rounded = Math.sign(v) * Math.round(Math.abs(v) * 10 ** places) / 10 ** places;
    const [whole, frac] = Math.abs(rounded).toFixed(places).split(".");
    const text = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (frac ? "." + frac : "");
    return rounded < 0 && /[1-9]/.test(text) ? "-" + text : text;
  }

  function currency(v, code) {
    const amount = number(Math.abs(v), code === "JPY" ? 0 : PLACES);
    const sign = v < 0 && /[1-9]/.test(amount) ? "-" : "";
    return code === PRIMARY ? sign + amount : sign + SIGNS[code] + amount;
  }

  function format(q) {
    if (q.pct) return number(q.v) + "%";
    if (!q.u) return number(q.v);
    if (UNITS[q.u].dim === "money") return currency(q.v, q.u);
    const [one, many] = UNITS[q.u].label.split("/"), label = many && Math.abs(q.v) !== 1 ? many : one;
    return number(q.v) + (label[0] === "°" ? "" : " ") + label;
  }

  // ---------- Quantities { v, u: unit id or null, pct } ----------

  function base(v, u, back) {
    const { dim, f } = UNITS[u];
    if (dim === "temp") return u === "C" ? v : back ? v * 9 / 5 + 32 : (v - 32) * 5 / 9;
    if (dim === "money") return back ? v * RATES[u] : v / RATES[u];
    return back ? v / f : v * f;
  }
  function convert(q, to) {
    if (q.pct) throw syntax();
    if (!q.u) return { v: q.v, u: to };
    if (UNITS[q.u].dim !== UNITS[to].dim) throw incompatible(q.u, to);
    return { v: base(base(q.v, q.u), to, true), u: to };
  }
  function add(a, b, minus) {
    const s = minus ? -1 : 1;
    if (a.u && b.u) {
      if (UNITS[a.u].dim !== UNITS[b.u].dim) throw incompatible(a.u, b.u);
      return { v: a.v + s * convert(b, a.u).v, u: a.u };
    }
    return { v: a.v + s * b.v, u: a.u || b.u, pct: Boolean(a.pct && b.pct) };
  }
  function mul(a, b) {
    if (b.pct && !a.pct) return { v: a.v * b.v / 100, u: a.u };
    if (a.u && b.u) throw incompatible(a.u, b.u);
    return { v: a.v * b.v, u: a.u || b.u };
  }
  function div(a, b) {
    if (b.v === 0) throw fail("Division by zero", true);
    if (a.u && b.u) {
      if (UNITS[a.u].dim !== UNITS[b.u].dim) throw incompatible(a.u, b.u);
      return { v: base(a.v, a.u) / base(b.v, b.u), u: null };
    }
    if (b.u) throw incompatible(b.u, b.u);
    return { v: a.v / b.v, u: a.u };
  }
  function aggregate(values, average) {
    if (!values.length) return { v: 0, u: null };
    let sum = values[0], n = 1;
    for (const q of values.slice(1)) {
      try { sum = add(sum, q); n++; } catch (_) { /* skip what can't be added */ }
    }
    return average ? { ...sum, v: sum.v / n } : sum;
  }

  // ---------- Lexer and parser ----------

  const NUMBER = /^(\d{1,3}(?:,\d{3})+(?!\d)(?:\.\d+)?|\d*\.\d+|\d+)/;
  const OPS = { "+": "+", "-": "-", "−": "-", "–": "-", "*": "*", "×": "*", "/": "/", "÷": "/", "^": "^", "%": "%", "(": "(", ")": ")" };
  const unitFor = (w) => (w === "C" || w === "F" ? w : NAMES[w.toLowerCase()] || null);

  function lex(src) {
    const out = [];
    for (let i = 0, m; i < src.length;) {
      const ch = src[i], rest = src.slice(i);
      if ((m = NUMBER.exec(rest))) { out.push({ t: "num", v: parseFloat(m[1].replace(/,/g, "")) }); i += m[1].length; }
      else if (SYMBOLS[ch]) { out.push({ t: "cur", v: SYMBOLS[ch] }); i++; }
      else if (OPS[ch]) { out.push({ t: "op", v: OPS[ch] }); i++; }
      else if ((m = /^°?[A-Za-z_]\w*/.exec(rest))) { out.push({ t: "word", v: m[0] }); i += m[0].length; }
      else i++; // spaces and punctuation are decoration
    }
    return out;
  }

  // Words become variables, units, functions or conversions; any other word is description and is dropped.
  function classify(raw, ctx) {
    const out = [];
    let noise = false;
    raw.forEach((tk, k) => {
      if (tk.t !== "word") return out.push(tk);
      const w = tk.v.toLowerCase(), prev = raw[k - 1], next = raw[k + 1];
      if (Object.hasOwn(ctx.vars, w)) out.push({ t: "var", v: w });
      else if (w === "ans" || w === "prev") out.push({ t: "ans" });
      else if (TOTAL.includes(w) || AVERAGE.includes(w)) out.push({ t: "agg", v: AVERAGE.includes(w) });
      else if (FUNCS[w]) out.push({ t: "fn", v: w });
      else if (w in CONSTS) out.push({ t: "num", v: CONSTS[w] });
      // "5 in to cm" is inches; "10 km in mi" converts.
      else if (w === "in" && prev && prev.t === "num" && !(next && (next.t === "cur" || (next.t === "word" && unitFor(next.v))))) out.push({ t: "unit", v: "in" });
      else if (["in", "to", "as", "into"].includes(w)) out.push({ t: "conv" });
      else if (w === "of") out.push({ t: "of" });
      else if (unitFor(tk.v)) out.push({ t: "unit", v: unitFor(tk.v) });
      else noise = true;
    });
    return { tokens: out, noise };
  }

  function parse(tokens, ctx) {
    let p = 0, ops = 0;
    const peek = (o = 0) => tokens[p + o] || {};
    const isOp = (v) => peek().t === "op" && peek().v === v;
    const close = () => { if (!isOp(")")) throw syntax(); p++; };

    function expr() {
      let q = additive();
      while (peek().t === "conv") {
        const t = tokens[++p];
        if (!t || (t.t !== "unit" && t.t !== "cur")) throw syntax();
        p++; ops++;
        q = convert(q, t.v);
      }
      return q;
    }
    function additive() {
      let a = multiplicative();
      while (isOp("+") || isOp("-")) {
        const minus = tokens[p++].v === "-", b = multiplicative();
        ops++;
        a = b.pct && !a.pct ? { ...a, v: a.v * (1 + (minus ? -b.v : b.v) / 100) } : add(a, b, minus);
      }
      return a;
    }
    function multiplicative() {
      let a = unary();
      for (;;) {
        if (isOp("*") || isOp("/")) {
          const times = tokens[p++].v === "*", b = unary();
          ops++;
          a = times ? mul(a, b) : div(a, b);
        } else if (peek().t === "of") {
          p++;
          const b = unary();
          ops++;
          a = a.pct ? { v: b.v * a.v / 100, u: b.u } : mul(a, b);
        } else return a;
      }
    }
    function unary() {
      if (isOp("-")) { p++; const q = unary(); return { ...q, v: -q.v }; }
      if (isOp("+")) { p++; return unary(); }
      let q = primary();
      if (isOp("%")) { p++; q = { ...q, pct: true, lit: false }; }
      if (!isOp("^")) return q;
      p++; ops++;
      const exp = unary();
      if (q.u || exp.u) throw incompatible(q.u || exp.u, q.u || exp.u);
      return { v: Math.pow(q.v, exp.v), u: null };
    }
    function withUnit(q) {
      const t = peek();
      if (t.t === "cur") { p++; return { ...q, u: t.v }; }
      if (t.t !== "unit") return q;
      p++;
      let out = { ...q, u: t.v };
      // "5 ft 3 in"
      while (peek().t === "num" && peek(1).t === "unit" && UNITS[peek(1).v].dim === UNITS[out.u].dim && UNITS[out.u].dim !== "money") {
        out = { ...add(out, { v: peek().v, u: peek(1).v }), lit: q.lit };
        p += 2;
      }
      return out;
    }
    function primary() {
      const t = tokens[p++] || {};
      switch (t.t) {
        case "num": return withUnit({ v: t.v, u: null, lit: true });
        case "cur": {
          const n = tokens[p++];
          if (!n || n.t !== "num") throw syntax();
          const q = { v: n.v, u: t.v, lit: true };
          if (peek().t === "unit" && UNITS[peek().v].dim === "money") q.u = tokens[p++].v; // "$32 USD"
          return q;
        }
        case "op": {
          if (t.v !== "(") throw syntax();
          const q = expr();
          close();
          return withUnit({ ...q, lit: false });
        }
        case "var": return { ...ctx.vars[t.v], lit: false };
        case "ans":
          if (!ctx.ans) throw fail("No previous answer", true);
          return { ...ctx.ans, lit: false };
        case "agg": ops++; return { ...aggregate(ctx.block, t.v), lit: false };
        case "fn": {
          let arg;
          if (isOp("(")) { p++; arg = expr(); close(); } else arg = primary();
          ops++;
          const keep = KEEP_UNIT.includes(t.v);
          if (arg.u && !keep) throw fail(`Invalid argument for ${t.v}`, true);
          const v = FUNCS[t.v](arg.v);
          if (!Number.isFinite(v)) throw fail("Not a number", true);
          return { v, u: keep ? arg.u : null, lit: false };
        }
        default: throw syntax();
      }
    }

    const q = expr();
    if (p < tokens.length) throw syntax();
    return { q, ops };
  }

  function evaluate(text, ctx) {
    const { tokens, noise } = classify(lex(text), ctx);
    if (!tokens.length) throw syntax();
    try {
      return parse(tokens, ctx);
    } catch (e) {
      throw Object.assign(e, { noise, hasNumber: tokens.some((t) => t.t === "num") });
    }
  }

  const DEFINITION = /^\s*([A-Za-z]\w*)\s*([:=])(?!\/\/)\s*(\S.*)$/;

  // One math line (NoteEngine.evaluateLine): answers lines ending in "=" and lines that do some math.
  function mathLine(line, ctx) {
    let text = line, strict = false;
    while (/[=\s]$/.test(text)) { strict = strict || text.endsWith("="); text = text.slice(0, -1); }
    const out = {};
    const answer = (q) => {
      out.result = format(q);
      ctx.ans = q;
      if (!q.pct) ctx.block.push(q);
    };
    const def = DEFINITION.exec(text);
    if (def && !RESERVED.includes(def[1].toLowerCase())) {
      out.def = { name: def[1], sep: def[2] };
      try {
        const e = evaluate(def[3], ctx);
        ctx.vars[def[1].toLowerCase()] = { v: e.q.v, u: e.q.u, pct: e.q.pct };
        if (strict || e.ops) answer(e.q);
      } catch (err) {
        if (strict) out.error = err.message;
      }
      return out;
    }
    const eq = text.indexOf("=");
    if (eq >= 0) { text = text.slice(0, eq); strict = true; }
    try {
      const e = evaluate(text, ctx);
      let q = e.q;
      // "$23 =" shows euros; "€20 =" shows dollars.
      if (strict && !e.ops && q.lit && q.u && UNITS[q.u].dim === "money") q = convert(q, q.u === PRIMARY ? SECONDARY : PRIMARY);
      if (strict || e.ops) answer(q);
    } catch (err) {
      if (strict || (err.semantic && !err.noise && err.hasNumber)) out.error = err.message;
    }
    return out;
  }

  // ---------- sum / avg / count ----------

  const TALLY = /(^|[^\w.,])([-−]?)([$€£¥]?)(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d*\.\d+|\d+)(?!\w)(?:\s?([$€£¥]|(?:usd|eur|gbp|jpy)\b))?/gi;

  function tally(lines, mode) {
    const counted = lines.filter((l) => !l.trim().startsWith("//"));
    if (mode === "count") {
      const plural = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;
      const words = counted.join(" ").split(/\s+/).filter(Boolean).length;
      return [plural(counted.filter((l) => l.trim()).length, "item"), plural(counted.length, "line"), plural(words, "word"),
        plural(counted.reduce((n, l) => n + [...l].length, 0), "character")].join(" · ");
    }
    const found = counted.flatMap((l) => [...l.matchAll(TALLY)].map((m) => ({
      v: (m[2] ? -1 : 1) * parseFloat(m[4].replace(/,/g, "")),
      code: SYMBOLS[m[3]] || (m[5] && (SYMBOLS[m[5]] || m[5].toUpperCase())) || null,
    })));
    const target = (found.find((f) => f.code) || {}).code;
    const total = found.reduce((t, f) => t + (f.code && target && f.code !== target ? f.v / RATES[f.code] * RATES[target] : f.v), 0);
    const avg = mode === "avg", value = avg ? total / (found.length || 1) : total;
    return (avg ? "Average: " : "Total: ") + (target ? currency(value, target) : number(value));
  }

  // ---------- Timers ----------

  function duration(token) {
    let m;
    if ((m = /^(\d+):(\d{1,2})$/.exec(token))) return { s: m[1] * 60 + +m[2], rank: 2 };
    if ((m = /^(\d+)h(\d+)m?$/.exec(token))) return { s: m[1] * 3600 + m[2] * 60, rank: 3 };
    if ((m = /^(\d+(?:\.\d+)?)(h|hrs?|hours?|m|mins?|minutes?|s|secs?|seconds?)?$/.exec(token))) {
      const u = (m[2] || "m")[0];
      return { s: m[1] * { h: 3600, m: 60, s: 1 }[u], rank: m[2] ? { h: 3, m: 2, s: 1 }[u] : 0 };
    }
    return null;
  }

  // "timer", "timer 5m tea", "timer 5:30", "timer 1h 30m", "timer 25 5", "timer pomo", "timer breathe"
  function parseTimer(firstLine) {
    const tokens = firstLine.trim().split(/\s+/);
    const kinds = ["stopwatch", "countdown", "pomodoro", "pomo", "breathe"];
    let hint = tokens.shift().toLowerCase().replace(/:$/, "");
    if (hint === "timer" && kinds.includes((tokens[0] || "").toLowerCase())) hint = tokens.shift().toLowerCase();
    const durations = [];
    let prevRank = -1, d;
    while (tokens.length && (d = duration(tokens[0].toLowerCase()))) {
      tokens.shift();
      if (durations.length && prevRank > d.rank && d.rank > 0) durations[durations.length - 1] += d.s; // "1h 30m"
      else durations.push(d.s);
      prevRank = d.rank;
    }
    const spec = (kind, extra) => ({ kind, name: tokens.join(" "), ...extra });
    const n = durations.length;
    if (hint === "stopwatch" || hint === "breathe") return n ? null : spec(hint);
    if (hint === "pomodoro" || hint === "pomo" || n === 2) {
      const [work = 1500, rest = 300] = durations;
      return n > 2 || !work || !rest ? null : spec("pomodoro", { work, rest });
    }
    if (n === 1) return durations[0] > 0 ? spec("countdown", { total: durations[0] }) : null;
    return n ? null : spec("stopwatch");
  }

  function clock(seconds) {
    const s = Math.max(0, Math.floor(seconds)), h = Math.floor(s / 3600), two = (x) => String(x).padStart(2, "0");
    return (h ? h + ":" : "") + two(Math.floor(s / 60) % 60) + ":" + two(s % 60);
  }

  // The text next to the timer line, e.g. "24:59 · work 1 · tea".
  function timerStatus(spec, elapsed) {
    let parts;
    if (spec.kind === "stopwatch") parts = [clock(elapsed)];
    else if (spec.kind === "countdown") parts = [elapsed >= spec.total ? "Done" : clock(Math.ceil(spec.total - elapsed))];
    else if (spec.kind === "breathe") parts = [elapsed % 10 < 4 ? "Breathe in." : "Breathe out."];
    else {
      const cycle = spec.work + spec.rest, n = Math.floor(elapsed / cycle) + 1, into = elapsed % cycle;
      parts = into < spec.work ? [clock(Math.ceil(spec.work - into)), "work " + n] : [clock(Math.ceil(cycle - into)), "break " + n];
    }
    return [...parts, spec.name].filter(Boolean).join(" · ");
  }

  const timerMessage = (spec) => ({ stopwatch: "Stopwatch started", countdown: "Countdown started", breathe: "Breathing started" }[spec.kind]
    || `${Math.round(spec.work / 60)}/${Math.round(spec.rest / 60)} Pomodoro started`);

  // ---------- :: commands (from the bundled date, finance and random extensions) ----------

  const MONTHS = "January February March April May June July August September October November December".split(" ");

  function runCommand(line, now = new Date(), random = Math.random) {
    const m = /^\s*::([A-Za-z_]+)\s*(?:\((.*)\))?\s*$/.exec(line);
    if (!m) return null;
    const args = m[2] ? m[2].split(",").map((s) => s.trim()).filter(Boolean) : [];
    const pick = (list) => list[Math.floor(random() * list.length)];
    const date = (offset) => {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
      return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
    };
    switch (m[1].toLowerCase()) {
      case "today": return date(Number(args[0]) || 0);
      case "tomorrow": return date(1);
      case "yesterday": return date(-1);
      case "tip": {
        const [amount, percent = 18, people = 1] = args.map(Number);
        if (!(amount >= 0 && percent >= 0 && people >= 1)) return null;
        const tip = amount * percent / 100, total = amount + tip;
        return `Tip: ${number(tip)} · Total: ${number(total)}` + (people > 1 ? ` · Each: ${number(total / people)}` : "");
      }
      case "pick": return args.length ? pick(args) : null;
      case "coin": return pick(["Heads", "Tails"]);
      case "dice": return String(1 + Math.floor(random() * 6));
      default: return null;
    }
  }

  // ---------- A whole note ----------

  function analyze(text) {
    const lines = text.split("\n");
    const head = /^\s*([A-Za-z]+)(?=$|[\s:])/.exec(lines[0]);
    const mode = (head && KEYWORDS[head[1].toLowerCase()]) || "plain";
    const start = head ? lines[0].indexOf(head[1]) : 0;
    const out = { mode, keyword: mode === "plain" ? null : { start, end: start + head[1].length }, lines: lines.map((t) => ({ text: t })) };
    const tallies = mode === "sum" || mode === "avg" || mode === "count";
    out.lines.forEach((l, i) => {
      const t = l.text.trim();
      if (i && t.startsWith("//") && (tallies || mode === "math")) l.comment = true;
      else if (i && t.startsWith("#") && (mode === "math" || mode === "list")) l.header = true;
    });
    if (mode === "math") {
      const ctx = { vars: {}, ans: null, block: [] };
      out.lines.forEach((l, i) => {
        if (!i || l.comment || l.header) return;
        if (!l.text.trim()) { ctx.block = []; return; } // a blank line starts a new running total
        Object.assign(l, mathLine(l.text, ctx), { vars: Object.keys(ctx.vars) });
      });
    } else if (tallies) out.summary = tally(lines.slice(1), mode);
    else if (mode === "timer") out.timer = parseTimer(lines[0]);
    return out;
  }

  return { analyze, mathLine, tally, parseTimer, timerStatus, timerMessage, runCommand, format, number };
})();

/* ---------------------------------------------------------------------------------------------------------- */

function initPage() {
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const finePointer = matchMedia("(pointer: fine)");
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => [...document.querySelectorAll(sel)];
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const span = (cls, text) => `<span class="${cls}">${esc(text)}</span>`;
  // Wraps each match of `re` in a span whose class `classOf(match)` picks.
  const wrap = (text, re, classOf) => {
    let out = "", last = 0;
    for (const m of text.matchAll(re)) { out += esc(text.slice(last, m.index)) + span(classOf(m), m[0]); last = m.index + m[0].length; }
    return out + esc(text.slice(last));
  };
  const caretLine = () => input.value.slice(0, input.selectionEnd).split("\n").length - 1;

  /* ---------- The live window ---------- */

  const win = $("#sn-window"), input = $("#sn-input"), mirror = $("#sn-mirror"), body = $("#sn-body");
  const toastEl = $("#sn-toast"), live = $("#sn-live");
  const blank = () => ({ name: "", text: "", checked: new Set() });
  const deck = $$("template[data-note]").map((t) => ({
    name: t.dataset.note, text: t.content.textContent.trim(), checked: new Set(t.dataset.note === "list" ? [1] : []),
  }));
  let current = 0, lastLines = [], timer = null;

  $("#sn-date").textContent = new Date().toLocaleDateString("en-US", { month: "short", day: "numeric" });

  let toastTimer;
  function toast(message, kind = "success") {
    toastEl.textContent = live.textContent = message;
    toastEl.dataset.kind = kind;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove("show"), 2200);
  }

  // Checked items stay on their lines while lines are added or removed above or below them.
  function remapChecked(note, before, after) {
    let head = 0, tail = 0;
    while (head < before.length && head < after.length && before[head] === after[head]) head++;
    while (tail < before.length - head && tail < after.length - head && before[before.length - 1 - tail] === after[after.length - 1 - tail]) tail++;
    const shift = after.length - before.length;
    note.checked = new Set([...note.checked].flatMap((i) => (i < head || (!shift && i < before.length - tail) ? [i] : i >= before.length - tail ? [i + shift] : [])));
  }

  const CODE = /(\/\/.*$|#.*$)|("(?:[^"\\]|\\.)*"?|'(?:[^'\\]|\\.)*'?|`[^`]*`?)|\b(\d+(?:\.\d+)?)\b|\b(const|let|var|function|return|if|else|for|while|def|class|import|from|func|struct|fn|pub|true|false|null|nil|None|new|await|async)\b|\b[A-Za-z_]\w*(?=\()/g;
  const markVars = (text, vars) => (vars.length ? wrap(text, new RegExp(`\\b(${vars.join("|")})\\b`, "gi"), () => "vu") : esc(text));

  function lineHTML(info, i, a) {
    const text = info.text;
    if (!i && a.keyword) {
      const { start, end } = a.keyword, whole = a.mode === "timer"; // a timer command is coloured whole
      return esc(text.slice(0, start)) + span("k", text.slice(start, whole ? undefined : end)) + (whole ? "" : esc(text.slice(end)));
    }
    if (info.comment) return span("cm", text);
    if (info.header) return span("hd", text);
    if (a.mode === "code" && i) return wrap(text, CODE, (m) => (m[1] ? "cm" : m[2] ? "st" : m[3] ? "nu" : m[4] ? "kc" : "fn"));
    if (/^\s*::[A-Za-z_]/.test(text)) return span("ext", text);
    if (!info.vars) return esc(text);
    if (!info.def) return markVars(text, info.vars);
    // name, colon (or =), then the expression: variable assignment, colon and use each get their colour
    const { name, sep } = info.def, at = text.indexOf(name), cut = text.indexOf(sep, at + name.length);
    return esc(text.slice(0, at)) + span("vd", name) + esc(text.slice(at + name.length, cut)) + span("vc", sep)
      + markVars(text.slice(cut + 1), info.vars.filter((v) => v !== name.toLowerCase()));
  }

  function render() {
    const note = deck[current], text = input.value, lines = text.split("\n");
    remapChecked(note, lastLines, lines);
    lastLines = lines;
    note.text = text;
    const a = Engine.analyze(text);
    win.dataset.mode = a.mode;
    let html = "";
    a.lines.forEach((info, i) => {
      const item = a.mode === "list" && i && info.text.trim() && !info.header, done = item && note.checked.has(i);
      const gap = /\s$/.test(info.text) ? "res" : "res gap";
      let inner = lineHTML(info, i, a);
      if (info.result) inner += `<span class="${gap}"><button type="button" class="rb" tabindex="-1" data-copy="${esc(info.result)}" title="Copy">${esc(info.result)}</button></span>`;
      else if (info.error) inner += `<span class="${gap} err">${esc(info.error)}</span>`;
      if (!i && a.mode === "timer") inner += `<span class="res gap"><span class="tm" id="sn-timer"></span></span>`;
      const box = item ? `<button type="button" class="cb" role="checkbox" aria-checked="${done}" data-line="${i}" aria-label="${esc(info.text.trim())}"></button>` : "";
      html += `<div class="l${done ? " done" : ""}">${box}${inner}</div>`;
    });
    if (a.summary) html += `<div class="l"></div><div class="l sum">${esc(a.summary)}</div>`;
    mirror.innerHTML = html;
    syncTimer(a);
    announce(a);
  }

  // Screen readers hear the answer on the caret's line once typing pauses.
  let announceTimer, lastAnnounced = "";
  function announce(a) {
    clearTimeout(announceTimer);
    announceTimer = setTimeout(() => {
      const line = caretLine(), info = a.lines[line] || {};
      const said = (info.result ? "Equals " + info.result : info.error) || (line && a.summary) || "";
      if (said && said !== lastAnnounced) live.textContent = said;
      lastAnnounced = said;
    }, 700);
  }

  // Timer notes start once the first line settles (the app starts them on Return).
  let timerWait;
  function syncTimer(a) {
    const key = a.timer ? JSON.stringify(a.timer) : null;
    if (timer && timer.key === key) return paintTimer();
    clearTimeout(timerWait);
    if (timer) clearInterval(timer.interval);
    timer = null;
    if (key) timerWait = setTimeout(() => {
      timer = { key, spec: a.timer, start: performance.now(), interval: setInterval(paintTimer, 250) };
      paintTimer();
      toast(Engine.timerMessage(a.timer));
    }, 450);
  }
  function paintTimer() {
    const el = $("#sn-timer");
    if (el && timer) el.textContent = Engine.timerStatus(timer.spec, (performance.now() - timer.start) / 1000);
  }

  function caretIntoView() {
    const el = mirror.children[caretLine()];
    if (!el) return;
    const pad = parseFloat(getComputedStyle(mirror).paddingBottom), bottom = el.offsetTop + el.offsetHeight;
    if (bottom > body.scrollTop + body.clientHeight - pad) body.scrollTop = bottom - body.clientHeight + pad;
    else if (el.offsetTop < body.scrollTop + 8) body.scrollTop = Math.max(0, el.offsetTop - 40);
  }

  function focusEnd() {
    input.focus({ preventScroll: true });
    input.setSelectionRange(input.value.length, input.value.length);
  }

  function show(index, focus) {
    // Like the app, an empty note cleans itself up when you move away from it.
    if (index !== current && !deck[current].text.trim() && deck.length > 1) {
      deck.splice(current, 1);
      if (index > current) index--;
      toast("Empty note deleted", "neutral");
    }
    current = Math.max(0, Math.min(index, deck.length - 1));
    input.value = deck[current].text;
    lastLines = input.value.split("\n");
    body.scrollTop = 0;
    render();
    $("#sn-pos").textContent = `${current + 1} of ${deck.length}`;
    $$("[data-load]").forEach((b) => b.setAttribute("aria-pressed", deck[current].name === b.dataset.load));
    if (focus) focusEnd();
  }

  function newNote() {
    if (deck[0].text.trim()) {
      if (!deck[current].text.trim()) deck.splice(current, 1);
      deck.unshift(blank());
      current = 0;
    }
    show(0, true);
  }

  function toggleLine(line) {
    const { checked } = deck[current];
    if (!checked.delete(line)) checked.add(line);
    render();
  }

  input.addEventListener("input", () => {
    // List items check off with "/x" at the end of the line.
    const end = input.selectionEnd, line = caretLine();
    if (win.dataset.mode === "list" && line && input.value.slice(0, end).endsWith("/x")) {
      input.setRangeText("", end - 2, end, "end");
      deck[current].checked.add(line);
    }
    render();
    caretIntoView();
  });

  input.addEventListener("keydown", (e) => {
    const mod = e.metaKey || e.ctrlKey, at = input.selectionStart;
    if (e.key === "Enter" && !e.shiftKey && !mod && at === input.selectionEnd) {
      // Return on a :: line runs the command in place.
      const start = input.value.lastIndexOf("\n", at - 1) + 1, nl = input.value.indexOf("\n", at), end = nl < 0 ? input.value.length : nl;
      const output = Engine.runCommand(input.value.slice(start, end));
      if (output !== null) {
        e.preventDefault();
        input.setRangeText(output, start, end, "end");
        render();
        live.textContent = output;
      }
    }
    if (mod && e.shiftKey && e.key.toLowerCase() === "k" && win.dataset.mode === "list" && caretLine()) {
      e.preventDefault();
      toggleLine(caretLine());
    }
  });
  input.addEventListener("keyup", (e) => { if (/^(Arrow|Page)/.test(e.key)) caretIntoView(); });

  // Checkboxes and answers live in the mirror; clicking them keeps the caret in the note.
  mirror.addEventListener("mousedown", (e) => { if (e.target.closest("button")) e.preventDefault(); });
  mirror.addEventListener("click", (e) => {
    const box = e.target.closest(".cb"), result = e.target.closest(".rb");
    if (box) toggleLine(+box.dataset.line);
    if (result) copy(result.dataset.copy).then(() => toast("Copied " + result.dataset.copy));
  });

  const load = (name) => show(Math.max(0, deck.findIndex((n) => n.name === name)));
  $$("[data-load]").forEach((b) => b.addEventListener("click", () => { load(b.dataset.load); if (finePointer.matches) focusEnd(); }));
  $$("[data-try]").forEach((b) => b.addEventListener("click", () => {
    load(b.dataset.try);
    $("#demo").scrollIntoView({ behavior: reduceMotion.matches ? "auto" : "smooth", block: "center" });
    setTimeout(focusEnd, reduceMotion.matches ? 0 : 450);
  }));

  $("#sn-new").addEventListener("click", newNote);
  $("#sn-prev").addEventListener("click", () => (current ? show(current - 1) : newNote()));
  $("#sn-next").addEventListener("click", () => show(current + 1));
  $("#sn-front").addEventListener("click", () => show(0));
  $("#sn-delete").addEventListener("click", () => {
    deck.splice(current, 1);
    if (!deck.length) deck.push(blank());
    current = Math.min(current, deck.length - 1);
    show(current);
    toast("Moved to The Void", "neutral");
  });

  show(0);

  /* ---------- ⌥A works on this page too ---------- */

  const caps = { Alt: $("#cap-option"), KeyA: $("#cap-a") };
  const press = (e, down) => {
    const cap = e.key === "Alt" ? caps.Alt : e.code === "KeyA" && (e.altKey || !down) ? caps.KeyA : null;
    if (cap) cap.classList.toggle("down", down);
  };
  addEventListener("keydown", (e) => {
    press(e, true);
    if (e.altKey && e.code === "KeyA" && !e.metaKey && !e.ctrlKey && !e.target.closest("input, textarea, [contenteditable]")) {
      e.preventDefault();
      $("#demo").scrollIntoView({ behavior: reduceMotion.matches ? "auto" : "smooth", block: "center" });
      input.focus({ preventScroll: true });
    }
  });
  addEventListener("keyup", (e) => press(e, false));
  addEventListener("blur", () => Object.values(caps).forEach((c) => c.classList.remove("down")));

  /* ---------- Copy buttons ---------- */

  const copy = (text) => (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject(new Error("no clipboard")));
  $$("[data-copy-target]").forEach((btn) => btn.addEventListener("click", () => {
    copy($(btn.dataset.copyTarget).textContent.trim()).then(() => {
      btn.classList.add("done");
      btn.lastElementChild.textContent = "Copied";
      setTimeout(() => { btn.classList.remove("done"); btn.lastElementChild.textContent = "Copy"; }, 1800);
    }, () => getSelection().selectAllChildren($(btn.dataset.copyTarget)));
  }));

  /* ---------- Motion ---------- */

  const nav = $(".nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Sections fade up once; bento animations only run while their card is on screen.
  const reveal = new IntersectionObserver((entries) => entries.forEach((en) => {
    if (en.isIntersecting) { en.target.classList.add("in"); reveal.unobserve(en.target); }
  }), { rootMargin: "0px 0px -8% 0px" });
  $$("[data-reveal]").forEach((el) => reveal.observe(el));
  const play = new IntersectionObserver((entries) => entries.forEach((en) => en.target.classList.toggle("play", en.isIntersecting)), { threshold: 0.15 });
  $$(".card").forEach((card) => {
    play.observe(card);
    // a soft light follows the pointer
    card.addEventListener("pointermove", (e) => {
      const r = card.getBoundingClientRect();
      card.style.setProperty("--mx", `${e.clientX - r.left}px`);
      card.style.setProperty("--my", `${e.clientY - r.top}px`);
    });
  });

  // The hero window leans toward the pointer, and settles flat while you type.
  const tilt = $("#tilt"), hero = $(".hero");
  const lean = (x, y) => { tilt.style.setProperty("--ry", `${x}deg`); tilt.style.setProperty("--rx", `${y}deg`); };
  let frame = 0;
  hero.addEventListener("pointermove", (e) => {
    if (reduceMotion.matches || !finePointer.matches || win.contains(document.activeElement)) return;
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => {
      const r = tilt.getBoundingClientRect();
      lean((((e.clientX - r.left - r.width / 2) / innerWidth) * 9).toFixed(2), (((r.top + r.height / 2 - e.clientY) / innerHeight) * 7).toFixed(2));
    });
  });
  hero.addEventListener("pointerleave", () => lean(0, 0));
  input.addEventListener("focus", () => lean(0, 0));
}

if (typeof document !== "undefined") initPage();
