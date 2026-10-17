// Super Notes extension: finance (MIT)
(function () {
  var ext = new Extension({ name: "finance", version: "1.0.0", author: "Super Notes", category: "Finance", dataScope: "none" });

  // 1234567.891 -> "1,234,567.89"
  function money(n) {
    var sign = n < 0 ? "-" : "", parts = Math.abs(n).toFixed(2).split(".");
    return sign + parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",") + "." + parts[1];
  }
  function ok(text) { return new ReturnObject({ status: "success", message: "Calculated", payload: text }); }
  function fail(message) { return new ReturnObject({ status: "error", message: message }); }
  function num(type, name, help, def) {
    return new Parameter(def === undefined ? { type: type, name: name, helpText: help }
                                           : { type: type, name: name, helpText: help, default: def, required: false });
  }

  new Command({
    name: "loan", type: "insert", aliases: ["mortgage"], extension: ext,
    helpText: "Monthly payment for a fixed-rate loan.",
    parameters: [num("expression", "principal", "Amount borrowed"), num("float", "rate", "Annual interest rate in percent"),
                 num("float", "years", "Term in years")],
    tutorials: [new TutorialCommand({ command: "loan(300000, 6.5, 30)", description: "30-year mortgage at 6.5%" })],
    execute: function (payload) {
      var p = this.getParsedParams(payload), principal = p[0], months = Math.round(p[2] * 12), r = p[1] / 100 / 12;
      if (principal <= 0 || months <= 0 || p[1] < 0) return fail("Principal and years must be positive and the rate not negative");
      var payment = r === 0 ? principal / months : principal * r / (1 - Math.pow(1 + r, -months));
      var total = payment * months;
      return ok("Monthly payment: " + money(payment) + " · Total paid: " + money(total) + " · Interest: " + money(total - principal));
    }
  });

  new Command({
    name: "tip", type: "insert", extension: ext,
    helpText: "Tip and total for a bill, optionally split between people.",
    parameters: [num("expression", "amount", "Bill amount"), num("float", "percent", "Tip percentage", 18),
                 num("int", "people", "Number of people splitting", 1)],
    tutorials: [new TutorialCommand({ command: "tip(84.50)", description: "18% tip" }),
                new TutorialCommand({ command: "tip(120, 20, 4)", description: "20% split four ways" })],
    execute: function (payload) {
      var p = this.getParsedParams(payload);
      if (p[0] < 0 || p[1] < 0 || p[2] < 1) return fail("Amount and percent can't be negative and people must be at least 1");
      var tip = p[0] * p[1] / 100, total = p[0] + tip;
      var out = "Tip: " + money(tip) + " · Total: " + money(total);
      if (p[2] > 1) out += " · Each: " + money(total / p[2]);
      return ok(out);
    }
  });

  new Command({
    name: "percent_change", type: "insert", aliases: ["pct_change"], extension: ext,
    helpText: "Percentage change from one value to another.",
    parameters: [num("expression", "from", "Starting value"), num("expression", "to", "Ending value")],
    tutorials: [new TutorialCommand({ command: "percent_change(80, 100)", description: "+25.00%" })],
    execute: function (payload) {
      var p = this.getParsedParams(payload);
      if (p[0] === 0) return fail("Can't compute a change from zero");
      var change = (p[1] - p[0]) / Math.abs(p[0]) * 100;
      return ok((change > 0 ? "+" : "") + change.toFixed(2) + "%");
    }
  });

  new Command({
    name: "compound", type: "insert", aliases: ["compound_interest"], extension: ext,
    helpText: "Future value of a deposit with compound interest.",
    parameters: [num("expression", "principal", "Starting amount"), num("float", "rate", "Annual interest rate in percent"),
                 num("float", "years", "Years"), num("int", "periods", "Compounding periods per year", 12)],
    tutorials: [new TutorialCommand({ command: "compound(10000, 5, 10)", description: "Monthly compounding for 10 years" }),
                new TutorialCommand({ command: "compound(10000, 5, 10, 1)", description: "Yearly compounding" })],
    execute: function (payload) {
      var p = this.getParsedParams(payload);
      if (p[3] < 1 || p[2] < 0) return fail("Years can't be negative and periods must be at least 1");
      var value = p[0] * Math.pow(1 + p[1] / 100 / p[3], p[3] * p[2]);
      return ok("Future value: " + money(value) + " · Interest earned: " + money(value - p[0]));
    }
  });
})();
