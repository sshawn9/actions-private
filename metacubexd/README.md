# metacubexd

[Deploy metacubexd 工作流](../.github/workflows/deploy-metacubexd.yml)将
[MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd) 的网页 release 产物
部署到 <https://metacubexd.sshawn9.com>，使用独立的 Cloudflare Workers Static Assets 服务。

## 使用

1. 将部署文件推送到 `main`，沿用仓库已有的 `CLOUDFLARE_API_TOKEN` Secret。
2. 在 **Actions → Deploy metacubexd → Run workflow** 中选择 `main`。
3. `version` 留空或填 `latest`，部署最新正式 release；填完整 tag（例如 `v1.273.1`），
   部署指定版本，也可用于回退。

仅手动运行时更新。工作流下载 `compressed-dist.tgz`，按上游提供的 SHA-256 digest
校验（旧版本未提供时跳过），检查入口文件并执行 Wrangler dry-run，再发布。
成功摘要包含实际版本、产物 SHA-256 和网站地址。

## 部署配置

- 沿用现有 Worker 的 `wrangler: "^4"`、`npm install`、`npx wrangler deploy`；Node 使用最新 LTS。
- `package-lock.json` 和本地安装产物均忽略。
- 自定义域名由 [worker/wrangler.toml](worker/wrangler.toml) 管理，不在 Terraform 中重复声明。
  同账户下的 `sshawn9.com` zone 和现有 Token 权限需可用于部署；首次域名绑定与证书由 Cloudflare 管理。
- 只部署网页静态产物，连接你自己的 Mihomo 后端；桌面版和内置核心的服务器版不在此工作流范围内。

## 本地验证

将 `compressed-dist.tgz` 解压到 `metacubexd/worker/dist/`，确保其中直接包含 `index.html`，然后：

```bash
cd metacubexd/worker
npm install
npm run deploy -- --dry-run
npm run dev
```

[上游发布流程](https://github.com/MetaCubeX/metacubexd/blob/main/.github/workflows/release.yml)
将静态目录的内容打包到归档根目录；[上游路由配置](https://github.com/MetaCubeX/metacubexd/blob/main/packages/ui/nuxt.config.ts)
启用 hash 路由，因此直接发布解压目录即可，无需 SPA fallback。
