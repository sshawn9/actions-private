// Path-based file server with declarative route mapping and fuzzy filename matching.
// All explicit name-to-file mappings are declared in routes.json.
// When no explicit mapping exists, searches file-server/files/ for a file whose name contains the requested name.
// Config values from shared/*.conf are injected into {{KEY}} placeholders.
// Usage: curl -fsSL https://file.sshawn9.com/<name>

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

interface TreeEntry {
  path: string;
  type: string;
}

async function getFileTree(env: Env): Promise<TreeEntry[]> {
  const url = `https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1`;
  const res = await fetch(url, {
    headers: {
      "User-Agent": "file-server",
      Authorization: `token ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github.v3+json",
    },
  });
  if (!res.ok) return [];
  const data: { tree: TreeEntry[] } = await res.json();
  return data.tree.filter(
    (e) => e.type === "blob" && e.path.startsWith(`${FILES_DIR}/`)
  );
}

function fuzzyMatch(name: string, tree: TreeEntry[]): string | null {
  const lower = name.toLowerCase();
  for (const entry of tree) {
    const relativePath = entry.path.slice(FILES_DIR.length + 1);
    const fileName = relativePath.split("/").pop()!.toLowerCase();
    if (fileName.includes(lower)) {
      return relativePath;
    }
  }
  return null;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const name = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "").toLowerCase();

    if (!name) {
      return new Response("Usage: curl -fsSL file.sshawn9.com/<name>\n", {
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    const cacheKey = new Request(`${url.origin}/${name}`);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const routesRaw = await fetchRaw(ROUTES_PATH, env);

    if (!routesRaw) {
      return new Response("Failed to load routes.\n", { status: 502 });
    }

    const routes: Record<string, string> = JSON.parse(routesRaw);

    // 1. Exact match in routes.json
    let filePath: string | undefined = routes[name];

    // 2. Fuzzy match: search file-server/files/ for a file whose name contains <name>
    if (!filePath) {
      const tree = await getFileTree(env);
      const fuzzyPath = fuzzyMatch(name, tree);
      if (fuzzyPath) {
        filePath = fuzzyPath;
      }
    }

    if (!filePath) {
      return new Response(`Not found: ${name}\n`, { status: 404 });
    }

    let file = await fetchRaw(`${FILES_DIR}/${filePath}`, env);

    if (!file) {
      return new Response(`File not found: ${filePath}\n`, { status: 404 });
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
