import 'java_topic.dart';

/// Authored Java topics 221..280 (author C): object contracts, generics,
/// reflection, annotations, records and sealed types, design patterns and
/// algorithms.
///
/// Imported by the aggregate `java_topics.dart`; every entry keeps the same
/// authoring rules as the original 100 topics: complete multi-line `Main.java`,
/// a byte-exact [JavaTopic.output], a Chinese objective, explanation, pitfalls
/// and a concrete exercise. Programs use only the Java 17 API, no networking,
/// no external libraries and no nondeterministic concurrency.
const List<JavaTopic> javaLanguageTopics = <JavaTopic>[
  JavaTopic(
    id: 221,
    level: 'advanced',
    title: 'Java 221：equals 与 hashCode 契约',
    summary: '只重写 equals 会让 HashSet 无法去重，验证两条契约的真实后果。',
    concepts: <String>['equals', 'hashCode', '哈希集合', '对象契约'],
    objective: '能说明 equals 与 hashCode 的相互依赖，并写出成对重写的正确实现。',
    explain:
        '哈希容器先用 hashCode 找桶，再用 equals 比较。只重写 equals 时，'
        '两个「相等」的对象 hashCode 不同，会被放进不同的桶，去重就失效了。'
        '契约要求：equals 为 true 的两个对象 hashCode 必须相同；反过来不要求。',
    code: '''import java.util.HashSet;
import java.util.Objects;
import java.util.Set;

public class Main {
    static final class Broken {
        private final String code;

        Broken(String code) {
            this.code = code;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Broken)) {
                return false;
            }
            return code.equals(((Broken) other).code);
        }
    }

    static final class Fixed {
        private final String code;

        Fixed(String code) {
            this.code = code;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Fixed)) {
                return false;
            }
            return code.equals(((Fixed) other).code);
        }

        @Override
        public int hashCode() {
            return Objects.hash(code);
        }
    }

    public static void main(String[] args) {
        Set<Broken> broken = new HashSet<>();
        broken.add(new Broken("A-1"));
        broken.add(new Broken("A-1"));
        Set<Fixed> fixed = new HashSet<>();
        fixed.add(new Fixed("A-1"));
        fixed.add(new Fixed("A-1"));
        System.out.println("brokenSetSize=" + broken.size());
        System.out.println("fixedSetSize=" + fixed.size());
        System.out.println("brokenEquals=" + new Broken("A-1").equals(new Broken("A-1")));
        System.out.println("fixedEquals=" + new Fixed("A-1").equals(new Fixed("A-1")));
    }
}''',
    output: 'brokenSetSize=2\nfixedSetSize=1\nbrokenEquals=true\nfixedEquals=true',
    pitfalls: <String>[
      '只重写 equals 不重写 hashCode 是最常见的静默 bug：单线程下也复现。',
      'hashCode 里用到的字段集合必须与 equals 完全一致。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 Broken 补上 hashCode，预测并验证 setSize 的变化。',
        hint: '照抄 Fixed 的 hashCode 实现即可。',
        answer: '加上 hashCode 后 brokenSetSize 变成 1，说明两条契约必须成对满足。',
      ),
    ],
  ),
  JavaTopic(
    id: 222,
    level: 'advanced',
    title: 'Java 222：compareTo 与 equals 一致性',
    summary: 'TreeSet 用 compareTo 判重，与 equals 不一致时会出现「丢元素」。',
    concepts: <String>['Comparable', 'TreeSet', '自然顺序', '一致性'],
    objective: '能判断 compareTo 为 0 但 equals 为 false 时集合会发生什么，并给出修正方向。',
    explain:
        '排序集合用 compareTo 的返回值判断是否重复：返回 0 就视为同一个元素。'
        '如果 compareTo 只看优先级而 equals 还比较名称，优先级相同的两个对象'
        '在 TreeSet 里会被丢弃。建议让 compareTo 为 0 等价于 equals 为 true。',
    code: '''import java.util.TreeSet;

public class Main {
    static final class Version implements Comparable<Version> {
        private final String name;
        private final int priority;

        Version(String name, int priority) {
            this.name = name;
            this.priority = priority;
        }

        @Override
        public int compareTo(Version other) {
            return Integer.compare(priority, other.priority);
        }

        @Override
        public String toString() {
            return name + "(" + priority + ")";
        }
    }

    public static void main(String[] args) {
        TreeSet<Version> set = new TreeSet<>();
        set.add(new Version("beta", 1));
        set.add(new Version("stable", 1));
        set.add(new Version("alpha", 0));
        Version stable = new Version("stable", 1);
        Version beta = new Version("beta", 1);
        System.out.println("size=" + set.size());
        System.out.println("first=" + set.first());
        System.out.println("set=" + set);
        System.out.println("equalsSamePriority=" + beta.equals(stable));
        System.out.println("compareZero=" + beta.compareTo(stable));
    }
}''',
    output:
        'size=2\nfirst=alpha(0)\nset=[alpha(0), beta(1)]\nequalsSamePriority=false\ncompareZero=0',
    pitfalls: <String>[
      '先加入 beta 再加入 stable，后者被拒绝，最终只保留在先者。',
      'TreeSet 的判重规则与 HashSet 不同，迁移容器时容易漏掉。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '让 compareTo 在优先级相同时再比较名称，重新运行并解释 size 的变化。',
        hint: '先比较 priority，相等时用 name.compareTo(other.name)。',
        answer: '优先级相同就比较名称，三个对象互相不相等，size 变成 3。',
      ),
    ],
  ),
  JavaTopic(
    id: 223,
    level: 'advanced',
    title: 'Java 223：防御性复制',
    summary: '构造器直接保存外部集合引用，会让「不可变对象」被悄悄篡改。',
    concepts: <String>['防御性复制', 'List.copyOf', '不可变对象', '可见性'],
    objective: '能用防御性复制切断外部引用，并说明为什么每次修改都要创建新实例。',
    explain:
        '把传入的集合引用直接赋给字段，外部仍持有同一对象，之后修改会穿透进来。'
        '正确做法是在构造器里复制（List.copyOf 同时得到只读快照），修改时'
        '复制出新对象返回，而不是原地修改字段。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static final class Ledger {
        private final List<String> entries;

        Ledger(List<String> entries) {
            this.entries = List.copyOf(entries);
        }

        List<String> view() {
            return entries;
        }

        Ledger withEntry(String entry) {
            List<String> next = new ArrayList<>(entries);
            next.add(entry);
            return new Ledger(next);
        }

        @Override
        public String toString() {
            return entries.toString();
        }
    }

    public static void main(String[] args) {
        List<String> source = new ArrayList<>();
        source.add("open");
        Ledger ledger = new Ledger(source);
        source.add("close");
        Ledger extended = ledger.withEntry("audit");
        System.out.println("afterSourceMutated=" + ledger);
        System.out.println("extended=" + extended);
        System.out.println("original=" + ledger);
        try {
            ledger.view().add("mutate");
        } catch (UnsupportedOperationException error) {
            System.out.println("viewIsReadOnly=true");
        }
    }
}''',
    output:
        'afterSourceMutated=[open]\nextended=[open, audit]\noriginal=[open]\nviewIsReadOnly=true',
    pitfalls: <String>[
      '只复制一层：元素本身可变时还需要逐元素复制。',
      'setter 里也要复制，否则外部对象仍可反向修改内部状态。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把构造器改成 this.entries = entries，观察输出变化。',
        hint: '只改一行再重新运行。',
        answer: 'afterSourceMutated 会变成 [open, close]，说明防御性复制被破坏。',
      ),
    ],
  ),
  JavaTopic(
    id: 224,
    level: 'advanced',
    title: 'Java 224：不可变对象设计',
    summary: 'final 类、final 字段、只读视图三件套，把可变性关在对象内部。',
    concepts: <String>['不可变对象', 'final', 'Collections.unmodifiableMap', '快照'],
    objective: '能设计一个对外完全不可变的配置对象，并解释每一条约束的作用。',
    explain:
        '不可变对象在构造完成后状态不再变化：字段用 final 保证只赋值一次，'
        '传入集合先复制再包成只读视图，不提供修改方法。这样对象天然线程安全，'
        '也可以安全地作为 Map 的键和缓存值。',
    code: '''import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    static final class Settings {
        private final String name;
        private final Map<String, String> values;

        Settings(String name, Map<String, String> source) {
            this.name = name;
            this.values = Collections.unmodifiableMap(new LinkedHashMap<>(source));
        }

        String get(String key) {
            return values.getOrDefault(key, "<unset>");
        }

        Map<String, String> asMap() {
            return values;
        }

        @Override
        public String toString() {
            return name + values;
        }
    }

    public static void main(String[] args) {
        Map<String, String> raw = new LinkedHashMap<>();
        raw.put("theme", "dark");
        Settings settings = new Settings("studio", raw);
        raw.put("theme", "light");
        System.out.println("isolated=" + settings);
        System.out.println("theme=" + settings.get("theme"));
        System.out.println("missing=" + settings.get("font"));
        try {
            settings.asMap().put("theme", "blue");
        } catch (UnsupportedOperationException error) {
            System.out.println("mapIsReadOnly=true");
        }
    }
}''',
    output:
        'isolated=studio{theme=dark}\ntheme=dark\nmissing=<unset>\nmapIsReadOnly=true',
    pitfalls: <String>[
      'Collections.unmodifiableMap 只是视图，底层 Map 仍可被外部改动，必须先复制。',
      'final 只约束引用本身，字段指向的对象依然可能可变。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '去掉 LinkedHashMap 复制，只保留 unmodifiableMap，观察第一个输出。',
        hint: '把 new LinkedHashMap<>(source) 换成 source。',
        answer: 'isolated 会打印 studio{theme=light}，证明只读视图挡不住底层修改。',
      ),
    ],
  ),
  JavaTopic(
    id: 225,
    level: 'advanced',
    title: 'Java 225：== 与 equals 的边界',
    summary: '字符串字面量、运行时拼接、intern 与整数缓存池的比较差异。',
    concepts: <String>['引用比较', '内容比较', '字符串池', '自动装箱缓存'],
    objective: '能区分 == 与 equals 的语义，并解释字符串池和整数缓存带来的「偶然相等」。',
    explain:
        '== 比较引用是否指向同一对象，equals 比较内容。字面量常量在编译期就'
        '进入字符串池，运行时拼接会产生新对象；intern() 把内容放回池中。'
        'Integer 缓存 -128..127，超出范围每次装箱都是新对象。',
    code: '''public class Main {
    static String build() {
        String prefix = "ja";
        return prefix + "va";
    }

    public static void main(String[] args) {
        String literal = "java";
        String built = build();
        String interned = built.intern();
        Integer small = 100;
        Integer alsoSmall = 100;
        Integer big = 1000;
        Integer alsoBig = 1000;
        System.out.println("literalRefEq=" + (literal == "java"));
        System.out.println("builtContentEq=" + literal.equals(built));
        System.out.println("builtRefEq=" + (literal == built));
        System.out.println("internedRefEq=" + (literal == interned));
        System.out.println("smallCacheEq=" + (small == alsoSmall));
        System.out.println("bigCacheEq=" + (big == alsoBig));
    }
}''',
    output:
        'literalRefEq=true\nbuiltContentEq=true\nbuiltRefEq=false\ninternedRefEq=true\nsmallCacheEq=true\nbigCacheEq=false',
    pitfalls: <String>[
      '把常量拼接写成纯字面量表达式时会被编译器折叠，比较结果与运行时拼接不同。',
      '包装类一律用 equals 或先拆箱比较，不要依赖缓存范围。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 build() 改成 return "ja" + "va";，解释 builtRefEq 为什么变了。',
        hint: '拆分常量表达式看编译器如何折叠。',
        answer: '常量表达式在编译期折叠成同一个池内字面量，builtRefEq 变成 true。',
      ),
    ],
  ),
  JavaTopic(
    id: 226,
    level: 'advanced',
    title: 'Java 226：哈希冲突的代价',
    summary: '故意写出碰撞的 hashCode，观察哈希表依然能正确工作，只是更慢。',
    concepts: <String>['哈希冲突', 'Objects.hash', '哈希桶', 'equals 兜底'],
    objective: '能解释 hashCode 碰撞为什么不会破坏正确性，以及它影响的是什么。',
    explain:
        'hashCode 只决定落在哪个桶，桶内还会逐个用 equals 比较。碰撞时同一'
        '桶里挂多个元素，正确性不变，但查找从常数级退化。好的 hashCode 应当'
        '尽量均匀地分散对象。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

public class Main {
    static final class Slot {
        private final String code;

        Slot(String code) {
            this.code = code;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Slot)) {
                return false;
            }
            return code.equals(((Slot) other).code);
        }

        @Override
        public int hashCode() {
            return Objects.hash(code.length());
        }

        @Override
        public String toString() {
            return code;
        }
    }

    public static void main(String[] args) {
        Map<Slot, String> map = new LinkedHashMap<>();
        map.put(new Slot("aa"), "first");
        map.put(new Slot("bb"), "second");
        map.put(new Slot("cc"), "third");
        System.out.println("hashAa=" + new Slot("aa").hashCode());
        System.out.println("hashBb=" + new Slot("bb").hashCode());
        System.out.println("collisions=" + (new Slot("aa").hashCode() == new Slot("bb").hashCode()));
        System.out.println("size=" + map.size());
        System.out.println("lookup=" + map.get(new Slot("bb")));
        System.out.println("distinct=" + map.keySet());
    }
}''',
    output:
        'hashAa=33\nhashBb=33\ncollisions=true\nsize=3\nlookup=second\ndistinct=[aa, bb, cc]',
    pitfalls: <String>[
      '只对长度求哈希时，同长度字符串全部碰撞，真实数据下性能会明显变差。',
      '碰撞不会让键「合并」，前提是 equals 仍然只比较内容。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 hashCode 改成只看首字符，重新运行看 collisions 是否变化。',
        hint: '返回 code.charAt(0) 即可。',
        answer: 'aa、bb、cc 首字符不同，collisions 变成 false，说明分布被改善了。',
      ),
    ],
  ),
  JavaTopic(
    id: 227,
    level: 'advanced',
    title: 'Java 227：Comparator 链式比较',
    summary: '用 comparing/thenComparing/reversed 组合多字段排序规则。',
    concepts: <String>['Comparator', '链式比较', '稳定排序', '多字段排序'],
    objective: '能组合出「分数降序、等级升序、名称升序」的多字段比较器。',
    explain:
        'Comparator.comparingInt 把取值函数变成比较器，thenComparing 在相等时'
        '继续比较下一字段，reversed 只反转它前面的那一段。排序是稳定的：'
        '比较器认为相等的元素保持原有相对顺序。',
    code: '''import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class Main {
    static final class Player {
        private final String name;
        private final int score;
        private final int level;

        Player(String name, int score, int level) {
            this.name = name;
            this.score = score;
            this.level = level;
        }

        @Override
        public String toString() {
            return name + ":" + score + "/" + level;
        }
    }

    public static void main(String[] args) {
        List<Player> players = new ArrayList<>();
        players.add(new Player("ann", 90, 2));
        players.add(new Player("bob", 90, 1));
        players.add(new Player("cid", 95, 3));
        players.add(new Player("dee", 80, 2));
        Comparator<Player> order = Comparator.comparingInt((Player p) -> p.score)
                .reversed()
                .thenComparing(p -> p.level)
                .thenComparing(p -> p.name);
        players.sort(order);
        System.out.println("order=" + players);
        Comparator<Player> byLevel = Comparator.comparingInt((Player p) -> p.level)
                .thenComparing(Comparator.comparing((Player p) -> p.name).reversed());
        players.sort(byLevel);
        System.out.println("byLevel=" + players);
    }
}''',
    output:
        'order=[cid:95/3, bob:90/1, ann:90/2, dee:80/2]\nbyLevel=[bob:90/1, dee:80/2, ann:90/2, cid:95/3]',
    pitfalls: <String>[
      'reversed() 作用于链上已经组装好的部分，写在中途会得到意料之外的顺序。',
      '对基本类型用 comparingInt，避免装箱和 null 拆箱异常。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把第二段排序改成先按等级降序，再按分数升序。',
        hint: '把 comparingInt 的结果先 reversed，再接 thenComparing。',
        answer: 'Comparator.comparingInt((Player p) -> p.level).reversed() 再 thenComparing(p -> p.score) 即可。',
      ),
    ],
  ),
  JavaTopic(
    id: 228,
    level: 'advanced',
    title: 'Java 228：继承下的 equals 对称性',
    summary: '父类用 instanceof、子类加字段，equals 立刻失去对称性。',
    concepts: <String>['equals 对称性', '继承', 'getClass', 'instanceof'],
    objective: '能构造并识别 equals 不对称的继承结构，并说出两种修复方式。',
    explain:
        '父类 equals 用 instanceof 时，子类实例也能通过检查；子类 equals'
        '却要求对方是自己的类型。于是 a.equals(b) 为 true 而 b.equals(a) 为'
        'false，违反对称性。修复方式：用 getClass 严格比较同一类型，或者'
        '不在子类里新增参与 equals 的状态（改用组合）。',
    code: '''public class Main {
    static class Point {
        private final int x;

        Point(int x) {
            this.x = x;
        }

        @Override
        public boolean equals(Object other) {
            return other instanceof Point && ((Point) other).x == x;
        }

        @Override
        public int hashCode() {
            return Integer.hashCode(x);
        }
    }

    static final class NamedPoint extends Point {
        private final String name;

        NamedPoint(int x, String name) {
            super(x);
            this.name = name;
        }

        @Override
        public boolean equals(Object other) {
            return other instanceof NamedPoint
                    && ((NamedPoint) other).name.equals(name)
                    && super.equals(other);
        }
    }

    public static void main(String[] args) {
        Point plain = new Point(1);
        NamedPoint named = new NamedPoint(1, "origin");
        System.out.println("plainToNamed=" + plain.equals(named));
        System.out.println("namedToPlain=" + named.equals(plain));
        System.out.println("symmetric=" + (plain.equals(named) == named.equals(plain)));
        System.out.println("hashSame=" + (plain.hashCode() == named.hashCode()));
    }
}''',
    output: 'plainToNamed=true\nnamedToPlain=false\nsymmetric=false\nhashSame=true',
    pitfalls: <String>[
      '把父类 equals 改成 getClass 能恢复对称，但子类与父类再也不会相等。',
      '子类重写 equals 必须同时重写 hashCode，否则哈希容器同样出错。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 Point.equals 改用 getClass() 比较，预测并验证四个输出。',
        hint: 'other != null && getClass() == other.getClass()。',
        answer: '两个方向都变成 false，symmetric 变成 true，hashSame 仍为 true。',
      ),
    ],
  ),
  JavaTopic(
    id: 229,
    level: 'advanced',
    title: 'Java 229：有界类型参数',
    summary: '用 T extends Number 让泛型类安全调用 doubleValue。',
    concepts: <String>['泛型类', '有界类型参数', 'Number', '类型安全'],
    objective: '能声明带边界的泛型类，并解释为什么无边界时编译不通过。',
    explain:
        '泛型参数默认是 Object，只能调用 Object 的方法。写 T extends Number'
        '后，编译器知道 T 一定有 doubleValue，因此可以在泛型代码里做数值运算，'
        '同时调用方仍然只能传入 Number 的子类。',
    code: '''import java.util.List;

public class Main {
    static final class Basket<T extends Number> {
        private final List<T> items;

        Basket(List<T> items) {
            this.items = List.copyOf(items);
        }

        double total() {
            double sum = 0;
            for (T item : items) {
                sum += item.doubleValue();
            }
            return sum;
        }

        int count() {
            return items.size();
        }
    }

    public static void main(String[] args) {
        Basket<Integer> ints = new Basket<>(List.of(1, 2, 3));
        Basket<Double> doubles = new Basket<>(List.of(1.5, 2.25));
        System.out.println("intTotal=" + ints.total());
        System.out.println("doubleTotal=" + doubles.total());
        System.out.println("counts=" + ints.count() + ":" + doubles.count());
        System.out.println("rounded=" + Math.round(ints.total() * doubles.total()));
    }
}''',
    output: 'intTotal=6.0\ndoubleTotal=3.75\ncounts=3:2\nrounded=23',
    pitfalls: <String>[
      '边界只能有一个类，其余必须是接口，且类要写在最前面。',
      'doubleValue 会丢失大整数精度，金融计算仍应使用 BigDecimal。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 Basket<Long> 并计算两个极大值的和，观察输出格式。',
        hint: 'List.of(9000000000L, 1L) 已经超出 int 范围。',
        answer: 'total 返回 double，输出为 9.000000001E9，说明 double 不适合精确金额。',
      ),
    ],
  ),
  JavaTopic(
    id: 230,
    level: 'advanced',
    title: 'Java 230：PECS 通配符',
    summary: '生产者用 extends、消费者用 super，写出可复用的复制与求和方法。',
    concepts: <String>['通配符', 'PECS', '协变', '泛型方法'],
    objective: '能根据参数是读取还是写入选择 extends 或 super，并解释原因。',
    explain:
        'PECS 是 Producer Extends, Consumer Super：只读取数据的参数用'
        'List<? extends T>，只写入数据的参数用 List<? super T>。这样既能接受'
        '更多实参类型，又不会破坏类型安全。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static <T> void copy(List<? super T> sink, List<? extends T> source) {
        for (T value : source) {
            sink.add(value);
        }
    }

    static double sum(List<? extends Number> numbers) {
        double total = 0;
        for (Number number : numbers) {
            total += number.doubleValue();
        }
        return total;
    }

    public static void main(String[] args) {
        List<Integer> source = List.of(1, 2, 3);
        List<Object> objects = new ArrayList<>();
        List<Number> numbers = new ArrayList<>();
        copy(objects, source);
        copy(numbers, source);
        System.out.println("objects=" + objects);
        System.out.println("numbers=" + numbers);
        System.out.println("sumInts=" + sum(source));
        System.out.println("sumDoubles=" + sum(List.of(0.5, 1.5)));
    }
}''',
    output:
        'objects=[1, 2, 3]\nnumbers=[1, 2, 3]\nsumInts=6.0\nsumDoubles=2.0',
    pitfalls: <String>[
      '写成 List<T> 会让 List<Integer> 无法传给 List<Number>，泛型不支持协变。',
      '通配符只约束「能读还是能写」，不要在 extends 的列表上 add。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 copy 增加一个返回值，返回实际复制的元素个数。',
        hint: '在循环里计数，方法返回 int。',
        answer: '声明 int copied 并在循环中自增，最后 return copied，两次调用都返回 3。',
      ),
    ],
  ),
  JavaTopic(
    id: 231,
    level: 'advanced',
    title: 'Java 231：泛型方法的类型推断',
    summary: '编译器从实参推断 T，必要时用类型见证显式指定。',
    concepts: <String>['泛型方法', '类型推断', '类型见证', '目标类型'],
    objective: '能读懂推断结果，并在推断不理想时用 Main.<T>method 显式指定。',
    explain:
        '泛型方法的类型参数由实参和目标类型共同推断。两个不同类型实参时，'
        '推断会向上找公共父类型（Integer 与 Double 推出 Number），'
        '这往往就是需要写类型见证的时刻。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static <T> List<T> repeat(T value, int times) {
        List<T> result = new ArrayList<>();
        for (int i = 0; i < times; i++) {
            result.add(value);
        }
        return result;
    }

    static <T extends Comparable<T>> T max(List<T> values) {
        T best = values.get(0);
        for (T value : values) {
            if (value.compareTo(best) > 0) {
                best = value;
            }
        }
        return best;
    }

    static <T> T pick(T first, T second) {
        return first != null ? first : second;
    }

    public static void main(String[] args) {
        System.out.println("repeat=" + repeat("ha", 3));
        System.out.println("maxString=" + max(List.of("pear", "apple", "zebra")));
        System.out.println("maxInt=" + max(List.of(4, 9, 2)));
        System.out.println("inferred=" + pick(7, 9));
        System.out.println("witness=" + Main.<Number>pick(7, 9.5));
    }
}''',
    output:
        'repeat=[ha, ha, ha]\nmaxString=zebra\nmaxInt=9\ninferred=7\nwitness=7',
    pitfalls: <String>[
      '推断结果不是运行时类型，擦除后方法体里看不到 T 的实际类型。',
      '类型见证写在方法名前：Main.<Number>pick(...)，不是 new。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 witness 那一行改成 pick(7, 9.5) 并观察输出类型推断的变化。',
        hint: '去掉 Main.<Number> 后重新编译运行。',
        answer: '推断为 Number 后返回 7，但输出仍是 7；换成 pick(9.5, 7) 才会看到 9.5。',
      ),
    ],
  ),
  JavaTopic(
    id: 232,
    level: 'advanced',
    title: 'Java 232：递归泛型边界',
    summary: 'T extends Comparable<T> 是 JDK 里最常见的自引用边界写法。',
    concepts: <String>['递归边界', 'Comparable', '自类型', '泛型约束'],
    objective: '能解释 T extends Comparable<T> 的含义，并让自定义类型满足它。',
    explain:
        'Comparable<T> 本身带类型参数，写成 T extends Comparable<T> 表示'
        '「T 能和自己比较」。这种自引用边界让泛型代码可以安全调用'
        'value.compareTo(best)，而不需要额外强转。',
    code: '''import java.util.List;

public class Main {
    static <T extends Comparable<T>> T maxOf(List<T> values) {
        T best = values.get(0);
        for (T value : values) {
            if (value.compareTo(best) > 0) {
                best = value;
            }
        }
        return best;
    }

    static final class Weight implements Comparable<Weight> {
        private final int grams;

        Weight(int grams) {
            this.grams = grams;
        }

        @Override
        public int compareTo(Weight other) {
            return Integer.compare(grams, other.grams);
        }

        @Override
        public String toString() {
            return grams + "g";
        }
    }

    public static void main(String[] args) {
        System.out.println("maxInt=" + maxOf(List.of(3, 8, 1)));
        System.out.println("maxWeight=" + maxOf(List.of(new Weight(120), new Weight(400))));
        System.out.println("comparable=" + (new Weight(5) instanceof Comparable));
    }
}''',
    output: 'maxInt=8\nmaxWeight=400g\ncomparable=true',
    pitfalls: <String>[
      '写成 T extends Comparable 是原始类型，会丢失类型检查。',
      'compareTo 与 equals 不一致时，排序集合的去重行为会出乎意料。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增一个按字符串长度比较的 Weight 子类，观察 maxOf 的结果。',
        hint: 'Weight 是 final，需要去掉 final 或另写一个实现 Comparable 的类。',
        answer: '另写 LengthName implements Comparable<LengthName> 后，maxOf 按长度选出最长者。',
      ),
    ],
  ),
  JavaTopic(
    id: 233,
    level: 'advanced',
    title: 'Java 233：类型擦除与桥方法',
    summary: '运行时看不到泛型实参，编译器用桥方法维持多态调用。',
    concepts: <String>['类型擦除', '桥方法', '反射', 'Comparator'],
    objective: '能用反射验证泛型被擦除，并解释 isBridge 方法的来源。',
    explain:
        '泛型只存在于编译期，编译后类型参数被擦除为上界（默认 Object）。'
        '因此 List<String> 与 List<Integer> 的运行时类相同。子类实现'
        'Comparator<String> 时，编译器会生成一个 compare(Object, Object) '
        '桥方法，转发到真正的 compare(String, String)。',
    code: '''import java.lang.reflect.Method;
import java.util.Comparator;

public class Main {
    static final class ByLength implements Comparator<String> {
        @Override
        public int compare(String left, String right) {
            return Integer.compare(left.length(), right.length());
        }
    }

    static final class Box<T> {
        private final T value;

        Box(T value) {
            this.value = value;
        }

        T get() {
            return value;
        }
    }

    public static void main(String[] args) {
        Box<String> text = new Box<>("java");
        Box<Integer> number = new Box<>(17);
        System.out.println("sameClass=" + (text.getClass() == number.getClass()));
        System.out.println("className=" + text.getClass().getSimpleName());
        long bridges = 0;
        for (Method method : ByLength.class.getDeclaredMethods()) {
            if (method.isBridge()) {
                bridges++;
            }
        }
        System.out.println("bridgeMethods=" + bridges);
        System.out.println("compare=" + new ByLength().compare("aaa", "b"));
    }
}''',
    output:
        'sameClass=true\nclassName=Box\nbridgeMethods=1\ncompare=1',
    pitfalls: <String>[
      '运行时不能写 new T() 或 T.class，擦除后没有具体类型信息。',
      '桥方法由编译器生成，手写同名方法会编译失败。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '打印 ByLength 所有声明方法的名称与参数类型。',
        hint: '遍历 getDeclaredMethods，输出 method.getName() 与 getParameterCount()。',
        answer: '会看到 compare 有两个版本：2 参的 String 版和 2 参的 Object 桥方法。',
      ),
    ],
  ),
  JavaTopic(
    id: 234,
    level: 'advanced',
    title: 'Java 234：堆污染与 @SafeVarargs',
    summary: '泛型可变参数会擦除成数组，越界写入只能在取出时才暴露。',
    concepts: <String>['堆污染', '可变参数', 'SafeVarargs', 'ClassCastException'],
    objective: '能解释堆污染为什么编译期不报错，并判断何时可以安全使用 @SafeVarargs。',
    explain:
        '可变参数在底层是数组，而泛型数组不被允许，编译器只能擦除成'
        'Object[]。用原始类型引用往 List<String> 里塞 Integer，编译期不报错，'
        '直到按 String 取出时才抛 ClassCastException。@SafeVarargs 只能标在'
        '不向数组写入的 final/static 方法上。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    @SafeVarargs
    static <T> List<T> listOf(T... values) {
        List<T> result = new ArrayList<>();
        for (T value : values) {
            result.add(value);
        }
        return result;
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    static void pollute(List<String> strings) {
        List raw = strings;
        raw.add(Integer.valueOf(42));
    }

    public static void main(String[] args) {
        List<String> words = listOf("a", "b", "c");
        System.out.println("safe=" + words);
        System.out.println("size=" + words.size());
        List<String> polluted = new ArrayList<>();
        pollute(polluted);
        System.out.println("rawSize=" + polluted.size());
        try {
            String first = polluted.get(0);
            System.out.println("first=" + first);
        } catch (ClassCastException error) {
            System.out.println("caught=" + error.getClass().getSimpleName());
        }
    }
}''',
    output:
        'safe=[a, b, c]\nsize=3\nrawSize=1\ncaught=ClassCastException',
    pitfalls: <String>[
      '堆污染不会在写入时报错，异常位置离真正的 bug 很远。',
      '不要为了消除警告随意加 @SafeVarargs，它会关掉编译器的真实检查。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 pollute 改成接收 List<Integer> 再写入字符串，观察异常信息。',
        hint: '交换泛型实参，保留原始类型写入。',
        answer: '取出时把 String 强转为 Integer，同样抛 ClassCastException，提示类型不匹配。',
      ),
    ],
  ),
  JavaTopic(
    id: 235,
    level: 'advanced',
    title: 'Java 235：泛型数组的替代方案',
    summary: '不能 new T[]，改用 Array.newInstance 或集合承载。',
    concepts: <String>['泛型数组', 'Array.newInstance', 'Class 令牌', '擦除'],
    objective: '能用 Class<T> 令牌创建类型正确的数组，并解释为什么直接 new T[] 不行。',
    explain:
        '擦除后 T 不再是具体类型，JVM 无法知道要分配什么数组，所以'
        'new T[] 不合法。把 Class<T> 传进来，用 Array.newInstance 在运行时'
        '创建正确类型，强转后调用方拿到的是 String[] 而不是 Object[]。',
    code: '''import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.List;

public class Main {
    @SuppressWarnings("unchecked")
    static <T> T[] newArray(Class<T> type, int length) {
        return (T[]) Array.newInstance(type, length);
    }

    static <T> List<T> newList() {
        return new ArrayList<>();
    }

    public static void main(String[] args) {
        String[] names = newArray(String.class, 3);
        names[0] = "ada";
        names[1] = "lin";
        names[2] = "zoe";
        System.out.println("arrayType=" + names.getClass().getSimpleName());
        System.out.println("arrayLength=" + names.length);
        System.out.println("arrayValues=" + String.join(",", names));
        int[] numbers = (int[]) Array.newInstance(int.class, 2);
        numbers[0] = 7;
        numbers[1] = 8;
        System.out.println("primitiveSum=" + (numbers[0] + numbers[1]));
        Object[] boxed = newArray(Object.class, 2);
        System.out.println("objectArrayType=" + boxed.getClass().getSimpleName());
        List<String> list = newList();
        list.add("noGenericArray");
        System.out.println("listBacked=" + list.get(0));
    }
}''',
    output:
        'arrayType=String[]\narrayLength=3\narrayValues=ada,lin,zoe\nprimitiveSum=15\nobjectArrayType=Object[]\nlistBacked=noGenericArray',
    pitfalls: <String>[
      'Array.newInstance 返回 Object，强转成 T[] 仍会产生未检查警告。',
      '集合通常比泛型数组更安全，只有在对接旧 API 时才需要这招。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 newArray 加一个越界测试，解释抛出的异常类型。',
        hint: '用 length 为 0 创建后访问下标 0。',
        answer: '抛 ArrayIndexOutOfBoundsException，数组长度在创建时就固定了。',
      ),
    ],
  ),
  JavaTopic(
    id: 236,
    level: 'advanced',
    title: 'Java 236：自类型泛型构建器',
    summary: '用 T extends Builder<T> 让链式方法返回子类类型而不是父类。',
    concepts: <String>['自类型', '泛型构建器', '链式调用', '模板方法'],
    objective: '能写出链式调用不丢失子类方法的泛型构建器基类。',
    explain:
        '父类方法返回 this 时，静态类型是父类，链式调用就拿不到子类方法。'
        '把子类类型作为泛型参数传回父类（T extends QueryBuilder<T>），'
        '父类通过抽象 self() 返回 T，链式调用就能继续使用子类 API。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    static abstract class QueryBuilder<T extends QueryBuilder<T>> {
        private final Map<String, String> parameters = new LinkedHashMap<>();

        protected abstract T self();

        T param(String key, String value) {
            parameters.put(key, value);
            return self();
        }

        Map<String, String> parameters() {
            return parameters;
        }
    }

    static final class UserQuery extends QueryBuilder<UserQuery> {
        private String table = "users";

        @Override
        protected UserQuery self() {
            return this;
        }

        UserQuery from(String table) {
            this.table = table;
            return this;
        }

        String describe() {
            return table + parameters();
        }
    }

    public static void main(String[] args) {
        UserQuery query = new UserQuery()
                .from("members")
                .param("page", "2")
                .param("size", "20");
        System.out.println("query=" + query.describe());
        System.out.println("paramCount=" + query.parameters().size());
    }
}''',
    output: 'query=members{page=2, size=20}\nparamCount=2',
    pitfalls: <String>[
      '子类必须把自身写成泛型实参，否则链式调用会在父类处断掉。',
      '自类型会提高可读性门槛，简单场景直接用具体类更清楚。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 orderBy(String) 方法并接在 from 与 param 之间。',
        hint: '在 UserQuery 里加一个返回 this 的方法。',
        answer: '加上 orderBy 后链式调用仍返回 UserQuery，describe 可把排序字段拼进输出。',
      ),
    ],
  ),
  JavaTopic(
    id: 237,
    level: 'advanced',
    title: 'Java 237：Class 元数据枚举',
    summary: '反射读取类的字段、方法与构造器，并排序输出。',
    concepts: <String>['反射', 'Class', 'Field', 'Method'],
    objective: '能用 getDeclaredFields/Methods/Constructors 描述一个类，并说明为什么输出要排序。',
    explain:
        'Class 对象描述类型本身：字段、方法、构造器、修饰符都能读取。'
        '反射返回的顺序由 JVM 决定，不属于语言契约，所以打印前要排序，'
        '否则同一程序在不同实现上输出不同。',
    code: '''import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class Main {
    static class Order {
        static final String LABEL = "order";
        private final String code;
        private int amount;

        Order(String code, int amount) {
            this.code = code;
            this.amount = amount;
        }

        public String describe() {
            return code + ":" + amount;
        }

        int amount() {
            return amount;
        }
    }

    public static void main(String[] args) throws Exception {
        Class<?> type = Order.class;
        System.out.println("name=" + type.getSimpleName());
        List<String> fields = new ArrayList<>();
        for (Field field : type.getDeclaredFields()) {
            fields.add(field.getType().getSimpleName() + " " + field.getName());
        }
        Collections.sort(fields);
        System.out.println("fields=" + fields);
        List<String> methods = new ArrayList<>();
        for (Method method : type.getDeclaredMethods()) {
            methods.add(method.getName() + "/" + method.getParameterCount());
        }
        Collections.sort(methods);
        System.out.println("methods=" + methods);
        for (Constructor<?> constructor : type.getDeclaredConstructors()) {
            System.out.println("ctorParams=" + constructor.getParameterCount());
        }
    }
}''',
    output:
        'name=Order\nfields=[String LABEL, String code, int amount]\nmethods=[amount/0, describe/0]\nctorParams=2',
    pitfalls: <String>[
      'getDeclaredMethods 不包含继承来的方法，getMethods 才包含 public 继承方法。',
      '直接打印反射数组的顺序在不同 JVM 版本上可能不同，必须排序。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 Order 加一个 public static 常量并重新运行，看 fields 列表如何变化。',
        hint: '常量也会出现在 getDeclaredFields 的结果里。',
        answer: 'fields 会多出一项 String 类型的常量，并因为排序而落在字母顺序处。',
      ),
    ],
  ),
  JavaTopic(
    id: 238,
    level: 'advanced',
    title: 'Java 238：反射创建实例与调用私有方法',
    summary: '用 setAccessible 越过访问控制，说明它的能力与代价。',
    concepts: <String>['反射', 'setAccessible', '私有构造器', 'invoke'],
    objective: '能通过反射实例化私有构造器的类并调用私有方法，说明这是绕过封装。',
    explain:
        'getDeclaredConstructor 能找到私有构造器，setAccessible(true) 关闭'
        '访问检查，newInstance 创建对象；私有方法同理通过 invoke 调用。'
        '这种能力适合框架与测试，但在普通业务代码里会破坏封装，并可能被'
        '模块系统拒绝。',
    code: '''import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

public class Main {
    static class Vault {
        private final String secret;

        private Vault(String secret) {
            this.secret = secret;
        }

        private String reveal(int times) {
            StringBuilder builder = new StringBuilder();
            for (int i = 0; i < times; i++) {
                builder.append(secret);
            }
            return builder.toString();
        }

        public String name() {
            return "vault";
        }
    }

    public static void main(String[] args) throws Exception {
        Constructor<Vault> constructor = Vault.class.getDeclaredConstructor(String.class);
        constructor.setAccessible(true);
        Vault vault = constructor.newInstance("k3");
        Method reveal = Vault.class.getDeclaredMethod("reveal", int.class);
        reveal.setAccessible(true);
        Object result = reveal.invoke(vault, 3);
        Method name = Vault.class.getMethod("name");
        System.out.println("instance=" + vault.name());
        System.out.println("secretValue=" + result);
        System.out.println("resultType=" + result.getClass().getSimpleName());
        System.out.println("publicInvoke=" + name.invoke(vault));
    }
}''',
    output:
        'instance=vault\nsecretValue=k3k3k3\nresultType=String\npublicInvoke=vault',
    pitfalls: <String>[
      'getDeclaredMethod 必须精确匹配参数类型，int 与 Integer 是不同签名。',
      'JDK 17 下未导出包或强封装模块会对 setAccessible 抛 InaccessibleObjectException。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 invoke 的第二个参数改成 0，观察输出变化。',
        hint: '次数为 0 时循环不执行。',
        answer: 'secretValue 变成空字符串，resultType 仍然是 String。',
      ),
    ],
  ),
  JavaTopic(
    id: 239,
    level: 'advanced',
    title: 'Java 239：反射读写字段与修饰符',
    summary: '读取 private final 字段、修改实例字段与 static 字段。',
    concepts: <String>['Field', 'Modifier', 'setInt', '静态字段'],
    objective: '能用 Field 读取修饰符与字段值，并区分实例字段和静态字段的访问方式。',
    explain:
        'Field.get/set 接收目标对象；静态字段的目标对象传 null。基本类型用'
        'setInt/setBoolean 等避免装箱。Modifier.toString 把修饰符位翻译成'
        '关键字，可以用来在框架里判断字段是否是 final 或 static。',
    code: '''import java.lang.reflect.Field;
import java.lang.reflect.Modifier;

public class Main {
    static class Counter {
        public static int created = 0;
        private int value;
        private final int step = 2;

        Counter() {
            created++;
        }

        int value() {
            return value;
        }
    }

    public static void main(String[] args) throws Exception {
        Counter counter = new Counter();
        Class<?> type = Counter.class;
        Field step = type.getDeclaredField("step");
        step.setAccessible(true);
        System.out.println("step=" + step.get(counter));
        System.out.println("stepModifiers=" + Modifier.toString(step.getModifiers()));
        Field value = type.getDeclaredField("value");
        value.setAccessible(true);
        value.setInt(counter, 40);
        System.out.println("value=" + counter.value());
        Field created = type.getDeclaredField("created");
        System.out.println("staticBefore=" + created.get(null));
        created.setInt(null, 7);
        System.out.println("staticAfter=" + Counter.created);
    }
}''',
    output:
        'step=2\nstepModifiers=private final\nvalue=40\nstaticBefore=1\nstaticAfter=7',
    pitfalls: <String>[
      '普通反射能读到 final 的值，但修改编译期常量不保证生效。',
      'getModifiers 返回位掩码，直接相加判断会出错，要用 Modifier.isFinal。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 Modifier.isStatic 判断 created 字段并输出 true。',
        hint: 'Modifier.isStatic(created.getModifiers())。',
        answer: '输出 createdIsStatic=true，证明修饰符位可以程序化判断。',
      ),
    ],
  ),
  JavaTopic(
    id: 240,
    level: 'advanced',
    title: 'Java 240：动态代理',
    summary: '用 InvocationHandler 在运行时为接口生成实现，统一拦截调用。',
    concepts: <String>['动态代理', 'InvocationHandler', 'Proxy', 'AOP'],
    objective: '能为接口创建代理对象，在调用前后插入统一逻辑并收集调用日志。',
    explain:
        'Proxy.newProxyInstance 根据接口在运行时生成实现类，每个方法调用都交给'
        'InvocationHandler。日志、鉴权、重试这类横切逻辑可以集中写一次，'
        '不用修改实现类。代理只能代理接口，类需要字节码库。',
    code: '''import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.List;

public class Main {
    interface Greeter {
        String greet(String name);
    }

    public static void main(String[] args) {
        List<String> log = new ArrayList<>();
        InvocationHandler handler = (Object proxy, Method method, Object[] methodArgs) -> {
            log.add(method.getName());
            String name = (String) methodArgs[0];
            return "hello " + name;
        };
        Greeter greeter = (Greeter) Proxy.newProxyInstance(
                Greeter.class.getClassLoader(),
                new Class<?>[] {Greeter.class},
                handler);
        System.out.println("result=" + greeter.greet("ada"));
        System.out.println("second=" + greeter.greet("lin"));
        System.out.println("calls=" + log);
        System.out.println("isProxy=" + Proxy.isProxyClass(greeter.getClass()));
    }
}''',
    output:
        'result=hello ada\nsecond=hello lin\ncalls=[greet, greet]\nisProxy=true',
    pitfalls: <String>[
      '代理类的 toString/equals/hashCode 也会进入 handler，需要单独处理。',
      '无参方法调用时 methodArgs 为 null，不能直接取下标。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '在 handler 里对 name 为空的情况返回 unknown，并测试空串调用。',
        hint: '在拼接前判断 name 是否 isEmpty。',
        answer: 'greet("") 返回 hello unknown，同时 log 里仍记录一次 greet。',
      ),
    ],
  ),
  JavaTopic(
    id: 241,
    level: 'advanced',
    title: 'Java 241：反射读取泛型签名',
    summary: '擦除的是运行时类型，签名信息仍保留在 Class 文件里。',
    concepts: <String>['GenericType', 'ParameterizedType', 'Type', '擦除'],
    objective: '能用 getGenericType 读出字段声明的泛型实参，并区分原始类型与普通类型。',
    explain:
        '字段与方法的泛型声明会写入 Class 文件的 Signature 属性，反射通过'
        'getGenericType 读取，强转为 ParameterizedType 后拿到实参列表。'
        '这也是 JSON 库能反序列化 List<String> 的原因；局部变量的泛型则拿不到。',
    code: '''import java.lang.reflect.Field;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.util.List;
import java.util.Map;

public class Main {
    static class Repo {
        List<String> names;
        Map<String, Integer> scores;
        int count;
    }

    public static void main(String[] args) throws Exception {
        Field names = Repo.class.getDeclaredField("names");
        Type generic = names.getGenericType();
        System.out.println("genericType=" + generic.getTypeName());
        ParameterizedType parameterized = (ParameterizedType) generic;
        System.out.println("rawType=" + parameterized.getRawType().getTypeName());
        System.out.println("argCount=" + parameterized.getActualTypeArguments().length);
        Field scores = Repo.class.getDeclaredField("scores");
        ParameterizedType scoreType = (ParameterizedType) scores.getGenericType();
        for (Type argument : scoreType.getActualTypeArguments()) {
            System.out.println("mapArg=" + argument.getTypeName());
        }
        Field count = Repo.class.getDeclaredField("count");
        System.out.println("plainType=" + count.getGenericType().getTypeName());
    }
}''',
    output:
        'genericType=java.util.List<java.lang.String>\nrawType=java.util.List\nargCount=1\nmapArg=java.lang.String\nmapArg=java.lang.Integer\nplainType=int',
    pitfalls: <String>[
      '对非泛型字段强转 ParameterizedType 会抛 ClassCastException。',
      '通配符与类型变量会以 WildcardType/TypeVariable 形式出现，处理前先 instanceof。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增字段 List<Map<String, Integer>> 并输出它的第二层实参。',
        hint: '先取外层 ParameterizedType，再取内层实参并再次强转。',
        answer: '可以读到 java.util.Map<java.lang.String, java.lang.Integer>，说明签名是递归结构。',
      ),
    ],
  ),
  JavaTopic(
    id: 242,
    level: 'advanced',
    title: 'Java 242：反射与 record',
    summary: '用 RecordComponent 读取组件，并用规范构造器创建实例。',
    concepts: <String>['record', 'RecordComponent', '规范构造器', '反射'],
    objective: '能通过反射列举 record 组件、创建实例并调用访问器。',
    explain:
        'record 在字节码里仍然是普通类，但有专门的 isRecord 与'
        'getRecordComponents API。组件顺序与声明顺序一致，访问器名等于'
        '组件名，规范构造器参数与组件一一对应，框架可以据此自动装配。',
    code: '''import java.lang.reflect.Constructor;
import java.lang.reflect.RecordComponent;

public class Main {
    record Point(int x, int y) {
    }

    public static void main(String[] args) throws Exception {
        System.out.println("isRecord=" + Point.class.isRecord());
        for (RecordComponent component : Point.class.getRecordComponents()) {
            System.out.println("component=" + component.getName() + ":" + component.getType().getSimpleName());
        }
        Constructor<Point> canonical = Point.class.getDeclaredConstructor(int.class, int.class);
        Point point = canonical.newInstance(3, 4);
        Point same = new Point(3, 4);
        System.out.println("instance=" + point);
        System.out.println("equals=" + point.equals(same));
        System.out.println("hashEqual=" + (point.hashCode() == same.hashCode()));
        for (RecordComponent component : Point.class.getRecordComponents()) {
            System.out.println("accessor=" + component.getAccessor().getName() + "=" + component.getAccessor().invoke(point));
        }
    }
}''',
    output:
        'isRecord=true\ncomponent=x:int\ncomponent=y:int\ninstance=Point[x=3, y=4]\nequals=true\nhashEqual=true\naccessor=x=3\naccessor=y=4',
    pitfalls: <String>[
      'record 的 toString/equals/hashCode 由编译器生成，手写覆盖会失去值语义。',
      '组件顺序是声明顺序，不要依赖集合遍历得到别的顺序。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增组件 String label 并观察 toString 与访问器输出的变化。',
        hint: '给 record 加第三个组件，构造器参数也跟着变。',
        answer: 'toString 变成 Point[x=3, y=4, label=...]，组件列表和构造器参数都多了一项。',
      ),
    ],
  ),
  JavaTopic(
    id: 243,
    level: 'advanced',
    title: 'Java 243：自定义注解入门',
    summary: '声明 @Retention(RUNTIME) + @Target 注解，并在运行时读取。',
    concepts: <String>['注解', 'Retention', 'Target', '反射'],
    objective: '能声明一个只在方法上生效、运行时可见的注解并读取它的值。',
    explain:
        '注解用 @interface 声明，元素写成方法形式。@Retention 决定保留到哪个'
        '阶段：RUNTIME 才能被反射读到；@Target 限定能标在哪里。'
        'method.getAnnotation 返回实例或 null，没有注解就是 null。',
    code: '''import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.Method;

public class Main {
    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.METHOD)
    @interface Label {
        String value();
    }

    static class Service {
        @Label("health")
        public String health() {
            return "ok";
        }

        public String plain() {
            return "plain";
        }
    }

    public static void main(String[] args) throws Exception {
        for (Method method : Service.class.getDeclaredMethods()) {
            Label label = method.getAnnotation(Label.class);
            if (label != null) {
                System.out.println("annotated=" + method.getName() + ":" + label.value());
            }
        }
        Method plain = Service.class.getMethod("plain");
        System.out.println("plainHasLabel=" + (plain.getAnnotation(Label.class) != null));
        System.out.println("service=" + new Service().health());
    }
}''',
    output:
        'annotated=health:health\nplainHasLabel=false\nservice=ok',
    pitfalls: <String>[
      '默认保留策略是 CLASS，反射读不到；要运行时可见必须写 RUNTIME。',
      '注解本身不执行任何逻辑，必须由反射或处理器主动读取。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 @Retention 改成 CLASS，预测并验证 annotated 行是否还存在。',
        hint: '只改保留策略一行。',
        answer: 'annotated 行消失，plainHasLabel 仍为 false，证明 CLASS 注解不进运行时。',
      ),
    ],
  ),
  JavaTopic(
    id: 244,
    level: 'advanced',
    title: 'Java 244：注解元素的类型与默认值',
    summary: '注解支持字符串、枚举、数组元素，并可为每个元素设默认值。',
    concepts: <String>['注解元素', '默认值', '枚举', '数组'],
    objective: '能声明带默认值的多元素注解，并区分使用默认值与显式赋值的输出。',
    explain:
        '注解元素只能是基本类型、String、Class、枚举、注解及其数组。'
        '用 default 提供默认值，使用时可以不写该元素；数组元素用花括号，'
        '读取时直接得到数组。',
    code: '''import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Method;
import java.util.Arrays;

public class Main {
    enum Level {
        LOW, HIGH
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Job {
        String name();

        Level level() default Level.LOW;

        int retries() default 1;

        String[] tags() default {"core"};
    }

    static class Worker {
        @Job(name = "sync")
        public void sync() {
        }

        @Job(name = "backup", level = Level.HIGH, retries = 3, tags = {"disk", "night"})
        public void backup() {
        }
    }

    public static void main(String[] args) throws Exception {
        for (String methodName : new String[] {"sync", "backup"}) {
            Method method = Worker.class.getMethod(methodName);
            Job job = method.getAnnotation(Job.class);
            System.out.println(job.name() + " level=" + job.level() + " retries=" + job.retries());
            System.out.println(job.name() + " tags=" + Arrays.toString(job.tags()));
        }
    }
}''',
    output:
        'sync level=LOW retries=1\nsync tags=[core]\nbackup level=HIGH retries=3\nbackup tags=[disk, night]',
    pitfalls: <String>[
      '没有 default 的元素必须显式赋值，否则编译失败。',
      '注解元素值必须是编译期常量，不能引用运行时变量。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 backup 补上 tags = {"disk"} 并观察输出长度。',
        hint: '数组元素用花括号包裹。',
        answer: 'backup tags 变成 [disk]，说明显式赋值会完全替换默认值。',
      ),
    ],
  ),
  JavaTopic(
    id: 245,
    level: 'advanced',
    title: 'Java 245：注解驱动的校验框架',
    summary: '用 NotBlank 与 Range 注解和反射实现一个迷你校验器。',
    concepts: <String>['注解', '校验', '反射', '框架原理'],
    objective: '能写一个遍历字段、读取注解并返回错误列表的通用校验方法。',
    explain:
        '框架的常见做法是：在字段上标注约束，运行时遍历 getDeclaredFields，'
        '用 isAnnotationPresent 与 getAnnotation 读取规则，再按规则检查值。'
        '校验逻辑与业务对象解耦，新增约束只需加注解。',
    code: '''import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;

public class Main {
    @Retention(RetentionPolicy.RUNTIME)
    @interface NotBlank {
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Range {
        int min();

        int max();
    }

    static class User {
        @NotBlank
        String name;

        @Range(min = 1, max = 120)
        int age;

        User(String name, int age) {
            this.name = name;
            this.age = age;
        }
    }

    static List<String> validate(Object target) throws Exception {
        List<String> errors = new ArrayList<>();
        for (Field field : target.getClass().getDeclaredFields()) {
            field.setAccessible(true);
            Object value = field.get(target);
            if (field.isAnnotationPresent(NotBlank.class)) {
                if (value == null || ((String) value).isBlank()) {
                    errors.add(field.getName() + ":blank");
                }
            }
            Range range = field.getAnnotation(Range.class);
            if (range != null) {
                int number = ((Integer) value).intValue();
                if (number < range.min() || number > range.max()) {
                    errors.add(field.getName() + ":outOfRange");
                }
            }
        }
        return errors;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("valid=" + validate(new User("ada", 30)));
        System.out.println("badName=" + validate(new User("  ", 30)));
        System.out.println("badAge=" + validate(new User("ada", 200)));
    }
}''',
    output:
        'valid=[]\nbadName=[name:blank]\nbadAge=[age:outOfRange]',
    pitfalls: <String>[
      'isBlank 是 Java 11 新增方法，空字符串与全空格都会判为 blank。',
      '反射读字段会绕过构造器校验，校验器应在对象构建后立刻运行。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 @Range 约束在 name 上并解释为何会抛 ClassCastException。',
        hint: 'Range 分支里把值强转成 Integer。',
        answer: 'String 不能转 Integer，说明校验器必须按字段类型选择处理方式。',
      ),
    ],
  ),
  JavaTopic(
    id: 246,
    level: 'advanced',
    title: 'Java 246：可重复注解',
    summary: '用 @Repeatable 在同一位置标注多次，并读取容器注解。',
    concepts: <String>['可重复注解', 'Repeatable', '容器注解', 'getAnnotationsByType'],
    objective: '能定义可重复注解与容器注解，并用两种方式读取多个值。',
    explain:
        'Java 8 起允许重复标注，前提是注解声明 @Repeatable(容器.class)，'
        '容器注解有一个返回注解数组的 value 元素。反射既可以直接读容器，'
        '也可以用 getAnnotationsByType 拿到展开后的数组。',
    code: '''import java.lang.annotation.Repeatable;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

public class Main {
    @Retention(RetentionPolicy.RUNTIME)
    @Repeatable(Roles.class)
    @interface Role {
        String value();
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Roles {
        Role[] value();
    }

    @Role("reader")
    @Role("writer")
    static class Editor {
    }

    public static void main(String[] args) {
        Roles roles = Editor.class.getAnnotation(Roles.class);
        for (Role role : roles.value()) {
            System.out.println("role=" + role.value());
        }
        Role[] direct = Editor.class.getAnnotationsByType(Role.class);
        System.out.println("count=" + direct.length);
        System.out.println("first=" + direct[0].value());
    }
}''',
    output: 'role=reader\nrole=writer\ncount=2\nfirst=reader',
    pitfalls: <String>[
      '直接 getAnnotation(Role.class) 拿不到重复注解，必须读容器或 getAnnotationsByType。',
      '容器注解的 value 元素名必须是 value，否则编译失败。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 Editor 再加一个 @Role("admin")，预测 count 与遍历输出。',
        hint: '重复注解按声明顺序保留。',
        answer: 'count 变成 3，role 行依次输出 reader、writer、admin。',
      ),
    ],
  ),
  JavaTopic(
    id: 247,
    level: 'advanced',
    title: 'Java 247：@Inherited 的继承规则',
    summary: '类注解可以继承，方法注解不会随重写自动继承。',
    concepts: <String>['Inherited', '注解继承', '方法重写', 'getDeclaredAnnotation'],
    objective: '能区分「子类能读到」与「子类自己声明」两种情况，并解释方法注解的行为。',
    explain:
        '@Inherited 只对类生效：子类通过 getAnnotation 能拿到父类的注解，'
        '但 getDeclaredAnnotation 仍为 null。方法上的注解永远不继承，'
        '子类重写后必须重新标注，否则 isAnnotationPresent 返回 false。',
    code: '''import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

public class Main {
    @Inherited
    @Retention(RetentionPolicy.RUNTIME)
    @interface Entity {
        String table();
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Audited {
    }

    @Entity(table = "users")
    static class Base {
        @Audited
        public void save() {
        }
    }

    static class Child extends Base {
        @Override
        public void save() {
        }
    }

    public static void main(String[] args) throws Exception {
        Entity childEntity = Child.class.getAnnotation(Entity.class);
        System.out.println("inheritedEntity=" + (childEntity != null));
        System.out.println("table=" + childEntity.table());
        System.out.println("childMethodAudited=" + Child.class.getMethod("save").isAnnotationPresent(Audited.class));
        System.out.println("baseMethodAudited=" + Base.class.getMethod("save").isAnnotationPresent(Audited.class));
        System.out.println("declaredOnChild=" + (Child.class.getDeclaredAnnotation(Entity.class) != null));
    }
}''',
    output:
        'inheritedEntity=true\ntable=users\nchildMethodAudited=false\nbaseMethodAudited=true\ndeclaredOnChild=false',
    pitfalls: <String>[
      '接口上的注解不会被子接口或实现类继承，@Inherited 只适用于类。',
      '子类重写方法后，父类方法上的注解不会被复制过去。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 @Inherited 去掉，重新运行并解释 inheritedEntity。',
        hint: '只删一行注解。',
        answer: 'inheritedEntity 变成 false，其余输出不变，说明类注解继承依赖 @Inherited。',
      ),
    ],
  ),
  JavaTopic(
    id: 248,
    level: 'advanced',
    title: 'Java 248：注解保留策略的差异',
    summary: 'SOURCE、CLASS、RUNTIME 三种策略决定注解能否活到运行时。',
    concepts: <String>['RetentionPolicy', 'SOURCE', 'CLASS', 'RUNTIME'],
    objective: '能预测每种保留策略下反射是否可见，并说明各自适用场景。',
    explain:
        'SOURCE 注解在编译后丢弃，只给编译器或 IDE 看；CLASS 保留在 Class '
        '文件里但不进运行时，供字节码工具使用；RUNTIME 才会被 JVM 保留，'
        '反射能读到。日常业务注解几乎都用 RUNTIME。',
    code: '''import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

public class Main {
    @Retention(RetentionPolicy.SOURCE)
    @interface SourceOnly {
    }

    @Retention(RetentionPolicy.CLASS)
    @interface ClassOnly {
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface RuntimeVisible {
    }

    @SourceOnly
    @ClassOnly
    @RuntimeVisible
    static class Sample {
    }

    public static void main(String[] args) {
        System.out.println("sourceVisible=" + Sample.class.isAnnotationPresent(SourceOnly.class));
        System.out.println("classVisible=" + Sample.class.isAnnotationPresent(ClassOnly.class));
        System.out.println("runtimeVisible=" + Sample.class.isAnnotationPresent(RuntimeVisible.class));
        System.out.println("annotationCount=" + Sample.class.getAnnotations().length);
    }
}''',
    output:
        'sourceVisible=false\nclassVisible=false\nruntimeVisible=true\nannotationCount=1',
    pitfalls: <String>[
      'SOURCE 注解写错不影响运行，但编译器检查会静默失效，排查时容易误判。',
      'getAnnotations 只返回 RUNTIME 注解，数量比源码里少是正常的。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 ClassOnly 改成 RUNTIME，预测 annotationCount。',
        hint: '运行时注解数量会随策略变化。',
        answer: 'annotationCount 变成 2，classVisible 也变成 true。',
      ),
    ],
  ),
  JavaTopic(
    id: 249,
    level: 'advanced',
    title: 'Java 249：record 紧凑构造器',
    summary: '在紧凑构造器里校验与规范化参数，再自动赋值给字段。',
    concepts: <String>['record', '紧凑构造器', '校验', '规范化'],
    objective: '能用紧凑构造器拒绝非法参数，并说明它不能重新赋值字段的原因。',
    explain:
        '紧凑构造器不写参数列表，参数名就是组件名，省掉 this.x = x。'
        '在里面可以校验并重新赋值参数，编译后编译器自动补上赋值。'
        '注意字段本身仍是 final，这里改的是构造器参数。',
    code: '''public class Main {
    record Range(int low, int high) {
        Range {
            if (low > high) {
                throw new IllegalArgumentException("low > high");
            }
            low = Math.max(low, 0);
        }

        int length() {
            return high - low;
        }
    }

    public static void main(String[] args) {
        Range range = new Range(-5, 10);
        System.out.println("range=" + range);
        System.out.println("length=" + range.length());
        try {
            new Range(9, 2);
        } catch (IllegalArgumentException error) {
            System.out.println("rejected=" + error.getMessage());
        }
        System.out.println("normalized=" + (range.low() == 0));
    }
}''',
    output:
        'range=Range[low=0, high=10]\nlength=10\nrejected=low > high\nnormalized=true',
    pitfalls: <String>[
      '紧凑构造器里写 this.low = low 会编译失败，编译器已经自动赋值。',
      '规范化只能改参数值，不能改变组件类型。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把规范化改成把 high 也限到 100 以内，并测试 new Range(0, 500)。',
        hint: '在紧凑构造器里再赋值 high = Math.min(high, 100)。',
        answer: '输出变成 Range[low=0, high=100]，说明两个参数都被规范化。',
      ),
    ],
  ),
  JavaTopic(
    id: 250,
    level: 'advanced',
    title: 'Java 250：record 的自定义访问器',
    summary: '覆盖访问器做格式化输出，同时保留 record 的值语义。',
    concepts: <String>['record', '访问器', '派生方法', '值语义'],
    objective: '能覆盖 record 访问器并添加派生方法，而不破坏 equals。',
    explain:
        'record 的访问器可以显式重写（不能改成别的名字），常用于返回'
        '规整后的值。派生方法（如 display/plus）像普通方法一样添加。'
        'equals/hashCode 只基于组件，与额外方法无关。',
    code: '''public class Main {
    record Money(long cents) {
        Money {
            if (cents < 0) {
                throw new IllegalArgumentException("negative");
            }
        }

        @Override
        public long cents() {
            return cents;
        }

        String display() {
            long whole = cents / 100;
            long fraction = cents % 100;
            return whole + "." + (fraction < 10 ? "0" + fraction : String.valueOf(fraction));
        }

        Money plus(Money other) {
            return new Money(cents + other.cents);
        }
    }

    public static void main(String[] args) {
        Money price = new Money(1999);
        Money tax = new Money(250);
        System.out.println("price=" + price.display());
        System.out.println("sum=" + price.plus(tax).display());
        System.out.println("cents=" + price.cents());
        System.out.println("raw=" + price);
        System.out.println("equal=" + price.equals(new Money(1999)));
    }
}''',
    output:
        'price=19.99\nsum=22.49\ncents=1999\nraw=Money[cents=1999]\nequal=true',
    pitfalls: <String>[
      '访问器返回类型必须与组件一致，签名不匹配会编译失败。',
      '用 String.format 做数字格式化会受 Locale 影响，教学示例应手写格式化。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 Money 增加次方方法 times(int)，并测试 new Money(1050).times(3)。',
        hint: '返回 new Money(cents * factor)，注意溢出。',
        answer: '得到 31.50，说明派生方法可以安全地构造新 record。',
      ),
    ],
  ),
  JavaTopic(
    id: 251,
    level: 'advanced',
    title: 'Java 251：record 实现接口',
    summary: 'record 可以 implements 接口，用 List.copyOf 守住集合组件。',
    concepts: <String>['record', '接口', 'List.copyOf', '不可变'],
    objective: '能写出实现接口的 record，并用防御性复制保证集合组件不可变。',
    explain:
        'record 只能继承 Record（隐式），但能实现接口，适合做多态的值对象。'
        '集合组件必须自己复制：否则外部修改原集合，record 的 equals/'
        'hashCode 会跟着变，作为 Map 键时会出现不可预测的丢失。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    interface Described {
        String describe();
    }

    record Team(String name, List<String> members) implements Described {
        Team {
            members = List.copyOf(members);
        }

        @Override
        public String describe() {
            return name + "(" + members.size() + "):" + String.join(",", members);
        }
    }

    public static void main(String[] args) {
        List<String> raw = new ArrayList<>();
        raw.add("ada");
        Team team = new Team("core", raw);
        raw.add("lin");
        System.out.println("isolated=" + team.describe());
        try {
            team.members().add("zoe");
        } catch (UnsupportedOperationException error) {
            System.out.println("membersReadOnly=true");
        }
        Team copy = new Team("core", List.of("ada"));
        System.out.println("same=" + team.equals(copy));
    }
}''',
    output: 'isolated=core(1):ada\nmembersReadOnly=true\nsame=true',
    pitfalls: <String>[
      '成员是 List 时，不复制会让外部改动穿透进 record。',
      'List.copyOf 遇到 null 元素会抛 NullPointerException。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '去掉紧凑构造器里的 List.copyOf，重新运行看 isolated 与 same。',
        hint: '直接删掉 members = List.copyOf(members); 这一行。',
        answer: 'isolated 变成 core(2):ada,lin，且 membersReadOnly 变成不可变性丢失。',
      ),
    ],
  ),
  JavaTopic(
    id: 252,
    level: 'advanced',
    title: 'Java 252：密封接口 + record 实现',
    summary: 'permits 限定实现者，用 instanceof 模式匹配分支处理。',
    concepts: <String>['sealed', 'permits', 'record', 'instanceof 模式'],
    objective: '能定义密封接口并用 instanceof 模式匹配穷尽处理所有实现。',
    explain:
        'sealed 把实现者限定为 permits 列出的类型，编译器因此知道全部子类型。'
        '配合 instanceof 模式匹配，每个分支变量直接可用，无需强转。'
        '最后的 throw 在密封层次完整时理论上不可达，但 Java 17 仍需写。',
    code: '''public class Main {
    sealed interface Shape permits Circle, Square, Rect {
    }

    record Circle(double radius) implements Shape {
    }

    record Square(double side) implements Shape {
    }

    record Rect(double width, double height) implements Shape {
    }

    static String describe(Shape shape) {
        if (shape instanceof Circle circle) {
            return "circle r=" + circle.radius();
        }
        if (shape instanceof Square square) {
            return "square side=" + square.side();
        }
        if (shape instanceof Rect rect) {
            return "rect " + rect.width() + "x" + rect.height();
        }
        throw new IllegalStateException("unreachable");
    }

    public static void main(String[] args) {
        Shape[] shapes = {new Circle(2), new Square(3), new Rect(4, 5)};
        for (Shape shape : shapes) {
            System.out.println(describe(shape));
        }
        System.out.println("sealed=" + Shape.class.isSealed());
        System.out.println("permitted=" + Shape.class.getPermittedSubclasses().length);
    }
}''',
    output:
        'circle r=2.0\nsquare side=3.0\nrect 4.0x5.0\nsealed=true\npermitted=3',
    pitfalls: <String>[
      'permits 列出的类型必须与它同包或同一个编译单元，否则编译失败。',
      '密封接口的实现类必须显式声明 final/sealed/non-sealed，否则报错。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 Triangle(double base, double height) 实现并删掉多余的 throw。',
        hint: '先改 permits 列表，再加 record 与一个 instanceof 分支。',
        answer: 'permitted 变成 4，第三个分支后仍需要 throw（Java 17 不做穷尽分析）。',
      ),
    ],
  ),
  JavaTopic(
    id: 253,
    level: 'advanced',
    title: 'Java 253：non-sealed 打开扩展',
    summary: '密封类里指定 non-sealed 子类，允许任意外部继续继承。',
    concepts: <String>['sealed', 'non-sealed', '继承', '模式匹配'],
    objective: '能解释 non-sealed 的作用，并验证密封边界在重启处的行为。',
    explain:
        'sealed 只控制第一层。子类声明为 non-sealed 后，这个分支就对所有'
        '后续继承者开放，常常用于「框架部分固定、部分可扩展」的设计。'
        '密封属性本身不继承：Branch 的 isSealed 为 false。',
    code: '''public class Main {
    sealed abstract static class Node permits Leaf, Branch {
        abstract int size();
    }

    static final class Leaf extends Node {
        @Override
        int size() {
            return 1;
        }
    }

    static non-sealed class Branch extends Node {
        private final Node left;
        private final Node right;

        Branch(Node left, Node right) {
            this.left = left;
            this.right = right;
        }

        @Override
        int size() {
            return left.size() + right.size();
        }
    }

    static final class TaggedBranch extends Branch {
        TaggedBranch(Node left, Node right) {
            super(left, right);
        }

        @Override
        int size() {
            return 100 + super.size();
        }
    }

    public static void main(String[] args) {
        Node tree = new Branch(new Leaf(), new Branch(new Leaf(), new Leaf()));
        Node tagged = new TaggedBranch(new Leaf(), new Leaf());
        System.out.println("treeSize=" + tree.size());
        System.out.println("taggedSize=" + tagged.size());
        System.out.println("nodeSealed=" + Node.class.isSealed());
        System.out.println("branchSealed=" + Branch.class.isSealed());
        System.out.println("leafFinal=" + java.lang.reflect.Modifier.isFinal(Leaf.class.getModifiers()));
    }
}''',
    output:
        'treeSize=3\ntaggedSize=102\nnodeSealed=true\nbranchSealed=false\nleafFinal=true',
    pitfalls: <String>[
      'non-sealed 是关键字组合，不是注解，写错会直接编译失败。',
      '密封类里的子类必须可访问，匿名内部类不能作为 permitted 子类。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 Branch 的 non-sealed 改成 final，解释编译错误。',
        hint: 'final 类不能再被 TaggedBranch 继承。',
        answer: 'TaggedBranch 编译失败，提示无法从 final 类继承，证明 non-sealed 是扩展点。',
      ),
    ],
  ),
  JavaTopic(
    id: 254,
    level: 'advanced',
    title: 'Java 254：record 作为 Map 键',
    summary: 'record 自动生成 equals/hashCode，天然适合做复合键。',
    concepts: <String>['record', 'Map 键', 'equals', 'hashCode'],
    objective: '能用一个 record 做复合键查询 Map，并说明为什么它能替代手写 equals。',
    explain:
        'record 的 equals 与 hashCode 由编译器根据所有组件生成，'
        '因此两个组件值相同的实例是等价的键。这比手写坐标类更安全，'
        '也便于在构造器里加上范围校验。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    record Coordinate(int x, int y) {
        Coordinate {
            if (x < 0 || y < 0) {
                throw new IllegalArgumentException("negative coordinate");
            }
        }
    }

    public static void main(String[] args) {
        Map<Coordinate, String> labels = new LinkedHashMap<>();
        labels.put(new Coordinate(0, 0), "origin");
        labels.put(new Coordinate(1, 2), "mark");
        System.out.println("lookup=" + labels.get(new Coordinate(1, 2)));
        System.out.println("missing=" + labels.get(new Coordinate(2, 1)));
        System.out.println("contains=" + labels.containsKey(new Coordinate(0, 0)));
        System.out.println("labels=" + labels);
        labels.put(new Coordinate(0, 0), "zero");
        System.out.println("afterReplace=" + labels);
        try {
            new Coordinate(-1, 0);
        } catch (IllegalArgumentException error) {
            System.out.println("rejected=" + error.getMessage());
        }
    }
}''',
    output:
        'lookup=mark\nmissing=null\ncontains=true\nlabels={Coordinate[x=0, y=0]=origin, Coordinate[x=1, y=2]=mark}\nafterReplace={Coordinate[x=0, y=0]=zero, Coordinate[x=1, y=2]=mark}\nrejected=negative coordinate',
    pitfalls: <String>[
      'record 的 println 输出依赖 toString 格式，assert 时要避免依赖它。',
      '组件是可变对象时，哈希值会随对象变化，record 也无法保护你。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 Map 换成 HashMap，观察 afterReplace 的输出是否变化。',
        hint: 'LinkedHashMap 保持插入顺序，HashMap 的打印顺序不保证。',
        answer: '逻辑结果不变（两个键），但打印顺序可能不同，说明顺序不应成为契约。',
      ),
    ],
  ),
  JavaTopic(
    id: 255,
    level: 'advanced',
    title: 'Java 255：模板方法模式',
    summary: '父类固定算法骨架，子类只填可变步骤。',
    concepts: <String>['模板方法', '抽象类', 'final 方法', '钩子方法'],
    objective: '能用 final 方法固定流程、用抽象方法开放变化点。',
    explain:
        '模板方法把「流程顺序」写在父类的 final 方法里，把每一步声明为'
        '抽象方法或带默认实现的钩子。子类只能替换步骤，无法打乱顺序，'
        '这样流程约束由编译器保证。',
    code: '''public class Main {
    static abstract class Report {
        final String render() {
            return header() + body() + footer();
        }

        abstract String header();

        abstract String body();

        String footer() {
            return "|end";
        }
    }

    static final class CsvReport extends Report {
        @Override
        String header() {
            return "id,name;";
        }

        @Override
        String body() {
            return "1,ada;2,lin;";
        }
    }

    static final class TextReport extends Report {
        @Override
        String header() {
            return "[report]";
        }

        @Override
        String body() {
            return "ada, lin";
        }

        @Override
        String footer() {
            return "[/report]";
        }
    }

    public static void main(String[] args) {
        Report csv = new CsvReport();
        Report text = new TextReport();
        System.out.println("csv=" + csv.render());
        System.out.println("text=" + text.render());
    }
}''',
    output: 'csv=id,name;1,ada;2,lin;|end\ntext=[report]ada, lin[/report]',
    pitfalls: <String>[
      'render 不加 final 就可能被子类覆盖，流程约束形同虚设。',
      '钩子方法要提供合理默认值，否则子类被迫实现无关步骤。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 MarkdownReport 并只实现 header 与 body，观察 footer 的默认值。',
        hint: '不覆盖 footer，直接继承默认实现。',
        answer: '输出以 |end 结尾，说明钩子方法提供了可复用的默认步骤。',
      ),
    ],
  ),
  JavaTopic(
    id: 256,
    level: 'advanced',
    title: 'Java 256：装饰器模式',
    summary: '用包装对象叠加功能，顺序不同结果就不同。',
    concepts: <String>['装饰器', '组合优于继承', '包装', '开闭原则'],
    objective: '能实现可叠加的装饰器链，并解释为什么它比继承组合更灵活。',
    explain:
        '装饰器实现同一接口并持有一个同类型对象，调用时先增强再转发。'
        '功能可以任意组合、任意嵌套，新增功能不用修改原有类。'
        '与继承相比，n 个装饰器能产生指数级的组合。',
    code: '''import java.util.Locale;

public class Main {
    interface Text {
        String value();
    }

    static final class Plain implements Text {
        private final String content;

        Plain(String content) {
            this.content = content;
        }

        @Override
        public String value() {
            return content;
        }
    }

    static final class Upper implements Text {
        private final Text inner;

        Upper(Text inner) {
            this.inner = inner;
        }

        @Override
        public String value() {
            return inner.value().toUpperCase(Locale.ROOT);
        }
    }

    static final class Bracketed implements Text {
        private final Text inner;

        Bracketed(Text inner) {
            this.inner = inner;
        }

        @Override
        public String value() {
            return "[" + inner.value() + "]";
        }
    }

    static final class Angled implements Text {
        private final Text inner;

        Angled(Text inner) {
            this.inner = inner;
        }

        @Override
        public String value() {
            return "<" + inner.value() + ">";
        }
    }

    public static void main(String[] args) {
        Text plain = new Plain("java");
        Text nested = new Bracketed(new Angled(new Upper(plain)));
        Text swapped = new Angled(new Bracketed(new Upper(plain)));
        System.out.println("plain=" + plain.value());
        System.out.println("nested=" + nested.value());
        System.out.println("swapped=" + swapped.value());
    }
}''',
    output: 'plain=java\nnested=[<JAVA>]\nswapped=<[JAVA]>',
    pitfalls: <String>[
      '装饰器顺序影响结果，构造时要写清楚嵌套层次。',
      'toUpperCase 不带 Locale 会受系统语言影响，应显式传 Locale.ROOT。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '再包一层 Upper，观察大写与括号叠加后的结果。',
        hint: '在 nested 外面再套 new Upper(...)。',
        answer: '输出变成 [<JAVA>]，括号不受大小写影响，说明装饰器只改自己关心的部分。',
      ),
    ],
  ),
  JavaTopic(
    id: 257,
    level: 'advanced',
    title: 'Java 257：适配器模式',
    summary: '用适配器把不兼容的旧接口包装成目标接口。',
    concepts: <String>['适配器', '接口转换', '委托', '兼容性'],
    objective: '能写一个实现目标接口、内部委托给旧类的适配器。',
    explain:
        '旧类签名与新接口不一致时，不要去改旧类（可能被其他代码依赖），'
        '而是写一个适配器：实现新接口，内部持有旧对象，把调用翻译过去。'
        '调用方只依赖新接口，旧实现可以保持不变。',
    code: '''public class Main {
    interface Printer {
        String print(String text);
    }

    static final class LegacyPrinter {
        String writeLine(String text, boolean newline) {
            return text + (newline ? "\\n" : "");
        }
    }

    static final class LegacyAdapter implements Printer {
        private final LegacyPrinter legacy;

        LegacyAdapter(LegacyPrinter legacy) {
            this.legacy = legacy;
        }

        @Override
        public String print(String text) {
            return legacy.writeLine(text, false);
        }
    }

    static String render(Printer printer, String text) {
        return "<<" + printer.print(text) + ">>";
    }

    public static void main(String[] args) {
        LegacyPrinter legacy = new LegacyPrinter();
        Printer adapter = new LegacyAdapter(legacy);
        System.out.println("direct=" + legacy.writeLine("hi", false));
        System.out.println("adapted=" + adapter.print("hi"));
        System.out.println("rendered=" + render(adapter, "hi"));
    }
}''',
    output: 'direct=hi\nadapted=hi\nrendered=<<hi>>',
    pitfalls: <String>[
      '适配器只做签名转换，不要在里叠加业务逻辑，否则职责不清。',
      '双向适配容易变成循环调用，只做单向转换更安全。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '让适配器默认带换行，观察 rendered 输出。',
        hint: '把 writeLine 的第二个参数改成 true。',
        answer: 'rendered 变成 <<hi\n>>，说明适配器决定了参数映射方式。',
      ),
    ],
  ),
  JavaTopic(
    id: 258,
    level: 'advanced',
    title: 'Java 258：命令模式与撤销',
    summary: '把操作封装成对象，用栈记录历史实现撤销。',
    concepts: <String>['命令模式', '撤销', 'Deque', '历史记录'],
    objective: '能把一次编辑封装成可执行/可撤销的命令对象。',
    explain:
        '命令对象持有接收者与参数，execute 与 undo 成对实现。把命令压入'
        '双端队列，撤销时弹出并调用 undo，就能恢复上一步状态。'
        '这也是编辑器撤销栈与事务日志的基本模型。',
    code: '''import java.util.ArrayDeque;
import java.util.Deque;

public class Main {
    interface Command {
        void execute();

        void undo();
    }

    static final class Editor {
        private final StringBuilder text = new StringBuilder();

        void append(String value) {
            text.append(value);
        }

        void deleteLast(int count) {
            text.delete(text.length() - count, text.length());
        }

        String text() {
            return text.toString();
        }
    }

    static final class AppendCommand implements Command {
        private final Editor editor;
        private final String value;

        AppendCommand(Editor editor, String value) {
            this.editor = editor;
            this.value = value;
        }

        @Override
        public void execute() {
            editor.append(value);
        }

        @Override
        public void undo() {
            editor.deleteLast(value.length());
        }
    }

    public static void main(String[] args) {
        Editor editor = new Editor();
        Deque<Command> history = new ArrayDeque<>();
        for (String word : new String[] {"ab", "cd", "ef"}) {
            Command command = new AppendCommand(editor, word);
            command.execute();
            history.push(command);
            System.out.println("after=" + editor.text());
        }
        while (!history.isEmpty()) {
            history.pop().undo();
            System.out.println("undo=" + editor.text());
        }
    }
}''',
    output:
        'after=ab\nafter=abcd\nafter=abcdef\nundo=abcd\nundo=ab\nundo=',
    pitfalls: <String>[
      'undo 必须精确反向执行 execute，长度算错会把文本删坏。',
      'ArrayDeque 不允许 null 元素，历史记录里不要放空命令。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增删除命令并实现它的 undo（把删除内容恢复回去）。',
        hint: '删除前先保存被删子串，undo 时再 append 回去。',
        answer: '删除命令 undo 后文本回到删除前的状态，与追加命令组成混合历史。',
      ),
    ],
  ),
  JavaTopic(
    id: 259,
    level: 'advanced',
    title: 'Java 259：状态模式',
    summary: '每个状态一个对象，状态自己决定下一步走向。',
    concepts: <String>['状态模式', '状态机', '多态', '转移'],
    objective: '能把 if-else 状态分支改成状态对象，并实现终态自循环。',
    explain:
        '状态模式把每个状态的转移规则放进状态类，上下文只持有一个当前状态。'
        '新增状态只需加一个类，不用改庞大的 switch。终态通常让 next 返回'
        '自身，保证重复调用不会越界。',
    code: '''public class Main {
    interface State {
        State next();

        String name();
    }

    static final class Draft implements State {
        @Override
        public State next() {
            return new Review();
        }

        @Override
        public String name() {
            return "DRAFT";
        }
    }

    static final class Review implements State {
        @Override
        public State next() {
            return new Published();
        }

        @Override
        public String name() {
            return "REVIEW";
        }
    }

    static final class Published implements State {
        @Override
        public State next() {
            return this;
        }

        @Override
        public String name() {
            return "PUBLISHED";
        }
    }

    static final class Document {
        private State state = new Draft();

        void advance() {
            state = state.next();
        }

        String state() {
            return state.name();
        }
    }

    public static void main(String[] args) {
        Document document = new Document();
        System.out.println("start=" + document.state());
        document.advance();
        System.out.println("afterAdvance=" + document.state());
        document.advance();
        document.advance();
        System.out.println("settled=" + document.state());
        System.out.println("terminalStable=" + new Published().next().name().equals("PUBLISHED"));
    }
}''',
    output:
        'start=DRAFT\nafterAdvance=REVIEW\nsettled=PUBLISHED\nterminalStable=true',
    pitfalls: <String>[
      '状态对象无状态时可以复用单例，有状态时必须每次新建。',
      '忘记处理终态会让多次 advance 抛异常或回退。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 Archived 状态，让 PUBLISHED 的 next 进入 ARCHIVED 并终止。',
        hint: '修改 Published.next 并新增一个实现类。',
        answer: '第三次 advance 后状态变成 ARCHIVED，再次 advance 仍为 ARCHIVED。',
      ),
    ],
  ),
  JavaTopic(
    id: 260,
    level: 'advanced',
    title: 'Java 260：访问者模式',
    summary: '元素 accept 访问者，双重分派把新操作加到类外。',
    concepts: <String>['访问者', '双重分派', '开闭原则', 'accept'],
    objective: '能实现 Visitor 与 Element 的双重分派，并说明它适合什么场景。',
    explain:
        'element.accept(visitor) 先按元素的实际类型选中 accept 实现，'
        '再由 accept 调用 visitor 对应的重载方法，完成两次动态分派。'
        '这样新增一种输出格式只需加一个 Visitor，不用改元素类；'
        '代价是新增元素类型要改所有 Visitor。',
    code: '''public class Main {
    interface Visitor {
        String visit(IntNode node);

        String visit(TextNode node);
    }

    interface Element {
        String accept(Visitor visitor);
    }

    static final class IntNode implements Element {
        private final int value;

        IntNode(int value) {
            this.value = value;
        }

        int value() {
            return value;
        }

        @Override
        public String accept(Visitor visitor) {
            return visitor.visit(this);
        }
    }

    static final class TextNode implements Element {
        private final String value;

        TextNode(String value) {
            this.value = value;
        }

        String value() {
            return value;
        }

        @Override
        public String accept(Visitor visitor) {
            return visitor.visit(this);
        }
    }

    static final class JsonVisitor implements Visitor {
        @Override
        public String visit(IntNode node) {
            return String.valueOf(node.value());
        }

        @Override
        public String visit(TextNode node) {
            return "\\"" + node.value() + "\\"";
        }
    }

    static final class DebugVisitor implements Visitor {
        @Override
        public String visit(IntNode node) {
            return "int(" + node.value() + ")";
        }

        @Override
        public String visit(TextNode node) {
            return "text(" + node.value() + ")";
        }
    }

    public static void main(String[] args) {
        Element[] elements = {new IntNode(42), new TextNode("java")};
        Visitor json = new JsonVisitor();
        Visitor debug = new DebugVisitor();
        StringBuilder builder = new StringBuilder();
        for (Element element : elements) {
            if (builder.length() > 0) {
                builder.append(",");
            }
            builder.append(element.accept(json));
        }
        System.out.println("json=" + builder);
        System.out.println("debug=" + elements[1].accept(debug));
        System.out.println("intDebug=" + elements[0].accept(debug));
    }
}''',
    output: 'json=42,"java"\ndebug=text(java)\nintDebug=int(42)',
    pitfalls: <String>[
      '元素类型稳定、操作频繁变化时访问者才划算，反之会变成维护负担。',
      'accept 方法里不要写业务逻辑，它只负责分派。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 CsvVisitor 并用它输出两个元素。',
        hint: '实现两个 visit 重载，分别返回数字与不加引号的文本。',
        answer: '输出 42,java，说明新增操作没有修改任何 Element 类。',
      ),
    ],
  ),
  JavaTopic(
    id: 261,
    level: 'advanced',
    title: 'Java 261：责任链模式',
    summary: '请求沿处理器链传递，直到某个节点能处理为止。',
    concepts: <String>['责任链', '链式设置', '转发', '兜底'],
    objective: '能搭建处理器链，并让无法处理的请求落到兜底分支。',
    explain:
        '每个处理器持有一个后继引用，自己能处理就返回，否则转发给后继。'
        '链尾没有后继时返回兜底结果。审批、过滤器、异常处理都可以用'
        '这个结构，调用方只接触链头。',
    code: '''public class Main {
    static abstract class Handler {
        private Handler next;

        Handler setNext(Handler next) {
            this.next = next;
            return next;
        }

        String handle(int amount) {
            if (next != null) {
                return next.handle(amount);
            }
            return "unhandled";
        }
    }

    static final class Clerk extends Handler {
        @Override
        String handle(int amount) {
            if (amount <= 100) {
                return "clerk:" + amount;
            }
            return super.handle(amount);
        }
    }

    static final class Manager extends Handler {
        @Override
        String handle(int amount) {
            if (amount <= 1000) {
                return "manager:" + amount;
            }
            return super.handle(amount);
        }
    }

    static final class Director extends Handler {
        @Override
        String handle(int amount) {
            if (amount <= 10000) {
                return "director:" + amount;
            }
            return super.handle(amount);
        }
    }

    public static void main(String[] args) {
        Handler clerk = new Clerk();
        Handler manager = new Manager();
        Handler director = new Director();
        clerk.setNext(manager).setNext(director);
        int[] amounts = {80, 500, 5000, 50000};
        for (int amount : amounts) {
            System.out.println(amount + " -> " + clerk.handle(amount));
        }
    }
}''',
    output:
        '80 -> clerk:80\n500 -> manager:500\n5000 -> director:5000\n50000 -> unhandled',
    pitfalls: <String>[
      '链过长会有性能开销，且忘设 next 会让请求静默丢失。',
      'setNext 返回后继而不是 this，链式写法才是 a.setNext(b).setNext(c)。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 Clerk 的额度改成 1000，观察 500 的归属变化。',
        hint: '只改一个比较值。',
        answer: '500 -> clerk:500，说明链上第一个满足条件的处理器胜出。',
      ),
    ],
  ),
  JavaTopic(
    id: 262,
    level: 'advanced',
    title: 'Java 262：原型模式与深拷贝',
    summary: 'clone 默认是浅拷贝，引用字段必须手动复制。',
    concepts: <String>['原型模式', 'clone', '浅拷贝', '深拷贝'],
    objective: '能识别浅拷贝共享引用的问题，并在 clone 中完成深拷贝。',
    explain:
        'Object.clone 逐字段复制，引用类型字段复制的是地址，原对象和副本'
        '会共享同一个 List。要真正独立，必须在 clone 里重新创建可变字段。'
        '现代写法更推荐拷贝构造器，语义比 Cloneable 清晰。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static final class Config implements Cloneable {
        private String name;
        private List<String> tags;

        Config(String name, List<String> tags) {
            this.name = name;
            this.tags = new ArrayList<>(tags);
        }

        void rename(String name) {
            this.name = name;
        }

        void addTag(String tag) {
            tags.add(tag);
        }

        boolean sharesTags(Config other) {
            return tags == other.tags;
        }

        @Override
        public Config clone() {
            try {
                Config copy = (Config) super.clone();
                copy.tags = new ArrayList<>(tags);
                return copy;
            } catch (CloneNotSupportedException error) {
                throw new AssertionError(error);
            }
        }

        @Override
        public String toString() {
            return name + tags;
        }
    }

    public static void main(String[] args) {
        Config original = new Config("base", List.of("a"));
        Config copy = original.clone();
        copy.rename("copy");
        copy.addTag("b");
        System.out.println("original=" + original);
        System.out.println("copy=" + copy);
        System.out.println("tagsShared=" + original.sharesTags(copy));
    }
}''',
    output: 'original=base[a]\ncopy=copy[a, b]\ntagsShared=false',
    pitfalls: <String>[
      '注释掉 copy.tags = new ArrayList<>(tags) 后 tagsShared 会变成 true。',
      'clone 不调用构造器，构造器里的校验与规范化不会在副本上执行。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '去掉 clone 中的深拷贝，预测 original 的输出。',
        hint: '只删 copy.tags = new ArrayList<>(tags); 一行。',
        answer: 'original 变成 base[a, b]，tagsShared 变成 true，证明浅拷贝共享了列表。',
      ),
    ],
  ),
  JavaTopic(
    id: 263,
    level: 'advanced',
    title: 'Java 263：享元模式',
    summary: '把可共享的内部状态缓存起来，只重复存储外部状态。',
    concepts: <String>['享元', '缓存', 'computeIfAbsent', '内部/外部状态'],
    objective: '能用工厂缓存共享对象，并解释内部状态与外部状态的划分。',
    explain:
        '享元把大量重复对象的「不变部分」抽成共享实例，把「每个实例不同'
        '的部分」放到外部传入。这里字符字形共享，位置是外部状态。'
        '缓存用 computeIfAbsent 一次完成查找与创建。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    static final class Glyph {
        private final char symbol;

        private Glyph(char symbol) {
            this.symbol = symbol;
        }

        @Override
        public String toString() {
            return String.valueOf(symbol);
        }
    }

    static final class GlyphFactory {
        private final Map<Character, Glyph> cache = new LinkedHashMap<>();

        Glyph get(char symbol) {
            return cache.computeIfAbsent(symbol, Glyph::new);
        }

        int size() {
            return cache.size();
        }
    }

    static final class Position {
        private final Glyph glyph;
        private final int x;

        Position(Glyph glyph, int x) {
            this.glyph = glyph;
            this.x = x;
        }

        @Override
        public String toString() {
            return glyph + "@" + x;
        }
    }

    public static void main(String[] args) {
        GlyphFactory factory = new GlyphFactory();
        String text = "banana";
        StringBuilder rendered = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            Position position = new Position(factory.get(text.charAt(i)), i);
            if (i > 0) {
                rendered.append(" ");
            }
            rendered.append(position);
        }
        System.out.println("rendered=" + rendered);
        System.out.println("uniqueGlyphs=" + factory.size());
        System.out.println("sameInstance=" + (factory.get('a') == factory.get('a')));
    }
}''',
    output:
        'rendered=b@0 a@1 n@2 a@3 n@4 a@5\nuniqueGlyphs=3\nsameInstance=true',
    pitfalls: <String>[
      '享元的共享对象必须不可变，否则一处修改会影响所有使用者。',
      '缓存无上限时会变成内存泄漏，真实场景要限制大小或用弱引用。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把文本改成 aaaa 并预测 uniqueGlyphs 与 rendered。',
        hint: '四个字符都是同一个字形。',
        answer: 'uniqueGlyphs=1，rendered 为 a@0 a@1 a@2 a@3。',
      ),
    ],
  ),
  JavaTopic(
    id: 264,
    level: 'advanced',
    title: 'Java 264：虚拟代理',
    summary: '代理先挡住昂贵对象，真正需要时才创建。',
    concepts: <String>['代理模式', '延迟加载', '惰性初始化', '委托'],
    objective: '能实现首次访问才创建真实对象的虚拟代理，并验证只创建一次。',
    explain:
        '虚拟代理与真实对象实现同一接口，内部持有可空的真实对象引用。'
        '第一次调用时才创建，之后直接转发。创建开销大（图片解码、'
        '远程连接）时能显著减少启动成本。',
    code: '''public class Main {
    interface Image {
        String render();
    }

    static final class RealImage implements Image {
        private final String name;
        private int renders;

        RealImage(String name) {
            this.name = name;
            System.out.println("load=" + name);
        }

        @Override
        public String render() {
            renders++;
            return name + "#" + renders;
        }
    }

    static final class LazyImage implements Image {
        private final String name;
        private RealImage real;

        LazyImage(String name) {
            this.name = name;
        }

        @Override
        public String render() {
            if (real == null) {
                real = new RealImage(name);
            }
            return real.render();
        }
    }

    public static void main(String[] args) {
        Image image = new LazyImage("cover.png");
        System.out.println("created=" + (image instanceof LazyImage));
        System.out.println("first=" + image.render());
        System.out.println("second=" + image.render());
    }
}''',
    output:
        'created=true\nload=cover.png\nfirst=cover.png#1\nsecond=cover.png#2',
    pitfalls: <String>[
      '代理与真实对象必须实现同一接口，否则调用方需要知道具体类型。',
      '多线程下惰性初始化需要同步，单例的 double-check 问题在这里同样存在。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '在构造 LazyImage 后立刻打印 loaded 标记，验证此时还没有加载。',
        hint: '用反射或再加一个 isLoaded() 方法读取 real 是否为 null。',
        answer: '构造后 isLoaded 为 false，首次 render 后才变成 true。',
      ),
    ],
  ),
  JavaTopic(
    id: 265,
    level: 'advanced',
    title: 'Java 265：组合模式',
    summary: '文件与目录实现同一接口，递归计算大小与渲染树。',
    concepts: <String>['组合模式', '树结构', '递归', '统一接口'],
    objective: '能让叶子与容器实现同一接口，并用递归处理整棵树。',
    explain:
        '组合模式把「单个对象」和「对象容器」统一成同一接口，调用方不必'
        '区分。容器的方法通常递归调用子节点，于是整棵树的操作只写一份。'
        '文件系统的文件与目录、UI 控件树都是典型例子。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    interface Node {
        int size();

        String render();
    }

    static final class FileNode implements Node {
        private final String name;
        private final int bytes;

        FileNode(String name, int bytes) {
            this.name = name;
            this.bytes = bytes;
        }

        @Override
        public int size() {
            return bytes;
        }

        @Override
        public String render() {
            return name;
        }
    }

    static final class DirNode implements Node {
        private final String name;
        private final List<Node> children = new ArrayList<>();

        DirNode(String name) {
            this.name = name;
        }

        DirNode add(Node child) {
            children.add(child);
            return this;
        }

        @Override
        public int size() {
            int total = 0;
            for (Node child : children) {
                total += child.size();
            }
            return total;
        }

        @Override
        public String render() {
            StringBuilder builder = new StringBuilder(name).append("/");
            for (Node child : children) {
                builder.append(" ").append(child.render());
            }
            return builder.toString();
        }
    }

    public static void main(String[] args) {
        DirNode root = new DirNode("src")
                .add(new FileNode("Main.java", 120))
                .add(new DirNode("util").add(new FileNode("Io.java", 80)));
        System.out.println("render=" + root.render());
        System.out.println("size=" + root.size());
        System.out.println("matches=" + (root.size() == 200));
    }
}''',
    output:
        'render=src/ Main.java util/ Io.java\nsize=200\nmatches=true',
    pitfalls: <String>[
      '容器与叶子的接口要克制，叶子实现 add 会带来无意义的异常。',
      '递归深度受调用栈限制，极深的树需要改成显式栈遍历。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增一个 depth() 方法，返回树的最大深度。',
        hint: '叶子返回 1，容器返回 1 + 子节点最大 depth。',
        answer: '示例树 depth 为 3（src -> util -> Io.java），说明递归可以叠加新操作。',
      ),
    ],
  ),
  JavaTopic(
    id: 266,
    level: 'advanced',
    title: 'Java 266：桥接模式',
    summary: '把抽象与实现拆成两个维度，用组合代替类爆炸。',
    concepts: <String>['桥接', '抽象与实现分离', '组合', '维度'],
    objective: '能识别两个独立变化的维度，并用组合把它们拆开。',
    explain:
        '控件类型（段落/标题）和输出格式（HTML/纯文本）是两个独立变化的'
        '维度。用继承会得到 2×2 个子类，用桥接只需 2+2 个类，'
        '新增一个维度不会引起组合爆炸。',
    code: '''import java.util.Locale;

