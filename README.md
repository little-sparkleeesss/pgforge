# pgforge

用 GitHub Actions 免费 CI 构建 PostgreSQL Docker 镜像并推送到 GHCR，方便随时拉取使用。

## 工作原理

- CI 工作流：[`.github/workflows/build-postgres.yml`](.github/workflows/build-postgres.yml)
- 使用仓库根目录的 [`Containerfile`](Containerfile) 构建镜像（Docker 与 Podman 通用）
- 构建完成后推送到 GHCR（GitHub Container Registry），无需配置任何额外密钥
- 触发方式：push 到 `main` 自动构建；或在 Actions 页面手动点击 **Run workflow**

## 镜像地址

构建产物推送到：

```
ghcr.io/<owner>/pgforge
```

标签：

- `latest` — 最新一次构建（默认分支）
- `main` — 默认分支构建
- `sha-<commit短哈希>` — 精确定位某次提交

> `<owner>` 为你的 GitHub 用户名或组织名，由仓库自动派生。

## 使用步骤

1. **替换构建文件**：把根目录的 [`Containerfile`](Containerfile) 换成你自己的 PostgreSQL 构建内容，保持文件名和路径不变。
2. **推送触发**：push 到 `main` 分支（或在 Actions 页面手动 Run workflow），等待构建完成。
3. **设为公开**：GHCR 包默认是 **private**。到仓库的 Packages 页面 → 点进包 → **Package settings** → **Change visibility** → 选择 **Public**，之后才能免登录拉取。
4. **拉取使用**：

   ```bash
   docker pull ghcr.io/<owner>/pgforge:latest

   docker run -d \
     --name pg \
     -e POSTGRES_PASSWORD=mysecret \
     -p 5432:5432 \
     ghcr.io/<owner>/pgforge:latest
   ```

## 自定义

- 修改 `Containerfile` 后 push，CI 会自动重新构建并更新 `latest` 标签。
- 镜像架构为 `linux/amd64`；如需 arm64，可在 workflow 中调整 `platforms` 并加装 QEMU 模拟。
