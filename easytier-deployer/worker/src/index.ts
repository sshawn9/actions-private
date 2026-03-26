// Serve install-easytier.sh from private repo with shared config injection.
// Usage: curl -fsSL https://iet.sshawn9.com | sudo sh -s <args>

interface Env {
  GITHUB_TOKEN: string;
}

const REPO = "sshawn9/actions-private";
const BRANCH = "main";
const SCRIPT_PATH = "easytier-deployer/scripts/install-easytier.sh";
const CONFIG_PATH = "shared/common-downloader-proxy.conf";

async function fetchRaw(path: string, env: Env): Promise<string | null> {
  const url = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/${path}`;
  const res = await fetch(url, {
    headers: {
      "User-Agent": "iet-worker",
      Authorization: `token ${env.GITHUB_TOKEN}`,
    },
  });
  return res.ok ? await res.text() : null;
}

function applyConfig(script: string, config: string): string {
  // Parse "KEY=value" lines from config
  for (const line of config.split("\n")) {
    const match = line.match(/^(\w+)=(.*)$/);
    if (match) {
      script = script.replaceAll(`{{${match[1]}}}`, match[2]);
    }
  }
  return script;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const cacheKey = new Request(new URL(request.url).origin);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const [script, config] = await Promise.all([
      fetchRaw(SCRIPT_PATH, env),
      fetchRaw(CONFIG_PATH, env),
    ]);

    if (!script) {
      return new Response("Failed to fetch script.\n", {
        status: 502,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    const body = config ? applyConfig(script, config) : script;

    const response = new Response(body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "s-maxage=300",
      },
    });

    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
