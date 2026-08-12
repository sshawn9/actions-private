# match

运行在 Cloudflare Workers 上的关键词匹配下载路由器。它根据规则集匹配 URL 路径中的关键词，将 `match.sshawn9.com/<keywords>` 请求路由到对应文件并进行代理，同时支持自动解析私有仓库中最新的 GitHub Release 资源。

## 使用方法

```bash
# 下载适用于 ARM 的最新 motion_control deb 包
curl -fsSL -OJ https://match.sshawn9.com/control-aarch64

# 关键词可以按任意顺序出现
curl -fsSL -OJ https://match.sshawn9.com/aarch64-control

# 下载适用于 x86 的最新 motion_control deb 包
curl -fsSL -OJ https://match.sshawn9.com/control-x86

# 列出所有可用规则
curl https://match.sshawn9.com/
```

无需身份认证，所有端点均可公开访问。

## 关键词匹配

关键词以**二维数组**定义，并采用 AND/OR 语义：

- **外层数组**：AND，即每个分组都必须匹配
- **内层数组**：OR，即分组中至少有一个关键词必须匹配

匹配**不区分大小写**，并检查 URL 路径是否以子字符串形式**包含**关键词。

**示例：**

```json
"keywords": [["control"], ["x86", "amd", "amd64"]]
```

该规则匹配任何包含 `control` **并且**包含（`x86`、`amd`、`amd64` **之一**）的路径：

| 路径 | 匹配 | 原因 |
|------|:-----:|--------|
| `/control-x86` | 是 | 包含 `control` 和 `x86` |
| `/x86-control` | 是 | 关键词顺序不影响匹配 |
| `/control-amd64` | 是 | 包含 `control` 和 `amd64` |
| `/control` | 否 | 缺少 x86/amd/amd64 |
| `/x86` | 否 | 缺少 `control` |
| `/control-arm` | 否 | `arm` 不在 OR 分组中 |

规则按数组中的顺序依次计算，**第一个匹配的规则生效**。

## 规则格式

规则定义在 `worker/src/rules.json` 中，并在构建时打包进 Worker。更改 `rules.json` 后需要推送到 `main`（工作流会监听 `match/**`，因此 CI/CD 将自动重新部署）。

每条规则支持以下两种下载源类型：

### 1. `github_release`：自动解析最新的 Release 资源

```json
{
  "name": "motion-control-arm-deb",
  "keywords": [["control"], ["arm", "aarch64"]],
  "github_release": {
    "repo": "autonomous-group/motion_control",
    "asset_keywords": [["aarch64", "arm64"], [".deb"]]
  }
}
```

| 字段 | 说明 |
|-------|-------------|
| `name` | 易于理解的标识符（显示在 `/` 的规则列表中） |
| `keywords` | 用于匹配 URL 路径的二维数组（AND/OR 语义） |
| `github_release.repo` | 用于获取最新 Release 的 GitHub `owner/repo` |
| `github_release.asset_keywords` | 用于匹配 Release 内资源文件名的二维数组（采用相同的 AND/OR 语义） |

**解析流程：**

1. 通过 GitHub API 调用 `GET /repos/{owner}/{repo}/releases/latest`
2. 遍历 Release 资源，使用 `asset_keywords` 匹配每个资源的文件名
3. 通过 API 资源端点下载第一个匹配的资源（`Accept: application/octet-stream`）
4. 此方式同时适用于**公开和私有**仓库（使用 `GITHUB_TOKEN` 进行身份认证）

### 2. `url`：静态下载 URL

```json
{
  "name": "some-static-file",
  "keywords": [["something"]],
  "url": "https://example.com/file.zip"
}
```

| 字段 | 说明 |
|-------|-------------|
| `url` | 直接下载 URL（按原样获取） |

两种类型可以在同一个 `rules.json` 中混合使用。

## GitHub Release 解析

规则使用 `github_release` 时，Worker 会：

