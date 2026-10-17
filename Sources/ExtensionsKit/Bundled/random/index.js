// Super Notes extension: random (MIT)
(function () {
  var ext = new Extension({ name: "random", version: "1.0.0", author: "Super Notes", category: "Random Generators", dataScope: "none" });

  function below(n) { return Math.floor(Math.random() * n); }
  function ok(text, message) { return new ReturnObject({ status: "success", message: message || "", payload: text }); }
  function fail(message) { return new ReturnObject({ status: "error", message: message }); }

  new Command({
    name: "dice", type: "insert", aliases: ["roll"], extension: ext,
    helpText: "Roll dice written as NdM (2d6 = two six-sided dice).",
    parameters: [new Parameter({ type: "string", name: "dice", helpText: "NdM, e.g. 1d20 or 3d6", default: "1d6", required: false })],
    tutorials: [
      new TutorialCommand({ command: "dice", description: "Roll one six-sided die" }),
      new TutorialCommand({ command: "dice(2d20)", description: "Roll two twenty-sided dice" })
    ],
    execute: function (payload) {
      var spec = this.getParsedParams(payload)[0].trim();
      var m = /^(\d*)\s*d\s*(\d+)$/i.exec(spec);
      if (!m) return fail("Write dice as NdM, for example 2d6");
      var count = m[1] === "" ? 1 : parseInt(m[1], 10), sides = parseInt(m[2], 10);
      if (count < 1 || count > 100) return fail("Roll between 1 and 100 dice");
      if (sides < 2 || sides > 1000) return fail("Dice need between 2 and 1000 sides");
      var rolls = [], total = 0;
      for (var i = 0; i < count; i++) { var r = below(sides) + 1; rolls.push(r); total += r; }
      var label = count + "d" + sides + ": ";
      return ok(count === 1 ? label + total : label + rolls.join(" + ") + " = " + total);
    }
  });

  new Command({
    name: "coin", type: "insert", aliases: ["flip"], parameters: [], extension: ext,
    helpText: "Flip a coin: Heads or Tails.",
    tutorials: [new TutorialCommand({ command: "coin", description: "Heads or Tails" })],
    execute: function () { return ok(below(2) === 0 ? "Heads" : "Tails"); }
  });

  new Command({
    name: "uuid", type: "insert", parameters: [], extension: ext, aliases: ["guid"],
    helpText: "Insert a random version 4 UUID.",
    tutorials: [new TutorialCommand({ command: "uuid", description: "e.g. 3f2b8c1e-…" })],
    execute: function () {
      var hex = "0123456789abcdef", out = "";
      for (var i = 0; i < 36; i++) {
        if (i === 8 || i === 13 || i === 18 || i === 23) out += "-";
        else if (i === 14) out += "4";
        else if (i === 19) out += hex.charAt(8 + below(4));
        else out += hex.charAt(below(16));
      }
      return ok(out);
    }
  });

  new Command({
    name: "password", type: "insert", extension: ext,
    helpText: "Insert a random password.",
    parameters: [
      new Parameter({ type: "int", name: "length", helpText: "Number of characters (8–128)", default: 20, required: false }),
      new Parameter({ type: "bool", name: "symbols", helpText: "Include symbols", default: true, required: false })
    ],
    tutorials: [
      new TutorialCommand({ command: "password", description: "20 characters with symbols" }),
      new TutorialCommand({ command: "password(32, false)", description: "32 letters and digits" })
    ],
    execute: function (payload) {
      var p = this.getParsedParams(payload), length = p[0];
      if (length < 8 || length > 128) return fail("Password length must be between 8 and 128");
      var sets = ["abcdefghijkmnopqrstuvwxyz", "ABCDEFGHJKLMNPQRSTUVWXYZ", "23456789"];
      if (p[1]) sets.push("!@#$%^&*-_=+?");
      var chars = sets.map(function (s) { return s.charAt(below(s.length)); });
      var all = sets.join("");
      while (chars.length < length) chars.push(all.charAt(below(all.length)));
      for (var i = chars.length - 1; i > 0; i--) { var j = below(i + 1); var t = chars[i]; chars[i] = chars[j]; chars[j] = t; }
      return ok(chars.join(""));
    }
  });

  new Command({
    name: "pick", type: "insert", extension: ext, aliases: ["choose"],
    helpText: "Pick one item at random from a comma-separated list.",
    parameters: [new Parameter({ type: "paragraph", name: "items", helpText: "Comma-separated choices" })],
    tutorials: [new TutorialCommand({ command: "pick(pizza, sushi, tacos)", description: "Let chance decide dinner" })],
    execute: function (payload) {
      var items = this.getParsedParams(payload)[0].split(",").map(function (s) { return s.trim(); })
        .filter(function (s) { return s !== ""; });
      if (items.length === 0) return fail("Give a comma-separated list to pick from");
      return ok(items[below(items.length)]);
    }
  });
})();
