"use strict";
/* Super Notes website: the nav, feature notes that type themselves, the compare carousel and the copy button. */

(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const wide = matchMedia("(min-width: 880px)"); // matches the stacked-features breakpoint in style.css
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  /* ---------- Nav: hides on the way down, comes back on the way up; a menu button on phones ---------- */

  const nav = $("#nav"), toggle = $(".nav-toggle", nav);
  const setMenu = (open) => { nav.classList.toggle("is-open", open); toggle.setAttribute("aria-expanded", String(open)); };
  let lastY = scrollY;
  addEventListener("scroll", () => {
    const y = scrollY;
    if (Math.abs(y - lastY) < 4) return;
    const down = y > lastY && y > 64;
    if (down) setMenu(false);
    nav.classList.toggle("is-hidden", down && !nav.contains(document.activeElement));
    lastY = y;
  }, { passive: true });
  nav.addEventListener("focusin", () => nav.classList.remove("is-hidden"));
  toggle.addEventListener("click", () => setMenu(!nav.classList.contains("is-open")));
  $$(".nav-links a", nav).forEach((a) => a.addEventListener("click", () => setMenu(false)));
  addEventListener("keydown", (e) => {
    if (e.key === "Escape" && nav.classList.contains("is-open")) { setMenu(false); toggle.focus(); }
  });

  /* ---------- Feature notes ----------
     A note's finished text is in the page. Playing it re-types that text one character at a time;
     elements marked data-instant (answers, pasted lines, pills) appear whole, data-later groups switch on
     afterwards (a ticked box, a shrunk link, a changed variable), and data-countdown ticks down. */

  function plan(root) {
    const steps = [];
    (function walk(node) {
      for (const child of node.childNodes) {
        if (child.nodeType === Node.TEXT_NODE) {
          for (let i = 0; i < child.data.length; i++) steps.push(child.data[i] === "\n" ? 150 : 16 + Math.random() * 26);
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          if (child.hasAttribute("data-instant")) steps.push(Number(child.dataset.pause) || 140);
          else walk(child);
        }
      }
    })(root);
    return steps;
  }

  // Keeps the first `left` steps of `node` and drops the rest; remembers where the caret goes.
  function cut(node, state) {
    for (let child = node.firstChild; child;) {
      const next = child.nextSibling;
      if (state.left <= 0) child.remove();
      else if (child.nodeType === Node.TEXT_NODE) {
        if (child.data.length >= state.left) { child.data = child.data.slice(0, state.left); state.left = 0; state.end = child; }
        else state.left -= child.data.length;
      } else if (child.nodeType === Node.ELEMENT_NODE) {
        if (child.hasAttribute("data-instant")) { state.left -= 1; if (!state.left) state.end = child; }
        else cut(child, state);
      }
      child = next;
    }
  }

  const clock = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

  class Player {
    constructor(article) {
      this.note = $(".note", article);
      this.note.setAttribute("aria-hidden", "true");
      this.text = $(".note-text", this.note);
      this.anim = article.dataset.kind === "anim";
      this.delay = Number(article.dataset.delay) || 0;
      this.timers = [];
      if (this.text) { this.final = this.text.cloneNode(true); this.steps = plan(this.final); }
      this.track = $(".deck-track", this.note);
    }

    stop() {
      this.timers.forEach(clearTimeout);
      this.timers.forEach(clearInterval);
      this.timers = [];
      this.note.classList.remove("play");
      if (this.track) this.deck(0);
    }

    after(ms, fn) { this.timers.push(setTimeout(fn, ms)); }

    render(k, caret = true) {
      const copy = this.final.cloneNode(true), state = { left: k, end: null };
      cut(copy, state);
      if (caret) {
        const c = document.createElement("span");
        c.className = "caret";
        if (state.end) state.end.after(c); else copy.prepend(c);
      }
      this.text.replaceChildren(...copy.childNodes);
    }

    deck(i) {
      this.track.style.transform = `translateX(${-i * 33.3334}%)`;
      $(".deck-count", this.note).textContent = `${i + 1} of 3`;
    }

    // What happens once the text is in: later groups switch on in order, countdowns start.
    settle(animate) {
      const groups = new Map();
      $$("[data-later]", this.text).forEach((el) => {
        const key = Number(el.dataset.later);
        groups.set(key, [...(groups.get(key) || []), el]);
      });
      [...groups.keys()].sort((a, b) => a - b).forEach((key, i) => {
        const on = () => groups.get(key).forEach((el) => el.classList.add("on"));
        if (animate) this.after(900 + i * 900, on); else on();
      });
      if (!animate) return;
      $$("[data-countdown]", this.text).forEach((el) => {
        let left = Number(el.dataset.countdown);
        this.timers.push(setInterval(() => { left = Math.max(0, left - 1); el.textContent = clock(left); }, 1000));
      });
    }

    play() {
      this.stop();
      if (reduce.matches) {
        if (this.text) { this.render(this.steps.length, false); this.settle(false); }
        return;
      }
      void this.note.offsetWidth; // restart CSS animations
      this.note.classList.add("play");
      if (this.track) {
        let i = 0;
        this.timers.push(setInterval(() => this.deck(i = (i + 1) % 3), 2200));
      }
      if (this.anim || !this.text) return;
      let k = 0;
      this.render(0);
      const step = () => {
        this.render(++k);
        if (k >= this.steps.length) this.settle(true);
        else this.after(this.steps[k], step);
      };
      this.after(this.delay + 450 + this.steps[0], step);
    }
  }

  const articles = $$(".feat");
  const players = articles.map((a) => new Player(a));
  const tabs = articles.map((a) => $(".feat-tab", a));
  let active = Math.max(0, articles.findIndex((a) => a.classList.contains("is-active")));
  let featsVisible = false;

  articles.forEach((a, i) => {
    const media = $(".feat-media", a);
    media.id = `feat-${i + 1}`;
    tabs[i].setAttribute("aria-controls", media.id);
  });

  function select(i, focus) {
    active = i;
    articles.forEach((a, j) => {
      a.classList.toggle("is-active", i === j);
      tabs[j].setAttribute("aria-expanded", String(i === j));
      if (i !== j) players[j].stop();
    });
    if (focus) tabs[i].focus();
    if (featsVisible) players[i].play();
  }

  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => { if (wide.matches) select(i); });
    tab.addEventListener("keydown", (e) => {
      const move = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
      if (!move || !wide.matches) return;
      e.preventDefault();
      select((i + move + tabs.length) % tabs.length, true);
    });
  });

  // Wide screens: the selected note plays while the section is on screen. Phones: each note plays as it scrolls in.
  const sectionWatch = new IntersectionObserver(([en]) => {
    featsVisible = en.isIntersecting;
    if (featsVisible) players[active].play(); else players[active].stop();
  }, { threshold: 0.25 });
  const noteWatch = new IntersectionObserver((entries) => entries.forEach((en) => {
    const p = players[articles.indexOf(en.target)];
    if (en.isIntersecting) p.play(); else p.stop();
  }), { threshold: 0.6 });

  function layout() {
    players.forEach((p) => p.stop());
    sectionWatch.disconnect();
    noteWatch.disconnect();
    if (wide.matches) {
      tabs.forEach((t) => { t.removeAttribute("tabindex"); t.removeAttribute("aria-disabled"); });
      select(active);
      sectionWatch.observe($(".feats"));
    } else {
      // Every feature is shown on phones, so the names are headings rather than buttons.
      tabs.forEach((t) => { t.setAttribute("tabindex", "-1"); t.setAttribute("aria-disabled", "true"); t.removeAttribute("aria-expanded"); });
      articles.forEach((a) => noteWatch.observe(a));
    }
  }
  wide.addEventListener("change", layout);
  reduce.addEventListener("change", layout);
  layout();

  /* ---------- Compare carousel: turns every few seconds while on screen, pauses on hover or focus ---------- */

  const car = $("[data-carousel]");
  const notes = $$(".cmp-note", car), words = $$(".cmp-words > span", car), dots = $$(".dots button", car);
  let slide = 0, auto = true, paused = false, carVisible = false, carTimer = 0;

  function show(i) {
    slide = (i + notes.length) % notes.length;
    notes.forEach((n, j) => n.classList.toggle("is-on", j === slide));
    words.forEach((w, j) => w.classList.toggle("is-on", j === slide));
    dots.forEach((d, j) => (j === slide ? d.setAttribute("aria-current", "true") : d.removeAttribute("aria-current")));
  }
  function schedule() {
    clearTimeout(carTimer);
    if (auto && !paused && carVisible && !reduce.matches) carTimer = setTimeout(() => { show(slide + 1); schedule(); }, 4500);
  }
  dots.forEach((d, i) => d.addEventListener("click", () => { auto = false; clearTimeout(carTimer); show(i); }));
  const pause = (on) => () => { paused = on; schedule(); };
  car.addEventListener("pointerenter", pause(true));
  car.addEventListener("pointerleave", pause(false));
  car.addEventListener("focusin", pause(true));
  car.addEventListener("focusout", (e) => { if (!car.contains(e.relatedTarget)) pause(false)(); });
  new IntersectionObserver(([en]) => { carVisible = en.isIntersecting; schedule(); }, { threshold: 0.3 }).observe(car);

  /* ---------- Copy the install command ---------- */

  const status = $("#copy-status");
  $$("[data-copy]").forEach((btn) => btn.addEventListener("click", async () => {
    const source = $(btn.dataset.copy);
    let label = "Copied";
    try {
      await navigator.clipboard.writeText(source.textContent.trim());
      status.textContent = "Install command copied.";
    } catch (_) {
      getSelection().selectAllChildren(source);
      label = "Press ⌘C";
      status.textContent = "Install command selected. Press Command C to copy it.";
    }
    btn.textContent = label;
    btn.classList.add("is-done");
    setTimeout(() => { btn.textContent = "Copy"; btn.classList.remove("is-done"); }, 1800);
  }));
})();
