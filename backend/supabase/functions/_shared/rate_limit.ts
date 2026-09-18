/**
 * Limitation de debit — premiere barriere anti-abus.
 *
 * Les Edge Functions sont ephemeres : ce compteur en memoire est une protection
 * de premier niveau, suffisante pour eviter les boucles accidentielles. Une
 * limite durable par utilisateur doit s'appuyer sur la table `api_usage`
 * (voir migrations/0001_init.sql) une fois l'authentification active.
 */

interface Bucket {
  count: number;
  resetAt: number;
}

const buckets = new Map<string, Bucket>();
const MAX_TRACKED_CLIENTS = 5000;

function clientKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  const realIp = request.headers.get("x-real-ip");
  if (realIp) return realIp.trim();
  return "unknown";
}

export function checkRateLimit(
  request: Request,
  options: { windowMs: number; max: number },
): { ok: true } | { ok: false; retryAfterS: number } {
  const now = Date.now();
  const key = clientKey(request);

  // Evite une croissance illimitee de la Map.
  if (buckets.size > MAX_TRACKED_CLIENTS) {
    for (const [k, v] of buckets) {
      if (v.resetAt <= now) buckets.delete(k);
    }
  }

  const bucket = buckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + options.windowMs });
    return { ok: true };
  }

  if (bucket.count >= options.max) {
    return { ok: false, retryAfterS: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)) };
  }

  bucket.count += 1;
  return { ok: true };
}
