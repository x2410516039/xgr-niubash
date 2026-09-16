# One-shot 快路径改造记录（Agent Fast Path）

> 分支：`one-shot-fastpath`　基线：master `e753d71`（v1.1.2 后）
> 关联 commit：`890f3b1`（one-shot + `--encoded-command`）、`deb7211`（`v1:` 前缀容错）
> 面向读者：本 fork 的维护者、以及准备向上游提 PR 时的参考。

## 1. 背景与目标

`niu -c` 是 agent/CI 场景的主力入口（ZCode 的 Bash 工具经 hook 最终 spawn 的就是它）。
目标是把非交互单命令执行的启动成本压到接近原生 bash，且**不破坏任何既有行为契约**。

## 2. 改动清单

### 2.1 `crates/niubash-runtime/src/shell.rs`

- 新增 `Shell::new_one_shot()`：`new_with_script_name(Some("niu"), /*one_shot=*/true)`。
- one-shot 模式下构造器跳过：
  - **prompt 后端**：用最廉价的 `PromptBackend::Bash(BashPrompt::new(...))` 代替模板/主题/段引擎编译；
  - **bundle 补全定义解析**（`plugin_completion_defs`）与**补全目录扫描**（`load_completion_dirs_with_bundle_and_definitions`）；
  - **native widget bindings**（`plugin_native_widget_bindings`）；
  - **oh-my-niu 框架 hook 探测**：`framework_hook_defined` 在 one-shot 下直接返回 false——rc 永远不会被 source，runner 必然不存在，探测只会触发 rubash 的全 PATH/command-link 扫描；
  - 末尾的 `update_completion_state()` 快照保留（无磁盘 I/O，成本可忽略）。

### 2.2 `src/main.rs`

- `run_shell_invocation`：`invocation.command.is_some()`（即 `niu -c` / bash 风格单命令）改用 `Shell::new_one_shot()`；`"-c"` 直连分支同步替换。
- 新增 `--encoded-command <b64>`：RFC4648 解码（容忍 padding 省略与 ASCII 空白），UTF-8 校验，走与 `-c` 相同的 one-shot 流程；纯标准库实现，无新依赖。
- `decode_base64_utf8` 容错剥离可选 `v1:` 前缀（`deb7211`）：包装命令经 Git Bash 传递时，MSYS 的 POSIX 路径启发式会改写以 `/` 开头的参数；`v1:` 钉住首字符，接收端负责剥离。

### 2.3 刻意保留（设计决策）

| 保留项 | 原因 | 将来砍除的前置条件 |
|---|---|---|
| history provider | `tests/host_contract.rs::history_and_fc_use_the_host_history_provider` 钉死 `niu -c 'history; fc 2'` 读写宿主历史文件；实测仅 0.6-0.8ms | 改契约测试 + 将历史文件打开改为懒加载 |
| managed/bundle 别名 | `tests/plugin_inventory.rs` 钉死 bundle 别名（`gphase`）对 `niu -c` 可见；且 rubash `Executor` 别名表为私有字段，无公开 setter，只能逐条 `execute_ast` 注册（~1.3ms） | 上游提供 `Executor::set_alias` 后一并砍除 |
| 框架探测的 memoize 结构 | 非 one-shot 路径依赖既有行为 | — |

## 3. 验证

- `cargo test` 全量 140 passed / 0 failed（含新增 base64 单测；18 ignored 为仓库原有）。
- 行为对拍 battery：29 项（管道/循环/算术/退出码/EXIT trap/命令替换/重定向/heredoc/函数/`$0`/别名/history/case/glob），新旧二进制 stdout+stderr+exit code 全零差异（脚本见 `perf/battery.sh`）。
- `--encoded-command` 单测覆盖：padding 有无、空白、`v1:` 前缀、非法字符、非 UTF-8 拒绝。

## 4. 实测数据（Windows 11 x64, release profile）

### 4.1 启动 trace（`NIU_TRACE_STARTUP=1 niu -c "echo hello"`）

| 阶段 | 安装版 v1.1.2 二进制 | master 源码构建 | 本分支 |
|---|---|---|---|
| executor created | 8.2 | 7.4-15.0 | 7.4-8.8 |
| executor env + host handler | 12.0 | 0.6 | 0.5 |
| aliases + builtin packs | 14.0 | 1.3 | 1.1-1.4 |
| prompt backend | 11.8 | 0.4 | **0.06** |
| history provider | 1.7 | 0.8 | 0.6-0.8 |
| completion state | **73.2** | 0.23 | **0.05** |
| bundle completion + keybindings | 11.1 | 0.3 | **0.05** |
| **Shell::new 合计** | **133.4** | **13.9-21.1** | **12.1** |
| execute_script | 10.8 | 0.9 | 0.6-0.8 |
| exit trap | 11.0 | 0.9 | **0.37** |
| 进程内总计 | 155.4 | ~16 | **~13.1** |

要点：master（v1.1.2 发布后合入的 issue-79 系列等）已经消化了安装版二进制中的大部分启动开销；
本分支的净收益集中在 prompt/completion/keybindings/probe 四项的**结构性归零**，
以及 exit trap 探测的完全短路。

### 4.2 端到端（`niu -c "echo hello"`，Git Bash 计时，20 轮交错）

| 二进制 | avg | min |
|---|---|---|
| 安装版 v1.1.2 | 155ms | 130ms |
| master 构建 | 83ms | 78ms |
| 本分支 | 81ms | 77ms |
| 本分支 `--encoded-command` | 80ms | 77ms |

进程创建 + runtime + winuxcmd 选择的硬地板约 50ms。

## 5. 配套改造（本仓库之外）

- **hook 直启**（ZCode PreToolUse 包装层，C#，见 `~/.zcode/hooks/niubash-hook2.cs`）：
  包装命令由 `"hook.exe" runfile <tmp>` 改为 `"niu.exe" --encoded-command v1:<b64>`，
  省一次 exe 中转；链路 220ms → 182ms（高负载窗口；安静时段 ~165ms）。
- runfile 仍保留为 >15KB 命令的回退通道；hook 层 fail-open 语义不变。

## 6. 复现

```bash
cargo test --manifest-path D:\project\git-clone\niubash\Cargo.toml
perf/battery.sh <旧niu> <新niu> <workdir>   # 行为对拍
perf/trace-min.sh                            # 分阶段 trace 对比
```
