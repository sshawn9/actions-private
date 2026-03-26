interface Env {
  GITHUB_REPO: string;
  GITHUB_BRANCH: string;
  GITHUB_TOKEN: string;
}

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext
  ): Promise<Response> {
    const url = new URL(request.url);
    let path = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "");

    // Root: return usage hint
    if (!path) {
      return new Response(
        "Usage: curl -fsSL demo.sshawn.com/<script-name> | sh\n",
        { headers: { "Content-Type": "text/plain; charset=utf-8" } }
      );
    }

    // Normalize: add .sh if missing
    if (!path.endsWith(".sh")) {
      path += ".sh";
    }

    // Check Cloudflare cache first
    const cacheKey = new Request(url.toString(), request);
    const cache = caches.default;
    let response = await cache.match(cacheKey);

    if (response) {
      return response;
    }

    // Fetch from GitHub (private repo requires token)
    const repo = env.GITHUB_REPO || "sshawn9/actions";
    const branch = env.GITHUB_BRANCH || "main";
    const githubUrl = `https://raw.githubusercontent.com/${repo}/${branch}/scripts/${path}`;

    const ghResponse = await fetch(githubUrl, {
      headers: {
        "User-Agent": "sh-sshawn-worker",
        Authorization: `token ${env.GITHUB_TOKEN}`,
      },
    });

    if (!ghResponse.ok) {
      if (ghResponse.status === 404) {
        return new Response(`Script not found: ${path}\n`, {
          status: 404,
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        });
      }
      return new Response(
        `Failed to fetch script: ${ghResponse.statusText}\n`,
        {
          status: 502,
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        }
      );
    }

    const scriptBody = await ghResponse.text();

    // Build cacheable response
    response = new Response(scriptBody, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "s-maxage=300",
      },
    });

    // Store in Cloudflare edge cache (non-blocking)
    ctx.waitUntil(cache.put(cacheKey, response.clone()));

    return response;
  },
};
