# MCP 配置文档

本文档说明 `linus.md` 中提到的各种 MCP 服务器的安装状态和配置方法。

---

## ⚠️ 重要：全局 vs 项目级配置

**默认行为差异：**
- **Gemini CLI**: `mcp add` 默认添加到**项目级**配置（当前目录下的 `.gemini/settings.json`）
- **Claude Code**: `mcp add` 默认添加到**项目级**配置，需用 `--scope user` 添加到全局
- **Codex CLI**: 需要手动编辑 `~/.codex/config.toml` 文件

**建议：** 为确保在任何目录下都能使用 MCP 工具，应配置**全局** MCP。

---

## 模块化指令文件结构

所有 CLI 工具（Claude Code、Gemini CLI、Codex CLI）都支持模块化的 `@import` 语法。为实现 DRY 原则，共享的指令模块存放在 `modules/` 目录中。

### 目录结构

```
~/.config_files/ai-agent/
├── modules/
│   ├── linus.md              # 角色定义
│   ├── git-workflow.md       # Git 提交和工作流规则
│   └── browser-automation.md # 浏览器自动化指令
├── CLAUDE.md            # Claude Code 主指令文件
├── GEMINI.md            # Gemini CLI 主指令文件
└── AGENTS.md            # Codex CLI 主指令文件
```

### 符号链接配置

```bash
# Claude Code (已配置)
~/.claude/CLAUDE.md -> ../config_files/ai-agent/CLAUDE.md

# Gemini CLI (已配置)
~/.gemini/GEMINI.md -> ../config_files/ai-agent/GEMINI.md

# Codex CLI (已配置)
~/.codex/AGENTS.md -> ../config_files/ai-agent/AGENTS.md
```

### Import 语法支持

| CLI 工具 | Import 语法 | 状态 |
|---------|------------|------|
| Claude Code | `@path/to/file.md` | ✅ 支持 |
| Gemini CLI | `@file.md` 或 `@/path/to/file.md` | ✅ 支持 (2025年6月新增) |
| Codex CLI | 级联 AGENTS.md 系统 | ✅ 支持 |

### 添加新模块

1. 在 `modules/` 创建新模块文件
2. 在 `CLAUDE.md`、`GEMINI.md`、`AGENTS.md` 中添加 `@modules/新模块.md`
3. 所有 CLI 工具自动生效，无需重复配置

---

## MCP 服务器状态总览

| MCP 服务器 | 状态 | 说明 |
|-----------|------|------|
| **Context7** | ✅ 全局配置 | 文档查询工具 |
| **Grep.app** | ✅ 全局配置 | GitHub 代码搜索 |
| **Serena** | ✅ 全局配置 | 语义代码代理 |
| **spec-workflow** | ✅ 全局配置 | 规格文档工作流 |

---

## 各 CLI 工具的 MCP 全局配置

### Gemini CLI

**配置文件位置**: `~/.gemini/settings.json`

**方法：直接编辑配置文件**

```json
{
  "mcpServers": {
    "context7": {
      "url": "https://mcp.context7.com/mcp",
      "type": "http"
    },
    "grep": {
      "url": "https://mcp.grep.app",
      "type": "http"
    },
    "serena": {
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--project-from-cwd"]
    },
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "spec-workflow-mcp@latest"]
    }
  }
}
```

**验证全局配置**:
```bash
# 在任意目录运行（如 /tmp）
cd /tmp && gemini mcp list
```

---

### Claude Code

**配置文件位置**: `~/.claude.json`

**方法：使用 --scope user 参数**

```bash
# HTTP 传输的 MCP
claude mcp add -s user grep --transport http https://mcp.grep.app

# stdio 传输的 MCP
claude mcp add -s user serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
claude mcp add -s user spec-workflow -- npx -y spec-workflow-mcp@latest
```

**验证全局配置**:
```bash
claude mcp list
```

**已配置的 MCP**: browsermcp, context7, grep, serena, spec-workflow

