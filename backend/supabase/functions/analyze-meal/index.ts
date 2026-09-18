/**
 * Edge Function `analyze-meal`
 *
 * Recoit une ou deux photos de repas, interroge DeepSeek (modele deepseek-flash,
 * multimodal) et renvoie la liste des aliments identifies avec un poids estime.
 *
 * La cle API DeepSeek reste cote serveur : elle n'est jamais presente dans
 * l'application mobile. Voir backend/README.md pour le deploiement.
 *
 * Entree  : { imageBase64, mimeType, secondImageBase64?, secondMimeType?,
 *             portionHint?, userHint? }
 * Sortie  : { foods, overallConfidence, notes, isEstimate, promptVersion }
 */

import { deepSeekChat, extractJson, DeepSeekError } from "../_shared/deepseek.ts";
import { MEAL_SYSTEM_PROMPT, buildMealUserPrompt, PROMPT_VERSION } from "../_shared/meal_prompt.ts";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { MAX_IMAGE_BYTES, tailleBase64, typeAccepte } from "../_shared/images.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

interface AnalyzeRequest {
  imageBase64?: string;
  mimeType?: string;
  secondImageBase64?: string;
  secondMimeType?: string;
  portionHint?: string;
  userHint?: string;
}

interface AnalyzedFood {
  name: string;
  estimatedWeightG: number;
  confidence: number;
}

interface ModelOutput {
  foods?: unknown;
  overallConfidence?: unknown;
  notes?: unknown;
}

/** Valide et normalise la reponse du modele : on ne fait jamais confiance au LLM. */
function normalize(raw: ModelOutput): { foods: AnalyzedFood[]; overallConfidence: number; notes: string } {
  const list = Array.isArray(raw.foods) ? raw.foods : [];
  const foods: AnalyzedFood[] = [];

  for (const item of list.slice(0, 25)) {
    if (!item || typeof item !== "object") continue;
    const entry = item as Record<string, unknown>;
    const name = typeof entry.name === "string" ? entry.name.trim().slice(0, 120) : "";
    if (!name) continue;

    const weightRaw = Number(entry.estimatedWeightG);
    const weight = Number.isFinite(weightRaw) && weightRaw > 0 ? Math.min(Math.round(weightRaw), 5000) : 0;

    const confidenceRaw = Number(entry.confidence);
    const confidence = Number.isFinite(confidenceRaw) ? Math.min(Math.max(confidenceRaw, 0), 1) : 0.5;

    foods.push({ name, estimatedWeightG: weight, confidence: Number(confidence.toFixed(2)) });
  }

  const overallRaw = Number(raw.overallConfidence);
  const overallConfidence = Number.isFinite(overallRaw)
    ? Math.min(Math.max(overallRaw, 0), 1)
    : foods.length
      ? Number((foods.reduce((sum, f) => sum + f.confidence, 0) / foods.length).toFixed(2))
      : 0;

  const notes = typeof raw.notes === "string" ? raw.notes.trim().slice(0, 500) : "";

  return { foods, overallConfidence: Number(overallConfidence.toFixed(2)), notes };
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "server_misconfigured", message: "Cle fournisseur absente." }, 500);
  }

  const limited = checkRateLimit(request, { windowMs: 60_000, max: 12 });
  if (!limited.ok) {
    return jsonResponse(
      { error: "rate_limited", message: "Trop de requetes, reessayez dans un instant.", retryAfterS: limited.retryAfterS },
      429,
    );
  }

  let body: AnalyzeRequest;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json", message: "Corps de requete illisible." }, 400);
  }

  const mimeType = (body.mimeType ?? "image/jpeg").toLowerCase();
  if (!body.imageBase64) {
    return jsonResponse({ error: "missing_image", message: "Aucune image fournie." }, 400);
  }
  if (!typeAccepte(mimeType)) {
    return jsonResponse({ error: "unsupported_media", message: "Format d'image non pris en charge." }, 415);
  }
  if (tailleBase64(body.imageBase64) > MAX_IMAGE_BYTES) {
    return jsonResponse({ error: "image_too_large", message: "Image trop volumineuse." }, 413);
  }

  // La seconde image passe par le meme plafond que la premiere. Il n'etait
  // auparavant applique qu'a celle-ci : une seconde image de plusieurs dizaines
  // de megaoctets etait transmise telle quelle au fournisseur, avec le cout et
  // la latence que cela suppose, sans qu'aucun controle ne l'arrete.
  if (body.secondImageBase64 && tailleBase64(body.secondImageBase64) > MAX_IMAGE_BYTES) {
    return jsonResponse({ error: "image_too_large", message: "Seconde image trop volumineuse." }, 413);
  }

  const blocks: Record<string, unknown>[] = [
    {
      type: "text",
      text: buildMealUserPrompt({
        portionHint: body.portionHint,
        userHint: body.userHint,
        hasSecondImage: Boolean(body.secondImageBase64),
      }),
    },
    {
      type: "image_url",
      image_url: { url: `data:${mimeType};base64,${body.imageBase64}`, detail: "high" },
    },
  ];

  if (body.secondImageBase64) {
    const secondMime = (body.secondMimeType ?? mimeType).toLowerCase();
    // Type non pris en charge : on ecarte la seconde image plutot que de refuser
    // la requete entiere. Un iPhone peut fournir un HEIC, et une analyse
    // « rapide » qui aboutit vaut mieux qu'un echec complet. Le plafond de
    // taille, lui, reste bloquant : une image enorme n'est jamais legitime.
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
      maxTokens: 2048,
      temperature: 0.2,
      messages: [
        { role: "system", content: MEAL_SYSTEM_PROMPT },
        { role: "user", content: blocks as never },
      ],
    });

    const parsed = normalize(extractJson<ModelOutput>(raw));

    return jsonResponse({
      foods: parsed.foods,
      overallConfidence: parsed.overallConfidence,
      notes: parsed.notes,
      isEstimate: true,
      promptVersion: PROMPT_VERSION,
    });
  } catch (error) {
    if (error instanceof DeepSeekError) {
      const status = error.status === 429 ? 429 : error.status >= 500 ? 502 : 400;
      return jsonResponse({ error: "provider_error", message: "L'analyse a echoue.", detail: error.detail }, status);
    }
    console.error("analyze-meal failure", error);
    return jsonResponse({ error: "internal_error", message: "Erreur interne pendant l'analyse." }, 500);
  }
});
