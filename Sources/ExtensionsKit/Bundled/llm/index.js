// Super Notes extension: llm (MIT)
// Talks to the provider chosen in this extension's settings through callAPI. Keys come from the Keychain
// (Settings → Extensions → API Keys); Ollama runs locally and needs no key, but every provider needs the
// "Let extensions call their own APIs" privacy switch.
(function () {
  var ext = new Extension({ name: "llm", version: "1.0.0", author: "Super Notes", category: "AI", dataScope: "full" });

  var PROVIDERS = {
    openai: { label: "OpenAI", key: "apikey_openai", model: "gpt-4o-mini", style: "chat",
              url: function () { return "https://api.openai.com/v1/chat/completions"; } },
    anthropic: { label: "Anthropic", key: "apikey_anthropic", model: "", style: "messages",
                 url: function () { return "https://api.anthropic.com/v1/messages"; } },
    gemini: { label: "Google Gemini", key: "apikey_google", model: "gemini-2.0-flash", style: "gemini",
              url: function (model) { return "https://generativelanguage.googleapis.com/v1beta/models/" + encodeURIComponent(model) + ":generateContent"; } },
    openrouter: { label: "OpenRouter", key: "apikey_openrouter", model: "openrouter/auto", style: "chat",
                  url: function () { return "https://openrouter.ai/api/v1/chat/completions"; } },
    ollama: { label: "Ollama (local)", key: "", model: "llama3.2", style: "chat",
              url: function () { return "http://localhost:11434/v1/chat/completions"; } }
  };

  ext.register_preference(new Preference({
    key: "provider", label: "Provider", type: "selectOne", defaultValue: "openai",
    options: ["openai", "anthropic", "gemini", "openrouter", "ollama"],
    helpText: "Where prompts are sent. Ollama runs on this Mac and needs no API key."
  }));
  ext.register_preference(new Preference({
    key: "model", label: "Model", type: "string", defaultValue: "",
    helpText: "Model id. Leave empty for the provider's default (Anthropic: the first model your key can use)."
  }));
  ext.register_preference(new Preference({
    key: "systemPrompt", label: "System prompt", type: "paragraph",
    defaultValue: "You are a concise assistant inside a plain-text scratchpad. Answer in plain text without Markdown.",
    helpText: "Instructions sent with every request."
  }));
  ext.register_preference(new Preference({
    key: "maxTokens", label: "Maximum response tokens", type: "string", defaultValue: "1024",
    helpText: "Upper limit for the length of a response."
  }));

  function provider() {
    var id = getPreference("provider") || "openai";
    var p = PROVIDERS[id];
    if (!p) throw new Error("Unknown provider '" + id + "'. Choose one in the llm extension settings.");
    return p;
  }

  function call(p, url, method, headers, body) {
    var result = callAPI(p.key, url, method, JSON.stringify(headers), body === null ? null : JSON.stringify(body));
    var data = null;
    try { data = JSON.parse(result.data); } catch (e) { data = null; }
    if (data && data.error) {
      var err = data.error.message || data.error;
      throw new Error(p.label + " error: " + (typeof err === "object" ? JSON.stringify(err) : err));
    }
    if (!result.success) throw new Error(p.label + " request failed: " + (result.error || "unknown error"));
    if (!data) throw new Error("Could not read the response from " + p.label);
    return data;
  }

  function authHeaders(p) {
    if (p.style === "messages") return { "x-api-key": "{{API_KEY}}", "anthropic-version": "2023-06-01", "Content-Type": "application/json" };
    if (p.style === "gemini") return { "x-goog-api-key": "{{API_KEY}}", "Content-Type": "application/json" };
    return p.key ? { "Authorization": "Bearer {{API_KEY}}", "Content-Type": "application/json" } : { "Content-Type": "application/json" };
  }

  function model(p) {
    var chosen = (getPreference("model") || "").trim();
    if (chosen) return chosen;
    if (p.model) return p.model;
    // Anthropic: ask the API which models this key can use and take the first (newest) one.
    var list = call(p, "https://api.anthropic.com/v1/models?limit=1", "GET", authHeaders(p), null);
    if (list.data && list.data.length) return list.data[0].id;
    throw new Error("No " + p.label + " model available. Set one in the llm extension settings.");
  }

  function complete(prompt) {
    var p = provider(), m = model(p);
    var system = getPreference("systemPrompt") || "";
    var maxTokens = parseInt(getPreference("maxTokens"), 10) || 1024;
    var data, text;
    if (p.style === "messages") {
      data = call(p, p.url(m), "POST", authHeaders(p),
                  { model: m, max_tokens: maxTokens, system: system, messages: [{ role: "user", content: prompt }] });
      text = (data.content || []).filter(function (c) { return c.type === "text"; }).map(function (c) { return c.text; }).join("");
    } else if (p.style === "gemini") {
      data = call(p, p.url(m), "POST", authHeaders(p), {
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: maxTokens }
      });
      var cand = data.candidates && data.candidates[0];
      text = cand && cand.content ? cand.content.parts.map(function (x) { return x.text || ""; }).join("") : "";
    } else {
      data = call(p, p.url(m), "POST", authHeaders(p), {
        model: m, max_tokens: maxTokens,
        messages: [{ role: "system", content: system }, { role: "user", content: prompt }]
      });
      text = data.choices && data.choices[0] && data.choices[0].message ? data.choices[0].message.content : "";
    }
    text = (text || "").trim();
    if (!text) throw new Error(p.label + " returned an empty response");
    return text;
  }

  function command(def) {
    new Command({
      name: def.name, type: def.type, aliases: def.aliases || [], helpText: def.help, parameters: def.parameters,
      tutorials: def.tutorials, extension: ext,
      execute: function (payload) {
        try {
          var prompt = def.prompt(this.getParsedParams(payload), payload);
          return new ReturnObject({ status: "success", message: "Response received", payload: complete(prompt) });
        } catch (e) {
          console.error(def.name + ": " + e.message);
          return new ReturnObject({ status: "error", message: e.message });
        }
      }
    });
  }

  command({
    name: "ask", type: "insert", aliases: ["ai", "llm"], help: "Insert an answer to your question.",
    parameters: [new Parameter({ type: "paragraph", name: "prompt", helpText: "Your question or instruction" })],
    tutorials: [new TutorialCommand({ command: "ask(Three names for a grey cat)", description: "Inserts the answer" })],
    prompt: function (p) { return p[0]; }
  });

  command({
    name: "summarize", type: "insert", aliases: ["tldr"], help: "Insert a short summary of the note.",
    parameters: [new Parameter({ type: "int", name: "sentences", helpText: "Length of the summary", default: 3, required: false })],
    tutorials: [new TutorialCommand({ command: "summarize", description: "Three-sentence summary" })],
    prompt: function (p, payload) {
      if (!(payload.fullText || "").trim()) throw new Error("There is nothing to summarize");
      return "Summarize the following note in at most " + p[0] + " sentences:\n\n" + payload.fullText;
    }
  });

  command({
    name: "rewrite", type: "replaceLine", help: "Rewrite the line in a given style.",
    parameters: [new Parameter({ type: "string", name: "style", helpText: "e.g. clearer, friendlier, formal, shorter", default: "clearer", required: false })],
    tutorials: [new TutorialCommand({ command: "rewrite(friendlier)", description: "Rewrites the current line" })],
    prompt: function (p, payload) {
      if (!(payload.line || "").trim()) throw new Error("Write the text to rewrite on the same line");
      return "Rewrite the following text to be " + p[0] + ". Reply with the rewritten text only.\n\n" + payload.line;
    }
  });

  command({
    name: "translate", type: "replaceLine", help: "Translate the line into another language.",
    parameters: [new Parameter({ type: "string", name: "language", helpText: "Target language, e.g. French" })],
    tutorials: [new TutorialCommand({ command: "translate(Spanish)", description: "Translates the current line" })],
    prompt: function (p, payload) {
      if (!(payload.line || "").trim()) throw new Error("Write the text to translate on the same line");
      return "Translate the following text into " + p[0] + ". Reply with the translation only.\n\n" + payload.line;
    }
  });
})();
