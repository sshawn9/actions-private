# cf-dns

由 Terraform 管理的 `sshawn9.com` 区域 Cloudflare 配置。

该配置直接声明 Cloudflare Provider 资源，而不是通过自定义的
`terraform.tfvars` 抽象资源。这样既能清晰展示规则顺序，也能让 Terraform
状态地址与 Cloudflare 资源直接对应。

## 托管资源

### DNS 记录

| 主机名 | 类型 | 内容 | 代理 | 用途 |
|---|---|---|:---:|---|
| `easytier.sshawn9.com` | A | `104.129.51.144` | 是 | EasyTier Web 面板 |
| `et-config.sshawn9.com` | A | `104.129.51.144` | 是 | EasyTier 配置服务器 |
| `www.sshawn9.com` | A | `192.0.2.1` | 是 | 用于规范重定向的无源站主机名 |

`192.0.2.1` 是保留的文档示例地址，Cloudflare 建议将其用于无源站主机名。
由于该记录已启用代理，Single Redirect 规则会在 Cloudflare 边缘运行，不会
与此地址建立连接。

网站自定义域名 `sshawn9.com` 由 Terraform 管理。服务自行管理的自定义域名，
例如 `file.sshawn9.com`、`match.sshawn9.com`、`dl.sshawn9.com` 和
`zashboard.sshawn9.com`，仍保留在
各自的 Worker 部署配置中。

### 网站预览访问控制

生产环境自定义域名 `sshawn9.com` 继续公开访问。Cloudflare Access 保护所有
非生产环境的网站端点：

- 生产环境 `sshawn9-com` Worker 的版本预览。
- 稳定的 `sshawn9-com-preview` workers.dev 端点。
- `sshawn9-com-preview` 的分支别名和不可变版本。

该应用使用由 Terraform 管理的 Cloudflare 账户身份提供商，跳过身份提供商
选择页面，并且不会回退到电子邮件一次性 PIN 认证。Access 策略允许此
Cloudflare 账户中已接受邀请的成员访问，会话时长为 24 小时，且不会在
Access 启动器中显示该应用。目标模式包含 Worker 名称，因此不会影响同一
账户中的其他 Worker。

### Single Redirects

`www.sshawn9.com` 使用以下规则永久重定向到 `https://sshawn9.com`：

- HTTP 状态码为 `308`，保留原始 HTTP 方法。
- 保留原始请求路径。
- 保留原始查询字符串。

例如，`http://www.sshawn9.com/a?x=1` 会变为
`https://sshawn9.com/a?x=1`。

所有区域级 Single Redirect 规则都必须保存在
`cloudflare_ruleset.single_redirects` 的有序 `rules` 列表中。Cloudflare 在
此阶段仅允许一个区域入口规则集，并且第一个匹配的重定向规则生效。

### Origin Rules

| 主机名 | 目标端口 |
|---|---:|
| `easytier.sshawn9.com` | 11212 |
| `et-config.sshawn9.com` | 22020 |

### 区域设置

区域范围的 SSL/TLS 模式为 `flexible`。如需改为 `full` 或 `strict`，所有受影响
的源站都必须配置兼容的 TLS 证书。

## 文件结构

| 文件 | 用途 |
|---|---|
| `backend.tf` | Cloudflare R2 远程状态后端 |
| `main.tf` | Terraform 和 Cloudflare Provider 版本 |
| `variables.tf` | 部署输入变量 |
| `terraform.tfvars` | 仅包含区域 ID |
| `dns.tf` | 显式声明的 DNS 记录资源 |
| `rules.tf` | 有序的 Origin Rules 和 Single Redirects 规则集 |
| `site-access.tf` | 网站预览的 Access 应用和可复用策略 |
| `site-worker.tf` | 生产网站的自定义域名 |
| `zone.tf` | 各项区域设置 |
| `migrations.tf` | 保留状态的 Provider v4 到 v5 迁移声明 |

## 版本

- Terraform：`>= 1.8, < 2.0`（GitHub Actions 使用 `1.15.8`）
- Cloudflare Provider：`5.23.0`

已提交的 `.terraform.lock.hcl` 固定了 Provider 软件包及其校验和。Provider
升级应作为单独的变更有计划地进行。

## 身份认证与权限

