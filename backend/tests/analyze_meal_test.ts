/**
 * Tests d'integration du gestionnaire `analyze-meal`.
 *
 * Ils interrogent le gestionnaire par de vraies requetes HTTP plutot que
 * d'appeler ses fonctions internes : c'est la seule facon de verifier que le
 * controle de taille s'applique bien a la seconde image, puisque le defaut
 * d'origine etait justement un controle present mais applique a une seule image.
 *
 * Aucun appel au fournisseur n'est declenche : toutes les requetes testees sont
 * refusees avant l'appel, par les controles locaux.
 *
 * Lancement :
 *   deno test --unstable --allow-net --allow-env tests/
 */

import "../supabase/functions/analyze-meal/index.ts";

const BASE = "http://127.0.0.1:8000";
const PLAFOND = 6 * 1024 * 1024;

function attendre(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

/** Chaine base64 dont la taille decodee depasse de peu le plafond. */
function imageTropGrosse(): string {
  return "A".repeat(Math.ceil((PLAFOND + 4096) / 3) * 4);
}

async function attendreServeur(): Promise<void> {
  for (let essai = 0; essai < 60; essai++) {
    try {
      // Une requete GET suffit : le gestionnaire repond 405, ce qui prouve
      // qu'il ecoute. Le corps doit etre consomme, sinon Deno signale une
      // ressource non liberee.
      const reponse = await fetch(BASE, { method: "GET" });
      await reponse.text();
      if (reponse.status === 405) return;
    } catch {
      // Pas encore pret.
    }
    await new Promise((suite) => setTimeout(suite, 100));
  }
  throw new Error("le gestionnaire n'a pas commence a ecouter");
}

async function poster(corps: unknown): Promise<{ statut: number; corps: Record<string, unknown> }> {
  const reponse = await fetch(BASE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(corps),
  });
  return { statut: reponse.status, corps: await reponse.json() };
}

// La cle n'est jamais utilisee : tous les cas testes s'arretent avant l'appel au
// fournisseur. Elle doit seulement etre presente pour franchir le controle de
// configuration du serveur.
Deno.env.set("DEEPSEEK_API_KEY", "cle-de-test-jamais-utilisee");

await attendreServeur();

Deno.test("seconde image trop volumineuse : refusee", async () => {
  const { statut, corps } = await poster({
    imageBase64: "AAAA",
    mimeType: "image/jpeg",
    secondImageBase64: imageTropGrosse(),
    secondMimeType: "image/jpeg",
  });

  attendre(statut === 413, `attendu 413, recu ${statut}`);
  attendre(
    corps.error === "image_too_large",
    `attendu image_too_large, recu ${String(corps.error)}`,
  );
});

Deno.test("premiere image trop volumineuse : refusee", async () => {
  const { statut, corps } = await poster({
    imageBase64: imageTropGrosse(),
    mimeType: "image/jpeg",
  });

  attendre(statut === 413, `attendu 413, recu ${statut}`);
  attendre(
    corps.error === "image_too_large",
    `attendu image_too_large, recu ${String(corps.error)}`,
  );
});

Deno.test("format non pris en charge : refuse avant tout appel", async () => {
  const { statut, corps } = await poster({
    imageBase64: "AAAA",
    mimeType: "application/pdf",
  });

  attendre(statut === 415, `attendu 415, recu ${statut}`);
  attendre(
    corps.error === "unsupported_media",
    `attendu unsupported_media, recu ${String(corps.error)}`,
  );
});

Deno.test("image absente : refusee", async () => {
  const { statut, corps } = await poster({ mimeType: "image/jpeg" });

  attendre(statut === 400, `attendu 400, recu ${statut}`);
  attendre(corps.error === "missing_image", `attendu missing_image, recu ${String(corps.error)}`);
});

Deno.test("corps illisible : refuse", async () => {
  const reponse = await fetch(BASE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{ceci n'est pas du JSON",
  });

  attendre(reponse.status === 400, `attendu 400, recu ${reponse.status}`);
  const corps = await reponse.json();
  attendre(corps.error === "invalid_json", `attendu invalid_json, recu ${String(corps.error)}`);
});

Deno.test("methode non autorisee : refusee", async () => {
  const reponse = await fetch(BASE, { method: "GET" });
  await reponse.text();
  attendre(reponse.status === 405, `attendu 405, recu ${reponse.status}`);
});

Deno.test("preflight OPTIONS : le CORS reste ferme par defaut", async () => {
  Deno.env.delete("ALLOWED_ORIGIN");
  const reponse = await fetch(BASE, { method: "OPTIONS" });
  await reponse.text();

  attendre(reponse.status === 200, `attendu 200, recu ${reponse.status}`);
  attendre(
    !reponse.headers.has("access-control-allow-origin"),
    "aucune origine ne doit etre autorisee tant que ALLOWED_ORIGIN n'est pas defini",
  );
});
