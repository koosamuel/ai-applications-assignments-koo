import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const DEFAULT_ORIGINS = [
  "https://ai-applications-assignments-koo.koosamuel1.chatgpt.site",
  "http://127.0.0.1:8765",
  "http://localhost:8765",
];

function allowedOrigins(): string[] {
  const configured = Deno.env.get("ALLOWED_ORIGINS");
  return configured
    ? configured.split(",").map((value) => value.trim()).filter(Boolean)
    : DEFAULT_ORIGINS;
}

function corsHeaders(origin: string): HeadersInit {
  const allowed = allowedOrigins();
  const selected = allowed.includes(origin) ? origin : allowed[0];
  return {
    "Access-Control-Allow-Origin": selected,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(origin: string, value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function estimateLevel(messages: Array<{ role: string; content: string }>): string {
  const text = messages
    .filter((message) => message.role === "user")
    .map((message) => message.content)
    .join(" ");
  const words = text.trim().split(/\s+/).filter(Boolean);
  const advanced =
    text.match(/\b(however|therefore|although|whereas|consequently|preserve|evaluate|accessible|overreliance)\b/gi)
      ?.length ?? 0;
  const longSentences = text
    .split(/[.!?]/)
    .filter((part) => part.trim().split(/\s+/).filter(Boolean).length >= 12)
    .length;

  if (words.length >= 85 && advanced >= 3 && longSentences >= 2) return "C1";
  if (words.length >= 55 && advanced >= 2) return "B2";
  if (words.length >= 30) return "B1";
  if (words.length >= 12) return "A2";
  return "A1";
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") ?? "";

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") {
    return json(origin, { error: "method_not_allowed" }, 405);
  }
  if (origin && !allowedOrigins().includes(origin)) {
    return json(origin, { error: "origin_not_allowed" }, 403);
  }

  let body: {
    messages?: Array<{ role?: unknown; content?: unknown }>;
    learner_turns?: unknown;
    current_level?: unknown;
  };
  try {
    body = await request.json();
  } catch {
    return json(origin, { error: "invalid_json" }, 400);
  }

  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return json(origin, { error: "messages_required" }, 400);
  }

  if (
    body.messages.slice(-16).some(
      (message) =>
        !message ||
        !["user", "assistant"].includes(String(message.role)) ||
        typeof message.content !== "string",
    )
  ) {
    return json(origin, { error: "invalid_message" }, 400);
  }

  const messages = body.messages.slice(-16).map((message) => ({
    role: String(message.role),
    content: String(message.content).trim(),
  }));

  if (
    messages.some(
      (message) =>
        !message.content ||
        message.content.length > 600,
    )
  ) {
    return json(origin, { error: "invalid_message" }, 400);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return json(origin, { error: "server_not_configured" }, 503);
  }

  const systemPrompt = [
    "You are StepUp English, a supportive CEFR-based conversation coach.",
    "Reply in this exact structure: Reply, Good, Fix, Next.",
    "Keep the English conversation to 1-3 sentences.",
    "Give one specific strength, one priority correction with an example, and one next question.",
    "Do not request personal or sensitive information.",
    "CEFR is an estimate based only on the available conversation sample.",
  ].join("\n");

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_CHAT_MODEL") ?? "gpt-4o-mini",
      input: [
        { role: "system", content: systemPrompt },
        ...messages,
      ],
      max_output_tokens: 320,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    console.error("OpenAI request failed", response.status, detail.slice(0, 500));
    return json(origin, { error: "coach_upstream_error" }, 502);
  }

  const result = await response.json();
  const reply =
    result.output_text ??
    result.output
      ?.flatMap((item: { content?: Array<{ type?: string; text?: string }> }) => item.content ?? [])
      .find((item: { type?: string }) => item.type === "output_text")
      ?.text;

  if (typeof reply !== "string" || !reply.trim()) {
    return json(origin, { error: "empty_coach_response" }, 502);
  }

  return json(origin, {
    reply: reply.trim(),
    level: estimateLevel(messages),
    learner_turns:
      typeof body.learner_turns === "number" ? body.learner_turns : undefined,
  });
});
