/// The JavaScript globals every extension context starts with. Same API shape as the original extension format
/// (config-object and positional constructors), implemented from scratch. Native bridges (`__nativeLog`,
/// `__evaluateMathExpression`, `getPreference`, `getExtensionPreference`, `callAPI`, `now`) are installed by
/// `ExtensionRuntime` before this script runs.
enum BaseLibrary {
    static let source = #"""
var global = this;
global.commandRegistry = [];
global.extensionRegistry = [];
global.__EXTENSION_SHARED__ = global.__EXTENSION_SHARED__ || {};

function __isConfig(args) {
  return args.length === 1 && args[0] !== null && typeof args[0] === "object" && !Array.isArray(args[0]);
}
function __pick(args, names) {
  if (__isConfig(args)) return args[0];
  var out = {};
  for (var i = 0; i < names.length; i++) out[names[i]] = args[i];
  return out;
}

var console = (function () {
  function format(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var a = args[i];
      if (a instanceof Error) parts.push(String(a.message || a));
      else if (typeof a === "object") { try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); } }
      else parts.push(String(a));
    }
    return parts.join(" ");
  }
  return {
    log: function () { __nativeLog("info", format(arguments)); },
    info: function () { __nativeLog("info", format(arguments)); },
    debug: function () { __nativeLog("info", format(arguments)); },
    warn: function () { __nativeLog("warning", format(arguments)); },
    error: function () { __nativeLog("error", format(arguments)); }
  };
})();

function Extension() {
  var c = __pick(arguments, ["name", "version", "endpoints", "requiredAPIKeys", "author", "category", "dataScope", "dependencies", "isService"]);
  this.name = c.name;
  this.version = c.version || "1.0.0";
  this.endpoints = c.endpoints || [];
  this.requiredAPIKeys = c.requiredAPIKeys || [];
  this.author = c.author || "";
  this.category = c.category || "Utilities";
  this.dataScope = c.dataScope || "full";
  this.dependencies = c.dependencies || [];
  this.isService = !!c.isService;
  this.commands = [];
  this.preferences = [];
  global.extensionRegistry.push(this);
}
Extension.prototype.register_command = function (cmd) { this.commands.push(cmd); };
Extension.prototype.register_preference = function (pref) { this.preferences.push(pref); };

function Preference() {
  var c = __pick(arguments, ["key", "label", "type", "defaultValue", "options", "helpText"]);
  this.key = c.key;
  this.label = c.label || c.key;
  this.type = c.type || "string";
  this.defaultValue = c.defaultValue;
  this.options = c.options || null;
  this.helpText = c.helpText || null;
}

function Parameter() {
  var c = __pick(arguments, ["type", "name", "helpText", "default", "required", "example"]);
  this.parameterType = c.type || "string";
  this.name = c.name;
  this.helpText = c.helpText || "";
  this.defaultValue = (c["default"] !== undefined) ? c["default"] : null;
  this.required = (c.required !== undefined) ? !!c.required : true;
  this.example = (c.example === undefined || c.example === null) ? "" : String(c.example);
}

function TutorialCommand() {
  var c = __pick(arguments, ["command", "description"]);
  this.command = c.command;
  this.description = c.description || "";
}

function ReturnObject() {
  var c = __pick(arguments, ["status", "message", "payload"]);
  this.status = c.status || "error";
  this.message = c.message || (this.status === "success" ? "" : "Undefined error.");
  this.payload = (c.payload === undefined || c.payload === null) ? "" : c.payload;
}

function Command() {
  var c = __pick(arguments, ["name", "parameters", "type", "helpText", "tutorials", "extension"]);
  this.name = c.name;
  this.parameters = c.parameters || [];
  this.type = c.type || "replaceLine";
  this.helpText = c.helpText || "";
  this.tutorials = c.tutorials || [];
  this.aliases = c.aliases || [];
  this.extension = c.extension;
  if (typeof c.execute === "function") this.execute = c.execute;
  if (c.extension && typeof c.extension.register_command === "function") c.extension.register_command(this);
  global.commandRegistry.push(this);
}