public class Main {
    interface Renderer {
        String render(String text);
    }

    static final class HtmlRenderer implements Renderer {
        @Override
        public String render(String text) {
            return "<p>" + text + "</p>";
        }
    }

    static final class PlainRenderer implements Renderer {
        @Override
        public String render(String text) {
            return text;
        }
    }

    static abstract class Widget {
        protected final Renderer renderer;

        Widget(Renderer renderer) {
            this.renderer = renderer;
        }

        abstract String draw();
    }

    static final class Paragraph extends Widget {
        private final String text;

        Paragraph(Renderer renderer, String text) {
            super(renderer);
            this.text = text;
        }

        @Override
        String draw() {
            return renderer.render(text);
        }
    }

    static final class Heading extends Widget {
        private final String text;

        Heading(Renderer renderer, String text) {
            super(renderer);
            this.text = text;
        }

        @Override
        String draw() {
            return renderer.render(text.toUpperCase(Locale.ROOT));
        }
    }

    public static void main(String[] args) {
        System.out.println("html=" + new Paragraph(new HtmlRenderer(), "hi").draw());
        System.out.println("plain=" + new Paragraph(new PlainRenderer(), "hi").draw());
        System.out.println("heading=" + new Heading(new HtmlRenderer(), "news").draw());
        System.out.println("combos=" + (2 * 2));
    }
}''',
    output:
        'html=<p>hi</p>\nplain=hi\nheading=<p>NEWS</p>\ncombos=4',
    pitfalls: <String>[
      '只有确实存在两个独立变化维度时才值得桥接，否则是过度设计。',
      '抽象侧不要反过来依赖实现侧的具体类型，否则桥就断了。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 MarkdownRenderer 并输出段落与标题。',
        hint: '实现 Renderer 一个方法即可，不用改 Widget 层次。',
        answer: '只需新增一个类就能得到 2×3 种组合，证明两个维度独立扩展。',
      ),
    ],
  ),
  JavaTopic(
    id: 267,
    level: 'advanced',
    title: 'Java 267：迭代器模式',
    summary: '自定义 Iterable 与 Iterator，让 for-each 遍历自己的集合。',
    concepts: <String>['迭代器', 'Iterable', 'Iterator', 'for-each'],
    objective: '能实现 Iterable 让自定义类型支持 for-each，并正确处理耗尽异常。',
    explain:
        'for-each 只是语法糖：它调用 iterator()，再用 hasNext/next 循环。'
        '实现 Iterable 就能被增强 for 遍历，无需暴露内部存储结构。'
        'next 在耗尽时必须抛 NoSuchElementException。',
    code: '''import java.util.Iterator;
