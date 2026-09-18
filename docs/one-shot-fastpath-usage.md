# one-shot-fastpath 分支：优化总览与使用指南（Windows）

> 面向读者：想在 Windows 上使用本分支优化版 `niu.exe` 的人与 agent 宿主作者。
> **不依赖 DSH**：任何能 spawn 子进程的环境（PowerShell / Python / Node / C# / 任务计划…）都适用。
> 前置阅读（实现细节）：`docs/one-shot-fastpath.md`、`docs/cwd-state.md`、`docs/further-speed-optimization.md`。

## 1. 这个分支做了什么（相对 master `e753d71`）

| commit | 内容 | 收益 |
|---|---|---|
| `890f3b1` | `niu -c` / `--encoded-command` 走 one-shot 快路径：跳过 prompt/主题编译、补全目录扫描、bundle 补全解析、native widget、oh-my-niu hook 探测 | 端到端 ~155ms → ~80ms；进程内启动 ~133ms → ~13ms |
| `deb7211` | `--encoded-command` 容忍 `v1:` 前缀 | 经 Git Bash 中转时防 MSYS 路径改写 |
| `5c4ec1d` | `--cwd-state`：一次性调用之间的目录记忆 | agent 不必每条命令写 `cd <项目根>` |
| `833cc7a` | 历史文件懒加载 + 框架目录探测削减 | 进程内启动 ~10.5-12ms → ~8.3ms |

本机（Windows 11 x64）与原生 GNU Bash 5.3（Cygwin）同窗口交错对拍（min）：

| 命令 | Git Bash | 本分支 niu |
|---|---|---|
| `true` | ~50ms | **~22ms** |
| `echo hello` | ~54ms | **~23ms** |
| `echo hello \| grep -c hello` | ~93ms | **~43ms** |
| `for i in 1 2 3 4 5; do echo $i; done` | ~55ms | **~21ms** |

> 数字是本机实测，不同机器/负载会浮动；对比务必同窗口交错、取 min（见 §6）。

## 2. 获取优化版

### 方式 A：源码构建

```powershell
# 前置：Rust (MSVC 工具链) — https://rustup.rs
git clone -b one-shot-fastpath https://github.com/unixwin/niubash.git
cd niubash
cargo build --release --locked
# 产物：target\release\niu.exe
```

### 方式 B：替换已安装版的 niu.exe（推荐，复用其 winuxcmd）

官方安装目录自带 `winuxcmd\`（Unix 命令的实现与命令链接）。用方式 A 构建出的
`niu.exe` 覆盖 `...\Programs\Niubash\niu.exe` 即可（先备份旧文件）：

```powershell
Copy-Item "$env:LOCALAPPDATA\Programs\Niubash\niu.exe" "$env:LOCALAPPDATA\Programs\Niubash\niu.exe.bak"
Copy-Item "D:\path\to\target\release\niu.exe" "$env:LOCALAPPDATA\Programs\Niubash\niu.exe" -Force
```

### 方式 C：全新打包

```powershell
powershell -File scripts\package-release.ps1 -Version <x.y.z> -WinuxCmdPath <winuxcmd 目录>
```

### 验证

```powershell
niu --version          # 应输出 1.1.2（或更新）
niu -c "echo ok"       # 应输出 ok，退出码 0
```

## 3. Windows 环境要求

- Windows 10/11 x64，无 MSYS2 / Git Bash / Cygwin / WSL 依赖。
- **winuxcmd 命令链接必须在 PATH 里**：`ls`、`grep`、`head` 等 Unix 命令由
  winuxcmd 命令链接提供。缺它时内建与外部 Windows 程序不受影响，但 Unix 命令
  会报 command not found —— 修链接，不要换 shell。
- 路径风格：接受 Windows 原生路径（`C:\...` 或 `C:/...`）；shell 内部按
  `NIU_SHELL_PATH_STYLE`（默认 `native`）显示。

## 4. 使用方式

### 4.1 `niu -c`（CI / 脚本）

```powershell
niu -c "seq 1 5 | tail -2"
echo $LASTEXITCODE   # 退出码精确透传，非交互、无 banner、输出稳定
```

### 4.2 `--encoded-command`（宿主程序化调用，推荐）

命令以 RFC4648 base64 传入，**没有引号转义问题**（容忍省略 padding 与 ASCII 空白）：

```powershell
# PowerShell 生成 payload
$payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('echo "a b" ''c'''))
niu --encoded-command $payload
```

```bash
# Python / Node 生成 payload
python -c "import base64;print(base64.b64encode('echo hello'.encode()).decode())"
node -e "console.log(Buffer.from('echo hello').toString('base64'))"
```

`v1:` 前缀：仅当 payload 会**经 Git Bash 中转**（MSYS 会改写以 `/` 开头的参数）
时才加，接收端自动剥离；直接 spawn 不需要。

### 4.3 `--cwd-state`（agent 跨调用目录记忆）

```powershell
niu --cwd-state "$env:USERPROFILE\.niu-cwd.json" --cwd-state-verbose -c "cd D:\work; ls"
```

- **恢复**：启动时读状态文件，有效目录 → 进入；无效/缺失 → 静默沿用调用者 cwd。
- **记录**：命令结束后把 shell 最终目录写回（JSON：`{"cwd":"...","updatedAt":<ms>}`）。
- 失败的命令也记录目录；写失败不改退出码。
- **显式开关**：不带 `--cwd-state` 时 `niu -c` 行为逐字节不变（CI 依赖可预测起始目录）。

### 4.4 脚本文件与 stdin

```powershell
niu script.sh              # 直接执行脚本文件
Get-Content script.sh | niu   # stdin 脚本
```

## 5. 宿主接入示例（任何宿主）

通用模式：`niu.exe --cwd-state <file> --encoded-command <b64>`，读三件套
stdout / stderr / exit code。

### Python

```python
import base64, subprocess

