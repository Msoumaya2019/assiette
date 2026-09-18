/**
 * Edge Function `analyze-label`
 *
 * Extrait les valeurs nutritionnelles d'une photo d'etiquette produit.
 * Meme fournisseur et meme modele que `analyze-meal`.
 *
 * Entree : { imageBase64, mimeType, secondImageBase64?, secondMimeType? }
 * Sortie : valeurs pour 100 g / 100 ml + confiance + nom/marque si lisibles.
 */

import { deepSeekChat, extractJson, DeepSeekError } from "../_shared/deepseek.ts";
import { LABEL_SYSTEM_PROMPT, buildLabelUserPrompt, LABEL_PROMPT_VERSION } from "../_shared/label_prompt.ts";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { MAX_IMAGE_BYTES, tailleBase64, typeAccepte } from "../_shared/images.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

const NUMERIC_FIELDS = [
  "energyKcal",
  "fat",
  "saturatedFat",
  "carbohydrates",
  "sugars",
  "fiber",
  "proteins",
  "salt",
] as const;

interface LabelRequest {
  imageBase64?: string;
  mimeType?: string;
  secondImageBase64?: string;
  secondMimeType?: string;
}

function normalize(raw: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};

  const text = (key: string, max: number): string | null => {
    const value = raw[key];
    if (typeof value !== "string") return null;
    const trimmed = value.trim().slice(0, max);
    return trimmed.length ? trimmed : null;
  };

  result.productName = text("productName", 120);
  result.brand = text("brand", 80);
  result.packageQuantity = text("packageQuantity", 40);
  result.notes = text("notes", 400) ?? "";

  const basis = text("basis", 10);
  result.basis = basis === "100ml" ? "100ml" : "100g";

  for (const field of NUMERIC_FIELDS) {
    const value = Number(raw[field]);
    // Une valeur negative ou absurde est rejetee : mieux vaut null qu'un faux chiffre.
    result[field] = Number.isFinite(value) && value >= 0 && value <= 100_000 ? Number(value.toFixed(2)) : null;
  }

  const confidence = Number(raw.confidence);
  result.confidence = Number.isFinite(confidence) ? Number(Math.min(Math.max(confidence, 0), 1).toFixed(2)) : 0.5;

  return result;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "server_misconfigured", message: "Cle fournisseur absente." }, 500);
  }

  const limited = checkRateLimit(request, { windowMs: 60_000, max: 12 });
  if (!limited.ok) {
    return jsonResponse({ error: "rate_limited", retryAfterS: limited.retryAfterS }, 429);
  }

  let body: LabelRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (!body.imageBase64) return jsonResponse({ error: "missing_image" }, 400);

  const mimeType = (body.mimeType ?? "image/jpeg").toLowerCase();
  if (!typeAccepte(mimeType)) return jsonResponse({ error: "unsupported_media" }, 415);

  if (tailleBase64(body.imageBase64) > MAX_IMAGE_BYTES) {
    return jsonResponse({ error: "image_too_large" }, 413);
  }

  // Meme regle que dans `analyze-meal` : le plafond s'applique aux deux images.
  if (body.secondImageBase64 && tailleBase64(body.secondImageBase64) > MAX_IMAGE_BYTES) {
    return jsonResponse({ error: "image_too_large" }, 413);
  }

  const blocks: Record<string, unknown>[] = [
    { type: "text", text: buildLabelUserPrompt(Boolean(body.secondImageBase64)) },
    { type: "image_url", image_url: { url: `data:${mimeType};base64,${body.imageBase64}`, detail: "high" } },
  ];

  if (body.secondImageBase64) {
    const secondMime = (body.secondMimeType ?? mimeType).toLowerCase();
    // Type non pris en charge : la seconde image est ecartee, la requete
    // aboutit. Meme raisonnement que dans `analyze-meal`.
    if (typeAccepte(secondMime)) {
      blocks.push({
        type: "image_url",
        image_url: { url: `data:${secondMime};base64,${body.secondImageBase64}`, detail: "high" },
      });
    }
  }

  try {
    const raw = await deepSeekChat({
      apiKey,
      jsonMode: true,
      maxTokens: 1200,
      temperature: 0.1,
      messages: [
        { role: "system", content: LABEL_SYSTEM_PROMPT },
        { role: "user", content: blocks as never },
      ],
    });

    return jsonResponse({
      ...normalize(extractJson<Record<string, unknown>>(raw)),
      isEstimate: true,
      promptVersion: LABEL_PROMPT_VERSION,
    });
  } catch (error) {
    if (error instanceof DeepSeekError) {
      const status = error.status === 429 ? 429 : error.status >= 500 ? 502 : 400;
      return jsonResponse({ error: "provider_error", detail: error.detail }, status);
    }
    console.error("analyze-label failure", error);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});
