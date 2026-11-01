---
name: web-app-scaffold
description: 从一句话需求搭出可打开的静态网站，包含文件结构、样式和自检步骤。提示词提到网站、网页、页面或 HTML 时优先使用。
---

# 静态网站脚手架

## 何时使用

用户要求做一个网站、网页、落地页或后台面板的静态原型，且项目里还没有对应文件。

## 文件结构

按需要选择，不要一次塞入多余文件：

- `index.html`：唯一入口，声明 `<!doctype html>`、`<html lang="zh-CN">`、`<meta charset="utf-8">`、`<meta name="viewport" content="width=device-width, initial-scale=1">`。
- `styles.css`：全部样式。用 CSS 变量定义配色，不要写行内样式。
- `app.js`：交互与数据。用 `defer` 引入，不要依赖网络 CDN。
- 数据量小时直接写在 `app.js` 里，不要凭空引用不存在的 JSON 文件。

## 步骤

1. 先用 todo 列出计划：结构、样式、交互、自检。
2. 规划完成后立刻用 write_file 创建 `index.html`，一次写完整文件。
   不要反复 list_files 看目录：建站阶段的空目录没有信息量。
3. 用 write_file 创建 `styles.css`，包含窄屏（≤ 480 px）布局。
4. 用 write_file 创建 `app.js`，事件绑定放在 `DOMContentLoaded` 之后或脚本末尾。
5. 文件写完后用 list_files 确认存在。一次调用就够，path 用 `.` 表示项目根。
6. 每次 write_file 写 `index.html` 后，工具结果会附带内置结构检查。
   它已经报告标签闭合与本地引用是否缺失，不需要再跑自己写的检查。

## 自检命令

需要本仓库特有的检查时，先把脚本写成项目里的文件，再用一行短命令执行：

1. 用 write_file 创建 `check.py`，检查逻辑全部写在里面。
2. 用 run_command 执行 `python3 check.py`。
3. 把真实输出贴回给用户。

`run_command` 的命令上限是 2000 字符。不要用 heredoc 把脚本塞进命令，
超过上限会被直接拒绝。

## 验收标准

- `index.html`、`styles.css`、`app.js` 都存在且非空。
- 写 `index.html` 时工具结果里的内置检查报告标签闭合正常、本地引用都存在。
- 自己写的 `check.py` 输出通过结论。
- 页面不引用任何本地不存在的文件或外部 CDN。
- 只有在上述检查都通过之后才向用户报告完成。
