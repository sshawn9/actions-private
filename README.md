# actions-private

**sshawn9.com** 域名生态的基础设施即代码仓库，由 Cloudflare Workers 和 Terraform 驱动。

## 架构

```
                         客户端（curl、浏览器、脚本）
                                     |
                 ┌───────────────────┼───────────────────┐
                 |                   |                   |
        file.sshawn9.com    match.sshawn9.com     dl.sshawn9.com
                 |                   |                   |
          ┌──────────────┐  ┌────────────────┐  ┌────────────────┐
          |  file-server |  |     match      |  |    dl-proxy    |
          |    Worker    |  |    Worker      |  |    Worker      |
          └──────┬───────┘  └───────┬────────┘  └────────┬───────┘
                 |                  |                    |
           GitHub 仓库          GitHub Releases       白名单中的
        （文件与配置注入）       （最新资源）          外部域名
                                                     （需认证）

  DNS、重定向、区域设置、稳定自定义域名及网站预览的 Access 策略
  均由 Terraform 管理（cf-dns/）
```

## 服务

| 服务 | 域名 | 用途 | 目录 |
|---------|--------|---------|-----------|
| **website** | `sshawn9.com` | 公开的生产域名；生产历史版本和分支预览由 Cloudflare Access 保护 | `cf-dns/` |
| **file-server** | `file.sshawn9.com/<name>` | 支持配置注入和模糊匹配的路径式文件服务器 | `file-server/` |
| **match** | `match.sshawn9.com/<keywords>` | 基于关键词匹配的下载路由器，可自动解析最新的 GitHub Release 资源 | `match/` |
| **dl-proxy** | `dl.sshawn9.com/<domain>/<path>?token=xxx` | 面向白名单域名、需要认证的下载代理 | `dl-proxy/` |
| **cf-dns** | 不适用 | 由 Terraform 管理的 DNS、重定向、Worker 自定义域名、网站预览访问策略和区域设置 | `cf-dns/` |

## 技术栈

- **运行时**：Cloudflare Workers（TypeScript）
- **构建与部署**：Wrangler v4
- **DNS 与基础设施**：Terraform、Cloudflare Provider v5.23.0 及 R2 远程状态
- **CI/CD**：GitHub Actions（推送到 `main` 时自动部署）
- **Node.js**：v24

## 目录结构

```
actions-private/
├── file-server/          # 路径式文件服务器
│   ├── files/            #   对外提供的文件（脚本、配置等）
│   ├── routes.json       #   名称到文件的映射
│   └── worker/           #   Cloudflare Worker 源码
├── match/                # 基于关键词匹配的下载路由器
│   └── worker/
│       └── src/
│           ├── index.ts  #   Worker 逻辑
│           └── rules.json#   匹配规则（打包进 Worker）
├── dl-proxy/             # 需要认证的下载代理
│   └── worker/
│       └── src/
│           ├── index.ts  #   Worker 逻辑
│           └── config.ts #   Token 与域名白名单
├── cf-dns/               # Terraform DNS 管理
│   ├── terraform.tfvars  #   Cloudflare 区域 ID
│   ├── backend.tf        #   R2 远程状态后端
│   ├── site-worker.tf    #   生产网站的自定义域名
│   ├── site-access.tf    #   网站预览的 Access 保护
│   └── *.tf              #   显式声明的 Terraform 资源
├── shared/               # 共享配置文件
│   └── *.conf            #   用于模板注入的 KEY=VALUE 文件
└── .github/workflows/    # CI/CD 流水线
    ├── file-server.yml
    ├── match.yml
    ├── dl-proxy.yml
    └── cf-dns.yml
```

## 部署

相关更改推送到 `main` 分支后，所有服务都会自动部署：

| 服务 | 触发路径 | 部署方式 |
|---------|-------------|---------------|
| file-server | `file-server/worker/**` | `npx wrangler deploy` |
| match | `match/**` | `npx wrangler deploy` |
| dl-proxy | `dl-proxy/worker/**` | `npx wrangler deploy` |
| cf-dns | `cf-dns/**` | 在 Pull Request 中生成 plan；合并到 `main` 后使用 R2 远程状态串行执行 apply |

所有工作流也支持通过 `workflow_dispatch` 手动触发。

## 必需的 Secret

在 GitHub 仓库的 **Settings > Secrets and variables > Actions** 中配置以下 Secret：

| Secret | 使用方 | 用途 |
|--------|---------|---------|
| `CLOUDFLARE_API_TOKEN` | 所有服务 | 账户所有的 `cfat_` Token，供 Workers、Terraform 和 R2 状态使用 |
| `GH_PAT` | file-server、match、dl-proxy | GitHub Personal Access Token，以 Worker Secret `GITHUB_TOKEN` 注入，用于访问私有仓库 |

`cf-dns` 工作流会从账户所有的 Token 中获取 Cloudflare 账户 ID 和 R2 S3
凭据。状态存储桶名称 `sshawn9-terraform-state` 固定配置在
`cf-dns/backend.tf` 中。

## 共享配置

`shared/` 目录包含由 `KEY=VALUE` 条目组成的 `.conf` 文件。**file-server** Worker 使用这些文件进行模板注入：对外提供的文件中，任何 `{{KEY}}` 占位符都会在运行时被替换为对应的值。

当前配置文件：

- `shared/dl-proxy.conf`：包含安装脚本使用的 `DL_PROXY` 和 `DL_TOKEN` 值

## 添加新服务

1. 创建 `<service>/worker/` 目录，并添加 `src/index.ts`、`wrangler.toml`、`package.json` 和 `tsconfig.json`
2. 在 `cf-dns/` 中添加稳定的自定义域名；Worker 代码和版本部署仍保留在服务仓库中
3. 在 `.github/workflows/<service>.yml` 中添加 GitHub Actions 工作流（可复制现有工作流作为模板）
4. 推送到 `main`，工作流会自动部署
5. 根据需要设置 Worker Secret；工作流中应包含注入 `GITHUB_TOKEN` 的步骤
