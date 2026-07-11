# Codex Quota Bar

一个轻量的 Windows 桌面浮条：在任务栏上方显示 Codex 的 5 小时与每周剩余额度，并在额度偏低时提示预警。

## 功能

- 从本机 Codex CLI 的只读 `app-server` JSON-RPC 获取真实额度与重置时间。
- Codex 窗口出现时显示，最小化或关闭时隐藏。
- 半透明“柔雾玻璃”细条，显示两项额度、状态点和进度线。
- 点击细条向上展开详情：额度、重置时间、同步状态与“立即同步”。
- 剩余额度低于 20% 显示黄色，低于 10% 显示红色。
- 启动器在启动前自动清理旧实例，避免重复浮条。
- 可选 Windows 登录自启；登录后打开 Codex 即自动显示浮条。

## 环境要求

- Windows 10 或 Windows 11。
- Windows PowerShell 5.1（系统自带）。
- 已安装并登录官方 Codex CLI。

如果 PowerShell 的 `codex` 命令被执行策略拦截，请使用 `.cmd` 启动器：

```powershell
codex.cmd login
```

若尚未安装 CLI：

```powershell
npm.cmd install -g @openai/codex
```

完成网页登录后确认状态：

```powershell
codex.cmd login status
```

## 启动

双击 `Start-CodexQuotaBar.cmd`。启动器会停止此前运行的浮条实例，再以后台方式启动新版。

也可以在 PowerShell 中运行：

```powershell
.\Start-CodexQuotaBar.cmd
```

## 设置自动启动

运行一次：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1
```

之后监测器会随 Windows 登录在后台运行；每次打开 Codex 时，浮条会自动出现。

如需移除登录自启：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1 -Remove
```

## 验证额度连接

在此目录中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexQuotaBar.ps1 -CheckRpc
```

成功时会输出 5 小时与每周剩余额度、重置时间和更新时间的 JSON。

## 隐私与安全

- 只启动 `codex -s read-only -a untrusted app-server`。
- 不读取浏览器 Cookie，不保存账号密码、OAuth token 或 API key。
- 不直接调用网页私有接口；凭证由已登录的 Codex CLI 自行管理。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `CodexQuotaBar.ps1` | 主程序与浮条界面 |
| `Start-CodexQuotaBar.cmd` | 清理旧实例后启动主程序 |
| `Stop-Existing-CodexQuotaBars.ps1` | 关闭旧版浮条进程 |
| `Launch-CodexQuotaBar.vbs` | 无命令窗口后台启动器 |
| `Install-Autostart.ps1` | 添加或移除 Windows 登录自启 |

## 排错

若 `-CheckRpc` 提示未认证，请重新运行 `codex.cmd login` 并完成浏览器授权。

若不显示浮条，确认 Codex 桌面窗口已打开，并重新运行 `Start-CodexQuotaBar.cmd`。
