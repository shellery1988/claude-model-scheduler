# Claude Model Scheduler

Claude Code 模型定时自动切换工具。支持 macOS（launchd）、Linux（cron）、Windows（schtasks）。

## 功能

- **定时切换**：在设定时间自动切换 Claude Code 使用的模型（如高峰期用 sonnet，非高峰期用 opus）
- **交互式安装**：引导式配置向导，零门槛上手
- **手动切换**：随时通过命令行手动切换模型
- **安全备份**：每次切换前自动备份配置文件
- **历史记录**：完整的切换日志，方便回溯

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/yourname/claude-model-scheduler/main/install.sh | bash
```

安装完成后，即可在任意位置使用 `claude-model-scheduler` 命令。

## 手动安装

```bash
git clone https://github.com/yourname/claude-model-scheduler.git
cd claude-model-scheduler
chmod +x claude-model-scheduler.sh lib/*.sh
./claude-model-scheduler.sh install
```

安装向导会：
1. 检测当前平台和已有配置
2. 自动清理旧版实现
3. 从 `~/.claude/settings.json` 读取当前模型映射
4. 引导选择高峰期/非高峰期模型和时间
5. 部署对应平台的调度任务

## 使用

```bash
# 查看状态
claude-model-scheduler status

# 手动切换模型
claude-model-scheduler switch sonnet
claude-model-scheduler switch opus
claude-model-scheduler switch haiku

# 重新配置
claude-model-scheduler install

# 卸载
claude-model-scheduler uninstall
```

## 工作原理

```
设定时间到达
    │
    ▼
调度器触发 (launchd / cron / schtasks)
    │
    ▼
claude-model-scheduler.sh switch <model>
    │
    ▼
备份 ~/.claude/settings.json → ~/.claude/backups/
    │
    ▼
修改 settings.json 中的环境变量
    │
    ▼
记录切换历史到 ~/.claude/scheduler.d/history.log
```

### 配置文件

| 文件 | 说明 |
|------|------|
| `~/.claude/scheduler.d/config.json` | 调度器配置（模型、时间） |
| `~/.claude/scheduler.d/history.log` | 切换历史记录 |
| `~/.claude/backups/settings.json.*` | 配置备份 |
| `~/.claude/settings.json` | Claude Code 配置（被修改的目标） |

## 系统要求

- Bash 4.0+
- `jq` 或 `python3`（用于 JSON 操作）
- macOS / Linux / Windows (Git Bash)

## License

MIT
