// General download proxy with domain whitelist + token auth.
// Usage: curl -fsSL "https://dl.sshawn9.com/github.com/owner/repo/releases/download/tag/file?token=xxx"
import { DL_TOKEN, ALLOWED_DOMAINS } from "./config";

function isAllowed(hostname: string): boolean {
  return ALLOWED_DOMAINS.some(
    (d) => hostname === d || hostname.endsWith(`.${d}`)
  );
}

export default {
  async fetch(request: Request, _env: unknown, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "");
    const token = url.searchParams.get("token");
    const noCache = url.searchParams.has("nocache");

    if (!path) {
      return new Response(
        "Usage: curl -fsSL \"dl.sshawn9.com/<domain>/<path>?token=xxx\"\n",
        { headers: { "Content-Type": "text/plain; charset=utf-8" } }
      );
    }

    if (token !== DL_TOKEN) {
      return new Response("Unauthorized.\n", { status: 403 });
    }

    // Extract hostname from path
    const targetUrl = `https://${path}`;
    let hostname: string;
    try {
      hostname = new URL(targetUrl).hostname;
    } catch {
      return new Response("Invalid URL path.\n", {
        status: 400,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    if (!isAllowed(hostname)) {
      return new Response(`Domain not allowed: ${hostname}\n`, {
        status: 403,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    // Check Cloudflare edge cache
    const cacheKey = new Request(targetUrl);
    const cache = caches.default;
    if (!noCache) {
      const cached = await cache.match(cacheKey);
      if (cached) return cached;
    }

    const upstream = await fetch(targetUrl, {
      headers: { "User-Agent": "dl-proxy" },
      redirect: "follow",
    });

    if (!upstream.ok) {
      return new Response(`Download failed: ${upstream.status} ${upstream.statusText}\n`, {
        status: upstream.status === 404 ? 404 : 502,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    const fileName = path.split("/").pop() || "download";
    const response = new Response(upstream.body, {
      headers: {
        "Content-Type": upstream.headers.get("Content-Type") || "application/octet-stream",
        "Content-Disposition": `attachment; filename="${fileName}"`,
        "Cache-Control": "s-maxage=3600",
      },
    });

    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