NIU = r"C:\Users\<you>\AppData\Local\Programs\Niubash\niu.exe"
STATE = r"C:\agent\niu-cwd.json"

def run(cmd: str, timeout: float = 30):
    payload = base64.b64encode(cmd.encode("utf-8")).decode()
    p = subprocess.run(
        [NIU, "--cwd-state", STATE, "--encoded-command", payload],
        capture_output=True, text=True, timeout=timeout,
    )
    return p.stdout, p.stderr, p.returncode
```

### Node.js

```js
import { execFile } from "node:child_process";

const run = (cmd, timeout = 30_000) =>
  new Promise((resolve) => {
    const payload = Buffer.from(cmd, "utf8").toString("base64");
    execFile(
      niuPath,
      ["--cwd-state", stateFile, "--encoded-command", payload],
      { timeout },
      (err, stdout, stderr) => resolve({ stdout, stderr, code: err?.code ?? 0 }),
    );
  });
```

### PowerShell / C#

```powershell
& "$env:LOCALAPPDATA\Programs\Niubash\niu.exe" --cwd-state "$env:USERPROFILE\.niu-cwd.json" `
  --encoded-command ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd)))
```

```csharp
var psi = new ProcessStartInfo(niuExe,
    $"--cwd-state \"{stateFile}\" --encoded-command {payload}")
{ UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
```

### 超时与取消

Windows 没有进程组信号。超时杀整棵树：宿主语言内用 Job Object（`CreateJobObject`
+ `TerminateJobObject`），或外部 `taskkill /T /F /PID <pid>`。niubash 自身
panic=abort、无 catch_unwind，Ctrl+C 处理是原子标志位，无残留线程。

## 6. 性能预期与自测

- 预期：单命令端到端 ~60-90ms（受机器负载影响）；同窗口下全面快于 Git Bash。
- 自测脚本：`perf/bench-vs-bash.sh`（与本机 Git Bash 对拍）、`perf/battery.sh`
  （29 项行为对拍）、`perf/trace-min.sh`（`NIU_TRACE_STARTUP=1` 分阶段 trace）。
  脚本内含本机绝对路径，换机器先改路径。
- 测量纪律：同窗口交错（round-robin）、取 min 为信号 —— e2e 抖动 ±5-15ms，
  毫秒级优化只能靠 trace 段数据归因。

## 7. 已知边界

- **~50ms 进程创建硬地板**：一次性进程模型无法突破；需要 ~10-20ms 级请参见
  `docs/further-speed-optimization.md` §4 的常驻 `niu-agentd` 设计（未实现）。
- 进程内最大单项 `Executor::new`（~6-7ms）在 rubash 上游；别名注册（~1ms）
  等上游 `Executor::set_alias`。
- 运行时环境变量用 `NIU_` 前缀；`--cwd-state` 是唯一跨调用状态，且完全显式。
- 默认行为护栏：不带新开关的 `niu -c` 与 master 行为一致（battery 29/29 零差异，
  `cargo test --workspace` 全绿）。
