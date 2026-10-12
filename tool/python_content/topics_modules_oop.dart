import 'python_topic.dart';

/// Chapter 5-6: 模块/异常/文件 与 面向对象 (topics 041-068).
const List<PythonTopic> pythonTopicsModulesOop = <PythonTopic>[
  PythonTopic(
    id: 41,
    level: 'intermediate',
    title: 'Python 041：模块与 import',
    summary: '把代码分到模块里，用 import 复用。',
    concepts: ['import', 'from...import', 'as', '__name__'],
    objective: '会导入模块、给模块起别名、理解 __name__。',
    prerequisites: ['定义函数与返回值'],
    explain:
        '每个 .py 文件就是一个模块。import math 导入整个模块，用 math.sqrt 访问；'
        'from math import sqrt 只导入某个名字，直接用 sqrt。as 起别名避免冲突，'
        '如 import math as m。模块顶层的 if __name__ == "__main__": 只在「直接'
        '运行该文件」时执行，被 import 时不执行——这让文件既能当脚本又能当模块。',
    code:
        'import math\n'
        'import math as m\n'
        'from math import sqrt\n'
        '\n'
        'print(math.pi)\n'
        'print(m.sqrt(16))\n'
        'print(sqrt(25))\n'
        'print(__name__)\n',
    output:
        '3.141592653589793\n'
        '4.0\n'
        '5.0\n'
        '__main__\n',
    pitfalls: [
      '模块名和当前文件里定义的变量同名会覆盖。',
      'from math import * 会把大量名字带进来，容易命名冲突。',
      '被 import 的模块里若有代价大的顶层代码，会在导入时就执行。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 math 模块计算 2 的平方根并保留两位小数。',
        hint: 'math.sqrt(2)，用 f-string 的 :.2f。',
        answer: 'import math\nprint(f"{math.sqrt(2):.2f}")',
      ),
    ],
  ),
  PythonTopic(
    id: 42,
    level: 'intermediate',
    title: 'Python 042：导入路径与 sys.path',
    summary: '理解导入查找顺序和项目内模块引用。',
    concepts: ['sys.path', '导入查找', '入口目录'],
    objective: '理解导入查找顺序并会查看 sys.path 诊断导入问题。',
    prerequisites: ['模块与 import'],
    explain:
        '导入模块时 Python 按 sys.path 里的目录顺序查找。本应用的运行时会把入口'
        '文件所在目录和项目根目录放进 sys.path，所以可以 import 同项目的模块。'
        '查看 sys.path 能帮助定位「为什么导入不到」。导入是相对路径解析，不该依赖'
        '进程的工作目录。',
    code:
        'import sys\n'
        '\n'
        'print(sys.platform in ("win32", "linux", "darwin", "ohos", "android", "ios"))\n'
        'print(len(sys.path) >= 1)\n'
        'print(sys.path[0] == "" or sys.path[0].endswith(".py") or "\\\\" in sys.path[0] or "/" in sys.path[0])\n'
        'print(sys.argv[0].endswith(".py") or sys.argv[0] == "main.py")\n'
        'print(sys.maxsize > 0)\n',
    output:
        'True\n'
        'True\n'
        'True\n'
        'True\n'
        'True\n',
    pitfalls: [
      '用相对路径导入会随工作目录变化，容易出错。',
      '模块名和标准库同名会遮蔽标准库。',
      '循环导入（A 导入 B，B 又导入 A）会导致部分名字未定义。',
    ],
    tasks: [
      PythonTask(
        prompt: '打印 sys.path 的第一个目录，判断它是否指向当前项目。',
        hint: '观察输出内容。',
        answer: 'import sys\nprint(sys.path[0])',
      ),
    ],
  ),
  PythonTopic(
    id: 43,
    level: 'intermediate',
    title: 'Python 043：异常基础',
    summary: '用 try/except 捕获并处理错误。',
    concepts: ['try/except', '异常类型', 'ValueError'],
    objective: '会捕获特定异常并给出可读的错误处理。',
    prerequisites: ['定义函数与返回值'],
    explain:
        '出错时 Python 抛出异常，不处理程序就中断。try/except 把可能出错的代码'
        '包起来，按异常类型捕获。捕获要具体（如 ValueError），不要用裸 except 把'
        '所有错误都吞掉——那会掩盖真正的 bug。把易出错的操作放在 try 里，处理逻辑'
        '写在 except 里。',
    code:
        'def parse_int(text):\n'
        '    try:\n'
        '        return int(text)\n'
        '    except ValueError:\n'
        '        return None\n'
        '\n'
        'print(parse_int("42"))\n'
        'print(parse_int("abc"))\n'
        '\n'
        'try:\n'
        '    result = 10 / 0\n'
        'except ZeroDivisionError as e:\n'
        '    print("除零错误：", e)\n',
    output:
        '42\n'
        'None\n'
        '除零错误： divide by zero\n',
    pitfalls: [
      '裸 except 捕获所有异常（包括键盘中断），应指定类型。',
      'try 块范围太大，会把无关代码的错误也归到一起。',
      '捕获后什么都不做（静默吞掉）会让问题更难排查。',
      '本内置运行器的 ZeroDivisionError 文案是 "divide by zero"，与 CPython 的 "division by zero" 不同。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个安全除法函数，被除数为 0 时返回 None。',
        hint: '捕获 ZeroDivisionError。',
        answer: 'def safe_div(a, b):\n    try:\n        return a / b\n    except ZeroDivisionError:\n        return None\nprint(safe_div(1, 0))',
      ),
    ],
  ),
  PythonTopic(
    id: 44,
    level: 'intermediate',
    title: 'Python 044：异常进阶——raise 与自定义异常',
    summary: '主动抛异常、定义自己的异常类型。',
    concepts: ['raise', '自定义异常', '异常继承'],
    objective: '会定义并抛出有语义的异常类型。',
    prerequisites: ['异常基础'],
    explain:
        '用 raise 主动抛异常表达「这个输入不合法」。自定义异常通过继承 Exception '
        '定义，名字要说明问题类型；在库代码里抛具体类型，让调用方能精确捕获。'
        '自定义异常可以携带额外信息，比如通过 __init__ 存字段。',
    code:
        'class BalanceError(Exception):\n'
        '    pass\n'
        '\n'
        'class Account:\n'
        '    def __init__(self, balance):\n'
        '        self.balance = balance\n'
        '    def withdraw(self, amount):\n'
        '        if amount > self.balance:\n'
        '            raise BalanceError(f"余额不足：需要 {amount}，只有 {self.balance}")\n'
        '        self.balance -= amount\n'
        '        return self.balance\n'
        '\n'
        'acc = Account(100)\n'
        'print(acc.withdraw(30))\n'
        'try:\n'
        '    acc.withdraw(200)\n'
        'except BalanceError as e:\n'
        '    print(e)\n',
    output:
        '70\n'
        '余额不足：需要 200，只有 70\n',
    pitfalls: [
      '自定义异常应继承 Exception，而不是 BaseException。',
      '抛出过于笼统的 Exception 让调用方无法区分错误种类。',
      '在异常里放太多内容会让错误信息难读。',
    ],
    tasks: [
      PythonTask(
        prompt: '定义一个 AgeError，年龄为负时抛出。',
        hint: 'class AgeError(Exception): pass。',
        answer: 'class AgeError(Exception):\n    pass\ndef check(age):\n    if age < 0:\n        raise AgeError("年龄不能为负")\n    return age\ntry:\n    check(-1)\nexcept AgeError as e:\n    print(e)',
      ),
    ],
  ),
  PythonTopic(
    id: 45,
    level: 'intermediate',
    title: 'Python 045：常见异常辨析',
    summary: '认识 IndexError、KeyError、ValueError、TypeError 等。',
    concepts: ['IndexError', 'KeyError', 'ValueError', 'TypeError'],
    objective: '能按错误信息判断异常类型并针对性修复。',
    prerequisites: ['异常基础'],
    explain:
        '常见异常各有含义：IndexError 是序列下标越界，KeyError 是字典键不存在，'
        'ValueError 是类型对但值非法（如 int("abc")），TypeError 是类型不匹配'
        '（如 "1" + 1），ZeroDivisionError 是除零，AttributeError 是对象没有该属性。'
        '读 traceback 的最后一行的异常名，通常就能定位问题。',
    code:
        'def show(label, func):\n'
        '    try:\n'
        '        func()\n'
        '    except Exception as e:\n'
        '        print(label, "->", type(e).__name__)\n'
        '\n'
        'show("下标越界", lambda: [1, 2][5])\n'
        'show("键不存在", lambda: {"a": 1}["b"])\n'
        'show("值非法", lambda: int("abc"))\n'
        'show("类型不符", lambda: "1" + 1)\n'
        'show("除零", lambda: 1 / 0)\n',
    output:
        '下标越界 -> IndexError\n'
        '键不存在 -> KeyError\n'
        '值非法 -> ValueError\n'
        '类型不符 -> TypeError\n'
        '除零 -> ZeroDivisionError\n',
    pitfalls: [
      '把 ValueError 和 TypeError 混淆：前者值不对，后者类型不对。',
      'KeyError 的提示只含键名，要结合上下文判断。',
      '捕获 Exception 会把所有类型一网打尽，调试时先不捕获。',
    ],
    tasks: [
      PythonTask(
        prompt: '分别触发 IndexError 和 KeyError 并打印它们的类型名。',
        hint: '用 type(e).__name__。',
        answer: 'for f in [lambda: [][0], lambda: {}["k"]]:\n    try:\n        f()\n    except Exception as e:\n        print(type(e).__name__)',
      ),
    ],
  ),
  PythonTopic(
    id: 46,
    level: 'intermediate',
    title: 'Python 046：文件读写',
    summary: '用 open 和 with 读写项目内文件。',
    concepts: ['open', 'with', '读/写模式'],
    objective: '会用 with 安全地读写文本文件。',
    prerequisites: ['异常基础'],
    explain:
        'open(path, mode) 打开文件，mode 有 "r"（读，默认）、"w"（覆盖写）、"a"'
        '（追加）。用 with open(...) as f 能在块结束时自动关闭文件，即使中途出错'
        '也如此，比手动 close 更安全。本应用的运行时只允许访问项目目录内的路径。',
    code:
        'with open("notes.txt", "w") as f:\n'
        '    f.write("第一行\\n")\n'
        '    f.write("第二行\\n")\n'
        '\n'
        'with open("notes.txt") as f:\n'
        '    content = f.read()\n'
        'print(content)\n'
        '\n'
        'with open("notes.txt", "a") as f:\n'
        '    f.write("第三行\\n")\n'
        'with open("notes.txt") as f:\n'
        '    print("--".join(f.read().splitlines()))\n',
    output:
        '第一行\n'
        '第二行\n'
        '\n'
        '第一行--第二行--第三行\n',
    pitfalls: [
      '模式 "w" 会清空原文件，想保留内容用 "a"。',
      '忘记 with 或 close 可能让内容未刷新到磁盘。',
      '写路径越出项目目录会被运行时拒绝。',
    ],
    tasks: [
      PythonTask(
        prompt: '把一个列表的每项写入文件，再读回来。',
        hint: '写时每项加 \\n，读时 splitlines。',
        answer: 'lines = ["a", "b", "c"]\nwith open("out.txt", "w") as f:\n    for x in lines:\n        f.write(x + "\\n")\nwith open("out.txt") as f:\n    print(f.read().splitlines())',
      ),
    ],
  ),
  PythonTopic(
    id: 47,
    level: 'intermediate',
    title: 'Python 047：文件进阶——逐行处理',
    summary: '按行迭代文件，处理较大文本。',
    concepts: ['逐行迭代', 'splitlines', 'strip'],
    objective: '会逐行读取并处理文件内容。',
    prerequisites: ['文件读写'],
    explain:
        '文件对象本身可迭代，for line in f 一次读一行，适合大文件（不必一次读进'
        '内存）。每行通常带行尾换行，处理前用 strip() 或 rstrip("\\n") 去掉。想一次'
        '拿到所有行的列表可以用 readlines() 或 read().splitlines()，但要留意内存。',
    code:
        'with open("data.txt", "w") as f:\n'
        '    f.write("10\\n20\\n30\\n")\n'
        '\n'
        'total = 0\n'
        'with open("data.txt") as f:\n'
        '    for line in f:\n'
        '        total += int(line.strip())\n'
        'print(total)\n'
        '\n'
        'with open("data.txt") as f:\n'
        '    lines = [line.strip() for line in f if line.strip()]\n'
        'print(lines)\n',
    output:
        '60\n'
        "['10', '20', '30']\n",
    pitfalls: [
      '不去掉行尾换行会让 int() 转换失败。',
      '空行要过滤，否则转换或计数会出错。',
      '边遍历边在别处关闭文件会报 ValueError。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计文件里非空行的数量。',
        hint: '遍历时用 if line.strip() 过滤。',
        answer: 'with open("data.txt", "w") as f:\n    f.write("a\\n\\nb\\n")\ncount = 0\nwith open("data.txt") as f:\n    for line in f:\n        if line.strip():\n            count += 1\nprint(count)',
      ),
    ],
  ),
  PythonTopic(
    id: 48,
    level: 'intermediate',
    title: 'Python 048：文本编码与处理',
    summary: '理解 UTF-8、换行和字符串清洗。',
    concepts: ['编码', '换行', 'strip', 'replace'],
    objective: '会处理带换行和空白的文本并做清洗。',
    prerequisites: ['字符串进阶——split/join/strip'],
    explain:
        '文本在文件里按某种编码存成字节，UTF-8 是现代默认。本运行的 I/O 都是 UTF-8。'
        '处理文本时常见任务是：去掉首尾空白、统一换行、去除多余空行、替换不需要的'
        '字符。理解「字符串是字符序列、编码是存储方式」能避免乱码类困惑。',
    code:
        'raw = "  Hello\\r\\n  World  \\n\\n"\n'
        'print(repr(raw))\n'
        'lines = [line.strip() for line in raw.splitlines()]\n'
        'print(lines)\n'
        'cleaned = [line for line in lines if line]\n'
        'print(cleaned)\n'
        'joined = " ".join(cleaned)\n'
        'print(joined)\n',
    output:
        "'  Hello\\r\\n  World  \\n\\n'\n"
        "['Hello', 'World', '']\n"
        "['Hello', 'World']\n"
        'Hello World\n',
    pitfalls: [
      'splitlines() 能同时处理 \\n 和 \\r\\n，比 split("\\n") 稳健。',
      'strip() 去掉两端所有空白，包括制表符，不只是空格。',
      '不同编码读同一文件可能乱码，需明确 UTF-8。',
    ],
    tasks: [
      PythonTask(
        prompt: '把多行文本清洗成非空行的列表。',
        hint: 'splitlines + strip + 过滤。',
        answer: 'text = " a \\n\\n b \\n"\nprint([l.strip() for l in text.splitlines() if l.strip()])',
      ),
    ],
  ),
  PythonTopic(
    id: 49,
    level: 'intermediate',
    title: 'Python 049：json 模块基础',
    summary: '在字符串和 Python 对象之间转换 JSON。',
    concepts: ['json.loads', 'json.dumps', 'JSON 结构'],
    objective: '会把 JSON 文本解析成对象、把对象序列化成 JSON。',
    prerequisites: ['字典基础'],
    explain:
        'json.loads(text) 把 JSON 文本解析成 Python 的 dict/list/str/int/float/bool/'
        'None；json.dumps(obj) 反过来把对象转成 JSON 文本。JSON 是跨语言的数据'
        '交换格式，键必须是字符串。注意 JSON 的 true/false/null 对应 Python 的 '
        'True/False/None。',
    code:
        'import json\n'
        '\n'
        'data = json.loads(\'{"name": "ming", "age": 18, "tags": ["a", "b"]}\')\n'
        'print(data["name"], data["age"])\n'
        'print("-".join(data["tags"]))\n'
        '\n'
        'text = json.dumps({"ok": True, "n": None})\n'
        'print("true" in text, "null" in text)\n'
        'print(json.loads(text))\n',
    output:
        'ming 18\n'
        'a-b\n'
        'True True\n'
        "{'ok': True, 'n': None}\n",
    pitfalls: [
      'JSON 的 true/false/null 和 Python 的 True/False/None 不同写。',
      '本内置运行器的 json.dumps 按键的哈希序输出，键顺序不稳定；需要稳定文本时不要直接打印整个 JSON。',
      'JSON 键必须是字符串，数字键会被转成字符串。',
    ],
    tasks: [
      PythonTask(
        prompt: '把嵌套字典转成 JSON 字符串再解析回来。',
        hint: 'dumps 后 loads。',
        answer: 'import json\nd = {"a": {"b": [1, 2]}}\ns = json.dumps(d)\nprint(json.loads(s)["a"]["b"])',
      ),
    ],
  ),
  PythonTopic(
    id: 50,
    level: 'intermediate',
    title: 'Python 050：json 进阶——读写配置',
    summary: '把 JSON 存进文件、读出来当配置。',
    concepts: ['json.dump', 'json.load', '配置文件'],
    objective: '会把结构数据持久化为 JSON 文件并读回。',
    prerequisites: ['json 模块基础', '文件读写'],
    explain:
        'json.dump(obj, f) 直接把对象写进已打开的文件，json.load(f) 从文件读出对象，'
        '省去手动 read/write 字符串。这类「把配置存成 JSON」的模式很常见：程序启动'
        '读配置、退出时写回。要可读性好可以用 json.dumps(indent=2)。',
    code:
        'import json\n'
        '\n'
        'config = {"theme": "dark", "font_size": 14, "recent": ["a.py", "b.py"]}\n'
        'with open("config.json", "w") as f:\n'
        '    f.write(json.dumps(config))\n'
        '\n'
        'with open("config.json") as f:\n'
        '    loaded = json.load(f)\n'
        'print(loaded["theme"], loaded["font_size"])\n'
        'print("-".join(loaded["recent"]))\n',
    output:
        'dark 14\n'
        'a.py-b.py\n',
    pitfalls: [
      '本内置运行器的 json.dumps 不支持 ensure_ascii/indent 等关键字，只接受位置参数。',
      '读一个损坏的 JSON 文件会抛异常，要配合 try/except。',
      'dumps 的对象里若含不可序列化类型（如集合）会报错。',
    ],
    tasks: [
      PythonTask(
        prompt: '把字典写入 settings.json 再读出来打印某个键。',
        hint: '用 json.dumps 写、json.load 读。',
        answer: 'import json\nwith open("settings.json", "w") as f:\n    f.write(json.dumps({"x": 1}))\nwith open("settings.json") as f:\n    print(json.load(f)["x"])',
      ),
    ],
  ),
  PythonTopic(
    id: 51,
    level: 'intermediate',
    title: 'Python 051：标准库概览 math / random / heapq',
    summary: '认识常用内置模块及其典型用途。',
    concepts: ['math', 'random', 'heapq'],
    objective: '知道常用模块能做什么并会用最常见函数。',
    prerequisites: ['模块与 import'],
    explain:
        'math 提供数学函数和常量（pi、sqrt、pow、floor、ceil）；random 生成随机数，'
        'seed 后序列可复现；heapq 把列表当小顶堆使用，heappush/heappop 维护优先'
        '队列。注意本运行时的 MicroPython 是这些模块的子集，缺少的函数要避免使用。',
    code:
        'import math\n'
        'import random\n'
        'import heapq\n'
        '\n'
        'print(math.floor(3.7), math.ceil(3.2))\n'
        'print(int(math.pow(2, 8)))\n'
        '\n'
        'random.seed(7)\n'
        'value = random.randint(1, 6)\n'
        'print(1 <= value <= 6)\n'
        '\n'
        'heap = [5, 1, 3]\n'
        'heapq.heapify(heap)\n'
        'heapq.heappush(heap, 2)\n'
        'print(heapq.heappop(heap), heap[0])\n',
    output:
        '3 4\n'
        '256\n'
        'True\n'
        '1 2\n',
    pitfalls: [
      'math.gcd 在本内置运行器中不可用，需自己实现或避免。',
      'random 不设 seed 时结果不可复现；而且本运行器与 CPython 的随机序列不同。',
      'heapq 只保证堆顶最小，其余元素无序。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 random.seed 固定后生成三个 1..100 的整数。',
        hint: 'seed 后循环 randint。',
        answer: 'import random\nrandom.seed(1)\nprint([random.randint(1, 100) for _ in range(3)])',
      ),
    ],
  ),
  PythonTopic(
    id: 52,
    level: 'intermediate',
    title: 'Python 052：综合——迷你待办清单',
    summary: '结合文件、json 和函数做一个可持久化的待办。',
    concepts: ['综合', '文件 + json', '函数拆分'],
    objective: '把文件、json、函数组合成一个可运行的小应用。',
    prerequisites: ['json 进阶——读写配置', '文件读写', '定义函数与返回值'],
    explain:
        '这个小应用把「加载—修改—保存」三步封装成函数，数据用 JSON 文件持久化。'
        'add 添加待办、done 标记完成、save/load 读写文件。虽然简单，但演示了真实'
        '程序的骨架：数据模型 + 操作 + 持久化，且每一步都能单独测试。',
    code:
        'import json\n'
        '\n'
        'def load(path):\n'
        '    try:\n'
        '        with open(path) as f:\n'
        '            return json.load(f)\n'
        '    except Exception:\n'
        '        return []\n'
        '\n'
        'def save(path, todos):\n'
        '    with open(path, "w") as f:\n'
        '        f.write(json.dumps(todos))\n'
        '\n'
        'path = "todos.json"\n'
        'todos = load(path)\n'
        'todos.append({"text": "learn", "done": False})\n'
        'todos.append({"text": "homework", "done": True})\n'
        'save(path, todos)\n'
        '\n'
        'for t in load(path):\n'
        '    mark = "[x]" if t["done"] else "[ ]"\n'
        '    print(mark, t["text"])\n',
    output:
        '[ ] learn\n'
        '[x] homework\n',
    pitfalls: [
      'save 用 w 覆盖整个文件，要确保已把所有待办都写回。',
      'load 失败时返回空列表，掩盖了文件损坏——生产代码要区分「不存在」和「损坏」。',
      '本内置运行器的 json.dumps 不支持 ensure_ascii 关键字。',
    ],
    tasks: [
      PythonTask(
        prompt: '给上面的程序加一个统计「已完成数量」的输出。',
        hint: '用 sum 统计 done 为真的项。',
        answer: 'todos = [{"text": "a", "done": True}, {"text": "b", "done": False}]\nprint(sum(1 for t in todos if t["done"]))',
      ),
    ],
  ),
  PythonTopic(
    id: 53,
    level: 'intermediate',
    title: 'Python 053：类与对象',
    summary: '用 class 定义类型，__init__ 初始化实例。',
    concepts: ['class', '__init__', 'self', '实例'],
    objective: '会定义类、创建对象、读写实例属性。',
    prerequisites: ['定义函数与返回值'],
    explain:
        'class 定义一类对象的模板，__init__ 是构造时调用的初始化方法，self 指代'
        '当前实例（必须作为第一个参数）。实例属性在 __init__ 里用 self.x = ... '
        '创建。创建对象时写 Dog("旺财")，Python 会自动把新对象作为 self 传进去。',
    code:
        'class Dog:\n'
        '    def __init__(self, name, age):\n'
        '        self.name = name\n'
        '        self.age = age\n'
        '\n'
        '    def bark(self):\n'
        '        return f"{self.name} 汪汪叫"\n'
        '\n'
        'd = Dog("旺财", 3)\n'
        'print(d.name, d.age)\n'
        'print(d.bark())\n'
        '\n'
        'd.age = 4\n'
        'print(d.age)\n',
    output:
        '旺财 3\n'
        '旺财 汪汪叫\n'
        '4\n',
    pitfalls: [
      '忘记写 self 参数，调用时参数个数对不上。',
      '在 __init__ 外直接使用未初始化的属性会报 AttributeError。',
      '把 self 当作类名使用，或在方法里漏写 self.。',
    ],
    tasks: [
      PythonTask(
        prompt: '定义一个 Rectangle 类，含宽高和面积方法。',
        hint: '__init__ 存宽高，area 返回乘积。',
        answer: 'class Rectangle:\n    def __init__(self, w, h):\n        self.w = w\n        self.h = h\n    def area(self):\n        return self.w * self.h\nprint(Rectangle(3, 4).area())',
      ),
    ],
  ),
  PythonTopic(
    id: 54,
    level: 'intermediate',
    title: 'Python 054：属性和方法',
    summary: '实例属性、实例方法和类的组织。',
    concepts: ['实例属性', '方法', '对象状态'],
    objective: '通过方法维护对象的内部状态。',
    prerequisites: ['类与对象'],
    explain:
        '对象把数据和操作它的方法绑在一起。方法读写 self 上的属性来维护状态，'
        '外部通过方法而不是直接改属性来表达意图。这样对象的「合法状态」由方法'
        '保证，调用方不必关心内部细节。多个实例各自独立，属性互不影响。',
    code:
        'class Counter:\n'
        '    def __init__(self):\n'
        '        self.value = 0\n'
        '    def inc(self, n=1):\n'
        '        self.value += n\n'
        '    def reset(self):\n'
        '        self.value = 0\n'
        '\n'
        'a = Counter()\n'
        'b = Counter()\n'
        'a.inc()\n'
        'a.inc(5)\n'
        'b.inc(100)\n'
        'print(a.value, b.value)\n'
        'a.reset()\n'
        'print(a.value)\n',
    output:
        '6 100\n'
        '0\n',
    pitfalls: [
      '在方法间共享可变类属性而非实例属性，会让所有实例互相影响。',
      '直接改 self.value 绕过方法校验，破坏封装。',
      '误以为两个实例会共享属性。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 BankAccount 类，支持存款并返回余额。',
        hint: '用 self.balance 维护状态。',
        answer: 'class BankAccount:\n    def __init__(self):\n        self.balance = 0\n    def deposit(self, x):\n        self.balance += x\n        return self.balance\na = BankAccount()\nprint(a.deposit(50))',
      ),
    ],
  ),
  PythonTopic(
    id: 55,
    level: 'intermediate',
    title: 'Python 055：封装与命名约定',
    summary: '用下划线约定区分公开与内部，property 暴露只读。',
    concepts: ['封装', '_约定', 'property'],
    objective: '理解 Python 的封装靠约定而非强制。',
    prerequisites: ['属性和方法'],
    explain:
        'Python 没有真正的私有：以单下划线开头的名字（_x）表示「内部使用」，是'
        '约定而非限制；双下划线会触发名字改写。封装的意义是让调用方只依赖公开'
        '接口。若想暴露「看起来像属性、实际经过计算或校验」的值，可以用 property。',
    code:
        'class Temperature:\n'
        '    def __init__(self, celsius):\n'
        '        self._celsius = celsius\n'
        '\n'
        '    @property\n'
        '    def fahrenheit(self):\n'
        '        return self._celsius * 9 / 5 + 32\n'
        '\n'
        't = Temperature(25)\n'
        'print(t.fahrenheit)\n'
        'print(t._celsius)\n',
    output:
        '77.0\n'
        '25\n',
    pitfalls: [
      '以为 _x 是真正私有，外部仍可访问。',
      '在 property 里再次调用自身造成无限递归。',
      '过度使用下划线让公开接口混乱。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 Temperature 加一个华氏度转摄氏度的 property。',
        hint: '反向公式 (f - 32) * 5 / 9。',
        answer: 'class T:\n    def __init__(self, c):\n        self._c = c\n    @property\n    def f(self):\n        return self._c * 9 / 5 + 32\nprint(T(0).f)',
      ),
    ],
  ),
  PythonTopic(
    id: 56,
    level: 'intermediate',
    title: 'Python 056：@property 计算属性',
    summary: '用 property 做校验和派生值。',
    concepts: ['property', 'getter', '校验'],
    objective: '会用 property 在校验通过后设置属性。',
    prerequisites: ['封装与命名约定'],
    explain:
        '@property 把一个方法变成「读属性」的语法；再配合 @x.setter，可以在赋值时'
        '做校验，非法值直接抛异常。这样外部仍写 obj.x = v，但实际经过你的逻辑。'
        '计算属性适合由其他属性派生的量，避免数据不一致。',
    code:
        'class Circle:\n'
        '    def __init__(self, r):\n'
        '        self.radius = r\n'
        '\n'
        '    @property\n'
        '    def area(self):\n'
        '        return 3.14159 * self.radius ** 2\n'
        '\n'
        '    @property\n'
        '    def radius(self):\n'
        '        return self._r\n'
        '\n'
        '    @radius.setter\n'
        '    def radius(self, value):\n'
        '        if value < 0:\n'
        '            raise ValueError("半径不能为负")\n'
        '        self._r = value\n'
        '\n'
        'c = Circle(2)\n'
        'print(f"{c.area:.2f}")\n'
        'try:\n'
        '    c.radius = -1\n'
        'except ValueError as e:\n'
        '    print(e)\n',
    output:
        '12.57\n'
        '半径不能为负\n',
    pitfalls: [
      'setter 里的属性名和 property 同名会递归，要用不同的内部名（如 _r）。',
      '只定义 getter 会得到只读属性，赋值会报错。',
      '计算属性每次访问都重算，代价大时可缓存。',
    ],
    tasks: [
      PythonTask(
        prompt: '给一个类加 property 校验分数必须在 0..100。',
        hint: '在 setter 里判断范围。',
        answer: 'class S:\n    def __init__(self, v):\n        self.score = v\n    @property\n    def score(self):\n        return self._s\n    @score.setter\n    def score(self, v):\n        if not 0 <= v <= 100:\n            raise ValueError("越界")\n        self._s = v\nprint(S(90).score)',
      ),
    ],
  ),
  PythonTopic(
    id: 57,
    level: 'intermediate',
    title: 'Python 057：继承与 super',
    summary: '子类复用父类，用 super 调用父类方法。',
    concepts: ['继承', 'super()', '方法重写'],
    objective: '会用继承扩展父类并重写方法。',
    prerequisites: ['类与对象'],
    explain:
        '子类 class B(A) 继承 A 的属性和方法，可以重写某个方法改变行为，也可以用 '
        'super() 调用父类版本再补充。继承表达「是一种」的关系（狗是动物）。若关系'
        '是「有一个」，应优先用组合。__init__ 里常用 super().__init__(...) 先完成'
        '父类初始化。',
    code:
        'class Animal:\n'
        '    def __init__(self, name):\n'
        '        self.name = name\n'
        '    def speak(self):\n'
        '        return "..."\n'
        '\n'
        'class Dog(Animal):\n'
        '    def speak(self):\n'
        '        return f"{self.name}: 汪汪"\n'
        '\n'
        'class Puppy(Dog):\n'
        '    def speak(self):\n'
        '        return super().speak() + "（奶声）"\n'
        '\n'
        'for a in [Animal("动物"), Dog("旺财"), Puppy("小狗")]:\n'
        '    print(a.speak())\n',
    output:
        '...\n'
        '旺财: 汪汪\n'
        '小狗: 汪汪（奶声）\n',
    pitfalls: [
      '重写 __init__ 时忘记调用 super().__init__，父类属性未初始化。',
      '继承层次过深会难以维护，优先组合。',
      '父类方法签名改变会波及子类。',
    ],
    tasks: [
      PythonTask(
        prompt: '定义 Shape 基类和 Circle 子类，子类重写 area。',
        hint: '用 super().__init__ 初始化公共属性。',
        answer: 'class Shape:\n    def area(self):\n        return 0\nclass Circle(Shape):\n    def __init__(self, r):\n        self.r = r\n    def area(self):\n        return 3.14 * self.r ** 2\nprint(Circle(1).area())',
      ),
    ],
  ),
  PythonTopic(
    id: 58,
    level: 'intermediate',
    title: 'Python 058：多态',
    summary: '同一接口，不同对象表现不同。',
    concepts: ['多态', '鸭子类型', '统一接口'],
    objective: '理解多态让代码面向接口而非具体类型。',
    prerequisites: ['继承与 super'],
    explain:
        '多态指对不同对象调用同名方法，各对象按自己的方式响应。Python 是鸭子类型：'
        '只要对象有需要的方法就能用，不必共享基类。这让函数可以接受「任何能 speak '
        '的东西」，与具体类型解耦。多态让新增类型时无需修改调用方代码。',
    code:
        'class Cat:\n'
        '    def speak(self):\n'
        '        return "喵"\n'
        '\n'
        'class Dog:\n'
        '    def speak(self):\n'
        '        return "汪"\n'
        '\n'
        'class Robot:\n'
        '    def speak(self):\n'
        '        return "哔"\n'
        '\n'
        'def chorus(animals):\n'
        '    return " ".join(a.speak() for a in animals)\n'
        '\n'
        'print(chorus([Cat(), Dog(), Robot()]))\n',
    output: '喵 汪 哔\n',
    pitfalls: [
      '对象缺少所需方法会报 AttributeError——鸭子类型不检查接口。',
      '把多态和重载混淆：Python 没有传统意义上的函数重载。',
      '为多态强加不必要的继承，鸭子类型下并非必需。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 summarize 函数，对任意含 name 属性、describe 方法的对象工作。',
        hint: '直接调用 obj.describe()。',
        answer: 'def summarize(objs):\n    return [o.describe() for o in objs]\nclass A:\n    def describe(self):\n        return "A"\nprint(summarize([A()]))',
      ),
    ],
  ),
  PythonTopic(
    id: 59,
    level: 'intermediate',
    title: 'Python 059：类方法与静态方法',
    summary: '用 @classmethod 和 @staticmethod 表达不同用途。',
    concepts: ['@classmethod', '@staticmethod', 'cls'],
    objective: '区分实例方法、类方法和静态方法的适用场景。',
    prerequisites: ['类与对象'],
    explain:
        '实例方法第一个参数是 self；@classmethod 第一个参数是 cls，常用于提供'
        '替代构造器（如 from_string）；@staticmethod 不接收 self/cls，只是逻辑上'
        '属于类的工具函数。选对类型能让意图更清楚，也方便调用方。',
    code:
        'class Point:\n'
        '    def __init__(self, x, y):\n'
        '        self.x = x\n'
        '        self.y = y\n'
        '\n'
        '    @classmethod\n'
        '    def origin(cls):\n'
        '        return cls(0, 0)\n'
        '\n'
        '    @staticmethod\n'
        '    def distance(a, b):\n'
        '        return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5\n'
        '\n'
        'p = Point.origin()\n'
        'q = Point(3, 4)\n'
        'print(p.x, p.y)\n'
        'print(Point.distance(p, q))\n',
    output:
        '0 0\n'
        '5.0\n',
    pitfalls: [
      'staticmethod 里用 self 会报 NameError，它没有 self。',
      'classmethod 的替代构造器常用于子类友好，别硬编码类名。',
      '把不依赖类状态的函数放进类里当 staticmethod 只是组织手段，不是必须。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 Point 加一个 from_tuple 的类方法。',
        hint: 'return cls(t[0], t[1])。',
        answer: 'class P:\n    def __init__(self, x, y):\n        self.x = x\n        self.y = y\n    @classmethod\n    def from_tuple(cls, t):\n        return cls(t[0], t[1])\nprint(P.from_tuple((1, 2)).x)',
      ),
    ],
  ),
  PythonTopic(
    id: 60,
    level: 'intermediate',
    title: 'Python 060：魔术方法 __str__ 与 __repr__',
    summary: '控制对象的打印形式。',
    concepts: ['__str__', '__repr__', '打印协议'],
    objective: '会定义 __str__/__repr__ 让对象可读。',
    prerequisites: ['类与对象'],
    explain:
        '__str__ 提供给用户看的字符串（print 用它），__repr__ 提供给开发者看的'
        '精确表示（交互式显示和容器里的元素用它）。约定 __repr__ 应尽量能表达'
        '「如何重建这个对象」。如果只定义 __repr__，print 会退回到它。',
    code:
        'class Money:\n'
        '    def __init__(self, amount, currency="CNY"):\n'
        '        self.amount = amount\n'
        '        self.currency = currency\n'
        '\n'
        '    def __str__(self):\n'
        '        return f"{self.amount} {self.currency}"\n'
        '\n'
        '    def __repr__(self):\n'
        '        return f"Money({self.amount}, {self.currency!r})"\n'
        '\n'
        'm = Money(10)\n'
        'print(m)\n'
        'print([m])\n'
        'print(repr(m))\n',
    output:
        '10 CNY\n'
        '[Money(10, \'CNY\')]\n'
        "Money(10, 'CNY')\n",
    pitfalls: [
      '__str__ 只接受 self，不能有额外参数。',
      '__repr__ 不返回字符串（如返回 None）会报 TypeError。',
      '只定义 __str__ 时列表里显示的是默认地址，可读性差。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 Money 加 __eq__ 让相同金额视为相等。',
        hint: '比较 amount 和 currency。',
        answer: 'class M:\n    def __init__(self, a):\n        self.a = a\n    def __eq__(self, o):\n        return isinstance(o, M) and o.a == self.a\nprint(M(1) == M(1))',
      ),
    ],
  ),
];
