// Generic script server: serves scripts from script-server/scripts/<subdomain>.sh
// Usage: curl -fsSL https://<script-name>.sshawn9.com | sudo sh -s <args>

interface Env {
  GITHUB_TOKEN: string;
}

const REPO = "sshawn9/actions-private";
const BRANCH = "main";
const SCRIPTS_DIR = "script-server/scripts";
const CONFIG_PATH = "shared/common-downloader-proxy.conf";

async function fetchRaw(path: string, env: Env): Promise<string | null> {
  const url = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/${path}`;
  const res = await fetch(url, {
    headers: {
      "User-Agent": "script-server",
      Authorization: `token ${env.GITHUB_TOKEN}`,
    },
  });
  return res.ok ? await res.text() : null;
}

function applyConfig(script: string, config: string): string {
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
    const url = new URL(request.url);
    const hostname = url.hostname;

    // Extract subdomain: "iet.sshawn9.com" → "iet"
    const parts = hostname.split(".");
    if (parts.length < 3) {
      return new Response("Invalid request.\n", { status: 400 });
    }
    const subdomain = parts.slice(0, -2).join(".").toLowerCase();

    if (!subdomain || subdomain === "www") {
      return new Response("No script specified.\n", { status: 400 });
    }

    const cacheKey = new Request(url.origin);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const scriptPath = `${SCRIPTS_DIR}/${subdomain}.sh`;

    const [script, config] = await Promise.all([
      fetchRaw(scriptPath, env),
      fetchRaw(CONFIG_PATH, env),
    ]);

    if (!script) {
      return new Response(`Script not found: ${subdomain}\n`, {
        status: 404,
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
