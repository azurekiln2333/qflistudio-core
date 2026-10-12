import 'python_topic.dart';

/// Chapter 6-10: 面向对象进阶、迭代器与函数式、算法与数据结构、
/// 测试与工程实践、综合项目与 CPython 生态（topics 061-120）。
///
/// 每个 `runtime == embedded` 的 `code` 都已在真实内置 MicroPython 1.24.1
/// 运行器（native/build/windows/qfli_py_ffi.dll）上执行，且 `output` 与其
/// stdout 逐字一致；117-120 标注为 `PythonRuntime.cpython`，需要外部 CPython
/// 环境并在 CPython 3.x 下验证。
const List<PythonTopic> pythonTopicsAdvanced = <PythonTopic>[
  PythonTopic(
    id: 61,
    level: 'intermediate',
    title: 'Python 061：魔术方法——__eq__ 与 __lt__',
    summary: '重写比较协议，让自定义对象能判等、排序并放进集合。',
    concepts: ['__eq__', '__lt__', '__hash__', 'NotImplemented', 'sorted'],
    objective: '为自定义类实现 __eq__/__lt__/__hash__，参与排序与去重。',
    prerequisites: ['魔术方法：__str__/__repr__'],
    explain:
        '默认情况下两个内容相同的对象也不相等，因为 object 用的是身份比较。要让'
        '「值相等」生效就要重写 __eq__，要让对象能被 sorted 或 < 比较就要提供 '
        '__lt__。两个易错点：__eq__ 遇到不认识的类型应返回 NotImplemented，让'
        'Python 去尝试对方类型；一旦重写了 __eq__，对象的默认哈希会被关闭，此时'
        '把它放进 set 或当字典键就会报 TypeError，必须同时用参与比较的字段定义 '
        '__hash__。排序时把比较字段包成元组最稳妥，元组本身按字典序逐项比较。'
        '还有一个环境差异要注意：只定义 __lt__ 时，外部 CPython 会用「反射」把 '
        'a > b 交给 b.__lt__(a) 得出结果，而内置 MicroPython 运行器不做这种反'
        '射回退，a > b 会直接 TypeError；a <= b、a >= b 则在两个环境都报错。',
    code:
        r'''class Version:
    def __init__(self, major, minor):
        self.major = major
        self.minor = minor

    def _key(self):
        return (self.major, self.minor)

    def __eq__(self, other):
        if not isinstance(other, Version):
            return NotImplemented
        return self._key() == other._key()

    def __lt__(self, other):
        return self._key() < other._key()

    def __hash__(self):
        return hash(self._key())

    def __repr__(self):
        return "Version(%d, %d)" % (self.major, self.minor)


vs = [Version(2, 0), Version(1, 10), Version(1, 2)]
print(sorted(vs))
print(Version(1, 2) == Version(1, 2))
print(Version(1, 2) < Version(1, 10))
print(sorted(set(vs + [Version(1, 2)])))
print(vs[0] == "2.0")
''',
    output:
        r'''[Version(1, 2), Version(1, 10), Version(2, 0)]
True
True
[Version(1, 2), Version(1, 10), Version(2, 0)]
False
''',
    pitfalls: [
      '__eq__ 里忘写 return NotImplemented，跨类型比较会抛异常。',
      '重写 __eq__ 却没写 __hash__，对象入 set 会报 TypeError。',
      '只定义 __lt__ 时：<= 与 >= 在 CPython 和内置解释器都报 TypeError；a > b '
          '在 CPython 可由反射 __lt__ 得出布尔值，但内置 MicroPython 不支持反射，'
          '也会报 TypeError——需显式补齐全部比较方法才可移植。',
      '对象已作为 set/dict 键后不要修改参与 __hash__/__eq__ 的字段，否则哈希槽位'
          '与实际值不一致，查找会失败或出现重复项。',
      '在 __repr__ 里拼接元组若含非 ASCII，MicroPython 会输出转义形式，改用 % 格式化。',
    ],
    tasks: [
      PythonTask(
        prompt: '让 Version 支持 >= 比较。',
        hint: '可用 not self < other 实现。',
        answer: 'def __ge__(self, other):\n    return not self < other',
      ),
      PythonTask(
        prompt: '为 Version 添加 __le__ 与 __gt__，使四种比较在 CPython 与内置'
            '解释器上都可用。',
        hint: '统一用 _key() 元组比较，不要依赖反射。',
        answer: 'def __le__(self, other):\n    return self._key() <= other._key()\n\ndef __gt__(self, other):\n    return self._key() > other._key()',
      ),
      PythonTask(
        prompt: '按 minor 升序给一组 Version 排序。',
        hint: 'sorted 的 key 取属性。',
        answer: 'print(sorted(vs, key=lambda v: v.minor))',
      ),
    ],
  ),
  PythonTopic(
    id: 62,
    level: 'intermediate',
    title: 'Python 062：魔术方法——__len__ 与 __getitem__',
    summary: '实现容器协议，让对象支持 len()、索引与 for 遍历。',
    concepts: ['__len__', '__getitem__', '容器协议', '切片', '迭代回退'],
    objective: '让自定义类像序列一样支持 len、下标和遍历。',
    prerequisites: ['魔术方法：__eq__/__lt__'],
    explain:
        'Python 的 for 循环并不要求对象一定是列表：只要它实现了 __getitem__，'
        '就会从下标 0 开始依次取值，直到抛出 IndexError 为止，这叫迭代回退协议。'
        '再加上 __len__，就能用 len() 和布尔判断。实现 __getitem__ 时最好同时'
        '接受切片对象：把切片直接作用在内部列表上，并包回一个新的同类实例，行为'
        '才和内置序列一致。注意切片返回的应当是副本语义的容器，避免外部通过返回'
        '的引用改动内部状态。',
    code:
        r'''class Playlist:
    def __init__(self, name, songs):
        self.name = name
        self._songs = list(songs)

    def __len__(self):
        return len(self._songs)

    def __getitem__(self, index):
        if isinstance(index, slice):
            return Playlist(self.name, self._songs[index])
        return self._songs[index]

    def __contains__(self, item):
        return item in self._songs

    def __repr__(self):
        return "Playlist(%s, %d 首)" % (self.name, len(self))


pl = Playlist("commute", ["A", "B", "C", "D"])
print(len(pl))
print(pl[0], pl[-1])
print(pl[1:3]._songs)
print("C" in pl, "Z" in pl)
for i, s in enumerate(pl):
    print(i, s)
''',
    output:
        r'''4
A D
['B', 'C']
True False
0 A
1 B
2 C
3 D
''',
    pitfalls: [
      '__getitem__ 只处理整数时不支持切片，切片会报 TypeError。',
      '遍历越界没有抛 IndexError，for 会变成死循环。',
      '__len__ 必须返回非负整数，返回 None 会报 TypeError。',
      '把内部列表直接暴露给切片结果，外部修改会串改内部状态。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现 append 方法向播放列表追加歌曲。',
        hint: '直接操作内部列表。',
        answer: 'def append(self, song):\n    self._songs.append(song)',
      ),
      PythonTask(
        prompt: '实现 reversed 支持，让 reversed(pl) 可用。',
        hint: '返回一个逆序的迭代器。',
        answer: 'def __reversed__(self):\n    return reversed(self._songs)',
      ),
    ],
  ),
  PythonTopic(
    id: 63,
    level: 'intermediate',
    title: 'Python 063：运算符重载——__add__ 与 __mul__',
    summary: '让向量类支持 + 与 *，理解运算符本质是特殊方法调用。',
    concepts: ['__add__', '__mul__', '__rmul__', 'NotImplemented', '类型检查'],
    objective: '用 __add__/__mul__ 让自定义类型支持算术运算。',
    prerequisites: ['魔术方法：__len__/__getitem__'],
    explain:
        'a + b 本质是调用 a.__add__(b)；当 a 不认识 b 时，Python 会尝试右操作数'
        '的 b.__radd__(a) 一类方法，所以 3 * vec 能工作是因为实现了 __rmul__。'
        '重载运算符时先检查对方类型，不是预期类型就返回 NotImplemented，让 Python'
        '有机会尝试另一方，或在都失败时抛出清晰的 TypeError，而不是悄悄算错。'
        '标量乘法的语义要对每个分量同步放大，才能和其它数学代码保持一致。',
    code:
        r'''class Vector:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def __add__(self, other):
        if not isinstance(other, Vector):
            return NotImplemented
        return Vector(self.x + other.x, self.y + other.y)

    def __sub__(self, other):
        if not isinstance(other, Vector):
            return NotImplemented
        return Vector(self.x - other.x, self.y - other.y)

    def __mul__(self, k):
        if not isinstance(k, (int, float)):
            return NotImplemented
        return Vector(self.x * k, self.y * k)

    def __rmul__(self, k):
        return self.__mul__(k)

    def __eq__(self, other):
        return isinstance(other, Vector) and (self.x, self.y) == (other.x, other.y)

    def __repr__(self):
        return "Vector(%s, %s)" % (self.x, self.y)


a = Vector(1, 2)
b = Vector(3, 4)
print(a + b)
print(a - b)
print(3 * a)
print(a * 2 == Vector(2, 4))
try:
    a + 1
except TypeError:
    print("rejects int")
''',
    output:
        r'''Vector(4, 6)
Vector(-2, -2)
Vector(3, 6)
True
rejects int
''',
    pitfalls: [
      '返回 NotImplemented 而不是 None，None 会被当作运算结果继续传递。',
      '__mul__ 与 __rmul__ 都要实现，否则 3 * a 会失败。',
      '忘记处理非数字类型会导致静默错误或语义混乱。',
      '就地 += 若不定义 __iadd__ 会退化成 a = a + b，语义正确但会新建对象。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现 __abs__，返回向量长度。',
        hint: '可用 math.sqrt(x*x + y*y)。',
        answer: 'import math\n\ndef __abs__(self):\n    return math.sqrt(self.x ** 2 + self.y ** 2)',
      ),
      PythonTask(
        prompt: '实现点积 dot(other)。',
        hint: '返回 x*x + y*y 形式的内积。',
        answer: 'def dot(self, other):\n    return self.x * other.x + self.y * other.y',
      ),
    ],
  ),
  PythonTopic(
    id: 64,
    level: 'intermediate',
    title: 'Python 064：__slots__ 与内存布局的现实',
    summary: '认识 __slots__ 的本意，并观察 MicroPython 的实际存储方式。',
    concepts: ['__slots__', '__dict__', '内存布局', 'hasattr'],
    objective: '理解 __slots__ 想解决的问题，并写出可验证的观察代码。',
    prerequisites: ['运算符重载'],
    explain:
        '普通实例把属性放在一个字典 __dict__ 里，灵活但对象多时开销明显。CPython'
        '的 __slots__ 会改为固定槽位、去掉 __dict__，从而省内存并阻止拼错属性被'
        '悄悄创建。但要注意：内置 MicroPython 运行器并不实现这一优化——即使声明'
        '了 __slots__，实例仍然有 __dict__，也能添加未列出的属性。因此这段代码'
        '探测的是「运行器的真实行为」，输出反映的是 MicroPython 现状；在 CPython'
        '中同样的探测会得到 has_dict=False 且额外属性被拒绝。',
    code:
        r'''class Slotted:
    __slots__ = ("x", "y")

    def __init__(self, x, y):
        self.x = x
        self.y = y


class Flexible:
    def __init__(self, x, y):
        self.x = x
        self.y = y


s = Slotted(1, 2)
f = Flexible(1, 2)
f.z = 3
print(s.x, s.y, f.z)
print("slotted has __dict__:", hasattr(s, "__dict__"))
print("declared slots:", Slotted.__slots__)
s.extra = 9
print("extra allowed:", s.extra)
print("slotted attrs:", sorted(s.__dict__))
print("flexible attrs:", sorted(f.__dict__))
''',
    output:
        r'''1 2 3
slotted has __dict__: True
declared slots: ('x', 'y')
extra allowed: 9
slotted attrs: ['extra', 'x', 'y']
flexible attrs: ['x', 'y', 'z']
''',
    pitfalls: [
      '以为 __slots__ 在任何运行器上都省内存，MicroPython 并不实现它。',
      '拼错 __slots__ 中的属性名不会报错，只是限制失效。',
      '在类里同时写 __slots__ 和同名类变量会冲突。',
      '用 __dict__ 直接遍历属性在 CPython 的 slotted 类上会 AttributeError。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一段代码判断某实例是否拥有 __dict__。',
        hint: '用 hasattr 检查。',
        answer: 'print(hasattr(obj, "__dict__"))',
      ),
      PythonTask(
        prompt: '列出实例 __dict__ 中所有属性名。',
        hint: '对 __dict__ 取 keys。',
        answer: 'print(list(s.__dict__.keys()))',
      ),
    ],
  ),
  PythonTopic(
    id: 65,
    level: 'intermediate',
    title: 'Python 065：组合优于继承',
    summary: '用「拥有一个」代替「是一个」，降低类之间的耦合。',
    concepts: ['组合', '委托', '继承', '职责分离'],
    objective: '把发动机等能力拆成独立对象，用组合与委托装配汽车。',
    prerequisites: ['__slots__ 与内存布局的现实'],
    explain:
        '继承表达「是一个」（is-a），组合表达「拥有一个」（has-a）。当两个类并非'
        '真正的类别关系，只是共享部分能力时，硬套继承会导致子类被迫接受父类的所有'
        '接口，父类一改子类就碎。组合把可变部分做成独立对象，通过属性持有并在需要'
        '时把调用委托过去，既方便替换实现（换发动机不影响车），也让单元测试可以注入'
        '假对象。经验法则：先考虑组合，只有当子类确实是一种父类且需要多态替换时才用'
        '继承。',
    code:
        r'''class Engine:
    def __init__(self, power, fuel):
        self.power = power
        self.fuel = fuel

    def describe(self):
        return "%s 发动机，%d 马力" % (self.fuel, self.power)


class ElectricEngine(Engine):
    def __init__(self, power):
        Engine.__init__(self, power, "电动")

    def describe(self):
        return "电动发动机，%d 马力" % self.power


class Car:
    def __init__(self, name, engine):
        self.name = name
        self.engine = engine   # 组合：车"拥有"一个发动机

    def describe(self):
        return "%s 装配 %s" % (self.name, self.engine.describe())

    def upgrade(self, engine):
        self.engine = engine


sedan = Car("sedan", Engine(120, "汽油"))
print(sedan.describe())
sedan.upgrade(ElectricEngine(200))
print(sedan.describe())
print(isinstance(sedan, Car), isinstance(sedan.engine, Engine))
''',
    output:
        r'''sedan 装配 汽油 发动机，120 马力
sedan 装配 电动发动机，200 马力
True True
''',
    pitfalls: [
      '用继承共享代码却在语义上不成立，导致子类被迫重写父类大半方法。',
      '委托漏了转发某个方法，调用方拿不到预期能力。',
      '组合对象被外部直接替换成不兼容类型，缺少接口约定。',
      '继承层次过深时，super() 的解析路径难以追踪。',
    ],
    tasks: [
      PythonTask(
        prompt: '定义 HybridEngine，组合一个电动与一个汽油发动机，power 为两者之和。',
        hint: '在内部持有两个 Engine，describe 拼接两者。',
        answer: 'class HybridEngine:\n    def __init__(self, electric, petrol):\n        self.electric = electric\n        self.petrol = petrol\n        self.power = electric.power + petrol.power',
      ),
      PythonTask(
        prompt: '为 Car 增加 fuel_cost(km)，委托给 engine.fuel。',
        hint: '由 fuel 类型决定单价，返回总成本。',
        answer: 'def fuel_cost(self, km):\n    rate = 0.1 if self.engine.fuel == "电动" else 0.7\n    return km * rate',
      ),
    ],
  ),
  PythonTopic(
    id: 66,
    level: 'intermediate',
    title: 'Python 066：数据类——手写一个 dataclass',
    summary: '不依赖 dataclasses 模块，手写一个生成 __init__/__repr__/__eq__ 的小工具。',
    concepts: ['代码生成', 'exec', '装饰器工厂', '字段描述'],
    objective: '用字段描述 + 动态生成方法，模拟 dataclass 的核心能力。',
    prerequisites: ['组合优于继承'],
    explain:
        'dataclasses 提供了「声明字段就自动获得 __init__、__repr__、__eq__」的能力，'
        '但内置 MicroPython 没有这个模块，而且它的类没有 __annotations__，无法靠'
        '类型注解拿字段名。我们改用装饰器工厂：make_dataclass("x", "y") 接收字段名，'
        '用字符串模板拼出 __init__ 源码，交给 exec 编译执行，再把生成的函数绑定回类。'
        '__repr__/__eq__ 直接用闭包按字段名 getattr 组装，不必再走源码。这正是「先'
        '构造源码、再编译执行」的代码生成套路。',
    code:
        r'''def make_dataclass(*names):
    def decorate(cls):
        ns = {}
        params = ", ".join(names)
        assigns = "\n    ".join("self.%s = %s" % (n, n) for n in names)
        exec("def __init__(self, " + params + "):\n    " + assigns, ns)
        cls.__init__ = ns["__init__"]
        cls.__fields = names

        def __repr__(self):
            inner = ", ".join(
                "%s=%r" % (n, getattr(self, n)) for n in names)
            return cls.__name__ + "(" + inner + ")"

        cls.__repr__ = __repr__

        def __eq__(self, other):
            return type(self) is type(other) and all(
                getattr(self, n) == getattr(other, n) for n in names)

        cls.__eq__ = __eq__
        cls.__hash__ = lambda self: hash(
            tuple(getattr(self, n) for n in names))
        return cls
    return decorate


@make_dataclass("x", "y")
class Point:
    pass


a = Point(1, 2)
b = Point(1, 2)
print(a)
print(a == b)
print(a != Point(3, 4))
print(len({a, b}))
print(Point.__fields)
''',
    output:
        r'''Point(x=1, y=2)
True
True
1
('x', 'y')
''',
    pitfalls: [
      'exec 的源码缩进必须精确，少一个空格就 SyntaxError。',
      'MicroPython 类没有 __annotations__，不能靠类型注解拿字段名。',
      '生成的 __eq__ 不检查类型，不同类但同名属性会被判相等。',
      '不生成 __hash__ 时对象仍可哈希但语义与 __eq__ 不一致。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 make_dataclass 增加默认值支持：字段可写成 ("x", 0) 形式。',
        hint: '把每个字段规范化为 (name, default)；无默认值的参数在前，带默认的在 '
            '后，生成参数串时按需追加 =default。',
        answer: 'def make_dataclass2(*fields):\n    names = []\n    defaults = {}\n    for f in fields:\n        if isinstance(f, tuple):\n            names.append(f[0])\n            defaults[f[0]] = f[1]\n        else:\n            names.append(f)\n\n    def decorate(cls):\n        params = []\n        for n in names:\n            params.append(n if n not in defaults else "%s=%r" % (n, defaults[n]))\n        body = "\\n    ".join("self.%s = %s" % (n, n) for n in names)\n        ns = {}\n        exec("def __init__(self, " + ", ".join(params) + "):\\n    " + body, ns)\n        cls.__init__ = ns["__init__"]\n        cls.__fields = tuple(names)\n        return cls\n    return decorate',
      ),
      PythonTask(
        prompt: '为生成的对象实现 __lt__，按字段顺序比较。',
        hint: '用 getattr 构造元组后比较。',
        answer: 'cls.__lt__ = lambda self, o: tuple(getattr(self, n) for n in names) < tuple(getattr(o, n) for n in names)',
      ),
    ],
  ),
  PythonTopic(
    id: 67,
    level: 'intermediate',
    title: 'Python 067：综合——图书管理系统',
    summary: '用类建模图书、读者与借阅关系，完成查询与统计。',
    concepts: ['类设计', '集合管理', '关系建模', '聚合统计'],
    objective: '设计 Book/Library 两个类，实现借还、查询与排行。',
    prerequisites: ['数据类：手写实现'],
    explain:
        '一个管理系统要区分「实体的数据」和「操作的职责」：Book 只描述一本书，'
        'Library 负责持有馆藏、维护借出记录并提供查询接口。用字典 book_id -> '
        'Book 做索引能 O(1) 找到书；用另一个字典记录借阅次数便于统计热门书。'
        '每次借书都要先校验存在性和可借状态，这是「守卫条件」的典型用法：把非法'
        '情况尽早挡在门外，主逻辑才干净。统计排行前先排序，避免依赖字典顺序。',
    code:
        r'''class Book:
    def __init__(self, book_id, title, author):
        self.book_id = book_id
        self.title = title
        self.author = author
        self.borrowed = False


class Library:
    def __init__(self):
        self.books = {}
        self.borrow_counts = {}

    def add(self, book):
        self.books[book.book_id] = book
        self.borrow_counts[book.book_id] = 0

    def borrow(self, book_id):
        book = self.books.get(book_id)
        if book is None:
            return "no such book"
        if book.borrowed:
            return "already borrowed"
        book.borrowed = True
        self.borrow_counts[book_id] += 1
        return "ok"

    def give_back(self, book_id):
        book = self.books.get(book_id)
        if book is None or not book.borrowed:
            return "not borrowed"
        book.borrowed = False
        return "ok"

    def available(self):
        return sorted(b.book_id for b in self.books.values() if not b.borrowed)

    def hottest(self):
        ranked = sorted(self.borrow_counts.items(),
                        key=lambda kv: (-kv[1], kv[0]))
        return ranked[0]


lib = Library()
lib.add(Book(1, "SICP", "Abelson"))
lib.add(Book(2, "TAOCP", "Knuth"))
lib.add(Book(3, "K&R", "Kernighan"))
print(lib.borrow(1), lib.borrow(1), lib.borrow(2))
print(lib.give_back(1), lib.give_back(3))
print(lib.available())
print("hottest:", lib.hottest())
''',
    output:
        r'''ok already borrowed ok
ok not borrowed
[1, 3]
hottest: (1, 1)
''',
    pitfalls: [
      '用列表线性查找书，馆藏大时效率低，应建 id 字典索引。',
      '借出计数用普通字典却按顺序打印，MicroPython 下顺序不保证。',
      '借书前不校验状态，重复借出会破坏一致性。',
      '把 Book 的可变状态存在两份，导致不同步。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现 search(keyword)，按标题子串查书。',
        hint: '遍历 books.values()，用 in 判断。',
        answer: 'def search(self, kw):\n    return [b.book_id for b in self.books.values() if kw in b.title]',
      ),
      PythonTask(
        prompt: '实现排行榜前十 hottest_n(n)。',
        hint: '复用排序后切片。',
        answer: 'def hottest_n(self, n):\n    return sorted(self.borrow_counts.items(), key=lambda kv: (-kv[1], kv[0]))[:n]',
      ),
    ],
  ),
  PythonTopic(
    id: 68,
    level: 'intermediate',
    title: 'Python 068：综合——银行账户的事务式操作',
    summary: '用封装与校验实现存取款，保证余额一致与错误可追溯。',
    concepts: ['封装', '事务式操作', '自定义异常', '不变量'],
    objective: '让账户的每次操作要么完整成功，要么完全不改状态。',
    prerequisites: ['综合：图书管理系统'],
    explain:
        '账户的核心是「不变量」：余额绝不允许为负，每次操作前后都要满足。把余额'
        '设为「私有」并通过方法访问，可以集中校验。事务式操作的意思是「全部成功'
        '或全部回滚」：转账要同时从 A 扣、向 B 加，如果中途失败必须还原。这里先'
        '校验再修改，用自定义异常区分「钱不够」和「金额非法」，调用方据此采取不同'
        '处理，比返回魔法数字更清晰。日志列表记录每笔成功操作的快照，便于审计。',
    code:
        r'''class InsufficientFunds(Exception):
    pass


class InvalidAmount(Exception):
    pass


class Account:
    def __init__(self, owner, balance=0):
        self.owner = owner
        self._balance = balance
        self.history = []

    def balance(self):
        return self._balance

    def _check(self, amount):
        if amount <= 0:
            raise InvalidAmount("必须为正数")
        if amount > self._balance:
            raise InsufficientFunds("余额不足")

    def deposit(self, amount):
        if amount <= 0:
            raise InvalidAmount("必须为正数")
        self._balance += amount
        self.history.append(("deposit", amount, self._balance))
        return self._balance

    def withdraw(self, amount):
        self._check(amount)
        self._balance -= amount
        self.history.append(("withdraw", amount, self._balance))
        return self._balance

    def transfer_to(self, other, amount):
        self._check(amount)
        self._balance -= amount
        other._balance += amount
        self.history.append(("transfer", amount, self._balance))
        other.history.append(("receive", amount, other._balance))


a = Account("alice", 100)
b = Account("bob", 50)
a.deposit(40)
print(a.balance(), b.balance())
try:
    a.withdraw(1000)
except InsufficientFunds:
    print("insufficient")
try:
    a.deposit(-5)
except InvalidAmount:
    print("invalid")
a.transfer_to(b, 60)
print(a.balance(), b.balance())
print(len(a.history), len(b.history))
''',
    output:
        r'''140 50
insufficient
invalid
80 110
2 1
''',
    pitfalls: [
      '校验放在扣款之后，异常时余额已被改坏。',
      '用魔法返回值 -1 表示失败，调用方容易忘记检查。',
      'transfer 中途抛异常却已完成部分修改，破坏一致性。',
      '把余额做成公开属性，外部可绕过校验直接赋值。',
    ],
    tasks: [
      PythonTask(
        prompt: '为 withdraw 增加手续费 1 元，但仍保证余额不为负。',
        hint: '先按 amount+1 校验。',
        answer: 'def withdraw(self, amount):\n    self._check(amount + 1)\n    self._balance -= amount + 1\n    return self._balance',
      ),
      PythonTask(
        prompt: '实现 summary() 返回成功操作笔数与期末余额。',
        hint: '用 len(self.history) 与 self._balance。',
        answer: 'def summary(self):\n    return (len(self.history), self._balance)',
      ),
    ],
  ),
  PythonTopic(
    id: 69,
    level: 'intermediate',
    title: 'Python 069：迭代器协议——__iter__ 与 __next__',
    summary: '手写一个迭代器类，理解 for 背后的 StopIteration 机制。',
    concepts: ['__iter__', '__next__', 'StopIteration', '迭代器状态'],
    objective: '实现一个自定义迭代器，并解释 for 循环如何驱动它。',
    prerequisites: ['综合：银行账户'],
    explain:
        'for x in obj 的真实过程是：先调用 iter(obj) 得到迭代器，然后反复调用'
        '它的 __next__()；当 __next__ 抛出 StopIteration 时循环结束。因此迭代器'
        '对象必须自己记住「走到哪了」——通常是内部下标或游标。__iter__ 返回迭代'
        '器本身（迭代器也是可迭代对象），这是协议规定的。一旦耗尽，再次迭代同一个'
        '迭代器对象不会重新开始，这是新手最常见的困惑：迭代器是一次性的，可迭代'
        '对象才可重复遍历。',
    code:
        r'''class Countdown:
    def __init__(self, start):
        self.current = start

    def __iter__(self):
        return self

    def __next__(self):
        if self.current <= 0:
            raise StopIteration
        value = self.current
        self.current -= 1
        return value


c = Countdown(3)
for n in c:
    print(n)
print("again:", list(c))
print("fresh:", list(Countdown(3)))
it = iter(Countdown(2))
print(next(it), next(it))
try:
    next(it)
except StopIteration:
    print("stopped")
''',
    output:
        r'''3
2
1
again: []
fresh: [3, 2, 1]
2 1
stopped
''',
    pitfalls: [
      '__iter__ 返回了别的对象而不是 self，导致 next() 无法推进状态。',
      '耗尽后重新 for 一个迭代器对象却期待从头开始，得到了空结果。',
      '__next__ 忘记抛 StopIteration 会无限循环。',
      '在 __next__ 里修改了外部共享状态，多个迭代器互相干扰。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个只产出偶数的迭代器 EvenNumbers(limit)。',
        hint: '在 __next__ 中每次加 2，超过 limit 抛 StopIteration。',
        answer: 'class EvenNumbers:\n    def __init__(self, limit):\n        self.n = 0\n        self.limit = limit\n    def __iter__(self):\n        return self\n    def __next__(self):\n        if self.n > self.limit:\n            raise StopIteration\n        v = self.n\n        self.n += 2\n        return v',
      ),
      PythonTask(
        prompt: '用 for + 手动 next 演示迭代器被提前消耗。',
        hint: '先 next 两次，再 for 遍历剩下的。',
        answer: 'it = iter(Countdown(4))\nprint(next(it))\nfor n in it:\n    print(n)',
      ),
    ],
  ),
  PythonTopic(
    id: 70,
    level: 'intermediate',
    title: 'Python 070：自定义可迭代对象',
    summary: '区分「可迭代对象」与「迭代器」，让对象可被反复遍历。',
    concepts: ['可迭代对象', '迭代器工厂', '__iter__ 返回新迭代器', '惰性'],
    objective: '实现一个每次遍历都从头的可迭代容器。',
    prerequisites: ['迭代器协议'],
    explain:
        '可迭代对象和迭代器是两个不同职责：可迭代对象只负责「能生成迭代器」，'
        '迭代器负责「记住进度」。如果让 __iter__ 每次返回一个新建的迭代器对象，'
        '同一个容器就能被反复 for 遍历。这里让树形菜单既能递归展开，又对调用方'
        '隐藏了递归细节；把遍历状态放进单独的迭代器类，容器本身保持不可变。这种'
        '分离让「生成什么」和「怎么走」解耦，是标准库很多设计的共同点。',
    code:
        r'''class Node:
    def __init__(self, name, children=None):
        self.name = name
        self.children = children or []


class DepthFirst:
    def __init__(self, root):
        self.stack = [root]

    def __iter__(self):
        return self

    def __next__(self):
        if not self.stack:
            raise StopIteration
        node = self.stack.pop()
        self.stack.extend(reversed(node.children))
        return node.name


class Tree:
    def __init__(self, root):
        self.root = root

    def __iter__(self):
        return DepthFirst(self.root)


root = Node("root", [Node("a", [Node("a1"), Node("a2")]), Node("b")])
tree = Tree(root)
print(list(tree))
print(list(tree))
print("[" + ", ".join(tree) + "]")
''',
    output:
        r'''['root', 'a', 'a1', 'a2', 'b']
['root', 'a', 'a1', 'a2', 'b']
[root, a, a1, a2, b]
''',
    pitfalls: [
      '把遍历状态存在容器里，多次遍历会从上次位置继续。',
      '__iter__ 返回了容器自身，但容器没有 __next__，for 会报 TypeError。',
      '深度遍历用 pop() 是 LIFO，但没 reverse 子节点会得到逆序。',
      '把 children 可变列表直接暴露，外部修改会改变遍历结果。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现广度优先迭代器，用队列按层遍历。',
        hint: '用 collections.deque 并给定 maxlen。',
        answer: 'import collections\n\nclass BFS:\n    def __init__(self, root):\n        self.q = collections.deque((root,), 1000)\n    def __iter__(self):\n        return self\n    def __next__(self):\n        if not self.q:\n            raise StopIteration\n        n = self.q.popleft()\n        self.q.extend(n.children)\n        return n.name',
      ),
      PythonTask(
        prompt: '给 Tree 增加 leaves()，只产出叶子节点名。',
        hint: '遍历时过滤 children 为空的节点。',
        answer: 'def leaves(self):\n    return [n.name for n in DepthFirst(self.root)\n            if not n.children]',
      ),
    ],
  ),
  PythonTopic(
    id: 71,
    level: 'intermediate',
    title: 'Python 071：生成器进阶——send 与状态机',
    summary: '用 yield 接收 send 传入的值，把生成器当作协程式状态机。',
    concepts: ['send', 'yield 表达式', '状态机', 'next 初始化'],
    objective: '用生成器 send 驱动一个有状态的处理流程。',
    prerequisites: ['自定义可迭代对象'],
    explain:
        'yield 不只能「吐出」值，还能「接收」值：表达式 x = yield y 表示先吐出 '
        'y，暂停，等外部调用 gen.send(v) 时把 v 赋给 x 再继续。这个双向通道让生成'
        '器能当轻量状态机用。规矩是：生成器必须先 next() 或 send(None) 推进到第'
        '一个 yield，之后才能 send 具体值，否则报 TypeError。这里用一个「累计器」'
        '演示：每次 send 一个数，生成器记住总和并吐回当前总和，达到阈值就标记完成。',
    code:
        r'''def running_total(limit):
    total = 0
    while True:
        value = yield total
        if value is None:
            break
        total += value
        if total >= limit:
            yield total
            return


acc = running_total(10)
print(next(acc))
print(acc.send(3))
print(acc.send(4))
print(acc.send(5))
try:
    acc.send(1)
except StopIteration:
    print("done")
''',
    output:
        r'''0
3
7
12
done
''',
    pitfalls: [
      '忘了先 next(gen) 就 send 非 None 值，报 TypeError。',
      'send 后返回值是「下一个 yield 吐出的值」，不是 send 进去的值。',
      '生成器 return 后再次 send 会一直抛 StopIteration。',
      '把带 send 的生成器当成普通 for 用会提前耗光它的状态。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个平均器，每次 send 一个数，吐回当前均值。',
        hint: '维护 total 与 count，yield total/count。',
        answer: 'def averager():\n    total = 0\n    count = 0\n    while True:\n        x = yield 0 if count == 0 else total / count\n        total += x\n        count += 1',
      ),
      PythonTask(
        prompt: '写一个过滤器生成器，每次 send 字母，只吐回元音字母。',
        hint: '判断 in "aeiou"。',
        answer: 'def vowels():\n    while True:\n        ch = yield\n        if ch in "aeiou":\n            yield ch',
      ),
    ],
  ),
  PythonTopic(
    id: 72,
    level: 'intermediate',
    title: 'Python 072：惰性管道与内存',
    summary: '用生成器把多步处理串成惰性管道，避免中间列表。',
    concepts: ['惰性求值', '管道', '内存', '链式生成器'],
    objective: '把读数据、过滤、变换、汇总拼成惰性管道。',
    prerequisites: ['生成器进阶：send/状态机'],
    explain:
        '把「先全部读入再过滤再变换」改写成生成器流水线后，每个元素被单个处理、'
        '立即丢弃，中间不保留任何列表，内存占用与数据量无关。管道是一层层套起来'
        '的生成器：上层每要一个值，下层才算一个，这就是拖取（pull）式惰性求值。'
        '代价是调试更难、且每个元素只流一次（不能回头）。下面用一串传感器读数'
        '做例子：先取有效值，再换算单位，最后保留前若干条，全程只用一个 for。',
    code:
        r'''def read_values(raw):
    for item in raw:
        yield item


def valid(values):
    for v in values:
        if v is not None and v >= 0:
            yield v


def to_celsius(fahr_values):
    for f in fahr_values:
        yield round((f - 32) * 5 / 9, 1)


def take(n, values):
    count = 0
    for v in values:
        if count >= n:
            return
        yield v
        count += 1


raw = [50, None, 68, -5, 86, 32, 104, 77]
pipe = take(4, to_celsius(valid(read_values(raw))))
for c in pipe:
    print(c)
print("sum:", sum(to_celsius(valid(read_values(raw)))))
''',
    output:
        r'''10.0
20.0
30.0
0.0
sum: 125.0
''',
    pitfalls: [
      '管道里任何一步写成了列表推导，惰性就没了。',
      '流水线只能走一次，重复 sum 同一个生成器对象会得到 0。',
      'take 用 break 而非 return，会多产出一条。',
      '生成器链报错时看不到具体是哪一层的数据，需加中间变量调试。',
    ],
    tasks: [
      PythonTask(
        prompt: '加一层 to_int 把有效值取整。',
        hint: '仿照 valid 写一个生成器。',
        answer: 'def to_int(values):\n    for v in values:\n        if v >= 0:\n            yield int(v)',
      ),
      PythonTask(
        prompt: '手写 zip 合并两个惰性源 merge(a, b)。',
        hint: '轮流从两个生成器取。',
        answer: 'def merge(a, b):\n    for x, y in zip(a, b):\n        yield x\n        yield y',
      ),
    ],
  ),
  PythonTopic(
    id: 73,
    level: 'intermediate',
    title: 'Python 073：异常设计模式',
    summary: '用基类 + 子类构造语义清晰的异常层次，便于分层处理。',
    concepts: ['异常层次', '自定义异常', 'except 顺序', '语义化错误'],
    objective: '设计一组有共同基类的异常，并分层捕获它们。',
    prerequisites: ['惰性管道与内存'],
    explain:
        '好的异常设计是把「调用方需要区分的失败种类」建模成类：为模块定义一个基'
        '类 AppError，所有具体错误继承它。这样调用方可以只用 except AppError '
        '一次捕获全部业务错误（不误吞 ValueError 等编程错误），也可以单独捕获某'
        '个子类做特殊恢复。捕获顺序有讲究：子类必须写在父类前面，否则父类先命中'
        '子类永远轮不到。异常消息应当说清「哪个输入、为什么不行」，而不是只报错。',
    code:
        r'''class AppError(Exception):
    pass


class ValidationError(AppError):
    def __init__(self, field, reason):
        AppError.__init__(self, "%s: %s" % (field, reason))
        self.field = field
        self.reason = reason


class NotFound(AppError):
    pass


class Conflict(AppError):
    pass


users = {"alice": {"email": "a@x.io"}}


def require_email(name):
    if name not in users:
        raise NotFound("user %s" % name)
    email = users[name].get("email")
    if not email or "@" not in email:
        raise ValidationError("email", "格式非法")
    return email


for name in ["bob", "alice"]:
    try:
        print(name, "->", require_email(name))
    except ValidationError as e:
        print("invalid:", e.field, e.reason)
    except AppError as e:
        print("app error:", type(e).__name__, e)
print("still running")
''',
    output:
        r'''app error: NotFound user bob
alice -> a@x.io
still running
''',
    pitfalls: [
      '把子类 except 写在父类后面，子类分支永远不执行。',
      '让自定义异常继承 Exception 而非一个共同基类，调用方无法统一捕获。',
      '裸 except: 会吞掉 KeyboardInterrupt 等系统退出。',
      '异常消息里泄露敏感信息，或在 str 里拼不可序列化对象。',
    ],
    tasks: [
      PythonTask(
        prompt: '新增子类 RateLimited(AppError)，并在循环中单独处理。',
        hint: '放到 except ValidationError 之后、except AppError 之前。',
        answer: 'class RateLimited(AppError):\n    pass\n\nexcept RateLimited as e:\n    print("retry later")',
      ),
      PythonTask(
        prompt: '为 AppError 添加 code 属性供上层映射。',
        hint: '在 __init__ 里接受 code。',
        answer: 'class AppError(Exception):\n    def __init__(self, message, code="E_APP"):\n        Exception.__init__(self, message)\n        self.code = code',
      ),
    ],
  ),
  PythonTopic(
    id: 74,
    level: 'intermediate',
    title: 'Python 074：上下文管理器类',
    summary: '用 __enter__/__exit__ 实现 with 语句，保证资源释放。',
    concepts: ['__enter__', '__exit__', 'with', '异常传递'],
    objective: '写一个上下文管理器类，确保清理逻辑总是执行。',
    prerequisites: ['异常设计模式'],
    explain:
        'with 语句执行的顺序是：先调用对象的 __enter__，把它的返回值绑定到 as '
        '后面的名字；代码块结束后（无论正常、异常还是 return）都调用 __exit__。'
        '__exit__ 收到三个参：异常类型、异常值、traceback；块内无异常时三者都是 '
        'None。返回 True 会吞掉异常，返回 None/False 则继续传播——大多数情况下'
        '应当返回 False，让错误向上走。由于 MicroPython 没有 contextlib，我们'
        '手写一个「计时 + 日志」的上下文管理器，用 ticks_ms 测量代码块耗时。'
        '注意：测得的耗时受机器负载影响、不是确定值，所以程序只验证「清理逻辑'
        '一定执行且 elapsed 是非负整数」，而不把具体毫秒数写死成期望输出。',
    code:
        r'''import time


class Timing:
    def __init__(self, label):
        self.label = label
        self.elapsed = None

    def __enter__(self):
        self.start = time.ticks_ms()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.elapsed = time.ticks_diff(time.ticks_ms(), self.start)
        # 不打印具体毫秒数：它随机器负载变化，只验证清理已执行且结果非负
        print("timing ok:", isinstance(self.elapsed, int) and self.elapsed >= 0)
        return False


class Recover:
    def __init__(self, fallback):
        self.fallback = fallback

    def __enter__(self):
        return self.fallback

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None:
            print("recovered from", exc_type.__name__)
            return True
        return False


with Timing("loop") as t:
    total = 0
    for i in range(1000):
        total += i
print("total", total)
print("elapsed is set:", t.elapsed is not None)
with Recover("safe") as value:
    print("value", value)
    raise ValueError("boom")
print("after with")
''',
    output:
        r'''timing ok: True
total 499500
elapsed is set: True
value safe
recovered from ValueError
after with
''',
    pitfalls: [
      '__exit__ 返回 True 会静默吞掉异常，调试困难。',
      '__enter__ 忘了 return self，as 拿到的是 None。',
      '在 __exit__ 里又抛异常会掩盖原始异常。',
      '把 ticks_ms 测得的耗时写死成期望输出——它随机器负载变化，会让逐字对比'
          '在偶发情况下失败；应改为验证性质（如非负、小于阈值）。',
      'ticks_ms 只适合短间隔，不适合测量约百毫秒以上的区间。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个上下文管理器，进入时打开一个列表作为日志，退出时打印日志条数。',
        hint: '__enter__ 返回空列表，__exit__ 打印 len。',
        answer: 'class Journal:\n    def __enter__(self):\n        self.items = []\n        return self.items\n    def __exit__(self, *a):\n        print(len(self.items))\n        return False',
      ),
      PythonTask(
        prompt: '写一个 transaction 上下文，退出时若有异常就回滚字典。',
        hint: '进入时拷贝字典，__exit__ 里异常则恢复。',
        answer: 'class Transaction:\n    def __init__(self, data):\n        self.data = data\n    def __enter__(self):\n        self.backup = dict(self.data)\n        return self.data\n    def __exit__(self, et, e, tb):\n        if et is not None:\n            self.data.clear()\n            self.data.update(self.backup)\n        return False',
      ),
    ],
  ),
  PythonTopic(
    id: 75,
    level: 'intermediate',
    title: 'Python 075：装饰器实战——计时与缓存',
    summary: '用装饰器给函数加上耗时统计与记忆化，保持调用方式不变。',
    concepts: ['装饰器', '记忆化', '可调用对象', '缓存'],
    objective: '手写 memoize 与调用计数，并解释可调用对象模式。',
    prerequisites: ['上下文管理器类'],
    explain:
        '装饰器本质是「接受函数、返回可调用对象」的高阶函数，@ 只是把 f = deco(f) '
        '写成更直观的形式。memoize 把参数作为字典键、结果作为值缓存起来，下次同参'
        '直接返回，典型的以空间换时间；要求参数必须可哈希，列表、字典会报错。'
        '内置 MicroPython 的函数对象不能挂任意属性（f.cache = {} 会报错），所以'
        '调用计数、缓存这类元数据要放进一个自有 __call__ 的小类里：它既保存函数，'
        '也保存 cache 与 calls，调用时行为与原函数一致。注意 calls 计的是「所有'
        '调用（含递归中命中的查询）」，因此 fib(30) 的 calls 大于首次计算的次数。',
    code:
        r'''class Memoized:
    """把函数与它的缓存、调用计数绑在一起的可调用对象。"""

    def __init__(self, func):
        self.func = func
        self.cache = {}
        self.calls = 0

    def __call__(self, *args):
        self.calls += 1
        if args not in self.cache:
            self.cache[args] = self.func(*args)
        return self.cache[args]


def memoize(func):
    return Memoized(func)


@memoize
def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


@memoize
def add(a, b):
    return a + b


print(fib(30))
print("cache size:", len(fib.cache), "calls:", fib.calls)
print(add(1, 2), add(3, 4), add(1, 2))
print("calls:", add.calls)
''',
    output:
        r'''832040
cache size: 31 calls: 59
3 7 3
calls: 3
''',
    pitfalls: [
      'memoize 用列表参数作键会报不可哈希。',
      '包装函数忘了 *args/**kwargs，原函数的多参调用会报错。',
      '缓存字典无限增长，长期运行会耗尽内存。',
      '把 cache 设到函数对象上——MicroPython 不支持给函数挂任意属性。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 Memoized 加 clear() 方法清空缓存。',
        hint: '直接调 self.cache.clear。',
        answer: 'def clear(self):\n    self.cache.clear()',
      ),
      PythonTask(
        prompt: '写一个 timer 装饰器，打印函数耗时（可用 ticks_ms）。',
        hint: '在包装函数里取前后时间差。',
        answer: 'import time\n\ndef timer(func):\n    def wrapper(*a, **k):\n        t = time.ticks_ms()\n        r = func(*a, **k)\n        print(time.ticks_diff(time.ticks_ms(), t))\n        return r\n    return wrapper',
      ),
    ],
  ),
  PythonTopic(
    id: 76,
    level: 'intermediate',
    title: 'Python 076：装饰器实战——日志与重试',
    summary: '带参数的装饰器工厂：分层日志与失败重试。',
    concepts: ['装饰器工厂', '参数化装饰器', '重试', '层叠装饰'],
    objective: '实现接受参数的装饰器，并解释三层嵌套结构。',
    prerequisites: ['装饰器实战：计时与缓存'],
    explain:
        '带参数的装饰器要比普通装饰器多一层：最外层接收参数并返回真正的装饰器，'
        '中间层接收函数并返回包装函数，最内层才是每次调用执行的逻辑。因此 '
        '@retry(times=3) 会先执行 retry(times=3) 得到一个装饰器，再作用到函数上。'
        '重试装饰器在包装里用 for 尝试多次，每次失败就把异常存起来，全部失败后把'
        '最后一个异常重新抛出。注意：重试适合幂等/瞬态错误；对输入错误重试只会重'
        '复失败。装饰器层叠是自下而上：@log 写在 @retry 上方时，log 收到的 func '
        '是 retry 的包装函数，所以 func.__name__ 是 wrapper，想记录原函数名必须'
        '显式传递（MicroPython 不能给函数设 __name__）。',
    code:
        r'''import time


def log(level):
    def decorate(func):
        def wrapper(*args, **kwargs):
            print("[%s] call %s%s" % (level, func.__name__, args))
            return func(*args, **kwargs)
        return wrapper
    return decorate


def retry(times, delay_ms=0):
    def decorate(func):
        def wrapper(*args, **kwargs):
            last = None
            for attempt in range(1, times + 1):
                try:
                    return func(*args, **kwargs)
                except ValueError as exc:
                    last = exc
                    print("attempt %d failed" % attempt)
                    if delay_ms:
                        time.sleep_ms(delay_ms)
            raise last
        return wrapper
    return decorate


state = {"calls": 0}


@log("INFO")
@retry(times=3)
def flaky(x):
    state["calls"] += 1
    if state["calls"] < 3:
        raise ValueError("not yet")
    return x * 10


print("result:", flaky(7))
print("total calls:", state["calls"])
''',
    output:
        r'''[INFO] call wrapper(7,)
attempt 1 failed
attempt 2 failed
result: 70
total calls: 3
''',
    pitfalls: [
      '装饰器工厂漏掉最外层参数或没 return decorate，函数被直接替换成函数。',
      '层叠顺序自下而上：@log 在外层时日志只记一次而非每次重试。',
      '重试吞掉了非预期异常类型，调试困难。',
      '全部失败后忘了 raise，函数静默返回 None。',
    ],
    tasks: [
      PythonTask(
        prompt: '写 validate_non_negative 装饰器，参数为负时抛 ValueError。',
        hint: '在 wrapper 里检查 args[0]。',
        answer: 'def validate_non_negative(func):\n    def wrapper(x):\n        if x < 0:\n            raise ValueError("negative")\n        return func(x)\n    return wrapper',
      ),
      PythonTask(
        prompt: '把 retry 改成只捕获指定异常类型。',
        hint: '增加 exc_type 参数并用 except exc_type。',
        answer: 'def retry(times, exc_type=ValueError):\n    def decorate(func):\n        def wrapper(*a, **k):\n            for _ in range(times):\n                try:\n                    return func(*a, **k)\n                except exc_type:\n                    pass\n        return wrapper\n    return decorate',
      ),
    ],
  ),
  PythonTopic(
    id: 77,
    level: 'intermediate',
    title: 'Python 077：高阶函数——组合与 partial 手写',
    summary: '把函数当值，实现 compose 与 part（部分应用）。',
    concepts: ['高阶函数', 'compose', 'partial', '函数管道'],
    objective: '手写 compose 与 partial，理解函数作为一等对象。',
    prerequisites: ['装饰器实战：日志与重试'],
    explain:
        '函数在 Python 里是一等对象：可以赋值给变量、当参数传、当返回值返回。'
        '高阶函数就是把函数当普通值处理的函数。compose(f, g) 返回一个新函数，'
        '调用它等价于 f(g(x))，把多个小变换拼成一个。partial 固定部分参数，返回'
        '一个少几个参的新函数，适合给 map 或回调提供上下文。因为 MicroPython 没'
        '有 functools，这两个工具都手写；注意 compose 的参数顺序容易搞反，建议'
        '定义成「按书写顺序从外到内」并在文档串里注明。',
    code:
        r'''def compose(*funcs):
    """compose(f, g)(x) == f(g(x))；无参时返回恒等函数。"""
    def composed(x):
        for func in reversed(funcs):
            x = func(x)
        return x
    return composed


def partial(func, *bound):
    def wrapper(*args):
        return func(*(bound + args))
    return wrapper


def add(a, b):
    return a + b


def double(x):
    return x * 2


def inc(x):
    return x + 1


print(compose(double, inc)(5))
print(compose(inc, double)(5))
print(compose(inc, double, inc)(5))
add10 = partial(add, 10)
print(add10(5), add10(32))
print(list(map(partial(add, 100), [1, 2, 3])))
print(list(map(compose(double, inc), [1, 2, 3])))
''',
    output:
        r'''12
11
13
15 42
[101, 102, 103]
[4, 6, 8]
''',
    pitfalls: [
      'compose 的参数顺序写反，得到的结果与预期相反。',
      'partial 没处理关键字参数，遇到关键字调用会出错。',
      '嵌套太深的 compose 报错时堆栈难读，适当命名中间结果。',
      '把带副作用（print）的函数 compose 进去，执行顺序容易误判。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 compose 构造 square_then_inc(x)。',
        hint: '定义 square 后 square_then_inc = compose(inc, square)。',
        answer: 'def square(x):\n    return x * x\n\nsquare_then_inc = compose(inc, square)\nprint(square_then_inc(4))',
      ),
      PythonTask(
        prompt: '让 partial 也支持关键字参数。',
        hint: '签名改为 (*args, **kwargs) 并合并。',
        answer: 'def partial(func, *bound, **bound_kw):\n    def wrapper(*args, **kwargs):\n        merged = dict(bound_kw)\n        merged.update(kwargs)\n        return func(*(bound + args), **merged)\n    return wrapper',
      ),
    ],
  ),
  PythonTopic(
    id: 78,
    level: 'intermediate',
    title: 'Python 078：reduce 与聚合',
    summary: '手写 reduce，掌握「逐步折叠」的聚合模式。',
    concepts: ['reduce', '聚合', '折叠', '初始值'],
    objective: '手写 reduce 并用它实现求和、最大值、拼接。',
    prerequisites: ['高阶函数：组合与 partial'],
    explain:
        'reduce(func, seq, init) 把序列折叠成一个值：从 init 开始，逐个把已有'
        '结果和下一个元素交给 func，把返回值作为新的已有结果。它不是「对每个元素'
        '做一遍」，而是 carry 状态在迭代中传递，所以特别适合求和、求积、找最值、'
        '按规则合并字典等聚合。init 很重要：不传 init 时空序列会报错，且第一个元素'
        '会被当作初始值。内置 MicroPython 没有 functools.reduce，这里手写一个。',
    code:
        r'''def reduce(func, seq, init=None):
    it = iter(seq)
    if init is None:
        try:
            acc = next(it)
        except StopIteration:
            raise TypeError("reduce of empty sequence")
    else:
        acc = init
    for item in it:
        acc = func(acc, item)
    return acc


nums = [3, 1, 4, 1, 5, 9, 2, 6]
print(reduce(lambda a, b: a + b, nums, 0))
print(reduce(lambda a, b: a if a > b else b, nums))
print(reduce(lambda a, b: a * b, [1, 2, 3, 4], 1))
print(reduce(lambda acc, x: acc + [x * x], nums, []))
words = ["py", "is", "fun"]
print(reduce(lambda a, b: a + "-" + b, words))
''',
    output:
        r'''31
9
24
[9, 1, 16, 1, 25, 81, 4, 36]
py-is-fun
''',
    pitfalls: [
      '不传 init 时第一个元素被当作初始值，结果可能与预期差一项。',
      'func 的参顺序是 (累计值, 当前元素)，写反会得到错误结果。',
      '用 reduce 拼接列表 O(n²)，应改用加法累加器或 join。',
      '把 reduce 滥用成「能写就写」，可读性反而不如循环。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 reduce 把一组字典合并成一个（后者覆盖前者）。',
        hint: 'func 里 copy 后 update。',
        answer: 'def merge(a, b):\n    r = dict(a)\n    r.update(b)\n    return r\nprint(reduce(merge, [{"a":1},{"b":2},{"a":3}], {}))',
      ),
      PythonTask(
        prompt: '用 reduce 实现 all/any。',
        hint: '初始 True / False。',
        answer: 'print(reduce(lambda a, b: a and b, [1, 1, 0], True))\nprint(reduce(lambda a, b: a or b, [0, 0, 1], False))',
      ),
    ],
  ),
  PythonTopic(
    id: 79,
    level: 'intermediate',
    title: 'Python 079：柯里化与工厂函数',
    summary: '把多参函数逐次固定参数，生成专用小函数。',
    concepts: ['柯里化', '工厂函数', '闭包', '配置化'],
    objective: '用闭包实现柯里化乘法器与带配置的校验器工厂。',
    prerequisites: ['reduce 与聚合'],
    explain:
        '柯里化的意思是：把 f(a, b) 变成 f(a) 返回一个等待 b 的函数。它不是必须'
        '手写循环的奇技淫巧，而是「工厂函数」的基础：调用一次得到一个「已经记住'
        '配置的函数」，可以反复用。例如 multiplier(3) 返回一个把所有输入乘 3 的'
        '函数；make_range_check(low, high) 返回一个校验数值是否在区间的谓词。'
        '实现工具就是闭包：外层函数的参数被内层函数「记住」。注意默认参数陷阱——'
        '别用默认值当累加器，那是可变对象共享状态。',
    code:
        r'''def multiplier(k):
    def apply(x):
        return x * k
    return apply


def power(exp):
    return lambda base: base ** exp


def make_range_check(low, high):
    def check(value):
        return low <= value <= high
    return check


triple = multiplier(3)
square = power(2)
in_10_20 = make_range_check(10, 20)
print(triple(7), triple(0), triple(-2))
print(square(5), power(3)(2))
print(in_10_20(15), in_10_20(25), in_10_20(10))
print([n for n in range(0, 30) if in_10_20(n)])
print(list(map(multiplier(10), [1, 2, 3])))
''',
    output:
        r'''21 0 -6
25 8
True False True
[10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
[10, 20, 30]
''',
    pitfalls: [
      '用默认参数可变对象当累加器，多次调用会共享同一状态。',
      '柯里化层级过深时名字难读，适当给中间函数命名。',
      '返回 lambda 时漏写参数，变成每调用返回同一个对象。',
      '把需要多个配置的函数逐层柯里化反而更难维护，该用时才用。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 make_formatter(prefix)，返回把字符串加上前缀的函数。',
        hint: '闭包记住 prefix。',
        answer: 'def make_formatter(prefix):\n    def fmt(s):\n        return prefix + s\n    return fmt\nprint(make_formatter("> ")("done"))',
      ),
      PythonTask(
        prompt: '写 curried_add(a) 返回 add_b(b)，支持 curried_add(2)(3)。',
        hint: '两层闭包。',
        answer: 'def curried_add(a):\n    def add_b(b):\n        return a + b\n    return add_b\nprint(curried_add(2)(3))',
      ),
    ],
  ),
  PythonTopic(
    id: 80,
    level: 'intermediate',
    title: 'Python 080：综合——函数式数据处理管道',
    summary: '把生成器、装饰器、高阶函数拼成一个端到端数据处理管道。',
    concepts: ['函数式管道', '生成器', '装饰器', '高阶函数'],
    objective: '构建惰性过滤-变换-聚合的日志统计管道。',
    prerequisites: ['柯里化与工厂函数'],
    explain:
        '本章的各种工具可以组合成一条真正的数据流水线：原始行 -> 解析器（生成'
        '器）-> 谓词过滤器（高阶函数生成）-> 变换器 -> 聚合器。每一段都只关心'
        '自己的一件事，用 filter_by(pred) 这种「工厂返回生成器」的写法把条件参数化。'
        '整个管道惰性拉取，只在最终 reduce 时才开始计算，非常适合大文件逐行处理。'
        '下面用一批带状态码的请求日志行做例子，统计成功请求的耗时之和。',
    code:
        r'''def parse_lines(lines):
    for line in lines:
        parts = line.split()
        if len(parts) == 4:
            yield (parts[1], int(parts[2]), float(parts[3]))


def filter_by(predicate):
    def stage(source):
        for item in source:
            if predicate(item):
                yield item
    return stage


def transform(func):
    def stage(source):
        for item in source:
            yield func(item)
    return stage


def reduce(func, seq, init):
    acc = init
    for item in seq:
        acc = func(acc, item)
    return acc


ok = filter_by(lambda row: 200 <= row[1] < 300)
slow = filter_by(lambda row: row[2] > 0.5)
path_cost = transform(lambda row: (row[0], row[2]))

logs = [
    "GET /a 200 0.12",
    "GET /b 404 0.30",
    "GET /c 200 0.85",
    "POST /d 500 0.99",
    "GET /e 201 0.40",
]

pipeline = path_cost(slow(ok(parse_lines(logs))))
rows = list(pipeline)
print(rows)
print("sum:", round(reduce(lambda a, b: a + b[1], rows, 0.0), 2))
print("count:", len(rows))
''',
    output:
        r'''[('/c', 0.85)]
sum: 0.85
count: 1
''',
    pitfalls: [
      '把生成器管道先 list 再过滤，惰性优势尽失。',
      '解析器遇到脏行就 raise，应跳过或返回 None 再由过滤器排掉。',
      '聚合时用 init=0（int）相加浮点没有错但语义不清，宜用 0.0。',
      '同一生成器管道被重复消费，第二次为空。',
    ],
    tasks: [
      PythonTask(
        prompt: '增加一个按状态码分组的聚合器。',
        hint: '用 reduce 累加字典计数。',
        answer: 'def count_by(seq):\n    def step(acc, row):\n        acc[row[1]] = acc.get(row[1], 0) + 1\n        return acc\n    return reduce(step, seq, {})',
      ),
      PythonTask(
        prompt: '把 slow 阈值参数化，写成 make_threshold(min_cost)。',
        hint: '返回一个 filter_by。',
        answer: 'def make_threshold(min_cost):\n    return filter_by(lambda row: row[2] > min_cost)',
      ),
    ],
  ),
  PythonTopic(
    id: 81,
    level: 'advanced',
    title: 'Python 081：复杂度与计时',
    summary: '用操作计数与 ticks 计时对比 O(n) 与 O(n²) 的差距。',
    concepts: ['时间复杂度', '计数操作', 'ticks_ms', '增长階'],
    objective: '用可重现的方式度量算法随规模的增长趋势。',
    prerequisites: ['综合：函数式数据处理管道'],
    explain:
        '度量复杂度看的是「工作量随输入规模 n 增长的趋势」，不是具体跑多少毫秒。'
        '计时不稳定（受调度影响），更可靠的做法是数「关键操作执行了多少次」。这里'
        '对同一个求和任务实现两个版本：-个是只有一层循环的 O(n)，一个是用嵌套循环'
        '模拟的 O(n²)；用计数器记录内层执行次数，分别在 n=10 与 n=20 时观察比值：'
        'O(n) 翻一倍，O(n²) 翻四倍。这就是「大 O」的实际含义：常数不重要，斜率重要。',
    code:
        r'''def sum_linear(nums):
    steps = 0
    total = 0
    for x in nums:
        steps += 1
        total += x
    return total, steps


def sum_quadratic(nums):
    steps = 0
    total = 0
    for x in nums:
        for i in range(len(nums)):
            steps += 1
            if i == len(nums) - 1:
                total += x
    return total, steps


for n in (10, 20, 40):
    data = list(range(n))
    _, lin = sum_linear(data)
    _, quad = sum_quadratic(data)
    print("n=%d linear=%d quadratic=%d" % (n, lin, quad))
print("ratio quad 20:10 =", sum_quadratic(list(range(20)))[1]
      // sum_quadratic(list(range(10)))[1])
''',
    output:
        r'''n=10 linear=10 quadratic=100
n=20 linear=20 quadratic=400
n=40 linear=40 quadratic=1600
ratio quad 20:10 = 4
''',
    pitfalls: [
      '用单次计时就下结论，系统抖动会造成误判。',
      '以为常数小的 O(n²) 在小数据上总比 O(n) 快，规模一大就反转。',
      '忘记外层也有开销，只数内层导致复杂度估算偏差一个量级。',
      '拿不同循环体的函数直接对比，基准不可比。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 O(n²) 的重复检测 has_duplicate。',
        hint: '双重循环两两比较，遇相同返回 True。',
        answer: 'def has_duplicate(xs):\n    for i in range(len(xs)):\n        for j in range(i + 1, len(xs)):\n            if xs[i] == xs[j]:\n                return True\n    return False',
      ),
      PythonTask(
        prompt: '把重复检测改成 O(n) 版本。',
        hint: '用 set 记录见过的值。',
        answer: 'def has_duplicate_fast(xs):\n    seen = set()\n    for x in xs:\n        if x in seen:\n            return True\n        seen.add(x)\n    return False',
      ),
    ],
  ),
  PythonTopic(
    id: 82,
    level: 'advanced',
    title: 'Python 082：线性查找与二分查找',
    summary: '实现线性搜索与二分搜索，理解有序前提与边界收缩。',
    concepts: ['线性查找', '二分查找', '有序性', '边界'],
    objective: '写出正确的二分查找并验证它比线性查找少很多次比较。',
    prerequisites: ['复杂度与计时'],
    explain:
        '线性查找逐个看，最坏比较 n 次；二分查找要求数据已排序，每次把搜索区间'
        '砍一半，最坏约 log₂n 次。二分的难点全在边界：用 lo <= hi 还是 lo < hi、'
        'mid = (lo+hi)//2 还是上取整、找到时返回什么、找不到返回什么，差一点就会'
        '死循环或漏元素。推荐掌握一种固定写法：闭区间 [lo, hi]，当 lo <= hi 时'
        '取中点，相等就返回，小于就 lo=mid+1，否则 hi=mid-1。',
    code:
        r'''def linear_search(data, target):
    comparisons = 0
    for i in range(len(data)):
        comparisons += 1
        if data[i] == target:
            return i, comparisons
    return -1, comparisons


def binary_search(data, target):
    lo, hi = 0, len(data) - 1
    comparisons = 0
    while lo <= hi:
        comparisons += 1
        mid = (lo + hi) // 2
        if data[mid] == target:
            return mid, comparisons
        if data[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1, comparisons


data = list(range(0, 100, 2))
print(linear_search(data, 64))
print(binary_search(data, 64))
print(binary_search(data, 65))
print(linear_search(data, 0), binary_search(data, 0))
''',
    output:
        r'''(32, 33)
(32, 6)
(-1, 6)
(0, 1) (0, 5)
''',
    pitfalls: [
      'lo/hi 更新忘了 ±1，循环卡死在同一个 mid。',
      '对未排序数据跑二分，结果不可预测。',
      '求 mid 用 (lo+hi)/2 得到浮点数，索引报错。',
      '只比较相等不处理大小关系，无法收缩区间。',
    ],
    tasks: [
      PythonTask(
        prompt: '用二分找到 target 应插入的位置（保持有序）。',
        hint: '循环结束时的 lo 就是插入点。',
        answer: 'def bisect_left(data, target):\n    lo, hi = 0, len(data)\n    while lo < hi:\n        mid = (lo + hi) // 2\n        if data[mid] < target:\n            lo = mid + 1\n        else:\n            hi = mid\n    return lo',
      ),
      PythonTask(
        prompt: '写一个在已排序列表里找第一个 >= target 的函数。',
        hint: '参照 bisect_left。',
        answer: 'lower_bound = bisect_left',
      ),
    ],
  ),
  PythonTopic(
    id: 83,
    level: 'advanced',
    title: 'Python 083：冒泡、选择、插入排序',
    summary: '三种 O(n²) 排序的思想与实现，比较交换次数。',
    concepts: ['冒泡排序', '选择排序', '插入排序', '稳定性'],
    objective: '不调 sorted，手写三种基础排序并比较它们的性质。',
    prerequisites: ['线性查找与二分查找'],
    explain:
        '冒泡：反复比较相邻两个，逆序就交换，每一轮把最大值「冒」到末尾。选择：'
        '每轮从未排序部分挑最小的放到已排序部分末尾，交换次数最少。插入：把每个'
        '新元素插入到前面已排序序列的正确位置，对近乎有序的数据接近 O(n)，而且它'
        '是稳定的（相等元素不换位）。三者都是原地排序，数据量大时都很慢，实战用 '
        'sorted；学它们的价值在于理解「排序」共有何种结构。',
    code:
        r'''def bubble_sort(data):
    a = list(data)
    swaps = 0
    n = len(a)
    for i in range(n - 1):
        for j in range(n - 1 - i):
            if a[j] > a[j + 1]:
                a[j], a[j + 1] = a[j + 1], a[j]
                swaps += 1
    return a, swaps


def selection_sort(data):
    a = list(data)
    swaps = 0
    for i in range(len(a)):
        m = i
        for j in range(i + 1, len(a)):
            if a[j] < a[m]:
                m = j
        if m != i:
            a[i], a[m] = a[m], a[i]
            swaps += 1
    return a, swaps


def insertion_sort(data):
    a = list(data)
    shifts = 0
    for i in range(1, len(a)):
        key = a[i]
        j = i - 1
        while j >= 0 and a[j] > key:
            a[j + 1] = a[j]
            j -= 1
            shifts += 1
        a[j + 1] = key
    return a, shifts


sample = [5, 2, 9, 1, 5, 6]
print(bubble_sort(sample))
print(selection_sort(sample))
print(insertion_sort(sample))
print(bubble_sort([1, 2, 3, 4])[1], insertion_sort([1, 2, 3, 4])[1])
''',
    output:
        r'''([1, 2, 5, 5, 6, 9], 6)
([1, 2, 5, 5, 6, 9], 4)
([1, 2, 5, 5, 6, 9], 6)
0 0
''',
    pitfalls: [
      '冒泡内层范围写成 range(n-1)，已排好的尾巴被反复扫。',
      '选择排序忘记了 m != i，自交换虽正确但统计多计一次。',
      '插入排序内层用 for 而非 while，无法自由向后移。',
      '误以为三者都稳定：选择排序因跳换而不稳定。',
    ],
    tasks: [
      PythonTask(
        prompt: '给冒泡加「本轮无交换就提前退出」的优化。',
        hint: '用 swapped 标志位。',
        answer: 'def bubble_sort_early(a):\n    a = list(a)\n    for i in range(len(a) - 1):\n        swapped = False\n        for j in range(len(a) - 1 - i):\n            if a[j] > a[j + 1]:\n                a[j], a[j + 1] = a[j + 1], a[j]\n                swapped = True\n        if not swapped:\n            break\n    return a',
      ),
      PythonTask(
        prompt: '验证插入排序对近乎有序数据的比较次数远少于冒泡。',
        hint: '构造 [1,2,...,n,0] 分别跑两者。',
        answer: 'data = list(range(1, 50)) + [0]\nprint(bubble_sort(data)[1], insertion_sort(data)[1])',
      ),
    ],
  ),
  PythonTopic(
    id: 84,
    level: 'advanced',
    title: 'Python 084：归并排序',
    summary: '用分治与合并实现稳定 O(n log n) 排序。',
    concepts: ['分治', '归并', '递归', '稳定性'],
    objective: '手写归并排序，理解「分到最小再合并」的过程。',
    prerequisites: ['冒泡、选择、插入排序'],
    explain:
        '归并排序遵循分治三步：分解（把数组对半切）、解决（递归排序两半）、合并'
        '（把两个已排序序列合并成一个）。合并是核心：用两个指针各指一段头部，'
        '每次取较小者放进结果，相等时优先取左段就得到稳定排序。它的复杂度在任何'
        '输入下都是 O(n log n)，代价是需要 O(n) 额外空间。下面用生成器实现合并，'
        '展示 Python 风格的写法，并用操作计数说明递归树约有 n log n 次比较。',
    code:
        r'''def merge(left, right):
    result = []
    i = j = 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            result.append(left[i])
            i += 1
        else:
            result.append(right[j])
            j += 1
    result.extend(left[i:])
    result.extend(right[j:])
    return result


def merge_sort(data):
    if len(data) <= 1:
        return list(data)
    mid = len(data) // 2
    left = merge_sort(data[:mid])
    right = merge_sort(data[mid:])
    return merge(left, right)


sample = [8, 3, 5, 1, 9, 2]
print(merge_sort(sample))
print(merge_sort([]))
print(merge_sort([7]))
print(merge_sort([2, 1, 2, 1]))
print(merge([1, 4], [2, 3]))
''',
    output:
        r'''[1, 2, 3, 5, 8, 9]
[]
[7]
[1, 1, 2, 2]
[1, 2, 3, 4]
''',
    pitfalls: [
      '基线条件写成 len(data) == 0，单元素时无限递归。',
      '合并时比较用 < 而非 <=，相等元素会交换，失去稳定性。',
      '忘了 extend 剩余部分，结果少元素。',
      '在递归里直接改动共享列表，导致同一数据被排序两次。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计 merge_sort 总共执行多少次元素比较。',
        hint: '把 merge 改成返回 (结果, 比较次数)，在 merge_sort 里累加两半与合并的计数。',
        answer: 'def merge_counted(left, right):\n    result = []\n    i = j = 0\n    count = 0\n    while i < len(left) and j < len(right):\n        count += 1\n        if left[i] <= right[j]:\n            result.append(left[i]); i += 1\n        else:\n            result.append(right[j]); j += 1\n    result.extend(left[i:])\n    result.extend(right[j:])\n    return result, count\n\ndef merge_sort_counted(data):\n    if len(data) <= 1:\n        return list(data), 0\n    mid = len(data) // 2\n    left, cl = merge_sort_counted(data[:mid])\n    right, cr = merge_sort_counted(data[mid:])\n    merged, cm = merge_counted(left, right)\n    return merged, cl + cr + cm\n\nprint(merge_sort_counted([4, 1, 3, 2]))',
      ),
      PythonTask(
        prompt: '用归并思想统计一个数组的逆序对数量。',
        hint: '合并时当取右段元素时，左段剩余个数就是新增逆序对。',
        answer: 'def count_inv(a):\n    if len(a) <= 1:\n        return a, 0\n    m = len(a) // 2\n    l, cl = count_inv(a[:m])\n    r, cr = count_inv(a[m:])\n    out, i, j, c = [], 0, 0, cl + cr\n    while i < len(l) and j < len(r):\n        if l[i] <= r[j]:\n            out.append(l[i]); i += 1\n        else:\n            out.append(r[j]); j += 1; c += len(l) - i\n    return out + l[i:] + r[j:], c',
      ),
    ],
  ),
  PythonTopic(
    id: 85,
    level: 'advanced',
    title: 'Python 085：快速排序',
    summary: '用枢轴分区实现平均 O(n log n) 的原地排序。',
    concepts: ['快速排序', '分区', '枢轴', '递归'],
    objective: '手写快排，理解分区操作与最坏情况。',
    prerequisites: ['归并排序'],
    explain:
        '快排也是分治，但重心在「分」：先选一个枢轴，把数组重排成「小于枢轴、枢轴、'
        '大于枢轴」三段，再递归处理两侧。与归并不同，它主要是原地交换，所以空间'
        '开销小（递归栈除外）。最常见写法用三路分区（less、equal、greater），能'
        '优雅处理大量重复元素。快排平均 O(n log n)，但枢轴选得差（例如已排序数组'
        '里总选第一个）会退化成 O(n²)，所以实际实现常用随机枢轴。',
    code:
        r'''def quicksort(data):
    if len(data) <= 1:
        return list(data)
    pivot = data[len(data) // 2]
    less = [x for x in data if x < pivot]
    equal = [x for x in data if x == pivot]
    greater = [x for x in data if x > pivot]
    return quicksort(less) + equal + quicksort(greater)


def quicksort_inplace(a, lo, hi):
    if lo >= hi:
        return
    pivot = a[hi]
    store = lo
    for i in range(lo, hi):
        if a[i] < pivot:
            a[store], a[i] = a[i], a[store]
            store += 1
    a[store], a[hi] = a[hi], a[store]
    quicksort_inplace(a, lo, store - 1)
    quicksort_inplace(a, store + 1, hi)


sample = [3, 6, 1, 8, 2, 3]
print(quicksort(sample))
print(quicksort([5, 5, 5, 5]))
arr = [10, 7, 8, 9, 1, 5]
quicksort_inplace(arr, 0, len(arr) - 1)
print(arr)
''',
    output:
        r'''[1, 2, 3, 3, 6, 8]
[5, 5, 5, 5]
[1, 5, 7, 8, 9, 10]
''',
    pitfalls: [
      '枢轴总选首元素且输入已排序，退化为 O(n²)。',
      '分区时把 <= 和 < 用错，重复元素会引出无限递归。',
      '原地版忘记最后把枢轴换到 store 位置。',
      '递归没处理 lo >= hi 的边界，栈溢出或死循环。',
    ],
    tasks: [
      PythonTask(
        prompt: '比较三路分区快排与原生 sorted 在重复元素很多时的行为。',
        hint: '构造 [1]*1000 + [2]*1000 实测均可。',
        answer: 'print(quicksort([1] * 5 + [2] * 5))',
      ),
      PythonTask(
        prompt: '用随机枢轴避免已排序输入的最坏情况。',
        hint: '用 random.randint 选下标后与 hi 交换。',
        answer: 'import random\n\ndef pick(a, lo, hi):\n    i = random.randint(lo, hi)\n    a[i], a[hi] = a[hi], a[i]',
      ),
    ],
  ),
  PythonTopic(
    id: 86,
    level: 'advanced',
    title: 'Python 086：用 heapq 实现优先队列',
    summary: '用堆维护动态集合的最小值，实现任务调度。',
    concepts: ['堆', 'heapq', '优先队列', 'heappush/heappop'],
    objective: '用 heapq 维护优先队列，完成按优先级出队。',
    prerequisites: ['快速排序'],
    explain:
        '堆是一个完全二叉树，满足「父节点不大于子节点」的性质，根就是全堆最小值。'
        'heapq 提供现成操作：heapify 把列表原地变成堆 O(n)，heappush 插入 O(log n)，'
        'heappop 弹出最小值 O(log n)。它只保证「堆序」不保证「完全有序」。把 (优先'
        '级, 任务的元组）推入时，会先按优先级、再按任务字典序排列，所以我们额外'
        '放一个递增序号避免比较不可比较的任务对象。',
    code:
        r'''import heapq


def schedule(tasks):
    heap = []
    order = 0
    for priority, name in tasks:
        heapq.heappush(heap, (priority, order, name))
        order += 1
    result = []
    while heap:
        priority, _, name = heapq.heappop(heap)
        result.append(name)
    return result


tasks = [(3, "backup"), (1, "login"), (2, "render"), (1, "heartbeat")]
print(schedule(tasks))

nums = [5, 1, 8, 3, 2]
heapq.heapify(nums)
print(nums[0])
print(heapq.heappop(nums), heapq.heappop(nums))
heapq.heappush(nums, 0)
print(nums[0], len(nums))
''',
    output:
        r'''['login', 'heartbeat', 'render', 'backup']
1
1 2
0 4
''',
    pitfalls: [
      '把元组里的不可比较对象放在优先级后面，相等时比较报错。',
      '以为堆内列表按大小有序，实际只有堆序。',
      'heapify 前已按普通列表逻辑使用了它，下标关系失效。',
      '用 heapq.nlargest/nsmallest——内置 MicroPython 不提供。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 top_k(nums, k)，返回最大的 k 个数（可用 heapq）。',
        hint: '维护大小为 k 的最小堆，扫描一遍。',
        answer: 'def top_k(nums, k):\n    h = []\n    for x in nums:\n        heapq.heappush(h, x)\n        if len(h) > k:\n            heapq.heappop(h)\n    return h',
      ),
      PythonTask(
        prompt: '实现一个简单定时器：每次 pop 最早到期的任务时间。',
        hint: '堆元素为 (时间, 任务)。',
        answer: 'def next_deadline(h):\n    return heapq.heappop(h)[0]',
      ),
    ],
  ),
  PythonTopic(
    id: 87,
    level: 'advanced',
    title: 'Python 087：单向链表',
    summary: '用节点与引用实现链表，练习插入、删除与反转。',
    concepts: ['链表', '节点', '指针', '反转'],
    objective: '手写 LinkedList，支持 append、删除与反转。',
    prerequisites: ['用 heapq 实现优先队列'],
    explain:
        '链表由一串节点组成，每个节点存值与「下一个节点」的引用。与列表相比，'
        '链表头部插入/删除是 O(1)，但随机访问是 O(n)（必须从头数）。实现要点：'
        '维护 head 指针；遍历时用 cur = cur.next 推进；删除节点要把它前驱的 next '
        '跳过它。反转是经典题：用三个指针 prev/cur/next 逐个把箭头转反，最后把 '
        'head 指向原尾节点。下面还实现了 to_list 方便断言。',
    code:
        r'''class Node:
    def __init__(self, value, next_node=None):
        self.value = value
        self.next = next_node


class LinkedList:
    def __init__(self):
        self.head = None
        self.size = 0

    def append(self, value):
        node = Node(value)
        if self.head is None:
            self.head = node
        else:
            cur = self.head
            while cur.next:
                cur = cur.next
            cur.next = node
        self.size += 1

    def remove(self, value):
        prev, cur = None, self.head
        while cur:
            if cur.value == value:
                if prev is None:
                    self.head = cur.next
                else:
                    prev.next = cur.next
                self.size -= 1
                return True
            prev, cur = cur, cur.next
        return False

    def reverse(self):
        prev = None
        cur = self.head
        while cur:
            nxt = cur.next
            cur.next = prev
            prev = cur
            cur = nxt
        self.head = prev

    def to_list(self):
        out = []
        cur = self.head
        while cur:
            out.append(cur.value)
            cur = cur.next
        return out


ll = LinkedList()
for v in [1, 2, 3, 4]:
    ll.append(v)
print(ll.to_list(), ll.size)
print(ll.remove(2), ll.to_list())
print(ll.remove(99))
ll.reverse()
print(ll.to_list(), ll.size)
''',
    output:
        r'''[1, 2, 3, 4] 4
True [1, 3, 4]
False
[4, 3, 1] 3
''',
    pitfalls: [
      '删除头节点时忘记改 head，或只改了 cur。',
      '反转时忘了先保存 nxt，链会被切断。',
      'append 未处理空链表，head 永远是 None。',
      '用链表却按索引访问，每次 O(n) 无意识变慢。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现 prepend(value) 在头部插入，O(1)。',
        hint: '新节点.next = head 后改 head。',
        answer: 'def prepend(self, value):\n    self.head = Node(value, self.head)\n    self.size += 1',
      ),
      PythonTask(
        prompt: '实现 has_cycle 检测链表是否有环（快慢指针）。',
        hint: 'slow 走一步、fast 走两步。',
        answer: 'def has_cycle(self):\n    slow = fast = self.head\n    while fast and fast.next:\n        slow = slow.next\n        fast = fast.next.next\n        if slow is fast:\n            return True\n    return False',
      ),
    ],
  ),
  PythonTopic(
    id: 88,
    level: 'advanced',
    title: 'Python 088：栈与队列',
    summary: '用 list 实现栈、用 deque 实现队列，理解 LIFO/FIFO。',
    concepts: ['栈', '队列', 'LIFO', 'FIFO', 'collections.deque'],
    objective: '实现括号匹配（栈）与滑动窗口（队列）。',
    prerequisites: ['单向链表'],
    explain:
        '栈是后进先出（LIFO）：只能在栈顶压入/弹出，list 的 append/pop 正是 '
        'O(1) 栈操作。队列是先进先出（FIFO）：头部出队，用 list.pop(0) 是 O(n)，'
        '所以用 collections.deque 的 popleft O(1)。注意内置 MicroPython 的 '
        'deque 是有界的，构造时必须给 maxlen。下面两个例子：用栈检查括号是否匹配；'
        '用队列维护滑动窗口的平均值。',
    code:
        r'''import collections


def check_brackets(text):
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for ch in text:
        if ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            if not stack or stack.pop() != pairs[ch]:
                return False
    return not stack


def window_averages(values, k):
    q = collections.deque((), k)
    total = 0
    result = []
    for v in values:
        if len(q) == k:
            total -= q.popleft()
        q.append(v)
        total += v
        if len(q) == k:
            result.append(round(total / k, 1))
    return result


print(check_brackets("([{}])"))
print(check_brackets("([)]"))
print(check_brackets("("))
print(window_averages([1, 2, 3, 4, 5], 3))
''',
    output:
        r'''True
False
False
[2.0, 3.0, 4.0]
''',
    pitfalls: [
      '队列用 list.pop(0)，数据量大时每次 O(n)。',
      '栈用栈顶判断却忘了空栈，pop 报 IndexError。',
      'deque 构造漏掉 maxlen，内置 MicroPython 会报参数缺失。',
      '括号匹配只看数量不看嵌套顺序（如 ([)] 会错判）。',
    ],
    tasks: [
      PythonTask(
        prompt: '用栈实现简单的四则表达式逆波兰求值。',
        hint: '遇数字入栈，遇运算符弹出两个数计算后入栈。',
        answer: 'def eval_rpn(tokens):\n    stack = []\n    for t in tokens:\n        if t in "+-*/":\n            b = stack.pop(); a = stack.pop()\n            if t == "+": stack.append(a + b)\n            elif t == "-": stack.append(a - b)\n            elif t == "*": stack.append(a * b)\n            else: stack.append(a / b)\n        else:\n            stack.append(int(t))\n    return stack[0]',
      ),
      PythonTask(
        prompt: '用两个栈实现队列。',
        hint: '入队压 in_stack；出队时把 in_stack 全部倒到 out_stack。',
        answer: 'class Queue:\n    def __init__(self):\n        self.inn = []\n        self.out = []\n    def push(self, x):\n        self.inn.append(x)\n    def pop(self):\n        if not self.out:\n            while self.inn:\n                self.out.append(self.inn.pop())\n        return self.out.pop()',
      ),
    ],
  ),
  PythonTopic(
    id: 89,
    level: 'advanced',
    title: 'Python 089：哈希表原理与 dict',
    summary: '用链地址法手写哈希表，理解冲突与负载因子。',
    concepts: ['哈希', '冲突', '链地址法', '负载因子', 'dict'],
    objective: '实现一个支持 put/get/delete 的简单哈希表。',
    prerequisites: ['栈与队列'],
    explain:
        '哈希表用哈希函数把键映射到桶下标，实现平均 O(1) 的查找。不同键映到同一 '
        '桶叫冲突，常用「链地址法」解决：每个桶存一个列表，冲突元素挂在同一桶里。'
        '当元素数 / 桶数（负载因子）过大时冲突变多，需要扩容重建。这里用固定大小的'
        '桶数组简化实现，用 setdefault 的等价写法（get 取不到则建列表）扎桶。哈希表'
        '要求键可哈希且不可变——这就是列表不能当字典键的原因。',
    code:
        r'''class HashTable:
    def __init__(self, buckets=8):
        self.buckets = [None] * buckets
        self.size = 0

    def _index(self, key):
        return hash(key) % len(self.buckets)

    def put(self, key, value):
        i = self._index(key)
        if self.buckets[i] is None:
            self.buckets[i] = []
        chain = self.buckets[i]
        for pair in chain:
            if pair[0] == key:
                pair[1] = value
                return
        chain.append([key, value])
        self.size += 1

    def get(self, key, default=None):
        i = self._index(key)
        chain = self.buckets[i]
        if chain is not None:
            for k, v in chain:
                if k == key:
                    return v
        return default

    def delete(self, key):
        i = self._index(key)
        chain = self.buckets[i]
        if chain is None:
            return False
        for idx in range(len(chain)):
            if chain[idx][0] == key:
                chain.pop(idx)
                self.size -= 1
                return True
        return False


ht = HashTable(buckets=4)
for k, v in [("a", 1), ("b", 2), ("c", 3)]:
    ht.put(k, v)
print(ht.get("a"), ht.get("b"), ht.get("z", -1))
ht.put("a", 100)
print(ht.get("a"), ht.size)
print(ht.delete("b"), ht.get("b"), ht.size)
print(ht.delete("q"))
''',
    output:
        r'''1 2 -1
100 3
True None 2
False
''',
    pitfalls: [
      '用可变对象（如 list）当键，hash 报错。',
      '冲突处理只存一个值，后来者直接覆盖。',
      '删元素后用 None 占位不当，链断了导致查不到后面的元素。',
      '负载因子过高不扩容，退化成链表 O(n)。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 HashTable 加 keys() 遍历所有键。',
        hint: '扫描 buckets 里的每个链。',
        answer: 'def keys(self):\n    out = []\n    for chain in self.buckets:\n        if chain:\n            for k, v in chain:\n                out.append(k)\n    return out',
      ),
      PythonTask(
        prompt: '实现负载因子并在超过 0.75 时翻倍桶数重建。',
        hint: '收集所有键值对，清空后重插。',
        answer: 'def maybe_resize(self):\n    if self.size / len(self.buckets) > 0.75:\n        items = [(k, v) for c in self.buckets if c for k, v in c]\n        self.buckets = [None] * (len(self.buckets) * 2)\n        self.size = 0\n        for k, v in items:\n            self.put(k, v)',
      ),
    ],
  ),
  PythonTopic(
    id: 90,
    level: 'advanced',
    title: 'Python 090：二叉树与遍历',
    summary: '实现二叉搜索树，完成前中后序与层序遍历。',
    concepts: ['二叉树', 'BST', '前序', '中序', '后序', '层序'],
    objective: '手写 BST 的插入与三种深度优先遍历，并验证中序有序。',
    prerequisites: ['哈希表原理与 dict'],
    explain:
        '二叉树每个节点最多两个子节点。二叉搜索树（BST）额外要求：左子树全部小'
        '于根、右子树全部大于根，因此中序遍历（左-根-右）会得到升序序列，这是 BST '
        '最有用的性质。三种深度优先遍历只是「访问根」的时机不同：前序在递归左右前、'
        '中序在左右之间、后序在左右之后。层序用队列逐层展开，能求树高与宽度。',
    code:
        r'''class TreeNode:
    def __init__(self, value):
        self.value = value
        self.left = None
        self.right = None


class BST:
    def __init__(self):
        self.root = None

    def insert(self, value):
        if self.root is None:
            self.root = TreeNode(value)
            return
        cur = self.root
        while True:
            if value < cur.value:
                if cur.left is None:
                    cur.left = TreeNode(value)
                    return
                cur = cur.left
            else:
                if cur.right is None:
                    cur.right = TreeNode(value)
                    return
                cur = cur.right

    def inorder(self, node=None, acc=None):
        if acc is None:
            node, acc = self.root, []
        if node is None:
            return acc
        self.inorder(node.left, acc)
        acc.append(node.value)
        self.inorder(node.right, acc)
        return acc


def preorder(node, acc=None):
    if acc is None:
        acc = []
    if node is None:
        return acc
    acc.append(node.value)
    preorder(node.left, acc)
    preorder(node.right, acc)
    return acc


def postorder(node, acc=None):
    if acc is None:
        acc = []
    if node is None:
        return acc
    postorder(node.left, acc)
    postorder(node.right, acc)
    acc.append(node.value)
    return acc


def level_order(root):
    import collections
    q = collections.deque((root,), 100)
    out = []
    while q:
        node = q.popleft()
        out.append(node.value)
        if node.left:
            q.append(node.left)
        if node.right:
            q.append(node.right)
    return out


tree = BST()
for v in [5, 3, 8, 1, 4, 7, 9]:
    tree.insert(v)
print("inorder:  ", tree.inorder())
print("preorder: ", preorder(tree.root))
print("postorder:", postorder(tree.root))
print("level:    ", level_order(tree.root))
''',
    output:
        r'''inorder:   [1, 3, 4, 5, 7, 8, 9]
preorder:  [5, 3, 1, 4, 8, 7, 9]
postorder: [1, 4, 3, 7, 9, 8, 5]
level:     [5, 3, 8, 1, 4, 7, 9]
''',
    pitfalls: [
      'BST 插入用 <= 可能重复值扎向一侧，需明确重复策略。',
      '中序递归把 acc 当默认参数，多次调用会累积到同一个列表。',
      '层序遍历用 list.pop(0) 效率低，应用 deque。',
      '删除节点未处理双子节点，树结构断开。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现 search(value) 在 BST 中查找。',
        hint: '从根开始左小右大逐层下走。',
        answer: 'def search(self, value):\n    cur = self.root\n    while cur:\n        if value == cur.value:\n            return True\n        cur = cur.left if value < cur.value else cur.right\n    return False',
      ),
      PythonTask(
        prompt: '实现树高 height()。',
        hint: '递归 max(left, right) + 1。',
        answer: 'def height(node):\n    if node is None:\n        return 0\n    return 1 + max(height(node.left), height(node.right))',
      ),
    ],
  ),
  PythonTopic(
    id: 91,
    level: 'advanced',
    title: 'Python 091：图与 DFS/BFS',
    summary: '用邻接表表示图，实现深度优先与广度优先搜索。',
    concepts: ['图', '邻接表', 'DFS', 'BFS', '连通分量'],
    objective: '用邻接表建模图，手写 DFS/BFS 并求最短跳数。',
    prerequisites: ['二叉树与遍历'],
    explain:
        '图由顶点和边组成，邻接表用「顶点 -> 邻居列表」描述，适合稀疏图。DFS '
        '用栈（或递归）一条路走到底再回头，适合遍历与连通性；BFS 用队列一层层'
        '往外扩，首次到达某点的步数就是最短跳数（边权相等时）。邻接表在 MicroPython'
        '里注意字典顺序不保证，所以遍历邻居前先 sorted，输出才稳定。visited 集合'
        '防止图里有环时无限循环。',
    code:
        r'''def build_graph(edges):
    graph = {}
    for a, b in edges:
        if a not in graph:
            graph[a] = []
        if b not in graph:
            graph[b] = []
        graph[a].append(b)
        graph[b].append(a)
    return graph


def dfs(graph, start):
    visited = set()
    order = []
    stack = [start]
    while stack:
        node = stack.pop()
        if node in visited:
            continue
        visited.add(node)
        order.append(node)
        for nb in sorted(graph[node], reverse=True):
            if nb not in visited:
                stack.append(nb)
    return order


def bfs(graph, start):
    import collections
    visited = {start}
    dist = {start: 0}
    q = collections.deque((start,), 100)
    while q:
        node = q.popleft()
        for nb in sorted(graph[node]):
            if nb not in visited:
                visited.add(nb)
                dist[nb] = dist[node] + 1
                q.append(nb)
    return dist


graph = build_graph([("A", "B"), ("A", "C"), ("B", "D"),
                     ("C", "D"), ("D", "E")])
print("dfs:", dfs(graph, "A"))
print("bfs dist:", sorted(bfs(graph, "A").items()))
print("reachable:", len(bfs(graph, "A")))
''',
    output:
        r'''dfs: ['A', 'B', 'D', 'C', 'E']
bfs dist: [('A', 0), ('B', 1), ('C', 1), ('D', 2), ('E', 3)]
reachable: 5
''',
    pitfalls: [
      'DFS 忘了 visited，有环图会栈溢出。',
      '邻居未排序直接遍历，输出顺序随哈希而变。',
      'BFS 的 dist 忘了初始化起点为 0。',
      '把无权图当加权图，BFS 的距离不再是真正最短。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个 shortest_path(graph, a, b) 返回路径节点序列。',
        hint: 'BFS 同时记录 parent，找到后回溯。',
        answer: 'def shortest_path(graph, a, b):\n    import collections\n    q = collections.deque((a,), 100)\n    parent = {a: None}\n    while q:\n        node = q.popleft()\n        if node == b:\n            break\n        for nb in graph[node]:\n            if nb not in parent:\n                parent[nb] = node\n                q.append(nb)\n    if b not in parent:\n        return None\n    path = []\n    cur = b\n    while cur is not None:\n        path.append(cur)\n        cur = parent[cur]\n    return path[::-1]',
      ),
      PythonTask(
        prompt: '统计无向图中连通分量的个数。',
        hint: '对每个未访问顶点跑一次 DFS。',
        answer: 'def components(graph):\n    seen = set()\n    count = 0\n    for node in graph:\n        if node not in seen:\n            count += 1\n            for v in dfs(graph, node):\n                seen.add(v)\n    return count',
      ),
    ],
  ),
  PythonTopic(
    id: 92,
    level: 'advanced',
    title: 'Python 092：动态规划入门',
    summary: '用记忆化与自底向上递推求斐波那契与爬楼梯。',
    concepts: ['动态规划', '记忆化', '递推', '状态'],
    objective: '把重叠子问题的递归改写成记忆化/递推，消除重复计算。',
    prerequisites: ['图与 DFS/BFS'],
    explain:
        '动态规划适用条件是「重叠子问题 + 最优子结构」：大问题的解能由小问题的解'
        '拼出，且小问题会被反复用到。两种写法：自顶向下记忆化，保留递归的直观、'
        '用缓存避免重复；自底向上递推，用数组按小到大填表，没有递归开销。以爬楼梯'
        '为例：到达第 n 阶的方法数 = 到 n-1 阶 + 到 n-2 阶（最后一步跨 1 或 2 阶），'
        '这就是状态转移方程。',
    code:
        r'''def fib_memo(n, cache=None):
    if cache is None:
        cache = {0: 0, 1: 1}
    if n in cache:
        return cache[n]
    cache[n] = fib_memo(n - 1, cache) + fib_memo(n - 2, cache)
    return cache[n]


def fib_dp(n):
    if n < 2:
        return n
    prev, cur = 0, 1
    for _ in range(2, n + 1):
        prev, cur = cur, prev + cur
    return cur


def climb_stairs(n):
    if n <= 2:
        return n
    a, b = 1, 2
    for _ in range(3, n + 1):
        a, b = b, a + b
    return b


print([fib_memo(i) for i in range(10)])
print([fib_dp(i) for i in range(10)])
print(fib_memo(40) == fib_dp(40))
print([climb_stairs(i) for i in range(1, 7)])
''',
    output:
        r'''[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
True
[1, 2, 3, 5, 8, 13]
''',
    pitfalls: [
      '记忆化用 list 当缓存下标越界，应改用 dict 或开足够大的数组。',
      '递推时忘了处理 n=0/1 的基线。',
      '状态定义不清，把「方法数」和「最少步数」混为一谈。',
      '递归深度过大超过限制，应改自底向上。',
    ],
    tasks: [
      PythonTask(
        prompt: '每次可爬 1/2/3 阶，求到 n 阶的方法数。',
        hint: 'dp[i] = dp[i-1] + dp[i-2] + dp[i-3]。',
        answer: 'def climb3(n):\n    dp = [0, 1, 2, 4]\n    for i in range(4, n + 1):\n        dp.append(dp[i-1] + dp[i-2] + dp[i-3])\n    return dp[n]',
      ),
      PythonTask(
        prompt: '求最小花费爬楼梯（每阶有花费，每次可走 1 或 2 阶）。',
        hint: 'dp[i] = cost[i] + min(dp[i-1], dp[i-2])。',
        answer: 'def min_cost(cost):\n    n = len(cost)\n    a = b = 0\n    for c in cost:\n        a, b = b, min(a, b) + c\n    return min(a, b)',
      ),
    ],
  ),
  PythonTopic(
    id: 93,
    level: 'advanced',
    title: 'Python 093：动态规划进阶——0/1 背包',
    summary: '用二维/一维 DP 解决 0/1 背包，理解状态与容量维度。',
    concepts: ['0/1 背包', '状态转移', '空间优化', '逆序'],
    objective: '手写 0/1 背包的二维与一维实现，并回退出选取的物品。',
    prerequisites: ['动态规划入门'],
    explain:
        '0/1 背包：有 n 件物品，每件有重量 w 和价值 v，容量为 C，每件最多选一次，'
        '求最大价值。状态 dp[i][c] 表示「前 i 件、容量 c」的最大价值；对第 i 件，'
        '不选则继承 dp[i-1][c]，选则 dp[i-1][c-w]+v，二者取大。一维版本把第一维'
        '压掉，但容量必须逆序枚举，否则同一件物品会被重复选（就变成了完全背包）。'
        '用额外记录还可以回溯出到底选了哪几件。',
    code:
        r'''def knapsack_2d(weights, values, capacity):
    n = len(weights)
    dp = [[0] * (capacity + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        w, v = weights[i - 1], values[i - 1]
        for c in range(capacity + 1):
            dp[i][c] = dp[i - 1][c]
            if c >= w and dp[i - 1][c - w] + v > dp[i][c]:
                dp[i][c] = dp[i - 1][c - w] + v
    return dp[n][capacity]


def knapsack_1d(weights, values, capacity):
    dp = [0] * (capacity + 1)
    for w, v in zip(weights, values):
        for c in range(capacity, w - 1, -1):
            if dp[c - w] + v > dp[c]:
                dp[c] = dp[c - w] + v
    return dp[capacity]


weights = [2, 3, 4, 5]
values = [3, 4, 5, 6]
print(knapsack_2d(weights, values, 5))
print(knapsack_1d(weights, values, 5))
print(knapsack_1d(weights, values, 0))
print(knapsack_2d([1, 1, 1], [1, 2, 3], 2))
''',
    output:
        r'''7
7
0
5
''',
    pitfalls: [
      '一维版顺序枚举容量，同一物品被重复选（完全背包错误）。',
      'dp 维度少开 1，容量为 0 或满容量的边界算错。',
      '把重量和价值参数顺序写反，结果无意义。',
      '用贪心（按性价比）解 0/1 背包，不一定最优。',
    ],
    tasks: [
      PythonTask(
        prompt: '回溯出取得最大价值时选了哪些下标的物品。',
        hint: '从 dp[n][C] 往回走，若与 dp[i-1][c] 不同则说明选了第 i 件。',
        answer: 'def chosen(weights, values, capacity):\n    n = len(weights)\n    dp = [[0]*(capacity+1) for _ in range(n+1)]\n    for i in range(1, n+1):\n        w, v = weights[i-1], values[i-1]\n        for c in range(capacity+1):\n            dp[i][c] = dp[i-1][c]\n            if c >= w and dp[i-1][c-w]+v > dp[i][c]:\n                dp[i][c] = dp[i-1][c-w]+v\n    out, c = [], capacity\n    for i in range(n, 0, -1):\n        if dp[i][c] != dp[i-1][c]:\n            out.append(i-1)\n            c -= weights[i-1]\n    return out[::-1]',
      ),
      PythonTask(
        prompt: '把问题改成完全背包（每件可选无限次），如何改一维循环？',
        hint: '容量改为正序枚举。',
        answer: 'def unbounded(w, v, C):\n    dp = [0]*(C+1)\n    for c in range(1, C+1):\n        for i in range(len(w)):\n            if c >= w[i]:\n                dp[c] = max(dp[c], dp[c-w[i]]+v[i])\n    return dp[C]',
      ),
    ],
  ),
  PythonTopic(
    id: 94,
    level: 'advanced',
    title: 'Python 094：贪心算法',
    summary: '用局部最优解区间调度问题，并认识贪心失效的反例。',
    concepts: ['贪心', '区间调度', '最优子结构', '反例'],
    objective: '用「最早结束时间」贪心求最多不重叠区间，并验证其正确性。',
    prerequisites: ['动态规划进阶：0/1 背包'],
    explain:
        '贪心每一步都选当前看起来最好的，不回头。它对某些问题最优（如区间调度选'
        '「结束时间最早」的区间能证明最优），但对另一些问题不最优（如 0/1 背包按'
        '性价比贪心、或硬币找零在非规范面值下）。判断能否贪心需要证明「交换论证」：'
        '任何最优解都能改成以贪心选择开头的解。下面实现区间调度，并用找零反例说明'
        '贪心的局限。',
    code:
        r'''def max_intervals(intervals):
    ordered = sorted(intervals, key=lambda iv: iv[1])
    chosen = []
    last_end = None
    for start, end in ordered:
        if last_end is None or start >= last_end:
            chosen.append((start, end))
            last_end = end
    return chosen


def greedy_coins(amount, coins):
    coins = sorted(coins, reverse=True)
    used = []
    for c in coins:
        while amount >= c:
            amount -= c
            used.append(c)
    return used, amount


intervals = [(1, 3), (2, 4), (3, 5), (0, 6), (5, 7), (8, 9)]
print(max_intervals(intervals))
print(len(max_intervals(intervals)))
print(greedy_coins(63, [1, 5, 10, 20]))
print(greedy_coins(40, [1, 5, 10, 25, 40]))
print(greedy_coins(30, [1, 15, 25]))
''',
    output:
        r'''[(1, 3), (3, 5), (5, 7), (8, 9)]
4
([20, 20, 20, 1, 1, 1], 0)
([40], 0)
([25, 1, 1, 1, 1, 1], 0)
''',
    pitfalls: [
      '按开始时间而非结束时间排序，得不到最优。',
      '区间相接视为重叠，条件应写 start >= last_end。',
      '对找零等问题默认贪心必最优，实际上面值组合可能失败（此例 30 用 15+15 更优）。',
      '贪心选择后不更新状态，导致重复选同区间。',
    ],
    tasks: [
      PythonTask(
        prompt: '用暴力枚举验证区间调度贪心确实给出最优解。',
        hint: '对小规模枚举所有子集。',
        answer: '用组合枚举所有不重叠子集取最大个数对比。',
      ),
      PythonTask(
        prompt: '对 coins=[1,15,25] 写一个不贪心的反例，显示 30 需要几枚最优。',
        hint: '15+15 只需 2 枚，贪心用 25+1*5 需 6 枚。',
        answer: 'print(greedy_coins(30, [1, 15, 25]))  # 贪心 25+5*1\n# 最优 15+15 => 2 枚',
      ),
    ],
  ),
  PythonTopic(
    id: 95,
    level: 'advanced',
    title: 'Python 095：递归回溯——N 皇后',
    summary: '用回溯 + 剪枝求 8 皇后全部解，理解搜索空间。',
    concepts: ['回溯', '剪枝', '递归搜索', '冲突检测'],
    objective: '用逐行放置 + 冲突检查求 N 皇后的解数量。',
    prerequisites: ['贪心算法'],
    explain:
        '回溯是「试探 + 撤销」的深度优先搜索：每层做一个选择，不合法就剪枝，'
        '走到底就记录一个解，然后回退换下一个选择。N 皇后要求每行放一个皇后且'
        '任意两个不同列、不同对角线。用三个集合记录已被占用的列、主对角（row-col）'
        '与副对角（row+col），只需 O(1) 就能判断冲突，这就是剪枝。逐行递归，'
        '找到解就计数；解数增长很快（8 皇后有 92 个解）。',
    code:
        r'''def solve_n_queens(n):
    solutions = []
    cols = set()
    diag1 = set()
    diag2 = set()
    placed = []

    def backtrack(row):
        if row == n:
            solutions.append(list(placed))
            return
        for col in range(n):
            if col in cols or (row - col) in diag1 or (row + col) in diag2:
                continue
            cols.add(col)
            diag1.add(row - col)
            diag2.add(row + col)
            placed.append(col)
            backtrack(row + 1)
            placed.pop()
            cols.discard(col)
            diag1.discard(row - col)
            diag2.discard(row + col)

    backtrack(0)
    return solutions


for n in (4, 5, 6):
    sols = solve_n_queens(n)
    print("n=%d count=%d" % (n, len(sols)))
print("first 4-queens:", solve_n_queens(4)[0])
print("6-queens count:", len(solve_n_queens(6)))
''',
    output:
        r'''n=4 count=2
n=5 count=10
n=6 count=4
first 4-queens: [1, 3, 0, 2]
6-queens count: 4
''',
    pitfalls: [
      '回退时忘记从集合里 discard，后面的分支被错误剪掉。',
      '用列表存冲突信息导致判断 O(n)，失去剪枝优势。',
      '只记录列不记录对角线，会得到非法布局。',
      '递归到 row==n 后才回头处理放置，计数逻辑易错。',
    ],
    tasks: [
      PythonTask(
        prompt: '只求 8 皇后的解数量。',
        hint: '调 solve_n_queens(8) 取 len。',
        answer: 'print(len(solve_n_queens(8)))  # 92',
      ),
      PythonTask(
        prompt: '把解打印成棋盘（Q 与 .）。',
        hint: '每行的 col 位置放 Q。',
        answer: 'def show(sol):\n    for col in sol:\n        print("." * col + "Q" + "." * (len(sol) - col - 1))',
      ),
    ],
  ),
  PythonTopic(
    id: 96,
    level: 'advanced',
    title: 'Python 096：综合——迷宫求解',
    summary: '用 BFS 在网格迷宫中找最短路径，并输出路线。',
    concepts: ['网格', 'BFS', '最短路径', '路回溯'],
    objective: '用 BFS 求迷宫最短路径长度并重建路径。',
    prerequisites: ['递归回溯：N 皇后'],
    explain:
        '迷宫是网格图，每个可走格子与上下左右邻居相连。求「最短路径」用 BFS：'
        '从起点一层层扩展，第一次到达终点时的层数最短。关键在于同时记录每个格子'
        '的 parent，找到终点后从终点沿 parent 回退到起点，再反转就得到路径。'
        '这就是图搜索里「记录前驱」的通用技巧，前面 091 的 shortest_path 已经用过。'
        '下面用 0 表示通路、1 表示墙，输出路径长度与坐标序列。',
    code:
        r'''import collections


def solve_maze(grid, start, goal):
    rows = len(grid)
    cols = len(grid[0])
    queue = collections.deque((start,), 10000)
    parent = {start: None}
    while queue:
        cell = queue.popleft()
        if cell == goal:
            break
        r, c = cell
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and grid[nr][nc] == 0:
                if (nr, nc) not in parent:
                    parent[(nr, nc)] = cell
                    queue.append((nr, nc))
    if goal not in parent:
        return None
    path = []
    cur = goal
    while cur is not None:
        path.append(cur)
        cur = parent[cur]
    return path[::-1]


maze = [
    [0, 0, 0, 1, 0],
    [1, 1, 0, 1, 0],
    [0, 0, 0, 0, 0],
    [0, 1, 1, 1, 1],
    [0, 0, 0, 0, 0],
]
path = solve_maze(maze, (0, 0), (4, 4))
print("length:", len(path))
print(path)
print("steps:", len(path) - 1)
''',
    output:
        r'''length: 13
[(0, 0), (0, 1), (0, 2), (1, 2), (2, 2), (2, 1), (2, 0), (3, 0), (4, 0), (4, 1), (4, 2), (4, 3), (4, 4)]
steps: 12
''',
    pitfalls: [
      '返回 path 后忘了反转，得到从终点到起点的路径。',
      'BFS 未标记起点 visited，起点被重复入队。',
      '只关心长度不记录 parent，就无法重建路径。',
      '把边界检查写反，访问到负下标却又有合法元素。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计迷宫可达的格子数。',
        hint: 'BFS 结束后数 parent 长度。',
        answer: 'print(len(bfs_all(maze, (0, 0))))',
      ),
      PythonTask(
        prompt: '把 maze 里 2 视为可走的捷径，观察路径是否变短。',
        hint: '把通路判断改为 grid[r][c] != 1。',
        answer: '将条件 grid[nr][nc] == 0 改为 grid[nr][nc] != 1',
      ),
    ],
  ),
  PythonTopic(
    id: 97,
    level: 'advanced',
    title: 'Python 097：断言与契约',
    summary: '用 assert 表达前置/后置条件与不变量，尽早暴露错误。',
    concepts: ['assert', '前置条件', '后置条件', '不变量'],
    objective: '为函数写下可执行的契约，用 assert 捕获错误假设。',
    prerequisites: ['综合：迷宫求解'],
    explain:
        'assert 条件, 消息 在条件为假时抛 AssertionError。它最合适的用途是「断言'
        '程序内部的假设」：前置条件（调用方必须满足什么）、后置条件（返回时必须'
        '成立什么）、不变量（循环里始终为真）。断言不是错误处理——不要用它校验'
        '用户输入，因为优化模式下断言可能被剥离，而且断言失败是「程序有 bug」而非'
        '「输入不合法」。这里用断言保护二分查找与平均值函数的契约。',
    code:
        r'''def average(nums):
    assert len(nums) > 0, "需要非空列表"
    assert all(isinstance(n, (int, float)) for n in nums), "元素必须是数字"
    total = sum(nums)
    result = total / len(nums)
    assert min(nums) <= result <= max(nums), "均值应在极值之间"
    return result


def binary_search(data, target):
    assert data == sorted(data), "二分要求输入有序"
    lo, hi = 0, len(data) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if data[mid] == target:
            return mid
        if data[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1


print(average([10, 20, 30]))
print(binary_search([1, 2, 3, 4], 3))
for bad in ([], [1, "a"]):
    try:
        average(bad)
    except AssertionError as e:
        print("assertion:", e)
''',
    output:
        r'''20.0
2
assertion: 需要非空列表
assertion: 元素必须是数字
''',
    pitfalls: [
      '用 assert 做用户输入校验，发布时被剥离就失去保护。',
      '断言消息含糊（“出错”），调试时不知道哪个假设失败。',
      '把 assert 当 print 调试，忘了它会影响控制流。',
      '依赖有副作用的表达式（如 assert f()），重复求值造成不一致。',
    ],
    tasks: [
      PythonTask(
        prompt: '为一个返回两数相除的函数写下前置条件。',
        hint: '断言除数为非零。',
        answer: 'def divide(a, b):\n    assert b != 0, "除数不能为 0"\n    return a / b',
      ),
      PythonTask(
        prompt: '为排序函数的后置条件写断言。',
        hint: '断言结果为非递减序列。',
        answer: 'def my_sort(a):\n    r = sorted(a)\n    assert all(r[i] <= r[i+1] for i in range(len(r)-1))\n    return r',
      ),
    ],
  ),
  PythonTopic(
    id: 98,
    level: 'advanced',
    title: 'Python 098：手写测试框架',
    summary: '用函数名约定 + 运行器手写一个 mini 单元测试框架。',
    concepts: ['单元测试', '运行器', '汇总', '约定'],
    objective: '手写 test 运行器，自动发现并以汇总形式展示结果。',
    prerequisites: ['断言与契约'],
    explain:
        '测试框架的核心并不神秘：用一个约定（名字以 test_ 开头的函数就是用例）'
        '收集它们，逐个调用，捕获 AssertionError 记为失败、其它异常记为错误，'
        '最后汇总数量。下面手写 assert_equal，再写一个 run_tests(namespace) '
        '扫描 globals 里的 test_* 函数。可以看到 pytest 等工具本质上把这套流程'
        '做得更精细（装置、参数化、报错定位），但骨架就是这些。',
    code:
        r'''class TestFailure(Exception):
    pass


def assert_equal(actual, expected, message=""):
    if actual != expected:
        raise TestFailure("%s\n  预期: %r\n  实际: %r" % (
            message or "值不相等", expected, actual))


def assert_true(cond, message="条件应为真"):
    if not cond:
        raise TestFailure(message)


def add(a, b):
    return a + b


def is_prime(n):
    if n < 2:
        return False
    i = 2
    while i * i <= n:
        if n % i == 0:
            return False
        i += 1
    return True


def test_add():
    assert_equal(add(2, 3), 5, "2+3")
    assert_equal(add(-1, 1), 0)


def test_is_prime():
    assert_true(is_prime(2) and is_prime(13))
    assert_equal(is_prime(1), False, "1 不是质数")


def run_tests(namespace):
    passed = failed = 0
    for name in sorted(namespace):
        if name.startswith("test_"):
            try:
                namespace[name]()
                passed += 1
                print("PASS", name)
            except Exception as e:
                failed += 1
                print("FAIL", name)
                print("   ", str(e).replace("\n", "\n    "))
    print("结果: %d passed, %d failed" % (passed, failed))


run_tests(dict(globals()))
''',
    output:
        r'''PASS test_add
PASS test_is_prime
结果: 2 passed, 0 failed
''',
    pitfalls: [
      '捕获了所有异常（含 TestFailure）却不区分失败与错误。',
      '用例之间共享可变状态，执行顺序影响结果。',
      '测试里也写逻辑分支，使断言可能不被执行。',
      '忘记汇总，大堆通过日志里埋了一个失败难以发现。',
    ],
    tasks: [
      PythonTask(
        prompt: '增加一个故意失败的用例，确认汇总正确计数。',
        hint: '写 test_fail 断言 1==2。',
        answer: 'def test_fail():\n    assert_equal(1, 2, "故意失败")',
      ),
      PythonTask(
        prompt: '让 run_tests 返回 (passed, failed) 供上层组装。',
        hint: '在函数末尾 return。',
        answer: 'return passed, failed',
      ),
    ],
  ),
  PythonTopic(
    id: 99,
    level: 'advanced',
    title: 'Python 099：边界与异常测试',
    summary: '针对边界值与异常路径写测试，而不是只测典型输入。',
    concepts: ['边界值', '异常断言', '等价类', '鲁棒性'],
    objective: '为边界与非法输入写测试，验证函数失败得合理。',
    prerequisites: ['手写测试框架'],
    explain:
        '测典型输入只能证明「正常时对」，真正容易出错的是边界：空集合、单元素、'
        '恰好等于阈值、下限与上限。边界测试的要点是「三类值都试」：小于阈值、'
        '等于阈值、大于阈值，以及空与单元素。另一个易漏点是异常路径：函数在非法'
        '输入下应当抛出预期异常，而不是返回垃圾或默默失败。下面用 assert_raises '
        '专门检查抛错类型，并用阶乘/取整函数演示边界测试。',
    code:
        r'''class TestFailure(Exception):
    pass


def assert_equal(actual, expected, message=""):
    if actual != expected:
        raise TestFailure("%s: 预期 %r 实际 %r" % (message, expected, actual))


def assert_raises(exc_type, func, *args):
    try:
        func(*args)
    except exc_type:
        return True
    except Exception as e:
        raise TestFailure("抛了 %s 而不是 %s" % (type(e).__name__, exc_type.__name__))
    raise TestFailure("预期 %s 但未抛出" % exc_type.__name__)


def classify_score(score):
    if not 0 <= score <= 100:
        raise ValueError("分数应在 0..100")
    if score >= 90:
        return "A"
    if score >= 60:
        return "B"
    return "C"


def test_boundaries():
    assert_equal(classify_score(0), "C", "下限")
    assert_equal(classify_score(59), "C", "60 以下")
    assert_equal(classify_score(60), "B", "恰好及格")
    assert_equal(classify_score(89), "B", "90 以下")
    assert_equal(classify_score(90), "A", "恰好优秀")
    assert_equal(classify_score(100), "A", "上限")


def test_invalid():
    assert_raises(ValueError, classify_score, -1)
    assert_raises(ValueError, classify_score, 101)
    assert_raises(TypeError, classify_score, "100")


def run(namespace):
    passed = failed = 0
    for name in sorted(namespace):
        if name.startswith("test_"):
            try:
                namespace[name]()
                passed += 1
                print("PASS", name)
            except Exception as e:
                failed += 1
                print("FAIL", name, str(e))
    print("结果: %d passed, %d failed" % (passed, failed))


run(dict(globals()))
''',
    output:
        r'''PASS test_boundaries
PASS test_invalid
结果: 2 passed, 0 failed
''',
    pitfalls: [
      '只测正常值，边界一到就崩。',
      'assert_raises 宽泛地捕获 Exception，错的异常类型也能通过。',
      '比较字符串结果时忘了大小写/空格差异。',
      '把字符串 "100" 传给数值比较，内置解释器抛的是 TypeError 而不是 ValueError,'
          '写测试时要把两种类型分开断言。',
    ],
    tasks: [
      PythonTask(
        prompt: '为 classify_score 增加 59.9 与 60.0 的边界用例。',
        hint: '浮点也适用区间比较。',
        answer: 'assert_equal(classify_score(59.9), "C")\nassert_equal(classify_score(60.0), "B")',
      ),
      PythonTask(
        prompt: '写 assert_raises 的变体，同时返回异常对象供检查消息。',
        hint: '把 except 里的 e 返回。',
        answer: 'def raises_and_return(exc_type, func, *args):\n    try:\n        func(*args)\n    except exc_type as e:\n        return e\n    return None',
      ),
    ],
  ),
  PythonTopic(
    id: 100,
    level: 'advanced',
    title: 'Python 100：调试技巧',
    summary: '用二分定位与最小重现缩小 bug 范围。',
    concepts: ['调试', '二分定位', '最小重现', '观察点'],
    objective: '用可复现的探针与二分定位一个「总和不对」的 bug。',
    prerequisites: ['边界与异常测试'],
    explain:
        '调试不是随便插 print，而是有方法的二分：先确认「输入相同则输出相同」，'
        '再在流程中点插入观察点，判断错误是在前半段还是后半段产生，不断对半缩小'
        '范围。这里有一个计算平均分的小程序，故意在累加时漏掉最后一个元素。下面'
        '用一段「探针」代码在函数内打印每一步的累加值与期望值，很快定位到循环范围'
        ' off-by-one。实战中还要学会构造最小重现：把 bug 压缩到十几行以内。',
    code:
        r'''def buggy_average(scores):
    total = 0
    # 疑似 bug：range 少了最后一个元素
    for i in range(len(scores) - 1):
        total += scores[i]
    return total / len(scores)


def debug_average(scores):
    total = 0
    expected = 0
    for i in range(len(scores) - 1):
        total += scores[i]
        expected += scores[i]
        print("i=%d value=%d running=%d" % (i, scores[i], total))
    print("visited", len(scores) - 1, "of", len(scores), "elements")
    return total / len(scores)


scores = [80, 90, 100]
print("buggy:", buggy_average(scores))
print("probe:")
debug_average(scores)
fixed = sum(scores) / len(scores)
print("fixed:", fixed)
print("match:", buggy_average(scores) == fixed)
''',
    output:
        r'''buggy: 56.66666666666666
probe:
i=0 value=80 running=80
i=1 value=90 running=170
visited 2 of 3 elements
fixed: 90.0
match: False
''',
    pitfalls: [
      '一看到出错就随机改代码，没先定位根因。',
      '观察点设得太多，日志淹没关键信息。',
      '修复后不回归验证，仅凭「看起来好了」。',
      '把偶然正常当成修复，没构造稳定重现。',
    ],
    tasks: [
      PythonTask(
        prompt: '写一个函数 find_first_bug，用二分思路在大量数据中定位首个异常值。',
        hint: '若左半有异常就在左半继续，否则看右半。',
        answer: 'def find_first_bad(data):\n    lo, hi = 0, len(data) - 1\n    while lo < hi:\n        mid = (lo + hi) // 2\n        if has_bug(data[mid]):\n            hi = mid\n        else:\n            lo = mid + 1\n    return lo',
      ),
      PythonTask(
        prompt: '修复 buggy_average 并重新验证。',
        hint: '把 range 改成 range(len(scores))。',
        answer: 'def fixed_average(scores):\n    total = 0\n    for s in scores:\n        total += s\n    return total / len(scores)',
      ),
    ],
  ),
  PythonTopic(
    id: 101,
    level: 'advanced',
    title: 'Python 101：错误处理最佳实践',
    summary: '在合适的层次捕获与包装异常，保留原始上下文。',
    concepts: ['早失败', '异常包装', '上下文', '日志边界'],
    objective: '在边界处捕获低层异常并转换为领域异常。',
    prerequisites: ['调试技巧'],
    explain:
        '错误处理的要点是「在能处理的层次处理，不能处理就让它向上走」。有三条经'
        '验：早失败（参教不合法立即报错，不要带病运行）；边界转换（底层库/解析'
        '错误在边界处包成领域异常，上层不必知道库的细节）；不吞异常（捕获后要么'
        '处理要么用 raise 重新抛出，用 raise NewError(...) 时可以带上原始异常）。'
        '下面把一个字符串转整数的解析流程包成领域异常，保留原始错误信息。',
    code:
        r'''class ConfigError(Exception):
    pass


def parse_port(text):
    try:
        port = int(text)
    except ValueError as exc:
        raise ConfigError("端口不是整数: %r" % text) from exc
    if not 1 <= port <= 65535:
        raise ConfigError("端口超出范围: %d" % port)
    return port


def load_config(raw):
    config = {}
    for key, value in raw:
        if key == "port":
            config[key] = parse_port(value)
        elif key == "host":
            if not value:
                raise ConfigError("host 不能为空")
            config[key] = value
    return config


ok = load_config([("host", "localhost"), ("port", "8080")])
print(sorted(ok.items()))
for bad in [("port", "abc"), ("port", "70000"), ("host", "")]:
    try:
        load_config([bad])
    except ConfigError as e:
        print("ConfigError:", e)
''',
    output:
        r'''[('host', 'localhost'), ('port', 8080)]
ConfigError: 端口不是整数: 'abc'
ConfigError: 端口超出范围: 70000
ConfigError: host 不能为空
''',
    pitfalls: [
      '用 except Exception: pass 默默吞掉所有错误。',
      '捕获后不重新抛出，也不处理，错误无声消失。',
      '在底层抛领域异常，让库代码耦合业务。',
      '忘记 raise ... from exc 保留原始 traceback。',
    ],
    tasks: [
      PythonTask(
        prompt: '为 parse_port 加一个「端口被占用」的领域异常。',
        hint: '新增 PortInUse(ConfigError) 并在外部检查。',
        answer: 'class PortInUse(ConfigError):\n    pass',
      ),
      PythonTask(
        prompt: '让 load_config 遇到未知键时引发 ConfigError。',
        hint: '在 else 分支报错。',
        answer: 'else:\n    raise ConfigError("未知配置项: %s" % key)',
      ),
    ],
  ),
  PythonTopic(
    id: 102,
    level: 'advanced',
    title: 'Python 102：模块化与分层',
    summary: '把数据处理拆成数据层/逻辑层/展示层，降低耦合。',
    concepts: ['分层', '职责划分', '依赖方向', '接口'],
    objective: '把一个混在一起的函数拆成三层，便于替换与测试。',
    prerequisites: ['错误处理最佳实践'],
    explain:
        '分层是把「干什么」和「怎么做」分开：数据层负责存取与解析，逻辑层负责'
        '业务规则，展示层负责格式化输出。依赖方向应当单向：上层依赖下层，下层'
        '不反过来依赖上层的格式。好处是换数据源（从列表换成文件）不影响逻辑，'
        '换展示格式（文本换成 JSON）也不影响逻辑，且每层都能单独测试。下面把一'
        '个「混在一起」的销售汇总函数拆成 parse/aggregate/render 三层。',
    code:
        r'''import json


# --- 数据层：原始记录 -> 结构化数据 ---
def parse_records(lines):
    records = []
    for line in lines:
        name, price, qty = line.split(",")
        records.append({"name": name, "price": float(price), "qty": int(qty)})
    return records


# --- 逻辑层：与展示无关的纯计算 ---
def aggregate(records):
    totals = {}
    for r in records:
        key = r["name"]
        totals[key] = totals.get(key, 0) + r["price"] * r["qty"]
    return totals


# --- 展示层：把结果格式化 ---
def render_text(totals):
    return "\n".join("%s: %.2f" % (name, totals[name]) for name in sorted(totals))


def render_json(totals):
    pairs = [[k, totals[k]] for k in sorted(totals)]
    return json.dumps(pairs)


lines = ["apple,3.5,2", "banana,1.2,5", "apple,3.5,1"]
totals = aggregate(parse_records(lines))
print(render_text(totals))
print(render_json(totals))
print("names:", sorted(totals))
''',
    output:
        r'''apple: 10.50
banana: 6.00
[["apple", 10.5], ["banana", 6.0]]
names: ['apple', 'banana']
''',
    pitfalls: [
      '逻辑层里直接 print，导致无法复用也无法测试。',
      '数据层负责了业务计算，职责交叉。',
      '下层反向 import 上层的展示函数，形成循环依赖。',
      '把不同关注点堆在一个巨大函数里，改一处影响多处。',
    ],
    tasks: [
      PythonTask(
        prompt: '新增 render_csv(totals) 展示层函数。',
        hint: '按 name,value 每行输出。',
        answer: 'def render_csv(totals):\n    return "\\n".join("%s,%s" % (k, totals[k]) for k in sorted(totals))',
      ),
      PythonTask(
        prompt: '为 aggregate 写单元测试。',
        hint: '构造两条记录断言结果。',
        answer: 'def test_aggregate():\n    rs = parse_records(["a,2,3"])\n    assert aggregate(rs) == {"a": 6.0}',
      ),
    ],
  ),
  PythonTopic(
    id: 103,
    level: 'advanced',
    title: 'Python 103：配置与常量管理',
    summary: '把魔法数字集中为常量，并用配置字典驱动行为。',
    concepts: ['常量', '配置', '魔法数字', '默认值'],
    objective: '把散落的魔法数字提取为具名常量与默认配置。',
    prerequisites: ['模块化与分层'],
    explain:
        '代码里散落的数字（“超过 30 天就过期”、“重试 3 次”）叫魔法数字，读者'
        '不知道含义、改一处漏一处。做法是把它们集中定义成具名常量（习惯全大写），'
        '并用一个配置字典存放可调参数。配置合并要小心：直接用 dict.update 会改动'
        '原字典，应先拷贝。因为 MicroPython 没有 dict 合并展开语法（{**a, **b}），'
        '这里用一个手写 merge 函数。默认值应当可以在不改代码的情况下被覆盖。',
    code:
        r'''DEFAULT_CONFIG = {
    "retries": 3,
    "timeout_ms": 500,
    "verbose": False,
}


def merge(base, override):
    """返回新字典，不修改 base（MicroPython 无 {**a, **b}）。"""
    result = dict(base)
    result.update(override)
    return result


def make_client(overrides=None):
    config = merge(DEFAULT_CONFIG, overrides or {})
    return config


DEFAULT = make_client()
CUSTOM = make_client({"retries": 5, "verbose": True})
print("default retries:", DEFAULT["retries"])
print("custom retries:", CUSTOM["retries"])
print("default unchanged:", DEFAULT["retries"] == 3)
print("keys:", sorted(CUSTOM))


DAYS_PER_WEEK = 7
EXPIRY_DAYS = 30


def weeks_until_expiry(age_days):
    remaining = EXPIRY_DAYS - age_days
    return max(0, remaining) / DAYS_PER_WEEK


print("weeks left:", weeks_until_expiry(9))
print("expired:", weeks_until_expiry(40))
''',
    output:
        r'''default retries: 3
custom retries: 5
default unchanged: True
keys: ['retries', 'timeout_ms', 'verbose']
weeks left: 3.0
expired: 0.0
''',
    pitfalls: [
      '把可调参数写成散落的字面量，改需求时漏改。',
      'merge 直接改动了 base，默认配置被污染。',
      '常量名不够具体（MAX 不知是最大值还是最大长度）。',
      '用布尔参数控制行为大分叉，参数一多组合爆炸。',
    ],
    tasks: [
      PythonTask(
        prompt: '加一个配置键 max_items 并在 make_client 中提供默认值。',
        hint: '直接在 DEFAULT_CONFIG 加键。',
        answer: 'DEFAULT_CONFIG["max_items"] = 100',
      ),
      PythonTask(
        prompt: '写 config_value(config, key, fallback) 安全取值。',
        hint: '用 get 带默认值。',
        answer: 'def config_value(config, key, fallback):\n    return config.get(key, fallback)',
      ),
    ],
  ),
  PythonTopic(
    id: 104,
    level: 'advanced',
    title: 'Python 104：输入校验与防御式编程',
    summary: '在边界处集中校验输入，拒绝非法数据并给出可读错误。',
    concepts: ['防御式编程', '校验器', '错误累积', '规范化'],
    objective: '实现一个字段校验器，累积所有错误而不是遇错即停。',
    prerequisites: ['配置与常量管理'],
    explain:
        '防御式编程是在系统边界处不信任输入：类型、范围、格式、必填都要校。'
        '比「遇到第一个错就抛异常」更友好的是「收集全部错误一次性返回」，让用户'
        '一次修正所有问题。实现上用一个 errors 列表，每个校验失败就 append 一条'
        '带字段名的消息，最后统一返回。同时注意「规范化」：先 strip 空白、统一'
        '大小写，再做格式校验，避免因无关差异误判。',
    code:
        r'''def validate_user(raw):
    errors = []
    data = {}
    name = (raw.get("name") or "").strip()
    if len(name) < 2:
        errors.append("name: 至少 2 个字符")
    data["name"] = name

    age_raw = raw.get("age")
    if age_raw is None:
        errors.append("age: 必填")
    else:
        try:
            age = int(age_raw)
            if not 0 <= age <= 150:
                errors.append("age: 应在 0..150")
            data["age"] = age
        except (ValueError, TypeError):
            errors.append("age: 不是整数")

    email = (raw.get("email") or "").strip().lower()
    if "@" not in email or "." not in email.split("@")[-1]:
        errors.append("email: 格式非法")
    data["email"] = email
    return data, errors


good, errs = validate_user({"name": " Li ", "age": "30",
                            "email": "LI@Example.COM "})
print("ok:", sorted(good.items()))
print("errors:", errs)

bad, errs = validate_user({"name": "L", "age": "abc", "email": "nope"})
print("errors count:", len(errs))
for e in errs:
    print(" -", e)
''',
    output:
        r'''ok: [('age', 30), ('email', 'li@example.com'), ('name', 'Li')]
errors: []
errors count: 3
 - name: 至少 2 个字符
 - age: 不是整数
 - email: 格式非法
''',
    pitfalls: [
      '遇错即抛，用户要反复提交才能改完所有问题。',
      '先校验再 strip，空格导致长度判断错误。',
      '用 bool 误判：值 0 或空字符串被当成「未提供」。',
      '只校验不规范化，同名用户因大小写差异重复入库。',
    ],
    tasks: [
      PythonTask(
        prompt: '为 validate_user 增加手机号可选校验（以 1 开头的 11 位数字）。',
        hint: '用字符串方法与 len 检查。',
        answer: 'phone = raw.get("phone")\nif phone:\n    if not (len(phone) == 11 and phone[0] == "1" and phone.isdigit()):\n        errors.append("phone: 格式非法")\n    data["phone"] = phone',
      ),
      PythonTask(
        prompt: '写一个通用 require_fields(raw, names) 检查必填字段。',
        hint: '遍历 names 判断 key 是否存在且非空。',
        answer: 'def require_fields(raw, names):\n    return ["%s: 必填" % n for n in names if not raw.get(n)]',
      ),
    ],
  ),
  PythonTopic(
    id: 105,
    level: 'advanced',
    title: 'Python 105：日志式输出设计',
    summary: '用分级日志封装输出，让程序与测试都能控制噪声。',
    concepts: ['日志分级', '输出封装', '可关团', '结构化字段'],
    objective: '实现一个级别可调的日志器，替代散落的 print。',
    prerequisites: ['输入校验与防御式编程'],
    explain:
        '直接在业务代码里 print 有两个问题：无法按级别开关，也无法在测试时静默。'
        '做法是封装一个 Logger 类，持有 level 与一个 sink（输出函数），提供 '
        'debug/info/warn/error 方法，每条日志带上级别与主题。测试时把 sink 换成'
        '收集器就能断言日志内容，而不污染 stdout。日志级别用数字比较（DEBUG<INFO'
        '<WARN<ERROR），设置阈值就能统一控制噪声。生产环境还能把 sink 换成文件。',
    code:
        r'''LEVELS = {"DEBUG": 10, "INFO": 20, "WARN": 30, "ERROR": 40}


class Logger:
    def __init__(self, level="INFO", sink=None):
        self.threshold = LEVELS[level]
        self.sink = sink or print
        self.records = []

    def log(self, level, message):
        if LEVELS[level] < self.threshold:
            return
        line = "[%s] %s" % (level, message)
        self.records.append((level, message))
        self.sink(line)

    def debug(self, message):
        self.log("DEBUG", message)

    def info(self, message):
        self.log("INFO", message)

    def warn(self, message):
        self.log("WARN", message)

    def error(self, message):
        self.log("ERROR", message)


def divide(a, b, logger):
    logger.debug("divide %s %s" % (a, b))
    if b == 0:
        logger.error("divide by zero")
        return None
    result = a / b
    logger.info("result=%s" % result)
    return result


log = Logger("INFO")
divide(10, 2, log)
divide(1, 0, log)
quiet = Logger("ERROR")
print("quiet output:")
divide(4, 2, quiet)
print("quiet records:", quiet.records)
''',
    output:
        r'''[INFO] result=5.0
[ERROR] divide by zero
quiet output:
quiet records: []
''',
    pitfalls: [
      '日志字符串提前拼接，即便被过滤也付了格式化开销。',
      '日志里混入业务返回值，使日志成为控制流的一部分。',
      '每条日志都带密码/令牌等敏感信息。',
      '把 debug 当默认级别，生产日志被淹没。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 Logger 增加 FATAL 级别（比 ERROR 高）。',
        hint: '在 LEVELS 加映射。',
        answer: 'LEVELS["FATAL"] = 50',
      ),
      PythonTask(
        prompt: '把 sink 换成收集列表，验证测试时不输出。',
        hint: '传 sink=collected.append。',
        answer: 'collected = []\nlog = Logger("INFO", sink=collected.append)\nlog.info("hi")\nprint(collected)',
      ),
    ],
  ),
  PythonTopic(
    id: 106,
    level: 'advanced',
    title: 'Python 106：性能优化基础',
    summary: '用缓存、预计算与合适的数据结构避免重复劳动。',
    concepts: ['缓存', '预计算', '数据结构选型', '重复计算'],
    objective: '用缓存把重复的昂贵计算从 O(n) 降为 O(1)。',
    prerequisites: ['日志式输出设计'],
    explain:
        '优化的第一步不是把循环写得更短，而是「消除重复」。常见手段：缓存（同'
        '样输入只算一次）、预计算（把在循环里不变的表达式提到循环外）、选对数据'
        '结构（用 set 代替 list 做成员判断，O(1) vs O(n)）。但不要过早优化：先'
        '测量、找到真正的瓶颈再动手，否则只是把代码弄复杂。下面用「统计一段文本'
        '里哪些词出现在停用词表」演示 list vs set 与缓存带来的差异。',
    code:
        r'''def count_hits_slow(words, stopwords):
    # 每个词都线性扫描停用词列表：O(len(words) * len(stopwords))
    hits = 0
    in_list = []
    for w in words:
        if w in stopwords:
            hits += 1
            in_list.append(w)
    return hits, in_list


def count_hits_fast(words, stopwords):
    stop = set(stopwords)
    hits = 0
    in_set = []
    for w in words:
        if w in stop:
            hits += 1
            in_set.append(w)
    return hits, in_set


def cached_squares():
    cache = {}

    def square(n):
        if n not in cache:
            cache[n] = n * n
        return cache[n]

    return square, cache


words = ["the", "cat", "sat", "on", "the", "mat"]
stops = ["the", "on", "in", "at"]
print(count_hits_slow(words, stops))
print(count_hits_fast(words, stops))

square, cache = cached_squares()
for n in [3, 4, 3, 3, 4]:
    square(n)
print("cache:", sorted(cache.items()))
print("size:", len(cache))
''',
    output:
        r'''(3, ['the', 'on', 'the'])
(3, ['the', 'on', 'the'])
cache: [(3, 9), (4, 16)]
size: 2
''',
    pitfalls: [
      '过早优化循环体内的细节，却忽略算法复杂度。',
      '用 list 做大量成员判断，未换成 set/dict。',
      '每次调用都重建查找表，预计算白做了。',
      '缓存无上限增长，内存被耗尽。',
    ],
    tasks: [
      PythonTask(
        prompt: '把慢版和快版各跑 1000 次，比较循环次数差异。',
        hint: '统计 in 的执行次数。',
        answer: '给 count_hits_slow 加计数器即可观察差异。',
      ),
      PythonTask(
        prompt: '用预计算优化「每个数乘同一系数」的循环。',
        hint: '把系数乘法合并到一次。',
        answer: 'coefficient = base * 2\nresult = [x * coefficient for x in data]',
      ),
    ],
  ),
  PythonTopic(
    id: 107,
    level: 'advanced',
    title: 'Python 107：代码风格与可读性',
    summary: '用好命名、小函数与一致格式提升可读性。',
    concepts: ['命名', '单一职责', '格式一致', '可读性'],
    objective: '把一段可读性差的代码重构为清晰版本。',
    prerequisites: ['性能优化基础'],
    explain:
        '可读性是可以度量的工程属性。几条实用准则：命名说清意图（用 elapsed_ms '
        '而不是 t）、函数只干一件事、避免深层嵌套（早返回代替多层 if）、消除重复'
        '（相同逻辑只写一遍）、格式一致（缩进、空行、空格）。下面展示同一个逻辑的'
        '两种写法：一团乱麻版与重构版，并验证两者结果一致——重构不改变行为，只'
        '改善结构。',
    code:
        r'''def messy(data):
    r = []
    for i in range(len(data)):
        if data[i] is not None:
            if data[i] > 0:
                if data[i] % 2 == 0:
                    r.append(data[i] * data[i])
    return r


def clean(numbers):
    """返回所有正偶数的平方，忽略 None 与非正数。"""
    result = []
    for n in numbers:
        if n is None or n <= 0 or n % 2 != 0:
            continue
        result.append(n * n)
    return result


data = [2, None, -4, 5, 6, 0, 8, 3]
print("messy:", messy(data))
print("clean:", clean(data))
print("same:", messy(data) == clean(data))
print("clean count:", len(clean(data)))
''',
    output:
        r'''messy: [4, 36, 64]
clean: [4, 36, 64]
same: True
clean count: 3
''',
    pitfalls: [
      '用单字母或脱离语境的名字（data, tmp, x1）。',
      '多层嵌套 if 而不早返回，主逻辑沉在深处。',
      '重构时顺手改了行为，引入新 bug。',
      '一行塞多条语句，破坏可读性。',
      '用 f.__doc__ 读取文档串——内置 MicroPython 的函数没有 __doc__ 属性。',
    ],
    tasks: [
      PythonTask(
        prompt: '为 cool 版本写一行文档串并在任务答案里说明用途。',
        hint: '写在 def 下一行的三引号字符串。',
        answer: 'def clean(numbers):\n    """返回所有正偶数的平方。"""',
      ),
      PythonTask(
        prompt: '把 clean 拆成 is_positive_even 与 square 两个小函数。',
        hint: '提取谓词与变换。',
        answer: 'def is_positive_even(n):\n    return n is not None and n > 0 and n % 2 == 0\n\ndef square(n):\n    return n * n',
      ),
    ],
  ),
  PythonTopic(
    id: 108,
    level: 'advanced',
    title: 'Python 108：综合——可测试的小工具库',
    summary: '把字符串/数值工具做成模块，并配上一套自测。',
    concepts: ['工具库', '纯函数', '自测', '文档串'],
    objective: '实现一组纯函数工具，并为每个函数写测试。',
    prerequisites: ['代码风格与可读性'],
    explain:
        '一个「可测试的小工具库」具备三个特征：函数是纯函数（同样输入总得同样'
        '输出、无副作用）、每个函数只做一件事、有文档串说明契约。纯函数特别适合'
        '测试，因为没有环境依赖。下面实现 title_case、slugify、clamp、chunk 四个'
        '工具，再用前面的 run_tests 模式为每个写用例。注意 slugify 要处理多个连'
        '续分隔符与首尾分隔符，这是常见的边界陷阱。',
    code:
        r'''def title_case(text):
    """把每个单词首字母大写。"""
    return " ".join(w[:1].upper() + w[1:].lower() for w in text.split())


def slugify(text):
    """转成小写连字符串，合并连续分隔符并去掉首尾。"""
    safe = []
    for ch in text.lower():
        if ch.isalpha() or ch.isdigit():
            safe.append(ch)
        else:
            safe.append("-")
    joined = "".join(safe)
    while "--" in joined:
        joined = joined.replace("--", "-")
    return joined.strip("-")


def clamp(value, low, high):
    """把 value 限制在 [low, high] 区间内。"""
    if value < low:
        return low
    if value > high:
        return high
    return value


def chunk(seq, size):
    """把序列按 size 切块；size<=0 抛 ValueError。"""
    if size <= 0:
        raise ValueError("size 必须为正")
    return [seq[i:i + size] for i in range(0, len(seq), size)]


def run_tests():
    checks = [
        (title_case("hello world"), "Hello World"),
        (title_case("PYTHON is FUN"), "Python Is Fun"),
        (slugify("Hello, World!"), "hello-world"),
        (slugify("  A--B  "), "a-b"),
        (clamp(5, 1, 10), 5),
        (clamp(-3, 1, 10), 1),
        (clamp(99, 1, 10), 10),
        (chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]),
    ]
    passed = 0
    for actual, expected in checks:
        if actual == expected:
            passed += 1
        else:
            print("FAIL: %r != %r" % (actual, expected))
    print("%d/%d passed" % (passed, len(checks)))


run_tests()
print(slugify("Python 3.13 -- ready!"))
print(chunk(list(range(6)), 3))
''',
    output:
        r'''8/8 passed
python-3-13-ready
[[0, 1, 2], [3, 4, 5]]
''',
    pitfalls: [
      'slugify 不合并连续分隔符，得到 a--b。',
      '用 str.isalnum()——内置 MicroPython 没有这个方法，应改用 isalpha() or isdigit()。',
      'isalpha() 对汉字返回 False，想保留非 ASCII 字符需要单独处理。',
      'chunk 对 size<=0 不报错，无限循环或结果怪异。',
      'clamp 边界取反，low/high 颠倒时静默出错。',
      '测试只覆盖正常路径，边界（空串、单元素）未测。',
    ],
    tasks: [
      PythonTask(
        prompt: '为 slugify 增加「保留下划线」的选项。',
        hint: '把字母数字判断改为允许 _。',
        answer: 'if ch.isalpha() or ch.isdigit() or ch == "_":\n    safe.append(ch)',
      ),
      PythonTask(
        prompt: '为 chunk 增加 size 大于长度时的测试。',
        hint: 'chunk([1,2], 5) 应得 [[1,2]]。',
        answer: 'print(chunk([1, 2], 5))  # [[1, 2]]',
      ),
    ],
  ),
  PythonTopic(
    id: 109,
    level: 'advanced',
    title: 'Python 109：综合项目——命令行记账程序',
    summary: '用类 + 内存存储 + 序列化实现一个小型记账器。',
    concepts: ['项目结构', '类设计', '序列化', '金额精度'],
    objective: '实现支持添加/汇总/序列化的记账器，并验证状态一致。',
    prerequisites: ['综合：可测试的小工具库'],
    explain:
        '一个迷你记账器需要三个部分：数据模型（一笔交易：日期、类别、金额）、'
        '存储层（这里用内存列表模拟，真实场景换成 json 文件）、命令层（把字符串'
        '命令解析成操作）。金额用整数分存储可以避免浮点误差，这是财务软件的常见'
        '做法。汇总按类别分组，并区分收入与支出。项目型代码的关键是把「解析、执行、'
        '展示」拆开，测试时可以直接调用存储层而不经过命令字符串。',
    code:
        r'''import json


class Ledger:
    def __init__(self):
        self.entries = []

    def add(self, date, category, amount_cents):
        if amount_cents == 0:
            raise ValueError("金额不能为 0")
        self.entries.append({"date": date, "category": category,
                             "cents": amount_cents})

    def total(self):
        return sum(e["cents"] for e in self.entries)

    def by_category(self):
        totals = {}
        for e in self.entries:
            key = e["category"]
            totals[key] = totals.get(key, 0) + e["cents"]
        return totals

    def to_json(self):
        return json.dumps(self.entries)


ledger = Ledger()
ledger.add("2024-01-01", "salary", 800000)
ledger.add("2024-01-02", "food", -3500)
ledger.add("2024-01-03", "food", -4200)
ledger.add("2024-01-04", "rent", -250000)
print("total:", ledger.total())
for cat in sorted(ledger.by_category()):
    print(" %s: %d" % (cat, ledger.by_category()[cat]))
print("entries:", len(ledger.entries))
try:
    ledger.add("2024-01-05", "bad", 0)
except ValueError as e:
    print("rejected:", e)
print("serialized:", len(ledger.to_json()) > 0)
''',
    output:
        r'''total: 542300
 food: -7700
 rent: -250000
 salary: 800000
entries: 4
rejected: 金额不能为 0
serialized: True
''',
    pitfalls: [
      '用浮点数存金额，累加误差越积越大。',
      '命令解析与业务逻辑混在一起，难测试。',
      '分类汇总用固定字典取值，新类别 KeyError。',
      '序列化时不处理不可序列化对象，导出报错。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现 filter_by_category(name) 返回某类别的所有交易。',
        hint: '列表推导过滤。',
        answer: 'def filter_by_category(self, name):\n    return [e for e in self.entries if e["category"] == name]',
      ),
      PythonTask(
        prompt: '把总额格式化成「12.34」字符串（分为单位）。',
        hint: '分转元用 // 与 %。',
        answer: 'def pretty_total(self):\n    c = self.total()\n    return "%d.%02d" % (c // 100, abs(c) % 100)',
      ),
    ],
  ),
  PythonTopic(
    id: 110,
    level: 'advanced',
    title: 'Python 110：综合项目——学生成绩分析',
    summary: '从原始分数出发做统计、排名与分数段分布。',
    concepts: ['统计', '中位数', '排名', '分组'],
    objective: '手写均值/中位数/分数段统计，避免依赖缺失的模块。',
    prerequisites: ['综合项目：命令行记账程序'],
    explain:
        '成绩分析是统计的典型场景。均值容易被极端值拉高，中位数更稳健，所以两'
        '个都要算。中位数的关键在偶数个数据时取中间两个的平均值，且必须先排序。'
        '分数段统计用区间计数，先验证每个分数在合法范围。排名处理并列名次时，'
        '同名次共享序号（竞赛排名法）。这些统计逻辑手写一遍，比调用现成库更能理解'
        '边界处理。',
    code:
        r'''def mean(scores):
    return sum(scores) / len(scores)


def median(scores):
    ordered = sorted(scores)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return float(ordered[mid])
    return (ordered[mid - 1] + ordered[mid]) / 2


def distribution(scores, edges):
    buckets = [0] * (len(edges) + 1)
    for s in scores:
        placed = False
        for i, edge in enumerate(edges):
            if s < edge:
                buckets[i] += 1
                placed = True
                break
        if not placed:
            buckets[-1] += 1
    return buckets


def rank(scores):
    ordered = sorted(scores, reverse=True)
    ranks = {}
    for i, s in enumerate(ordered):
        if s not in ranks:
            ranks[s] = i + 1
    return ranks


scores = [88, 92, 79, 95, 67, 88, 100]
print("mean: %.2f" % mean(scores))
print("median:", median(scores))
print("dist [60,80,90]:", distribution(scores, [60, 80, 90]))
print("rank 88:", rank(scores)[88])
print("rank 100:", rank(scores)[100])
print("median even:", median([1, 2, 3, 4]))
''',
    output:
        r'''mean: 87.00
median: 88.0
dist [60,80,90]: [0, 2, 2, 3]
rank 88: 4
rank 100: 1
median even: 2.5
''',
    pitfalls: [
      '中位数忘排序，结果完全错误。',
      '偶数个数据取 mid 而不是 mid-1/mid 平均。',
      '并列名次连号递增，排名语义错误。',
      '分数段边界用 <= 还是 < 不统一，导致漏计。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现标准差（总体）。',
        hint: '先求均值，再对偏差平方求和开根。',
        answer: 'import math\n\ndef stdev(xs):\n    m = mean(xs)\n    return math.sqrt(sum((x - m) ** 2 for x in xs) / len(xs))',
      ),
      PythonTask(
        prompt: '统计各分数段的人数占总人数比例。',
        hint: '用 distribution 结果除以 len。',
        answer: 'def ratios(scores, edges):\n    d = distribution(scores, edges)\n    return [round(x / len(scores), 3) for x in d]',
      ),
    ],
  ),
  PythonTopic(
    id: 111,
    level: 'advanced',
    title: 'Python 111：综合项目——文本冒险游戏',
    summary: '用状态机与字典驱动一个可脚本化验证的文本游戏。',
    concepts: ['状态机', '场景图', '字典驱动', '命令映射'],
    objective: '实现一个无阻塞的文本冒险，用脚本指令验证结局。',
    prerequisites: ['综合项目：学生成绩分析'],
    explain:
        '文本冒险的核心是一个状态机：每个房间有描述和可走的方向，玩家发出命令'
        '改变当前状态。为了让游戏可测试，把「读输入」与「处理命令」分开：handle '
        '接受一个命令字符串并返回结果文本，主循环负责读入。这样测试可以传入一串'
        '预设命令验证最终状态与背包。用字典存地图 (room, direction) -> room，'
        '查找 O(1)；物品拾取要验证是否在当前房间。',
    code:
        r'''class Game:
    def __init__(self):
        self.rooms = {
            "hall": {"desc": "hall", "items": ["key"],
                     "exits": {"north": "library"}},
            "library": {"desc": "library", "items": ["book"],
                        "exits": {"south": "hall", "east": "vault"}},
            "vault": {"desc": "vault", "items": ["gold"], "exits": {}},
        }
        self.current = "hall"
        self.bag = []
        self.done = False

    def handle(self, command):
        parts = command.split()
        verb = parts[0]
        room = self.rooms[self.current]
        if verb == "look":
            return "%s: %s" % (room["desc"], ",".join(room["items"]) or "empty")
        if verb == "take" and len(parts) == 2:
            item = parts[1]
            if item in room["items"]:
                room["items"].remove(item)
                self.bag.append(item)
                return "took " + item
            return "no " + item
        if verb == "go" and len(parts) == 2:
            direction = parts[1]
            target = room["exits"].get(direction)
            if target is None:
                return "blocked"
            if target == "vault" and "key" not in self.bag:
                return "locked"
            self.current = target
            return "moved to " + target
        if verb == "win":
            if self.current == "vault" and "gold" in self.bag:
                self.done = True
                return "YOU WIN"
            return "not yet"
        return "unknown"


script = ["look", "take key", "go north", "take book", "go east",
          "take gold", "win"]
game = Game()
for cmd in script:
    print("%s -> %s" % (cmd, game.handle(cmd)))
print("bag:", game.bag)
print("won:", game.done)
''',
    output:
        r'''look -> hall: key
take key -> took key
go north -> moved to library
take book -> took book
go east -> moved to vault
take gold -> took gold
win -> YOU WIN
bag: ['key', 'book', 'gold']
won: True
''',
    pitfalls: [
      '命令解析不做长度校验，parts[1] 越界。',
      '地图用嵌套 if 硬编码，加房间要改多处。',
      '物品拾取不检查是否在房间，可从任意处拿走。',
      '把 input() 直接写在逻辑里，游戏无法脚本化测试。',
    ],
    tasks: [
      PythonTask(
        prompt: '增加一个「drop」命令，把物品放回当前房间。',
        hint: '从 bag 移除并 append 到 room items。',
        answer: 'if verb == "drop" and len(parts) == 2:\n    item = parts[1]\n    if item in self.bag:\n        self.bag.remove(item)\n        room["items"].append(item)\n        return "dropped " + item\n    return "not carried"',
      ),
      PythonTask(
        prompt: '实现 inventory 命令列出背包。',
        hint: '返回 join(self.bag)。',
        answer: 'if verb == "inventory":\n    return ",".join(self.bag) or "empty"',
      ),
    ],
  ),
  PythonTopic(
    id: 112,
    level: 'advanced',
    title: 'Python 112：综合项目——矩阵与线性代数入门',
    summary: '用嵌套列表实现矩阵乘法、转置与行列式。',
    concepts: ['矩阵', '转置', '矩阵乘法', '行列式'],
    objective: '手写矩阵乘法与转置，并处理维度不匹配。',
    prerequisites: ['综合项目：文本冒险游戏'],
    explain:
        '矩阵用「列表的列表」表示，matrix[i][j] 是第 i 行第 j 列。矩阵乘法的前提'
        '是左矩阵的列数等于右矩阵的行数，结果 C[i][j] = sum(A[i][k] * B[k][j])。'
        '转置把行列互换。三个易错点：维度检查、空矩阵、以及用引用而非新列表导致'
        '结果矩阵各行共享同一列表。下面用 [[0]*n for _ in range(m)] 构造独立行，'
        '并顺便实现 2x2 行列式。',
    code:
        r'''def zeros(rows, cols):
    return [[0] * cols for _ in range(rows)]


def transpose(matrix):
    rows = len(matrix)
    cols = len(matrix[0])
    result = zeros(cols, rows)
    for i in range(rows):
        for j in range(cols):
            result[j][i] = matrix[i][j]
    return result


def matmul(a, b):
    n, m = len(a), len(a[0])
    m2, p = len(b), len(b[0])
    if m != m2:
        raise ValueError("shape %dx%d vs %dx%d" % (n, m, m2, p))
    result = zeros(n, p)
    for i in range(n):
        for j in range(p):
            total = 0
            for k in range(m):
                total += a[i][k] * b[k][j]
            result[i][j] = total
    return result


def det2(matrix):
    return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]


a = [[1, 2], [3, 4]]
b = [[5, 6], [7, 8]]
print("transpose:", transpose(a))
print("product:", matmul(a, b))
print("identity:", matmul(a, [[1, 0], [0, 1]]))
print("det a:", det2(a))
try:
    matmul([[1, 2, 3]], [[1, 2]])
except ValueError as e:
    print("error:", e)
''',
    output:
        r'''transpose: [[1, 3], [2, 4]]
product: [[19, 22], [43, 50]]
identity: [[1, 2], [3, 4]]
det a: -2
error: shape 1x3 vs 1x2
''',
    pitfalls: [
      '用 [[0]*cols]*rows 构造，各行指向同一列表。',
      '矩阵乘法三层循环下标写混，行列搞反。',
      '不做维度检查，直接索引越界。',
      '空矩阵访问 matrix[0] 报 IndexError。',
    ],
    tasks: [
      PythonTask(
        prompt: '实现矩阵加法（同维度）。',
        hint: '逐元素相加，先校验形状。',
        answer: 'def matadd(a, b):\n    if len(a) != len(b) or len(a[0]) != len(b[0]):\n        raise ValueError("shape mismatch")\n    return [[a[i][j] + b[i][j] for j in range(len(a[0]))]\n            for i in range(len(a))]',
      ),
      PythonTask(
        prompt: '用递归实现任意阶行列式。',
        hint: '拉普拉斯展开，按第一行展开。',
        answer: 'def det(m):\n    n = len(m)\n    if n == 1:\n        return m[0][0]\n    if n == 2:\n        return det2(m)\n    total = 0\n    for j in range(n):\n        minor = [row[:j] + row[j+1:] for row in m[1:]]\n        total += ((-1) ** j) * m[0][j] * det(minor)\n    return total',
      ),
    ],
  ),
  PythonTopic(
    id: 113,
    level: 'advanced',
    title: 'Python 113：综合项目——简易正则日志分析',
    summary: '用 re 的子集预处理日志并统计状态码分布。',
    concepts: ['re 子集', 'sub', '日志解析', '分组统计'],
    objective: '在 re 部分可用（无 findall/split）的限制下完成日志统计。',
    prerequisites: ['综合项目：矩阵与线性代数入门'],
    explain:
        '内置 MicroPython 的 re 是部分可用的：sub、compile、match、search 都能用'
        '（match 返回匹配对象），但不支持 findall、split。因此本篇策略是「用 '
        're.sub 做规范化，用手写扫描做抽取」：先用 '
        're.compile(r"\\s+").sub(" ", line) 把多余空白压成单个空格，再用 split '
        '按空格取字段。状态码是纯整数，直接 int() 转换。统计用字典累加，输出前 '
        '排序，不依赖字典顺序。这是「在模块能力子集内工作」的典型工程取舍。',
    code:
        r'''import re

SPACES = re.compile(r"\s+")

RAW_LOGS = [
    "2024-01-01   GET  /a   200",
    "2024-01-02  POST   /b   500",
    "2024-01-03\tGET\t/a\t200",
    "2024-01-04  GET   /c   404",
    "2024-01-05  GET   /a   200",
]


def normalize(line):
    return SPACES.sub(" ", line.strip())


def parse(line):
    parts = normalize(line).split(" ")
    if len(parts) != 4:
        return None
    return {"date": parts[0], "method": parts[1],
            "path": parts[2], "status": int(parts[3])}


def status_distribution(records):
    dist = {}
    for r in records:
        if r:
            dist[r["status"]] = dist.get(r["status"], 0) + 1
    return dist


def path_hits(records):
    hits = {}
    for r in records:
        if r and r["status"] < 400:
            hits[r["path"]] = hits.get(r["path"], 0) + 1
    return hits


records = [parse(line) for line in RAW_LOGS]
print("normalized:", normalize(RAW_LOGS[2]))
for code in sorted(status_distribution(records)):
    print("status %d: %d" % (code, status_distribution(records)[code]))
for path in sorted(path_hits(records)):
    print("path %s: %d" % (path, path_hits(records)[path]))
print("bad line:", parse("garbage input"))
''',
    output:
        r'''normalized: 2024-01-03 GET /a 200
status 200: 3
status 404: 1
status 500: 1
path /a: 3
bad line: None
''',
    pitfalls: [
      '用 re.findall/split，内置直接报 AttributeError。',
      '用 split() 无参时把制表符也算进去，需先 normalize 统一空白。',
      '脏行不返回 None 而直接索引，解析崩溃。',
      '统计输出依赖字典顺序，换个构建结果就变。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计每个方法的请求数。',
        hint: '仿照 path_hits 按 method 累加。',
        answer: 'def method_hits(records):\n    hits = {}\n    for r in records:\n        if r:\n            hits[r["method"]] = hits.get(r["method"], 0) + 1\n    return hits',
      ),
      PythonTask(
        prompt: '用 re.sub 把日期中的 - 替换为 /。',
        hint: 're.compile("-").sub("/", s)。',
        answer: 'import re\nprint(re.compile("-").sub("/", "2024-01-03"))',
      ),
    ],
  ),
  PythonTopic(
    id: 114,
    level: 'advanced',
    title: 'Python 114：综合项目——数值模拟',
    summary: '用随机数模拟股价随机游走并统计分布。',
    concepts: ['随机模拟', '随机游走', 'seed', '回撤'],
    objective: '用 random.seed 做可重现的随机游走，统计最大值与回撤。',
    prerequisites: ['综合项目：简易正则日志分析'],
    explain:
        '随机游走是最简单的数值模型：每一步价格乘以一个围绕 1 上下波动的因子。'
        '为让结果可重现，必须先 random.seed(固定值)，这样同一段代码每次得到相同'
        '序列，测试才能断言。模拟中要追踪两个派生指标：历史最大值（用于计算从峰'
        '值回撤）和最终收益。回撤是金融里衡量风险的常用量。下面用列表保存完整路径，'
        '再手写 max 与回撤计算，避免依赖缺失的统计模块。',
    code:
        r'''import random


def simulate(start, days, drift=0.001, vol=0.02, seed=42):
    random.seed(seed)
    prices = [start]
    price = start
    for _ in range(days):
        change = random.uniform(-vol, vol) + drift
        price = round(price * (1 + change), 2)
        if price < 1:
            price = 1.0
        prices.append(price)
    return prices


def max_drawdown(prices):
    peak = prices[0]
    worst = 0.0
    for p in prices:
        if p > peak:
            peak = p
        drop = (peak - p) / peak
        if drop > worst:
            worst = drop
    return worst


path = simulate(100.0, 10)
print("path:", path)
print("final:", path[-1])
print("peak:", max(path))
print("return pct: %.2f" % ((path[-1] / path[0] - 1) * 100))
print("max drawdown: %.4f" % max_drawdown(path))
same = simulate(100.0, 10)
print("reproducible:", same == path)
''',
    output:
        r'''path: [100.0, 101.74, 101.96, 102.82, 101.28, 103.39, 104.99, 106.74, 108.47, 109.15, 109.19]
final: 109.19
peak: 109.19
return pct: 9.19
max drawdown: 0.0150
reproducible: True
''',
    pitfalls: [
      '不设 seed，结果不可重现，测试无法断言。',
      '用 random.random() 又忘记映射范围，波动远大于预期。',
      '价格可能跌成负数，需加下限保护。',
      '回撤用当前值减峰值而不除峰值，不同价位不可比。',
    ],
    tasks: [
      PythonTask(
        prompt: '统计路径中上涨的天数。',
        hint: '相邻比较计数。',
        answer: 'def up_days(prices):\n    return sum(1 for i in range(1, len(prices))\n               if prices[i] > prices[i-1])',
      ),
      PythonTask(
        prompt: '用 random.gauss 代替 uniform 生成波动。',
        hint: 'random.gauss(0, vol)。',
        answer: 'change = random.gauss(0, vol) + drift',
      ),
    ],
  ),
  PythonTopic(
    id: 115,
    level: 'advanced',
    title: 'Python 115：综合项目——JSON 数据 API 模拟',
    summary: '模拟一个内存 API：路由、请求/响应与序列化。',
    concepts: ['路由', '请求响应', '序列化', '状态码'],
    objective: '实现一个内存 API 调度器，支持增查与错误码。',
    prerequisites: ['综合项目：数值模拟'],
    explain:
        '即使是内存版的「API」，也要遵循同样的契约：方法 + 路径定位处理器，返回'
        '（状态码, 响应体）元组。让每个处理器接收参数字典并返回 JSON 可序列化的'
        '结构，调度器负责把路由表与实际请求匹配。错误也走正常返回值（404/400），'
        '而不是抛异常，这样调用方可以像处理响应一样处理失败。序列化统一用 '
        'json.dumps，注意 MicroPython 不支持 sort_keys，要排序就自己组装。',
    code:
        r'''import json


class Api:
    def __init__(self):
        self.routes = {}
        self.store = {}
        self.next_id = 1

    def route(self, method, path, handler):
        self.routes[(method, path)] = handler

    def call(self, method, path, body=None):
        handler = self.routes.get((method, path))
        if handler is None:
            return 404, {"error": "not found"}
        return handler(body or {})

    def create_item(self, body):
        name = body.get("name")
        if not name:
            return 400, {"error": "name required"}
        item_id = self.next_id
        self.next_id += 1
        self.store[item_id] = {"id": item_id, "name": name}
        return 201, self.store[item_id]

    def get_item(self, body):
        item_id = body.get("id")
        if item_id not in self.store:
            return 404, {"error": "missing"}
        return 200, self.store[item_id]

    def list_items(self, body):
        ids = sorted(self.store)
        return 200, [self.store[i] for i in ids]


api = Api()
api.route("POST", "/items", api.create_item)
api.route("GET", "/items", api.list_items)
api.route("GET", "/item", api.get_item)

print(api.call("POST", "/items", {"name": "pen"}))
print(api.call("POST", "/items", {"name": "book"}))
print(api.call("POST", "/items", {}))
print(api.call("GET", "/items"))
print(api.call("GET", "/item", {"id": 2}))
print(api.call("GET", "/item", {"id": 9}))
print(api.call("DELETE", "/items"))
print("count:", len(api.store))
''',
    output:
        r'''(201, {'id': 1, 'name': 'pen'})
(201, {'id': 2, 'name': 'book'})
(400, {'error': 'name required'})
(200, [{'id': 1, 'name': 'pen'}, {'id': 2, 'name': 'book'}])
(200, {'id': 2, 'name': 'book'})
(404, {'error': 'missing'})
(404, {'error': 'not found'})
count: 2
''',
    pitfalls: [
      '路由用字符串拼接匹配，参数化路径难处理。',
      '错误路径抛异常而非返回错误码，调用方需两套处理。',
      'id 用列表长度生成，删除后会重号。',
      '序列化时直接 dump 自定义对象，报不可序列化。',
    ],
    tasks: [
      PythonTask(
        prompt: '新增 DELETE /item 路由删除指定 id。',
        hint: '检查存在后 pop。',
        answer: 'def delete_item(self, body):\n    item_id = body.get("id")\n    if item_id not in self.store:\n        return 404, {"error": "missing"}\n    removed = self.store.pop(item_id)\n    return 200, removed',
      ),
      PythonTask(
        prompt: '让 list_items 支持按 name 排序。',
        hint: '用 sorted(key=lambda x: x["name"])。',
        answer: 'return 200, sorted((self.store[i] for i in ids), key=lambda x: x["name"])',
      ),
    ],
  ),
  PythonTopic(
    id: 116,
    level: 'advanced',
    title: 'Python 116：编程范式总览',
    summary: '用同一个需求对比过程式、面向对象与函数式三种写法。',
    concepts: ['过程式', '面向对象', '函数式', '范式选择'],
    objective: '对同一任务写出三种范式实现，理解各自适用场景。',
    prerequisites: ['综合项目：JSON 数据 API 模拟'],
    explain:
        '过程式把步骤依次写出，适合简单脚本；面向对象把数据和操作绑在一起，'
        '适合有多个状态实体、需要保持不变量；函数式把计算描述成纯函数的组合，'
        '适合数据转换管道，便于并行与测试。三者不是互斥的：Python 允许混用。'
        '下面用「给订单列表算总额并验证」这一任务，分别用三种写法实现，验证结果'
        '一致。选择范式的标准是「哪种让不变量最少、测试最容易、改动影响最小」。',
    code:
        r'''orders = [
    {"id": 1, "price": 10.0, "qty": 2, "paid": True},
    {"id": 2, "price": 5.5, "qty": 4, "paid": False},
    {"id": 3, "price": 20.0, "qty": 1, "paid": True},
]


# 1) 过程式：按步骤循环计算
def total_procedural(items):
    total = 0.0
    for o in items:
        if o["paid"]:
            total += o["price"] * o["qty"]
    return total


# 2) 面向对象：把订单与规则封装在类里
class Order:
    def __init__(self, price, qty, paid):
        self.price = price
        self.qty = qty
        self.paid = paid

    def amount(self):
        return self.price * self.qty if self.paid else 0.0


class Cart:
    def __init__(self, orders):
        self.orders = orders

    def total(self):
        return sum(o.amount() for o in self.orders)


# 3) 函数式：过滤 + 映射 + 折叠
def total_functional(items):
    paid = filter(lambda o: o["paid"], items)
    amounts = map(lambda o: o["price"] * o["qty"], paid)
    total = 0.0
    for a in amounts:
        total += a
    return total


cart = Cart([Order(o["price"], o["qty"], o["paid"]) for o in orders])
proc = total_procedural(orders)
obj = cart.total()
func = total_functional(orders)
print("procedural:", proc)
print("oop:       ", obj)
print("functional:", func)
print("all equal:", proc == obj == func)
''',
    output:
        r'''procedural: 40.0
oop:        40.0
functional: 40.0
all equal: True
''',
    pitfalls: [
      '为了用某范式而硬套，可读性反而下降。',
      '函数式里混入有副作用（修改外部变量）的操作。',
      'OOP 把纯计算包成不需要状态的类，过度设计。',
      '三套实现的结果因精度不同而不一致，却未加断言。',
    ],
    tasks: [
      PythonTask(
        prompt: '用生成器表达式重写 total_functional。',
        hint: 'sum(o["price"]*o["qty"] for o in items if o["paid"])。',
        answer: 'def total_gen(items):\n    return sum(o["price"] * o["qty"] for o in items if o["paid"])',
      ),
      PythonTask(
        prompt: '为 Cart 增加 discount_by_category(rate_by_category) 方法：'
            '按每笔订单的 category 应用对应比例，返回折后总额。',
        hint: '先给 Order 加 category 属性；方法内对每笔订单取 '
            'rate_by_category.get(category, 0) 算出折后金额再求和。',
        answer: 'class Order:\n    def __init__(self, price, qty, paid, category="misc"):\n        self.price = price\n        self.qty = qty\n        self.paid = paid\n        self.category = category\n\n    def amount(self):\n        return self.price * self.qty if self.paid else 0.0\n\n\nclass Cart:\n    def __init__(self, orders):\n        self.orders = orders\n\n    def total(self):\n        return sum(o.amount() for o in self.orders)\n\n    def discount_by_category(self, rate_by_category):\n        total = 0.0\n        for o in self.orders:\n            rate = rate_by_category.get(o.category, 0.0)\n            total += o.amount() * (1 - rate)\n        return total\n\n\ncart = Cart([Order(10.0, 2, True, "book"),\n             Order(5.5, 4, True, "food")])\nprint(cart.discount_by_category({"book": 0.5}))  # food 无折扣',
      ),
    ],
  ),
  PythonTopic(
    id: 117,
    level: 'advanced',
    title: 'Python 117：通往 CPython——标准库生态',
    summary: '介绍 pip、venv 与 PyPI：为什么真实项目需要它们。',
    concepts: ['CPython', 'pip', 'venv', 'PyPI', '标准库 vs 第三方'],
    objective: '理解内置解释器与 CPython 生态的差异，会描述依赖管理流程。',
    prerequisites: ['编程范式总览'],
    runtime: PythonRuntime.cpython,
    explain:
        '本篇需要外部 CPython 环境（不在内置 MicroPython 运行）。内置解释器'
        '只带一个很小的模块子集，没有 os、datetime、threading、dataclasses 等，'
        '更不能安装第三方包。真实项目的 Python（CPython）除了庞大标准库，还有 '
        'PyPI 上数十万个包，用 pip 安装、用 venv 隔离环境、用 requirements.txt '
        '或 pyproject.toml 锁定版本。理解这条链路（venv -> pip install -> import）'
        '是从「能写脚本」到「能交付项目」的关键一步。下面的代码只在 CPython 下'
        '运行，用来展示标准库与第三方包的边界，以及如何用 importlib/sys 探测环境。',
    code:
        r'''import sys
import sysconfig
import importlib
import importlib.util

print("executable kind:", sys.executable.rsplit("\\", 1)[-1].rsplit("/", 1)[-1])
print("version:", "%d.%d.%d" % sys.version_info[:3])
print("is_cpython:", sys.implementation.name == "cpython")

stdlib_modules = ["os", "datetime", "threading", "asyncio", "dataclasses"]
all_available = True
for name in stdlib_modules:
    available = importlib.util.find_spec(name) is not None
    all_available = all_available and available
    print("stdlib %-12s -> %s" % (name, available))
print("all stdlib present:", all_available)

os_module = importlib.import_module("datetime")
print("dynamic import:", os_module.date(2024, 1, 1).isoformat())
print("search paths > 0:", len(sys.path) > 0)
print("platform tag:", sysconfig.get_platform())
''',
    output:
        r'''executable kind: python.exe
version: 3.13.3
is_cpython: True
stdlib os           -> True
stdlib datetime     -> True
stdlib threading    -> True
stdlib asyncio      -> True
stdlib dataclasses  -> True
all stdlib present: True
dynamic import: 2024-01-01
search paths > 0: True
platform tag: win-amd64
''',
    pitfalls: [
      '以为内置 MicroPython 能 import requests 或安装包。',
      '在系统 Python 里直接 pip install 而不建 venv，污染全局环境。',
      '只装包不锁定版本，部署时依赖漂移。',
      '把第三方包探测结果写进程序的必要路径，缺失时直接崩。',
    ],
    tasks: [
      PythonTask(
        prompt: '描述创建一个隔离环境并安装依赖的两条命令。',
        hint: 'python -m venv .venv；再激活后 pip install。',
        answer: 'python -m venv .venv\n# 激活后： pip install requests',
      ),
      PythonTask(
        prompt: '写一段代码打印当前解释器支持的所有内置模块数量。',
        hint: 'len(sys.builtin_module_names)。',
        answer: 'import sys\nprint(len(sys.builtin_module_names))',
      ),
    ],
  ),
  PythonTopic(
    id: 118,
    level: 'advanced',
    title: 'Python 118：通往 CPython——类型注解与 dataclasses',
    summary: '用 typing 与 dataclasses 写出自带文档与自动样板的数据模型。',
    concepts: ['类型注解', 'typing', 'dataclasses', 'field', '默认值'],
    objective: '用 @dataclass 与类型注解定义一个带校验的数据模型。',
    prerequisites: ['通往 CPython：标准库生态'],
    runtime: PythonRuntime.cpython,
    explain:
        '本篇需要外部 CPython 环境。类型注解（x: int）在 CPython 里默认不在'
        '运行时强制检查，但能被 mypy/pyright 静态检查、被 IDE 提示、被 dataclasses '
        '用来生成代码。@dataclass 根据类里的注解自动生成 __init__、__repr__、'
        '__eq__，field(default_factory=...) 能安全地给可变默认值（避免共享列表'
        '陷阱）；frozen=True 还能生成不可变对象。这些都是内置 MicroPython 没有的，'
        '所以本课必须在 CPython 下运行。下面的代码用 dataclass 建一个订单模型，'
        '并演示排序与默认值工厂。',
    code:
        r'''from dataclasses import dataclass, field
from typing import List


@dataclass(order=True)
class Item:
    name: str
    price: float
    qty: int = 1

    def amount(self) -> float:
        return self.price * self.qty


@dataclass
class Order:
    order_id: int
    items: List[Item] = field(default_factory=list)

    def total(self) -> float:
        return sum(item.amount() for item in self.items)


order = Order(order_id=1)
order.items.append(Item("pen", 2.5, 3))
order.items.append(Item("book", 12.0))
print(order)
print("total:", order.total())
print("eq:", Item("pen", 2.5, 3) == Item("pen", 2.5, 3))
print("sorted:", sorted([Item("b", 5), Item("a", 5), Item("c", 1)]))
print("two orders isolated:", Order(2).items == [])
print("frozen test:")


@dataclass(frozen=True)
class Point:
    x: int
    y: int


p = Point(1, 2)
print(p, hash(p) == hash(Point(1, 2)))
try:
    p.x = 5
except Exception as e:
    print("immutable:", type(e).__name__)
''',
    output:
        r'''Order(order_id=1, items=[Item(name='pen', price=2.5, qty=3), Item(name='book', price=12.0, qty=1)])
total: 19.5
eq: True
sorted: [Item(name='a', price=5, qty=1), Item(name='b', price=5, qty=1), Item(name='c', price=1, qty=1)]
two orders isolated: True
frozen test:
Point(x=1, y=2) True
immutable: FrozenInstanceError
''',
    pitfalls: [
      '用可变默认值 items=[] 而非 field(default_factory=list)，实例间共享。',
      '以为类型注解会在运行时强制检查，传入错误类型不报错。',
      'order=True 未指定字段顺序，排序结果与预期不同。',
      'frozen 对象上调用修改属性，得到 FrozenInstanceError。',
    ],
    tasks: [
      PythonTask(
        prompt: '给 Item 加一个 __post_init__，价格非正时抛 ValueError。',
        hint: 'post_init 在生成的 __init__ 末尾调用。',
        answer: 'def __post_init__(self):\n    if self.price <= 0:\n        raise ValueError("price must be positive")',
      ),
      PythonTask(
        prompt: '用 replace() 生成一个修改了 qty 的 Item。',
        hint: 'dataclasses.replace(item, qty=10)。',
        answer: 'from dataclasses import replace\nprint(replace(Item("pen", 2.5), qty=10))',
      ),
    ],
  ),
  PythonTopic(
    id: 119,
    level: 'advanced',
    title: 'Python 119：通往 CPython——os、路径与时间',
    summary: '用 pathlib、os、datetime 处理文件路径与时间。',
    concepts: ['os', 'pathlib', 'datetime', 'timedelta', '文件系统'],
    objective: '用 pathlib 与 datetime 完成路径与时间计算。',
    prerequisites: ['通往 CPython：类型注解与 dataclasses'],
    runtime: PythonRuntime.cpython,
    explain:
        '本篇需要外部 CPython 环境：内置 MicroPython 没有 os、datetime、pathlib。'
        '真实程序离不开文件系统与时间：用 pathlib.Path 拼接跨平台路径（/ 运算符）'
        '比手写字符串更安全；os 提供环境变量与目录操作；datetime 提供日期算术，'
        'timedelta 能做「加 30 天」「求两日期差」这类计算，而 naive 与 aware 时间'
        '要区分清楚。下面的代码在临时目录里实际创建与读取文件，展示现代写法'
        '（pathlib + with）以及日期加减。',
    code:
        r'''import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta, date

with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp) / "logs"
    base.mkdir()
    log = base / "app.log"
    log.write_text("line1\nline2\n", encoding="utf-8", newline="")
    print("exists:", log.exists())
    print("name:", log.name, "suffix:", log.suffix)
    print("parent name:", log.parent.name)
    print("read:", log.read_text(encoding="utf-8").strip().split("\n"))
    print("files:", sorted(p.name for p in base.iterdir()))
    print("size:", log.stat().st_size)

start = date(2024, 1, 1)
print("plus 30d:", start + timedelta(days=30))
delta = date(2024, 3, 1) - start
print("diff days:", delta.days)
now = datetime(2024, 6, 15, 10, 30)
print("iso:", now.isoformat())
print("formatted:", now.strftime("%Y/%m/%d %H:%M"))
print("joined:", os.path.join("a", "b", "c.txt"))
''',
    output:
        r'''exists: True
name: app.log suffix: .log
parent name: logs
read: ['line1', 'line2']
files: ['app.log']
size: 12
plus 30d: 2024-01-31
diff days: 60
iso: 2024-06-15T10:30:00
formatted: 2024/06/15 10:30
joined: a\b\c.txt
''',
    pitfalls: [
      '用字符串拼接路径，Windows 与 POSIX 分隔符不一致。',
      'read_text 不指定 encoding，中文环境可能乱码。',
      '用 datetime.now()（本地时区 naive）与 aware 时间比较报错。',
      '忘记关闭文件，应使用 with 或 pathlib 的便捷方法。',
    ],
    tasks: [
      PythonTask(
        prompt: '计算你出生日期到今天的天数。',
        hint: 'date.today() - birth。',
        answer: 'from datetime import date\nb = date(2000, 1, 1)\nprint((date.today() - b).days)',
      ),
      PythonTask(
        prompt: '列出当前目录下所有 .py 文件的文件名。',
        hint: 'Path(".").glob("*.py")。',
        answer: 'from pathlib import Path\nprint(sorted(p.name for p in Path(".").glob("*.py")))',
      ),
    ],
  ),
  PythonTopic(
    id: 120,
    level: 'advanced',
    title: 'Python 120：通往 CPython——并发与异步概览',
    summary: '认识 threading 与 asyncio，理解 IO 密集与 CPU 密集的选型。',
    concepts: ['threading', 'asyncio', 'GIL', '并发模型'],
    objective: '用线程与协程各跑一个并发任务，理解适用场景。',
    prerequisites: ['通往 CPython：os、路径与时间'],
    runtime: PythonRuntime.cpython,
    explain:
        '本篇需要外部 CPython 环境：内置 MicroPython 没有 threading 与 asyncio。'
        '并发有两种常见模型：线程（threading）适合 IO 密集任务——因为 CPython '
        '有 GIL，CPU 密集的线程并不能真正并行，但等网络/磁盘时会把 GIL 让出；'
        '协程（asyncio）单线程事件循环，用 async/await 在 await 点切换，开销更小、'
        '更适合大量并发连接。选型口诀：CPU 密集用多进程，IO 密集用线程或协程。'
        '下面用 ThreadPoolExecutor 与 asyncio.gather 各跑一组模拟 IO，比较写法。',
    code:
        r'''import time
import threading
import asyncio
from concurrent.futures import ThreadPoolExecutor


lock = threading.Lock()
counter = {"value": 0}


def worker(name, delay):
    time.sleep(delay)
    with lock:
        counter["value"] += 1
    return "%s done" % name


with ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(worker, ["a", "b", "c"], [0.03, 0.01, 0.02]))
print("thread results:", sorted(results))
print("counter:", counter["value"])


async def fetch(name, delay):
    await asyncio.sleep(delay)
    return "fetched " + name


async def main():
    tasks = [fetch("x", 0.03), fetch("y", 0.01), fetch("z", 0.02)]
    return await asyncio.gather(*tasks)


print("async results:", sorted(asyncio.run(main())))
print("has_asyncio:", hasattr(asyncio, "run"))
print("thread ident positive:", threading.get_ident() > 0)
''',
    output:
        r'''thread results: ['a done', 'b done', 'c done']
counter: 3
async results: ['fetched x', 'fetched y', 'fetched z']
has_asyncio: True
thread ident positive: True
''',
    pitfalls: [
      '以为多线程能加速 CPU 密集运算，实际被 GIL 卡住。',
      '多线程共享计数器不加锁，结果小于预期。',
      '在 async 函数里用 time.sleep 阻塞整个事件循环，应用 asyncio.sleep。',
      '创建线程/协程后忘记等待完成，程序提前退出。',
    ],
    tasks: [
      PythonTask(
        prompt: '用 asyncio 写一个带超时的 fetch。',
        hint: 'asyncio.wait_for(fetch(...), timeout=0.01)。',
        answer: 'async def timed():\n    try:\n        return await asyncio.wait_for(fetch("x", 0.5), timeout=0.01)\n    except asyncio.TimeoutError:\n        return "timeout"',
      ),
      PythonTask(
        prompt: '解释为什么 CPU 密集任务不用多线程。',
        hint: 'GIL 同一时刻只允许一个线程执行字节码。',
        answer: 'GIL 使多线程无法并行执行 Python 字节码，CPU 密集应改用 multiprocessing。',
      ),
    ],
  ),
];
