# Codex Quota Bar

[English](README.md) · [中文](README.zh-CN.md)

一个轻量的 Windows 桌面浮条，用于显示 Codex 的每周剩余额度，并在额度偏低时给出清晰预警。

![Codex Quota Bar 柔雾玻璃示例](assets/codex-quota-bar-example.svg)

## 功能

- 通过本机 Codex CLI 的只读 `app-server` JSON-RPC 获取每周额度与重置时间。
- 只有官方 ChatGPT/Codex 桌面窗口处于前台时显示，切换到其他应用后隐藏。
- 柔雾玻璃深色界面，搭配低存在感边框、悬停高亮、状态点和紧凑进度线。
- 点击浮条展开详情面板，查看重置时间、同步状态并手动同步。
- 剩余额度低于 20% 显示黄色，低于 10% 显示红色。
- 启动前自动清理旧实例，避免重复浮条。
- 可选 Windows 登录自启。

## 环境要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1
- 已安装并登录官方 Codex CLI

如果 PowerShell 拦截 `codex`，请使用：

```powershell
codex.cmd login
codex.cmd login status
```

尚未安装 CLI 时：

```powershell
npm.cmd install -g @openai/codex
```

## 启动

双击 `Start-CodexQuotaBar.cmd`，或运行：

```powershell
.\Start-CodexQuotaBar.cmd
```

如果已经安装计划任务，启动器会优先启动受托管的监控器；否则使用无窗口的手动监控器。

## 推荐：跟随桌面端生命周期自动启停

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1
```

安装后，轻量监控器会在登录时启动：打开 ChatGPT/Codex 桌面端时启动浮条，完全关闭桌面端时停止浮条；监控器异常退出后由 Windows 自动恢复。

计划任务通过无窗口的 Windows Script Host 启动监控器；即使 Windows Terminal 是系统默认终端，长期运行的监控器也不会打开终端窗口。

移除自启：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1 -Remove
```

## 验证额度连接

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexQuotaBar.ps1 -CheckRpc
```

## 隐私与安全

- 只启动 `codex -s read-only -a untrusted app-server`。
- 不读取浏览器 Cookie，不保存密码、OAuth token 或 API key。
- 不直接调用网页私有额度接口，凭证由已登录的本机 Codex CLI 管理。

## 文件

| 文件 | 用途 |
| --- | --- |
| `CodexQuotaBar.ps1` | 浮条界面、前台检测、RPC 同步与交互 |
| `CodexQuotaBar-Watchdog.ps1` | 跟随 ChatGPT/Codex 桌面端生命周期，并写入有限大小的诊断日志 |
| `Start-CodexQuotaBar.cmd` | 启动计划任务监控器，未安装时使用手动回退 |
| `Stop-Existing-CodexQuotaBars.ps1` | 清理重复实例 |
| `Launch-CodexQuotaBar.vbs` | 无控制台窗口运行监控器，并保持计划任务处于活动状态 |
| `Install-Autostart.ps1` | 添加或移除生命周期监控计划任务 |
| `assets/codex-quota-bar-example.svg` | README 示例图片 |

## 排错

如果 `-CheckRpc` 提示未登录，请重新运行 `codex.cmd login` 并完成浏览器授权。

如果浮条不显示，请先打开 Codex 桌面窗口，再运行 `Start-CodexQuotaBar.cmd`，并查看 `CodexQuotaBar-Watchdog.log` 中的错误。