import java.util.NoSuchElementException;

public class Main {
    static final class Range implements Iterable<Integer> {
        private final int start;
        private final int end;

        Range(int start, int end) {
            this.start = start;
            this.end = end;
        }

        @Override
        public Iterator<Integer> iterator() {
            return new Iterator<Integer>() {
                private int current = start;

                @Override
                public boolean hasNext() {
                    return current < end;
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
        Range range = new Range(2, 5);
        StringBuilder builder = new StringBuilder();
        for (int value : range) {
            builder.append(value).append(";");
        }
        int sum = 0;
        for (int value : range) {
            sum += value;
        }
        System.out.println("values=" + builder);
        System.out.println("sum=" + sum);
        Iterator<Integer> iterator = range.iterator();
        while (iterator.hasNext()) {
            System.out.println("next=" + iterator.next());
        }
        try {
            new Range(5, 5).iterator().next();
        } catch (NoSuchElementException error) {
            System.out.println("exhausted=true");
        }
    }
}''',
    output:
        'values=2;3;4;\nsum=9\nnext=2\nnext=3\nnext=4\nexhausted=true',
    pitfalls: <String>[
      '每次 iterator() 都要返回独立的新迭代器，否则多次遍历会互相干扰。',
      'next 内部忘记检查 hasNext 会返回错误值而不是抛异常。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '让 Range 支持反向遍历，新增一个 descending() 方法返回 Iterable。',
        hint: '返回 lambda 形式的 Iterable，内部 current 从 end-1 递减。',
        answer: 'for (int v : range.descending()) 依次输出 4、3、2，说明 Iterable 可自定义方向。',
      ),
    ],
  ),
  JavaTopic(
    id: 268,
    level: 'advanced',
    title: 'Java 268：空对象模式',
    summary: '用「空实现」代替 null，让调用方不再到处判空。',
    concepts: <String>['空对象', 'null 安全', '多态', '默认行为'],
    objective: '能用一个默认实现替代返回 null，并说明它不能代替输入校验。',
    explain:
        '返回 null 会迫使每个调用点判空，漏一处就是 NullPointerException。'
        '空对象提供一个行为安全、语义明确的默认实现，调用方可以无条件调用。'
        '但它只隐藏「不存在」，不能掩盖非法输入。',
    code: '''public class Main {
    interface User {
        String name();

        boolean isGuest();
    }

    static final class Member implements User {
        private final String name;

        Member(String name) {
            this.name = name;
        }

        @Override
        public String name() {
            return name;
        }

        @Override
        public boolean isGuest() {
            return false;
        }
    }

    static final class Guest implements User {
        @Override
        public String name() {
            return "guest";
        }

        @Override
        public boolean isGuest() {
            return true;
        }
    }

    static User find(String name) {
        if (name == null || name.isBlank()) {
            return new Guest();
        }
        return new Member(name);
    }

    public static void main(String[] args) {
        User missing = find(null);
        User ada = find("ada");
        System.out.println("missing=" + missing.name());
        System.out.println("missingGuest=" + missing.isGuest());
        System.out.println("ada=" + ada.name());
        System.out.println("adaGuest=" + ada.isGuest());
        StringBuilder builder = new StringBuilder();
        for (String name : new String[] {null, "ada"}) {
            builder.append(find(name).name()).append(";");
        }
        System.out.println("batch=" + builder);
    }
}''',
    output:
        'missing=guest\nmissingGuest=true\nada=ada\nadaGuest=false\nbatch=guest;ada;',
    pitfalls: <String>[
      '空对象不能区分「未登录」和「用户不存在」，必要时仍要返回状态码。',
      '空对象的 isGuest 判断容易在业务分支里被忘记。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 Guest 加上 id() 返回 0，并让 Member 返回真实 id。',
        hint: '在接口上增加 String id()，两个实现分别返回。',
        answer: '调用方无需判空就能拿到 id，guest 得到 0，说明默认行为统一。',
      ),
    ],
  ),
  JavaTopic(
    id: 269,
    level: 'advanced',
    title: 'Java 269：反射驱动的依赖注入',
    summary: '用构造器参数类型递归解析依赖，实现迷你容器。',
    concepts: <String>['依赖注入', '反射', '构造器', '单例作用域'],
    objective: '能写一个按构造器参数递归解析、并缓存实例的迷你 DI 容器。',
    explain:
        '容器维护「类型 -> 实例」的注册表。resolve 时先查注册表，命中就返回；'
        '否则反射拿构造器，按参数类型递归 resolve，创建后存入注册表。'
        '缓存使容器内默认是单例作用域。',
    code: '''import java.lang.reflect.Constructor;
import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    interface Clock {
        String now();
    }

    static final class FixedClock implements Clock {
        @Override
        public String now() {
            return "2026-01-01";
        }
    }

    static final class Report {
        private final Clock clock;

        Report(Clock clock) {
            this.clock = clock;
        }

        String line() {
            return "generated@" + clock.now();
        }
    }

    static final class Container {
        private final Map<Class<?>, Object> instances = new LinkedHashMap<>();

        <T> void register(Class<T> type, T instance) {
            instances.put(type, instance);
        }

        <T> T resolve(Class<T> type) throws Exception {
            Object existing = instances.get(type);
            if (existing != null) {
                return type.cast(existing);
            }
            Constructor<?> constructor = type.getDeclaredConstructors()[0];
            Class<?>[] parameterTypes = constructor.getParameterTypes();
            Object[] arguments = new Object[parameterTypes.length];
            for (int i = 0; i < parameterTypes.length; i++) {
                arguments[i] = resolve(parameterTypes[i]);
            }
            constructor.setAccessible(true);
            T created = type.cast(constructor.newInstance(arguments));
            instances.put(type, created);
            return created;
        }
    }

    public static void main(String[] args) throws Exception {
        Container container = new Container();
        container.register(Clock.class, new FixedClock());
        Report report = container.resolve(Report.class);
        System.out.println("line=" + report.line());
        System.out.println("sameReport=" + (report == container.resolve(Report.class)));
        System.out.println("sameClock=" + (container.resolve(Clock.class) == container.resolve(Clock.class)));
    }
}''',
    output:
        'line=generated@2026-01-01\nsameReport=true\nsameClock=true',
    pitfalls: <String>[
      '参数类型无法解析时会无限递归或抛异常，真实容器需要环依赖检测。',
      'getDeclaredConstructors()[0] 顺序不保证，多构造器时要显式选择或加注解。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增 Logger 依赖并注入 Report，验证容器自动解析两层依赖。',
        hint: '给 Report 构造器加 Logger 参数，并注册一个 Logger 实现。',
        answer: '容器先解析 Logger 再创建 Report，输出中能看到 logger 与 clock 都被注入。',
      ),
    ],
  ),
  JavaTopic(
    id: 270,
    level: 'advanced',
    title: 'Java 270：规格模式',
    summary: '把筛选条件组合成可复用的 Spec 对象。',
    concepts: <String>['规格模式', 'Predicate', 'and/or/not', '组合'],
    objective: '能用默认方法组合多个筛选条件，并解释它比硬编码 if 的优势。',
    explain:
        '规格把「一个业务条件」封装成对象，并提供 and/or/not 组合子。'
        '条件可以在不同查询间复用、命名和测试，避免把多个判断揉成一个'
        '难以阅读的布尔表达式。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static final class Product {
        private final String name;
        private final int price;
        private final boolean inStock;

        Product(String name, int price, boolean inStock) {
            this.name = name;
            this.price = price;
            this.inStock = inStock;
        }

        @Override
        public String toString() {
            return name;
        }
    }

    interface Spec {
        boolean test(Product product);

        default Spec and(Spec other) {
            return product -> test(product) && other.test(product);
        }

        default Spec or(Spec other) {
            return product -> test(product) || other.test(product);
        }

        default Spec not() {
            return product -> !test(product);
        }
    }

    static List<Product> filter(List<Product> products, Spec spec) {
        List<Product> result = new ArrayList<>();
        for (Product product : products) {
            if (spec.test(product)) {
                result.add(product);
            }
        }
        return result;
    }

    public static void main(String[] args) {
        List<Product> products = List.of(
                new Product("keyboard", 200, true),
                new Product("mouse", 80, true),
                new Product("monitor", 1200, false));
        Spec inStock = product -> product.inStock;
        Spec cheap = product -> product.price < 500;
        System.out.println("inStock=" + filter(products, inStock));
        System.out.println("cheapAndInStock=" + filter(products, cheap.and(inStock)));
        System.out.println("notCheap=" + filter(products, cheap.not()));
        System.out.println("cheapOrOutOfStock=" + filter(products, cheap.or(inStock.not())));
    }
}''',
    output:
        'inStock=[keyboard, mouse]\ncheapAndInStock=[keyboard, mouse]\nnotCheap=[monitor]\ncheapOrOutOfStock=[keyboard, mouse, monitor]',
    pitfalls: <String>[
      '条件组合过多时结果难以预测，建议给常用组合命名。',
      'Spec 只描述条件，不应在里面修改商品状态。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '新增名称包含字母 o 的条件，并与 cheap 组合。',
        hint: 'product -> product.name.contains("o")。',
        answer: '与 cheap 组合后只剩 keyboard 与 mouse 中的匹配项，说明组合子可叠加。',
      ),
    ],
  ),
  JavaTopic(
    id: 271,
    level: 'advanced',
    title: 'Java 271：快速排序与分区',
    summary: 'Lomuto 分区把小于基准的元素堆到左侧，再递归两侧。',
    concepts: <String>['快速排序', '分区', '递归', '平均复杂度'],
    objective: '能手写 Lomuto 分区并解释每一步交换后数组的状态。',
    explain:
        '选最后一个元素作基准，用 boundary 指针记录「小于基准区」的右边界。'
        '扫描一遍把小于基准的元素换到左边，最后把基准放到 boundary 位置，'
        '此时基准左边全小、右边全大，再对两侧递归。平均 O(n log n)，'
        '最坏 O(n²)。',
    code: '''import java.util.Arrays;

public class Main {
    static void sort(int[] values, int low, int high) {
        if (low >= high) {
            return;
        }
        int pivot = values[high];
        int boundary = low;
        for (int i = low; i < high; i++) {
            if (values[i] < pivot) {
                swap(values, boundary, i);
                boundary++;
            }
        }
        swap(values, boundary, high);
        System.out.println("partition=" + Arrays.toString(values) + " pivot=" + pivot);
        sort(values, low, boundary - 1);
        sort(values, boundary + 1, high);
    }

    static void swap(int[] values, int left, int right) {
        int temp = values[left];
        values[left] = values[right];
        values[right] = temp;
    }

    public static void main(String[] args) {
        int[] values = {5, 2, 8, 1, 9, 3};
        sort(values, 0, values.length - 1);
        System.out.println("sorted=" + Arrays.toString(values));
    }
}''',
    output:
        'partition=[2, 1, 3, 5, 9, 8] pivot=3\npartition=[1, 2, 3, 5, 9, 8] pivot=1\npartition=[1, 2, 3, 5, 8, 9] pivot=8\nsorted=[1, 2, 3, 5, 8, 9]',
    pitfalls: <String>[
      '边界写成 i <= high 会越界，循环必须只扫到 high 之前。',
      '已排序数组配最后一个元素作基准会退化为 O(n²)。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把输入改成已减序的 {9, 8, 7, 6, 5}，数一数 partition 打了几行。',
        hint: '每次分区后基准都在最右侧。',
        answer: '已增序或减序时每次只切掉一个元素，partition 行数接近 n，体现最坏情况。',
      ),
    ],
  ),
  JavaTopic(
    id: 272,
    level: 'advanced',
    title: 'Java 272：归并排序与合并',
    summary: '二分到底再两两合并，稳定且最坏 O(n log n)。',
    concepts: <String>['归并排序', '分治', '稳定排序', '额外空间'],
    objective: '能写出递归归并并在合并时保持相等元素的原始顺序。',
    explain:
        '归并把数组一分为二递归排序，再把两个有序段合并。合并时用'
        'values[left] <= values[right] 取左段元素，相等时优先左段，'
        '因此排序稳定，代价是需要 O(n) 的缓冲区。',
    code: '''import java.util.Arrays;

public class Main {
    static void mergeSort(int[] values, int[] buffer, int low, int high) {
        if (high - low < 2) {
            return;
        }
        int mid = (low + high) / 2;
        mergeSort(values, buffer, low, mid);
        mergeSort(values, buffer, mid, high);
        merge(values, buffer, low, mid, high);
        System.out.println("merged=" + Arrays.toString(Arrays.copyOfRange(values, low, high)));
    }

    static void merge(int[] values, int[] buffer, int low, int mid, int high) {
        int left = low;
        int right = mid;
        int target = low;
        while (left < mid && right < high) {
            if (values[left] <= values[right]) {
                buffer[target] = values[left];
                left++;
            } else {
                buffer[target] = values[right];
                right++;
            }
            target++;
        }
        while (left < mid) {
            buffer[target] = values[left];
            left++;
            target++;
        }
        while (right < high) {
            buffer[target] = values[right];
            right++;
            target++;
        }
        for (int i = low; i < high; i++) {
            values[i] = buffer[i];
        }
    }

    public static void main(String[] args) {
        int[] values = {8, 3, 5, 1, 9, 2};
        mergeSort(values, new int[values.length], 0, values.length);
        System.out.println("sorted=" + Arrays.toString(values));
    }
}''',
    output:
        'merged=[3, 5]\nmerged=[3, 5, 8]\nmerged=[2, 9]\nmerged=[1, 2, 9]\nmerged=[1, 2, 3, 5, 8, 9]\nsorted=[1, 2, 3, 5, 8, 9]',
    pitfalls: <String>[
      '合并后必须把缓冲区写回原数组，否则上层看到的是旧数据。',
      '把 <= 改成 < 会让相等元素逆序，稳定性丢失。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把合并条件改成 values[left] < values[right]，追踪相等元素的相对顺序。',
        hint: '用 {3, 1, 3, 2} 这样带重复值的数组观察。',
        answer: '相等时右段先出，两个 3 的相对次序可能被交换，稳定性被破坏。',
      ),
    ],
  ),
  JavaTopic(
    id: 273,
    level: 'advanced',
    title: 'Java 273：堆与 Top-K',
    summary: '用大小为 k 的小顶堆在线筛选最大的 k 个元素。',
    concepts: <String>['优先队列', '小顶堆', 'Top-K', 'Comparator'],
    objective: '能用 PriorityQueue 以 O(n log k) 求 Top-K，并理解为什么不用大顶堆。',
    explain:
        '小顶堆的堆顶是当前 k 个候选中最小者。每来一个元素就入堆，'
        '超过 k 就把堆顶（当前最小的）弹出，最终堆里就是最大的 k 个。'
        '排序全量数据是 O(n log n)，这里只需要 O(n log k)。',
    code: '''import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.PriorityQueue;

public class Main {
    static List<Integer> topK(int[] values, int k) {
        PriorityQueue<Integer> heap = new PriorityQueue<>();
        for (int value : values) {
            heap.add(value);
            if (heap.size() > k) {
                heap.poll();
            }
        }
        List<Integer> result = new ArrayList<>(heap);
        Collections.sort(result);
        return result;
    }

    public static void main(String[] args) {
        int[] values = {7, 3, 9, 1, 9, 5, 8};
        System.out.println("top3=" + topK(values, 3));
        PriorityQueue<Integer> minHeap = new PriorityQueue<>();
        for (int value : new int[] {4, 1, 6}) {
            minHeap.add(value);
        }
        System.out.println("peekMin=" + minHeap.peek());
        PriorityQueue<Integer> maxHeap = new PriorityQueue<>(Comparator.reverseOrder());
        for (int value : new int[] {4, 1, 6}) {
            maxHeap.add(value);
        }
        System.out.println("peekMax=" + maxHeap.peek());
        System.out.println("pollOrder=" + maxHeap.poll() + "," + maxHeap.poll() + "," + maxHeap.poll());
    }
}''',
    output:
        'top3=[8, 9, 9]\npeekMin=1\npeekMax=6\npollOrder=6,4,1',
    pitfalls: <String>[
      'PriorityQueue 的遍历顺序不等于排序顺序，打印前要先排序。',
      '求最大的 k 个要维护小顶堆，堆类型弄反会得到最小的 k 个。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把条件改成 heap.peek() < value 再 add，解释它与现有写法的差异。',
        hint: '现有写法总是先入堆再挤出。',
        answer: '先比较再入堆可以少做一次删除，结果相同，但代码多一个分支。',
      ),
    ],
  ),
  JavaTopic(
    id: 274,
    level: 'advanced',
    title: 'Java 274：二分查找的上下界',
    summary: 'lowerBound 找第一个不小于 x 的位置，upperBound 找第一个大于 x 的位置。',
    concepts: <String>['二分查找', '下界', '上界', '插入位置'],
    objective: '能写出无死循环的上下界二分，并用差值计算重复元素个数。',
    explain:
        '两个函数结构相同，只是比较符不同：< 得到下界，<= 得到上界。'
        '循环不变量是答案落在 [low, high] 内，每次把区间减半，'
        '结束时 low 就是第一个满足条件的位置，可用于插入点与计数。',
    code: '''public class Main {
    static int lowerBound(int[] values, int target) {
        int low = 0;
        int high = values.length;
        while (low < high) {
            int mid = (low + high) / 2;
            if (values[mid] < target) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return low;
    }

    static int upperBound(int[] values, int target) {
        int low = 0;
        int high = values.length;
        while (low < high) {
            int mid = (low + high) / 2;
            if (values[mid] <= target) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return low;
    }

    public static void main(String[] args) {
        int[] values = {1, 2, 2, 2, 5, 9};
        for (int target : new int[] {2, 3, 1, 9, 10}) {
            int lower = lowerBound(values, target);
            int upper = upperBound(values, target);
            System.out.println("target=" + target + " lower=" + lower + " upper=" + upper + " count=" + (upper - lower));
        }
    }
}''',
    output:
        'target=2 lower=1 upper=4 count=3\ntarget=3 lower=4 upper=4 count=0\ntarget=1 lower=0 upper=1 count=1\ntarget=9 lower=5 upper=6 count=1\ntarget=10 lower=6 upper=6 count=0',
    pitfalls: <String>[
      'high 取 length-1 且用 low <= high 会写出另一个版本，混用容易死循环。',
      '(low + high) / 2 在超大数组下可能溢出，应改用 low + (high - low) / 2。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 lowerBound 写一个插入方法，把 target 插入到保持有序的位置。',
        hint: '先算下界，再用 System.arraycopy 搬移后插入。',
        answer: '插入 4 到 {1,2,2,2,5,9} 得到 {1,2,2,2,4,5,9}，位置为 4。',
      ),
    ],
  ),
  JavaTopic(
    id: 275,
    level: 'advanced',
    title: 'Java 275：链表反转与快慢指针',
    summary: '三指针反转链表，快慢指针求中点与判环。',
    concepts: <String>['链表', '反转', '快慢指针', '环检测'],
    objective: '能手写原地反转，并用快慢指针在 O(1) 空间内求中点、判环。',
    explain:
        '反转需要三个指针：previous、current、next，每步把 current.next 指向'
        'previous 再整体后移。快慢指针中快指针每次走两步，快指针到达末尾时'
        '慢指针正好在中点；若快慢相遇则说明有环。',
    code: '''public class Main {
    static final class Node {
        final int value;
        Node next;

        Node(int value, Node next) {
            this.value = value;
            this.next = next;
        }
    }

    static Node build(int... values) {
        Node head = null;
        for (int i = values.length - 1; i >= 0; i--) {
            head = new Node(values[i], head);
        }
        return head;
    }

    static String format(Node head) {
        StringBuilder builder = new StringBuilder();
        for (Node node = head; node != null; node = node.next) {
            if (builder.length() > 0) {
                builder.append("->");
            }
            builder.append(node.value);
        }
        return builder.toString();
    }

    static Node reverse(Node head) {
        Node previous = null;
        Node current = head;
        while (current != null) {
            Node next = current.next;
            current.next = previous;
            previous = current;
            current = next;
        }
        return previous;
    }

    static int middle(Node head) {
        Node slow = head;
        Node fast = head;
        while (fast.next != null && fast.next.next != null) {
            slow = slow.next;
            fast = fast.next.next;
        }
        return slow.value;
    }

    static boolean hasCycle(Node head) {
        Node slow = head;
        Node fast = head;
        while (fast != null && fast.next != null) {
            slow = slow.next;
            fast = fast.next.next;
            if (slow == fast) {
                return true;
            }
        }
        return false;
    }

    public static void main(String[] args) {
        Node list = build(1, 2, 3, 4, 5);
        System.out.println("list=" + format(list));
        System.out.println("middleOf5=" + middle(list));
        System.out.println("middleOf4=" + middle(build(1, 2, 3, 4)));
        System.out.println("reversed=" + format(reverse(list)));
        System.out.println("cycleBefore=" + hasCycle(build(1, 2, 3)));
        Node cyclic = build(1, 2, 3);
        Node last = cyclic;
        while (last.next != null) {
            last = last.next;
        }
        last.next = cyclic.next;
        System.out.println("cycleAfter=" + hasCycle(cyclic));
    }
}''',
    output:
        'list=1->2->3->4->5\nmiddleOf5=3\nmiddleOf4=2\nreversed=5->4->3->2->1\ncycleBefore=false\ncycleAfter=true',
    pitfalls: <String>[
      '反转时先改 next 会丢失后续节点，必须先保存 next。',
      '判环循环条件必须同时检查 fast 和 fast.next，否则会空指针。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用快慢指针找到环的入口结点值（提示：相遇后一指针回到头部）。',
        hint: '相遇后让 slow 回到 head，两边每次各走一步，再次相遇即入口。',
        answer: '示例中环入口是值 2 的结点，证明环入口可用常数空间求出。',
      ),
    ],
  ),
  JavaTopic(
    id: 276,
    level: 'advanced',
    title: 'Java 276：LRU 缓存实现',
    summary: 'LinkedHashMap 的访问顺序模式能直接构造 LRU。',
    concepts: <String>['LRU', 'LinkedHashMap', 'removeEldestEntry', '访问顺序'],
    objective: '能用 accessOrder 与 removeEldestEntry 实现容量受限的 LRU 缓存。',
    explain:
        'LinkedHashMap 构造器第三个参数 accessOrder=true 时，每次 get/put'
        '都会把该键移到双向链表尾部，头部就是最久未使用。'
        'removeEldestEntry 在插入后回调，返回 true 就删除头部，于是自动淘汰。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    static final class LruCache<K, V> extends LinkedHashMap<K, V> {
        private final int capacity;

        LruCache(int capacity) {
            super(16, 0.75f, true);
            this.capacity = capacity;
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
            return size() > capacity;
        }
    }

    public static void main(String[] args) {
        LruCache<String, Integer> cache = new LruCache<>(2);
        cache.put("a", 1);
        cache.put("b", 2);
        cache.get("a");
        cache.put("c", 3);
        System.out.println("containsA=" + cache.containsKey("a"));
        System.out.println("containsB=" + cache.containsKey("b"));
        System.out.println("order=" + cache.keySet());
        System.out.println("accessA=" + cache.get("a"));
        cache.put("d", 4);
        System.out.println("afterEvict=" + cache.keySet());
    }
}''',
    output:
        'containsA=true\ncontainsB=false\norder=[a, c]\naccessA=1\nafterEvict=[a, d]',
    pitfalls: <String>[
      'accessOrder 为 false 时是插入顺序，get 不会影响淘汰顺序。',
      'LinkedHashMap 不是线程安全的，并发场景要额外加锁。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把容量改成 3，重新推导每一步的淘汰结果。',
        hint: '容量 3 时先放 a、b、c，get a 后最久未使用的是 b。',
        answer: 'put d 后淘汰 b，访问顺序变为 [c, a, d]，containsB 变成 false。',
      ),    ],
  ),
  JavaTopic(
    id: 277,
    level: 'advanced',
    title: 'Java 277：并查集',
    summary: '路径压缩 + 按大小合并，近似 O(1) 地判定连通性。',
    concepts: <String>['并查集', '路径压缩', '按大小合并', '连通分量'],
    objective: '能实现 find/union 并说明两种优化各自带来的收益。',
    explain:
        'find 沿父指针找到根；路径压缩在查找后把路径上的结点直接挂到根上。'
        'union 把小树的根挂到大树下，保证树高是对数级。两者结合后'
        '均摊复杂度接近常数，非常适合动态连通性问题。',
    code: '''public class Main {
    static final class UnionFind {
        private final int[] parent;
        private final int[] size;

        UnionFind(int count) {
            parent = new int[count];
            size = new int[count];
            for (int i = 0; i < count; i++) {
                parent[i] = i;
                size[i] = 1;
            }
        }

        int find(int value) {
            int root = value;
            while (parent[root] != root) {
                root = parent[root];
            }
            int current = value;
            while (parent[current] != root) {
                int next = parent[current];
                parent[current] = root;
                current = next;
            }
            return root;
        }

        boolean union(int left, int right) {
            int rootLeft = find(left);
            int rootRight = find(right);
            if (rootLeft == rootRight) {
                return false;
            }
            if (size[rootLeft] < size[rootRight]) {
                int temp = rootLeft;
                rootLeft = rootRight;
                rootRight = temp;
            }
            parent[rootRight] = rootLeft;
            size[rootLeft] += size[rootRight];
            return true;
        }

        int componentSize(int value) {
            return size[find(value)];
        }
    }

    public static void main(String[] args) {
        UnionFind sets = new UnionFind(6);
        System.out.println("union01=" + sets.union(0, 1));
        System.out.println("union12=" + sets.union(1, 2));
        System.out.println("repeat02=" + sets.union(0, 2));
        System.out.println("union34=" + sets.union(3, 4));
        System.out.println("size2=" + sets.componentSize(2));
        System.out.println("size4=" + sets.componentSize(4));
        int roots = 0;
        for (int i = 0; i < 6; i++) {
            if (sets.find(i) == i) {
                roots++;
            }
        }
        System.out.println("components=" + roots);
    }
}''',
    output:
        'union01=true\nunion12=true\nrepeat02=false\nunion34=true\nsize2=3\nsize4=2\ncomponents=3',
    pitfalls: <String>[
      'find 里直接返回 parent[x] 会漏掉路径压缩，链长会持续退化。',
      '按大小合并时比较的是 size 而不是树高，写反了会导致树偏高。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '去掉路径压缩，构造 0-1-2-3-4-5 依次合并的链，数一数 find 的循环次数。',
        hint: '把第二个 while 删除后再观察 parent 结构。',
        answer: '去掉压缩后 find(5) 要向上追 5 次，链长随合并次数线性增长。',
      ),
    ],
  ),
  JavaTopic(
    id: 278,
    level: 'advanced',
    title: 'Java 278：Dijkstra 最短路径',
    summary: '优先队列选最小距离，松弛所有出边。',
    concepts: <String>['Dijkstra', '最短路径', '图', '松弛'],
    objective: '能用优先队列实现 Dijkstra，并解释为什么跳过过期条目。',
    explain:
        '每次从队列取出当前距离最小的顶点，用它松弛邻居。同一顶点可能'
        '被多次加入队列，取出时若距离大于已知最优距离，说明是过期条目，'
        '直接跳过即可。要求边权非负。',
    code: '''import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.PriorityQueue;

