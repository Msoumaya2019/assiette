/**
 * Regles communes de validation des images recues par les Edge Functions.
 *
 * Elles vivent ici, et non dans chaque fonction, pour une raison precise : le
 * plafond de taille etait auparavant ecrit dans les deux fichiers et applique a
 * la premiere image seulement. La seconde image, elle, n'etait jamais mesuree.
 * Une seule copie de la regle evite que les deux fonctions divergent a nouveau.
 */

/** Taille maximale d'une image, avant encodage en base64. */
export const MAX_IMAGE_BYTES = 6 * 1024 * 1024;

/** Formats acceptes par le fournisseur de vision. */
export const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);

/**
 * Taille approximative d'une chaine base64 une fois decodee.
 *
 * Le calcul evite de decoder : quatre caracteres base64 representent trois
 * octets. Une estimation suffit — l'ecart d'un octet n'a aucune consequence sur
 * un plafond de plusieurs megaoctets, alors que decoder une image de plusieurs
 * megaoctets en memoire, pour la rejeter ensuite, en aurait une.
 */
export function tailleBase64(value: string): number {
  return Math.floor((value.length * 3) / 4);
}

/** Vrai si le type MIME fait partie des formats acceptes. */
export function typeAccepte(mimeType: string): boolean {
  return ALLOWED_MIME.has(mimeType.toLowerCase());
}