Cloudflare Provider 和 R2 后端共享 `CLOUDFLARE_API_TOKEN` 中由账户所有的
`cfat_` Token。该 Token 需要以下权限：

- Zone DNS Edit
- Zone Settings Edit
- Zone Origin Rules Edit
- Zone Single Redirect Edit
- Account Workers Scripts Edit（API 中称为 `Workers Scripts Write`）
- Access: Apps and Policies Edit（API 中称为 `Access: Apps and Policies Write`）
- Access: Organizations, Identity Providers, and Groups Edit（API 中称为
  `Access: Organizations, Identity Providers, and Groups Write`）
- R2 Object Read and Write；条件允许时，将范围限制到 Terraform 状态存储桶

工作流通过 Accounts API 查找账户，并从 Account Token Verify API 获取账户
Token ID。对于 R2 S3 后端，它使用 Token ID 作为 Access Key ID，并使用 Token
值的 SHA-256 摘要作为 Secret Access Key。无需配置账户 ID 或单独的 R2 凭据。
该 Token 必须只能访问一个 Cloudflare 账户。

## GitHub 配置

配置以下 Actions Secret：

| Secret | 用途 |
|---|---|
| `CLOUDFLARE_API_TOKEN` | 由账户所有的 `cfat_` Token，用于区域资源和 R2 状态 |

Pull Request 会运行格式检查、验证和 plan。推送到 `main` 时会执行相同的检查，
并应用已保存的 plan。工作流并发控制会串行执行针对此状态的所有操作。
GitHub Actions 会根据操作系统、架构和 `.terraform.lock.hcl` 内容缓存 Provider
二进制文件。Terraform 还会重试可安全重试的 Registry 连接错误和服务器错误，
从而在不更改锁定 Provider 版本的情况下，减少上游临时故障导致的失败。

## 一次性远程状态迁移

启用新工作流前，R2 存储桶必须已经存在，并且 `cfat_` Token 必须拥有访问权限。
其固定名称为 `sshawn9-terraform-state`，声明在 `backend.tf` 中。进行本地迁移时，
使用同一个 Token 派生后端凭据：

```bash
export CLOUDFLARE_API_TOKEN="<cfat_ account token>"

ACCOUNT_ID="$(curl --fail-with-body --silent --show-error \
  "https://api.cloudflare.com/client/v4/accounts" \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
  jq -er 'if .success == true and (.result | length) == 1 then .result[0].id else error("expected one account") end')"

export AWS_ACCESS_KEY_ID="$(curl --fail-with-body --silent --show-error \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tokens/verify" \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
  jq -er 'if .success == true and .result.status == "active" then .result.id else error("token is not active") end')"
export AWS_SECRET_ACCESS_KEY="$(printf '%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -d' ' -f1)"
export AWS_ENDPOINT_URL_S3="https://$ACCOUNT_ID.r2.cloudflarestorage.com"
```

可以手动运行 `Terraform Cloudflare DNS` 工作流并设置 `migrate_state=true`，也可以
在此目录中将当前已提交的本地状态复制到 R2：

```bash
terraform init -migrate-state -force-copy

terraform state list
```

删除受版本控制的 `terraform.tfstate` 文件前，请确认远程状态包含现有 DNS 记录和
Origin Rules。只有验证 R2 副本后，才能提交该文件的最终删除。在引导状态仍受
版本控制期间，普通 CI 运行会被有意阻止。

Provider v5 迁移会有意从本地状态中移除旧的聚合地址
`cloudflare_zone_settings_override.ssl`。首次执行经过身份认证的 plan/apply 时，
`migrations.tf` 会将现有 `ssl` 设置导入为 `cloudflare_zone_setting.ssl`，而不会
重新创建或重置远程值。

## 迁移后的本地工作流

```bash
export CLOUDFLARE_API_TOKEN="<Cloudflare API token>"

# 按照上方“一次性远程状态迁移”的方法，从 cfat_ Token 派生
# AWS_ACCESS_KEY_ID、AWS_SECRET_ACCESS_KEY 和 AWS_ENDPOINT_URL_S3。

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

不要在 Cloudflare 控制台中创建或编辑 DNS 记录、区域设置、Origin Rules、
Single Redirects 或网站预览 Access 应用。将任何现有资源添加到此配置前，必须
先导入该资源，以确保 Terraform 始终是其唯一管理者。
