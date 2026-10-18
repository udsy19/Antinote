// Super Notes extension: llm (MIT)
// Asks the engine chosen in Settings → AI through AI.complete: the downloaded on-device model, Apple's on-device
// model, or a command-line tool the user installed and signed in to. No keys, no endpoints, no network of its own.
(function () {
  var ext = new Extension({ name: "llm", version: "2.0.0", author: "Super Notes", category: "AI", dataScope: "full" });

  ext.register_preference(new Preference({
    key: "systemPrompt", label: "Instructions", type: "paragraph",
    defaultValue: "You are a concise assistant inside a plain-text scratchpad. Answer in plain text without Markdown.",
    helpText: "Standing instructions sent with every request."
  }));
  ext.register_preference(new Preference({
    key: "maxTokens", label: "Maximum answer length (tokens)", type: "string", defaultValue: "1024",
    helpText: "Upper limit for the length of an answer."
  }));

  function complete(prompt) {
    var text = AI.complete(prompt, {
      system: getPreference("systemPrompt") || "",
      maxTokens: parseInt(getPreference("maxTokens"), 10) || 1024
    });
    text = (text || "").trim();
    if (!text) throw new Error("The model returned an empty answer");
    return text;
  }

  function command(def) {
    new Command({
      name: def.name, type: def.type, aliases: def.aliases || [], helpText: def.help, parameters: def.parameters,
      tutorials: def.tutorials, extension: ext,
      execute: function (payload) {
        try {
          var prompt = def.prompt(this.getParsedParams(payload), payload);
          return new ReturnObject({ status: "success", message: "Answer received", payload: complete(prompt) });
        } catch (e) {
          if (e.message !== "Stopped") console.error(def.name + ": " + e.message);
          return new ReturnObject({ status: "error", message: e.message });
        }
      }
    });
  }

  command({
    name: "ask", type: "insert", aliases: ["ai", "llm"], help: "Insert an answer to your question.",
    parameters: [new Parameter({ type: "paragraph", name: "prompt", helpText: "what to ask",
                                 example: "Three names for a grey cat" })],
    tutorials: [new TutorialCommand({ command: "ask(Three names for a grey cat)", description: "Inserts the answer" })],
    prompt: function (p) { return p[0]; }
  });

  command({
    name: "summarize", type: "insert", aliases: ["tldr"], help: "Insert a short summary of the note.",
    parameters: [new Parameter({ type: "int", name: "sentences", helpText: "how many at most", default: 3, required: false,
                                 example: "1 or 5" })],
    tutorials: [new TutorialCommand({ command: "summarize", description: "Three-sentence summary" })],
    prompt: function (p, payload) {
      if (!(payload.fullText || "").trim()) throw new Error("There is nothing to summarize");
      return "Summarize the following note in at most " + p[0] + " sentences:\n\n" + payload.fullText;
    }
  });

  command({
    name: "rewrite", type: "replaceLine", help: "Rewrite the line in a given style.",
    parameters: [new Parameter({ type: "string", name: "style", helpText: "how it should read", default: "clearer", required: false,
                                 example: "shorter" })],
    tutorials: [new TutorialCommand({ command: "rewrite(friendlier)", description: "Rewrites the current line" })],
    prompt: function (p, payload) {
      if (!(payload.line || "").trim()) throw new Error("Write the text to rewrite on the same line");
      return "Rewrite the following text to be " + p[0] + ". Reply with the rewritten text only.\n\n" + payload.line;
    }
  });

  command({
    name: "translate", type: "replaceLine", help: "Translate the line into another language.",
    parameters: [new Parameter({ type: "string", name: "language", helpText: "the language to translate into",
                                 example: "French" })],
    tutorials: [new TutorialCommand({ command: "translate(Spanish)", description: "Translates the current line" })],
    prompt: function (p, payload) {
      if (!(payload.line || "").trim()) throw new Error("Write the text to translate on the same line");
      return "Translate the following text into " + p[0] + ". Reply with the translation only.\n\n" + payload.line;
    }
  });
})();
