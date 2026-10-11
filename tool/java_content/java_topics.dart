import 'java_topic.dart';

/// The 100 authored Java topics, ordered fundamentals -> advanced.
///
/// Code style rule enforced by tests: each program has a `class Main` on its
/// own line, `main` on its own line, and every statement on its own indented
/// line. No single-line packed classes.
const List<JavaTopic> javaTopics = <JavaTopic>[
  JavaTopic(
    id: 1,
    level: 'beginner',
    title: 'Java 001：第一个 Java 程序',
    summary: '从零认识 Java 程序结构：类、main 方法、语句与分号。',
    concepts: <String>['程序结构', 'main 方法', 'System.out', '编译与运行'],
    objective: '能写出并运行一个最简单的 Java 程序，理解类与 main 方法的作用。',
    explain:
        'Java 程序的入口是某个类里的 `public static void main(String[] args)`。'
        'JVM 从这个方法开始执行。每条语句以分号结束，字符串用双引号。'
        '`System.out.println` 输出一行并换行，`System.out.print` 不换行。',
    code: '''public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, Java!");
        System.out.print("这一行");
        System.out.println("接着上一行");
    }
}''',
    output: 'Hello, Java!\n这一行接着上一行',
    pitfalls: <String>[
      '类名必须与文件名一致（Main.java 里写 class Main）。',
      'main 的签名必须完整，否则运行时找不到入口。',
    ],
    tasks: <JavaTask>[
      JavaTask(prompt: '把输出改成你的名字。', hint: '修改字符串字面量。', answer: 'System.out.println("你的名字");'),
    ],
  ),
  JavaTopic(
    id: 2,
    level: 'beginner',
    title: 'Java 002：变量与基本类型',
    summary: '用 int、double、boolean、char 保存不同类型的数据。',
    concepts: <String>['变量', '基本类型', '字面量'],
    objective: '能声明并初始化 int、double、boolean、char 变量并输出。',
    explain:
        'Java 有 8 种基本类型。最常用的是 int（整数）、double（小数）、'
        'boolean（真假）、char（单个字符）。声明格式是「类型 变量名 = 值;」。',
    code: '''public class Main {
    public static void main(String[] args) {
        int age = 20;
        double price = 19.9;
        boolean active = true;
        char grade = 'A';
        System.out.println("age=" + age);
        System.out.println("price=" + price);
        System.out.println("active=" + active);
        System.out.println("grade=" + grade);
    }
}''',
    output: 'age=20\nprice=19.9\nactive=true\ngrade=A',
    pitfalls: <String>[
      'char 用单引号，String 用双引号，不能混用。',
      'double 字面量建议写小数点，否则会按整数处理。',
    ],
  ),
  JavaTopic(
    id: 3,
    level: 'beginner',
    title: 'Java 003：算术与运算符',
    summary: '掌握 + - * / % 以及整数除法与优先级。',
    concepts: <String>['算术运算符', '整数除法', '取余', '优先级'],
    objective: '能正确使用算术运算符，理解整数除法与浮点除法的区别。',
    explain:
        '整数相除会丢弃小数部分（7 / 2 == 3）。要得到小数，至少一个操作数要是'
        '浮点类型。% 是取余。乘除优先于加减，可用括号改变顺序。',
    code: '''public class Main {
    public static void main(String[] args) {
        int a = 7;
        int b = 2;
        System.out.println("a / b = " + (a / b));
        System.out.println("a % b = " + (a % b));
        System.out.println("a / 2.0 = " + (a / 2.0));
        System.out.println("(a + b) * 2 = " + ((a + b) * 2));
    }
}''',
    output: 'a / b = 3\na % b = 1\na / 2.0 = 3.5\n(a + b) * 2 = 18',
    pitfalls: <String>[
      '整数除法不会自动保留小数，务必区分。',
      '在字符串里拼接算式要用括号，否则按字符串拼接。',
    ],
  ),
  JavaTopic(
    id: 4,
    level: 'beginner',
    title: 'Java 004：类型转换',
    summary: '自动提升、强制转换与可能的数据丢失。',
    concepts: <String>['自动类型提升', '强制转换', '精度丢失'],
    objective: '能在 int、long、double 之间安全转换，并识别强制转换的风险。',
    explain:
        '小范围类型可以自动提升到大范围（int -> double）。反向转换需要强制'
        '转换「(类型)值」，可能丢失小数部分或溢出。',
    code: '''public class Main {
    public static void main(String[] args) {
        int i = 300;
        long l = i;
        double d = i;
        System.out.println("long=" + l);
        System.out.println("double=" + d);
        double pi = 3.99;
        int truncated = (int) pi;
        System.out.println("truncated=" + truncated);
    }
}''',
    output: 'long=300\ndouble=300.0\ntruncated=3',
    pitfalls: <String>['强制转换小数会截断而不是四舍五入。', '超出范围转换会得到意外的值。'],
  ),
  JavaTopic(
    id: 5,
    level: 'beginner',
    title: 'Java 005：字符串基础',
    summary: 'String 的创建、拼接、长度与常用方法。',
    concepts: <String>['String', '不可变', '字符串方法'],
    objective: '能使用 length、toUpperCase、substring、contains 等方法。',
    explain: 'String 是不可变的。每次「修改」都会产生新对象。常用方法包括长度、'
        '大小写转换、查找和截取。字符串用 + 拼接。',
    code: '''public class Main {
    public static void main(String[] args) {
        String name = "Java";
        System.out.println("length=" + name.length());
        System.out.println("upper=" + name.toUpperCase());
        String full = name + " 教程";
        System.out.println("contains=" + full.contains("教程"));
        System.out.println("sub=" + full.substring(0, 4));
    }
}''',
    output: 'length=4\nupper=JAVA\ncontains=true\nsub=Java',
    pitfalls: <String>['substring 的结束下标不包含在结果里。', '用 == 比较字符串内容会出错，应用 equals。'],
  ),
  JavaTopic(
    id: 6,
    level: 'beginner',
    title: 'Java 006：条件判断',
    summary: 'if / else if / else 处理分支逻辑。',
    concepts: <String>['if', 'else if', '比较运算符'],
    objective: '能根据条件选择不同分支并输出对应结果。',
    explain: 'if 后接布尔表达式。从上到下判断，命中一个分支后其余跳过。'
        '比较用 ==、!=、<、>、<=、>=。',
    code: '''public class Main {
    public static void main(String[] args) {
        int score = 82;
        if (score >= 90) {
            System.out.println("优秀");
        } else if (score >= 60) {
            System.out.println("及格");
        } else {
            System.out.println("不及格");
        }
    }
}''',
    output: '及格',
    pitfalls: <String>['条件必须是 boolean，不能写成赋值 =。', '注意分支顺序，较严格的条件放前面。'],
  ),
  JavaTopic(
    id: 7,
    level: 'beginner',
    title: 'Java 007：switch 分支',
    summary: '用 switch 处理多值选择，含新式箭头语法。',
    concepts: <String>['switch', 'case', '箭头语法'],
    objective: '能用 switch 表达式根据枚举或字符串选择结果。',
    explain: 'switch 适合「一个值对多个固定选项」。新式 `case X ->` 语法不需要'
        'break，也不会穿透。default 处理未匹配情况。',
    code: '''public class Main {
    public static void main(String[] args) {
        String day = "SAT";
        String type = switch (day) {
            case "SAT", "SUN" -> "周末";
            default -> "工作日";
        };
        System.out.println(day + " -> " + type);
    }
}''',
    output: 'SAT -> 周末',
    pitfalls: <String>['传统 case 忘记 break 会穿透到下一个分支。', 'switch 表达式所有分支都要有返回值。'],
  ),
  JavaTopic(
    id: 8,
    level: 'beginner',
    title: 'Java 008：for 循环',
    summary: '计数循环与累加求和。',
    concepts: <String>['for', '循环变量', '累加'],
    objective: '能用 for 循环重复执行并累计结果。',
    explain: 'for(初始化; 条件; 步进) 是最常用的计数循环。循环变量作用域只在循环内。'
        '把累加变量声明在循环外。',
    code: '''public class Main {
    public static void main(String[] args) {
        int sum = 0;
        for (int i = 1; i <= 5; i++) {
            sum += i;
        }
        System.out.println("sum=" + sum);
    }
}''',
    output: 'sum=15',
    pitfalls: <String>['循环条件写错会造成死循环。', '累加变量声明在循环里会被重置。'],
  ),
  JavaTopic(
    id: 9,
    level: 'beginner',
    title: 'Java 009：while 与 do-while',
    summary: '条件循环，以及至少执行一次的 do-while。',
    concepts: <String>['while', 'do-while', '循环控制'],
    objective: '能根据条件使用 while 循环，并说明 do-while 的区别。',
    explain: 'while 先判断后执行；do-while 先执行一次再判断。适合「直到满足条件才停」'
        '的场景。注意在循环里更新条件变量避免死循环。',
    code: '''public class Main {
    public static void main(String[] args) {
        int n = 3;
        int count = 0;
        while (n > 0) {
            count++;
            n--;
        }
        System.out.println("count=" + count);
        int once = 0;
        do {
            once++;
        } while (false);
        System.out.println("once=" + once);
    }
}''',
    output: 'count=3\nonce=1',
    pitfalls: <String>['忘记更新条件会死循环。', 'do-while 至少执行一次，条件为假也一样。'],
  ),
  JavaTopic(
    id: 10,
    level: 'beginner',
    title: 'Java 010：数组',
    summary: '声明、初始化、遍历与数组长度。',
    concepts: <String>['数组', '下标', '遍历'],
    objective: '能创建数组、按下标访问并用增强 for 遍历。',
    explain: '数组长度固定，用 `new int[n]` 或字面量 `{...}` 创建。下标从 0 开始，'
        '越界会抛异常。`length` 是属性不是方法。',
    code: '''public class Main {
    public static void main(String[] args) {
        int[] scores = {90, 75, 88};
        System.out.println("length=" + scores.length);
        int total = 0;
        for (int score : scores) {
            total += score;
        }
        System.out.println("first=" + scores[0]);
        System.out.println("total=" + total);
    }
}''',
    output: 'length=3\nfirst=90\ntotal=253',
    pitfalls: <String>['下标从 0 开始，最大是 length-1。', '数组长度创建后不可变；扩容要新建数组。'],
  ),
  JavaTopic(
    id: 11,
    level: 'beginner',
    title: 'Java 011：方法定义与调用',
    summary: '把逻辑封装成方法，理解参数与返回值。',
    concepts: <String>['方法', '参数', 'return'],
    objective: '能定义带参数和返回值的方法并调用。',
    explain: '方法把一段逻辑命名复用。`static` 方法属于类，可以直接在 main 里调用。'
        '`return` 返回值并结束方法；void 表示无返回值。',
    code: '''public class Main {
    public static void main(String[] args) {
        int result = add(3, 4);
        System.out.println("add=" + result);
        greet("Java");
    }

    static int add(int a, int b) {
        return a + b;
    }

    static void greet(String name) {
        System.out.println("你好, " + name);
    }
}''',
    output: 'add=7\n你好, Java',
    pitfalls: <String>['返回类型要和方法体 return 的类型一致。', 'void 方法不能出现在赋值表达式里。'],
  ),
  JavaTopic(
    id: 12,
    level: 'beginner',
    title: 'Java 012：递归',
    summary: '方法调用自身：阶乘与终止条件。',
    concepts: <String>['递归', '终止条件', '调用栈'],
    objective: '能写出带终止条件的递归方法。',
    explain: '递归方法必须有一个不再递归的终止条件，否则会栈溢出。'
        '每层调用把问题缩小，直到基础情形。',
    code: '''public class Main {
    public static void main(String[] args) {
        System.out.println("factorial(5)=" + factorial(5));
        System.out.println("fib(7)=" + fib(7));
    }

    static int factorial(int n) {
        if (n <= 1) {
            return 1;
        }
        return n * factorial(n - 1);
    }

    static int fib(int n) {
        if (n <= 1) {
            return n;
        }
        return fib(n - 1) + fib(n - 2);
    }
}''',
    output: 'factorial(5)=120\nfib(7)=13',
    pitfalls: <String>['缺少终止条件会无限递归导致栈溢出。', '朴素递归效率低，可用记忆化或迭代优化。'],
  ),
  JavaTopic(
    id: 13,
    level: 'beginner',
    title: 'Java 013：可变参数与重载',
    summary: 'varargs 接收不定参数，方法重载按签名区分。',
    concepts: <String>['可变参数', '方法重载', '签名'],
    objective: '能定义可变参数方法与方法重载。',
    explain: '`int... nums` 表示可变参数，调用时可传任意个。方法重载是同名不同参数列表，'
        '编译器按实参选择。',
    code: '''public class Main {
    public static void main(String[] args) {
        System.out.println("sum=" + sum(1, 2, 3, 4));
        System.out.println("say=" + say("hi"));
        System.out.println("say=" + say(42));
    }

    static int sum(int... nums) {
        int total = 0;
        for (int n : nums) {
            total += n;
        }
        return total;
    }

    static String say(String text) {
        return "文本:" + text;
    }

    static String say(int number) {
        return "数字:" + number;
    }
}''',
    output: 'sum=10\nsay=文本:hi\nsay=数字:42',
    pitfalls: <String>['可变参数只能放在参数列表末尾。', '重载不能只靠返回类型区分。'],
  ),
  JavaTopic(
    id: 14,
    level: 'beginner',
    title: 'Java 014：枚举入门',
    summary: '用 enum 表示一组固定常量并携带字段。',
    concepts: <String>['enum', '常量', '字段'],
    objective: '能定义带属性和方法的枚举。',
    explain: 'enum 定义一组命名常量，比裸字符串更安全。枚举可以有构造器、字段和方法，'
        '常量之间用逗号分隔。',
    code: '''public class Main {
    enum Level {
        LOW(1),
        HIGH(3);

        final int weight;

        Level(int weight) {
            this.weight = weight;
        }
    }

    public static void main(String[] args) {
        Level level = Level.HIGH;
        System.out.println("name=" + level.name());
        System.out.println("weight=" + level.weight);
    }
}''',
    output: 'name=HIGH\nweight=3',
    pitfalls: <String>['枚举常量列表末尾有分号（若有字段/方法）。', '枚举不能用 new 创建。'],
  ),
  JavaTopic(
    id: 15,
    level: 'beginner',
    title: 'Java 015：综合练习：成绩统计',
    summary: '把变量、循环、数组、方法组合起来统计成绩。',
    concepts: <String>['综合', '循环累加', '方法复用'],
    objective: '能把前 14 课知识组合成一个可运行的小程序。',
    explain: '综合使用数组保存数据、循环遍历、方法返回统计结果，体会程序如何分层组织。',
    code: '''public class Main {
    public static void main(String[] args) {
        int[] scores = {88, 92, 79, 95};
        System.out.println("total=" + total(scores));
        System.out.println("average=" + average(scores));
        System.out.println("max=" + max(scores));
    }

    static int total(int[] values) {
        int sum = 0;
        for (int value : values) {
            sum += value;
        }
        return sum;
    }

    static double average(int[] values) {
        return (double) total(values) / values.length;
    }

    static int max(int[] values) {
        int best = values[0];
        for (int value : values) {
            if (value > best) {
                best = value;
            }
        }
        return best;
    }
}''',
    output: 'total=354\naverage=88.5\nmax=95',
    pitfalls: <String>['平均值要用浮点除法，否则结果被截断。', '数组为空时访问 [0] 会越界。'],
  ),
  JavaTopic(
    id: 16,
    level: 'intermediate',
    title: 'Java 016：类与对象',
    summary: '定义类、创建对象、通过字段与方法描述状态和行为。',
    concepts: <String>['类', '对象', 'new', '字段', '方法'],
    objective: '能定义一个类并创建对象，访问其字段和调用其方法。',
    explain:
        '类是模板，对象是按模板创建的实例。字段保存状态，方法描述行为。'
        '用 new 创建对象；对象的方法通过「对象.方法()」调用。',
    code: '''public class Main {
    static class Dog {
        String name;
        int age;

        void bark() {
            System.out.println(name + " 汪汪");
        }
    }

    public static void main(String[] args) {
        Dog dog = new Dog();
        dog.name = "旺财";
        dog.age = 3;
        System.out.println(dog.name + " 年龄 " + dog.age);
        dog.bark();
    }
}''',
    output: '旺财 年龄 3\n旺财 汪汪',
    pitfalls: <String>['对象字段默认有初值（0/null），不是未定义。', '忘记 new 直接使用会得到 null。'],
  ),
  JavaTopic(
    id: 17,
    level: 'intermediate',
    title: 'Java 017：构造方法与 this',
    summary: '用构造器初始化对象，用 this 区分字段与参数。',
    concepts: <String>['构造方法', 'this', '初始化'],
    objective: '能编写带参数的构造器并用 this 指向当前对象。',
    explain:
        '构造方法与类同名、无返回类型，new 时自动调用。当参数名与字段同名时，'
        '用 this.字段 指代字段避免遮蔽。',
    code: '''public class Main {
    static class Point {
        final int x;
        final int y;

        Point(int x, int y) {
            this.x = x;
            this.y = y;
        }

        String describe() {
            return "(" + x + ", " + y + ")";
        }
    }

    public static void main(String[] args) {
        Point p = new Point(3, 4);
        System.out.println(p.describe());
    }
}''',
    output: '(3, 4)',
    pitfalls: <String>['构造方法不能写返回类型。', 'final 字段必须在构造器里赋值一次。'],
  ),
  JavaTopic(
    id: 18,
    level: 'intermediate',
    title: 'Java 018：封装与访问控制',
    summary: '用 private 字段 + getter/setter 保护内部状态。',
    concepts: <String>['封装', 'private', 'getter', 'setter'],
    objective: '能用私有字段和受控访问方法保护不变量。',
    explain:
        '把字段设为 private，阻止外部随意修改；提供 getter/setter 在读写时校验，'
        '从而维持对象的不变量。',
    code: '''public class Main {
    static class Account {
        private int balance;

        Account(int balance) {
            this.balance = balance;
        }

        int getBalance() {
            return balance;
        }

        void deposit(int amount) {
            if (amount <= 0) {
                throw new IllegalArgumentException("金额必须为正");
            }
            balance += amount;
        }
    }

    public static void main(String[] args) {
        Account account = new Account(100);
        account.deposit(50);
        System.out.println("balance=" + account.getBalance());
    }
}''',
    output: 'balance=150',
    pitfalls: <String>['不要为所有字段都机械生成 setter，破坏封装。', '校验放在 setter/业务方法里，而不是调用方。'],
  ),
  JavaTopic(
    id: 19,
    level: 'intermediate',
    title: 'Java 019：继承与 super',
    summary: '子类继承父类，用 super 调用父类构造器与方法。',
    concepts: <String>['继承', 'extends', 'super', '方法覆盖'],
    objective: '能定义继承关系并用 super 复用父类实现。',
    explain:
        '子类用 extends 继承父类，获得其字段与方法，可覆盖方法改变行为。'
        '子类构造器第一句用 super(...) 调用父类构造器。',
    code: '''public class Main {
    static class Animal {
        final String name;

        Animal(String name) {
            this.name = name;
        }

        String sound() {
            return "...";
        }
    }

    static class Cat extends Animal {
        Cat(String name) {
            super(name);
        }

        @Override
        String sound() {
            return "喵";
        }
    }

    public static void main(String[] args) {
        Cat cat = new Cat("咪咪");
        System.out.println(cat.name + ": " + cat.sound());
    }
}''',
    output: '咪咪: 喵',
    pitfalls: <String>['子类构造器未显式调用 super 时，会先调用父类无参构造器。', '@Override 写错方法签名会报错，正好用于校验。'],
  ),
  JavaTopic(
    id: 20,
    level: 'intermediate',
    title: 'Java 020：多态与动态绑定',
    summary: '父类引用指向子类对象，运行时选择实际实现。',
    concepts: <String>['多态', '向上转型', '动态绑定'],
    objective: '能用父类类型统一处理不同子类对象。',
    explain:
        '父类引用可以指向子类对象；调用被覆盖的方法时，运行时按实际对象类型执行。'
        '这让代码依赖抽象而不依赖具体实现。',
    code: '''import java.util.List;

public class Main {
    interface Shape {
        double area();
    }

    static class Circle implements Shape {
        final double r;

        Circle(double r) {
            this.r = r;
        }

        @Override
        public double area() {
            return 3.14159 * r * r;
        }
    }

    static class Square implements Shape {
        final double side;

        Square(double side) {
            this.side = side;
        }

        @Override
        public double area() {
            return side * side;
        }
    }

    public static void main(String[] args) {
        List<Shape> shapes = List.of(new Square(2), new Circle(1));
        for (Shape shape : shapes) {
            System.out.println("area=" + shape.area());
        }
    }
}''',
    output: 'area=4.0\narea=3.14159',
    pitfalls: <String>['多态只作用于方法，不作用于字段。', '静态方法不参与动态绑定。'],
  ),
  JavaTopic(
    id: 21,
    level: 'intermediate',
    title: 'Java 021：抽象类',
    summary: '定义不能实例化的抽象基类，强制子类实现抽象方法。',
    concepts: <String>['abstract', '抽象方法', '模板方法'],
    objective: '能用抽象类定义共享骨架并强制子类实现细节。',
    explain:
        '抽象类用 abstract 声明，可包含抽象方法（只有签名）与具体方法。'
        '子类必须实现所有抽象方法，否则也必须是抽象类。',
    code: '''public class Main {
    abstract static class Report {
        abstract String body();

        String render() {
            return "标题\\n" + body();
        }
    }

    static class TextReport extends Report {
        @Override
        String body() {
            return "正文";
        }
    }

    public static void main(String[] args) {
        System.out.println(new TextReport().render());
    }
}''',
    output: '标题\n正文',
    pitfalls: <String>['抽象类不能 new。', '抽象方法不能是 private 或 static。'],
  ),
  JavaTopic(
    id: 22,
    level: 'intermediate',
    title: 'Java 022：接口与默认方法',
    summary: '用接口定义能力契约，default 方法提供默认实现。',
    concepts: <String>['接口', 'implements', 'default 方法'],
    objective: '能定义接口、实现多个接口并重写 default 方法。',
    explain:
        '接口描述「能做什么」的契约，一个类可实现多个接口。default 方法让接口'
        '在新增方法时不破坏已有实现。',
    code: '''public class Main {
    interface Greeter {
        String name();

        default String greet() {
            return "你好, " + name();
        }
    }

    static class Robot implements Greeter {
        @Override
        public String name() {
            return "R2";
        }
    }

    public static void main(String[] args) {
        System.out.println(new Robot().greet());
    }
}''',
    output: '你好, R2',
    pitfalls: <String>['接口方法默认是 public abstract。', '类实现接口时必须用 public 修饰实现方法。'],
  ),
  JavaTopic(
    id: 23,
    level: 'intermediate',
    title: 'Java 023：静态成员',
    summary: 'static 字段与方法属于类而非实例；静态计数器示例。',
    concepts: <String>['static', '类变量', '静态方法'],
    objective: '能解释 static 的含义并用静态成员共享状态。',
    explain:
        'static 成员属于类，被所有实例共享。静态方法不能直接访问实例字段；'
        '静态字段常用来计数或保存共享常量。',
    code: '''public class Main {
    static class Counter {
        static int created;

        Counter() {
            created++;
        }
    }

    public static void main(String[] args) {
        new Counter();
        new Counter();
        new Counter();
        System.out.println("created=" + Counter.created);
    }
}''',
    output: 'created=3',
    pitfalls: <String>['静态字段被所有实例共享，注意并发。', '在静态方法里不能直接用 this。'],
  ),
  JavaTopic(
    id: 24,
    level: 'intermediate',
    title: 'Java 024：内部类与匿名类',
    summary: '成员内部类、静态嵌套类与匿名类。',
    concepts: <String>['嵌套类', '匿名类', '作用域'],
    objective: '能使用静态嵌套类和匿名类实现一次性的行为。',
    explain:
        '嵌套类把辅助类型放进外层类。静态嵌套类不持有外部实例；匿名类用于'
        '一次性实现接口或抽象类。',
    code: '''public class Main {
    interface Printer {
        String print(String value);
    }

    static String run(Printer printer) {
        return printer.print("data");
    }

    public static void main(String[] args) {
        Printer upper = new Printer() {
            @Override
            public String print(String value) {
                return value.toUpperCase();
            }
        };
        System.out.println(run(upper));
    }
}''',
    output: 'DATA',
    pitfalls: <String>['匿名类不能有构造器，只能用初始化块。', '过度使用匿名类会降低可读性，可考虑 lambda。'],
  ),
  JavaTopic(
    id: 25,
    level: 'intermediate',
    title: 'Java 025：record 记录类',
    summary: '用 record 声明不可变数据载体，自动生成访问器与 equals。',
    concepts: <String>['record', '不可变', '自动生成方法'],
    objective: '能用 record 定义简洁的不可变值类型。',
    explain:
        'record 自动生成构造器、访问器、equals、hashCode 和 toString，适合'
        '表示「一组不可变数据」。字段是 final 的，访问器名与字段同名。',
    code: '''public class Main {
    record Point(int x, int y) {
        Point {
            if (x < 0 || y < 0) {
                throw new IllegalArgumentException("坐标不能为负");
            }
        }
    }

    public static void main(String[] args) {
        Point p = new Point(2, 3);
        System.out.println(p);
        System.out.println("x=" + p.x());
        System.out.println("equal=" + p.equals(new Point(2, 3)));
    }
}''',
    output: 'Point[x=2, y=3]\nx=2\nequal=true',
    pitfalls: <String>['record 不能继承其它类，也不能声明额外实例字段。', '访问器是 x() 而不是 getX()。'],
  ),
  JavaTopic(
    id: 26,
    level: 'intermediate',
    title: 'Java 026：equals 与 hashCode',
    summary: '重写 equals/hashCode 让基于内容的对象可正确比较与查找。',
    concepts: <String>['equals', 'hashCode', '契约'],
    objective: '能手写一致的 equals 与 hashCode。',
    explain:
        '默认 equals 比较引用。按内容比较要重写 equals，且必须同时重写 hashCode，'
        '保证相等对象哈希一致，才能在 HashMap/HashSet 中正确工作。',
    code: '''import java.util.Objects;

public class Main {
    static class Money {
        final int amount;

        Money(int amount) {
            this.amount = amount;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Money money)) {
                return false;
            }
            return amount == money.amount;
        }

        @Override
        public int hashCode() {
            return Objects.hash(amount);
        }
    }

    public static void main(String[] args) {
        Money a = new Money(10);
        Money b = new Money(10);
        System.out.println("equals=" + a.equals(b));
        System.out.println("hashSame=" + (a.hashCode() == b.hashCode()));
    }
}''',
    output: 'equals=true\nhashSame=true',
    pitfalls: <String>['重写 equals 不重写 hashCode 会导致哈希集合出错。', 'equals 参数类型是 Object，别写成具体类型。'],
  ),
  JavaTopic(
    id: 27,
    level: 'intermediate',
    title: 'Java 027：枚举进阶',
    summary: '枚举带抽象方法：用每个常量实现自己的行为。',
    concepts: <String>['枚举', '抽象方法', '策略'],
    objective: '能用枚举常量实现各自的行为，替代冗长分支。',
    explain:
        '枚举常量可以各自实现抽象方法，形成一组内置策略，避免 switch 分支并提升'
        '类型安全。',
    code: '''public class Main {
    enum Op {
        ADD {
            @Override
            int apply(int a, int b) {
                return a + b;
            }
        },
        MUL {
            @Override
            int apply(int a, int b) {
                return a * b;
            }
        };

        abstract int apply(int a, int b);
    }

    public static void main(String[] args) {
        System.out.println("add=" + Op.ADD.apply(3, 4));
        System.out.println("mul=" + Op.MUL.apply(3, 4));
    }
}''',
    output: 'add=7\nmul=12',
    pitfalls: <String>['枚举里的抽象方法必须在每个常量实现。', '枚举常量顺序影响 values() 与 ordinal()。'],
  ),
  JavaTopic(
    id: 28,
    level: 'intermediate',
    title: 'Java 028：接口继承与多接口组合',
    summary: '接口可继承接口，一个类可实现多个接口。',
    concepts: <String>['接口继承', '多接口', '能力组合'],
    objective: '能组合多个接口表达复合能力。',
    explain:
        '接口之间用 extends 继承，类用 implements 可实现多个接口，从而组合多种能力。'
        '同名默认方法冲突时，实现类必须显式重写。',
    code: '''public class Main {
    interface Named {
        String name();
    }

    interface Aged {
        int age();
    }

    static class Person implements Named, Aged {
        @Override
        public String name() {
            return "张三";
        }

        @Override
        public int age() {
            return 30;
        }
    }

    public static void main(String[] args) {
        Person p = new Person();
        System.out.println(p.name() + " 岁数 " + p.age());
    }
}''',
    output: '张三 岁数 30',
    pitfalls: <String>['两个接口有同名默认方法时必须重写消歧。', '接口不能有实例字段。'],
  ),
  JavaTopic(
    id: 29,
    level: 'intermediate',
    title: 'Java 029：包装类与自动装箱',
    summary: '基本类型与包装类型的转换，以及缓存陷阱。',
    concepts: <String>['包装类', '自动装箱', '缓存'],
    objective: '能解释自动装箱/拆箱并避免 Integer 比较陷阱。',
    explain:
        'int 与 Integer 自动互相转换。较小的 Integer（-128..127）会复用缓存对象，'
        '所以 == 可能在范围内为 true、超出为 false；比较值要用 equals。',
    code: '''public class Main {
    public static void main(String[] args) {
        Integer a = 100;
        Integer b = 100;
        System.out.println("small == " + (a == b));
        Integer c = 200;
        Integer d = 200;
        System.out.println("large == " + (c == d));
        System.out.println("large equals " + c.equals(d));
    }
}''',
    output: 'small == true\nlarge == false\nlarge equals true',
    pitfalls: <String>['用 == 比较包装类型值会出错，用 equals。', '对 null 的包装类型拆箱会抛 NPE。'],
  ),
  JavaTopic(
    id: 30,
    level: 'intermediate',
    title: 'Java 030：综合练习：简易银行账户',
    summary: '把类、封装、枚举、异常组合成一个可运行的小系统。',
    concepts: <String>['综合', '封装', '枚举', '异常'],
    objective: '能综合运用 OOP 知识实现一个小型业务模型。',
    explain:
        '用一个类维护余额、一个枚举表示交易类型、一个自定义异常处理透支，'
        '体会面向对象如何把状态与行为收敛在一起。',
    code: '''public class Main {
    enum Kind {
        DEPOSIT,
        WITHDRAW
    }

    static class BankAccount {
        private int balance;

        BankAccount(int opening) {
            this.balance = opening;
        }

        void apply(Kind kind, int amount) {
            if (amount <= 0) {
                throw new IllegalArgumentException("金额必须为正");
            }
            if (kind == Kind.DEPOSIT) {
                balance += amount;
            } else {
                if (amount > balance) {
                    throw new IllegalStateException("余额不足");
                }
                balance -= amount;
            }
        }

        int balance() {
            return balance;
        }
    }

    public static void main(String[] args) {
        BankAccount account = new BankAccount(100);
        account.apply(Kind.DEPOSIT, 40);
        account.apply(Kind.WITHDRAW, 30);
        System.out.println("balance=" + account.balance());
    }
}''',
    output: 'balance=110',
    pitfalls: <String>['业务校验放在领域方法里，而不是散落各处。', '金额用 int 分或 BigDecimal，避免浮点误差。'],
  ),
  JavaTopic(
    id: 31,
    level: 'intermediate',
    title: 'Java 031：StringBuilder 高效拼接',
    summary: '循环中拼接字符串应使用 StringBuilder。',
    concepts: <String>['StringBuilder', '可变字符串', '性能'],
    objective: '能用 StringBuilder 在循环里高效构造字符串。',
    explain:
        'String 不可变，循环里用 + 会频繁创建新对象。StringBuilder 在同一个缓冲区'
        '上追加，最后 toString() 得到结果。',
    code: '''public class Main {
    public static void main(String[] args) {
        StringBuilder builder = new StringBuilder();
        for (int i = 1; i <= 5; i++) {
            builder.append(i).append(",");
        }
        System.out.println(builder.toString());
        builder.reverse();
        System.out.println(builder.toString());
    }
}''',
    output: '1,2,3,4,5,\n,5,4,3,2,1',
    pitfalls: <String>['append 返回自身，可链式调用。', '多线程共享要改用 StringBuffer。'],
  ),
  JavaTopic(
    id: 32,
    level: 'intermediate',
    title: 'Java 032：正则表达式',
    summary: '用 Pattern/Matcher 做匹配、提取与替换。',
    concepts: <String>['正则', 'Pattern', 'Matcher', '分组'],
    objective: '能编写简单正则进行匹配与分组提取。',
    explain:
        '正则用元字符描述模式。`\\d` 数字、`+` 一个或多个、括号是分组。'
        'matches 要求整串匹配，find 找子串。',
    code: '''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        Pattern pattern = Pattern.compile("(\\\\d+)-(\\\\d+)");
        Matcher matcher = pattern.matcher("订单 2024-001 已发货");
        if (matcher.find()) {
            System.out.println("year=" + matcher.group(1));
            System.out.println("id=" + matcher.group(2));
        }
        System.out.println("replaced=" + "a1b2".replaceAll("\\\\d", "#"));
    }
}''',
    output: 'year=2024\nid=001\nreplaced=a#b#',
    pitfalls: <String>['Java 字符串里反斜杠要双写。', 'matches 是全串匹配，find 是子串搜索。'],
  ),
  JavaTopic(
    id: 33,
    level: 'intermediate',
    title: 'Java 033：BigDecimal 精确计算',
    summary: '金额计算用 BigDecimal，避免浮点误差。',
    concepts: <String>['BigDecimal', '精度', '舍入'],
    objective: '能用 BigDecimal 做精确加减乘除并指定舍入。',
    explain:
        'double 有二进制浮点误差（0.1 + 0.2 != 0.3）。金额用 BigDecimal，'
        '用字符串构造，除法必须指定精度和舍入模式。',
    code: '''import java.math.BigDecimal;
import java.math.RoundingMode;

public class Main {
    public static void main(String[] args) {
        BigDecimal a = new BigDecimal("0.1");
        BigDecimal b = new BigDecimal("0.2");
        System.out.println("sum=" + a.add(b));
        BigDecimal price = new BigDecimal("19.99");
        BigDecimal qty = new BigDecimal(3);
        System.out.println("total=" + price.multiply(qty));
        System.out.println("div=" + new BigDecimal("10").divide(new BigDecimal(3), 2, RoundingMode.HALF_UP));
    }
}''',
    output: 'sum=0.3\ntotal=59.97\ndiv=3.33',
    pitfalls: <String>['用 double 构造 BigDecimal 会带入误差，要用字符串。', 'divide 不指定精度可能抛 ArithmeticException。'],
  ),
  JavaTopic(
    id: 34,
    level: 'intermediate',
    title: 'Java 034：java.time 日期时间',
    summary: 'LocalDate/LocalDateTime 与格式化。',
    concepts: <String>['java.time', 'LocalDate', 'DateTimeFormatter'],
    objective: '能创建、运算并格式化日期时间。',
    explain:
        'java.time 是不可变的现代日期 API。LocalDate 表示日期，Duration/Period 表示'
        '时间跨度，DateTimeFormatter 负责格式化与解析。',
    code: '''import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

public class Main {
    public static void main(String[] args) {
        LocalDate date = LocalDate.of(2024, 1, 31);
        LocalDate next = date.plusDays(1);
        System.out.println("next=" + next);
        System.out.println("leap=" + date.isLeapYear());
        String text = next.format(DateTimeFormatter.ISO_DATE);
        System.out.println("formatted=" + text);
    }
}''',
    output: 'next=2024-02-01\nleap=true\nformatted=2024-02-01',
    pitfalls: <String>['月份从 1 开始，不像旧 API 从 0。', 'java.time 对象不可变，运算会返回新对象。'],
  ),
  JavaTopic(
    id: 35,
    level: 'intermediate',
    title: 'Java 035：Optional 处理可能为空',
    summary: '用 Optional 表达「可能没有值」，避免 null 判断。',
    concepts: <String>['Optional', 'null 安全', '链式'],
    objective: '能用 Optional 的 map/orElse 安全处理缺失值。',
    explain:
        'Optional 明确表达值可能缺失。map 在存在时变换，orElse 提供默认值，'
        '避免层层 null 检查。',
    code: '''import java.util.Optional;

public class Main {
    static Optional<String> find(int id) {
        return id == 1 ? Optional.of("张三") : Optional.empty();
    }

    public static void main(String[] args) {
        System.out.println(find(1).orElse("未知"));
        System.out.println(find(2).orElse("未知"));
        System.out.println(find(1).map(String::toUpperCase).orElse("-"));
    }
}''',
    output: '张三\n未知\n张三',
    pitfalls: <String>['Optional 不适合做字段或方法参数。', '不要用 get() 直接取，可能抛 NoSuchElementException。'],
  ),
  JavaTopic(
    id: 36,
    level: 'intermediate',
    title: 'Java 036：List 与 ArrayList',
    summary: '有序可重复集合：增删查改与遍历。',
    concepts: <String>['List', 'ArrayList', '集合'],
    objective: '能用 List 保存有序数据并安全遍历。',
    explain:
        'List 有序可重复，ArrayList 是最常用实现。add/get/size 是基础操作；'
        '遍历推荐增强 for。注意删除元素时不要边遍历边删。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<String> names = new ArrayList<>();
        names.add("Java");
        names.add("Kotlin");
        names.add("Java");
        System.out.println("size=" + names.size());
        System.out.println("get(1)=" + names.get(1));
        System.out.println("contains=" + names.contains("Java"));
        names.remove("Java");
        System.out.println("afterRemove=" + names);
    }
}''',
    output: 'size=3\nget(1)=Kotlin\ncontains=true\nafterRemove=[Kotlin, Java]',
    pitfalls: <String>['remove(int) 删下标，remove(Object) 删元素，别搞混。', '遍历中直接 remove 会抛 ConcurrentModificationException。'],
  ),
  JavaTopic(
    id: 37,
    level: 'intermediate',
    title: 'Java 037：HashSet 去重',
    summary: '用 Set 保存不重复元素并做集合运算。',
    concepts: <String>['Set', 'HashSet', '去重'],
    objective: '能用 Set 去重并计算交集/并集。',
    explain:
        'Set 不允许重复元素，HashSet 按哈希存储，add 重复元素返回 false。'
        'retainAll/AddAll 可实现交集/并集。',
    code: '''import java.util.HashSet;
