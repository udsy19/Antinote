// Super Notes extension: text (MIT)
// Case and identifier conversions for the current line (or for the text passed in parentheses).
(function () {
  var ext = new Extension({ name: "text", version: "1.0.0", author: "Super Notes", category: "Text Formatting", dataScope: "line" });

  function words(s) {
    return s.replace(/([a-z0-9])([A-Z])/g, "$1 $2")
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .split(/[^A-Za-z0-9]+/).filter(function (w) { return w.length > 0; });
  }
  function cap(w) { return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase(); }

  var transforms = [
    ["upper", "UPPERCASE the line.", ["uppercase"], function (s) { return s.toUpperCase(); }],
    ["lower", "lowercase the line.", ["lowercase"], function (s) { return s.toLowerCase(); }],
    ["title", "Capitalize Every Word.", ["titlecase"], function (s) {
      return s.replace(/[A-Za-zÀ-ÿ0-9][^\s-]*/g, function (w) { return cap(w); });
    }],
    ["sentence", "Sentence case: capitalize the first letter of each sentence.", ["sentencecase"], function (s) {
      return s.toLowerCase().replace(/(^\s*|[.!?]\s+)([a-zà-ÿ])/g, function (m, p, c) { return p + c.toUpperCase(); });
    }],
    ["slug", "Make a URL slug: my-note-title.", ["slugify"], function (s) { return words(s).join("-").toLowerCase(); }],
    ["snake", "Make a snake_case identifier.", ["snake_case"], function (s) { return words(s).join("_").toLowerCase(); }],
    ["camel", "Make a camelCase identifier.", ["camel_case"], function (s) {
      var w = words(s);
      return w.map(function (x, i) { return i === 0 ? x.toLowerCase() : cap(x); }).join("");
    }]
  ];

  var input = new Parameter({ type: "paragraph", name: "text", helpText: "Text to convert instead of the line", default: "", required: false });

  transforms.forEach(function (t) {
    new Command({
      name: t[0], helpText: t[1], aliases: t[2], type: "replaceLine", parameters: [input], extension: ext,
      tutorials: [
        new TutorialCommand({ command: t[0], description: t[1] }),
        new TutorialCommand({ command: t[0] + "(some text)", description: "Convert the given text" })
      ],
      execute: function (payload) {
        var given = this.getParsedParams(payload)[0];
        var line = payload.line || "";
        var out = given ? (line ? line + " " : "") + t[3](given) : t[3](line);
        return new ReturnObject({ status: "success", message: "Converted", payload: out });
      }
    });
  });

  new Command({
    name: "count_chars", helpText: "Count characters and words on the line.", aliases: ["count"], type: "insert",
    parameters: [input], extension: ext,
    tutorials: [new TutorialCommand({ command: "count_chars", description: "Shows the counts without changing the note" })],
    execute: function (payload) {
      var s = this.getParsedParams(payload)[0] || payload.line || "";
      var chars = Array.from(s).length, noSpaces = Array.from(s.replace(/\s/g, "")).length;
      var w = s.trim() === "" ? 0 : s.trim().split(/\s+/).length;
      return new ReturnObject({ status: "success", message: chars + " characters (" + noSpaces + " without spaces) · " + w + (w === 1 ? " word" : " words") });
    }
  });
})();
