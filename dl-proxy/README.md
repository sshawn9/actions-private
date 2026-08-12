# dl-proxy

运行在 Cloudflare Workers 上的认证下载代理。通过 `dl.sshawn9.com` 代理白名单域名（主要是 GitHub）的文件下载，用于访问某些地区可能无法直接获取的资源。

## 使用方法

```bash
# 基本下载
curl -fsSL -o easytier-gui.deb \
  "https://dl.sshawn9.com/github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-gui_2.4.5_amd64.deb?token=xxx"

# 使用 -O 自动识别文件名（读取 Content-Disposition 响应头）
curl -fsSL -OJ \
  "https://dl.sshawn9.com/github.com/EasyTier/EasyTier/releases/download/v2.4.5/easytier-linux-x86_64-v2.4.5.zip?token=xxx"

# 从 GitHub 仓库下载原始文件
curl -fsSL \
  "https://dl.sshawn9.com/raw.githubusercontent.com/EasyTier/EasyTier/main/README.md?token=xxx"

# 绕过缓存并下载最新内容
curl -fsSL -o file.deb \
  "https://dl.sshawn9.com/github.com/...?token=xxx&nocache"

# 查看使用说明（无需 Token）
curl https://dl.sshawn9.com/
```

**URL 格式**：`https://dl.sshawn9.com/<domain>/<path>?token=<your-token>`

Worker 会将 `<domain>/<path>` 部分转换为 `https://<domain>/<path>` 并获取对应资源。

### 查询参数

| 参数 | 必需 | 说明 |
|-----------|----------|-------------|
| `token` | 是 | 认证 Token（参见下方的“管理 Token”） |
| `nocache` | 否 | 跳过边缘缓存，直接从源站获取；只需提供该参数，无需赋值 |

## 身份认证

每个请求都必须包含有效的 `token` 查询参数。缺少 Token 或 Token 无效时，将返回 `403 Unauthorized`。

Token 在 `worker/src/config.ts` 的 `DL_TOKENS` 数组中定义。该数组支持多个 Token，可按用户或用途分别设置（例如私人 Token 和共享 Token）。

**安全提示：** Token 会显示在 URL 中，请勿公开分享完整的下载链接。

## 域名白名单

只有目标属于白名单域名的请求才会被代理，其他请求将返回 `403 Domain not allowed`。

白名单在 `worker/src/config.ts` 中定义：

| 域名 | 注入 GitHub PAT | 说明 |
|--------|:-------------------:|-------------|
| `github.com` | 是 | GitHub Release 下载和仓库页面 |
| `raw.githubusercontent.com` | 是 | 仓库中的原始文件内容 |
| `api.github.com` | 是 | GitHub API 端点 |
| `objects.githubusercontent.com` | 否 | GitHub LFS 和 Release 资源存储 |
| `github-releases.githubusercontent.com` | 否 | GitHub Release 资源 CDN |

标记为“注入 GitHub PAT”的域名会自动注入 `Authorization: token <GITHUB_TOKEN>` 请求头，从而支持访问私有仓库。

支持子域名匹配：如果 `github.com` 在白名单中，`api.github.com` 也会通过检查（使用 `endsWith` 判断）。

## 缓存

- **边缘缓存 TTL**：1 小时（`s-maxage=3600`）
- **缓存键**：目标 URL（例如 `https://github.com/...`）
- **绕过缓存**：添加 `?nocache`，跳过缓存并从源站获取
- 不同用户或 Token 请求相同的目标 URL 时，会共享同一缓存条目

## 错误码

| 状态码 | 条件 | 响应正文 |
|--------|-----------|---------------|
| 200 | 未提供路径（请求根路径） | 使用说明 |
| 403 | Token 缺失或无效 | `Unauthorized.` |
| 403 | 目标域名不在白名单中 | `Domain not allowed: {hostname}` |
| 400 | 无法将路径解析为有效 URL | `Invalid URL path.` |
| 404 | 上游返回 404 | `Download failed: 404 Not Found` |
| 502 | 上游返回其他错误 | `Download failed: {status} {statusText}` |

## 管理 Token

编辑 `worker/src/config.ts`：

```typescript
export const DL_TOKENS: string[] = [
  "shawn326",     // 私人
  "bit472",       // 共享
  "c3i",          // 共享
];
```

- 添加新 Token：将其追加到数组中
- 撤销 Token：将其从数组中移除
- 推送到 `main`，使用更新后的 Token 重新部署

## 管理域名

编辑 `worker/src/config.ts` 中的 `ALLOWED_DOMAINS` 数组：

```typescript
export const ALLOWED_DOMAINS: string[] = [
  ...GITHUB_DOMAINS,
  "objects.githubusercontent.com",
  "github-releases.githubusercontent.com",
  // 在此添加新域名
];
```

如果需要为新域名注入 GitHub PAT 请求头，还应将其添加到 `GITHUB_DOMAINS`。

推送到 `main` 以重新部署。