public class Main {
    static final class Edge {
        final int to;
        final int weight;

        Edge(int to, int weight) {
            this.to = to;
            this.weight = weight;
        }
    }

    static final class Entry implements Comparable<Entry> {
        final int id;
        final int distance;

        Entry(int id, int distance) {
            this.id = id;
            this.distance = distance;
        }

        @Override
        public int compareTo(Entry other) {
            return Integer.compare(distance, other.distance);
        }
    }

    static int[] shortest(List<List<Edge>> graph, int source) {
        int[] distance = new int[graph.size()];
        Arrays.fill(distance, Integer.MAX_VALUE);
        distance[source] = 0;
        PriorityQueue<Entry> queue = new PriorityQueue<>();
        queue.add(new Entry(source, 0));
        while (!queue.isEmpty()) {
            Entry current = queue.poll();
            if (current.distance > distance[current.id]) {
                continue;
            }
            for (Edge edge : graph.get(current.id)) {
                int candidate = current.distance + edge.weight;
                if (candidate < distance[edge.to]) {
                    distance[edge.to] = candidate;
                    queue.add(new Entry(edge.to, candidate));
                }
            }
        }
        return distance;
    }

    public static void main(String[] args) {
        List<List<Edge>> graph = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            graph.add(new ArrayList<>());
        }
        graph.get(0).add(new Edge(1, 4));
        graph.get(0).add(new Edge(2, 1));
        graph.get(2).add(new Edge(1, 2));
        graph.get(1).add(new Edge(3, 1));
        graph.get(2).add(new Edge(3, 5));
        graph.get(3).add(new Edge(4, 3));
        int[] distance = shortest(graph, 0);
        System.out.println("distances=" + Arrays.toString(distance));
        System.out.println("toFour=" + distance[4]);
    }
}''',
    output: 'distances=[0, 3, 1, 4, 7]\ntoFour=7',
    pitfalls: <String>[
      '不要用 Dijkstra 处理负权边，应改用 Bellman-Ford。',
      '不跳过过期条目仍能得到正确答案，但会多算很多次。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把边 0->2 的权重改成 5，重新计算到 4 的最短距离。',
        hint: '先算到各点的距离再相加。',
        answer: '到 4 变成 4+1+3=8（走 0->1->3->4），说明路径会随权重重排。',
      ),
    ],
  ),
  JavaTopic(
    id: 279,
    level: 'advanced',
    title: 'Java 279：回溯法与剪枝',
    summary: '逐行放皇后、逐位选字符，用合法性检查剪掉无效分支。',
    concepts: <String>['回溯', '剪枝', 'N 皇后', '排列'],
    objective: '能用回溯枚举解空间，并说清「尝试-递归-撤销」三步结构。',
    explain:
        '回溯在每一层枚举一个候选，检查合法性后递归下一层，返回后撤销选择。'
        '合法性检查就是剪枝：一旦同列或同对角线就立即剪掉整个分支，'
        '枚举量从指数级降到可接受范围。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static int solutions(int size) {
        return place(size, 0, new int[size]);
    }

    static int place(int size, int row, int[] columns) {
        if (row == size) {
            return 1;
        }
        int total = 0;
        for (int column = 0; column < size; column++) {
            if (isSafe(columns, row, column)) {
                columns[row] = column;
                total += place(size, row + 1, columns);
            }
        }
        return total;
    }

    static boolean isSafe(int[] columns, int row, int column) {
        for (int previous = 0; previous < row; previous++) {
            if (columns[previous] == column) {
                return false;
            }
            if (Math.abs(columns[previous] - column) == row - previous) {
                return false;
            }
        }
        return true;
    }

    static void permutations(String prefix, String rest, List<String> result) {
        if (rest.isEmpty()) {
            result.add(prefix);
            return;
        }
        for (int i = 0; i < rest.length(); i++) {
            permutations(prefix + rest.charAt(i), rest.substring(0, i) + rest.substring(i + 1), result);
        }
    }

    public static void main(String[] args) {
        for (int size : new int[] {4, 5, 6}) {
            System.out.println(size + " queens=" + solutions(size));
        }
        List<String> result = new ArrayList<>();
        permutations("", "abc", result);
        System.out.println("permutations=" + result);
        System.out.println("count=" + result.size());
    }
}''',
    output:
        '4 queens=2\n5 queens=10\n6 queens=4\npermutations=[abc, acb, bac, bca, cab, cba]\ncount=6',
    pitfalls: <String>[
      '忘记撤销选择会让后续分支读到脏状态。',
      '字符串拼接实现的排列枚举会产生大量临时对象，规模大时要改用数组交换。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '统计 7 皇后解的个数，并观察运行时间的变化趋势。',
        hint: '把 6 改成 7 即可。',
        answer: '7 皇后有 40 个解，说明解的数量并不随规模单调变化。',
      ),
    ],
  ),
  JavaTopic(
    id: 280,
    level: 'advanced',
    title: 'Java 280：编辑距离与最长递增子序列',
    summary: '两个经典 DP：二维表的编辑距离，一维表的 LIS。',
    concepts: <String>['动态规划', '编辑距离', '最长递增子序列', '状态转移'],
    objective: '能写出编辑距离的二维转移方程，并用 O(n²) 求 LIS 长度。',
    explain:
        '编辑距离的 table[i][j] 表示 left 前 i 个字符变成 right 前 j 个字符的'
        '最少操作数：相同则继承表格左上，否则取替换/删除/插入三者最小值加一。'
        'LIS 令 best[i] 为以 i 结尾的最长长度，向前找更小值转移。',
    code: '''import java.util.Arrays;

public class Main {
    static int editDistance(String left, String right) {
        int[][] table = new int[left.length() + 1][right.length() + 1];
        for (int i = 0; i <= left.length(); i++) {
            table[i][0] = i;
        }
        for (int j = 0; j <= right.length(); j++) {
            table[0][j] = j;
        }
        for (int i = 1; i <= left.length(); i++) {
            for (int j = 1; j <= right.length(); j++) {
                if (left.charAt(i - 1) == right.charAt(j - 1)) {
                    table[i][j] = table[i - 1][j - 1];
                } else {
                    int replace = table[i - 1][j - 1] + 1;
                    int delete = table[i - 1][j] + 1;
                    int insert = table[i][j - 1] + 1;
                    table[i][j] = Math.min(replace, Math.min(delete, insert));
                }
            }
        }
        return table[left.length()][right.length()];
    }

    static int longestIncreasing(int[] values) {
        int[] best = new int[values.length];
        Arrays.fill(best, 1);
        int answer = 0;
        for (int i = 0; i < values.length; i++) {
            for (int j = 0; j < i; j++) {
                if (values[j] < values[i] && best[j] + 1 > best[i]) {
                    best[i] = best[j] + 1;
                }
            }
            answer = Math.max(answer, best[i]);
        }
        return answer;
    }

    public static void main(String[] args) {
        System.out.println("kittenToSitting=" + editDistance("kitten", "sitting"));
        System.out.println("same=" + editDistance("java", "java"));
        System.out.println("empty=" + editDistance("", "abc"));
        System.out.println("lis=" + longestIncreasing(new int[] {10, 9, 2, 5, 3, 7, 101, 18}));
        System.out.println("lisShort=" + longestIncreasing(new int[] {3, 4}));
    }
}''',
    output:
        'kittenToSitting=3\nsame=0\nempty=3\nlis=4\nlisShort=2',
    pitfalls: <String>[
      '表格要开 n+1 大小，否则空串边界会越界。',
      '把 values[j] < values[i] 写成 <= 就变成最长非递减子序列。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 table 回溯出 kitten → sitting 的一组合法编辑序列。',
        hint: '从右下角往回走，比较三个候选值来自哪个方向。',
        answer: 'kitten → sitten（替换）→ sittin（替换）→ sitting（插入），共 3 步。',
      ),
    ],
  ),
];