1. 使用 `GITHUB_TOKEN` 进行身份认证，并获取 `https://api.github.com/repos/{repo}/releases/latest`
2. 扫描 Release 的 `assets` 数组，查找第一个文件名与 `asset_keywords` 匹配的资源
3. 携带 `Accept: application/octet-stream`，通过 `https://api.github.com/repos/{repo}/releases/assets/{asset_id}` 下载

**为什么不使用 `browser_download_url`？** 对于私有仓库，即使提供了认证 Token，`browser_download_url` 仍会返回 404。API 资源端点会返回签名后的重定向 URL，同时适用于公开和私有仓库。

**GitHub API 速率限制：** 经过身份认证的请求额度为每小时 5,000 次。每个未命中缓存的请求会使用 2 次 API 调用（1 次获取最新 Release，1 次下载资源）。由于边缘缓存时间为 1 小时，实际 API 用量很低。

## 当前规则

| 名称 | 关键词 | 仓库 | 资源匹配条件 |
|------|----------|------|-------------|
| motion-control-x86-deb | control + (x86\|amd) | autonomous-group/motion_control | (x86\|x86_64\|amd64) + .deb |
| motion-control-arm-deb | control + (arm\|aarch64) | autonomous-group/motion_control | (aarch64\|arm64) + .deb |
| communication-utilities-x86-deb | communication + (x86\|amd) | autonomous-group/communication_utilities | (x86\|x86_64\|amd64) + .deb |
| communication-utilities-arm-deb | communication + (arm\|aarch64) | autonomous-group/communication_utilities | (aarch64\|arm64) + .deb |
| msg-converter-x86-deb | converter + (x86\|amd) | autonomous-group/msg_converter | (x86\|x86_64\|amd64) + .deb |
| msg-converter-arm-deb | converter + (arm\|aarch64) | autonomous-group/msg_converter | (aarch64\|arm64) + .deb |
| local-roadnet-x86-deb | roadnet + (x86\|amd) | autonomous-group/local_roadnet | (x86\|x86_64\|amd64) + .deb |
| local-roadnet-arm-deb | roadnet + (arm\|aarch64) | autonomous-group/local_roadnet | (aarch64\|arm64) + .deb |
| autonomous-joystick-x86-deb | joystick + (x86\|amd) | autonomous-group/autonomous_joystick | (x86\|x86_64\|amd64) + .deb |
| autonomous-joystick-arm-deb | joystick + (arm\|aarch64) | autonomous-group/autonomous_joystick | (aarch64\|arm64) + .deb |
| protopico-x86-deb | protopico + (x86\|amd) | autonomous-group/protopico | (x86\|x86_64\|amd64) + .deb |
| protopico-arm-deb | protopico + (arm\|aarch64) | autonomous-group/protopico | (aarch64\|arm64) + .deb |
| fake-pub-x86-deb | fake + (x86\|amd) | autonomous-group/fake_pub | (x86\|x86_64\|amd64) + .deb |
| fake-pub-arm-deb | fake + (arm\|aarch64) | autonomous-group/fake_pub | (aarch64\|arm64) + .deb |

## 缓存

- **边缘缓存 TTL**：1 小时（`s-maxage=3600`）
- **缓存键**：`{origin}/{path}`（请求中的完整 URL 路径）
- GitHub 发布新 Release 后，缓存版本会在 1 小时内过期，随后自动提供新版本

## 添加新规则

1. 编辑 `match/worker/src/rules.json`
2. 添加新的规则对象：

```json
{
  "name": "my-package-arm-deb",
  "keywords": [["mypackage"], ["arm", "aarch64"]],
  "github_release": {
    "repo": "org/my-package",
    "asset_keywords": [["aarch64", "arm64"], [".deb"]]
  }
}
```

3. 推送到 `main`，CI/CD 会自动部署更新后的 Worker

**提示：**

- 将更具体的规则放在较宽泛的规则之前（第一个匹配的规则生效）
- `asset_keywords` 与 `keywords` 使用相同的 AND/OR 匹配方式：需要 AND 时使用不同的内层数组，需要 OR 时将备选项放在同一个内层数组中
- 在 `asset_keywords` 中加入 `".deb"` 等文件扩展名，以区分不同的软件包格式
