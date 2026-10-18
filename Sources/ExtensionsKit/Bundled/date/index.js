// Super Notes extension: date (MIT)
// Dates are computed from now(), the host clock, so they can be pinned in tests.
// Also exposes global.SuperNotesDate for extensions that depend on "date".
(function () {
  var ext = new Extension({ name: "date", version: "1.0.0", author: "Super Notes", category: "Date & Time", dataScope: "none" });

  ext.register_preference(new Preference({
    key: "format", label: "Date format", type: "selectOne", defaultValue: "long",
    options: ["long", "weekday", "iso", "us", "eu"],
    helpText: "long: October 17, 2026 · weekday: Saturday, October 17, 2026 · iso: 2026-10-17 · us: 10/17/2026 · eu: 17/10/2026. Commands also accept a pattern such as YYYY/MM/DD."
  }));

  var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  function two(n) { return (n < 10 ? "0" : "") + n; }

  function format(d, style) {
    var y = d.getFullYear(), m = d.getMonth() + 1, day = d.getDate();
    switch ((style || "long").toLowerCase()) {
      case "iso": return y + "-" + two(m) + "-" + two(day);
      case "us": return two(m) + "/" + two(day) + "/" + y;
      case "eu": return two(day) + "/" + two(m) + "/" + y;
      case "weekday": return DAYS[d.getDay()] + ", " + MONTHS[m - 1] + " " + day + ", " + y;
      case "long": return MONTHS[m - 1] + " " + day + ", " + y;
      default:
        if (/YYYY|MM|DD/.test(style)) {
          return style.replace(/YYYY/g, String(y)).replace(/MM/g, two(m)).replace(/DD/g, two(day));
        }
        return MONTHS[m - 1] + " " + day + ", " + y;
    }
  }

  function today() { var d = new Date(now()); d.setHours(12, 0, 0, 0); return d; }
  function addDays(d, n) { var r = new Date(d.getTime()); r.setDate(r.getDate() + n); return r; }
  function addBusinessDays(d, n) {
    var r = new Date(d.getTime()), step = n < 0 ? -1 : 1, left = Math.abs(n);
    while (left > 0) {
      r.setDate(r.getDate() + step);
      if (r.getDay() !== 0 && r.getDay() !== 6) left--;
    }
    return r;
  }
  function style(override) { return override || getExtensionPreference("date", "format") || "long"; }

  global.SuperNotesDate = { format: format, today: today, addDays: addDays, style: function () { return style(""); } };

  // Blank uses the format chosen in this extension's settings.
  var fmt = new Parameter({ type: "string", name: "format", helpText: "iso, us, eu, long, weekday or a pattern", default: "",
                            required: false, example: "YYYY/MM/DD" });

  function dayCommand(name, base, help, aliases, days) {
    var offset = new Parameter({ type: "int", name: "days", helpText: days.help, default: 0, required: false, example: days.example });
    new Command({
      name: name, parameters: [offset, fmt], type: "insert", helpText: help, aliases: aliases, extension: ext,
      tutorials: [
        new TutorialCommand({ command: name, description: help }),
        new TutorialCommand({ command: name + "(7)", description: "Seven days later" }),
        new TutorialCommand({ command: name + "(0, iso)", description: "As 2026-10-17" })
      ],
      execute: function (payload) {
        var p = this.getParsedParams(payload);
        return new ReturnObject({ status: "success", message: "Inserted date", payload: format(addDays(today(), base + p[0]), style(p[1])) });
      }
    });
  }
  dayCommand("today", 0, "Insert today's date, optionally offset by days.", ["date"],
             { help: "how many days from today", example: "3 or -1" });
  dayCommand("tomorrow", 1, "Insert tomorrow's date, optionally offset by more days.", [],
             { help: "more days after tomorrow", example: "1 or 6" });
  dayCommand("yesterday", -1, "Insert yesterday's date, optionally offset by more days.", [],
             { help: "days from yesterday", example: "-1 or -6" });

  new Command({
    name: "business_day", type: "insert", aliases: ["workday"], extension: ext,
    helpText: "Insert the date a number of business days (Monday to Friday) away.",
    parameters: [new Parameter({ type: "int", name: "days", helpText: "working days from today", default: 1,
                                 required: false, example: "5 or -1" }), fmt],
    tutorials: [
      new TutorialCommand({ command: "business_day", description: "Next business day" }),
      new TutorialCommand({ command: "business_day(10)", description: "Two working weeks from today" }),
      new TutorialCommand({ command: "business_day(-1)", description: "Previous business day" })
    ],
    execute: function (payload) {
      var p = this.getParsedParams(payload);
      return new ReturnObject({ status: "success", message: "Inserted date", payload: format(addBusinessDays(today(), p[0]), style(p[1])) });
    }
  });
})();
