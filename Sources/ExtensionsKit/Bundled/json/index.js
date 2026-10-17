// Super Notes extension: json (MIT)
(function () {
  var ext = new Extension({ name: "json", version: "1.0.0", author: "Super Notes", category: "Developer", dataScope: "full" });

  function parse(text) {
    var source = (text || "").trim();
    if (source === "") throw new Error("The note has no JSON");
    try { return JSON.parse(source); } catch (e) { throw new Error("Invalid JSON: " + e.message); }
  }
  function run(fn) {
    try { return fn(); } catch (e) { return new ReturnObject({ status: "error", message: e.message }); }
  }
  function describe(v) {
    if (Array.isArray(v)) return "array with " + v.length + (v.length === 1 ? " item" : " items");
    if (v !== null && typeof v === "object") { var n = Object.keys(v).length; return "object with " + n + (n === 1 ? " key" : " keys"); }
    return v === null ? "null" : typeof v;
  }

  new Command({
    name: "format", type: "replaceAll", aliases: ["json_format", "pretty"], extension: ext,
    helpText: "Pretty-print the note's JSON.",
    parameters: [new Parameter({ type: "int", name: "indent", helpText: "Spaces per level (0–8)", default: 2, required: false })],
    tutorials: [new TutorialCommand({ command: "format", description: "Two-space indentation" }),
                new TutorialCommand({ command: "format(4)", description: "Four-space indentation" })],
    execute: function (payload) {
      var indent = Math.max(0, Math.min(8, this.getParsedParams(payload)[0]));
      return run(function () {
        return new ReturnObject({ status: "success", message: "Formatted", payload: JSON.stringify(parse(payload.fullText), null, indent) });
      });
    }
  });

  new Command({
    name: "minify", type: "replaceAll", aliases: ["json_minify"], parameters: [], extension: ext,
    helpText: "Remove all whitespace from the note's JSON.",
    tutorials: [new TutorialCommand({ command: "minify", description: "One compact line" })],
    execute: function (payload) {
      return run(function () {
        return new ReturnObject({ status: "success", message: "Minified", payload: JSON.stringify(parse(payload.fullText)) });
      });
    }
  });

  new Command({
    name: "validate", type: "insert", aliases: ["json_validate"], parameters: [], extension: ext,
    helpText: "Check whether the note is valid JSON (the note is not changed).",
    tutorials: [new TutorialCommand({ command: "validate", description: "Reports Valid JSON or the parse error" })],
    execute: function (payload) {
      return run(function () {
        return new ReturnObject({ status: "success", message: "Valid JSON (" + describe(parse(payload.fullText)) + ")" });
      });
    }
  });
})();
