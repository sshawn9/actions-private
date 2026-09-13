# zashboard

通过 [Deploy zashboard 工作流](../.github/workflows/deploy-zashboard.yml)，将
[Zephyruso/zashboard](https://github.com/Zephyruso/zashboard) 的 release 产物部署到
<https://zashboard.sshawn9.com>。

使用独立的 Cloudflare Workers Static Assets 服务 `zashboard`。工作流直接下载
包含字体的 `dist.zip`，无需构建上游源码，也不在仓库中保存下载的产物。

## 首次运行

1. 将这些部署文件推送到本仓库默认分支 `main`。
2. 沿用仓库已有的 Actions Secret `CLOUDFLARE_API_TOKEN`。与其他 Worker 一样，
   由 Wrangler 自动识别此 Token 可访问的唯一账户，无需新增 Account ID Secret。
   Token 需要能够列出该账户、部署 Worker 并管理 `sshawn9.com` 区域下的自定义域名；
   可按 Cloudflare 的 **Edit Cloudflare Workers** 权限模板核对账户和区域范围。
3. 打开 **Actions → Deploy zashboard → Run workflow**，选择 `main` 并运行。

首次成功部署会创建 Worker 并绑定自定义域名。Cloudflare 自动配置该域名的 DNS
和证书；首次证书签发可能需要等待。`sshawn9.com` 必须是同一账户下的 active zone。
如果该主机名已经存在其他 CNAME 或服务绑定，应先确认其归属再迁移。

域名由 [worker/wrangler.toml](worker/wrangler.toml) 唯一管理，沿用 `file-server`、
`match` 和 `dl-proxy` 的服务模式。不要在 `cf-dns/` 或控制台中重复创建同名 DNS
或自定义域名资源。无需运行 Terraform apply。

## 更新与回退

| `version` 输入 | 部署内容 |
| --- | --- |
| `latest` 或留空 | GitHub 标记为 Latest 的正式 release，排除草稿和预发布版本 |
| 完整 release tag，例如 `v3.26.0` | 对应 release，可用于固定版本或回退；保留 tag 中的 `v` 前缀 |

只有手动运行才会更新网站。推送本仓库、更新 Wrangler 依赖或上游发布新版本均不会
自动升级面板。回退时重新运行工作流，指定所需的旧 release tag。

工作流先解析具体 release，再下载它的 `dist.zip`；若上游提供 SHA-256 digest 则
校验文件，随后检查 `dist/index.html` 并执行 Wrangler dry-run。以上步骤失败时不会
进入部署步骤。每次成功运行的摘要包含实际 tag、产物 SHA-256 和网站链接，Worker
版本消息也会记录 tag。

## 托管方式

- 只发布解压后的内层 `dist/`，不发布仓库文件，也不注入 `GH_PAT` 或其他 Worker Secret。
- 静态站点不需要 Worker JS、R2、KV 或运行时 GitHub 请求。GitHub Token 只用于部署时读取公开 release。
- 上游采用 hash 路由（例如 `/#/proxies`），无需 SPA fallback；不存在的文件返回 404。
- 使用 Cloudflare 默认的 `Cache-Control: public, max-age=0, must-revalidate` 和 ETag。
  HTML、service worker 和资源会重新验证，PWA 继续使用上游的更新机制。
- 关闭 `workers.dev` 和版本预览 URL，站点入口为 `zashboard.sshawn9.com`。
- 沿用其他 Worker 的 `wrangler: "^4"`、`npm install` 和 `npx wrangler deploy`。
  `package-lock.json` 与本地安装产物均忽略，不单独配置 npm Dependabot。
- 部署环境使用最新 LTS Node.js（`lts/*`，`check-latest: true`）。

## 本地验证

将所需 release 的 `dist.zip` 解压后，把内层 `dist/` 放到 `zashboard/worker/dist/`，然后：

```bash
cd zashboard/worker
npm install
npm run deploy -- --dry-run
npm run dev
```

也可以通过 `--assets /absolute/path/to/dist` 指定已有的解压目录。
`--dry-run` 只检查部署包，不会验证云端 Token 权限、域名绑定或实际发布。

## 参考

- [上游发布工作流](https://github.com/Zephyruso/zashboard/blob/main/.github/workflows/deploy.yml)：release 使用 `zip -r dist.zip dist` 打包。
- [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/)：静态托管方式。
- [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)：域名、DNS 和证书管理。
- [GitHub Actions 部署](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)：账户与 API Token 配置。
- [Static Assets Headers](https://developers.cloudflare.com/workers/static-assets/headers/)：默认缓存与响应头。
