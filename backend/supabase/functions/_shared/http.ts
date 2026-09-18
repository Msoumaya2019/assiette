/** Reponses HTTP communes aux Edge Functions. */

/**
 * En-tetes CORS.
 *
 * Par defaut, **aucun en-tete n'est emis** : le navigateur bloque alors tout
 * appel provenant d'une page web.
 *
 * L'application mobile n'est pas concernee. Un client HTTP natif n'applique pas
 * le CORS et n'envoie pas d'en-tete `Origin` : ces en-tetes ne lui servent a
 * rien. Les ouvrir largement n'apportait donc aucun service a l'application, et
 * permettait en revanche a n'importe quelle page web de faire consommer le
 * credit du fournisseur, sur un point d'entree sans authentification dont chaque
 * appel est facture.
 *
 * Pour autoriser un site precis — une administration web, par exemple — definir
 * `ALLOWED_ORIGIN` dans les secrets de la fonction, par exemple
 * `https://mon-admin.example`.
 */
export function corsHeaders(): Record<string, string> {
  const origine = Deno.env.get("ALLOWED_ORIGIN")?.trim();
  if (!origine) return {};

  return {
    "Access-Control-Allow-Origin": origine,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    // L'en-tete depend de la requete : sans `Vary`, un cache intermediaire
    // pourrait servir a un site la reponse destinee a un autre.
    Vary: "Origin",
  };
}

export function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json; charset=utf-8" },
  });
}
