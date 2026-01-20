# MCP 配置文档

本文档说明 `linus.md` 中提到的各种 MCP 服务器的安装状态和配置方法。

---

## 模块化指令文件结构

所有 CLI 工具（Claude Code、Gemini CLI、Codex CLI）都支持模块化的 `@import` 语法。为实现 DRY 原则，共享的指令模块存放在 `modules/` 目录中。

### 目录结构

```
~/.config_files/ai-agent/
├── linus.md              # 角色定义（Linus Torvalds persona）
├── modules/
│   ├── git-workflow.md       # Git 提交和工作流规则
│   ├── browser-automation.md # 浏览器自动化指令
│   └── project-context.md    # 项目上下文（buffer-nexus 等）
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
| **Context7** | ✅ 可用 | 文档查询工具 |
| **Grep.app** | ✅ 可用 | GitHub 代码搜索 |
| **Serena** | ✅ 可用 | 语义代码代理 |
| **spec-workflow** | ✅ 可用 | 规格文档工作流 |

---

## 各 CLI 工具的 MCP 配置

### Gemini CLI

配置文件位置: `~/.gemini/settings.json`

```bash
# 查看已配置的 MCP 服务器
gemini mcp list

# 添加 HTTP 传输的 MCP 服务器
gemini mcp add <name> --transport http <url>

# 添加 stdio 传输的 MCP 服务器
gemini mcp add <name> <command> [args...]

# 删除 MCP 服务器
gemini mcp remove <name>
```

**已安装的 MCP 服务器:**
- `context7`: https://mcp.context7.com/mcp (sse) - Connected
- `grep`: https://mcp.grep.app (sse) - Connected
- `serena`: uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd (stdio) - Connected
- `spec-workflow`: npx -y spec-workflow-mcp@latest (stdio) - Connected

### Codex CLI

配置文件位置: `~/.codex/config.toml`

```bash
# 查看已配置的 MCP 服务器
codex mcp list

# 添加 HTTP 传输的 MCP 服务器
codex mcp add <name> --transport http <url>

# 添加 stdio 传输的 MCP 服务器
codex mcp add <name> <command> [args...]

# 删除 MCP 服务器
codex mcp remove <name>
```

**已安装的 MCP 服务器:**
- `context7`: https://mcp.context7.com/mcp
- `grep`: https://mcp.grep.app
- `serena`: uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
- `spec-workflow`: npx -y spec-workflow-mcp@latest

### Claude Code CLI

```bash
# 查看已配置的 MCP 服务器
claude mcp list

# 添加 HTTP 传输的 MCP 服务器
claude mcp add <name> --transport http <url>

# 添加 stdio 传输的 MCP 服务器
claude mcp add <name> <command> [args...]

# 删除 MCP 服务器
claude mcp remove <name>
```

---

## 可用的 MCP 服务器详情

### 1. Context7 - 文档查询工具

**功能**: 获取最新的官方文档和代码示例

**安装命令** (所有 CLI):
```bash
# Gemini
gemini mcp add context7 --transport http https://mcp.context7.com/mcp

# Codex
codex mcp add context7 --transport http https://mcp.context7.com/mcp

# Claude
claude mcp add context7 --transport http https://mcp.context7.com/mcp
```

**使用方法**:
- `resolve-library-id` - 解析库名称到 Context7 ID
- `query-docs` - 获取最新官方文档

### 2. Grep.app - GitHub 代码搜索

**功能**: 在 GitHub 上搜索实际的代码使用示例

**安装命令** (所有 CLI):
```bash
# Gemini
gemini mcp add grep --transport http https://mcp.grep.app

# Codex
codex mcp add grep --transport http https://mcp.grep.app

# Claude
claude mcp add grep --transport http https://mcp.grep.app
```

### 3. Serena - 语义代码代理

**功能**: 提供类似 IDE 的语义代码检索和编辑工具

**安装命令** (所有 CLI):
```bash
# Gemini
gemini mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd

# Codex
codex mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd

# Claude
claude mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
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

### 4. spec-workflow - 规格文档工作流

**功能**: 管理需求、设计和实现文档的规范工作流

**可用版本**:
- `spec-workflow-mcp` (v1.0.8) - 原始版本
- `@pimzino/spec-workflow-mcp` (v2.1.7) - 带 Web 仪表板
- `@iflow-mcp/spec-workflow-mcp` (v2.1.4) - 另一分支版本

**安装命令** (所有 CLI):
```bash
# Gemini
gemini mcp add spec-workflow npx -y spec-workflow-mcp@latest

# Codex
codex mcp add spec-workflow npx -y spec-workflow-mcp@latest

# Claude
claude mcp add spec-workflow npx -y spec-workflow-mcp@latest
```

**主要工具**:
- 检查进度: `action.type="check"`
- 初始化: `action.type="init"`
- 更新任务: `action.type="complete_task"`
- 路径: `/docs/specs/*`

**GitHub**: https://github.com/kingkongshot/specs-workflow-mcp

---

## MCP 传输类型说明

### HTTP/SSE 传输
适用于远程 MCP 服务器，通过 HTTP/WebSocket 连接:
```bash
<cli> mcp add <name> --transport http <url>
```

### stdio 传输
适用于本地运行的 MCP 服务器，通过标准输入输出通信:
```bash
<cli> mcp add <name> <command> [args...]
# 例如:
<cli> mcp add my-server npx my-mcp-package
<cli> mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
```

---

## 快速设置脚本

```bash
#!/bin/bash
# 为所有 CLI 工具配置可用的 MCP 服务器

# Gemini CLI
gemini mcp add context7 --transport http https://mcp.context7.com/mcp
gemini mcp add grep --transport http https://mcp.grep.app
gemini mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
gemini mcp add spec-workflow npx -y spec-workflow-mcp@latest

# Codex CLI
codex mcp add context7 --transport http https://mcp.context7.com/mcp
codex mcp add grep --transport http https://mcp.grep.app
codex mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
codex mcp add spec-workflow npx -y spec-workflow-mcp@latest

# Claude Code CLI
claude mcp add context7 --transport http https://mcp.context7.com/mcp
claude mcp add grep --transport http https://mcp.grep.app
claude mcp add serena uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd
claude mcp add spec-workflow npx -y spec-workflow-mcp@latest
```

---

## 配置验证

运行以下命令验证 MCP 服务器是否正确配置:

```bash
# Gemini
gemini mcp list

# Codex
codex mcp list

# Claude Code
claude mcp list
```