Command.prototype.execute = function () {
  return new ReturnObject({ status: "error", message: "Command '" + this.name + "' has no implementation." });
};

Command.prototype.getParsedParams = function (payload) {
  var values = (payload && payload.parameters) || [];
  var out = [];
  for (var i = 0; i < this.parameters.length; i++) {
    var p = this.parameters[i];
    var raw = values[i];
    var text = p.parameterType === "string" || p.parameterType === "paragraph";
    var missing = raw === undefined || raw === null || (!text && raw === "");
    if (missing && p.required) throw new Error("Required parameter '" + p.name + "' is missing");
    if (missing) raw = p.defaultValue;
    switch (p.parameterType) {
      case "int": out.push(typeof raw === "number" ? Math.trunc(raw) : parseInt(raw, 10)); break;
      case "float": out.push(typeof raw === "number" ? raw : parseFloat(raw)); break;
      case "expression":
      case "mathExpression": out.push(MathEvaluator.parseNumeric(raw)); break;
      case "bool": out.push(typeof raw === "boolean" ? raw : String(raw).toLowerCase() === "true"); break;
      default: out.push(raw === undefined || raw === null ? "" : String(raw));
    }
  }
  return out;
};

var MathEvaluator = {
  eval: function (expression) {
    var r = __evaluateMathExpression(String(expression));
    if (!r || !r.success) throw new Error((r && r.error) || "Math evaluation failed");
    return r.value;
  },
  evalSafe: function (expression, fallback) {
    try { return this.eval(expression); } catch (e) { return fallback === undefined ? 0 : fallback; }
  },
  isMathExpression: function (s) {
    return typeof s === "string" && /[+\-*/()^%]/.test(s) && !/^\s*-?\d+\.?\d*\s*$/.test(s);
  },
  parseNumeric: function (v) {
    if (typeof v === "number") return v;
    if (typeof v !== "string") return parseFloat(v) || 0;
    return this.isMathExpression(v) ? this.eval(v) : (parseFloat(v) || 0);
  }
};
global.MathEvaluator = MathEvaluator;

// Called by the host. Returns a JSON string {status, message, payload}.
function __superNotesRun(extensionName, commandName, payloadJSON) {
  var cmd = null;
  for (var i = 0; i < global.commandRegistry.length; i++) {
    var c = global.commandRegistry[i];
    if (c.name === commandName && c.extension && c.extension.name === extensionName) { cmd = c; break; }
  }
  if (!cmd) return JSON.stringify({ status: "error", message: "Command '" + commandName + "' is not registered." });
  try {
    var result = cmd.execute(JSON.parse(payloadJSON));
    if (result === undefined || result === null) result = { status: "success", message: "", payload: "" };
    if (typeof result !== "object") result = { status: "success", message: "", payload: String(result) };
    var payload = result.payload;
    if (payload !== undefined && payload !== null && typeof payload !== "string") {
      payload = typeof payload === "object" ? JSON.stringify(payload) : String(payload);
    }
    return JSON.stringify({ status: String(result.status || "error"), message: String(result.message || ""), payload: payload || "" });
  } catch (e) {
    return JSON.stringify({ status: "error", message: String((e && e.message) || e) });
  }
}

// Called by the host after loading: a JSON description of what the scripts registered.
function __superNotesDescribe() {
  return JSON.stringify(global.extensionRegistry.map(function (ext) {
    return {
      name: ext.name, version: ext.version,
      preferences: ext.preferences.map(function (p) {
        return { key: p.key, label: p.label, type: p.type, defaultValue: p.defaultValue === undefined ? null : p.defaultValue,
                 options: p.options, helpText: p.helpText };
      }),
      commands: ext.commands.map(function (c) {
        return {
          name: c.name, type: c.type, helpText: c.helpText, aliases: c.aliases || [],
          parameters: c.parameters.map(function (p) {
            return { name: p.name, type: p.parameterType, helpText: p.helpText, defaultValue: p.defaultValue, required: p.required,
                     example: p.example || "" };
          }),
          tutorials: c.tutorials.map(function (t) { return { command: t.command, description: t.description }; })
        };
      })
    };
  }));
}
"""#
}
