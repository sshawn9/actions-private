// ---- Edit this file to manage your proxy settings ----

export const DL_TOKENS: string[] = [
  // ---- Private (never share) ----
  // "admin-123",
  "shawn326",

  // ---- Shared (revoke anytime) ----
  // "friend-abc",
  "bit472",
  "c3i",
];

// Domains that will receive the GitHub PAT for private repo access
export const GITHUB_DOMAINS: string[] = [
  "github.com",
  "raw.githubusercontent.com",
  "api.github.com",
];

// All domains allowed to be proxied (must include GITHUB_DOMAINS)
export const ALLOWED_DOMAINS: string[] = [
  ...GITHUB_DOMAINS,
  "objects.githubusercontent.com",
  "github-releases.githubusercontent.com",
];
