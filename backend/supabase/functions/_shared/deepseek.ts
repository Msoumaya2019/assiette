/**
 * Client DeepSeek — appels chat/completions compatibles OpenAI, avec vision.
 *
 * Le modele `deepseek-flash` (DeepSeek-V4.1-Flash) accepte les images et le
 * mode JSON. Les images ne sont autorisees que dans les messages `user`.
 *
 * Ce fichier est partage par les Edge Functions Supabase.
 */

export interface DeepSeekMessage {
  role: "system" | "user" | "assistant";
  content: string | ContentBlock[];
}

export type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string; detail?: "low" | "high" | "original" | "auto" } };

export interface DeepSeekOptions {
  apiKey: string;
  model?: string;
  baseUrl?: string;
  messages: DeepSeekMessage[];
  jsonMode?: boolean;
  maxTokens?: number;
  temperature?: number;
  /** Nombre de tentatives supplementaires en cas d'echec transitoire. */
  retries?: number;
  timeoutMs?: number;
}

export class DeepSeekError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly detail?: string,
  ) {
    super(message);
    this.name = "DeepSeekError";
  }
}

const DEFAULT_BASE_URL = "https://api.deepseek.com";
const DEFAULT_MODEL = "deepseek-flash";

/** Le mode JSON de DeepSeek peut renvoyer un contenu vide de facon sporadique. */
export async function deepSeekChat(options: DeepSeekOptions): Promise<string> {
  const {
    apiKey,
    model = DEFAULT_MODEL,
    baseUrl = DEFAULT_BASE_URL,
    messages,
    jsonMode = false,
    maxTokens = 2048,
    temperature = 0.2,
    retries = 2,
    timeoutMs = 90_000,
  } = options;

  const body: Record<string, unknown> = {
    model,
    messages,
    max_tokens: maxTokens,
    temperature,
  };
  if (jsonMode) body.response_format = { type: "json_object" };

  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(`${baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!response.ok) {
        const text = await response.text();
        // 4xx (hors 429) : la requete est fautive, inutile de reessayer.
        if (response.status < 500 && response.status !== 429) {
          throw new DeepSeekError("Requete refusee par le fournisseur", response.status, text.slice(0, 500));
        }
        lastError = new DeepSeekError("Fournisseur indisponible", response.status, text.slice(0, 500));
        continue;
      }

      const payload = await response.json();
      const content: string | undefined = payload?.choices?.[0]?.message?.content;
      if (!content || !content.trim()) {
        lastError = new DeepSeekError("Reponse vide du modele", 200);
        continue;
      }
      return content;
    } catch (error) {
      if (error instanceof DeepSeekError && error.status < 500 && error.status !== 429) throw error;
      lastError = error instanceof Error ? error : new Error(String(error));
    } finally {
      clearTimeout(timer);
    }

    if (attempt < retries) await new Promise((r) => setTimeout(r, 600 * (attempt + 1)));
  }

  throw lastError ?? new DeepSeekError("Echec de l'appel au fournisseur", 502);
}

/**
 * Extrait un objet JSON d'une reponse de modele.
 * Tolere les balises Markdown et le texte parasite autour de l'objet.
 */
export function extractJson<T = unknown>(raw: string): T {
  const cleaned = raw.replace(/^\uFEFF/, "").trim();
  const withoutFence = cleaned
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  try {
    return JSON.parse(withoutFence) as T;
  } catch {
    // Repli : premier objet equilibre du texte.
    const start = withoutFence.indexOf("{");
    if (start === -1) throw new DeepSeekError("Aucun objet JSON dans la reponse", 502, cleaned.slice(0, 300));
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let i = start; i < withoutFence.length; i++) {
      const char = withoutFence[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char === "\\") {
        escaped = true;
        continue;
      }
      if (char === '"') inString = !inString;
      if (inString) continue;
      if (char === "{") depth++;
      else if (char === "}") {
        depth--;
        if (depth === 0) {
          return JSON.parse(withoutFence.slice(start, i + 1)) as T;
        }
      }
    }
    throw new DeepSeekError("JSON incomplet dans la reponse", 502, cleaned.slice(0, 300));
  }
}
