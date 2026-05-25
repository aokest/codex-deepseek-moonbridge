---
type: Guide
domain: tech
status: active
created: 2026-05-25
updated: 2026-05-25
tags: [codex, deepseek, moon-bridge, 开发工具, protocol-bridge, 教程]
---

# 在 Mac 上用 DeepSeek 跑 Codex：保姆级配置教程

> 通过 Moon Bridge 协议桥，让 OpenAI Codex CLI/App 使用 DeepSeek V4 模型。实测可用，稳定运行。

## 为什么需要这个教程？

Codex 是 OpenAI 出的编程 Agent，它使用 **Responses API**（OpenAI 私有协议）与模型通信。而 DeepSeek 只支持标准的 **Chat Completions API**。两者协议不兼容——直接改 `base_url` 会导致 404、工具调用失败、多轮对话断裂。

**Moon Bridge** 是 DeepSeek 官方推荐的本地协议转换器，它在中间做翻译：让 Codex 以为自己在调 OpenAI，实际上请求被转发给了 DeepSeek。

```
Codex ──Responses API──▶ Moon Bridge ──Chat Completions──▶ DeepSeek
       ◀──Responses API──◀             ◀──Chat Completions──◀
```

## 前置条件

| 依赖 | 版本 | 说明 |
|------|------|------|
| macOS | 12+ | 本教程基于 macOS（Apple Silicon） |
| Node.js | 18+ | Codex CLI 依赖 |
| Go | 1.25.x | Moon Bridge 编译运行 |
| Git | 任意 | 克隆 Moon Bridge 仓库 |
| DeepSeek API Key | — | [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) |

> 💡 **只需 DeepSeek 一个 Key**。不需要 OpenAI Key。

---

## 第一步：安装 Go

Moon Bridge 用 Go 写的，需要 Go 1.25+。**推荐直接下载二进制**，brew 安装极慢（实测 ~1MB/min）。

```bash
# 创建本地 SDK 目录（不需要 sudo）
mkdir -p ~/go-sdk

# 下载 Go 1.25.10（Apple Silicon）
curl -fsSL https://go.dev/dl/go1.25.10.darwin-arm64.tar.gz -o /tmp/go.tar.gz

# 解压到 ~/go-sdk/go/
tar -C ~/go-sdk -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz

# 验证安装
~/go-sdk/go/bin/go version
# → go version go1.25.10 darwin/arm64
```

> ⚠️ **Go 版本很重要！** 截至 2026-05，Go 1.26.x 编译 Moon Bridge 会报 `redeclared` 错误（标准库内部冲突）。**必须用 Go 1.25.x**。

> ⚠️ **Intel Mac 用户**：把 `darwin-arm64` 改为 `darwin-amd64`。

> 💡 **为什么不用 brew？** `brew install go` 下载速度极慢（~1MB/min），且会安装到系统目录需要 sudo。直接下载到用户目录更快、更干净。

---

## 第二步：克隆 Moon Bridge

```bash
git clone https://github.com/ZhiYi-R/moon-bridge ~/moon-bridge
cd ~/moon-bridge
```

克隆完成后，**先创建 data 目录**（否则启动时会报 SQLite 错误）：

```bash
mkdir -p ~/moon-bridge/data
```

> ⚠️ **这一步很容易漏！** Moon Bridge 默认启用 SQLite 持久化，如果 `data/` 目录不存在，启动时会报错：
> ```
> unable to open database file (14)
> ```
> 不是权限问题，就是目录不存在。

---

## 第三步：配置 config.yml

在 `~/moon-bridge/` 下创建 `config.yml`：

