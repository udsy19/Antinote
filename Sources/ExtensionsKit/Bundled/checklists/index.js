// Super Notes extension: checklists (MIT)
// Works on [ ] / [x] markers (optionally after indentation or a "- " bullet).
(function () {
  var ext = new Extension({ name: "checklists", version: "1.0.0", author: "Super Notes", category: "Text Manipulation", dataScope: "full" });

  var BOX = /^(\s*(?:[-*]\s+)?)\[([ xX])\]/;
  function isChecked(line) { var m = BOX.exec(line); return !!m && m[2] !== " "; }
  function mark(line, checked) {
    return line.replace(BOX, function (all, lead) { return lead + (checked ? "[x]" : "[ ]"); });
  }
  function apply(payload, transform, message) {
    var lines = (payload.fullText || "").split("\n");
    if (!lines.some(function (l) { return BOX.test(l); })) {
      return new ReturnObject({ status: "error", message: "This note has no [ ] checklist items" });
    }
    return new ReturnObject({ status: "success", message: message, payload: transform(lines).join("\n") });
  }

  var commands = [
    ["check_all", "Check every item.", function (l) { return l.map(function (x) { return mark(x, true); }); }],
    ["uncheck_all", "Uncheck every item.", function (l) { return l.map(function (x) { return mark(x, false); }); }],
    ["remove_checked", "Delete checked items.", function (l) { return l.filter(function (x) { return !isChecked(x); }); }],
    ["checked_to_bottom", "Move checked items below the unchecked ones.", function (l) {
      return l.filter(function (x) { return !isChecked(x); }).concat(l.filter(isChecked));
    }]
  ];

  commands.forEach(function (c) {
    new Command({
      name: c[0], helpText: c[1], type: "replaceAll", parameters: [], extension: ext,
      tutorials: [new TutorialCommand({ command: c[0], description: c[1] })],
      execute: function (payload) { return apply(payload, c[2], c[1]); }
    });
  });
})();