import java.util.Set;

public class Main {
    public static void main(String[] args) {
        Set<String> tags = new HashSet<>();
        System.out.println("added1=" + tags.add("java"));
        System.out.println("added2=" + tags.add("java"));
        tags.add("spring");
        System.out.println("size=" + tags.size());

        Set<String> other = new HashSet<>(Set.of("java", "sql"));
        Set<String> common = new HashSet<>(tags);
        common.retainAll(other);
        System.out.println("common=" + common);
    }
}''',
    output: 'added1=true\nadded2=false\nsize=2\ncommon=[java]',
    pitfalls: <String>['自定义对象去重要正确重写 equals/hashCode。', 'set.add 返回 boolean，不要当 void 用。'],
  ),
  JavaTopic(
    id: 38,
    level: 'intermediate',
    title: 'Java 038：HashMap 键值映射',
    summary: '用 Map 存取键值对与遍历技巧。',
    concepts: <String>['Map', 'HashMap', 'TreeMap', 'entrySet'],
    objective: '能用 Map 统计频次并按稳定顺序遍历键值。',
    explain:
        'Map 保存键到值的映射，键唯一。put/get/getOrDefault/computeIfAbsent 是常用'
        '方法，遍历用 entrySet。HashMap 不保证顺序，需要有序输出时用 TreeMap。',
    code: '''import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        Map<String, Integer> count = new HashMap<>();
        for (String word : new String[] {"a", "b", "a", "a"}) {
            count.put(word, count.getOrDefault(word, 0) + 1);
        }
        System.out.println("a=" + count.get("a"));
        System.out.println("missing=" + count.getOrDefault("z", 0));
        // TreeMap 按 key 排序，保证输出顺序稳定，不依赖 HashMap 的哈希顺序。
        for (Map.Entry<String, Integer> entry : new TreeMap<>(count).entrySet()) {
            System.out.println(entry.getKey() + "->" + entry.getValue());
        }
    }
}''',
    output: 'a=3\nmissing=0\na->3\nb->1',
    pitfalls: <String>['HashMap 不保证遍历顺序，要稳定顺序用 TreeMap 或先排序。', 'get 缺失键返回 null，Integer 拆箱可能 NPE。'],
  ),
  JavaTopic(
    id: 39,
    level: 'intermediate',
    title: 'Java 039：Comparable 与 Comparator',
    summary: '定义自然排序与自定义排序。',
    concepts: <String>['Comparable', 'Comparator', '排序'],
    objective: '能实现 Comparable 并用 Comparator 做多级排序。',
    explain:
        'Comparable 定义类的自然顺序（compareTo）；Comparator 是外部比较器，'
        '可写多套排序规则并链式组合。',
    code: '''import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class Main {
    record Person(String name, int age) {}

    public static void main(String[] args) {
        List<Person> people = new ArrayList<>(List.of(
            new Person("甲", 30),
            new Person("乙", 25),
            new Person("丙", 30)));
        people.sort(Comparator.comparingInt(Person::age).thenComparing(Person::name));
        System.out.println(people);
    }
}''',
    output: '[Person[name=乙, age=25], Person[name=丙, age=30], Person[name=甲, age=30]]',
    pitfalls: <String>['compareTo 返回负/零/正表示小于/等于/大于。', '排序会修改 List 顺序，需要保留原顺序时先复制。'],
  ),
  JavaTopic(
    id: 40,
    level: 'intermediate',
    title: 'Java 040：泛型方法',
    summary: '用类型参数编写可复用的泛型方法。',
    concepts: <String>['泛型', '类型参数', '类型安全'],
    objective: '能定义泛型方法并理解编译期类型检查。',
    explain:
        '泛型方法在方法级声明类型参数 `<T>`，调用时推断类型，提供编译期类型安全'
        '并避免强制转换。',
    code: '''import java.util.List;

