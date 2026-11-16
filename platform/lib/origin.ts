// The page and the API must be the same site. Behind the Pi's tunnel the server sees http://host while the browser
// sends Origin https://host, so the host decides and https is accepted for a plain-http request (never the reverse).
export function sameOrigin(origin: string | null, requestUrl: string): boolean {
  if (!origin) return false;
  let from: URL;
  try { from = new URL(origin); } catch { return false; }
  const to = new URL(requestUrl);
  if (from.host !== to.host) return false;
  return from.protocol === to.protocol || (from.protocol === "https:" && to.protocol === "http:");
}
