// Keyword-matching download router.
// Matches keywords in URL path against rules, resolves latest GitHub release asset, and proxies the file.
// Usage: curl -fsSL https://match.sshawn9.com/<keywords>

import rules from "./rules.json";

interface Env {
  GITHUB_TOKEN?: string;
}

interface GitHubRelease {
  repo: string;
  asset_keywords: string[][];
}

interface Rule {
  name: string;
  keywords: string[][];
  url?: string;
  github_release?: GitHubRelease;
}

interface GitHubAsset {
  id: number;
  name: string;
  browser_download_url: string;
}

interface GitHubReleaseResponse {
  tag_name: string;
  assets: GitHubAsset[];
}

function keywordsMatch(input: string, keywords: string[][]): boolean {
  const lower = input.toLowerCase();
  return keywords.every(group => group.some(kw => lower.includes(kw.toLowerCase())));
}

function matchRule(input: string): Rule | null {
  for (const rule of rules as Rule[]) {
    if (keywordsMatch(input, rule.keywords)) {
      return rule;
    }
  }
  return null;
}

function githubHeaders(env: Env, accept?: string): Record<string, string> {
  const headers: Record<string, string> = { "User-Agent": "match-proxy" };
  if (accept) headers["Accept"] = accept;
  if (env.GITHUB_TOKEN) headers["Authorization"] = `token ${env.GITHUB_TOKEN}`;
  return headers;
}

async function resolveGitHubRelease(release: GitHubRelease, env: Env): Promise<{ assetApiUrl: string; fileName: string } | null> {
  const apiUrl = `https://api.github.com/repos/${release.repo}/releases/latest`;
  const res = await fetch(apiUrl, { headers: githubHeaders(env, "application/vnd.github.v3+json") });
  if (!res.ok) return null;

  const data: GitHubReleaseResponse = await res.json();

  for (const asset of data.assets) {
    if (keywordsMatch(asset.name, release.asset_keywords)) {
      // Use API asset endpoint for private repo support
      const assetApiUrl = `https://api.github.com/repos/${release.repo}/releases/assets/${asset.id}`;
      return { assetApiUrl, fileName: asset.name };
    }
  }
  return null;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const input = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "");

    if (!input) {
      const names = (rules as Rule[]).map(r => `  ${r.name}: ${r.keywords.map(g => g.join("|")).join(" + ")}`).join("\n");
      return new Response(`Usage: curl -fsSL match.sshawn9.com/<keywords>\n\nAvailable rules:\n${names}\n`, {
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    // Check cache
    const cacheKey = new Request(`${url.origin}${url.pathname}`);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const rule = matchRule(input);
    if (!rule) {
      return new Response(`No matching rule for: ${input}\n`, {
        status: 404,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    let fileName: string;
    let upstream: Response;

    if (rule.github_release) {
      const resolved = await resolveGitHubRelease(rule.github_release, env);
      if (!resolved) {
        return new Response(`Failed to resolve latest release for: ${rule.github_release.repo}\n`, {
          status: 502,
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        });
      }
      fileName = resolved.fileName;
      // Download via API with Accept: application/octet-stream (works for private repos)
      upstream = await fetch(resolved.assetApiUrl, {
        headers: githubHeaders(env, "application/octet-stream"),
        redirect: "follow",
      });
    } else if (rule.url) {
      fileName = rule.url.split("/").pop() || "download";
      upstream = await fetch(rule.url, { headers: { "User-Agent": "match-proxy" }, redirect: "follow" });
    } else {
      return new Response(`Rule ${rule.name} has no download source configured.\n`, {
        status: 500,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    if (!upstream.ok) {
      return new Response(`Download failed: ${upstream.status} ${upstream.statusText}\n`, {
        status: upstream.status === 404 ? 404 : 502,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

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
