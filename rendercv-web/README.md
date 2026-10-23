# RenderCV Web 部署

应用与 OAuth Worker 源码保存在 `sshawn9/rendercv-web`；本目录只管理生产部署配置，不复制应用源码。网站在浏览器内编辑、渲染和存储简历，浏览器直接同步到用户的 GitHub 仓库。授权 Worker 只交换及刷新 OAuth 令牌，无数据库、对象存储或用户会话。

| 服务 | Worker 名称 | 正式地址 | 配置 |
| --- | --- | --- | --- |
| 静态网站 | `rendercv-web` | <https://rendercv.sshawn9.com> | `worker/site.wrangler.toml` |
| OAuth 服务 | `rendercv-github-auth` | <https://rendercv-auth.sshawn9.com> | `worker/auth.wrangler.toml` |

两个自定义域名由 Wrangler 创建 DNS 记录和证书，不要在 `cf-dns` 中重复定义。两个 Worker 的 `workers.dev`、预览 URL 和请求日志均关闭。OAuth 回调返回网站根路径，不是授权 Worker。

## 首次配置

1. 把应用源码推送到 `sshawn9/rendercv-web`，必须包含本次压缩运行时与生产验证脚本。CI 在忽略的 `rendercv-web/source/` 中检出所选版本，不读取本机工作目录。
2. 在现有的 **GitHub OAuth App** 中添加精确回调 `https://rendercv.sshawn9.com/`，主页设为 `https://rendercv.sshawn9.com`。保留 `http://127.0.0.1:5173/` 回调即可继续本地测试；不启用通配匹配，保持 expiring tokens 开启。不需要 GitHub App 安装流程。
3. 在本仓库 **Settings → Secrets and variables → Actions** 中配置：

   | 类型 | 名称 | 值 |
   | --- | --- | --- |
   | Secret | `CLOUDFLARE_API_TOKEN` | 沿用现有 Cloudflare 账户 Token |
   | Variable | `RENDERCV_GITHUB_OAUTH_CLIENT_ID` | 现有 OAuth App 的 Client ID |
   | Secret | `RENDERCV_GITHUB_OAUTH_CLIENT_SECRET` | 同一个 OAuth App 的 Client Secret |
   | Secret（私有源码仓库时） | `GH_PAT` | 沿用现有 Token，需能读取 `sshawn9/rendercv-web`；仅用于源码检出 |

   已有本地凭据位于应用目录下忽略的 `workers/github-auth/.dev.vars`。不要把它提交到任一仓库。Client Secret 仅从 Actions Secret 写入临时文件，再作为 Cloudflare Worker Secret 随代码部署；临时文件随后删除。它不进入前端、构建包或应用同步数据。

4. 将本仓库的部署配置提交并推送后，手动运行 **Deploy RenderCV Web**，输入应用的提交号、标签或分支（默认 `main`）。无需额外配置 Cloudflare 账户 ID；与现有服务一样由账户 Token 识别唯一账户。

## 工作流

`.github/workflows/deploy-rendercv-web.yml` 一次检出应用，再依次执行：

1. `npm ci` 下载锁定依赖和渲染资源，运行全部单元测试。
2. `npm run build` 完成运行时打包、Svelte/TypeScript 检查和生产构建；通过 `VITE_GITHUB_AUTH_URL` 注入正式授权服务地址。
3. `npm run check:assets` 检查免费计划的 25 MiB 单文件和 20,000 个文件限制；`npm run test:production` 在独立的临时预览服务上验证编辑、真实渲染、PDF、YAML 和窄屏操作。
4. 对授权服务和网站执行 Wrangler dry-run；所有本地检查通过后才开始发布。
5. 将 OAuth Worker 与 Client Secret 一起部署，使用正式网站 Origin 检查 `/config` 返回的 Client ID。
6. 发布同一份源码构建的静态网站，检查首页响应；在运行摘要中记录实际源码提交和两个地址。

Typst 编译器原始 WASM 超过单文件限制，应用将其打包为 `.wasm.gz`，浏览器 Worker 解压后加载。静态资源按文件原样上传，应用同时支持普通 gzip 文件和服务器的 HTTP gzip 解码，无需额外添加响应头，也不需要为此使用 R2。缺失静态资源返回 404，不回退成 HTML。

授权服务和静态网站是两次部署，不是跨服务原子发布。网站发布前会检查授权服务；如果其中一步失败，修复后重跑该版本。回退时输入上一次运行摘要中的完整源码提交号，重新构建并部署两个服务。回退源码不恢复旧的 OAuth 凭据；部署始终使用当前 Actions 设置。部署流程不读取或修改用户简历。

## 修改正式地址

同时修改两个 Wrangler 配置中的域名、授权服务的 `ALLOWED_ORIGINS`，以及工作流中的 `SITE_ORIGIN` 和 `VITE_GITHUB_AUTH_URL`；在 OAuth App 添加网站的精确回调后重新部署。配置中的目录指向工作流检出的 `../source`，授权服务入口始终来自该份源码。