```bash
cat > ~/moon-bridge/config.yml << 'EOF'
mode: "Transform"

log:
  level: "info"
  format: "text"

server:
  addr: "127.0.0.1:38440"

# SQLite 持久化（必须先创建 data/ 目录）
persistence:
  active_provider: db_sqlite

extensions:
  deepseek_v4:
    config:
      reinforce_instructions: true
      reinforce_prompt: "[System Reminder]: Please pay close attention to the system instructions, AGENTS.md files, and any other context provided. Follow them carefully and completely in your response.\n[User]:"
  db_sqlite:
    enabled: true
    config:
      path: ./data/moonbridge.db
      wal: true
      busy_timeout_ms: 5000
      max_open_conns: 1

defaults:
  model: "moonbridge"
  max_tokens: 65536

models:
  deepseek-v4-pro:
    context_window: 1000000
    max_output_tokens: 384000
    display_name: "DeepSeek V4 Pro"
    description: "DeepSeek V4 with selectable high/xhigh reasoning effort."
    default_reasoning_level: "high"
    supported_reasoning_levels:
      - effort: "high"
        description: "High reasoning effort"
      - effort: "xhigh"
        description: "Extra high reasoning effort"
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"
    extensions:
      deepseek_v4:
        enabled: true

providers:
  deepseek:
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "sk-你的DeepSeek密钥"
    version: "2023-06-01"
    user_agent: "moonbridge/1.0"
    offers:
      - model: deepseek-v4-pro
        pricing:
          input_price: 2
          output_price: 8
          cache_write_price: 1
          cache_read_price: 0.2

routes:
  moonbridge:
    model: deepseek-v4-pro
    provider: deepseek
EOF
```

> ⚠️ **把 `sk-你的DeepSeek密钥` 替换为你的真实 Key**。从 [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) 获取。

> ⚠️ **base_url 是 `/anthropic`，不是 `/v1`**。Moon Bridge 通过 Anthropic 兼容协议与 DeepSeek 通信，这是 DeepSeek 推荐的方式。

> ⚠️ **密钥安全**：`config.yml` 含明文 API Key。确认 `~/moon-bridge/.gitignore` 中已忽略此文件，**切勿推送到公开仓库**。

> 💡 **`deepseek_v4` 扩展**：启用后支持 reasoning effort 选择（high/xhigh），让模型有更强的推理能力。`reinforce_instructions` 会自动强化系统提示，提升 Codex 的指令遵循度。

---

## 第四步：启动 Moon Bridge

```bash
cd ~/moon-bridge
export PATH="$HOME/go-sdk/bin:$HOME/go-sdk/go/bin:$PATH"

# 前台启动（推荐先用这种方式调试）
go run ./cmd/moonbridge --config config.yml
```

看到以下输出即表示启动成功：

```
Moon Bridge 监听于 127.0.0.1:38440
```

> ⚠️ **首次编译较慢**（1-2 分钟），Go 需要下载依赖并编译。后续启动会快很多。

> 💡 **快速启动优化**：编译一次后可以保留二进制，避免每次 `go run` 都重新编译：
> ```bash
> go build -o moonbridge ./cmd/moonbridge
> # 以后直接用：
> ./moonbridge --config config.yml
> ```

保持这个终端窗口打开，**新开一个终端**继续下面的步骤。

---

## 第五步：生成 Codex 配置文件

Moon Bridge 提供命令自动生成 Codex 所需的配置文件。

```bash
export PATH="$HOME/go-sdk/bin:$HOME/go-sdk/go/bin:$PATH"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

cd ~/moon-bridge

# 生成 config.toml 片段 + models_catalog.json
go run ./cmd/moonbridge \
  --config config.yml \
  --codex-home "$CODEX_HOME" \
  --print-codex-config moonbridge
```

这个命令会：
1. **输出 config.toml 片段**到终端（你需要复制到 `~/.codex/config.toml`）
2. **自动生成 `~/.codex/models_catalog.json`**（模型元数据，Codex 需要这个文件来识别模型能力）

> ⚠️ **models_catalog.json 必须存在**。没有这个文件，Codex 会提示 "Model metadata not found" 并使用降级模式，影响工具调用和上下文窗口管理。

---

## 第六步：配置 Codex config.toml

编辑 `~/.codex/config.toml`：

