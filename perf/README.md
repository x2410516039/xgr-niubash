# perf/ — 本机测量工具（机器特定，非通用）

配套文档：`docs/one-shot-fastpath.md`、`docs/further-speed-optimization.md`。

脚本内含本机绝对路径（Git Bash、Niubash 安装位、对照构建 worktree），
换机器需先改路径。所有脚本按 `docs/further-speed-optimization.md` §6 的
测量纪律使用：绝对路径 Git Bash 执行、同窗口交错、min 为信号。

| 脚本 | 用途 |
|---|---|
| `battery.sh` | 新旧二进制 29 项行为对拍（stdout/stderr/exit code 零差异校验） |
| `bench.sh` | 单二进制多命令延迟采样 |
| `bench3.sh` | 三二进制交错基准（master 对照 / fastpath / 安装版） |
| `bench-final.sh` | 最终 A/B 端到端 + `--encoded-command` 通道 |
| `bench-vs-bash.sh` | 与原生 Git Bash 5.3 对拍的交错基准（本机 niu 全命令面快于 Git Bash） |
| `trace-min.sh` | `NIU_TRACE_STARTUP` 分阶段最小值对比 |
| `chain-bench.sh` | hook 链路四段耗时（原生/引擎/stage1/stage2） |

快照 exe（`niu-fastpath` / `niu-master` / `niu-dyncrt` / `niu-crtstatic` /
`niu-lazyhist` / `niu-tuned`）为本地工作产物，不进 git；重建方式见
`docs/further-speed-optimization.md`（crt-static 结论：不采纳，§3b）。
