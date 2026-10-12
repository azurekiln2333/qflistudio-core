import 'python_topic.dart';

/// Chapter 1-2: 起步与流程控制 (topics 001-016).
const List<PythonTopic> pythonTopicsBasics = <PythonTopic>[
  PythonTopic(
    id: 1,
    level: 'beginner',
    title: 'Python 001：第一个 Python 程序',
    summary: '用 print 输出文本，认识缩进和字符串。',
    concepts: ['print', '字符串', '缩进'],
    objective: '能写出并运行一个输出文本的最小 Python 程序。',
    prerequisites: ['无（本课程第一课）'],
    explain:
        'Python 用缩进（约定 4 个空格）表示代码块，不用大括号，也不需要 main '
        '函数或分号结尾。print 是一个内置函数，括号里放要显示的对象。字符串用单'
        '引号或双引号都可以，两边配对即可。一行一句是惯例，但 Python 也允许用分号'
        '把多条语句写在一行——不要这么做，可读性会变差。',
    code:
        'print("Hello, Python!")\n'
        'print(\'单引号也可以\')\n'
        'print("第一行\\n第二行")  # \\n 是换行符\n',
    output: 'Hello, Python!\n单引号也可以\n第一行\n第二行\n',
    pitfalls: [
      '把 print 写成 Print 或 pint，Python 区分大小写。',
      '忘记写引号会让 Python 把内容当成变量名，报 NameError。',
      '字符串里的反斜杠 \\n 是换行，想显示它本身要写成 \\\\n。',
    ],
    tasks: [
      PythonTask(
        prompt: '打印三行，分别是你的名字、年龄和所在城市。',
        hint: '写三个 print，每行一个。',
        answer: 'print("小明")\nprint(18)\nprint("杭州")',
      ),
      PythonTask(
        prompt: '用一行 print 输出带换行的两句话。',
        hint: '在字符串里插入 \\n。',
        answer: 'print("你好\\n世界")',
      ),
    ],
  ),
  PythonTopic(
    id: 2,
    level: 'beginner',
    title: 'Python 002：变量与动态类型',
    summary: '赋值创建变量，类型由值决定，可用 type() 查看。',
    concepts: ['变量', '动态类型', 'type()', 'int/float/str/bool'],
    objective: '理解变量是名字绑定到对象，并会查看值的类型。',
    prerequisites: ['第一个 Python 程序'],
    explain:
        'Python 的变量不需要声明类型：一次赋值就同时创建了名字和它指向的对象，'
        '类型属于对象而不属于名字。因此同一个名字可以先指向整数、再指向字符串，'
        '这称为动态类型。type(x) 返回对象所属的类，常用于调试。四种最常见的类型'
        '是 int（整数）、float（小数）、str（字符串）和 bool（True/False）。',
    code:
        'age = 18\n'
        'height = 1.75\n'
        'name = "小明"\n'
        'is_student = True\n'
        '\n'
        'print(age, height, name, is_student)\n'
        'print(type(age), type(height), type(name), type(is_student))\n'
        '\n'
        'age = "十八"  # 同一个名字可以改指向字符串\n'
        'print(age, type(age))\n',
    output:
        "18 1.75 小明 True\n"
        "<class 'int'> <class 'float'> <class 'str'> <class 'bool'>\n"
        "十八 <class 'str'>\n",
    pitfalls: [
      '把名字和类型绑定：类型属于对象，重新赋值就能换类型。',
      '使用未赋值的变量会报 NameError，不是「默认空值」。',
      'True/False 首字母必须大写。',
    ],
    tasks: [
      PythonTask(
        prompt: '把 age 重新赋成字符串，再打印它的类型。',
        hint: '直接重新赋值即可，Python 允许换类型。',
        answer: 'age = "十八"\nprint(type(age))  # <class \'str\'>',
      ),
      PythonTask(
        prompt: '创建两个变量并交换它们的值，打印交换前后的结果。',
        hint: 'Python 可以用 a, b = b, a 一步交换。',
        answer: 'a, b = 1, 2\nprint(a, b)\na, b = b, a\nprint(a, b)',
      ),
    ],
  ),
  PythonTopic(
    id: 3,
    level: 'beginner',
    title: 'Python 003：数值与运算符',
    summary: '算术运算、整除、取余、幂和运算优先级。',
    concepts: ['算术运算符', '整除 //', '取余 %', '幂 **', '优先级'],
    objective: '正确使用整数与小数运算，并区分 / 与 // 的结果。',
    prerequisites: ['变量与动态类型'],
    explain:
        'Python 的除法 / 总是得到浮点数，5 / 2 是 2.5；整除 // 向下取整，5 // 2 '
        '是 2；取余 % 得到余数，5 % 2 是 1，常用于判断奇偶或循环取模。幂用 **，'
        '2 ** 10 是 1024。括号可以改变优先级，不确定时加括号永远比记规则更可靠。'
        '整数和浮点混合运算的结果是浮点数。',
    code:
        'a, b = 17, 5\n'
        'print(a + b, a - b, a * b)\n'
        'print(a / b)     # 真除法，结果是浮点数\n'
        'print(a // b)    # 整除，向下取整\n'
        'print(a % b)     # 取余\n'
        'print(2 ** 10)   # 幂\n'
        'print(a % 2 == 0)\n'
        'print((1 + 2) * 3)  # 括号优先\n',
    output:
        '22 12 85\n'
        '3.4\n'
        '3\n'
        '2\n'
        '1024\n'
        'False\n'
        '9\n',
    pitfalls: [
      '把 / 当整除：5 / 2 是 2.5 而不是 2。',
      '负数整除 // 向下取整，-7 // 2 是 -4 不是 -3。',
      '浮点数有精度误差，0.1 + 0.2 不严格等于 0.3。',
    ],
    tasks: [
      PythonTask(
        prompt: '输入秒数 3661，换算成「时:分:秒」。',
        hint: '用 // 和 % 层层分解。',
        answer: 's = 3661\nh = s // 3600\nm = s % 3600 // 60\nsec = s % 60\nprint(f"{h}:{m}:{sec}")',
      ),
      PythonTask(
        prompt: '判断一个数是奇数还是偶数。',
        hint: '用 n % 2 的结果。',
        answer: 'n = 7\nprint("奇数" if n % 2 else "偶数")',
      ),
    ],
  ),
  PythonTopic(
    id: 4,
    level: 'beginner',
    title: 'Python 004：字符串入门',
    summary: '拼接、索引、切片与长度。',
    concepts: ['拼接', '索引', '切片', 'len()'],
    objective: '能用下标访问字符、用切片取子串。',
    prerequisites: ['变量与动态类型'],
    explain:
        '字符串是不可变序列，可以用下标访问单个字符，下标从 0 开始，-1 表示最后'
        '一个。切片 s[start:stop] 取从 start 到 stop（不含 stop）的子串；省略一端'
        '表示从头或到尾。len(s) 返回字符个数。拼接可以直接用 +，重复用 *。注意：'
        '切片越界不会报错，但单个下标越界会报 IndexError。',
    code:
        's = "Python编程"\n'
        'print(len(s))\n'
        'print(s[0], s[5], s[-1])\n'
        'print(s[0:6])\n'
        'print(s[:6])\n'
        'print(s[6:])\n'
        'print("Py" + "thon")\n'
        'print("ab" * 3)\n',
    output:
        '8\n'
        'P n 程\n'
        'Python\n'
        'Python\n'
        '编程\n'
        'Python\n'
        'ababab\n',
    pitfalls: [
      '下标从 0 开始，s[1] 是第二个字符不是第一个。',
      '切片 s[0:2] 不含下标 2，只有两个字符。',
      '字符串不可变，s[0] = "X" 会报 TypeError。',
    ],
    tasks: [
      PythonTask(
        prompt: '取字符串 "abcdef" 的中间两个字符 "cd"。',
        hint: '用切片 s[2:4]。',
        answer: 's = "abcdef"\nprint(s[2:4])',
      ),
      PythonTask(
        prompt: '把字符串 "hello" 反转成 "olleh"。',
        hint: '内置运行器的字符串不支持步长切片，要先转成列表或改用 reversed："".join(reversed(s))。',
        answer: 's = "hello"\nprint("".join(reversed(s)))  # olleh',
      ),
    ],
  ),
  PythonTopic(
    id: 5,
    level: 'beginner',
    title: 'Python 005：f-string 格式化',
    summary: '用 f-string 把变量和表达式嵌入文本，并控制小数位。',
    concepts: ['f-string', '格式说明符', '对齐'],
    objective: '能用 f-string 生成含变量、表达式和格式控制的字符串。',
    prerequisites: ['字符串入门'],
    explain:
        '在字符串前加 f 就得到 f-string，其中 {} 内可以直接写变量或表达式，运行'
        '时会被求值并替换。格式说明符写在冒号后面：:.2f 保留两位小数，:03d 补零'
        '到三位，:>5 右对齐到宽度 5。f-string 比用 + 拼接更清晰，也不用手动把数字'
        '转成字符串。',
    code:
        'name = "小明"\n'
        'age = 18\n'
        'price = 5.5\n'
        'count = 3\n'
        'print(f"我叫{name}，今年{age}岁")\n'
        'print(f"合计：{price * count} 元")\n'
        'print(f"保留两位：{price * count:.2f}")\n'
        'print(f"编号：{7:03d}")\n'
        'print(f"右对齐：|{age:>5}|")\n',
    output:
        '我叫小明，今年18岁\n'
        '合计：16.5 元\n'
        '保留两位：16.50\n'
        '编号：007\n'
        '右对齐：|   18|\n',
    pitfalls: [
      '忘记字符串前的 f，{} 会被原样打印出来。',
      '在 f-string 里嵌套同种引号要小心 Python 版本，必要时改用外层双引号。',
      ':.2f 会四舍五入，不是截断。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 f-string 打印「商品：苹果，单价 5.5 元，数量 3，合计 16.50 元」。',
        hint: '在 {} 内写表达式并用 :.2f。',
        answer: 'print(f"商品：苹果，单价 5.5 元，数量 3，合计 {5.5 * 3:.2f} 元")',
      ),
      PythonTask(
        prompt: '把 3.14159 打印成保留 3 位小数。',
        hint: '用 :.3f。',
        answer: 'print(f"{3.14159:.3f}")  # 3.142',
      ),
    ],
  ),
  PythonTopic(
    id: 6,
    level: 'beginner',
    title: 'Python 006：布尔值与比较',
    summary: '比较运算、and/or/not 与短路求值。',
    concepts: ['bool', 'and/or/not', '短路'],
    objective: '写出正确的复合条件，并理解短路的作用。',
    prerequisites: ['数值与运算符'],
    explain:
        '比较运算（==、!=、<、<=、>、>=）的结果是布尔值 True 或 False。and 要求'
        '两侧都为真，or 只要一侧为真，not 取反。and 和 or 是短路的：and 左侧为假'
        '就不看右侧，or 左侧为真就不看右侧——这既提高效率，也能防止右侧出错。注意 '
        '== 是判断相等，= 是赋值，别写混。',
    code:
        'age = 20\n'
        'has_ticket = True\n'
        'print(age >= 18 and has_ticket)\n'
        'print(age < 18 or has_ticket)\n'
        'print(not has_ticket)\n'
        '\n'
        'x = 0\n'
        'print(x != 0 and 10 / x > 1)  # 短路：x==0 时不除\n'
        'print(1 < 2 < 3)              # 链式比较\n',
    output:
        'True\n'
        'True\n'
        'False\n'
        'False\n'
        'True\n',
    pitfalls: [
      '用 = 代替 ==，会变成赋值并可能报错。',
      '误以为 and/or 会返回布尔值：它们返回的是参与运算的对象。',
      '依赖短路来避免除零，要考虑清楚左右顺序。',
    ],
    tasks: [
      PythonTask(
        prompt: '判断一年是否为闰年（能被 4 整除且不能被 100 整除，或能被 400 整除）。',
        hint: '用 and/or 组合两个条件。',
        answer: 'y = 2024\nleap = (y % 4 == 0 and y % 100 != 0) or y % 400 == 0\nprint(leap)',
      ),
    ],
  ),
  PythonTopic(
    id: 7,
    level: 'beginner',
    title: 'Python 007：类型转换',
    summary: 'int/float/str 之间的显式转换与隐式提升。',
    concepts: ['int()', 'float()', 'str()', '隐式转换'],
    objective: '能安全地把输入文本转成数字参与计算。',
    prerequisites: ['变量与动态类型'],
    explain:
        'Python 不会自动把字符串 "3" 当成数字 3。要做算术必须先显式转换：int("3") '
        '得到整数，float("1.5") 得到小数，str(3) 得到字符串。数字之间会隐式提升：'
        'int 与 float 运算自动变 float。转换非数字文本会抛 ValueError，所以处理用户'
        '输入时通常要配合异常处理或先校验。',
    code:
        'a = int("10")\n'
        'b = float("2.5")\n'
        'print(a + b)\n'
        'print(str(3) + "元")\n'
        'print(int(3.9))   # 截断小数部分\n'
        'print(round(3.5)) # 四舍五入\n'
        'try:\n'
        '    int("abc")\n'
        'except ValueError:\n'
        '    print("无法转换")\n',
    output:
        '12.5\n'
        '3元\n'
        '3\n'
        '4\n'
        '无法转换\n',
    pitfalls: [
      'int("1.5") 会报 ValueError，因为小数点不是整数字符。',
      'int(3.9) 是截断成 3，不是四舍五入。',
      'round(2.5) 因二进制表示可能得到 2，金融计算别依赖它。',
    ],
    tasks: [
      PythonTask(
        prompt: '把字符串 "3.14" 转成浮点数并乘 2。',
        hint: '用 float()。',
        answer: 'x = float("3.14")\nprint(x * 2)  # 6.28',
      ),
    ],
  ),
  PythonTopic(
    id: 8,
    level: 'beginner',
    title: 'Python 008：读取输入 input()',
    summary: '用 input() 读一行，配合 split 和类型转换。',
    concepts: ['input()', 'split()', '类型转换'],
    objective: '能读取一行输入并把它解析成数字参与运算。',
    prerequisites: ['类型转换'],
    explain:
        'input() 从标准输入读一行并返回字符串（不含行尾换行）。本应用的解释器'
        '「先备好输入再一次性跑完」，所以标准输入写在项目根目录的 input.txt 里。'
        'input() 永远返回字符串，要参与算术必须用 int() 或 float() 转换；读一行多个'
        '数可以用 input().split() 再逐个转换。',
    code:
        'a = int(input())\n'
        'b = int(input())\n'
        'print(a + b)\n'
        'print(a * b)\n',
    output: '22\n85\n',
    input: '17\n5\n',
    pitfalls: [
      '忘记转换类型，a + b 会变成字符串拼接而不是求和。',
      '输入为空或行数不够时 input() 抛 EOFError。',
      'input().split() 得到的是字符串列表，别忘了再转数字。',
    ],
    tasks: [
      PythonTask(
        prompt: '一行读入两个空格分隔的数，输出它们的乘积。',
        hint: 'x, y = map(int, input().split())。',
        answer: 'x, y = map(int, input().split())\nprint(x * y)',
      ),
    ],
  ),
  PythonTopic(
    id: 9,
    level: 'beginner',
    title: 'Python 009：条件分支 if / elif / else',
    summary: '用缩进划分多分支逻辑。',
    concepts: ['if', 'elif', 'else', '缩进'],
    objective: '能写出多分支判断并理解执行顺序。',
    prerequisites: ['布尔值与比较'],
    explain:
        'if 后面的条件为真就执行它的代码块，否则依次尝试 elif，最后落到 else。'
        'Python 用 elif 而不是 else if，每个条件后面要有冒号，下一行缩进。分支按'
        '从上到下的顺序匹配，一旦命中就不再检查后面的条件——所以条件的顺序会影响'
        '结果。',
    code:
        'score = 85\n'
        'if score >= 90:\n'
        '    grade = "优秀"\n'
        'elif score >= 80:\n'
        '    grade = "良好"\n'
        'elif score >= 60:\n'
        '    grade = "及格"\n'
        'else:\n'
        '    grade = "不及格"\n'
        'print(grade)\n',
    output: '良好\n',
    pitfalls: [
      '漏写冒号或缩进不一致，报 IndentationError。',
      '把 elif 写成 else if，Python 不认。',
      '分支顺序颠倒会导致更高等级被吞掉。',
    ],
    tasks: [
      PythonTask(
        prompt: '加入「90 以上优秀、80 以上良好、60 以上及格、其余不及格」。',
        hint: '在优秀和及格之间插入 elif score >= 80。',
        answer: 'if score >= 90:\n    print("优秀")\nelif score >= 80:\n    print("良好")\nelif score >= 60:\n    print("及格")\nelse:\n    print("不及格")',
      ),
    ],
  ),
  PythonTopic(
    id: 10,
    level: 'beginner',
    title: 'Python 010：while 循环',
    summary: '按条件重复执行，直到条件不成立。',
    concepts: ['while', '循环条件', '计数器'],
    objective: '用 while 写出可控次数的循环。',
    prerequisites: ['条件分支'],
    explain:
        'while 在条件为真时反复执行代码块。必须让循环体里的某些东西最终使条件'
        '变为假，否则会死循环。计数器是最常见的模式：进入前初始化，每轮更新，'
        '条件围绕它判断。倒计时循环常用「先判断后执行」的语义。',
    code:
        'n = 5\n'
        'while n > 0:\n'
        '    print(n, end=" ")\n'
        '    n -= 1\n'
        'print("发射！")\n'
        '\n'
        'total = 0\n'
        'i = 1\n'
        'while i <= 100:\n'
        '    total += i\n'
        '    i += 1\n'
        'print(total)\n',
    output: '5 4 3 2 1 发射！\n5050\n',
    pitfalls: [
      '忘记更新计数器导致死循环。',
      'while 条件一开始就为假，循环体一次都不执行——这是正确的语义。',
      '浮点计数器累加可能永不精确等于边界值。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 while 求 1 到 n 的乘积（阶乘）。',
        hint: '从 result = 1 开始，每轮乘上 i。',
        answer: 'n = 5\nresult = 1\ni = 1\nwhile i <= n:\n    result *= i\n    i += 1\nprint(result)',
      ),
    ],
  ),
  PythonTopic(
    id: 11,
    level: 'beginner',
    title: 'Python 011：for 与 range',
    summary: '遍历序列，用 range 生成数列。',
    concepts: ['for', 'range', '遍历'],
    objective: '理解 for 是遍历，range 生成整数序列。',
    prerequisites: ['while 循环'],
    explain:
        'Python 的 for 是「对序列里每个元素执行一次」，不是 C 风格的计数循环。'
        'range(stop) 生成 0..stop-1；range(start, stop) 生成 start..stop-1；'
        'range(start, stop, step) 按步长生成。注意 range 不含 stop。当需要的是'
        '序列本身而非下标时，直接 for x in 序列 更清晰。',
    code:
        'for i in range(5):\n'
        '    print(i, end=" ")\n'
        'print()\n'
        'for i in range(2, 6):\n'
        '    print(i, end=" ")\n'
        'print()\n'
        'for i in range(1, 10, 2):\n'
        '    print(i, end=" ")\n'
        'print()\n'
        'for ch in "abc":\n'
        '    print(ch, end="-")\n'
        'print()\n',
    output: '0 1 2 3 4 \n2 3 4 5 \n1 3 5 7 9 \na-b-c-\n',
    pitfalls: [
      '以为 range(5) 包含 5，其实只到 4。',
      '在遍历列表时修改列表，可能导致跳过元素。',
      'range 的 step 为 0 会报 ValueError。',
    ],
    tasks: [
      PythonTask(
        prompt: '打印 1 到 20 之间所有 3 的倍数。',
        hint: '用 range(3, 21, 3)。',
        answer: 'for i in range(3, 21, 3):\n    print(i, end=" ")',
      ),
    ],
  ),
  PythonTopic(
    id: 12,
    level: 'beginner',
    title: 'Python 012：嵌套循环',
    summary: '两层循环配合 end 参数打印乘法表。',
    concepts: ['嵌套循环', 'end 参数', '外层/内层'],
    objective: '理解嵌套循环的执行次数与打印排版。',
    prerequisites: ['for 与 range'],
    explain:
        '嵌套循环里，外层每走一步，内层都要完整走一遍，所以总执行次数是两层次数'
        '之积。print 默认换行，给 end="" 可以不换行，这样内层多个结果能排在同一行，'
        '外层每轮结束再 print() 换行。九九乘法表的第 i 行有 i 个式子，所以内层范围'
        '随外层变化。',
    code:
        'for i in range(1, 4):\n'
        '    for j in range(1, i + 1):\n'
        '        print(f"{j}x{i}={i * j}", end="\\t")\n'
        '    print()\n',
    output: '1x1=1\t\n1x2=2\t2x2=4\t\n1x3=3\t2x3=6\t3x3=9\t\n',
    pitfalls: [
      '内外层用同一个变量名，互相覆盖导致逻辑错乱。',
      '忘记内层循环后的换行，所有输出挤在一行。',
      '误以为嵌套循环次数是相加，其实是相乘。',
    ],
    tasks: [
      PythonTask(
        prompt: '打印一个 5 行的直角三角形，第 n 行有 n 个星号。',
        hint: 'print("*" * row) 一行就能搞定。',
        answer: 'for row in range(1, 6):\n    print("*" * row)',
      ),
    ],
  ),
  PythonTopic(
    id: 13,
    level: 'beginner',
    title: 'Python 013：break、continue 与循环 else',
    summary: '提前结束、跳过本轮，以及循环正常结束时的 else。',
    concepts: ['break', 'continue', '循环 else'],
    objective: '用 break/continue 控制循环，并理解循环 else 的触发条件。',
    prerequisites: ['for 与 range'],
    explain:
        'break 立刻结束整个循环；continue 跳过本轮剩余部分进入下一轮。for 和 '
        'while 都可以带一个 else 子句：它只在循环「没有被 break 打断」时执行，'
        '适合表达「找遍了都没找到」这种语义。注意 else 不是「循环结束」的同义词。',
    code:
        'for i in range(1, 10):\n'
        '    if i == 5:\n'
        '        break\n'
        '    if i % 2 == 0:\n'
        '        continue\n'
        '    print(i, end=" ")\n'
        'print()\n'
        '\n'
        'for n in [4, 6, 8]:\n'
        '    if n % 2 == 1:\n'
        '        print("找到奇数", n)\n'
        '        break\n'
        'else:\n'
        '    print("没有奇数")\n',
    output: '1 3 \n没有奇数\n',
    pitfalls: [
      '把 else 理解成「循环体结束后总执行」，它其实跳过 break 的情况。',
      '在多层循环里 break 只跳出最内层。',
      'continue 放在更新语句之前可能造成死循环（while 中）。',
    ],
    tasks: [
      PythonTask(
        prompt: '在 1..20 中找第一个能被 7 整除的数，找不到就提示。',
        hint: '用 for + break + else。',
        answer: 'for n in range(1, 21):\n    if n % 7 == 0:\n        print(n)\n        break\nelse:\n    print("没找到")',
      ),
    ],
  ),
  PythonTopic(
    id: 14,
    level: 'beginner',
    title: 'Python 014：循环模式——累加、计数、最值',
    summary: '用累加器、计数器和极值变量处理一组数据。',
    concepts: ['累加器', '计数器', '极值', '哨兵'],
    objective: '掌握遍历中维护状态变量的通用模式。',
    prerequisites: ['for 与 range'],
    explain:
        '遍历数据时经常要边看边维护状态：求和的累加器初始为 0，计数的计数器初始'
        '为 0，求最大/最小值的变量初始为第一个元素（不能随便设 0，否则遇到全负数'
        '会出错）。这些「初始值 + 每轮更新」的模式是很多算法的骨架。',
    code:
        'nums = [88, 92, 79, 95, 67]\n'
        'total = 0\n'
        'count = 0\n'
        'largest = nums[0]\n'
        'smallest = nums[0]\n'
        'for n in nums:\n'
        '    total += n\n'
        '    count += 1\n'
        '    if n > largest:\n'
        '        largest = n\n'
        '    if n < smallest:\n'
        '        smallest = n\n'
        'print(f"总分 {total}，个数 {count}，平均 {total / count:.1f}")\n'
        'print(f"最高 {largest}，最低 {smallest}")\n',
    output: '总分 421，个数 5，平均 84.2\n最高 95，最低 67\n',
    pitfalls: [
      '把极值初始为 0，遇到全负数列表会得出错误的 0。',
      '平均时忘记用浮点除法，得到截断的整数。',
      '空列表时 nums[0] 会报 IndexError。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计一组分数里及格（>=60）的人数。',
        hint: '用计数器 + if。',
        answer: 'scores = [55, 90, 72, 40]\npass_count = 0\nfor s in scores:\n    if s >= 60:\n        pass_count += 1\nprint(pass_count)',
      ),
    ],
  ),
  PythonTopic(
    id: 15,
    level: 'beginner',
    title: 'Python 015：综合练习——数字金字塔与图形',
    summary: '用循环和字符串乘法画图形。',
    concepts: ['字符串乘法', '居中', '嵌套循环'],
    objective: '把循环和字符串操作组合起来输出规则图形。',
    prerequisites: ['嵌套循环'],
    explain:
        '字符串 * n 得到重复，配合空格就能排版。要画居中的金字塔，需要计算每行'
        '前面补多少空格。把「每行由前导空格 + 星号」拆开思考，比直接硬编码容易。'
        '这类练习能训练「用循环描述规律」的能力。',
    code:
        'rows = 4\n'
        'for i in range(1, rows + 1):\n'
        '    print(" " * (rows - i) + "*" * (2 * i - 1))\n'
        'print("---")\n'
        'for i in range(rows, 0, -1):\n'
        '    print("*" * i)\n',
    output:
        '   *\n'
        '  ***\n'
        ' *****\n'
        '*******\n'
        '---\n'
        '****\n'
        '***\n'
        '**\n'
        '*\n',
    pitfalls: [
      '空格数量算错导致图形歪斜。',
      '星号数量用 i 而不是 2*i-1，画不出等腰效果。',
      '忘了换行，图形连成一条线。',
    ],
    tasks: [
      PythonTask(
        prompt: '打印一个 n 行的倒置三角形（第 1 行 n 个星号）。',
        hint: '用 range(n, 0, -1)。',
        answer: 'n = 4\nfor i in range(n, 0, -1):\n    print("*" * i)',
      ),
    ],
  ),
  PythonTopic(
    id: 16,
    level: 'beginner',
    title: 'Python 016：综合练习——猜数字（确定性版）',
    summary: '用 random.seed 得到可复现的随机数，配合循环与分支。',
    concepts: ['random', 'seed', '循环 + 分支'],
    objective: '把随机、循环和条件组合成一个可复现的小游戏。',
    prerequisites: ['while 循环', '条件分支'],
    explain:
        'random 模块生成随机数，但 random.seed(x) 能让序列可复现——同一 seed 得到'
        '同一串随机数，这对教学和测试很重要（否则每次输出都不同）。这个小游戏在'
        '有限次数内猜目标数，用 while + if + break 控制流程。',
    code:
        'import random\n'
        '\n'
        'random.seed(42)\n'
        'target = random.randint(1, 100)\n'
        'guesses = [50, 75, 88, 90]\n'
        'for i, g in enumerate(guesses, 1):\n'
        '    if g == target:\n'
        '        print(f"第 {i} 次猜中：{g}")\n'
        '        break\n'
        '    hint = "太大" if g > target else "太小"\n'
        '    print(f"第 {i} 次 {g}：{hint}")\n'
        'else:\n'
        '    print("没猜中")\n',
    output:
        '第 1 次 50：太大\n'
        '第 2 次 75：太大\n'
        '第 3 次 88：太大\n'
        '第 4 次 90：太大\n'
        '没猜中\n',
    pitfalls: [
      '不设 seed 会让输出每次不同，不利于对照答案。',
      'randint(a, b) 两端都包含，和 range 的半开区间不同。',
      '本内置运行器的随机数算法与 CPython 不同：同样的 seed 得到不同的序列，所以这里不写死具体目标值。',
    ],
    tasks: [
      PythonTask(
        prompt: '改成先猜中再停，并统计用了多少次。',
        hint: '用 while True + break + 计数变量。',
        answer: 'import random\nrandom.seed(1)\ntarget = random.randint(1, 100)\ncount = 0\nwhile True:\n    count += 1\n    g = random.randint(1, 100)\n    if g == target:\n        print(count)\n        break',
      ),
    ],
  ),
];
