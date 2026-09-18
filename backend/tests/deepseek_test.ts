/**
 * Tests du corps de requete envoye au fournisseur.
 *
 * Le mode reflexion de DeepSeek est **actif par defaut, effort `high`**, et les
 * jetons de raisonnement sont factures comme des jetons de sortie — la ligne la
 * plus chere. Le client ne l'envoyait pas : le fournisseur appliquait donc son
 * propre defaut. Pire, en mode reflexion `temperature` est ignore **en
 * silence**, donc le `0.2` du code ne reglait rien.
 *
 * Un test qui lirait seulement la constante du modele passerait aussi sur le
 * code fautif. Il faut interroger le corps **reellement transmis**, ce que fait
 * `corpsEnvoye` en interceptant `fetch`.
 *
 * Lancement :
 *   deno test --allow-net --allow-env tests/
 */

import { deepSeekChat, type DeepSeekOptions } from "../supabase/functions/_shared/deepseek.ts";

/** Assertion minimale : evite toute dependance distante, donc tout reseau. */
function attendre(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const MESSAGES: DeepSeekOptions["messages"] = [{ role: "user", content: "un plat de pates" }];

/** Intercepte `fetch`, rend le corps envoye, et ne touche a aucun reseau. */
async function corpsEnvoye(
  options: Omit<DeepSeekOptions, "apiKey">,
): Promise<Record<string, unknown>> {
  const origine = globalThis.fetch;
  let capture: Record<string, unknown> = {};

  globalThis.fetch = ((_entree: unknown, init?: RequestInit) => {
    capture = JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
    return Promise.resolve(
      new Response(JSON.stringify({ choices: [{ message: { content: "{}" } }] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as typeof fetch;

  try {
    await deepSeekChat({ apiKey: "cle-de-test", ...options });
  } finally {
    globalThis.fetch = origine;
  }

  return capture;
}

function typeDeReflexion(corps: Record<string, unknown>): string | undefined {
  return (corps.thinking as { type?: string } | undefined)?.type;
}

Deno.test("le mode reflexion est desactive par defaut", async () => {
  const corps = await corpsEnvoye({ messages: MESSAGES });
  attendre(
    typeDeReflexion(corps) === "disabled",
    `attendu 'disabled', recu ${JSON.stringify(corps.thinking)}`,
  );
});

Deno.test("temperature accompagne le mode reflexion desactive", async () => {
  const corps = await corpsEnvoye({ messages: MESSAGES, temperature: 0.2 });
  attendre(
    corps.temperature === 0.2,
    `attendu 0.2, recu ${JSON.stringify(corps.temperature)}`,
  );
});

Deno.test("en mode reflexion, temperature n'est pas envoye", async () => {
  // Le fournisseur ignore `temperature` en mode reflexion : l'envoyer ferait
  // croire au lecteur qu'il regle la determinisme.
  const corps = await corpsEnvoye({ messages: MESSAGES, thinking: true });
  attendre(typeDeReflexion(corps) === "enabled", `attendu 'enabled', recu ${typeDeReflexion(corps)}`);
  attendre(
    !("temperature" in corps),
    "temperature ne doit pas figurer dans le corps en mode reflexion",
  );
});

Deno.test("le mode JSON et le modele sont transmis", async () => {
  const corps = await corpsEnvoye({ messages: MESSAGES, jsonMode: true });
  attendre(corps.model === "deepseek-flash", `modele inattendu : ${String(corps.model)}`);
  attendre(
    JSON.stringify(corps.response_format) === '{"type":"json_object"}',
    `format de reponse inattendu : ${JSON.stringify(corps.response_format)}`,
  );
});

Deno.test("une image accompagne le texte dans un message utilisateur", async () => {
  const corps = await corpsEnvoye({
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: "estime ce repas" },
          { type: "image_url", image_url: { url: "data:image/jpeg;base64,AAAA" } },
        ],
      },
    ],
  });

  const messages = corps.messages as Array<{ content: Array<{ type: string }> }>;
  const blocs = messages[0].content.map((bloc) => bloc.type);
  attendre(blocs.includes("image_url"), `aucun bloc image : ${JSON.stringify(blocs)}`);
  attendre(blocs.includes("text"), `aucun bloc texte : ${JSON.stringify(blocs)}`);
});
