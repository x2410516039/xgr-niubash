# 工作目录状态契约（Agent cwd-state）

> 分支：`one-shot-fastpath`（承接 `890f3b1` / `deb7211` 的 agent 快路径）
> 面向读者：本 fork 的维护者、agent 宿主（DSH / hook）作者、以及准备向上游提 PR 时的参考。

## 1. 背景与目标

`niu -c` 是 agent/CI 的主力入口，但它是**一次性**的：每条命令一个新进程，起始目录由调用者传入，`cd` 出不了这一次调用。

对 agent 来说这不是小摩擦：为了让第二条命令落在正确目录，模型必须在**每条**命令前面写 `cd <项目根> && …`。代价有三层——

1. 每条命令都多花 token，且 `cd` 让命令的真实意图变模糊；
2. `cd sub && …` 之后，模型无法让"我现在在 sub"这一事实跨调用成立，只能反复重申；
3. 宿主若靠"解析命令文本"来跟踪工作目录（如 Claude Code 系 hook 的 `updatedInput` 包装成 base64），一旦命令被包装成不透明 token，宿主的跟踪就永久失效——声明"工作目录跨调用保持"的工具描述随即变成假话。

目标：给 niu 一个**显式**的目录记忆开关，让"一条命令 = 一次可审计的执行"保持不变，同时让 `cd` 在调用之间成立。

> 更新（2026-09-20）：本文描述的开关本身没有变（不带开关时行为逐字节不变），但 DSH 的 `my-bash` 预设最终**没有**采用"`cd` 持久"语义——它改成"`cd` 一次性 + `pwd` 默认在对话目录"，目录由宿主 spawn 时传入，不再走 `--cwd-state`。理由与现状见 §6；本 flag 保留给需要跨进程 `cd` 的宿主（§7 的 ZCode）。

## 2. 契约

```
niu --cwd-state <file> [--cwd-state-verbose] -c '<cmd>'
```

1. **恢复**：启动时读 `<file>`，内容有效目录 → `chdir` 过去；否则沿用调用者传入的 cwd。恢复发生在**一切之前**（先于 niu 自身启动逻辑、`source_non_interactive_env`、相对脚本路径解析）。
2. **记录**：命令结束后把 shell 的最终目录写回 `<file>`。
3. **显式开关**：不带开关时 `niu -c` 的行为逐字节不变；CI 与交互式调用者对"起始目录可预测"的依赖不能被破坏。

状态文件是一个小 JSON 对象，便于宿主读取、展示与重置：

```json
{"cwd":"D:\\project\\git-clone\\niubash","updatedAt":1789641441305}
```

读取时**容忍**手写的裸路径（`echo D:/work > state` 也能用）；写入用 `临时文件 + rename` 覆盖（Windows 上是 `MoveFileEx` + `REPLACE_EXISTING`），rename 被占用时重试 2 次并退化为直接写。

## 3. 刻意保留的设计决策

| 决策 | 原因 |
|---|---|
| 记录在 `finish_with_exit_trap` **之后** | `EXIT` trap 里的 `cd` 也算"shell 最终在哪"；`execute_script` 末尾已把进程 cwd 同步到 shell 的 `PWD`，而 trap 的 `cd` 只更新 `PWD` |
| 记录在**退出码传播之前** | 等价于 `; pwd > state` 而不是 `&& pwd > state`：命令失败也要记录，否则一次失败就丢目录 |
| 取值用 shell 的 `PWD`（`Shell::current_host_cwd()`） | `PWD` 是 shell 自己认账的目录（`pwd` 的输出），比进程 cwd 更贴近语义；`PWD` 不可用时才退进程 cwd |
| 无效状态**静默回退** | 目录被删/文件手改坏/权限不足都不该变成命令失败；下一次记录自动覆盖，状态自愈 |
| 写失败**不改退出码** | 记账失败不是命令失败；但要 `eprintln` 出来，否则"为什么没记住"无从排查 |
| **不做** `NIU_CWD_STATE` 环境变量形态 | `&`/coproc 会让 rubash 自旋出新的 `niu.exe`（`tests/background_spawn_args.rs` 钉死），环境变量会被这些子进程继承，后台 subshell 的 cwd 会污染状态；flag 形态天然只作用于本次调用 |
| **不做** 常驻会话进程 | 一次性执行模型的健壮性（崩溃无残留、无超时/僵尸/输出交错问题）比省一次进程创建值钱 |
| 覆盖范围：`-c` / `--encoded-command` / 脚本文件 / stdin 脚本 | 这四条都是一次性语义；`-C/--repl-command` 与交互式 REPL 只恢复、不记录（REPL 的退出路径不该被宿主开关改写） |
| 选项是**前缀组** | 扫描在遇到第一个非本组 token 时停止，因此 `niu -c 'echo $1' nm --cwd-state` 里的 `--cwd-state` 仍是位置参数，也不会被我方选项干扰 `ShellInvocation::parse` 的 bash 风格回退 |
| 相对 state 路径在启动时**钉死**为绝对路径 | 记录发生在命令跑完之后，而 `execute_script` 此时已经把进程 cwd 换成了 shell 的最终目录；不钉死就会出现"从 A 读、往 B 写" |

## 4. 改动清单（本仓库）

| 文件 | 内容 |
|---|---|
| `src/main.rs` | `CwdStateOption` + 前缀式选项扫描 + 恢复 + 记录 + `finish_one_shot()`（9 个退出点统一收口）+ `print_usage` |
| `crates/niubash-runtime/src/shell.rs` | `Shell::current_host_cwd()`（`PWD` → 进程 cwd 的兜底链） |
| `tests/cwd_state.rs` | 11 个契约用例（往返、失败仍记录、EXIT trap、子 shell 不泄漏、失效回退、裸路径、自动建目录、显式开关、位置参数、相对路径固定、缺参报错） |