---

### Codex CLI

**配置文件位置**: `~/.codex/config.toml`

**方法：直接编辑配置文件**

```toml
[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"

[mcp_servers.grep]
url = "https://mcp.grep.app"

[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--project-from-cwd"]

[mcp_servers.spec-workflow]
command = "npx"
args = ["-y", "spec-workflow-mcp@latest"]
```

**验证全局配置**:
```bash
codex mcp list
```

---

## 可用的 MCP 服务器详情

### 1. Context7 - 文档查询工具

**功能**: 获取最新的官方文档和代码示例

**全局配置**:
```json
// Gemini CLI (~/.gemini/settings.json)
"context7": {
  "url": "https://mcp.context7.com/mcp",
  "type": "http"
}
```

```toml
# Codex CLI (~/.codex/config.toml)
[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
```

```bash
# Claude Code
claude mcp add -s user context7 --transport http https://mcp.context7.com/mcp
```

**使用方法**:
- `resolve-library-id` - 解析库名称到 Context7 ID
- `query-docs` - 获取最新官方文档

---

### 2. Grep.app - GitHub 代码搜索

**功能**: 在 GitHub 上搜索实际的代码使用示例

**全局配置**:
```json
// Gemini CLI
"grep": {
  "url": "https://mcp.grep.app",
  "type": "http"
}
```

```toml
# Codex CLI
[mcp_servers.grep]
url = "https://mcp.grep.app"
```

```bash
# Claude Code
claude mcp add -s user grep --transport http https://mcp.grep.app
```

---

### 3. Serena - 语义代码代理

**功能**: 提供类似 IDE 的语义代码检索和编辑工具

**全局配置**:
```json
// Gemini CLI
"serena": {
  "command": "uvx",
  "args": ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--project-from-cwd"]
}
```

```toml
# Codex CLI
[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--project-from-cwd"]
```

```bash
# Claude Code
claude mcp add -s user serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
```

**主要工具**:
- `find_symbol`: 搜索符号（全局或局部）
- `find_referencing_symbols`: 查找引用特定符号的符号
- `get_symbols_overview`: 获取文件中顶层符号的概览
- `insert_after_symbol` / `insert_before_symbol`: 在符号位置插入内容
- `replace_symbol_body`: 替换符号的完整定义
- `execute_shell_command`: 执行 shell 命令
- `read_file` / `create_text_file`: 读写文件
- `list_dir`: 列出文件和目录

**官方文档**: https://oraios.github.io/serena/

---

### 4. spec-workflow - 规格文档工作流

**功能**: 管理需求、设计和实现文档的规范工作流

**可用版本**:
- `spec-workflow-mcp` (v1.0.8) - 原始版本
- `@pimzino/spec-workflow-mcp` (v2.1.7) - 带 Web 仪表板
- `@iflow-mcp/spec-workflow-mcp` (v2.1.4) - 另一分支版本

**全局配置**:
```json
// Gemini CLI
"spec-workflow": {
  "command": "npx",
  "args": ["-y", "spec-workflow-mcp@latest"]
}
```

```toml
# Codex CLI
[mcp_servers.spec-workflow]
command = "npx"
args = ["-y", "spec-workflow-mcp@latest"]
```

```bash
# Claude Code
claude mcp add -s user spec-workflow -- npx -y spec-workflow-mcp@latest
```

**主要工具**:
- 检查进度: `action.type="check"`
- 初始化: `action.type="init"`
- 更新任务: `action.type="complete_task"`
- 路径: `/docs/specs/*`

**GitHub**: https://github.com/kingkongshot/specs-workflow-mcp

---

## 配置验证

**重要：在非项目目录（如 /tmp）验证全局配置是否生效**

```bash
cd /tmp

# Gemini CLI
gemini mcp list

# Claude Code
claude mcp list

# Codex CLI
codex mcp list
```

所有三个 CLI 工具都应显示相同的 MCP 服务器列表。
