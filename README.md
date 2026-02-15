# openclaw-docker

OpenClaw 的 Docker 镜像构建仓库，通过 GitHub Actions 构建并推送镜像到 GitHub Container Registry (GHCR)。

## 功能

- **自动化构建**：使用 GitHub Actions 构建 Docker 镜像
- **GHCR 推送**：构建完成后自动推送到 [GitHub Container Registry](https://ghcr.io)
- **构建缓存**：使用 GitHub Actions 缓存 (GHA cache) 加速后续构建

## 如何构建

1. 打开仓库的 **Actions** 页签
2. 在左侧选择 **Build OpenClaw Docker Image**
3. 点击 **Run workflow**，选择分支后运行

构建由 `workflow_dispatch` 手动触发，不会在 push 时自动运行。

## 镜像信息

- **注册表**：`ghcr.io`
- **镜像名称**：`<你的 GitHub 用户名或组织>/openclaw-docker/online-base`
- **标签**：`linux_latest`

拉取示例（将 `OWNER` 替换为实际用户名或组织名）：

```bash
docker pull ghcr.io/OWNER/openclaw-docker/online-base:linux_latest
```

## 工作流说明

- **`build-openclaw.yml`**：入口工作流，手动触发后调用通用构建流程，使用根目录下的 `Dockerfile`
- **`base-workflow.yml`**：可复用的 Docker 构建流程，负责 checkout、登录 GHCR、元数据、构建并推送镜像

## 前置条件

- 仓库根目录需存在 `Dockerfile`
- 默认使用 GitHub 提供的 `GITHUB_TOKEN` 推送镜像，无需额外配置
