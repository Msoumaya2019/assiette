/**
 * Tests des regles de validation des images.
 *
 * Le premier test vise le defaut lui-meme : le plafond de taille n'etait
 * applique qu'a la premiere image. Un test qui ne verifierait que l'aide
 * `tailleBase64` passerait aussi sur le code fautif ; il faut donc interroger le
 * gestionnaire de requete.
 *
 * Lancement :
 *   deno test --unstable --allow-net --allow-env tests/
 */

import { MAX_IMAGE_BYTES, tailleBase64, typeAccepte } from "../supabase/functions/_shared/images.ts";

/** Assertion minimale : evite toute dependance distante, donc tout reseau. */
function attendre(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("tailleBase64 estime la taille decodee", () => {
  // 4 caracteres base64 = 3 octets.
  attendre(tailleBase64("AAAA") === 3, "quatre caracteres doivent valoir trois octets");
  attendre(tailleBase64("") === 0, "une chaine vide doit valoir zero");
  // Un octet au-dela du plafond doit bien etre vu comme tel.
  const justeAuDessus = "A".repeat(Math.ceil((MAX_IMAGE_BYTES + 1) / 3) * 4);
  attendre(
    tailleBase64(justeAuDessus) > MAX_IMAGE_BYTES,
    "une chaine depassant le plafond doit etre mesuree comme telle",
  );
});

Deno.test("typeAccepte reconnait les formats du fournisseur", () => {
  attendre(typeAccepte("image/jpeg"), "jpeg doit etre accepte");
  attendre(typeAccepte("IMAGE/PNG"), "la casse ne doit pas compter");
  attendre(!typeAccepte("image/heic"), "heic ne doit pas etre accepte");
  attendre(!typeAccepte("application/pdf"), "un document ne doit pas etre accepte");
});
