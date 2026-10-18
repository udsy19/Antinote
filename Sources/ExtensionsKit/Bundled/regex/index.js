// Super Notes extension: regex (MIT)
(function () {
  var ext = new Extension({ name: "regex", version: "1.0.0", author: "Super Notes", category: "Text Manipulation", dataScope: "full" });

  new Command({
    name: "replace_regex", type: "replaceAll", aliases: ["regex", "sub"], extension: ext,
    helpText: "Replace every match of a regular expression in the note. Use $1, $2 … for groups.",
    parameters: [
      new Parameter({ type: "string", name: "pattern", helpText: "a regex; quote it if it has commas",
                      example: "\\d+" }),
      new Parameter({ type: "string", name: "replacement", helpText: "the new text, $1 for a group",
                      default: "", required: false, example: "#" }),
      new Parameter({ type: "string", name: "flags", helpText: "g all matches, i ignore case", default: "g",
                      required: false, example: "gi" })
    ],
    tutorials: [
      new TutorialCommand({ command: "replace_regex(\\d+, #)", description: "Replace every number with #" }),
      new TutorialCommand({ command: "replace_regex(\"(\\w+)@(\\w+)\", \"$2 at $1\")", description: "Swap groups" }),
      new TutorialCommand({ command: "replace_regex(todo, done, gi)", description: "Case-insensitive" })
    ],
    execute: function (payload) {
      var p = this.getParsedParams(payload);
      if (p[0] === "") return new ReturnObject({ status: "error", message: "Required parameter 'pattern' is missing" });
      var re;
      try { re = new RegExp(p[0], p[2] || "g"); } catch (e) {
        return new ReturnObject({ status: "error", message: "Invalid regular expression: " + e.message });
      }
      var text = payload.fullText || "";
      var count = (text.match(new RegExp(re.source, re.flags.indexOf("g") === -1 ? re.flags + "g" : re.flags)) || []).length;
      return new ReturnObject({ status: "success", message: count + (count === 1 ? " replacement" : " replacements"),
                                payload: text.replace(re, p[1]) });
    }
  });
})();
