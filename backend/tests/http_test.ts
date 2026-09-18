/**
 * Tests des en-tetes de reponse.
 *
 * L'enjeu : le point d'entree est sans authentification et chaque appel est
 * facture au proprietaire. Le CORS doit donc rester ferme tant que personne ne
 * l'ouvre explicitement.
 *
 * Lancement :
 *   deno test --allow-net --allow-env tests/
 */

import { corsHeaders, jsonResponse } from "../supabase/functions/_shared/http.ts";

function attendre(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("aucun en-tete CORS par defaut", () => {
  Deno.env.delete("ALLOWED_ORIGIN");
  const enTetes = corsHeaders();

  attendre(
    !("Access-Control-Allow-Origin" in enTetes),
    `aucune origine ne doit etre autorisee par defaut, recu ${JSON.stringify(enTetes)}`,
  );
});

Deno.test("l'origine configuree est renvoyee, avec Vary", () => {
  Deno.env.set("ALLOWED_ORIGIN", "https://mon-admin.example");
  try {
    const enTetes = corsHeaders();
    attendre(
      enTetes["Access-Control-Allow-Origin"] === "https://mon-admin.example",
      "l'origine configuree doit etre reprise telle quelle",
    );
    attendre(
      enTetes["Vary"] === "Origin",
      "Vary doit valoir Origin, sans quoi un cache pourrait melanger les reponses",
    );
  } finally {
    Deno.env.delete("ALLOWED_ORIGIN");
  }
});

Deno.test("une origine vide ne rouvre pas le CORS", () => {
  Deno.env.set("ALLOWED_ORIGIN", "   ");
  try {
    const enTetes = corsHeaders();
    attendre(
      !("Access-Control-Allow-Origin" in enTetes),
      "une valeur vide ou faite d'espaces ne doit pas ouvrir le CORS",
    );
  } finally {
    Deno.env.delete("ALLOWED_ORIGIN");
  }
});

Deno.test("jsonResponse n'ouvre pas le CORS", () => {
  Deno.env.delete("ALLOWED_ORIGIN");
  const reponse = jsonResponse({ ok: true });

  attendre(
    !reponse.headers.has("access-control-allow-origin"),
    "une reponse ordinaire ne doit porter aucun en-tete CORS par defaut",
  );
  attendre(
    reponse.headers.get("content-type")?.startsWith("application/json") === true,
    "le type de contenu doit rester du JSON",
  );
});
