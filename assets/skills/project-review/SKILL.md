---
name: project-review
description: 审阅当前项目的结构与可运行性：列文件、找入口、跑一次真实检查、给出清单。用户要求检查或整理项目时使用。
---

# 项目审阅

## 步骤

1. 用 list_files 递归列出项目，记录文件数与入口文件。
2. 用 read_file 读取入口文件与配置（例如 `index.html`、`main.py`、`pubspec.yaml`）。
3. 用 run_command 运行项目自己的检查命令，没有检查命令时至少做一次语法检查：
   - JavaScript：`node --check app.js`
   - Python：`python3 -m py_compile main.py`
   - Shell：`bash -n script.sh`
4. 用 todo 记录发现的问题，状态从 pending 开始，逐项改为 done。

## 报告格式

- 项目入口：路径
- 文件清单：数量与关键文件
- 检查命令与真实退出码
- 问题列表：每条附上文件与行号
- 下一步建议：按影响排序，最多三条

## 约束

- 只报告真实运行过的检查结果。
- 未运行的检查在报告里标为「未验证」。