public class Main {
    static <T> T first(List<T> items) {
        if (items.isEmpty()) {
            throw new IllegalArgumentException("empty");
        }
        return items.get(0);
    }

    public static void main(String[] args) {
        String s = first(List.of("a", "b"));
        Integer n = first(List.of(1, 2));
        System.out.println(s);
        System.out.println(n);
    }
}''',
    output: 'a\n1',
    pitfalls: <String>['泛型在运行时会擦除，不能 new T[]。', '基本类型不能作为类型参数，要用包装类。'],
  ),
  JavaTopic(
    id: 41,
    level: 'intermediate',
    title: 'Java 041：泛型通配符',
    summary: '理解 extends/super 上界下界与 PECS 原则。',
    concepts: <String>['通配符', '上界', '下界', 'PECS'],
    objective: '能用 extends/super 通配符提高泛型灵活性。',
    explain:
        '`? extends T` 只能读（生产者），`? super T` 只能写（消费者），即'
        'PECS（Producer Extends, Consumer Super）。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static double sum(List<? extends Number> numbers) {
        double total = 0;
        for (Number n : numbers) {
            total += n.doubleValue();
        }
        return total;
    }

    static void addInts(List<? super Integer> target) {
        target.add(1);
        target.add(2);
    }

    public static void main(String[] args) {
        System.out.println("sum=" + sum(List.of(1, 2.5, 3)));
        List<Number> numbers = new ArrayList<>();
        addInts(numbers);
        System.out.println(numbers);
    }
}''',
    output: 'sum=6.5\n[1, 2]',
    pitfalls: <String>['extends 的集合不能 add（除 null）。', 'super 的集合读出来只能当 Object。'],
  ),
  JavaTopic(
    id: 42,
    level: 'intermediate',
    title: 'Java 042：Arrays 实用方法',
    summary: '排序、查找、填充与转字符串。',
    concepts: <String>['Arrays', '排序', '二分查找'],
    objective: '能用 Arrays 的 sort/binarySearch/toString。',
    explain:
        'Arrays 提供数组的工具方法：sort 排序、binarySearch 二分查找（需先排序）、'
        'toString 打印、fill 填充。',
    code: '''import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        int[] values = {5, 1, 4, 2};
        Arrays.sort(values);
        System.out.println(Arrays.toString(values));
        System.out.println("index=" + Arrays.binarySearch(values, 4));
        int[] filled = new int[3];
        Arrays.fill(filled, 7);
        System.out.println(Arrays.toString(filled));
    }
}''',
    output: '[1, 2, 4, 5]\nindex=2\n[7, 7, 7]',
    pitfalls: <String>['binarySearch 前必须已排序。', '对对象数组排序要求元素可比较。'],
  ),
  JavaTopic(
    id: 43,
    level: 'intermediate',
    title: 'Java 043：迭代器与增强 for',
    summary: 'Iterator 的遍历与安全删除。',
    concepts: <String>['Iterator', '遍历', 'remove'],
    objective: '能用 Iterator 遍历并在循环中安全删除元素。',
    explain:
        '增强 for 底层就是 Iterator。需要在遍历时删除元素时要显式使用 Iterator.remove，'
        '否则会并发修改异常。',
    code: '''import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> numbers = new ArrayList<>(List.of(1, 2, 3, 4, 5, 6));
        Iterator<Integer> it = numbers.iterator();
        while (it.hasNext()) {
            if (it.next() % 2 == 0) {
                it.remove();
            }
        }
        System.out.println(numbers);
    }
}''',
    output: '[1, 3, 5]',
    pitfalls: <String>['直接 list.remove 会在遍历时抛异常。', 'next 每次前进一步，别重复调用。'],
  ),
  JavaTopic(
    id: 44,
    level: 'intermediate',
    title: 'Java 044：对象数组与 varargs 结合',
    summary: '用泛型+可变参数写通用的最大/查找工具。',
    concepts: <String>['泛型', '可变参数', '比较'],
    objective: '能编写接受可变参数的泛型工具方法。',
    explain:
        '把可变参数与泛型、Comparator 结合，可写出通用的集合工具方法。',
    code: '''import java.util.Comparator;

public class Main {
    @SafeVarargs
    static <T> T max(Comparator<T> comparator, T... items) {
        T best = items[0];
        for (T item : items) {
            if (comparator.compare(item, best) > 0) {
                best = item;
            }
        }
        return best;
    }

    public static void main(String[] args) {
        System.out.println(max(Integer::compare, 3, 9, 4));
        System.out.println(max(String::compareTo, "pear", "apple", "fig"));
    }
}''',
    output: '9\npear',
    pitfalls: <String>['泛型可变参数会引起警告，用 @SafeVarargs 声明安全。', '空参数数组会越界，需自行校验。'],
  ),
  JavaTopic(
    id: 45,
    level: 'intermediate',
    title: 'Java 045：综合练习：词频统计',
    summary: '用 Map 与正则统计一段文本的词频。',
    concepts: <String>['综合', 'Map', '正则', '排序'],
    objective: '能把集合、正则、排序组合成文本处理程序。',
    explain:
        '先用正则分词，再用 Map 计数，最后排序输出。这是文本处理常见套路。',
    code: '''import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Main {
    public static void main(String[] args) {
        String text = "the quick fox the lazy dog the fox";
        Map<String, Integer> count = new HashMap<>();
        for (String word : text.split("\\s+")) {
            count.put(word, count.getOrDefault(word, 0) + 1);
        }
        List<Map.Entry<String, Integer>> entries = new ArrayList<>(count.entrySet());
        entries.sort(Comparator.comparingInt((Map.Entry<String, Integer> e) -> e.getValue()).reversed().thenComparing(Map.Entry::getKey));
        for (Map.Entry<String, Integer> entry : entries) {
            System.out.println(entry.getKey() + " " + entry.getValue());
        }
    }
}''',
    output: 'the 3\nfox 2\ndog 1\nlazy 1\nquick 1',
    pitfalls: <String>['中文分词不能只按空格，需专门处理。', '排序比较器里注意类型推导。'],
  ),
  JavaTopic(
    id: 46,
    level: 'intermediate',
    title: 'Java 046：受检与非受检异常',
    summary: '区分 checked/unchecked 异常并选择处理方式。',
    concepts: <String>['异常', 'checked', 'unchecked', 'throws'],
    objective: '能识别受检异常并说明何时声明何时捕获。',
    explain:
        '受检异常（如 IOException）必须捕获或用 throws 声明；非受检异常（RuntimeException）'
        '通常代表编程错误，无需强制处理。',
    code: '''public class Main {
    static int parse(String text) {
        try {
            return Integer.parseInt(text);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    public static void main(String[] args) {
        System.out.println(parse("42"));
        System.out.println(parse("abc"));
    }
}''',
    output: '42\n-1',
    pitfalls: <String>['不要catch了什么都不做（吞异常）。', '能用校验避免的异常优于靠异常控制流程。'],
  ),
  JavaTopic(
    id: 47,
    level: 'intermediate',
    title: 'Java 047：try/catch/finally 与多捕获',
    summary: '多个 catch、finally 清理与异常传播。',
    concepts: <String>['try', 'catch', 'finally', '多捕获'],
    objective: '能编写带多捕获与 finally 的异常处理。',
    explain:
        '多个 catch 从上到下匹配；finally 总在最后执行，用于释放资源。'
        '可用 `catch (A | B e)` 合并同类处理。',
    code: '''public class Main {
    public static void main(String[] args) {
        System.out.println(run("10"));
        System.out.println(run("x"));
    }

    static String run(String value) {
        StringBuilder log = new StringBuilder();
        try {
            int number = Integer.parseInt(value);
            log.append("ok:").append(number);
        } catch (NumberFormatException e) {
            log.append("bad");
        } finally {
            log.append("|").append("done");
        }
        return log.toString();
    }
}''',
    output: 'ok:10|done\nbad|done',
    pitfalls: <String>['finally 里 return 会覆盖 try 的返回值，避免。', 'catch 顺序要从具体到宽泛。'],
  ),
  JavaTopic(
    id: 48,
    level: 'intermediate',
    title: 'Java 048：try-with-resources',
    summary: '自动关闭实现了 AutoCloseable 的资源。',
    concepts: <String>['try-with-resources', 'AutoCloseable', '资源管理'],
    objective: '能用 try-with-resources 保证资源关闭。',
    explain:
        '把资源声明在 try 的括号里，作用域结束时自动调用 close()，'
        '即使发生异常也不漏关。',
    code: '''public class Main {
    static class Resource implements AutoCloseable {
        final String name;

        Resource(String name) {
            this.name = name;
            System.out.println("open " + name);
        }

        @Override
        public void close() {
            System.out.println("close " + name);
        }
    }

    public static void main(String[] args) {
        try (Resource r = new Resource("db")) {
            System.out.println("using " + r.name);
        }
    }
}''',
    output: 'open db\nusing db\nclose db',
    pitfalls: <String>['资源必须实现 AutoCloseable。', '多个资源用分号分隔，按逆序关闭。'],
  ),
  JavaTopic(
    id: 49,
    level: 'intermediate',
    title: 'Java 049：自定义异常',
    summary: '定义业务异常类并携带上下文。',
    concepts: <String>['自定义异常', '继承', '上下文'],
    objective: '能定义业务异常并在合适层次抛出。',
    explain:
        '自定义异常通过继承异常类表达业务错误，可携带字段提供上下文，'
        '在调用边界统一处理。',
    code: '''public class Main {
    static class InsufficientFunds extends RuntimeException {
        final int shortfall;

        InsufficientFunds(int shortfall) {
            super("缺少 " + shortfall);
            this.shortfall = shortfall;
        }
    }

    static void withdraw(int balance, int amount) {
        if (amount > balance) {
            throw new InsufficientFunds(amount - balance);
        }
    }

    public static void main(String[] args) {
        try {
            withdraw(100, 130);
        } catch (InsufficientFunds e) {
            System.out.println(e.getMessage());
            System.out.println("shortfall=" + e.shortfall);
        }
    }
}''',
    output: '缺少 30\nshortfall=30',
    pitfalls: <String>['自定义异常应放在合适的包，不要都做成 RuntimeException。', '异常消息要可读，便于排错。'],
  ),
  JavaTopic(
    id: 50,
    level: 'intermediate',
    title: 'Java 050：Files 读写文本',
    summary: '用 java.nio Files 读写 UTF-8 文本文件。',
    concepts: <String>['Files', 'java.nio', 'UTF-8', 'Path'],
    objective: '能用 Files 读写文本并在临时目录内清理。',
    explain:
        'java.nio.file.Files 提供简洁的文本读写：writeString/readString，'
        '并支持按行读取。指定 UTF-8 避免平台编码差异。',
    code: '''import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class Main {
    public static void main(String[] args) throws Exception {
        Path file = Files.createTempFile("qfli", ".txt");
        try {
            Files.writeString(file, "第一行\\n第二行", StandardCharsets.UTF_8);
            String content = Files.readString(file, StandardCharsets.UTF_8);
            System.out.println("lines=" + content.lines().count());
            System.out.println("contains=" + content.contains("第二行"));
        } finally {
            Files.deleteIfExists(file);
        }
    }
}''',
    output: 'lines=2\ncontains=true',
    pitfalls: <String>['忘记删临时文件会残留。', '平台默认编码不同，读写要显式 UTF-8。'],
  ),
  JavaTopic(
    id: 51,
    level: 'intermediate',
    title: 'Java 051：按行读取与写入',
    summary: 'BufferedReader/BufferedWriter 流式处理。',
    concepts: <String>['BufferedReader', 'BufferedWriter', '流'],
    objective: '能用缓冲流逐行读写文件。',
    explain:
        '缓冲流减少系统调用，适合大文件。readLine 逐行读取，返回 null 表示结束，'
        '配合 try-with-resources 保证关闭。',
    code: '''import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.StringReader;
import java.io.StringWriter;

public class Main {
    public static void main(String[] args) throws Exception {
        StringWriter buffer = new StringWriter();
        try (BufferedWriter writer = new BufferedWriter(buffer)) {
            writer.write("a");
            writer.newLine();
            writer.write("b");
        }
        try (BufferedReader reader = new BufferedReader(new StringReader(buffer.toString()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                System.out.println("line:" + line);
            }
        }
    }
}''',
    output: 'line:a\nline:b',
    pitfalls: <String>['readLine 不包含行尾换行符。', '流用完必须关闭，否则句柄泄漏。'],
  ),
  JavaTopic(
    id: 52,
    level: 'intermediate',
    title: 'Java 052：路径与目录操作',
    summary: '用 Path/Files 创建目录、判断类型、列出内容。',
    concepts: <String>['Path', '目录', 'Files'],
    objective: '能用 Path 拼接路径并操作目录。',
    explain:
        'Path 表示路径，用 resolve 拼接而不是字符串相加，跨平台更安全。'
        'Files.createDirectories 创建多级目录，Files.list 遍历。',
    code: '''import java.nio.file.Files;
import java.nio.file.Path;

public class Main {
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("qfli_dir");
        try {
            Path nested = root.resolve("a").resolve("b");
            Files.createDirectories(nested);
            System.out.println("isDir=" + Files.isDirectory(nested));
            System.out.println("name=" + nested.getFileName());
            System.out.println("exists=" + Files.exists(nested));
        } finally {
            deleteRecursively(root);
        }
    }

    static void deleteRecursively(Path path) throws Exception {
        if (Files.isDirectory(path)) {
            try (var stream = Files.list(path)) {
                for (Path child : stream.toList()) {
                    deleteRecursively(child);
                }
            }
        }
        Files.deleteIfExists(path);
    }
}''',
    output: 'isDir=true\nname=b\nexists=true',
    pitfalls: <String>['用字符串拼接路径在不同平台会出错，用 resolve。', '递归删除要小心，仅限自己的临时目录。'],
  ),
  JavaTopic(
    id: 53,
    level: 'intermediate',
    title: 'Java 053：字节流与字符流',
    summary: '区分字节流（二进制）与字符流（文本）。',
    concepts: <String>['InputStream', 'Reader', '字节', '字符'],
    objective: '能按数据性质选择字节流或字符流。',
    explain:
        '字节流处理原始二进制，字符流按编码处理文本。图片用字节流，文本用字符流。'
        '两者之间用 InputStreamReader/OutputStreamWriter 桥接编码。',
    code: '''import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) throws Exception {
        byte[] bytes = "中文".getBytes(StandardCharsets.UTF_8);
        System.out.println("bytes=" + bytes.length);
        try (Reader reader = new InputStreamReader(new ByteArrayInputStream(bytes), StandardCharsets.UTF_8)) {
            int ch = reader.read();
            System.out.println("first=" + (char) ch);
        }
    }
}''',
    output: 'bytes=6\nfirst=中',
    pitfalls: <String>['一个中文字在 UTF-8 下是多字节，不能用单字节读。', '桥接流要显式指定编码。'],
  ),
  JavaTopic(
    id: 54,
    level: 'intermediate',
    title: 'Java 054：序列化基础',
    summary: '用 Java 序列化将对象转为字节再恢复。',
    concepts: <String>['Serializable', '序列化', '往返'],
    objective: '能序列化一个对象并反序列化回来。',
    explain:
        '实现 Serializable 的对象可被 ObjectOutputStream 写成字节，'
        '再用 ObjectInputStream 读回。用于本地持久化或传输。',
    code: '''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;

public class Main {
    record User(String name, int age) implements Serializable {}

    public static void main(String[] args) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(bytes)) {
            out.writeObject(new User("Alice", 30));
        }
        try (ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()))) {
            Object restored = in.readObject();
            System.out.println(restored);
        }
    }
}''',
    output: 'User[name=Alice, age=30]',
    pitfalls: <String>['序列化会受类版本影响，用 serialVersionUID 控制。', '不要反序列化不可信数据。'],
  ),
  JavaTopic(
    id: 55,
    level: 'intermediate',
    title: 'Java 055：字符编码与乱码',
    summary: '理解编码/解码一致性与乱码成因。',
    concepts: <String>['编码', '解码', 'UTF-8', '乱码'],
    objective: '能解释乱码成因并用一致的编码修复。',
    explain:
        '文本 = 字节 + 编码。用 A 编码写入、用 B 解码就会乱码。'
        '只要读写两侧使用同一编码（推荐 UTF-8）即可。',
    code: '''import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) {
        String text = "你好";
        byte[] utf8 = text.getBytes(StandardCharsets.UTF_8);
        String correct = new String(utf8, StandardCharsets.UTF_8);
        String wrong = new String(utf8, StandardCharsets.ISO_8859_1);
        System.out.println("correct=" + correct);
        System.out.println("wrongMatches=" + wrong.equals(text));
    }
}''',
    output: 'correct=你好\nwrongMatches=false',
    pitfalls: <String>['用平台默认编码会让代码在不同机器结果不同。', '修复乱码要看原始字节，不能凭空猜测。'],
  ),
  JavaTopic(
    id: 56,
    level: 'intermediate',
    title: 'Java 056：解析简单文本格式',
    summary: '手写一个 key=value 配置解析器。',
    concepts: <String>['解析', 'Map', '字符串处理'],
    objective: '能解析 key=value 文本为 Map。',
    explain:
        '解析就是把文本按规则拆解成结构化数据。这里按行、按第一个 = 拆分，'
        '跳过空行与注释。',
    code: '''import java.util.HashMap;
import java.util.Map;

public class Main {
    static Map<String, String> parse(String text) {
        Map<String, String> result = new HashMap<>();
        for (String line : text.split("\\n")) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                continue;
            }
            int index = trimmed.indexOf('=');
            if (index > 0) {
                result.put(trimmed.substring(0, index).trim(), trimmed.substring(index + 1).trim());
            }
        }
        return result;
    }

    public static void main(String[] args) {
        Map<String, String> config = parse("# 注释\\nhost = localhost\\nport=8080\\n");
        System.out.println("host=" + config.get("host"));
        System.out.println("port=" + config.get("port"));
        System.out.println("size=" + config.size());
    }
}''',
    output: 'host=localhost\nport=8080\nsize=2',
    pitfalls: <String>['值里含 = 时要用第一个等号分割。', '注意去掉键值两侧空白。'],
  ),
  JavaTopic(
    id: 57,
    level: 'intermediate',
    title: 'Java 057：生成器与 Iterable',
    summary: '实现 Iterable/Iterator 让对象可被 for 遍历。',
    concepts: <String>['Iterable', 'Iterator', '自定义遍历'],
    objective: '能实现 Iterable 让自定义结构支持增强 for。',
    explain:
        '实现 Iterable<T> 的 iterator() 方法后，对象可直接用于增强 for。'
        '适合封装内部数据结构。',
    code: '''import java.util.Iterator;
import java.util.NoSuchElementException;

public class Main {
    static class Range implements Iterable<Integer> {
        final int from;
        final int to;

        Range(int from, int to) {
            this.from = from;
            this.to = to;
        }

        @Override
        public Iterator<Integer> iterator() {
            return new Iterator<>() {
                int current = from;

                @Override
                public boolean hasNext() {
                    return current < to;
                }

                @Override
                public Integer next() {
                    if (!hasNext()) {
                        throw new NoSuchElementException();
                    }
                    return current++;
                }
            };
        }
    }

    public static void main(String[] args) {
        int total = 0;
        for (int value : new Range(1, 4)) {
            total += value;
        }
        System.out.println("total=" + total);
    }
}''',
    output: 'total=6',
    pitfalls: <String>['next 在无元素时要抛 NoSuchElementException。', '迭代器状态应为每次 iterator() 新建。'],
  ),
  JavaTopic(
    id: 58,
    level: 'intermediate',
    title: 'Java 058：资源泄漏与关闭顺序',
    summary: '多资源嵌套关闭与异常抑制。',
    concepts: <String>['资源', '关闭顺序', '异常抑制'],
    objective: '能解释多资源的关闭顺序与异常抑制。',
    explain:
        'try-with-resources 中多个资源按声明逆序关闭；关闭时的异常会被抑制，'
        '不会掩盖主异常。',
    code: '''public class Main {
    static class Res implements AutoCloseable {
        final String name;

        Res(String name) {
            this.name = name;
        }

        @Override
        public void close() {
            System.out.println("close " + name);
        }
    }

    public static void main(String[] args) {
        try (Res a = new Res("A"); Res b = new Res("B")) {
            System.out.println("work");
            throw new IllegalStateException("boom");
        } catch (IllegalStateException e) {
            System.out.println("caught " + e.getMessage());
        }
    }
}''',
    output: 'work\nclose B\nclose A\ncaught boom',
    pitfalls: <String>['关闭顺序是逆序，有依赖关系时要注意。', '不要把重要错误藏在关闭异常里。'],
  ),
  JavaTopic(
    id: 59,
    level: 'intermediate',
    title: 'Java 059：断言与防御式编程',
    summary: '用校验提前失败，用 assert 做开发期检查。',
    concepts: <String>['防御式编程', '校验', 'assert'],
    objective: '能在入口处校验参数，快速失败而不是静默错误。',
    explain:
        '在方法入口校验参数，非法就抛异常，让错误尽早暴露。'
        'assert 默认关闭，仅用于开发期不变式，不应用于业务校验。',
    code: '''import java.util.Objects;

public class Main {
    static int divide(int a, int b) {
        if (b == 0) {
            throw new IllegalArgumentException("除数不能为 0");
        }
        return a / b;
    }

    static String requireName(String name) {
        Objects.requireNonNull(name, "name 不能为空");
        if (name.isBlank()) {
            throw new IllegalArgumentException("name 不能为空白");
        }
        return name.trim();
    }

    public static void main(String[] args) {
        System.out.println(divide(10, 2));
        System.out.println(requireName("  ok  "));
        try {
            divide(1, 0);
        } catch (IllegalArgumentException e) {
            System.out.println("error=" + e.getMessage());
        }
    }
}''',
    output: '5\nok\nerror=除数不能为 0',
    pitfalls: <String>['业务校验不要依赖 assert（可能被禁用）。', '校验消息要明确指出哪个参数不合法。'],
  ),
  JavaTopic(
    id: 60,
    level: 'intermediate',
    title: 'Java 060：综合练习：日志分析器',
    summary: '读取多行日志，统计级别并处理异常行。',
    concepts: <String>['综合', 'IO', '异常', '统计'],
    objective: '能把 IO、异常、集合组合成一个小分析器。',
    explain:
        '模拟一行一条日志，按级别统计；对格式不正确的行记入错误计数而不中断。'
        '体现「坏数据不崩溃」的健壮性。',
    code: '''import java.util.HashMap;
import java.util.Map;

public class Main {
    public static void main(String[] args) {
        String[] lines = {"INFO boot", "ERROR disk", "INFO ready", "garbage", "WARN slow"};
        Map<String, Integer> levels = new HashMap<>();
        int malformed = 0;
        for (String line : lines) {
            String[] parts = line.split(" ", 2);
            if (parts.length != 2 || parts[0].isEmpty()) {
                malformed++;
                continue;
            }
            levels.put(parts[0], levels.getOrDefault(parts[0], 0) + 1);
        }
        System.out.println("INFO=" + levels.getOrDefault("INFO", 0));
        System.out.println("ERROR=" + levels.getOrDefault("ERROR", 0));
        System.out.println("malformed=" + malformed);
    }
}''',
    output: 'INFO=2\nERROR=1\nmalformed=1',
    pitfalls: <String>['split 限制次数可避免消息里的空格被切碎。', '坏数据要计数而不是直接崩溃。'],
  ),
  JavaTopic(
    id: 61,
    level: 'intermediate',
    title: 'Java 061：Lambda 入门',
    summary: '用 lambda 简洁地传递行为。',
    concepts: <String>['lambda', '函数式接口', '箭头'],
    objective: '能把匿名内部类改写为 lambda。',
    explain:
        'lambda 是函数式接口的紧凑写法：`(参数) -> 表达式`。它把「行为」当作参数传递，'
        '取代冗长的匿名类。',
    code: '''public class Main {
    interface Calc {
        int apply(int a, int b);
    }

    static int run(Calc calc, int a, int b) {
        return calc.apply(a, b);
    }

    public static void main(String[] args) {
        System.out.println(run((a, b) -> a + b, 3, 4));
        System.out.println(run((a, b) -> a * b, 3, 4));
    }
}''',
    output: '7\n12',
    pitfalls: <String>['lambda 只能用于函数式接口（单抽象方法）。', '带代码块的 lambda 要显式 return。'],
  ),
  JavaTopic(
    id: 62,
    level: 'intermediate',
    title: 'Java 062：内置函数式接口',
    summary: 'Function、Predicate、Supplier、Consumer 的用途。',
    concepts: <String>['Function', 'Predicate', 'Consumer', 'Supplier'],
    objective: '能根据输入输出选用内置函数式接口。',
    explain:
        'java.util.function 提供常用函数式接口：Function 变换、Predicate 判断、'
        'Consumer 消费、Supplier 供给，减少了自定义接口的需要。',
    code: '''import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.function.Supplier;

public class Main {
    public static void main(String[] args) {
        Function<Integer, Integer> square = x -> x * x;
        Predicate<Integer> isEven = x -> x % 2 == 0;
        Consumer<String> printer = s -> System.out.println("consume:" + s);
        Supplier<String> supplier = () -> "supplied";

        System.out.println("square=" + square.apply(5));
        System.out.println("isEven=" + isEven.test(4));
        printer.accept("data");
        System.out.println(supplier.get());
    }
}''',
    output: 'square=25\nisEven=true\nconsume:data\nsupplied',
    pitfalls: <String>['Function<T,R> 两个类型参数别写错顺序。', 'Predicate 是 test，Consumer 是 accept，名字不同。'],
  ),
  JavaTopic(
    id: 63,
    level: 'intermediate',
    title: 'Java 063：方法引用',
    summary: '用 :: 进一步简化 lambda。',
    concepts: <String>['方法引用', '::', '可读性'],
    objective: '能把直接转发到方法的 lambda 改写为方法引用。',
    explain:
        '当 lambda 只是调用一个已有方法时，可用方法引用：静态方法、实例方法、'
        '构造函数引用（类名::new）。',
    code: '''import java.util.List;
import java.util.function.Function;

public class Main {
    public static void main(String[] args) {
        Function<String, Integer> length = String::length;
        System.out.println("length=" + length.apply("java"));

        List<String> names = List.of("b", "a", "c").stream()
            .map(String::toUpperCase)
            .sorted()
            .toList();
        System.out.println(names);
    }
}''',
    output: 'length=4\n[A, B, C]',
    pitfalls: <String>['方法引用要求签名与函数式接口一致。', '实例方法引用 obj::m 与类方法引用 String::m 用处不同。'],
  ),
  JavaTopic(
    id: 64,
    level: 'intermediate',
    title: 'Java 064：Stream 的 map/filter',
    summary: '用流式操作变换与过滤集合。',
    concepts: <String>['Stream', 'map', 'filter', '链式'],
    objective: '能用 map/filter/collect 处理集合。',
    explain:
        'Stream 提供声明式处理：filter 过滤、map 变换、collect 收集。'
        '流是惰性的，遇到终止操作才执行。',
    code: '''import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> numbers = List.of(1, 2, 3, 4, 5, 6);
        List<Integer> evenSquares = numbers.stream()
            .filter(n -> n % 2 == 0)
            .map(n -> n * n)
            .toList();
        System.out.println(evenSquares);
        int sum = numbers.stream().mapToInt(Integer::intValue).sum();
        System.out.println("sum=" + sum);
    }
}''',
    output: '[4, 16, 36]\nsum=21',
    pitfalls: <String>['流只能消费一次，重复使用会报错。', '对基本类型用 mapToInt 避免装箱开销。'],
  ),
  JavaTopic(
    id: 65,
    level: 'intermediate',
    title: 'Java 065：Stream 的 reduce 与聚合',
    summary: '用 reduce/count/min/max 做归约。',
    concepts: <String>['reduce', '聚合', 'Optional'],
    objective: '能用 reduce 与聚合方法得到单一结果。',
    explain:
        'reduce 把流元素逐步合并成一个值，可带初始值。count/min/max 是常用聚合，'
        'min/max 返回 Optional。',
    code: '''import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> numbers = List.of(3, 1, 4, 1, 5);
        int sum = numbers.stream().reduce(0, Integer::sum);
        System.out.println("sum=" + sum);
        int max = numbers.stream().reduce(Integer.MIN_VALUE, Math::max);
        System.out.println("max=" + max);
        long count = numbers.stream().filter(n -> n > 2).count();
        System.out.println("count=" + count);
    }
}''',
    output: 'sum=14\nmax=5\ncount=3',
    pitfalls: <String>['带初始值的 reduce 要用单位元（加法的 0）。', '空流 reduce 无初始值返回 Optional。'],
  ),
  JavaTopic(
    id: 66,
    level: 'intermediate',
    title: 'Java 066：Collectors 分组与统计',
    summary: 'groupingBy/counting/joining 常见收集器。',
    concepts: <String>['Collectors', 'groupingBy', 'joining'],
    objective: '能用 Collectors 做分组、连接与统计。',
    explain:
        'Collectors 提供丰富的收集策略：groupingBy 分组、counting 计数、'
        'joining 连接字符串、summingInt 求和。',
    code: '''import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public class Main {
    record Fruit(String name, String color) {}

    public static void main(String[] args) {
        List<Fruit> fruits = List.of(
            new Fruit("apple", "red"),
            new Fruit("banana", "yellow"),
            new Fruit("cherry", "red"));
        Map<String, List<String>> byColor = fruits.stream()
            .collect(Collectors.groupingBy(Fruit::color, Collectors.mapping(Fruit::name, Collectors.toList())));
        System.out.println("red=" + byColor.get("red"));
        String joined = fruits.stream().map(Fruit::name).collect(Collectors.joining(","));
        System.out.println("joined=" + joined);
    }
}''',
    output: 'red=[apple, cherry]\njoined=apple,banana,cherry',
    pitfalls: <String>['groupingBy 返回 Map，遍历顺序不固定。', 'joining 需要流元素是字符串。'],
  ),
  JavaTopic(
    id: 67,
    level: 'intermediate',
    title: 'Java 067：Stream 的 flatMap',
    summary: '把嵌套集合展平成一维流。',
    concepts: <String>['flatMap', '展平', '嵌套集合'],
    objective: '能用 flatMap 展平 List<List<T>>。',
    explain:
        'flatMap 把每个元素映射成一个流，再合并为一个流；map 则是 1:1 变换。'
        '处理嵌套结构时用 flatMap。',
    code: '''import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<List<Integer>> nested = List.of(List.of(1, 2), List.of(3, 4));
        List<Integer> flat = nested.stream().flatMap(List::stream).toList();
        System.out.println(flat);

        List<String> letters = List.of("ab", "cd").stream()
            .flatMap(s -> s.chars().mapToObj(c -> String.valueOf((char) c)))
            .toList();
        System.out.println(letters);
    }
}''',
    output: '[1, 2, 3, 4]\n[a, b, c, d]',
    pitfalls: <String>['map 得到嵌套流，flatMap 才展平。', '流元素类型在 flatMap 后可能改变。'],
  ),
  JavaTopic(
    id: 68,
    level: 'intermediate',
    title: 'Java 068：Stream 的排序与去重',
    summary: 'sorted/distinct/limit/skip 组合。',
    concepts: <String>['sorted', 'distinct', 'limit', 'skip'],
    objective: '能对流做排序、去重和截取。',
    explain:
        'sorted 排序（可传 Comparator）、distinct 去重、limit 取前 N、'
        'skip 跳过前 N。可链式组合。',
    code: '''import java.util.Comparator;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> values = List.of(5, 3, 5, 1, 4, 3);
        List<Integer> top = values.stream()
            .distinct()
            .sorted(Comparator.reverseOrder())
            .limit(3)
            .toList();
        System.out.println(top);
        System.out.println(values.stream().skip(2).findFirst().orElse(-1));
    }
}''',
    output: '[5, 4, 3]\n5',
    pitfalls: <String>['sorted 会消耗流并缓存全部元素。', 'findFirst 返回 Optional。'],
  ),
  JavaTopic(
    id: 69,
    level: 'intermediate',
    title: 'Java 069：流与副作用',
    summary: 'forEach 与 peek，以及为什么应避免副作用。',
    concepts: <String>['forEach', 'peek', '副作用'],
    objective: '能在终止操作中输出，并知道不应在流里改共享状态。',
    explain:
        'forEach 是终止操作，用于遍历输出。peek 是调试用中间操作。'
        '流应尽量无副作用，避免在中间操作里修改外部集合。',
    code: '''import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<String> names = List.of("a", "b", "c");
        names.stream()
            .peek(name -> System.out.println("peek:" + name))
            .filter(name -> !name.equals("b"))
            .forEach(name -> System.out.println("keep:" + name));
    }
}''',
    output: 'peek:a\nkeep:a\npeek:b\npeek:c\nkeep:c',
    pitfalls: <String>['peek 无终止操作时不会执行。', '在流操作里修改外部集合可能导致错误结果。'],
  ),
  JavaTopic(
    id: 70,
    level: 'intermediate',
    title: 'Java 070：并行流',
    summary: 'parallelStream 提升计算密集任务性能与风险。',
    concepts: <String>['并行流', 'parallel', '线程安全'],
    objective: '能安全地使用并行流做无状态计算。',
    explain:
        'parallelStream 把工作分给多线程。对无状态、计算密集且数据量大的任务有效；'
        '有共享可变状态时会出错，数据量小时反而更慢。',
    code: '''import java.util.stream.LongStream;

public class Main {
    public static void main(String[] args) {
        long sequential = LongStream.rangeClosed(1, 1_000_000).sum();
        long parallel = LongStream.rangeClosed(1, 1_000_000).parallel().sum();
        System.out.println("sequential=" + sequential);
        System.out.println("parallel=" + parallel);
        System.out.println("equal=" + (sequential == parallel));
    }
}''',
    output: 'sequential=500000500000\nparallel=500000500000\nequal=true',
    pitfalls: <String>['并行流里修改共享变量会得到错误结果。', '小数据量用并行流得不偿失。'],
  ),
  JavaTopic(
    id: 71,
    level: 'intermediate',
    title: 'Java 071：CompletableFuture 异步组合',
    summary: '用 thenApply/thenCombine 组合异步结果。',
    concepts: <String>['CompletableFuture', '异步', 'thenApply'],
    objective: '能用 CompletableFuture 串行与并行组合异步任务。',
    explain:
        'supplyAsync 提交异步任务；thenApply 变换结果，thenCombine 合并两个任务，'
        'join 阻塞等结果（类似 Future.get）。',
    code: '''import java.util.concurrent.CompletableFuture;

public class Main {
    public static void main(String[] args) {
        CompletableFuture<Integer> a = CompletableFuture.supplyAsync(() -> 10);
        CompletableFuture<Integer> b = CompletableFuture.supplyAsync(() -> 20);
        int result = a.thenCombine(b, Integer::sum).join();
        System.out.println("sum=" + result);
        int doubled = a.thenApply(x -> x * 2).join();
        System.out.println("doubled=" + doubled);
    }
}''',
    output: 'sum=30\ndoubled=20',
    pitfalls: <String>['join/get 在异步未完成时会阻塞。', '未捕获的异步异常会随 join 抛出 CompletionException。'],
  ),
  JavaTopic(
    id: 72,
    level: 'intermediate',
    title: 'Java 072：Optional 与 Stream 结合',
    summary: '用 findFirst/filter 返回 Optional 并安全处理。',
    concepts: <String>['Optional', 'Stream', 'findFirst'],
    objective: '能把流查找结果用 Optional 安全地取用。',
    explain:
        'findFirst/findAny 返回 Optional，配合 filter 与 orElse/map 可在缺失时'
        '优雅处理，避免 null。',
    code: '''import java.util.List;
import java.util.Optional;

public class Main {
    public static void main(String[] args) {
        List<String> names = List.of("ann", "bob", "carol");
        Optional<String> found = names.stream()
            .filter(n -> n.startsWith("c"))
            .findFirst();
        System.out.println(found.orElse("none"));
        System.out.println(found.map(String::length).orElse(0));
        System.out.println(names.stream().filter(n -> n.startsWith("z")).findFirst().orElse("none"));
    }
}''',
    output: 'carol\n5\nnone',
    pitfalls: <String>['orElse 的参数总会被求值，成本高时用 orElseGet。', 'findAny 在并行流里不保证第一个。'],
  ),
  JavaTopic(
    id: 73,
    level: 'intermediate',
    title: 'Java 073：函数式管道综合',
    summary: '把 map/filter/sorted/collect 组合成完整数据管道。',
    concepts: <String>['管道', '综合', 'Stream'],
    objective: '能把多个流操作组合成清晰的数据处理管道。',
    explain:
        '真实处理往往是「过滤 -> 变换 -> 排序 -> 收集」的管道。'
        '把每步拆开比嵌套循环更易读。',
    code: '''import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public class Main {
    record Order(String product, int amount) {}

    public static void main(String[] args) {
        List<Order> orders = List.of(
            new Order("pen", 3),
            new Order("book", 1),
            new Order("pen", 2),
            new Order("bag", 5));
        Map<String, Integer> totals = orders.stream()
            .collect(Collectors.groupingBy(Order::product, Collectors.summingInt(Order::amount)));
        List<String> top = totals.entrySet().stream()
            .sorted(
                Map.Entry.<String, Integer>comparingByValue()
                    .reversed()
                    .thenComparing(Map.Entry.comparingByKey()))
            .map(entry -> entry.getKey() + "=" + entry.getValue())
            .toList();
        System.out.println(top);
    }
}''',
    output: '[bag=5, pen=5, book=1]',
    pitfalls: <String>['排序 Map.Entry 需要显式类型参数。', '值相同时必须加次级排序，否则顺序不稳定。'],
  ),
  JavaTopic(
    id: 74,
    level: 'intermediate',
    title: 'Java 074：Stream 与 IO 结合',
    summary: '用 Files.lines 流式处理文件行。',
    concepts: <String>['Files.lines', 'Stream', 'IO'],
    objective: '能用 Files.lines 按行流式处理并在结束后关闭。',
    explain:
        'Files.lines 返回一个 Stream<String>，惰性读行，适合大文件。'
        '它携带打开的文件句柄，必须用 try-with-resources 关闭。',
    code: '''import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws Exception {
        Path file = Files.createTempFile("qfli_lines", ".txt");
        Files.writeString(file, "alpha\\nbeta\\ngamma", StandardCharsets.UTF_8);
        try (Stream<String> lines = Files.lines(file, StandardCharsets.UTF_8)) {
            long count = lines.filter(line -> line.length() == 5).count();
            System.out.println("five=" + count);
        } finally {
            Files.deleteIfExists(file);
        }
        System.out.println("done");
    }
}''',
    output: 'five=2\ndone',
    pitfalls: <String>['Files.lines 必须关闭，否则文件句柄泄漏。', '流已关闭后再使用会报 IllegalStateException。'],
  ),
  JavaTopic(
    id: 75,
    level: 'intermediate',
    title: 'Java 075：综合练习：排行榜',
    summary: '解析得分记录并生成排名。',
    concepts: <String>['综合', 'Stream', 'collect', '排序'],
    objective: '能把集合、流、排序组合成一个排行榜。',
    explain:
        '把「名字:分数」解析成对象，按分数降序排名，同分按名字升序，'
        '练习流管道的真实用法。',
    code: '''import java.util.Comparator;
import java.util.List;

public class Main {
    record Score(String name, int score) {}

    public static void main(String[] args) {
        String[] raw = {"ann:80", "bob:95", "cara:80"};
        List<Score> scores = java.util.Arrays.stream(raw)
            .map(entry -> entry.split(":"))
            .map(parts -> new Score(parts[0], Integer.parseInt(parts[1])))
            .toList();
        List<String> ranking = scores.stream()
            .sorted(Comparator.comparingInt(Score::score).reversed().thenComparing(Score::name))
            .map(score -> score.name() + ":" + score.score())
            .toList();
        System.out.println(ranking);
    }
}''',
    output: '[bob:95, ann:80, cara:80]',
    pitfalls: <String>['降序后再按名字升序要用 thenComparing 链式。', '解析失败要有容错，这里假定格式正确。'],
  ),
  JavaTopic(
    id: 76,
    level: 'advanced',
    title: 'Java 076：创建线程',
    summary: '用 Thread 与 Runnable 启动线程。',
    concepts: <String>['Thread', 'Runnable', 'start'],
    objective: '能创建并启动一个线程，理解 start 与 run 的区别。',
    explain:
        '线程代表一条执行流。实现 Runnable 传给 Thread，或直接继承 Thread。'
        '必须调用 start() 才会开新线程；直接调 run() 只是普通方法。',
    code: '''public class Main {
    public static void main(String[] args) throws InterruptedException {
        Thread worker = new Thread(() -> System.out.println("worker running"));
        worker.start();
        worker.join();
        System.out.println("main done");
    }
}''',
    output: 'worker running\nmain done',
    pitfalls: <String>['调 run() 不会开新线程。', '线程调度顺序不确定，输出顺序不保证。'],
  ),
  JavaTopic(
    id: 77,
    level: 'advanced',
    title: 'Java 077：竞态条件与 synchronized',
    summary: '多个线程改共享变量会出错，用锁保护。',
    concepts: <String>['竞态', 'synchronized', '原子性'],
    objective: '能识别竞态并用 synchronized 修复。',
    explain:
        '`count++` 不是原子操作（读-改-写），并发下会丢失更新。'
        '用 synchronized 让临界区互斥，保证同一时刻只有一个线程执行。',
    code: '''public class Main {
    static int count = 0;

    static synchronized void increment() {
        count++;
    }

    public static void main(String[] args) throws InterruptedException {
        Thread[] threads = new Thread[4];
        for (int i = 0; i < threads.length; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 1000; j++) {
                    increment();
                }
            });
            threads[i].start();
        }
        for (Thread thread : threads) {
            thread.join();
        }
        System.out.println("count=" + count);
    }
}''',
    output: 'count=4000',
    pitfalls: <String>['synchronized 保护的对象要一致，否则锁不住。', '锁范围过大影响性能，过小则不安全。'],
  ),
  JavaTopic(
    id: 78,
    level: 'advanced',
    title: 'Java 078：Atomic 原子类',
    summary: '用 AtomicInteger 做无锁原子计数。',
    concepts: <String>['AtomicInteger', 'CAS', '无锁'],
    objective: '能用原子类替代锁实现简单计数。',
    explain:
        '原子类基于 CAS（比较并交换）实现无锁并发，incrementAndGet 等操作是原子的，'
        '适合简单的共享计数。',
    code: '''import java.util.concurrent.atomic.AtomicInteger;

public class Main {
    public static void main(String[] args) throws InterruptedException {
        AtomicInteger counter = new AtomicInteger();
        Thread[] threads = new Thread[4];
        for (int i = 0; i < threads.length; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 1000; j++) {
                    counter.incrementAndGet();
                }
            });
            threads[i].start();
        }
        for (Thread thread : threads) {
            thread.join();
        }
        System.out.println("counter=" + counter.get());
    }
}''',
    output: 'counter=4000',
    pitfalls: <String>['多个原子操作组合起来仍不是原子，需要用锁。', 'CAS 在高竞争下会自旋重试。'],
  ),
  JavaTopic(
    id: 79,
    level: 'advanced',
    title: 'Java 079：线程池 ExecutorService',
    summary: '用线程池提交任务并收集结果。',
    concepts: <String>['ExecutorService', '线程池', 'Future'],
    objective: '能用线程池提交任务并获取 Future 结果。',
    explain:
        '直接 new Thread 开销大且难复用。ExecutorService 管理一组线程，'
        'submit 返回 Future，shutdown 后等待完成。',
    code: '''import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class Main {
    public static void main(String[] args) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            Future<Integer> a = pool.submit(() -> 1 + 1);
            Future<Integer> b = pool.submit(() -> 2 * 3);
            System.out.println("a=" + a.get());
            System.out.println("b=" + b.get());
        } finally {
            pool.shutdown();
        }
    }
}''',
    output: 'a=2\nb=6',
    pitfalls: <String>['忘记 shutdown 会导致线程不退出。', 'Future.get 会阻塞直到任务完成。'],
  ),
  JavaTopic(
    id: 80,
    level: 'advanced',
    title: 'Java 080：Callable 与超时',
    summary: '带返回值和超时的任务。',
    concepts: <String>['Callable', '超时', 'Future'],
    objective: '能用 Callable 返回值并在 get 里设置超时。',
    explain:
        'Callable 与 Runnable 类似但能返回值并抛异常；Future.get(timeout) 在超时时'
        '抛 TimeoutException，避免无限等待。',
    code: '''import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

public class Main {
    public static void main(String[] args) throws Exception {
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try {
            Callable<String> slow = () -> {
                Thread.sleep(500);
                return "done";
            };
            var future = pool.submit(slow);
            try {
                System.out.println(future.get(100, TimeUnit.MILLISECONDS));
            } catch (TimeoutException e) {
                System.out.println("timeout");
            }
            System.out.println(future.get());
        } finally {
            pool.shutdown();
        }
    }
}''',
    output: 'timeout\ndone',
    pitfalls: <String>['超时不会取消任务，需要时手动 cancel。', '被中断的 sleep 会抛 InterruptedException。'],
  ),
  JavaTopic(
    id: 81,
    level: 'advanced',
    title: 'Java 081：并发集合',
    summary: '用 ConcurrentHashMap 安全并发读写。',
    concepts: <String>['ConcurrentHashMap', '并发集合', '分段锁'],
    objective: '能在多线程下使用并发安全集合。',
    explain:
        '普通 HashMap 并发修改会损坏内部结构。ConcurrentHashMap 提供高并发下的安全访问，'
        'compute/merge 等操作是原子的。',
    code: '''import java.util.concurrent.ConcurrentHashMap;

public class Main {
    public static void main(String[] args) throws InterruptedException {
        ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();
        Thread[] threads = new Thread[4];
        for (int i = 0; i < threads.length; i++) {
            threads[i] = new Thread(() -> {
                for (int j = 0; j < 500; j++) {
                    map.merge("hits", 1, Integer::sum);
                }
            });
            threads[i].start();
        }
        for (Thread thread : threads) {
            thread.join();
        }
        System.out.println("hits=" + map.get("hits"));
    }
}''',
    output: 'hits=2000',
    pitfalls: <String>['复合操作（判断再 put）要改用 compute/merge/putIfAbsent。', 'ConcurrentHashMap 不允许 null 键值。'],
  ),
  JavaTopic(
    id: 82,
    level: 'advanced',
    title: 'Java 082：CountDownLatch 协调',
    summary: '用倒计时门塞等待多个任务完成。',
    concepts: <String>['CountDownLatch', '同步', '等待'],
    objective: '能用 CountDownLatch 等待一组线程全部就绪。',
    explain:
        'CountDownLatch 初始化计数，每个线程完成后 countDown，主线程 await 直到计数归零，'
        '用于「等全部完成」的场景。',
    code: '''import java.util.concurrent.CountDownLatch;

public class Main {
    public static void main(String[] args) throws InterruptedException {
        int workers = 3;
        CountDownLatch latch = new CountDownLatch(workers);
        for (int i = 0; i < workers; i++) {
            new Thread(() -> {
                System.out.println("work done");
                latch.countDown();
            }).start();
        }
        latch.await();
        System.out.println("all done");
    }
}''',
    output: 'work done\nwork done\nwork done\nall done',
    pitfalls: <String>['latch 只能倒计一次，不能重复使用（用 CyclicBarrier）。', '忘记 countDown 会永久阻塞。'],
  ),
  JavaTopic(
    id: 83,
    level: 'advanced',
    title: 'Java 083：volatile 可见性',
    summary: 'volatile 保证可见性但不保证原子性。',
    concepts: <String>['volatile', '可见性', '内存模型'],
    objective: '能解释 volatile 的作用与局限。',
    explain:
        'volatile 让一个线程的写入对其他线程立即可见，适合状态标志位。'
        '但它不保证复合操作（如 ++）的原子性。',
    code: '''public class Main {
    static volatile boolean running = true;

    public static void main(String[] args) throws InterruptedException {
        Thread worker = new Thread(() -> {
            while (running) {
                // busy wait until the flag flips
            }
            System.out.println("stopped");
        });
        worker.start();
        Thread.sleep(100);
        running = false;
        worker.join();
        System.out.println("main done");
    }
}''',
    output: 'stopped\nmain done',
    pitfalls: <String>['volatile 不能保证 ++ 的原子性。', '无 volatile 时循环可能永远看不到新值。'],
  ),
  JavaTopic(
    id: 84,
    level: 'advanced',
    title: 'Java 084：死锁与避免',
    summary: '锁顺序不当会造成死锁，统一加锁顺序可避免。',
    concepts: <String>['死锁', '锁顺序', 'synchronized'],
    objective: '能识别死锁条件并用统一锁顺序避免。',
    explain:
        'Thread1 持有 A 等 B、Thread2 持有 B 等 A 时相互等待，形成死锁。'
        '让所有线程按同一全局顺序获取锁即可避免。',
    code: '''public class Main {
    static final Object LOCK_A = new Object();
    static final Object LOCK_B = new Object();

    static void transferAB() {
        synchronized (LOCK_A) {
            synchronized (LOCK_B) {
                System.out.println("AB");
            }
        }
    }

    static void transferBA() {
        synchronized (LOCK_A) {
            synchronized (LOCK_B) {
                System.out.println("BA");
            }
        }
    }

    public static void main(String[] args) throws InterruptedException {
        Thread t1 = new Thread(Main::transferAB);
        Thread t2 = new Thread(Main::transferBA);
        t1.start();
        t2.start();
        t1.join();
        t2.join();
        System.out.println("finished");
    }
}''',
    output: 'AB\nBA\nfinished',
    pitfalls: <String>['两个方法用了不同顺序就会死锁（此处故意统一）。', '死锁难以复现，需靠设计避免。'],
  ),
  JavaTopic(
    id: 85,
    level: 'advanced',
    title: 'Java 085：综合练习：并发下载模拟',
    summary: '用线程池并发处理任务并汇总结果。',
    concepts: <String>['综合', '线程池', 'Future'],
    objective: '能把线程池与 Future 组合成并发批量处理。',
    explain:
        '模拟多个下载任务并发执行，每个返回字节数，主线程汇总。'
        '体现「提交-收集-汇总」的并发模式。',
    code: '''import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class Main {
    public static void main(String[] args) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(3);
        try {
            Callable<Integer>[] tasks = new Callable[] {
                (Callable<Integer>) () -> 100,
                (Callable<Integer>) () -> 200,
                (Callable<Integer>) () -> 300
            };
            int total = 0;
            for (Callable<Integer> task : tasks) {
                Future<Integer> future = pool.submit(task);
                total += future.get();
            }
            System.out.println("total=" + total);
        } finally {
            pool.shutdown();
        }
    }
}''',
    output: 'total=600',
    pitfalls: <String>['逐个 get 会串行等待，可先全部提交再收集。', '线程池大小要与任务性质匹配。'],
  ),
  JavaTopic(
    id: 86,
    level: 'advanced',
    title: 'Java 086：单例模式',
    summary: '用枚举或持有类实现线程安全单例。',
    concepts: <String>['单例', '设计模式', '线程安全'],
    objective: '能实现线程安全的单例并说明枚举写法的优势。',
    explain:
        '单例保证全局唯一实例。枚举单例天然线程安全、防反射/序列化破坏，'
        '是最推荐的写法。',
    code: '''public class Main {
    enum Config {
        INSTANCE;

        String value = "default";
    }

    public static void main(String[] args) {
        Config a = Config.INSTANCE;
        Config b = Config.INSTANCE;
        a.value = "changed";
        System.out.println("same=" + (a == b));
        System.out.println("value=" + b.value);
    }
}''',
    output: 'same=true\nvalue=changed',
    pitfalls: <String>['双重检查锁写法容易写错，优先用枚举或静态持有类。', '单例不要做成可变的全局状态黑洞。'],
  ),
  JavaTopic(
    id: 87,
    level: 'advanced',
    title: 'Java 087：工厂模式',
    summary: '用工厂方法隐藏对象创建细节。',
    concepts: <String>['工厂', '多态', '解耦'],
    objective: '能用工厂根据参数返回不同实现。',
    explain:
        '工厂把「创建什么」与「如何使用」解耦：调用方只依赖接口，'
        '由工厂决定具体类型，便于扩展。',
    code: '''public class Main {
    interface Payment {
        String pay(int amount);
    }

    static class Alipay implements Payment {
        @Override
        public String pay(int amount) {
            return "支付宝支付 " + amount;
        }
    }

    static class WeChat implements Payment {
        @Override
        public String pay(int amount) {
            return "微信支付 " + amount;
        }
    }

    static Payment create(String channel) {
        return switch (channel) {
            case "alipay" -> new Alipay();
            case "wechat" -> new WeChat();
            default -> throw new IllegalArgumentException("未知渠道: " + channel);
        };
    }

    public static void main(String[] args) {
        System.out.println(create("alipay").pay(100));
        System.out.println(create("wechat").pay(200));
    }
}''',
    output: '支付宝支付 100\n微信支付 200',
    pitfalls: <String>['新增类型时要修改工厂，注意单一职责。', '工厂适合创建逻辑复杂的情况，简单对象无需过度设计。'],
  ),
  JavaTopic(
    id: 88,
    level: 'advanced',
    title: 'Java 088：建造者模式',
    summary: '用链式建造者构造多参对象。',
    concepts: <String>['建造者', '链式调用', '可读性'],
    objective: '能用 builder 链式构造参数较多的对象。',
    explain:
        '参数多时构造器难读难用。建造者用链式设置可选字段，最后 build()，'
        '既清晰又能校验必填项。',
    code: '''public class Main {
    static final class Request {
        private final String url;
        private final String method;
        private final int timeout;

        private Request(Builder builder) {
            this.url = builder.url;
            this.method = builder.method;
            this.timeout = builder.timeout;
        }

        static final class Builder {
            private final String url;
            private String method = "GET";
            private int timeout = 1000;

            Builder(String url) {
                this.url = url;
            }

            Builder method(String method) {
                this.method = method;
                return this;
            }

            Builder timeout(int timeout) {
                this.timeout = timeout;
                return this;
            }

            Request build() {
                return new Request(this);
            }
        }

        String describe() {
            return method + " " + url + " (" + timeout + "ms)";
        }
    }

    public static void main(String[] args) {
        Request request = new Request.Builder("/api").method("POST").timeout(2000).build();
        System.out.println(request.describe());
    }
}''',
    output: 'POST /api (2000ms)',
    pitfalls: <String>['必填项放在 Builder 构造器里，可选字段用链式方法。', 'builder 不要对外暴露可变中间状态。'],
  ),
  JavaTopic(
    id: 89,
    level: 'advanced',
    title: 'Java 089：策略模式',
    summary: '把可互换算法封装成策略对象。',
    concepts: <String>['策略', '多态', '可扩展'],
    objective: '能用策略模式替换多个 if/else 分支。',
    explain:
        '策略模式把每种算法封装成实现同一接口的类，运行时注入不同实现，'
        '避免大量分支且便于新增算法。',
    code: '''import java.util.List;
import java.util.function.Function;

public class Main {
    static int discount(String strategy, int price) {
        Function<Integer, Integer> fn = switch (strategy) {
            case "none" -> p -> p;
            case "percent10" -> p -> p * 9 / 10;
            case "minus20" -> p -> p - 20;
            default -> throw new IllegalArgumentException("未知策略");
        };
        return fn.apply(price);
    }

    public static void main(String[] args) {
        List<String> strategies = List.of("none", "percent10", "minus20");
        for (String strategy : strategies) {
            System.out.println(strategy + "=" + discount(strategy, 100));
        }
    }
}''',
    output: 'none=100\npercent10=90\nminus20=80',
    pitfalls: <String>['策略对象应无状态，保持不变性。', '简单分支无需强行套模式。'],
  ),
  JavaTopic(
    id: 90,
    level: 'advanced',
    title: 'Java 090：观察者模式',
    summary: '一对多依赖：状态变化自动通知订阅者。',
    concepts: <String>['观察者', '订阅', '解耦'],
    objective: '能实现发布-订阅的通知机制。',
    explain:
        '被观察者维护观察者列表，状态变化时逐个通知。观察者只需实现回调接口，'
        '发布方与订阅方解耦。',
    code: '''import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

public class Main {
    static class NewsAgency {
        private final List<Consumer<String>> observers = new ArrayList<>();

        void subscribe(Consumer<String> observer) {
            observers.add(observer);
        }

        void publish(String news) {
            for (Consumer<String> observer : observers) {
                observer.accept(news);
            }
        }
    }

    public static void main(String[] args) {
        NewsAgency agency = new NewsAgency();
        agency.subscribe(news -> System.out.println("订阅者A: " + news));
        agency.subscribe(news -> System.out.println("订阅者B: " + news));
        agency.publish("Hello");
    }
}''',
    output: '订阅者A: Hello\n订阅者B: Hello',
    pitfalls: <String>['单个观察者抛异常会影响其他人，需隔离。', '记得取消订阅避免内存泄漏。'],
  ),
  JavaTopic(
    id: 91,
    level: 'advanced',
    title: 'Java 091：冒泡排序与二分查找',
    summary: '手写基础排序与有序数组查找。',
    concepts: <String>['排序', '二分查找', '复杂度'],
    objective: '能实现冒泡排序与二分查找并说明复杂度。',
    explain:
        '冒泡排序相邻比较交换，O(n^2)；二分查找要求已排序，每次折半，O(log n)。',
    code: '''import java.util.Arrays;

public class Main {
    static void bubbleSort(int[] values) {
        for (int i = 0; i < values.length - 1; i++) {
            for (int j = 0; j < values.length - 1 - i; j++) {
                if (values[j] > values[j + 1]) {
                    int temp = values[j];
                    values[j] = values[j + 1];
                    values[j + 1] = temp;
                }
            }
        }
    }

    static int binarySearch(int[] sorted, int target) {
        int low = 0;
        int high = sorted.length - 1;
        while (low <= high) {
            int mid = (low + high) >>> 1;
            if (sorted[mid] == target) {
                return mid;
            } else if (sorted[mid] < target) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        return -1;
    }

    public static void main(String[] args) {
        int[] values = {5, 2, 9, 1, 7};
        bubbleSort(values);
        System.out.println(Arrays.toString(values));
        System.out.println("index=" + binarySearch(values, 7));
        System.out.println("missing=" + binarySearch(values, 3));
    }
}''',
    output: '[1, 2, 5, 7, 9]\nindex=3\nmissing=-1',
    pitfalls: <String>['二分查找前必须已排序。', '(low+high) 可能溢出，用无符号右移。'],
  ),
  JavaTopic(
    id: 92,
    level: 'advanced',
    title: 'Java 092：递归与动态规划',
    summary: '用记忆化把指数级递归降为线性。',
    concepts: <String>['动态规划', '记忆化', '递归'],
    objective: '能用记忆化优化重复子问题。',
    explain:
        '朴素斐波那契重复计算子问题是指数级。用数组缓存已算结果，'
        '每个值只算一次，降到 O(n)。',
    code: '''import java.util.Arrays;

public class Main {
    static long fib(int n, long[] memo) {
        if (n <= 1) {
            return n;
        }
        if (memo[n] != -1) {
            return memo[n];
        }
        memo[n] = fib(n - 1, memo) + fib(n - 2, memo);
        return memo[n];
    }

    public static void main(String[] args) {
        int n = 40;
        long[] memo = new long[n + 1];
        Arrays.fill(memo, -1);
        System.out.println("fib=" + fib(n, memo));
    }
}''',
    output: 'fib=102334155',
    pitfalls: <String>['memo 要用 -1 初始化区分未计算。', '注意大数溢出，可用 long 或 BigInteger。'],
  ),
  JavaTopic(
    id: 93,
    level: 'advanced',
    title: 'Java 093：图遍历 DFS/BFS',
    summary: '用栈/队列实现图搜索。',
    concepts: <String>['图', 'DFS', 'BFS', '访问标记'],
    objective: '能实现广度优先遍历并访问每个节点一次。',
    explain:
        'BFS 用队列逐层扩展，DFS 用栈深入。都要用 visited 标记避免重复访问与环。',
    code: '''import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;

public class Main {
    public static void main(String[] args) {
        Map<String, List<String>> graph = new HashMap<>();
        graph.put("A", List.of("B", "C"));
        graph.put("B", List.of("D"));
        graph.put("C", List.of("D"));
        graph.put("D", List.of());

        List<String> order = new ArrayList<>();
        Queue<String> queue = new ArrayDeque<>();
        Map<String, Boolean> visited = new HashMap<>();
        queue.add("A");
        visited.put("A", true);
        while (!queue.isEmpty()) {
            String node = queue.poll();
            order.add(node);
            for (String next : graph.get(node)) {
                if (visited.putIfAbsent(next, true) == null) {
                    queue.add(next);
                }
            }
        }
        System.out.println(order);
    }
}''',
    output: '[A, B, C, D]',
    pitfalls: <String>['忘记标记 visited 会在环上死循环。', 'BFS 顺序取决于邻居顺序。'],
  ),
  JavaTopic(
    id: 94,
    level: 'advanced',
    title: 'Java 094：不可变对象设计',
    summary: '用 final、防御性拷贝构建不可变类型。',
    concepts: <String>['不可变', 'final', '防御性拷贝'],
    objective: '能设计线程安全的不可变对象。',
    explain:
        '不可变对象创建后状态不变，天然线程安全。要点：字段 final、构造器完成初始化、'
        '可变字段要拷贝、不提供修改器。',
    code: '''import java.util.List;

public class Main {
    static final class Basket {
        private final List<String> items;

        Basket(List<String> items) {
            this.items = List.copyOf(items);
        }

        List<String> items() {
            return items;
        }
    }

    public static void main(String[] args) {
        List<String> source = new java.util.ArrayList<>(List.of("apple"));
        Basket basket = new Basket(source);
        source.add("banana");
        System.out.println("basket=" + basket.items());
        try {
            basket.items().add("x");
        } catch (UnsupportedOperationException e) {
            System.out.println("immutable");
        }
    }
}''',
    output: 'basket=[apple]\nimmutable',
    pitfalls: <String>['直接保存传入集合引用会被外部修改。', '返回内部集合要用不可变视图或拷贝。'],
  ),
  JavaTopic(
    id: 95,
    level: 'advanced',
    title: 'Java 095：密封类型与 instanceof 模式匹配',
    summary: '用 sealed 限定子类集合，用 instanceof 模式匹配免去强制转换。',
    concepts: <String>['sealed', 'instanceof 模式匹配', 'permits', '类型安全'],
    objective: '能用 sealed 层次和 instanceof 模式匹配安全地处理形状，并列举密封类型的已知子类。',
    explain:
        'sealed 接口用 permits 明确列出允许的子类，编译器因此知道类型的完整集合。'
        'Java 17 的 instanceof 模式匹配在判断类型的同时声明变量，省去显式强制转换；'
        '（switch 的记录模式需要更高版本的 Java，本项目按 17 编译，所以用 instanceof 模式。）',
    code: '''public class Main {
    sealed interface Shape permits Circle, Square {}

    static final class Circle implements Shape {
        final double radius;

        Circle(double radius) {
            this.radius = radius;
        }
    }

    static final class Square implements Shape {
        final double side;

        Square(double side) {
            this.side = side;
        }
    }

    static double area(Shape shape) {
        if (shape instanceof Circle circle) {
            return Math.PI * circle.radius * circle.radius;
        }
        if (shape instanceof Square square) {
            return square.side * square.side;
        }
        throw new IllegalStateException("unknown shape");
    }

    static String describe(Shape shape) {
        if (shape instanceof Circle circle) {
            return "圆 r=" + circle.radius;
        }
        return "正方形 side=" + ((Square) shape).side;
    }

    public static void main(String[] args) {
        System.out.println("square=" + area(new Square(3)));
        System.out.println("circle>0=" + (area(new Circle(1)) > 3));
        System.out.println(describe(new Square(2)));
        System.out.println("permitted=" + Shape.class.getPermittedSubclasses().length);
    }
}''',
    output: 'square=9.0\ncircle>0=true\n正方形 side=2.0\npermitted=2',
    pitfalls: <String>[
      '同一个普通（未命名）模块中，sealed 的直接子类必须在同一个包内（不要求同一个文件）。',
      'Java 17 不支持 switch 里的记录模式，用 instanceof 模式匹配。',
      'instanceof 模式匹配后变量只在匹配分支内可见。',
    ],
  ),
  JavaTopic(
    id: 96,
    level: 'advanced',
    title: 'Java 096：手写 JSON 解析',
    summary: '不依赖库解析简单 JSON 对象。',
    concepts: <String>['解析', '状态机', '字符串'],
    objective: '能实现一个能解析简单对象的迷你 JSON 解析器。',
    explain:
        'JSON 解析本质是词法+语法分析。这里用递归下降解析简单对象，'
        '支持字符串、数字与嵌套对象。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    static int index;

    static Object parse(String text) {
        index = 0;
        return parseValue(text);
    }

    static Object parseValue(String text) {
        char c = text.charAt(index);
        if (c == '{') {
            return parseObject(text);
        }
        if (c == '"') {
            return parseString(text);
        }
        return parseInt(text);
    }

    static Map<String, Object> parseObject(String text) {
        Map<String, Object> map = new LinkedHashMap<>();
        index++;
        while (text.charAt(index) != '}') {
            String key = parseString(text);
            index++; // skip ':'
            Object value = parseValue(text);
            map.put(key, value);
            if (text.charAt(index) == ',') {
                index++;
            }
        }
        index++;
        return map;
    }

    static String parseString(String text) {
        index++;
        int start = index;
        while (text.charAt(index) != '"') {
            index++;
        }
        String value = text.substring(start, index);
        index++;
        return value;
    }

    static Integer parseInt(String text) {
        int start = index;
        while (index < text.length() && Character.isDigit(text.charAt(index))) {
            index++;
        }
        return Integer.parseInt(text.substring(start, index));
    }

    public static void main(String[] args) {
        String json = "{\\"name\\":\\"ann\\",\\"age\\":30}";
        Map<?, ?> parsed = (Map<?, ?>) parse(json);
        System.out.println("name=" + parsed.get("name"));
        System.out.println("age=" + parsed.get("age"));
    }
}''',
    output: 'name=ann\nage=30',
    pitfalls: <String>['未处理转义、空白与非法输入，生产应使用成熟库。', '下标变量是静态的，不线程安全。'],
  ),
  JavaTopic(
    id: 97,
    level: 'advanced',
    title: 'Java 097：命令行参数与输入',
    summary: '读取程序参数并在无参数时给出默认值。',
    concepts: <String>['args', '参数校验', '默认值'],
    objective: '能解析命令行参数并健壮处理缺失情况。',
    explain:
        'main 的 args 是命令行参数数组。要根据长度与内容校验，缺失时给出默认或提示，'
        '而不是直接越界。',
    code: '''public class Main {
    static String getName(String[] args) {
        if (args.length == 0 || args[0].isBlank()) {
            return "guest";
        }
        return args[0].trim();
    }

    public static void main(String[] args) {
        System.out.println("Hello, " + getName(args));
        System.out.println("count=" + args.length);
    }
}''',
    output: 'Hello, guest\ncount=0',
    pitfalls: <String>['args 可能为空，必须先判长度。', '参数带空格时要用引号包裹。'],
  ),
  JavaTopic(
    id: 98,
    level: 'advanced',
    title: 'Java 098：分层设计：控制台 MVC',
    summary: '把输入、业务、输出分成三层的小应用。',
    concepts: <String>['分层', 'MVC', '职责分离'],
    objective: '能把程序拆成 model/service/view 三层。',
    explain:
        '分层让每层只关心自己的职责：模型保存数据、服务处理逻辑、视图负责展示，'
        '便于测试与替换。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    record Task(String title, boolean done) {}

    static class TaskService {
        private final List<Task> tasks = new ArrayList<>();

        void add(String title) {
            tasks.add(new Task(title, false));
        }

        void complete(int index) {
            Task current = tasks.get(index);
            tasks.set(index, new Task(current.title(), true));
        }

        List<Task> all() {
            return List.copyOf(tasks);
        }
    }

    static class TaskView {
        void render(List<Task> tasks) {
            for (int i = 0; i < tasks.size(); i++) {
                Task task = tasks.get(i);
                String mark = task.done() ? "[x]" : "[ ]";
                System.out.println((i + 1) + ". " + mark + " " + task.title());
            }
        }
    }

    public static void main(String[] args) {
        TaskService service = new TaskService();
        service.add("写代码");
        service.add("写测试");
        service.complete(0);
        new TaskView().render(service.all());
    }
}''',
    output: '1. [x] 写代码\n2. [ ] 写测试',
    pitfalls: <String>['视图不应包含业务逻辑。', '服务接口要稳定，便于以后换实现。'],
  ),
  JavaTopic(
    id: 99,
    level: 'advanced',
    title: 'Java 099：性能与复杂度基础',
    summary: '用大 O 衡量算法，避免常见性能陷阱。',
    concepts: <String>['复杂度', '大O', '性能'],
    objective: '能判断常见操作的复杂度并选择合适结构。',
    explain:
        '大 O 描述随规模增长的趋势。ArrayList 随机访问 O(1) 但中间插入 O(n)，'
        'HashSet 查找平均 O(1)。选对结构比微优化更重要。',
    code: '''import java.util.HashSet;
import java.util.Set;

public class Main {
    static boolean containsBrute(int[] values, int target) {
        for (int value : values) {
            if (value == target) {
                return true;
            }
        }
        return false;
    }

    public static void main(String[] args) {
        int[] values = new int[1000];
        for (int i = 0; i < values.length; i++) {
            values[i] = i;
        }
        Set<Integer> set = new HashSet<>();
        for (int value : values) {
            set.add(value);
        }
        System.out.println("brute=" + containsBrute(values, 999));
        System.out.println("set=" + set.contains(999));
    }
}''',
    output: 'brute=true\nset=true',
    pitfalls: <String>['在循环里做线性查找会变成 O(n^2)。', '过早优化是万恶之源，先测量再优化。'],
  ),
  JavaTopic(
    id: 100,
    level: 'advanced',
    title: 'Java 100：综合项目：迷你任务清单',
    summary: '综合运用集合、流、异常与分层完成一个小应用。',
    concepts: <String>['综合', 'Stream', '分层', '异常'],
    objective: '能把全书知识整合成一个可运行的任务清单程序。',
    explain:
        '综合练习：用 Map 分组、用 Stream 统计、用自定义异常校验输入、'
        '用分层组织，输出完成率报告。',
    code: '''import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

public class Main {
    record Task(String title, String owner, boolean done) {}

    static class InvalidTask extends RuntimeException {
        InvalidTask(String message) {
            super(message);
        }
    }

    static Task create(String title, String owner) {
        if (title == null || title.isBlank()) {
            throw new InvalidTask("标题不能为空");
        }
        return new Task(title.trim(), owner, false);
    }

    public static void main(String[] args) {
        List<Task> tasks = List.of(
            create("设计", "ann"),
            create("编码", "ann"),
            create("测试", "bob"));
        // TreeMap 分组：输出按 owner 排序，不依赖默认 Map 的迭代顺序。
        Map<String, Long> byOwner = tasks.stream()
            .collect(Collectors.groupingBy(Task::owner, TreeMap::new, Collectors.counting()));
        System.out.println("byOwner=" + byOwner);
        double rate = tasks.stream().filter(Task::done).count() / (double) tasks.size();
        System.out.println("completion=" + rate);
        try {
            create(" ", "cara");
        } catch (InvalidTask e) {
            System.out.println("error=" + e.getMessage());
        }
    }
}''',
    output: 'byOwner={ann=2, bob=1}\ncompletion=0.0\nerror=标题不能为空',
    pitfalls: <String>['默认分组结果的顺序不固定，要稳定输出用 TreeMap 分组。', '输入校验要在创建入口完成。'],
  ),
];
