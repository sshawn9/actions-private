# file-server

运行在 Cloudflare Workers 上的路径式文件服务器。通过 `file.sshawn9.com/<name>` 提供本仓库中的文件，并支持自动注入配置值和模糊匹配文件名。

## 使用方法

```bash
# 精确匹配（名称已在 routes.json 中定义）
curl -fsSL https://file.sshawn9.com/iet | bash

# 模糊匹配（在 files/ 中搜索文件名包含输入内容的文件）
curl -fsSL https://file.sshawn9.com/install-easytier | bash

# 查看使用说明
curl https://file.sshawn9.com/
```

## 路由逻辑

Worker 使用两级回退机制将 `<name>` 解析为文件：

1. **精确匹配**：在 `routes.json` 中查找 `<name>`；找到后直接返回映射的文件。
2. **模糊匹配**：如果没有精确匹配，则通过 GitHub Trees API 获取 `file-server/files/` 的完整目录树，并返回第一个文件名中**包含** `<name>` 的文件（不区分大小写）。
3. **404**：两种匹配均未找到文件时，返回 `Not found: <name>`。

## 配置

### routes.json

将短名称映射到文件路径（相对于 `file-server/files/`）：

```json
{
  "iet": "scripts/install-easytier.sh",
  "deploy-easytier-web": "scripts/deploy-easytier-web.sh"
}
```

- 键是用户请求的 URL 路径段
- 值是 `file-server/files/` 中的相对路径
- 运行时会从 GitHub 动态加载此文件（缓存过期后更改即可生效，无需重新部署）

### 配置注入

返回文件前，Worker 会加载 `shared/` 目录中的所有 `.conf` 文件，并将文件内容中的 `{{KEY}}` 占位符替换为对应的值。

**工作原理：**

1. Worker 通过 GitHub API 列出 `shared/` 中的所有文件
2. 读取每个 `.conf` 文件（格式：每行一个 `KEY=VALUE`）
3. 对每个配置项，将待返回文件中的所有 `{{KEY}}` 替换为 `VALUE`

**示例：**

`shared/dl-proxy.conf`：
```
DL_PROXY=https://dl.sshawn9.com
DL_TOKEN=shawn326
```

如果返回的脚本中包含 `{{DL_PROXY}}`，它会在响应时被替换为 `https://dl.sshawn9.com`。

## 模糊匹配

找不到精确路由时，Worker 使用 GitHub Trees API（`GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1`）获取 `file-server/files/` 下的所有文件路径。随后遍历目录树，返回第一个**文件名**（而非完整路径）中包含所请求 `<name>` 的文件（不区分大小写）。

例如，请求 `/install-easytier` 会匹配 `scripts/install-easytier.sh`，因为文件名 `install-easytier.sh` 中包含 `install-easytier`。

## 缓存

- **边缘缓存 TTL**：5 分钟（`s-maxage=300`）
- **缓存键**：`{origin}/{name}`（基于完整路径，因此不同名称使用独立缓存）
- 推送文件或配置更改后，缓存的响应会在 5 分钟内过期

## 添加新文件

1. 将文件放入 `file-server/files/`（可使用任意子目录结构）
2. **（可选）** 如需使用短别名，请在 `routes.json` 中添加条目（例如 `"myalias": "path/to/file.sh"`）
3. 如果跳过第 2 步，仍可通过模糊匹配访问该文件（例如使用文件名本身）
4. 如需注入配置值，请在文件中使用 `{{KEY}}` 占位符
5. 推送到 `main` 后文件即可使用（无需重新部署 Worker，但受缓存 TTL 影响）

**注意：** 只有对 `file-server/worker/**` 的更改才会触发 Worker 重新部署。`files/`、`routes.json` 或 `shared/*.conf` 均在运行时从 GitHub 获取，因此相关更改会在下一次未命中缓存的请求中生效。

## 文件清单

| 路由 | 文件路径 | 说明 |
|-------|-----------|-------------|
| `/iet` | `scripts/install-easytier.sh` | EasyTier VPN 客户端安装程序：下载二进制文件、设置 systemd 服务并配置机器 ID |
| `/deploy-easytier-web` | `scripts/deploy-easytier-web.sh` | EasyTier Web 面板部署脚本：安装二进制文件、GeoIP 数据库、systemd 服务、Cloudflare Origin Rules 和防火墙 |
