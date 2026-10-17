// Jotter extension: lines (MIT)
// Whole-note line operations. Each command replaces the note with the transformed lines.
(function () {
  var ext = new Extension({ name: "lines", version: "1.0.0", author: "jotter", category: "Text Manipulation", dataScope: "full" });

  ext.register_preference(new Preference({
    key: "keepFirstLine", label: "Keep the first line in place", type: "bool", defaultValue: false,
    helpText: "Treat the first line as a title (for example a list keyword) and leave it at the top."
  }));

  function apply(payload, transform) {
    var lines = (payload.fullText || "").split("\n");
    var head = getPreference("keepFirstLine") && lines.length > 1 ? [lines.shift()] : [];
    return new ReturnObject({ status: "success", message: "Done", payload: head.concat(transform(lines)).join("\n") });
  }
  function compare(a, b) {
    return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
  }

  var ops = [
    ["sort", "Sort lines A to Z (numbers in numeric order).", ["sort_asc"], function (l) { return l.slice().sort(compare); }],
    ["sort_desc", "Sort lines Z to A.", [], function (l) { return l.slice().sort(compare).reverse(); }],
    ["reverse", "Reverse the order of the lines.", ["reverse_lines"], function (l) { return l.slice().reverse(); }],
    ["shuffle", "Shuffle the lines randomly.", [], function (l) {
      var a = l.slice();
      for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t; }
      return a;
    }],
    ["dedupe", "Remove duplicate lines, keeping the first occurrence.", ["unique"], function (l) {
      var seen = {};
      return l.filter(function (x) { if (seen.hasOwnProperty("k" + x)) return false; seen["k" + x] = true; return true; });
    }],
    ["remove_empty", "Remove blank lines.", [], function (l) { return l.filter(function (x) { return x.trim() !== ""; }); }],
    ["number_lines", "Number the non-empty lines 1., 2., 3. …", [], function (l) {
      var n = 0;
      return l.map(function (x) { return x.trim() === "" ? x : (++n) + ". " + x.replace(/^\s*\d+\.\s+/, ""); });
    }],
    ["trim", "Remove leading and trailing spaces from every line.", ["trim_lines"], function (l) { return l.map(function (x) { return x.trim(); }); }]
  ];

  ops.forEach(function (op) {
    new Command({
      name: op[0], helpText: op[1], aliases: op[2], type: "replaceAll", parameters: [], extension: ext,
      tutorials: [new TutorialCommand({ command: op[0], description: op[1] })],
      execute: function (payload) { return apply(payload, op[3]); }
    });
  });
})();