```bash
# 如果已有 config.toml，先备份
cp ~/.codex/config.toml ~/.codex/config.toml.bak 2>/dev/null

# 追加 moonbridge provider（不破坏已有配置）
cat >> ~/.codex/config.toml << 'EOF'

[model_providers.moonbridge]
name = "Moon Bridge"
base_url = "http://127.0.0.1:38440/v1"
wire_api = "responses"
EOF
```

然后把默认模型切到 moonbridge：

```bash
# 修改默认 provider 和 model
sed -i '' 's/^model_provider = .*/model_provider = "moonbridge"/' ~/.codex/config.toml
sed -i '' 's/^model = .*/model = "moonbridge"/' ~/.codex/config.toml
```

> ⚠️ **wire_api 必须是 `"responses"`**。如果写成 `"chat"`，Codex 会走 Chat Completions 协议，和 DeepSeek 直连一样会失败。

> ⚠️ **不要删除已有的其他 provider 配置**。保留原有的 `deepseek`、`openai` 等 provider，随时可以切回。

> ⚠️ **如果之前登录过 OpenAI**，需要先退出：
> ```bash
> codex logout
> ```
> 否则 Codex 可能仍然尝试用 OpenAI 的认证。

---

## 第七步：验证

### 7.1 检查 Moon Bridge 端点

```bash
curl -s http://127.0.0.1:38440/v1/models | python3 -m json.tool
```

应返回包含 `deepseek-v4-pro` 和 `moonbridge` 的模型列表。

### 7.2 测试完整链路

```bash
curl -s -X POST http://127.0.0.1:38440/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "moonbridge",
    "input": [
      {"role": "user", "content": "What is 2+2? Reply in one word."}
    ],
    "max_output_tokens": 100
  }' | python3 -m json.tool
```

应返回 `"status": "completed"`，`"model": "deepseek-v4-pro"`，以及模型的回复。

### 7.3 启动 Codex

```bash
cd /path/to/your/project
codex
```

在 Codex 中输入一条简单指令（如 "列出当前目录的文件"），确认能正常返回结果。

> ⚠️ **如果 Codex 提示 "Model metadata not found"**：说明 `models_catalog.json` 没生成。回到第五步重新执行。

> ⚠️ **如果 Codex 提示要登录 OpenAI**：执行 `codex logout`，然后重试。

---

## 第八步：配置 macOS 开机自启（launchd）

让 Moon Bridge 随系统启动，不用每次手动运行。

### 8.1 创建 plist 文件

```bash
# 获取当前用户名（自动替换）
USERNAME=$(whoami)

cat > ~/Library/LaunchAgents/com.user.moonbridge.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.moonbridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/${USERNAME}/go-sdk/go/bin/go</string>
        <string>run</string>
        <string>./cmd/moonbridge</string>
        <string>--config</string>
        <string>config.yml</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/${USERNAME}/moon-bridge</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/moonbridge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/moonbridge.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/Users/${USERNAME}/go-sdk/bin:/Users/${USERNAME}/go-sdk/go/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLIST
```

### 8.2 先停掉手动启动的 Moon Bridge

```bash
pkill -f moonbridge 2>/dev/null
sleep 2
```

### 8.3 加载服务

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.moonbridge.plist
```

### 8.4 验证

```bash
# 检查服务状态
launchctl list | grep moonbridge
# 应显示类似：12345  0  com.user.moonbridge

