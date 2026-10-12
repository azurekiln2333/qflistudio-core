import 'python_topic.dart';

/// Chapter 3-4: 容器与函数 (topics 017-040).
const List<PythonTopic> pythonTopicsContainersFunctions = <PythonTopic>[
  PythonTopic(
    id: 17,
    level: 'beginner',
    title: 'Python 017：列表基础',
    summary: '创建列表、下标访问、切片和长度。',
    concepts: ['list', '下标', '切片', 'len()'],
    objective: '能创建列表并按下标/切片读写和取子列表。',
    prerequisites: ['字符串入门'],
    explain:
        '列表用 [] 创建，可以装不同类型的元素，元素有顺序、可修改。下标从 0 开始，'
        '-1 是最后一个；切片 list[start:stop] 返回新列表（不含 stop）。列表支持 '
        'len()。与字符串不同，列表是可变对象：可以通过下标赋值修改元素。',
    code:
        'fruits = ["apple", "banana", "orange"]\n'
        'print(fruits)\n'
        'print(fruits[0], fruits[-1])\n'
        'print(fruits[1:])\n'
        'print(len(fruits))\n'
        'fruits[1] = "grape"\n'
        'print(fruits)\n'
        'nums = [3, 1, 4, 1, 5]\n'
        'print(sum(nums), max(nums), min(nums))\n',
    output:
        "['apple', 'banana', 'orange']\n"
        'apple orange\n'
        "['banana', 'orange']\n"
        '3\n'
        "['apple', 'grape', 'orange']\n"
        '14 5 1\n',
    pitfalls: [
      '切片 fruit[1:2] 只含一个元素，stop 不包含。',
      '下标越界报 IndexError，访问前要确认长度。',
      '把列表赋值给另一个名字不会复制，两者指向同一对象。',
      '本运行时 repr/print 会把非 ASCII（中文）转义成 \\uXXXX，故示例列表用英文以免干扰。',
    ],
    tasks: [
      PythonTask(
        prompt: '把列表倒序打印出来（不修改原列表）。',
        hint: '用切片 fruits[::-1]。',
        answer: 'fruits = [1, 2, 3]\nprint(fruits[::-1])',
      ),
    ],
  ),
  PythonTopic(
    id: 18,
    level: 'beginner',
    title: 'Python 018：列表方法与原地修改',
    summary: 'append、insert、remove、pop、sort 等常用操作。',
    concepts: ['append', 'insert', 'remove', 'pop', 'sort'],
    objective: '区分会修改原列表的方法和返回新列表的函数。',
    prerequisites: ['列表基础'],
    explain:
        '列表方法大多「原地修改」并返回 None，例如 append、insert、remove、pop、'
        'sort。这意味着 x = lst.append(1) 会把 x 变成 None——这是常见错误。要得到'
        '新列表用 sorted(lst) 或切片。pop() 默认弹出最后一个，pop(i) 按下标弹出并'
        '返回被删元素。',
    code:
        'nums = [3, 1, 4]\n'
        'nums.append(1)\n'
        'print(nums)\n'
        'nums.insert(0, 9)\n'
        'print(nums)\n'
        'removed = nums.pop()\n'
        'print(nums, removed)\n'
        'nums.remove(1)\n'
        'print(nums)\n'
        'nums.sort()\n'
        'print(nums)\n'
        'other = sorted([3, 1, 2])\n'
        'print(other)\n',
    output:
        '[3, 1, 4, 1]\n'
        '[9, 3, 1, 4, 1]\n'
        '[9, 3, 1, 4] 1\n'
        '[9, 3, 4]\n'
        '[3, 4, 9]\n'
        '[1, 2, 3]\n',
    pitfalls: [
      'nums = nums.append(x) 得到 None，因为 append 返回 None。',
      'remove 按值删除，值不存在时报 ValueError。',
      'sort() 就地排序返回 None，sorted() 返回新列表。',
    ],
    tasks: [
      PythonTask(
        prompt: '向列表插入元素并保持有序，再删除指定值。',
        hint: 'append 后 sort，或先 insert 到正确位置。',
        answer: 'a = [1, 3, 5]\na.append(4)\na.sort()\nprint(a)\na.remove(3)\nprint(a)',
      ),
    ],
  ),
  PythonTopic(
    id: 19,
    level: 'beginner',
    title: 'Python 019：列表推导式',
    summary: '用一行表达式生成新列表，支持条件过滤。',
    concepts: ['列表推导式', '条件过滤', '表达式'],
    objective: '能用推导式替代简单的 for + append。',
    prerequisites: ['列表方法与原地修改'],
    explain:
        '列表推导式 [表达式 for 变量 in 序列 if 条件] 会遍历序列，对满足条件的项'
        '求值并收集成新列表。它比「先建空列表再 for + append」更短、更符合 Python '
        '习惯，但嵌套过深会难懂——超过一层 for 或复杂条件时应改回普通循环。推导式'
        '产生的是新列表，不影响原数据。',
    code:
        'nums = [1, 2, 3, 4, 5, 6]\n'
        'squares = [n * n for n in nums]\n'
        'print(squares)\n'
        'evens = [n for n in nums if n % 2 == 0]\n'
        'print(evens)\n'
        'labels = [f"R{i}" for i in range(1, 4)]\n'
        'print(labels)\n'
        'pairs = [(x, y) for x in range(2) for y in range(2)]\n'
        'print(pairs)\n',
    output:
        '[1, 4, 9, 16, 25, 36]\n'
        '[2, 4, 6]\n'
        "['R1', 'R2', 'R3']\n"
        '[(0, 0), (0, 1), (1, 0), (1, 1)]\n',
    pitfalls: [
      '把推导式当成万能：层级太深应改普通循环，可读性优先。',
      '在推导式里做有副作用的操作（如 print）使意图不清。',
      '平方写法 n*n 和 n**2 都行，但别误写成 n^2（那是异或）。',
    ],
    tasks: [
      PythonTask(
        prompt: '用推导式取出字符串列表中长度大于 3 的项。',
        hint: '在 if 里用 len(w) > 3。',
        answer: 'words = ["a", "hello", "hi", "world"]\nprint([w for w in words if len(w) > 3])',
      ),
    ],
  ),
  PythonTopic(
    id: 20,
    level: 'beginner',
    title: 'Python 020：元组与解包',
    summary: '不可变序列、元组解包和交换变量。',
    concepts: ['tuple', '解包', '不可变'],
    objective: '理解元组不可变，并会用解包批量赋值。',
    prerequisites: ['列表基础'],
    explain:
        '元组用圆括号 (a, b) 创建，是不可变序列：创建后不能修改元素。元组适合表示'
        '「一组固定搭配」的值，比如坐标、记录。解包 x, y = (1, 2) 能把元组拆到多个'
        '变量；配合 * 还能收集中间元素。函数返回多个值其实就是返回一个元组。',
    code:
        'point = (3, 5)\n'
        'x, y = point\n'
        'print(x, y)\n'
        'a, b = 1, 2\n'
        'a, b = b, a\n'
        'print(a, b)\n'
        'first, *rest = [1, 2, 3, 4]\n'
        'print(first, rest)\n'
        'single = (42,)\n'
        'print(type(single), len(single))\n',
    output:
        '3 5\n'
        '2 1\n'
        '1 [2, 3, 4]\n'
        "<class 'tuple'> 1\n",
    pitfalls: [
      '创建单元素元组必须写 (42,)；写 (42) 只是加了括号的整数。',
      '元组不可变，t[0] = 1 会报 TypeError。',
      '解包时变量个数必须和元素个数一致（除非用 *）。',
    ],
    tasks: [
      PythonTask(
        prompt: '用元组解包一次性给三个变量赋值。',
        hint: 'a, b, c = (1, 2, 3)。',
        answer: 'a, b, c = (1, 2, 3)\nprint(a, b, c)',
      ),
    ],
  ),
  PythonTopic(
    id: 21,
    level: 'beginner',
    title: 'Python 021：字典基础',
    summary: '用键值对存储数据，get 取默认值。',
    concepts: ['dict', '键值对', 'get()', 'items()'],
    objective: '能创建字典、按键取值、遍历键值对。',
    prerequisites: ['列表基础'],
    explain:
        '字典 dict 存「键 → 值」的映射，用 d[key] 取值，键通常是字符串或数字且唯一。'
        '取不存在的键会报 KeyError；用 d.get(key, default) 可以给默认值而不报错。'
        '遍历用 d.items() 同时拿到键和值，d.keys()/d.values() 只拿一边。字典从 '
        'Python 3.7 起保持插入顺序。',
    code:
        'student = {"name": "Ming", "age": 18, "score": 88}\n'
        'print(student["name"])\n'
        'print(student.get("city", "N/A"))\n'
        'student["age"] = 19\n'
        'student["city"] = "Hangzhou"\n'
        'print(len(student), "city" in student)\n'
        'for key in sorted(student):\n'
        '    print(f"{key}={student[key]}")\n',
    output:
        'Ming\n'
        'N/A\n'
        '4 True\n'
        'age=19\n'
        'city=Hangzhou\n'
        'name=Ming\n'
        'score=88\n',
    pitfalls: [
      '用 [] 取不存在的键报 KeyError，不确定时用 get。',
      '键必须可哈希，列表不能当键。',
      '本运行时字典不是插入序：需要稳定顺序时先 sorted(d)。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计一句话里每个字出现的次数。',
        hint: '用 counts[ch] = counts.get(ch, 0) + 1。',
        answer: 'text = "你好世界你好"\ncounts = {}\nfor ch in text:\n    counts[ch] = counts.get(ch, 0) + 1\nprint(counts)',
      ),
    ],
  ),
  PythonTopic(
    id: 22,
    level: 'beginner',
    title: 'Python 022：字典进阶——计数与分组',
    summary: '用 get/setdefault 模式统计与按规则分组。',
    concepts: ['计数', '分组', 'setdefault'],
    objective: '掌握字典累加计数与按字段分组的常见模式。',
    prerequisites: ['字典基础'],
    explain:
        '计数模式 counts[k] = counts.get(k, 0) + 1 是字典最常用的套路。分组模式则是'
        '把满足同一条件的元素收集到同一个列表：groups.setdefault(key, []).append(x)。'
        'setdefault 在键不存在时先放入默认值再返回它，省去一次 if 判断。这些模式在'
        '数据统计里反复出现。',
    code:
        'words = ["apple", "banana", "avocado", "blueberry", "cherry"]\n'
        'by_first = {}\n'
        'for w in words:\n'
        '    by_first.setdefault(w[0], []).append(w)\n'
        'for key in sorted(by_first):\n'
        '    print(key, by_first[key])\n'
        '\n'
        'text = "aabbc"\n'
        'counts = {}\n'
        'for ch in text:\n'
        '    counts[ch] = counts.get(ch, 0) + 1\n'
        'print(sorted(counts.items()))\n',
    output:
        "a ['apple', 'avocado']\n"
        "b ['banana', 'blueberry']\n"
        "c ['cherry']\n"
        "[('a', 2), ('b', 2), ('c', 1)]\n",
    pitfalls: [
      '忘记初始化就 counts[ch] += 1，键不存在会报 KeyError。',
      'setdefault 每次都会求值默认参数，代价大时改用 if 判断。',
      '直接修改遍历中的字典会报 RuntimeError。',
    ],
    tasks: [
      PythonTask(
        prompt: '按成绩等级把学生名字分组。',
        hint: '用 setdefault(level, []).append(name)。',
        answer: 'data = [("A", "小明"), ("B", "小红"), ("A", "小刚")]\ngroups = {}\nfor level, name in data:\n    groups.setdefault(level, []).append(name)\nprint(groups)',
      ),
    ],
  ),
  PythonTopic(
    id: 23,
    level: 'beginner',
    title: 'Python 023：集合 set',
    summary: '去重、成员判断和交并差运算。',
    concepts: ['set', '去重', '交集', '并集', '差集'],
    objective: '用集合去重并做集合运算。',
    prerequisites: ['列表基础'],
    explain:
        '集合 set 是一组无序、不重复的元素，用 {} 或 set() 创建（空集合必须用 '
        'set()，因为 {} 是空字典）。集合的成员判断很快。集合运算：& 交集、| 并集、'
        '- 差集、^ 对称差。要把列表去重，转成 set 再转回来是最直接的方式。',
    code:
        'a = {1, 2, 3, 4}\n'
        'b = {3, 4, 5, 6}\n'
        'print(sorted(a & b))\n'
        'print(sorted(a | b))\n'
        'print(sorted(a - b))\n'
        'print(sorted(a ^ b))\n'
        'nums = [1, 1, 2, 3, 3, 3]\n'
        'unique = set(nums)\n'
        'print(sorted(unique))\n'
        'print(2 in a, 9 in a)\n',
    output:
        '[3, 4]\n'
        '[1, 2, 3, 4, 5, 6]\n'
        '[1, 2]\n'
        '[1, 2, 5, 6]\n'
        '[1, 2, 3]\n'
        'True False\n',
    pitfalls: [
      '空集合写成 {} 会得到空字典，要用 set()。',
      '集合无序，不要依赖元素的打印顺序。',
      '集合元素必须可哈希，不能放列表。',
    ],
    tasks: [
      PythonTask(
        prompt: '找出两个列表的共同元素。',
        hint: '转成 set 后取交集。',
        answer: 'a = [1, 2, 3]\nb = [2, 3, 4]\nprint(set(a) & set(b))',
      ),
    ],
  ),
  PythonTopic(
    id: 24,
    level: 'beginner',
    title: 'Python 024：字符串进阶——split/join/strip',
    summary: '文本切分、合并和去除空白。',
    concepts: ['split', 'join', 'strip', 'replace'],
    objective: '会用 split/join/strip 处理文本。',
    prerequisites: ['字符串入门'],
    explain:
        '"a,b,c".split(",") 按分隔符切成列表；不传参数则按任意空白切分。"-".join(list) '
        '把字符串列表合并成一个字符串，是 split 的逆操作。strip() 去掉两端空白，'
        'lstrip/rstrip 只去一侧；replace 做替换。处理用户输入时先 strip 再判断是否'
        '为空。',
    code:
        'line = "  apple,banana , cherry "\n'
        'parts = line.strip().split(",")\n'
        'print(parts)\n'
        'cleaned = [p.strip() for p in parts]\n'
        'print(cleaned)\n'
        'print("-".join(cleaned))\n'
        'print("a b  c".split())\n'
        'print("hello".replace("l", "L"))\n',
    output:
        "['apple', 'banana ', ' cherry']\n"
        "['apple', 'banana', 'cherry']\n"
        'apple-banana-cherry\n'
        "['a', 'b', 'c']\n"
        'heLLo\n',
    pitfalls: [
      'split(",") 不会自动去空格，切完通常还要 strip。',
      'join 的调用者是分隔符，不是列表：要写 sep.join(list)。',
      'split() 无参数和 split(" ") 不同，后者保留空串。',
    ],
    tasks: [
      PythonTask(
        prompt: '把一行逗号分隔的分数解析成整数列表并求和。',
        hint: 'split 后用 int 转换求和。',
        answer: 'line = "80, 90, 100"\nnums = [int(x) for x in line.split(",")]\nprint(sum(nums))',
      ),
    ],
  ),
  PythonTopic(
    id: 25,
    level: 'beginner',
    title: 'Python 025：排序与 key 函数',
    summary: '用 sorted 的 key 参数按自定义规则排序。',
    concepts: ['sorted', 'key', 'reverse'],
    objective: '会按长度、字段等自定义规则排序。',
    prerequisites: ['列表方法与原地修改'],
    explain:
        'sorted(iterable, key=..., reverse=...) 返回新列表，list.sort 就地排序。key '
        '接收一个函数，排序时用它的返回值作为比较依据，例如 key=len 按长度、'
        'key=lambda x: x[1] 按第二个字段。稳定排序保证相等元素的相对顺序不变。多个'
        '排序键可用元组：先按第一个、相同再按第二个。',
    code:
        'words = ["banana", "kiwi", "apple", "fig"]\n'
        'print(sorted(words))\n'
        'print(sorted(words, key=len))\n'
        'print(sorted(words, key=len, reverse=True))\n'
        'people = [("Ming", 18), ("Hong", 15), ("Gang", 18)]\n'
        'print(sorted(people, key=lambda p: (p[1], p[0])))\n'
        'nums = [3, 1, 2]\n'
        'nums.sort()\n'
        'print(nums)\n',
    output:
        "['apple', 'banana', 'fig', 'kiwi']\n"
        "['fig', 'kiwi', 'apple', 'banana']\n"
        "['banana', 'apple', 'kiwi', 'fig']\n"
        "[('Hong', 15), ('Gang', 18), ('Ming', 18)]\n"
        '[1, 2, 3]\n',
    pitfalls: [
      'key 要传函数本身（key=len），不要写成 key=len()。',
      '按多字段排序用元组 key，不要写多次 sort 又搞混。',
      'sort 就地修改返回 None，别写成 x = list.sort()。',
    ],
    tasks: [
      PythonTask(
        prompt: '按字符串长度降序排列一组单词。',
        hint: 'sorted(words, key=len, reverse=True)。',
        answer: 'words = ["a", "ccc", "bb"]\nprint(sorted(words, key=len, reverse=True))',
      ),
    ],
  ),
  PythonTopic(
    id: 26,
    level: 'beginner',
    title: 'Python 026：enumerate 与 zip',
    summary: '带下标遍历，以及并行遍历多个序列。',
    concepts: ['enumerate', 'zip'],
    objective: '用 enumerate 取序号、用 zip 并行遍历。',
    prerequisites: ['for 与 range'],
    explain:
        'enumerate(seq, start=1) 在遍历时同时给出下标和元素，比自己维护计数器更'
        '清晰。zip(a, b) 把多个序列按位置配对，遍历长度以最短的为准。要同时拿到'
        '序号和配对可以用 enumerate(zip(...))。这两个工具能消除大量手工下标。',
    code:
        'fruits = ["apple", "banana", "orange"]\n'
        'for i, fruit in enumerate(fruits, 1):\n'
        '    print(f"{i}. {fruit}")\n'
        '\n'
        'names = ["Ming", "Hong"]\n'
        'scores = [90, 85]\n'
        'for name, score in zip(names, scores):\n'
        '    print(f"{name}: {score}")\n'
        '\n'
        'print(list(zip([1, 2, 3], "abc")))\n',
    output:
        '1. apple\n'
        '2. banana\n'
        '3. orange\n'
        'Ming: 90\n'
        'Hong: 85\n'
        '[(1, \'a\'), (2, \'b\'), (3, \'c\')]\n',
    pitfalls: [
      'zip 长度不等时按最短截断，多余元素被忽略。',
      '想遍历下标又改列表要注意索引失效。',
      'enumerate 默认从 0 开始，需要从 1 起要传 start=1。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 enumerate 打印列表中偶数元素的下标。',
        hint: '在循环里判断元素值。',
        answer: 'nums = [3, 4, 7, 8]\nfor i, n in enumerate(nums):\n    if n % 2 == 0:\n        print(i)',
      ),
    ],
  ),
  PythonTopic(
    id: 27,
    level: 'beginner',
    title: 'Python 027：切片进阶',
    summary: '步长、负索引和复制语义。',
    concepts: ['步长', '负索引', '复制'],
    objective: '用步长切片做反转、取隔项，并理解切片会复制。',
    prerequisites: ['列表基础'],
    explain:
        '切片完整形式 s[start:stop:step]。step 为负可以反向取，nums[::-1] 是最常见的'
        '反转写法。切片总是返回新对象，所以 b = a[:] 得到一个浅拷贝，修改 b 不影响 '
        'a。注意两点：一是「浅」拷贝（元素本身是列表时内外层仍共享）；二是本内置'
        '运行器只支持**列表/序列对象的步长切片**，字符串的步长切片会抛 '
        'NotImplementedError，所以反转字符串要用 "".join(reversed(s)) 或先 list(s)。',
    code:
        'nums = [0, 1, 2, 3, 4, 5]\n'
        'print(nums[1:4])\n'
        'print(nums[::2])\n'
        'print(nums[::-1])\n'
        'print(nums[-2:])\n'
        'copy = nums[:]\n'
        'copy[0] = 99\n'
        'print(nums[0], copy[0])\n'
        'print("".join(reversed("abc")))\n',
    output:
        '[1, 2, 3]\n'
        '[0, 2, 4]\n'
        '[5, 4, 3, 2, 1, 0]\n'
        '[4, 5]\n'
        '0 99\n'
        'cba\n',
    pitfalls: [
      '切片不会报越界错误，s[10:20] 返回空。',
      'b = a 不是复制而是别名，要复制用 a[:] 或 list(a)。',
      '本内置运行器的字符串不支持步长切片："hello"[::-1] 会抛 NotImplementedError，反转字符串改用 "".join(reversed(s))。',
    ],
    tasks: [
      PythonTask(
        prompt: '取列表的奇数位元素（下标 1、3、5...）。',
        hint: '用切片 s[1::2]。',
        answer: 's = [0, 1, 2, 3, 4, 5]\nprint(s[1::2])',
      ),
    ],
  ),
  PythonTopic(
    id: 28,
    level: 'beginner',
    title: 'Python 028：综合——词频统计',
    summary: '把字典、循环和排序组合起来做文本统计。',
    concepts: ['词频', 'dict', 'sorted', 'split'],
    objective: '综合运用容器与排序完成一次词频统计。',
    prerequisites: ['字典进阶——计数与分组', '排序与 key 函数'],
    explain:
        '词频统计的典型步骤：切词、转小写、逐词计数、按次数排序输出。排序键用 '
        'lambda 取 (次数, 单词)，再配合 reverse 得到「次数多在前、同次数按字母」。'
        '这是把前面学的容器、循环、排序串起来的综合练习。',
    code:
        'text = "the cat the dog the bird cat"\n'
        'counts = {}\n'
        'for word in text.split():\n'
        '    counts[word] = counts.get(word, 0) + 1\n'
        'ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))\n'
        'for word, n in ranked:\n'
        '    print(f"{word}: {n}")\n',
    output: 'the: 3\ncat: 2\nbird: 1\ndog: 1\n',
    pitfalls: [
      '不做大小写归一，The 和 the 会被当成不同词。',
      '排序键写死 kv[1] 时无法稳定处理同频词，建议用元组。',
      '标点若不清理会混进词里。',
    ],
    tasks: [
      PythonTask(
        prompt: '只输出出现次数最多的一個单词。',
        hint: '用 max(counts, key=counts.get)。',
        answer: 'text = "a b a c a b"\ncounts = {}\nfor w in text.split():\n    counts[w] = counts.get(w, 0) + 1\nprint(max(counts, key=counts.get))',
      ),
    ],
  ),
  PythonTopic(
    id: 29,
    level: 'beginner',
    title: 'Python 029：定义函数与返回值',
    summary: '用 def 封装逻辑，return 交回结果。',
    concepts: ['def', 'return', 'None'],
    objective: '能定义带参数和返回值的函数并调用。',
    prerequisites: ['for 与 range'],
    explain:
        'def 定义函数，函数体缩进。return 交回结果并结束函数；没有 return（或只写 '
        'return）时函数返回 None。把重复逻辑抽成函数能减少复制、方便测试。函数名'
        '用小写加下划线，参数名要有意义。',
    code:
        'def add(a, b):\n'
        '    return a + b\n'
        '\n'
        'def greet(name):\n'
        '    print(f"你好，{name}")\n'
        '\n'
        'def no_return():\n'
        '    x = 1\n'
        '\n'
        'print(add(3, 4))\n'
        'greet("小明")\n'
        'print(no_return())\n',
    output:
        '7\n'
        '你好，小明\n'
        'None\n',
    pitfalls: [
      '忘记 return 会得到 None，而不是最后一个表达式的值。',
      'print 和 return 不同：print 只显示，return 把值交回调用方。',
      '函数体缩进不一致会报 IndentationError。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个函数求矩形面积。',
        hint: 'def area(w, h): return w * h。',
        answer: 'def area(w, h):\n    return w * h\nprint(area(3, 4))',
      ),
    ],
  ),
  PythonTopic(
    id: 30,
    level: 'beginner',
    title: 'Python 030：参数——默认值与关键字',
    summary: '默认参数、关键字实参和可读性调用。',
    concepts: ['默认参数', '关键字实参'],
    objective: '会定义带默认值的参数并用关键字调用。',
    prerequisites: ['定义函数与返回值'],
    explain:
        '参数可以给默认值，调用时省略就用默认值。调用时可以写「参数名=值」用关键字'
        '传参，顺序随意且更易读。默认参数只在定义时求值一次，所以不要用可变对象'
        '（如 []）做默认值——那会在多次调用间共享同一个列表。',
    code:
        'def greet(name, greeting="你好"):\n'
        '    return f"{greeting}，{name}！"\n'
        '\n'
        'def power(base, exp=2):\n'
        '    return base ** exp\n'
        '\n'
        'print(greet("小明"))\n'
        'print(greet("小红", "早上好"))\n'
        'print(greet(greeting="晚上好", name="小刚"))\n'
        'print(power(3))\n'
        'print(power(2, 10))\n',
    output:
        '你好，小明！\n'
        '早上好，小红！\n'
        '晚上好，小刚！\n'
        '9\n'
        '1024\n',
    pitfalls: [
      '用可变对象做默认值（def f(x=[])）会在调用间共享状态。',
      '默认参数之后不能再跟没有默认值的参数。',
      '关键字实参的名字必须和形参一致。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个带默认税率 0.1 的算价函数。',
        hint: 'def price(x, rate=0.1): return x * (1 + rate)。',
        answer: 'def price(x, rate=0.1):\n    return x * (1 + rate)\nprint(price(100))\nprint(price(100, 0.2))',
      ),
    ],
  ),
  PythonTopic(
    id: 31,
    level: 'beginner',
    title: 'Python 031：可变参数 *args 与 **kwargs',
    summary: '收集任意数量的位置参数和关键字参数。',
    concepts: ['*args', '**kwargs', '打包', '解包'],
    objective: '会用 *args/**kwargs 写通用函数。',
    prerequisites: ['参数——默认值与关键字'],
    explain:
        '*args 把多余的位置参数收成一个元组，**kwargs 把多余的关键字参数收成字典。'
        '反过来，调用时 f(*seq) 把序列展开成位置参数，f(**d) 把字典展开成关键字'
        '参数。它们是「转发参数」的标准手段，让包装函数不必写死参数列表。',
    code:
        'def total(*nums):\n'
        '    return sum(nums)\n'
        '\n'
        'def show(**info):\n'
        '    for k, v in info.items():\n'
        '        print(f"{k}={v}")\n'
        '\n'
        'print(total(1, 2, 3, 4))\n'
        'show(name="小明", age=18)\n'
        'args = [1, 2, 3]\n'
        'print(total(*args))\n',
    output:
        '10\n'
        'name=小明\n'
        'age=18\n'
        '6\n',
    pitfalls: [
      '*args 是元组不是列表，需要列表要显式 list()。',
      '参数顺序固定：普通参数、*args、普通关键字参数、**kwargs。',
      '把已定义的变量名和 **kwargs 的键同名可能覆盖，注意命名冲突。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个函数接受任意个数字并返回最大值。',
        hint: 'return max(nums) 或处理空情况。',
        answer: 'def biggest(*nums):\n    return max(nums)\nprint(biggest(3, 9, 1))',
      ),
    ],
  ),
  PythonTopic(
    id: 32,
    level: 'beginner',
    title: 'Python 032：作用域与 LEGB',
    summary: '局部、全局作用域，以及 global 的使用。',
    concepts: ['作用域', 'LEGB', 'global'],
    objective: '理解变量查找顺序和函数内的读写规则。',
    prerequisites: ['定义函数与返回值'],
    explain:
        'Python 按 LEGB 顺序查找名字：Local（局部）、Enclosing（外层函数）、Global'
        '（模块全局）、Built-in（内置）。函数内给名字赋值会创建局部变量，除非用 '
        'global 声明。在函数里「只读」全局变量没问题，「赋值」则默认当它是局部——'
        '这是很多 UnboundLocalError 的根源。',
    code:
        'count = 0\n'
        '\n'
        'def increment():\n'
        '    global count\n'
        '    count += 1\n'
        '\n'
        'def local_shadow():\n'
        '    count = 100  # 这是局部变量\n'
        '    return count\n'
        '\n'
        'print(local_shadow())\n'
        'print(count)\n'
        'increment()\n'
        'print(count)\n',
    output:
        '100\n'
        '0\n'
        '1\n',
    pitfalls: [
      '在函数内赋值后再读同名全局变量会报 UnboundLocalError。',
      '过度使用 global 让数据流难追踪，优先用参数和返回值。',
      '局部变量名和全局同名会造成混淆。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个用 global 累加计数器的函数并调用三次。',
        hint: '声明 global 后在函数内 +=。',
        answer: 'n = 0\ndef inc():\n    global n\n    n += 1\nfor _ in range(3):\n    inc()\nprint(n)',
      ),
    ],
  ),
  PythonTopic(
    id: 33,
    level: 'beginner',
    title: 'Python 033：递归入门',
    summary: '函数调用自身，要有基线条件。',
    concepts: ['递归', '基线条件', '递归调用'],
    objective: '能写出有基线条件的递归函数。',
    prerequisites: ['定义函数与返回值', '条件分支'],
    explain:
        '递归就是函数调用自身。写递归必须想清楚两点：基线条件（什么时候直接返回、'
        '不再递归）和递归步骤（如何把问题缩小再交给自身）。缺少或写错基线条件会'
        '导致无限递归，最终报 RecursionError。递归让树、分治等问题表达得更自然。',
    code:
        'def factorial(n):\n'
        '    if n <= 1:\n'
        '        return 1\n'
        '    return n * factorial(n - 1)\n'
        '\n'
        'def sum_to(n):\n'
        '    if n == 0:\n'
        '        return 0\n'
        '    return n + sum_to(n - 1)\n'
        '\n'
        'print(factorial(5))\n'
        'print(sum_to(100))\n',
    output:
        '120\n'
        '5050\n',
    pitfalls: [
      '忘记基线条件导致 RecursionError。',
      '递归深度过大（Python 默认上限约 1000）会溢出。',
      '每层重复计算相同子问题，效率低时考虑记忆化。',
    ],
    tasks: [
      PythonTask(
        prompt: '用递归求斐波那契数列第 n 项。',
        hint: 'fib(n) = fib(n-1) + fib(n-2)，基线 fib(0)=0, fib(1)=1。',
        answer: 'def fib(n):\n    if n < 2:\n        return n\n    return fib(n - 1) + fib(n - 2)\nprint(fib(10))',
      ),
    ],
  ),
  PythonTopic(
    id: 34,
    level: 'beginner',
    title: 'Python 034：递归进阶——汉诺塔与记忆化',
    summary: '用递归解决汉诺塔，用字典做记忆化。',
    concepts: ['汉诺塔', '记忆化', '分治'],
    objective: '理解分治递归并用记忆化消除重复计算。',
    prerequisites: ['递归入门'],
    explain:
        '汉诺塔的分治思路：把 n 个盘从 A 移到 C，先把上面 n-1 个移到 B，移动最大盘'
        '到 C，再把 n-1 个从 B 移到 C。记忆化把已算过的结果存进字典，避免斐波那契'
        '这种递归树里的重复计算——这是「缓存换时间」的最简形式。',
    code:
        'def hanoi(n, src, aux, dst, moves):\n'
        '    if n == 0:\n'
        '        return\n'
        '    hanoi(n - 1, src, dst, aux, moves)\n'
        '    moves.append(f"{src}->{dst}")\n'
        '    hanoi(n - 1, aux, src, dst, moves)\n'
        '\n'
        'moves = []\n'
        'hanoi(3, "A", "B", "C", moves)\n'
        'print(len(moves))\n'
        'print(moves)\n'
        '\n'
        'memo = {}\n'
        'def fib(n):\n'
        '    if n < 2:\n'
        '        return n\n'
        '    if n not in memo:\n'
        '        memo[n] = fib(n - 1) + fib(n - 2)\n'
        '    return memo[n]\n'
        'print(fib(20))\n',
    output:
        '7\n'
        "['A->C', 'A->B', 'C->B', 'A->C', 'B->A', 'B->C', 'A->C']\n"
        '6765\n',
    pitfalls: [
      '汉诺塔最少移动次数是 2^n - 1，n 大时结果是天文数字。',
      '记忆化要确认子问题可复用，否则只是浪费内存。',
      'moves 用可变列表做参数是刻意的副作用，要注意调用方的预期。',
    ],
    tasks: [
      PythonTask(
        prompt: '求 n 层汉诺塔的最少移动次数（用公式或递归）。',
        hint: '次数 = 2**n - 1。',
        answer: 'n = 4\nprint(2 ** n - 1)',
      ),
    ],
  ),
  PythonTopic(
    id: 35,
    level: 'beginner',
    title: 'Python 035：lambda 与高阶函数',
    summary: '匿名函数，以及把函数作为参数的 map/filter。',
    concepts: ['lambda', 'map', 'filter', '高阶函数'],
    objective: '会用 lambda 和 map/filter 做简洁转换与筛选。',
    prerequisites: ['定义函数与返回值'],
    explain:
        'lambda 参数列表: 表达式 创建匿名函数，适合「只用一次」的短函数，常作为 '
        'key、map、filter 的参数。高阶函数指接收函数或返回函数的函数。map(f, seq) '
        '对每个元素应用 f，filter(pred, seq) 保留判真元素。很多场景用列表推导式'
        '比 map/filter 更易读。',
    code:
        'nums = [1, 2, 3, 4, 5]\n'
        'doubled = list(map(lambda x: x * 2, nums))\n'
        'print(doubled)\n'
        'odds = list(filter(lambda x: x % 2 == 1, nums))\n'
        'print(odds)\n'
        'pairs = sorted([(1, "b"), (2, "a")], key=lambda p: p[1])\n'
        'print(pairs)\n'
        'print(list(map(lambda x: x * x, range(5))))\n',
    output:
        '[2, 4, 6, 8, 10]\n'
        '[1, 3, 5]\n'
        '[(2, \'a\'), (1, \'b\')]\n'
        '[0, 1, 4, 9, 16]\n',
    pitfalls: [
      'lambda 只能写表达式，不能含语句或多行逻辑。',
      'map/filter 返回惰性迭代器，需要 list() 才能直接看到结果。',
      '给 lambda 起名再赋值给变量通常不如用 def 清晰。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 map 把温度列表从摄氏度转成华氏度。',
        hint: 'f = c * 9 / 5 + 32。',
        answer: 'c = [0, 25, 100]\nprint(list(map(lambda x: x * 9 / 5 + 32, c)))',
      ),
    ],
  ),
  PythonTopic(
    id: 36,
    level: 'beginner',
    title: 'Python 036：闭包',
    summary: '嵌套函数记住外层变量，用 nonlocal 修改。',
    concepts: ['闭包', 'nonlocal', '工厂函数'],
    objective: '理解闭包如何捕获外层变量并生成专用函数。',
    prerequisites: ['作用域与 LEGB'],
    explain:
        '内层函数引用外层函数的变量，即使外层已经返回，那些变量依然被「记住」，'
        '这就是闭包。闭包可以造出带状态的函数，比如计数器工厂。默认内层只能读外层'
        '变量；要修改需要 nonlocal 声明。闭包是装饰器和很多工厂模式的基础。',
    code:
        'def make_counter():\n'
        '    count = 0\n'
        '    def step():\n'
        '        nonlocal count\n'
        '        count += 1\n'
        '        return count\n'
        '    return step\n'
        '\n'
        'c1 = make_counter()\n'
        'print(c1(), c1(), c1())\n'
        'c2 = make_counter()\n'
        'print(c2())\n'
        '\n'
        'def multiplier(factor):\n'
        '    return lambda x: x * factor\n'
        '\n'
        'double = multiplier(2)\n'
        'print(double(5), multiplier(10)(5))\n',
    output:
        '1 2 3\n'
        '1\n'
        '10 50\n',
    pitfalls: [
      '忘记 nonlocal 会在内层创建新的局部变量而不是修改外层。',
      '每个 make_counter() 调用产生独立状态，别误以为共享。',
      '闭包捕获的是变量而非值，循环里创建闭包要小心延迟绑定。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 countdown 工厂，返回一个每次调用减一的函数。',
        hint: '用 nonlocal 修改外层计数。',
        answer: 'def countdown(start):\n    n = start\n    def step():\n        nonlocal n\n        n -= 1\n        return n\n    return step\nc = countdown(3)\nprint(c(), c(), c())',
      ),
    ],
  ),
  PythonTopic(
    id: 37,
    level: 'beginner',
    title: 'Python 037：装饰器入门',
    summary: '用 @语法在不改函数体的前提下增强函数。',
    concepts: ['装饰器', '函数即对象', '@语法'],
    objective: '理解装饰器是「接收函数、返回新函数」的高阶函数。',
    prerequisites: ['闭包'],
    explain:
        '装饰器本质是接收一个函数、返回一个新函数的高阶函数，@decorator 只是 '
        'func = decorator(func) 的语法糖。新函数通常在调用原函数前后加动作，比如'
        '打印、计时、校验。因为原函数被替换，包装函数要用 *args/**kwargs 转发所有'
        '参数。',
    code:
        'def logged(func):\n'
        '    def wrapper(*args, **kwargs):\n'
        '        print(f"调用 {func.__name__}")\n'
        '        result = func(*args, **kwargs)\n'
        '        print(f"返回 {result}")\n'
        '        return result\n'
        '    return wrapper\n'
        '\n'
        '@logged\n'
        'def add(a, b):\n'
        '    return a + b\n'
        '\n'
        'print(add(2, 3))\n',
    output:
        '调用 add\n'
        '返回 5\n'
        '5\n',
    pitfalls: [
      '包装函数忘记 return，原返回值会丢失变成 None。',
      '不用 *args/**kwargs 转发，原函数的多参数会传不进去。',
      '装饰器在定义时执行一次，不是在每次调用时。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个装饰器，在函数执行前打印它的名字。',
        hint: '用 func.__name__。',
        answer: 'def name_log(func):\n    def w(*a, **k):\n        print(func.__name__)\n        return func(*a, **k)\n    return w\n@name_log\ndef hi():\n    return 1\nhi()',
      ),
    ],
  ),
  PythonTopic(
    id: 38,
    level: 'beginner',
    title: 'Python 038：装饰器进阶',
    summary: '带参数的装饰器、堆叠装饰器和 functools-free 的元信息保留。',
    concepts: ['装饰器工厂', '堆叠', '元信息'],
    objective: '会用装饰器工厂并理解装饰器堆叠顺序。',
    prerequisites: ['装饰器入门'],
    explain:
        '带参数的装饰器是「返回装饰器的函数」：repeat(3) 先接收参数，再返回真正'
        '的装饰器。堆叠装饰器 @a @b def f 相当于 f = a(b(f))，即由内向外应用、由'
        '外向内执行。包装函数会覆盖原函数的 __name__ 和 __doc__，标准库用 '
        'functools.wraps 修复；此处用内置子集，手动复制 __name__ 即可。',
    code:
        'def repeat(times):\n'
        '    def decorator(func):\n'
        '        def wrapper(*args, **kwargs):\n'
        '            result = None\n'
        '            for _ in range(times):\n'
        '                result = func(*args, **kwargs)\n'
        '            return result\n'
        '        return wrapper\n'
        '    return decorator\n'
        '\n'
        '@repeat(3)\n'
        'def say(msg):\n'
        '    print(msg)\n'
        '    return msg\n'
        '\n'
        'say("hi")\n',
    output:
        'hi\n'
        'hi\n'
        'hi\n',
    pitfalls: [
      '带参数装饰器要多一层返回，容易少写一层括号。',
      '堆叠顺序搞反：最靠近函数的最先被应用。',
      '没有 functools.wraps 时 __name__ 会变成 wrapper，调试时容易困惑。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个装饰器让函数至少重复两次并返回最后一次结果。',
        hint: '循环两次调用 func。',
        answer: 'def twice(func):\n    def w(*a, **k):\n        func(*a, **k)\n        return func(*a, **k)\n    return w\n@twice\ndef f():\n    print("x")\nf()',
      ),
    ],
  ),
  PythonTopic(
    id: 39,
    level: 'beginner',
    title: 'Python 039：生成器入门',
    summary: '用 yield 惰性产出值，节省内存。',
    concepts: ['yield', '生成器', '惰性求值'],
    objective: '能写生成器函数并用 for 消费它。',
    prerequisites: ['定义函数与返回值'],
    explain:
        '包含 yield 的函数是生成器函数：调用它不立即执行，而是返回一个生成器；每次'
        '请求下一个值时才运行到下一个 yield 并「暂停」。生成器一次只产出一个值，'
        '不把整个序列放进内存，因此适合大序列或无限序列。生成器只能遍历一次。',
    code:
        'def count_up(n):\n'
        '    i = 1\n'
        '    while i <= n:\n'
        '        yield i\n'
        '        i += 1\n'
        '\n'
        'for x in count_up(4):\n'
        '    print(x, end=" ")\n'
        'print()\n'
        '\n'
        'gen = count_up(3)\n'
        'print(next(gen))\n'
        'print(list(gen))\n',
    output:
        '1 2 3 4 \n'
        '1\n'
        '[2, 3]\n',
    pitfalls: [
      '生成器只能遍历一次，第二次遍历为空。',
      '把生成器当列表调用 len() 会报错，需要先 list()。',
      'yield 之后的代码在下一次 next 时才继续执行。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个生成器产出前 n 个偶数。',
        hint: 'yield i*2。',
        answer: 'def evens(n):\n    for i in range(n):\n        yield i * 2\nprint(list(evens(5)))',
      ),
    ],
  ),
  PythonTopic(
    id: 40,
    level: 'beginner',
    title: 'Python 040：生成器表达式与管道',
    summary: '用生成器表达式串联处理步骤。',
    concepts: ['生成器表达式', '管道', '惰性'],
    objective: '会用生成器表达式做惰性数据处理。',
    prerequisites: ['生成器入门', '列表推导式'],
    explain:
        '把列表推导式的方括号换成圆括号就得到生成器表达式，它惰性求值、不一次性'
        '建列表。多个生成器可以串成管道：上游产出、下游消费，一级级转换而无需中间'
        '列表。sum、max、any、all 这类聚合函数能直接消费生成器。',
    code:
        'nums = range(1, 11)\n'
        'squares = (n * n for n in nums)\n'
        'print(sum(squares))\n'
        '\n'
        'words = ["apple", "fig", "banana", "kiwi"]\n'
        'long_words = (w for w in words if len(w) > 3)\n'
        'print(list(long_words))\n'
        '\n'
        'total = sum(n for n in range(100) if n % 2 == 0)\n'
        'print(total)\n',
    output:
        '385\n'
        "['apple', 'banana', 'kiwi']\n"
        '2450\n',
    pitfalls: [
      '生成器表达式用完即空，调试时先转 list 观察。',
      '把生成器表达式当元组——它不生成元组，而是一次性迭代器。',
      '嵌套生成器过多会降低可读性，必要时拆成函数。',
    ],
    tasks: [
      PythonTask(
        prompt: '用生成器表达式求 1..n 中所有奇数的平方和。',
        hint: 'sum(n*n for n in range(1, 11) if n % 2)。',
        answer: 'print(sum(n * n for n in range(1, 11) if n % 2 == 1))',
      ),
    ],
  ),
];