记录点全部收口到 `finish_one_shot(cwd_state, &shell, code)`，避免在每个 `std::process::exit` 前手写一遍。

## 5. 验证

- `cargo test --workspace --locked`：**420 passed / 0 failed**（13 个测试目标；20 ignored 为仓库原有的 winuxcmd 命令链接门禁），其中新增 `tests/cwd_state.rs` 11 项。
- `cargo fmt --check -p niubash` 通过（顺带把分支上既有的 `base64_decodes_*` 测试格式化到 rustfmt 标准——该门禁在本次改动前就是红的）。
- 手工双调用：`niu --cwd-state F -c 'cd <dir>; pwd'` → `niu --cwd-state F -c pwd` 命中 `<dir>`；失败命令（退出码 1）仍然记录；`( cd x )` 不泄漏；`--encoded-command` 同样有效。
- 性能（20 轮，`echo hi` 重定向到 null）：不带开关 0.45s，带 `--cwd-state` 0.46s（≈0.5ms/次，含一次 JSON 原子写）；同机安装版 1.1.2 为 0.84s（本分支的 one-shot 快路径另有约 2× 收益）。

## 6. 配套改造（本仓库之外）：DSH `my-bash` 预设

`C:\Users\xianguanrong\.dsh\.agent-presets\my-bash\niubash-env.mjs`

宿主侧的语义最终定为 **“`cd` 一次性 + `pwd` 默认在对话目录”**：agent 不必每条命令写 `cd <项目根> && …`，同时一条命令里的 `cd` 也**不会**悄悄把后面每条命令都带走（静默漂移是“记住目录”方案自身的失败模式）。

- **目录由 spawn 传，不由 niu 选项传**：每次调用都是一次新的 `niu -c`，起始目录走 `SubprocessSpawnSpec.cwd` → `child_process.spawn`（`packages/subprocess/subprocess-local/src/spawn.ts:462`）。因此**本预设不用 `--cwd-state`**：它要的是“每个会话一个固定目录”，不是“上次漂到哪”，用 spawn cwd 表达即可。附带好处：不需要能力探测（任何 niu 版本都行，包括安装版 1.1.2），也就不存在“挂载时探测失败 → 静默退化成一次性契约”这一失败模式。niu 的 `--cwd-state` 本身保留，供确实需要跨进程 `cd` 的宿主（见 §7 的 ZCode）使用。
- **会话 → 目录的映射**：`state/<末两段路径>-<工作区哈希>.json`，一个工作区一个 JSON，里面按会话分条：

  ```json
  { "version": 2, "workspace": "D:\\project\\git-clone",
    "conversations": { "<会话id>": { "dir": "D:\\project\\git-clone\\niubash", "updatedAt": … } } }
  ```

  同一项目下的所有会话共用一个文件（好读、好 diff、好删），各会话各有自己的目录：条目初值是**会话工作区**，显式 `workdir` 会改写它（之后的调用都从那里开始）。>14 天未动的文件在挂载时清理；删掉某个工作区的文件 = 把该项目的会话重置回工作区。
- **v1 不迁移**：v1 记的是“`cd` 漂移到了哪”，v2 记的是“这个会话应该在哪个目录”，语义不同，无法区分“漂移”与“有意 `workdir`”；读到 `version != 2` 的文件直接当空文档并替换（warn 一次）。升级时会话一律先回到自己的工作区。
- **调用**：`start = workdir ?? 该会话条目 ?? 会话工作区 ?? 宿主进程 cwd`；`workdir` 必须存在，否则忽略并在结果里说明（既不 spawn ENOENT，也不把无效目录写进记录）；只有会话条目真的变了才写文件，同一目录的连续调用不产生写放大。
- **可见性**：仅当本次调用的目录 ≠ 会话工作区时，结果末尾追加 `[cwd: <目录>]`；`workdir` 被忽略时追加 `[workdir ignored: <值>]`。
- **不再注册 hook**：`agent/created` 播种已删除（首次工具调用时懒播种即可），插件只剩“一个工具 + 一段提示词”。
- **并发**：同一工作区的多个会话各自合并自己的条目并整文件 rename，last rename wins（窗口是“读→写”的微秒级，损坏不可能，丢的条目会被该会话下一次调用重新播种）。同一会话的并行调用之间已无目录竞态——目录是每次调用显式给的，不共享。

## 7. 已知未做

- **环境变量与 shell 函数**不持久化（只有 cwd）。若将来要做，建议另开 `--env-state`，并沿用“显式开关 + 自愈回退”的形状。
- **ZCode hook**（`~/.zcode/hooks/`）未接：其 `niu --encoded-command` 包装只需在 argv 前加 `--cwd-state <按工作区根哈希命名>.txt`，即可拿到跨调用目录（那是“`cd` 持久”语义，与本预设刻意选择的“`cd` 一次性”相反），并天然按项目隔离。
- **对话目录的显式切换**只有 `workdir` 一条路（改会话记录、之后每次调用生效）；没有“本会话永久换目录”的交互式命令。

## 8. 复现

```bash
cargo fmt --check -p niubash
cargo build --locked && cargo test --workspace --locked
# 双调用验收
F=D:/tmp/niu-cwd.json
target/release/niu.exe --cwd-state "$F" -c 'cd D:/project/git-clone/niubash; pwd'
target/release/niu.exe --cwd-state "$F" -c 'pwd'      # 必须输出 niubash 目录
```