# 等几秒后检查端口
curl -s http://127.0.0.1:38440/v1/models
# 应返回模型列表
```

> ⚠️ **KeepAlive=true 的含义**：Moon Bridge 崩溃后 macOS 会自动重启它。这是期望的行为——保证 Codex 随时可用。

> ⚠️ **手动停止服务**：
> ```bash
> launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.moonbridge.plist
> ```

> ⚠️ **查看日志**：
> ```bash
> tail -f /tmp/moonbridge.log
> ```

> 💡 **如果更喜欢用预编译二进制**（避免每次启动等 Go 编译），修改 plist 的 ProgramArguments：
> ```xml
> <array>
>     <string>/Users/你的用户名/moon-bridge/moonbridge</string>
>     <string>--config</string>
>     <string>config.yml</string>
> </array>
> ```
> 前提是先 `cd ~/moon-bridge && go build -o moonbridge ./cmd/moonbridge`。

---

## 常见问题排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `connection refused` | Moon Bridge 没启动 | `launchctl list \| grep moonbridge` 检查状态 |
| `unable to open database file (14)` | `data/` 目录不存在 | `mkdir -p ~/moon-bridge/data` |
| `401 Unauthorized` | API Key 错误或过期 | 检查 `config.yml` 中的 `api_key` |
| `402 Payment Required` | DeepSeek 账户余额不足 | 到 [platform.deepseek.com](https://platform.deepseek.com) 充值 |
| `Model metadata not found` | `models_catalog.json` 缺失 | 重新执行第五步 |
| Go 编译报 `redeclared` | Go 版本过高（1.26.x） | 降级到 Go 1.25.x |
| Codex 提示登录 OpenAI | 未退出 OpenAI 登录 | `codex logout` |
| 工具调用报错 | Moon Bridge 版本过旧 | `cd ~/moon-bridge && git pull` |
| `brew install go` 极慢 | brew 镜像问题 | 用本教程的直接下载方式 |
| Codex App 没走 Moon Bridge | config.toml 未配置 | 确认 `model_provider = "moonbridge"` |

---

## 与 Claude Code 的关系

此配置**不影响** Claude Code。两者完全独立：

| 工具 | 配置文件 | 通信协议 | 中间层 |
|------|---------|---------|--------|
| **Codex** | `~/.codex/config.toml` | Responses API | Moon Bridge |
| **Claude Code** | `~/.claude/` | Anthropic Messages API | 直连 |

> 💡 Codex 和 Claude Code 可以同时运行，互不干扰。甚至可以在同一个项目里交替使用。

---

## 文件清单

配置完成后，你的系统里会多出这些文件：

| 文件 | 用途 |
|------|------|
| `~/go-sdk/go/bin/go` | Go 编译器 |
| `~/moon-bridge/` | Moon Bridge 项目目录 |
| `~/moon-bridge/config.yml` | Moon Bridge 配置（含 API Key） |
| `~/moon-bridge/data/` | SQLite 持久化数据 |
| `~/.codex/config.toml` | Codex 配置（含 moonbridge provider） |
| `~/.codex/models_catalog.json` | 模型元数据（自动生成） |
| `~/Library/LaunchAgents/com.user.moonbridge.plist` | macOS 自启服务 |
| `/tmp/moonbridge.log` | Moon Bridge 运行日志 |

---

## 卸载

如果不再需要：

```bash
# 1. 停止并卸载 launchd 服务
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.moonbridge.plist
rm ~/Library/LaunchAgents/com.user.moonbridge.plist

# 2. 删除 Moon Bridge
rm -rf ~/moon-bridge

# 3. 删除 Go SDK
rm -rf ~/go-sdk

# 4. 恢复 Codex 配置（如果有备份）
cp ~/.codex/config.toml.bak ~/.codex/config.toml
# 或者删除 moonbridge provider 相关行

# 5. 清理日志
rm /tmp/moonbridge.log
```

---

## 相关链接

| 资源 | 链接 |
|------|------|
| Moon Bridge | [github.com/ZhiYi-R/moon-bridge](https://github.com/ZhiYi-R/moon-bridge) |
| DeepSeek 官方 Codex 指南 | [awesome-deepseek-agent/docs/codex.md](https://github.com/deepseek-ai/awesome-deepseek-agent/blob/main/docs/codex.md) |
| Codex CLI 配置参考 | [developers.openai.com/codex/config-reference](https://developers.openai.com/codex/config-reference/) |
| DeepSeek API 文档 | [api-docs.deepseek.com](https://api-docs.deepseek.com/) |
| DeepSeek API Key 管理 | [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) |
| Go 下载 | [go.dev/dl](https://go.dev/dl) |

---

*最后更新：2026-05-25，基于实际配置经验整理。*
