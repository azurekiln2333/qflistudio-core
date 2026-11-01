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
6. 用 run_command 执行自检，把真实输出贴回给用户。

## 自检命令

```sh
python3 - <<'PY'
import html.parser, pathlib, sys
class P(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.errors = []
    def handle_starttag(self, tag, attrs):
        if tag not in ('meta', 'link', 'br', 'img', 'input', 'hr'):
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()
        elif tag in self.stack:
            self.errors.append(f'unclosed before </{tag}>')
p = P()
for name in ('index.html',):
    path = pathlib.Path(name)
    if not path.exists():
        sys.exit(f'{name} 缺失')
    p.feed(path.read_text(encoding='utf-8'))
    if path.stat().st_size == 0:
        sys.exit(f'{name} 为空')
print('未闭合标签:', p.errors)
print('结构检查:', 'OK' if not p.errors and not p.stack else f'失败 {p.stack}')
PY
```

## 验收标准

- `index.html`、`styles.css`、`app.js` 都存在且非空。
- 自检脚本输出 `结构检查: OK`。
- 页面不引用任何本地不存在的文件或外部 CDN。
- 只有在自检输出为 OK 之后才向用户报告完成。
