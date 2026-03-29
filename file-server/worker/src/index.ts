// Subdomain-based file server with declarative route mapping.
// All subdomain-to-file mappings must be declared in routes.json.
// Config values from shared/*.conf are injected into {{KEY}} placeholders.
// Usage: curl -fsSL https://<name>.sshawn9.com

interface Env {
  GITHUB_TOKEN: string;
}

const REPO = "sshawn9/actions-private";
const BRANCH = "main";
const FILES_DIR = "file-server/files";
const ROUTES_PATH = "file-server/routes.json";
const CONFIGS_DIR = "shared";

async function fetchRaw(path: string, env: Env): Promise<string | null> {
  const url = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/${path}`;
  const res = await fetch(url, {
    headers: {
      "User-Agent": "file-server",
      Authorization: `token ${env.GITHUB_TOKEN}`,
    },
  });
  return res.ok ? await res.text() : null;
}

function applyConfig(content: string, config: string): string {
  for (const line of config.split("\n")) {
    const match = line.match(/^(\w+)=(.*)$/);
    if (match) {
      content = content.replaceAll(`{{${match[1]}}}`, match[2]);
    }
  }
  return content;
}

async function listDir(dir: string, env: Env): Promise<string[]> {
  const url = `https://api.github.com/repos/${REPO}/contents/${dir}?ref=${BRANCH}`;
  const res = await fetch(url, {
    headers: {
      "User-Agent": "file-server",
      Authorization: `token ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github.v3+json",
    },
  });
  if (!res.ok) return [];
  const items: { name: string }[] = await res.json();
  return items.map((i) => i.name);
}

async function loadConfigs(env: Env): Promise<string[]> {
  const files = await listDir(CONFIGS_DIR, env);
  const configs: string[] = [];

  for (const file of files.filter((f) => f.endsWith(".conf"))) {
    const raw = await fetchRaw(`${CONFIGS_DIR}/${file}`, env);
    if (raw) configs.push(raw);
  }
  return configs;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const hostname = url.hostname;

    const parts = hostname.split(".");
    if (parts.length < 3) {
      return new Response("Invalid request.\n", { status: 400 });
    }
    const subdomain = parts.slice(0, -2).join(".").toLowerCase();

    if (!subdomain || subdomain === "www") {
      return new Response("No file specified.\n", { status: 400 });
    }

    const cacheKey = new Request(url.origin);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const routesRaw = await fetchRaw(ROUTES_PATH, env);

    if (!routesRaw) {
      return new Response("Failed to load routes.\n", { status: 502 });
    }

    const routes: Record<string, string> = JSON.parse(routesRaw);

    if (!(subdomain in routes)) {
      return new Response(`Not found: ${subdomain}\n`, { status: 404 });
    }

    let file = await fetchRaw(`${FILES_DIR}/${routes[subdomain]}`, env);

    if (!file) {
      return new Response(`File not found: ${routes[subdomain]}\n`, { status: 404 });
    }

    const configs = await loadConfigs(env);
    for (const config of configs) {
      file = applyConfig(file, config);
    }

    const response = new Response(file, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "s-maxage=300",
      },
    });

    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
