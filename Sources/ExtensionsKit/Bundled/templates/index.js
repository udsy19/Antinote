// Super Notes extension: templates (MIT)
// Depends on "date" for date formatting (global.SuperNotesDate).
(function () {
  var ext = new Extension({ name: "templates", version: "1.0.0", author: "Super Notes", category: "Templates", dataScope: "none", dependencies: ["date"] });

  function dateText(style) { return SuperNotesDate.format(SuperNotesDate.today(), style || SuperNotesDate.style()); }
  function ok(text) { return new ReturnObject({ status: "success", message: "Inserted template", payload: text }); }

  new Command({
    name: "meeting", type: "insert", aliases: ["meeting_notes"], extension: ext,
    helpText: "Meeting notes: attendees, agenda, notes and action items.",
    parameters: [new Parameter({ type: "paragraph", name: "title", helpText: "what the meeting is about", default: "", required: false,
                                 example: "Design review" })],
    tutorials: [new TutorialCommand({ command: "meeting(Design review)", description: "Titled meeting notes" })],
    execute: function (payload) {
      var title = this.getParsedParams(payload)[0];
      return ok([
        "Meeting" + (title ? ": " + title : "") + " — " + dateText(),
        "", "Attendees:", "- ", "", "Agenda:", "1. ", "", "Notes:", "", "", "Action items:", "[ ] "
      ].join("\n"));
    }
  });

  new Command({
    name: "standup", type: "insert", parameters: [], extension: ext,
    helpText: "Daily standup: yesterday, today, blockers.",
    tutorials: [new TutorialCommand({ command: "standup", description: "Standup notes for today" })],
    execute: function () {
      return ok(["Standup — " + dateText(), "", "Yesterday:", "- ", "", "Today:", "- ", "", "Blockers:", "- "].join("\n"));
    }
  });

  new Command({
    name: "journal", type: "insert", aliases: ["diary"], parameters: [], extension: ext,
    helpText: "Journal entry with gratitude, thoughts and today's focus.",
    tutorials: [new TutorialCommand({ command: "journal", description: "Today's journal page" })],
    execute: function () {
      return ok(["Journal — " + dateText("weekday"), "", "Grateful for:", "- ", "", "On my mind:", "", "",
                 "Today's focus:", "[ ] "].join("\n"));
    }
  });
})();
