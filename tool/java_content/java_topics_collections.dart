import 'java_topic.dart';

/// Java topics 101-160: strings, Unicode, collections, streams, Optional and
/// practical algorithms. Authored for the offline Java IDE content expansion;
/// every program is a complete `Main` class whose stdout is captured verbatim
/// from a real JDK 17 run (`javac --release 17`, `java`).
///
/// Kept in a dedicated module so the original 001-100 list stays untouched and
/// the aggregate assembler can concatenate the groups deterministically.
const List<JavaTopic> javaCollectionTopics = <JavaTopic>[
  JavaTopic(
    id: 101,
    level: 'intermediate',
    title: 'Java 101：String 不可变与字符串驻留',
    summary: '理解 String 的不可变语义，以及字面量驻留与 new 的差别。',
    concepts: <String>['String 不可变', '字符串驻留', 'intern', '== 与 equals'],
    objective: '能解释 String 方法为何总是返回新对象，并判断两个引用是否指向同一实例。',
    explain:
        'String 一旦创建就不能修改，toUpperCase、concat 等都会返回新对象，原对象保持不变。'
        '字符串字面量会被常量池驻留，相同字面量共享同一实例；new String 一定创建新对象，intern 后才可能复用池中的实例。'
        '因此比较内容要用 equals，只有比较身份时才用 ==。',
    code: '''public class Main {
    public static void main(String[] args) {
        String original = "hello";
        String upper = original.toUpperCase();
        System.out.println("original=" + original);
        System.out.println("upper=" + upper);
        String literal = "java";
        String created = new String("java");
        System.out.println("literalEqCreated=" + (literal == created));
        System.out.println("equals=" + literal.equals(created));
        System.out.println("internEq=" + (created.intern() == literal));
        String folded = "ja" + "va";
        System.out.println("foldedEq=" + (folded == literal));
        String joined = "ja" + "v".concat("a");
        System.out.println("joinedEq=" + (joined == literal));
    }
}''',
    output: 'original=hello\nupper=HELLO\nliteralEqCreated=false\nequals=true\ninternEq=true\nfoldedEq=true\njoinedEq=false',
    pitfalls: <String>['用 == 比较字符串内容，结果依赖是否驻留。', '在循环里用 + 拼接大量字符串，会不断产生临时对象。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '让 joined 与 literal 指向同一实例并输出 true。', hint: '对拼接结果调用 intern() 再比较。', answer: 'System.out.println(joined.intern() == literal);'),
    ],
  ),
  JavaTopic(
    id: 102,
    level: 'beginner',
    title: 'Java 102：字符串比较与排序规则',
    summary: 'compareTo 的返回值含义，以及大小写无关排序。',
    concepts: <String>['compareTo', '自然排序', 'CASE_INSENSITIVE_ORDER', 'equalsIgnoreCase'],
    objective: '能用 compareTo 判断字典序，并为字符串列表选择正确的排序器。',
    explain:
        'compareTo 按字符的 Unicode 码点逐位比较，返回首个不同字符的差值；全部相同时返回长度差。'
        '自然排序区分大小写，大写字母码点更小，所以 Banana 会排在 apple 前面。'
        '需要忽略大小写时用 String.CASE_INSENSITIVE_ORDER，需要本地化排序时用 Collator。',
    code: '''import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<String> words = new ArrayList<>(List.of("pear", "apple", "Banana"));
        words.sort(Comparator.naturalOrder());
        System.out.println("natural=" + words);
        words.sort(String.CASE_INSENSITIVE_ORDER);
        System.out.println("ignoreCase=" + words);
        words.sort(Comparator.comparingInt(String::length));
        System.out.println("byLength=" + words);
        System.out.println("compare=" + "apple".compareTo("banana"));
        System.out.println("equalsIgnoreCase=" + "Java".equalsIgnoreCase("JAVA"));
    }
}''',
    output: 'natural=[Banana, apple, pear]\nignoreCase=[apple, Banana, pear]\nbyLength=[pear, apple, Banana]\ncompare=-1\nequalsIgnoreCase=true',
    pitfalls: <String>['以为 compareTo 只会返回 -1、0、1，实际可能是任意字符差值。', '把自然排序当成字母表顺序，忽略了大写字母码点更小。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '按长度降序排列 words，长度相同时按字母序。', hint: '用 Comparator.comparingInt 配合 reversed 和 thenComparing。', answer: 'words.sort(Comparator.comparingInt(String::length).reversed().thenComparing(Comparator.naturalOrder()));'),
    ],
  ),
  JavaTopic(
    id: 103,
    level: 'intermediate',
    title: 'Java 103：char 与 Unicode 码点',
    summary: '为什么一个 emoji 的 length() 是 2，以及如何正确统计字符数。',
    concepts: <String>['UTF-16', '代理对', 'codePointCount', 'charAt'],
    objective: '能区分 char 单元与码点，正确统计含 emoji 的字符串长度。',
    explain:
        'Java 的 String 内部是 UTF-16 编码，char 只能表示基本多文种平面内的码点。'
        '超出 U+FFFF 的字符（例如 emoji）要用一对代理 char 表示，所以 length 返回 2。'
        '统计真实字符数要用 codePointCount，读取完整字符用 codePointAt。',
    code: '''public class Main {
    public static void main(String[] args) {
        String emoji = "😀";
        String mixed = "Java😀";
        System.out.println("emojiLength=" + emoji.length());
        System.out.println("mixedLength=" + mixed.length());
        System.out.println("codePoints=" + mixed.codePointCount(0, mixed.length()));
        System.out.println("charAt4=" + (int) mixed.charAt(4));
        System.out.println("codePointAt4=" + mixed.codePointAt(4));
        System.out.println("highSurrogate=" + Character.isHighSurrogate(mixed.charAt(4)));
        System.out.println("lowSurrogate=" + Character.isLowSurrogate(mixed.charAt(5)));
    }
}''',
    output: 'emojiLength=2\nmixedLength=6\ncodePoints=5\ncharAt4=55357\ncodePointAt4=128512\nhighSurrogate=true\nlowSurrogate=true',
    pitfalls: <String>['用 length() 判断用户可见字符数，遇到 emoji 会翻倍。', '用 charAt 直接处理代理对，会得到半个字符。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '统计 mixed 中真实字符的个数并输出。', hint: '用 codePointCount(0, mixed.length())。', answer: 'System.out.println(mixed.codePointCount(0, mixed.length()));'),
    ],
  ),
  JavaTopic(
    id: 104,
    level: 'intermediate',
    title: 'Java 104：按码点遍历与反转',
    summary: '用 codePoints 流安全处理代理对，避免把 emoji 劈成两半。',
    concepts: <String>['codePoints', 'Character.toChars', 'Stream', '代理对'],
    objective: '能按码点遍历字符串，并构造不破坏代理对的反转结果。',
    explain:
        'codePoints() 把字符串展开为 int 码点流，适合过滤、统计和转换。'
        '把码点还原成字符串用 Character.toChars 再交给 new String。'
        '按 char 下标截取可能落在代理对中间，得到的是非法字符串。',
    code: '''import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

public class Main {
    public static void main(String[] args) {
        String text = "a中😀";
        List<String> hex = text.codePoints()
            .mapToObj(cp -> "U+" + Integer.toHexString(cp).toUpperCase())
            .collect(Collectors.toList());
        System.out.println(hex);
        List<String> units = new ArrayList<>();
        text.codePoints().forEach(cp -> units.add(new String(Character.toChars(cp))));
        StringBuilder reversed = new StringBuilder();
        for (int i = units.size() - 1; i >= 0; i--) {
            reversed.append(units.get(i));
        }
        System.out.println("reversed=" + reversed);
        String broken = text.substring(0, 3);
        System.out.println("brokenLength=" + broken.length());
        System.out.println("brokenCodePoints=" + broken.codePointCount(0, broken.length()));
        System.out.println("danglingHigh=" + Character.isHighSurrogate(broken.charAt(2)));
    }
}''',
    output: '[U+61, U+4E2D, U+1F600]\nreversed=😀中a\nbrokenLength=3\nbrokenCodePoints=3\ndanglingHigh=true',
    pitfalls: <String>['substring 的下标是 char 单元而不是字符个数。', '按长度截断含代理对的字符串，可能留下半个字符。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 text 中所有码点大于 U+FFFF 的字符过滤出来并打印。', hint: '用 codePoints().filter(cp -> cp > 0xFFFF)。', answer: 'text.codePoints().filter(cp -> cp > 0xFFFF).forEach(cp -> System.out.println(cp));'),
    ],
  ),
  JavaTopic(
    id: 105,
    level: 'advanced',
    title: 'Java 105：Unicode 规范化与等价比较',
    summary: '同一个字形两种码点序列，为什么 equals 会返回 false。',
    concepts: <String>['Normalizer', 'NFC', 'NFD', '组合字符'],
    objective: '能识别规范化形式不同导致的比较失败，并用 Normalizer 修复。',
    explain:
        '同一个字形可能有组合式与分解式两种码点序列：é 可以是一个码点，也可以是 e 加组合重音。'
        'equals 逐码点比较，所以两者不相等，length 也不相同。'
        '比较前统一用 Normalizer.normalize 转成 NFC 或 NFD，再做 equals。',
    code: '''import java.text.Normalizer;

public class Main {
    public static void main(String[] args) {
        String composed = "café";
        String decomposed = "cafe" + (char) 0x0301;
        System.out.println("equals=" + composed.equals(decomposed));
        String nfc = Normalizer.normalize(decomposed, Normalizer.Form.NFC);
        System.out.println("nfcEquals=" + composed.equals(nfc));
        System.out.println("composedLength=" + composed.length());
        System.out.println("decomposedLength=" + decomposed.length());
        String nfd = Normalizer.normalize(composed, Normalizer.Form.NFD);
        System.out.println("nfdLength=" + nfd.length());
        System.out.println("nfdEquals=" + nfd.equals(decomposed));
    }
}''',
    output: 'equals=false\nnfcEquals=true\ncomposedLength=4\ndecomposedLength=5\nnfdLength=5\nnfdEquals=true',
    pitfalls: <String>['以为肉眼看起来相同就一定 equals。', '只规范化比较的一方，两边形式仍然不同。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '写一个方法，判断两个字符串在 NFD 形式下是否相等。', hint: '两边都调用 Normalizer.normalize(s, Normalizer.Form.NFD)。', answer: 'static boolean same(String a, String b) { return Normalizer.normalize(a, Normalizer.Form.NFD).equals(Normalizer.normalize(b, Normalizer.Form.NFD)); }'),
    ],
  ),
  JavaTopic(
    id: 106,
    level: 'advanced',
    title: 'Java 106：大小写转换与 Locale',
    summary: '土耳其语 i 问题：为什么 toUpperCase 会得到带点的 İ。',
    concepts: <String>['Locale', 'toUpperCase', 'toLowerCase', 'Locale.ROOT'],
    objective: '能解释区域敏感的大小写规则，并在协议与存储场景固定用 Locale.ROOT。',
    explain:
        '土耳其语中 i 的大写是 İ，I 的小写是 ı，与英语规则不同。'
        '无参的 toUpperCase 使用默认 Locale，结果会随设备区域设置变化。'
        '协议字段、文件名、关键字比较应显式传 Locale.ROOT，保证跨区域稳定。',
    code: '''import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        Locale turkish = Locale.forLanguageTag("tr");
        System.out.println("root=" + "istanbul".toUpperCase(Locale.ROOT));
        System.out.println("turkish=" + "istanbul".toUpperCase(turkish));
        System.out.println("turkishLower=" + "I".toLowerCase(turkish));
        System.out.println("rootLower=" + "I".toLowerCase(Locale.ROOT));
        System.out.println("turkishDotless=" + "ı".toUpperCase(turkish));
    }
}''',
    output: 'root=ISTANBUL\nturkish=İSTANBUL\nturkishLower=ı\nrootLower=i\nturkishDotless=I',
    pitfalls: <String>['用默认 Locale 做大小写转换后再比较，换区域就出错。', '用 equalsIgnoreCase 处理土耳其语 i，结果不符合当地规则。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把协议关键字统一转成大写，写出不受区域影响的表达式。', hint: '显式传入 Locale.ROOT。', answer: 'String key = raw.toUpperCase(Locale.ROOT);'),
    ],
  ),
  JavaTopic(
    id: 107,
    level: 'beginner',
    title: 'Java 107：String.format 格式化输出',
    summary: '宽度、补零、进制与千分位：一次掌握常用格式说明符。',
    concepts: <String>['String.format', '格式说明符', '宽度与对齐', 'Locale.ROOT'],
    objective: '能用格式串控制小数位、对齐、补零和数字分组。',
    explain:
        '格式串以百分号开始，依次是标志、宽度、精度和转换符，例如 %05.1f 表示补零到 5 位并保留 1 位小数。'
        '负号表示左对齐，逗号开启千分位分组。'
        '格式化数字时显式传 Locale.ROOT，避免不同区域的小数点与分组符差异。',
    code: '''import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        System.out.println("[" + String.format(Locale.ROOT, "%05.1f", 3.14159) + "]");
        System.out.println("[" + String.format(Locale.ROOT, "%-6s|", "ab") + "]");
        System.out.println("[" + String.format(Locale.ROOT, "%6s|", "ab") + "]");
        System.out.println(String.format(Locale.ROOT, "%x-%X", 255, 255));
        System.out.println(String.format(Locale.ROOT, "%,d", 1234567));
        System.out.println(String.format(Locale.ROOT, "%s=%d", "id", 7));
        System.out.println(String.format(Locale.ROOT, "%.3f", 2.0));
    }
}''',
    output: '[003.1]\n[ab    |]\n[    ab|]\nff-FF\n1,234,567\nid=7\n2.000',
    pitfalls: <String>['用 %d 格式化小数会抛 IllegalFormatConversionException。', '忽略 Locale，导致小数点在某些区域变成逗号。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 42 输出成宽度 5、右侧补零的字符串。', hint: '格式串用 %05d。', answer: 'System.out.println(String.format(Locale.ROOT, "%05d", 42));'),
    ],
  ),
  JavaTopic(
    id: 108,
    level: 'beginner',
    title: 'Java 108：strip、isBlank 与 repeat',
    summary: 'Java 11 起的空白处理与字符串复制新 API。',
    concepts: <String>['strip', 'isBlank', 'repeat', 'lines'],
    objective: '能用 strip 系列方法正确处理 Unicode 空白，并拆分多行文本。',
    explain:
        'strip 按 Character.isWhitespace 去掉首尾空白，能处理全角空格等 Unicode 空白；'
        'trim 只处理小于等于 U+0020 的字符。'
        'isBlank 判断字符串是否只含空白，空串也算空白。'
        'repeat 复制字符串，lines 按行拆分并去掉行终止符。',
    code: '''public class Main {
    public static void main(String[] args) {
        String padded = "  hi  ";
        System.out.println("[" + padded.strip() + "]");
        System.out.println("[" + padded.stripTrailing() + "]");
        System.out.println("blank=" + "   ".isBlank());
        System.out.println("emptyBlank=" + "".isBlank());
        System.out.println("repeat=" + "ab".repeat(3));
        String twoLines = "a" + (char) 10 + "b";
        System.out.println("lines=" + twoLines.lines().count());
        System.out.println("emptyLines=" + "".lines().count());
    }
}''',
    output: '[hi]\n[  hi]\nblank=true\nemptyBlank=true\nrepeat=ababab\nlines=2\nemptyLines=0',
    pitfalls: <String>['继续用 trim 处理含全角空格的输入，首尾空白去不掉。', '对 null 调用 strip 会抛 NullPointerException。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '判断用户输入去掉空白后是否为空。', hint: '先 strip 再 isEmpty。', answer: 'boolean empty = input == null || input.strip().isEmpty();'),
    ],
  ),
  JavaTopic(
    id: 109,
    level: 'beginner',
    title: 'Java 109：split 与 join 的边界行为',
    summary: '末尾空串被丢弃、limit 参数与 StringJoiner 的用法。',
    concepts: <String>['split', 'limit', 'String.join', 'StringJoiner'],
    objective: '能预测 split 在不同 limit 下的结果，并选择合适的分隔输出方式。',
    explain:
        'split 默认会丢弃末尾的空串，传负数 limit 则全部保留，传正数最多切出 limit 段。'
        'String.join 适合简单拼接，StringJoiner 可以额外加前缀和后缀。'
        '分隔符是正则表达式，含元字符时要转义或用 Pattern.quote。',
    code: '''import java.util.Arrays;
import java.util.List;
import java.util.StringJoiner;

public class Main {
    public static void main(String[] args) {
        String csv = "a,b,,c";
        System.out.println(Arrays.toString(csv.split(",")));
        System.out.println(Arrays.toString(csv.split(",", -1)));
        System.out.println(Arrays.toString(csv.split(",", 2)));
        System.out.println(String.join("|", "x", "y", "z"));
        StringJoiner joiner = new StringJoiner(",", "[", "]");
        joiner.add("1").add("2");
        System.out.println(joiner);
        List<String> parts = List.of(csv.split(","));
        System.out.println("size=" + parts.size());
    }
}''',
    output: '[a, b, , c]\n[a, b, , c]\n[a, b,,c]\nx|y|z\n[1,2]\nsize=4',
    pitfalls: <String>['以为 split 会保留所有空段，实际末尾空串默认被丢弃。', '把点号或竖线当普通字符做分隔符，被当成正则元字符。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 a,b,,c 完整切成 4 段，包括中间的空串。', hint: '使用负数 limit。', answer: 'String[] parts = csv.split(",", -1);'),
    ],
  ),
  JavaTopic(
    id: 110,
    level: 'intermediate',
    title: 'Java 110：replace 与正则替换',
    summary: '字面量替换和正则替换的区别，以及元字符陷阱。',
    concepts: <String>['replace', 'replaceAll', 'replaceFirst', '正则元字符'],
    objective: '能区分字面量与正则替换，避免把点号当成普通字符。',
    explain:
        'replace 按字面量替换，replaceAll 和 replaceFirst 按正则匹配。'
        '点号在正则里表示任意字符，所以 replaceAll 用点号会把每个字符都替换掉。'
        '替换串中的美元符号和反斜杠有特殊含义，普通文本替换优先用 replace。',
    code: '''public class Main {
    public static void main(String[] args) {
        String raw = "a1b22c333";
        System.out.println("digits=" + raw.replaceAll("[0-9]", "#"));
        System.out.println("first=" + raw.replaceFirst("[0-9]+", "#"));
        System.out.println("literal=" + raw.replace("22", "-"));
        System.out.println("literalDot=" + "a.b".replace(".", "*"));
        System.out.println("regexDot=" + "a.b".replaceAll(".", "*"));
        System.out.println("same=" + "a.b".replaceAll("[.]", "*"));
    }
}''',
    output: 'digits=a#b##c###\nfirst=a#b22c333\nliteral=a1b-c333\nliteralDot=a*b\nregexDot=***\nsame=a*b',
    pitfalls: <String>['想替换一个点却用了 replaceAll，结果整串都被替换。', '在替换串里写美元符号引用分组，却以为它是普通字符。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 raw 中所有连续数字替换成一个井号。', hint: '正则用 [0-9]+。', answer: 'String masked = raw.replaceAll("[0-9]+", "#");'),
    ],
  ),
  JavaTopic(
    id: 111,
    level: 'beginner',
    title: 'Java 111：双指针判断回文串',
    summary: '用左右指针忽略非字母数字字符，判断字符串是否回文。',
    concepts: <String>['双指针', '回文', 'Character.isLetterOrDigit', 'toLowerCase'],
    objective: '能写出 O(n) 时间、O(1) 空间的回文判断，并忽略标点与大小写。',
    explain:
        '回文判断从两端向中间比较，相同就收缩一步，不同立即返回 false。'
        '遇到标点或空格时跳过该侧下标，遇到大写时统一转小写再比较。'
        '指针法比先反转再比较更省内存，也不需要构造新字符串。',
    code: '''public class Main {
    static boolean isPalindrome(String text) {
        int left = 0;
        int right = text.length() - 1;
        while (left < right) {
            char a = text.charAt(left);
            char b = text.charAt(right);
            if (!Character.isLetterOrDigit(a)) {
                left++;
            } else if (!Character.isLetterOrDigit(b)) {
                right--;
            } else if (Character.toLowerCase(a) != Character.toLowerCase(b)) {
                return false;
            } else {
                left++;
                right--;
            }
        }
        return true;
    }

    public static void main(String[] args) {
        System.out.println("plain=" + isPalindrome("noon"));
        System.out.println("sentence=" + isPalindrome("A man, a plan, a canal: Panama"));
        System.out.println("negative=" + isPalindrome("java"));
        System.out.println("single=" + isPalindrome("x"));
        System.out.println("empty=" + isPalindrome(""));
    }
}''',
    output: 'plain=true\nsentence=true\nnegative=false\nsingle=true\nempty=true',
    pitfalls: <String>['没跳过非字母数字字符，带标点的句子会被误判。', '先反转整个字符串再比较，额外占用一份内存。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '修改方法，使其只判断数字串是否为回文。', hint: '把 isLetterOrDigit 换成 isDigit。', answer: 'if (!Character.isDigit(a)) { left++; }'),
    ],
  ),
  JavaTopic(
    id: 112,
    level: 'intermediate',
    title: 'Java 112：Pattern 与 Matcher 分组提取',
    summary: '用捕获组从 key=value 文本中抽取结构化数据。',
    concepts: <String>['Pattern', 'Matcher', '捕获组', 'find'],
    objective: '能编译一次正则并循环 find，取出每个匹配的分组内容。',
    explain:
        'Pattern.compile 把正则编译成可复用的对象，Matcher.find 逐个定位匹配片段。'
        '括号是捕获组，group(1)、group(2) 取对应括号的内容，group(0) 是整段匹配。'
        '命名分组 group(name) 让代码更可读，适合字段较多的场景。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        Pattern pattern = Pattern.compile("([a-z]+)=([0-9]+)");
        String text = "port=8080 host=localhost retries=3";
        Map<String, Integer> values = new LinkedHashMap<>();
        Matcher matcher = pattern.matcher(text);
        while (matcher.find()) {
            values.put(matcher.group(1), Integer.parseInt(matcher.group(2)));
        }
        System.out.println(values);
        System.out.println("port=" + values.get("port"));
        System.out.println("count=" + values.size());
        Matcher single = pattern.matcher("env=prod port=9090");
        boolean found = single.find();
        System.out.println("found=" + found + " group0=" + (found ? single.group(0) : "none"));
        System.out.println("skippedHost=" + text.contains("host=localhost"));
    }
}''',
    output: '{port=8080, retries=3}\nport=8080\ncount=2\nfound=true group0=port=9090\nskippedHost=true',
    pitfalls: <String>['在循环里反复调用 group(0) 却忘了先调用 find。', '在同一个表达式里先调用 find 再调用 group，若 find 返回 false 会直接抛异常。', '正则只匹配数字值，像 host=localhost 这样的键值对会被静默跳过。', '在循环内重复 compile 正则，浪费性能。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用命名分组改写正则，取出 host 的值。', hint: '写成 ([a-z]+) 对应的 (?<key>[a-z]+)，用 group("key") 取值。', answer: 'Pattern.compile("(?<key>[a-z]+)=(?<value>[0-9]+)")'),
    ],
  ),
  JavaTopic(
    id: 113,
    level: 'advanced',
    title: 'Java 113：正则命名分组解析日志行',
    summary: '用命名分组把一行日志拆成级别、时间和消息三部分。',
    concepts: <String>['命名分组', 'group(name)', 'matches', '可选分组'],
    objective: '能用一条正则解析固定格式日志，并对不匹配的行给出明确提示。',
    explain:
        '命名分组写成 (?<name>模式)，取值时用 matcher.group("name")，比数字下标更不容易错位。'
        'matches 要求整串匹配，find 只要求存在子串匹配。'
        '先判断 matches 为 false 再提示格式错误，避免直接取分组抛异常。',
    code: '''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    static final Pattern LINE = Pattern.compile("(?<level>[A-Z]+) (?<time>[0-9]{2}:[0-9]{2}) (?<msg>.+)");

    static String parse(String line) {
        Matcher matcher = LINE.matcher(line);
        if (!matcher.matches()) {
            return "invalid: " + line;
        }
        return matcher.group("level") + "/" + matcher.group("time") + "/" + matcher.group("msg");
    }

    public static void main(String[] args) {
        System.out.println(parse("INFO 09:30 service started"));
        System.out.println(parse("ERROR 10:01 disk full"));
        System.out.println(parse("debug 10:02 short level"));
        System.out.println(parse("INFO 9:03 bad time"));
        System.out.println("groups=" + LINE.matcher("WARN 11:59 slow").groupCount());
    }
}''',
    output: 'INFO/09:30/service started\nERROR/10:01/disk full\ninvalid: debug 10:02 short level\ninvalid: INFO 9:03 bad time\ngroups=3',
    pitfalls: <String>['用 find 代替 matches，导致只匹配到一部分也算成功。', '正则不含固定锚点却期望整串校验，多余字符被忽略。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '让消息部分允许为空。', hint: '把消息分组从 .+ 改成 .*。', answer: 'Pattern.compile("(?<level>[A-Z]+) (?<time>[0-9]{2}:[0-9]{2}) (?<msg>.*)")'),
    ],
  ),
  JavaTopic(
    id: 114,
    level: 'advanced',
    title: 'Java 114：KMP 子串查找',
    summary: '用前缀函数把子串查找从 O(n*m) 降到 O(n+m)。',
    concepts: <String>['KMP', '前缀函数', '失配回退', '线性时间'],
    objective: '能手写前缀函数数组，并解释为什么失配时不需要回退主串指针。',
    explain:
        '暴力匹配失配后要从主串的下一位重新开始，最坏情况退化到 O(n*m)。'
        'KMP 预处理模式串的前缀函数，记录每个位置的最长相等前后缀长度。'
        '失配时按前缀函数回退模式指针，主串指针只前进不后退，因此总时间线性。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static int[] prefixFunction(String pattern) {
        int[] table = new int[pattern.length()];
        int matched = 0;
        for (int i = 1; i < pattern.length(); i++) {
            while (matched > 0 && pattern.charAt(i) != pattern.charAt(matched)) {
                matched = table[matched - 1];
            }
            if (pattern.charAt(i) == pattern.charAt(matched)) {
                matched++;
            }
            table[i] = matched;
        }
        return table;
    }

    static List<Integer> search(String text, String pattern) {
        List<Integer> hits = new ArrayList<>();
        int[] table = prefixFunction(pattern);
        int matched = 0;
        for (int i = 0; i < text.length(); i++) {
            while (matched > 0 && text.charAt(i) != pattern.charAt(matched)) {
                matched = table[matched - 1];
            }
            if (text.charAt(i) == pattern.charAt(matched)) {
                matched++;
            }
            if (matched == pattern.length()) {
                hits.add(i - pattern.length() + 1);
                matched = table[matched - 1];
            }
        }
        return hits;
    }

    public static void main(String[] args) {
        System.out.println(java.util.Arrays.toString(prefixFunction("ababaca")));
        System.out.println(search("ababababaca", "ababaca"));
        System.out.println(search("aaaaa", "aa"));
        System.out.println(search("abc", "z"));
    }
}''',
    output: '[0, 0, 1, 2, 3, 0, 1]\n[4]\n[0, 1, 2, 3]\n[]',
    pitfalls: <String>['前缀函数用 table[matched] 回退，正确写法是 table[matched - 1]。', '找到一次匹配后忘记继续回退，漏掉相互重叠的匹配。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '返回第一次出现的下标，不存在时返回 -1。', hint: '命中后立即 return i - pattern.length() + 1。', answer: 'if (matched == pattern.length()) { return i - pattern.length() + 1; }'),
    ],
  ),
  JavaTopic(
    id: 115,
    level: 'advanced',
    title: 'Java 115：编辑距离（Levenshtein）',
    summary: '用动态规划计算两个单词之间的最少编辑次数。',
    concepts: <String>['动态规划', '编辑距离', '插入删除替换', '二维表'],
    objective: '能写出编辑距离的转移方程，并用滚动数组把空间降到 O(n)。',
    explain:
        '编辑距离允许插入、删除、替换三种操作，每种代价都是 1。'
        'dp[i][j] 表示把前 i 个字符变成前 j 个字符的最小代价，字符相同则继承左上角，否则取三种操作的最小值加一。'
        '只依赖上一行，所以用一维数组滚动更新即可，注意先保存左上角旧值。',
    code: '''public class Main {
    static int distance(String source, String target) {
        int[] previous = new int[target.length() + 1];
        for (int j = 0; j <= target.length(); j++) {
            previous[j] = j;
        }
        for (int i = 1; i <= source.length(); i++) {
            int[] current = new int[target.length() + 1];
            current[0] = i;
            for (int j = 1; j <= target.length(); j++) {
                if (source.charAt(i - 1) == target.charAt(j - 1)) {
                    current[j] = previous[j - 1];
                } else {
                    int insert = current[j - 1];
                    int delete = previous[j];
                    int replace = previous[j - 1];
                    current[j] = Math.min(insert, Math.min(delete, replace)) + 1;
                }
            }
            previous = current;
        }
        return previous[target.length()];
    }

    public static void main(String[] args) {
        System.out.println("kitten->sitting=" + distance("kitten", "sitting"));
        System.out.println("same=" + distance("java", "java"));
        System.out.println("empty=" + distance("", "abc"));
        System.out.println("swap=" + distance("ab", "ba"));
        System.out.println("caseOnly=" + distance("Java", "java"));
    }
}''',
    output: 'kitten->sitting=3\nsame=0\nempty=3\nswap=2\ncaseOnly=1',
    pitfalls: <String>['把插入和删除的转移写反，结果仍然对称但单步过程错误。', '滚动数组里没先保存左上角旧值，替换分支用到被覆盖的数据。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把插入和删除的代价改成 2，替换仍为 1。', hint: '调整转移中的加数即可。', answer: 'current[j] = Math.min(insert + 2, Math.min(delete + 2, replace + 1));'),
    ],
  ),
  JavaTopic(
    id: 116,
    level: 'advanced',
    title: 'Java 116：最长公共子序列',
    summary: '用二维动态规划求两个字符串的最长公共子序列长度并还原内容。',
    concepts: <String>['LCS', '动态规划', '回溯还原', '子序列'],
    objective: '能计算 LCS 长度，并从 DP 表回溯出具体的公共子序列。',
    explain:
        '子序列不要求连续，所以两个串末尾字符相同时直接加一，不同时取上边和左边的较大值。'
        '长度填表完成后，从右下角回溯：字符相同就收集并斜向移动，否则朝数值更大的方向移动。'
        '回溯得到的字符是逆序的，需要反转一次。',
    code: '''public class Main {
    static int[][] buildTable(String a, String b) {
        int[][] dp = new int[a.length() + 1][b.length() + 1];
        for (int i = 1; i <= a.length(); i++) {
            for (int j = 1; j <= b.length(); j++) {
                if (a.charAt(i - 1) == b.charAt(j - 1)) {
                    dp[i][j] = dp[i - 1][j - 1] + 1;
                } else {
                    dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
                }
            }
        }
        return dp;
    }

    static String lcs(String a, String b) {
        int[][] dp = buildTable(a, b);
        StringBuilder sb = new StringBuilder();
        int i = a.length();
        int j = b.length();
        while (i > 0 && j > 0) {
            if (a.charAt(i - 1) == b.charAt(j - 1)) {
                sb.append(a.charAt(i - 1));
                i--;
                j--;
            } else if (dp[i - 1][j] >= dp[i][j - 1]) {
                i--;
            } else {
                j--;
            }
        }
        return sb.reverse().toString();
    }

    public static void main(String[] args) {
        System.out.println("length=" + buildTable("AGGTAB", "GXTXAYB")[6][7]);
        System.out.println("lcs=" + lcs("AGGTAB", "GXTXAYB"));
        System.out.println("none=" + lcs("abc", "xyz"));
        System.out.println("self=" + lcs("java", "java"));
    }
}''',
    output: 'length=4\nlcs=GTAB\nnone=\nself=java',
    pitfalls: <String>['把子序列当成子串，误以为字符必须连续。', '回溯时两个方向数值相等却随意移动，可能漏掉更靠前的字符。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '求 a 与反转后的 a 的 LCS 长度，说明它代表什么。', hint: '那是字符串的最长回文子序列长度。', answer: 'int best = buildTable(a, new StringBuilder(a).reverse().toString())[a.length()][a.length()];'),
    ],
  ),
  JavaTopic(
    id: 117,
    level: 'advanced',
    title: 'Java 117：最长回文子串（中心扩展）',
    summary: '以每个位置为中心向两侧扩展，一次扫描解决最长回文子串。',
    concepts: <String>['中心扩展', '回文子串', '奇偶长度', '时间复杂度'],
    objective: '能处理奇偶两种中心，写出 O(n^2) 时间、O(1) 空间的实现。',
    explain:
        '回文串的中心有两种：单个字符（奇数长度）和两个字符之间（偶数长度）。'
        '对每个中心向两侧扩展，只要字符相等就继续，记录最长区间。'
        '共有 2n-1 个中心，每个中心最多扩展 O(n)，总体 O(n^2) 且不需要额外空间。',
    code: '''public class Main {
    static String longest(String text) {
        int bestStart = 0;
        int bestLength = 0;
        for (int center = 0; center < text.length(); center++) {
            int odd = expand(text, center, center);
            int even = expand(text, center, center + 1);
            int length = Math.max(odd, even);
            if (length > bestLength) {
                bestLength = length;
                bestStart = center - (length - 1) / 2;
            }
        }
        return text.substring(bestStart, bestStart + bestLength);
    }

    static int expand(String text, int left, int right) {
        while (left >= 0 && right < text.length() && text.charAt(left) == text.charAt(right)) {
            left--;
            right++;
        }
        return right - left - 1;
    }

    public static void main(String[] args) {
        System.out.println("babad=" + longest("babad"));
        System.out.println("cbbd=" + longest("cbbd"));
        System.out.println("aba=" + longest("aba"));
        System.out.println("single=" + longest("x"));
    }
}''',
    output: 'babad=bab\ncbbd=bb\naba=aba\nsingle=x',
    pitfalls: <String>['只扩展奇数中心，会漏掉 abba 这类偶数长度回文。', '起点公式写成 center - length / 2，偶数长度会偏一位。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '改为返回最长回文子串的长度。', hint: '把返回类型改成 int，直接返回 bestLength。', answer: 'static int longestLength(String text) { return longest(text).length(); }'),
    ],
  ),
  JavaTopic(
    id: 118,
    level: 'advanced',
    title: 'Java 118：Rabin-Karp 滚动哈希查找',
    summary: '用滚动哈希在 O(n) 期望时间内找出所有匹配位置。',
    concepts: <String>['滚动哈希', 'Rabin-Karp', '取模', '冲突校验'],
    objective: '能实现滚动哈希窗口更新，并说明为什么命中后仍要逐个字符校验。',
    explain:
        '把窗口内的字符当作多项式计算哈希，窗口右移时去掉最高位、加上新字符，单步 O(1)。'
        '哈希相同只说明可能是匹配，仍要逐字符比较排除冲突。'
        '取模值过小会让冲突变多，实际实现常用 long 配合大质数。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static final long BASE = 131;
    static final long MOD = 1000000007L;

    static List<Integer> search(String text, String pattern) {
        List<Integer> hits = new ArrayList<>();
        int m = pattern.length();
        if (m == 0 || m > text.length()) {
            return hits;
        }
        long target = 0;
        long window = 0;
        long highest = 1;
        for (int i = 0; i < m; i++) {
            target = (target * BASE + pattern.charAt(i)) % MOD;
            window = (window * BASE + text.charAt(i)) % MOD;
            if (i < m - 1) {
                highest = highest * BASE % MOD;
            }
        }
        for (int start = 0; start + m <= text.length(); start++) {
            if (window == target && text.regionMatches(start, pattern, 0, m)) {
                hits.add(start);
            }
            if (start + m < text.length()) {
                long out = text.charAt(start) * highest % MOD;
                window = ((window - out + MOD) % MOD * BASE + text.charAt(start + m)) % MOD;
            }
        }
        return hits;
    }

    public static void main(String[] args) {
        System.out.println(search("abracadabra", "abra"));
        System.out.println(search("aaaa", "aa"));
        System.out.println(search("abc", "d"));
        System.out.println(search("abc", "abcd"));
    }
}''',
    output: '[0, 7]\n[0, 1, 2]\n[]\n[]',
    pitfalls: <String>['哈希命中后不校验字符，取模冲突会带来误报。', '减法后忘记加 MOD 再取模，Java 的负数取模会得到负值。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 BASE 改成 31，观察匹配位置是否变化。', hint: '哈希变化不影响正确结果，因为命中后仍做字符校验。', answer: 'static final long BASE = 31;'),
    ],
  ),
  JavaTopic(
    id: 119,
    level: 'intermediate',
    title: 'Java 119：变位词分组',
    summary: '排序字符作为键，把字母相同顺序不同的单词归到一组。',
    concepts: <String>['HashMap', '排序键', 'groupingBy', '变位词'],
    objective: '能为复合条件选出稳定键，把同组元素聚合到同一个列表中。',
    explain:
        '变位词排序后完全相同，所以排序后的字符串是天然的分组键。'
        '用 LinkedHashMap 可以让分组顺序跟随首次出现的顺序；用 TreeMap 则按键排序输出。'
        '用字符计数数组拼成键可以进一步把每个单词的代价降到 O(n)。',
    code: '''import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    static String keyOf(String word) {
        char[] letters = word.toCharArray();
        Arrays.sort(letters);
        return new String(letters);
    }

    public static void main(String[] args) {
        List<String> words = List.of("eat", "tea", "tan", "ate", "nat", "bat");
        Map<String, List<String>> grouped = new LinkedHashMap<>();
        for (String word : words) {
            grouped.computeIfAbsent(keyOf(word), key -> new ArrayList<>()).add(word);
        }
        System.out.println("groups=" + grouped);
        System.out.println("keys=" + new TreeMap<>(grouped).keySet());
        System.out.println("count=" + grouped.size());
        System.out.println("oneGroup=" + grouped.get("aet"));
    }
}''',
    output: 'groups={aet=[eat, tea, ate], ant=[tan, nat], abt=[bat]}\nkeys=[abt, aet, ant]\ncount=3\noneGroup=[eat, tea, ate]',
    pitfalls: <String>['直接把单词本身当键，变位词无法聚在一起。', '用 HashMap 后依赖遍历顺序输出，结果不稳定。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用字符计数生成键，避免每个单词都排序。', hint: '统计 26 个字母的出现次数并拼成字符串。', answer: 'int[] count = new int[26]; for (char c : word.toCharArray()) { count[c - 97]++; }'),
    ],
  ),
  JavaTopic(
    id: 120,
    level: 'beginner',
    title: 'Java 120：LinkedHashSet 去重保序',
    summary: '去重的同时保留首次出现顺序，替代手写判重循环。',
    concepts: <String>['LinkedHashSet', '去重', '插入顺序', 'add 返回值'],
    objective: '能用集合完成稳定去重，并根据 add 返回值判断是否为重复项。',
    explain:
        'Set 不允许重复元素，HashSet 不保证顺序，LinkedHashSet 额外维护一条插入顺序链表。'
        'add 返回 false 表示元素已存在，可以据此统计重复项而不必再查一次。'
        '需要按字典序输出时用 TreeSet，需要保留插入顺序时用 LinkedHashSet。',
    code: '''import java.util.LinkedHashSet;
import java.util.Set;
import java.util.TreeSet;

public class Main {
    public static void main(String[] args) {
        String[] visits = {"home", "search", "home", "detail", "search", "home"};
        Set<String> ordered = new LinkedHashSet<>();
        int repeats = 0;
        for (String page : visits) {
            if (!ordered.add(page)) {
                repeats++;
            }
        }
        System.out.println("ordered=" + ordered);
        System.out.println("repeats=" + repeats);
        System.out.println("size=" + ordered.size());
        System.out.println("sorted=" + new TreeSet<>(ordered));
        System.out.println("duplicateAdd=" + ordered.add("home"));
    }
}''',
    output: 'ordered=[home, search, detail]\nrepeats=3\nsize=3\nsorted=[detail, home, search]\nduplicateAdd=false',
    pitfalls: <String>['用 HashSet 去重后直接打印，顺序不确定。', '先 contains 再 add，两次哈希查找多于一次 add 的返回值判断。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '输出按照首次出现顺序排列的前三个页面。', hint: '把 Set 转成 List 后调用 subList。', answer: 'System.out.println(new java.util.ArrayList<>(ordered).subList(0, 3));'),
    ],
  ),
  JavaTopic(
    id: 121,
    level: 'intermediate',
    title: 'Java 121：subList 是视图而不是拷贝',
    summary: '修改子列表会影响原列表，结构修改还会让子列表失效。',
    concepts: <String>['subList', '视图', '结构修改', 'ConcurrentModificationException'],
    objective: '能说明 subList 的视图语义，并在需要独立数据时显式拷贝。',
    explain:
        'subList 返回的是原列表的一段视图，set 会同步写回原列表。'
        '子列表的结构性修改（增删）也会作用到原列表上。'
        '原列表在子列表创建后被结构性修改，子列表会抛 ConcurrentModificationException。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<String> all = new ArrayList<>(List.of("a", "b", "c", "d", "e"));
        List<String> middle = all.subList(1, 4);
        System.out.println("view=" + middle);
        middle.set(0, "B");
        System.out.println("afterSet=" + all);
        middle.remove("d");
        System.out.println("afterRemove=" + all);
        List<String> copy = new ArrayList<>(all.subList(0, 2));
        all.add("f");
        System.out.println("copy=" + copy);
        System.out.println("copySize=" + copy.size());
    }
}''',
    output: 'view=[b, c, d]\nafterSet=[a, B, c, d, e]\nafterRemove=[a, B, c, e]\ncopy=[a, B]\ncopySize=2',
    pitfalls: <String>['把 subList 结果当独立副本保存，后续原列表变化会一并生效。', '原列表增删之后继续使用旧子列表，直接抛并发修改异常。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '安全地取出中间两段并保证与后续原列表变化无关。', hint: '用 new ArrayList<>(list.subList(a, b))。', answer: 'List<String> part = new ArrayList<>(all.subList(1, 3));'),
    ],
  ),
  JavaTopic(
    id: 122,
    level: 'intermediate',
    title: 'Java 122：用 Deque 接口使用 LinkedList',
    summary: 'LinkedList 的正确用法是当作双端队列，而不是随机访问列表。',
    concepts: <String>['LinkedList', 'Deque', 'ArrayDeque', 'offer/poll'],
    objective: '能按复杂度选择实现：随机访问用 ArrayList，两端进出用 Deque。',
    explain:
        'LinkedList 每次按下标访问都要从头或尾遍历，get(i) 是 O(n)。'
        '它实现了 Deque，offerFirst、pollLast 都是 O(1)，适合队列和栈。'
        '纯队列场景优先用 ArrayDeque，它没有节点对象开销，常数更小。',
    code: '''import java.util.ArrayDeque;
import java.util.Deque;
import java.util.LinkedList;

public class Main {
    public static void main(String[] args) {
        Deque<String> queue = new LinkedList<>();
        queue.offerLast("first");
        queue.offerLast("second");
        queue.offerFirst("zero");
        System.out.println("queue=" + queue);
        System.out.println("head=" + queue.peekFirst());
        System.out.println("polled=" + queue.pollFirst());
        System.out.println("remaining=" + queue);
        Deque<Integer> stack = new ArrayDeque<>();
        stack.push(1);
        stack.push(2);
        stack.push(3);
        System.out.println("stack=" + stack);
        System.out.println("popped=" + stack.pop());
        System.out.println("size=" + stack.size());
    }
}''',
    output: 'queue=[zero, first, second]\nhead=zero\npolled=zero\nremaining=[first, second]\nstack=[3, 2, 1]\npopped=3\nsize=2',
    pitfalls: <String>['用 LinkedList 做大量 get(i) 遍历，时间复杂度退化为 O(n^2)。', '混用 add/remove 与 offer/poll，异常语义不同容易出错。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用 Deque 实现先进先出的广度优先队列，写出入队与出队语句。', hint: '入队 offerLast，出队 pollFirst。', answer: 'queue.offerLast(node); Node next = queue.pollFirst();'),
    ],
  ),
  JavaTopic(
    id: 123,
    level: 'beginner',
    title: 'Java 123：Arrays.asList 与 List.of 的限制',
    summary: '定长列表可以改元素但不能增删，不可变列表连改都不行。',
    concepts: <String>['Arrays.asList', 'List.of', '不可变', 'UnsupportedOperationException'],
    objective: '能判断哪种列表支持增删改，并在需要可变列表时正确包装。',
    explain:
        'Arrays.asList 返回定长列表，set 可以修改元素，add 和 remove 会抛 UnsupportedOperationException。'
        'List.of 返回真正不可变列表，任何修改都抛异常，且不接受 null。'
        '需要可变列表时用 new ArrayList<>(Arrays.asList(...)) 做一次拷贝。',
    code: '''import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<String> fixed = Arrays.asList("a", "b", "c");
        fixed.set(0, "A");
        System.out.println("fixed=" + fixed);
        List<String> immutable = List.of("x", "y");
        System.out.println("immutable=" + immutable);
        List<String> mutable = new ArrayList<>(fixed);
        mutable.add("d");
        System.out.println("mutable=" + mutable);
        try {
            immutable.add("z");
        } catch (UnsupportedOperationException e) {
            System.out.println("immutableAddRejected=" + (e.getCause() == null));
        }
        try {
            fixed.add("d");
        } catch (UnsupportedOperationException e) {
            System.out.println("fixedAddRejected=true");
        }
    }
}''',
    output: 'fixed=[A, b, c]\nimmutable=[x, y]\nmutable=[A, b, c, d]\nimmutableAddRejected=true\nfixedAddRejected=true',
    pitfalls: <String>['把 Arrays.asList 的结果当成可增删列表，运行时抛异常。', '对基本类型数组用 asList，得到的是一元素列表而不是 5 个整数。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 int 数组转成可变的 Integer 列表。', hint: '用 Arrays.stream(arr).boxed() 再收集。', answer: 'List<Integer> list = Arrays.stream(arr).boxed().collect(java.util.stream.Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 124,
    level: 'beginner',
    title: 'Java 124：Collections 工具类常用方法',
    summary: '排序、反转、交换、最值与二分查找的标准写法。',
    concepts: <String>['Collections.sort', 'Collections.binarySearch', 'Collections.reverse', 'max'],
    objective: '能用工具类完成常规集合操作，并理解二分查找要求有序。',
    explain:
        'Collections.sort 直接对传入列表原地排序，List.sort 是等价写法。'
        'binarySearch 只有在对列表预先排序后结果才有意义，找不到时返回负数插入点。'
        'reverse、swap、max、min 都是原地或只读操作，使用简单但没有额外优化。',
    code: '''import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> numbers = new ArrayList<>(List.of(5, 3, 9, 1, 7));
        Collections.sort(numbers);
        System.out.println("sorted=" + numbers);
        System.out.println("indexOf7=" + Collections.binarySearch(numbers, 7));
        System.out.println("missing4=" + Collections.binarySearch(numbers, 4));
        Collections.swap(numbers, 0, 4);
        System.out.println("swapped=" + numbers);
        Collections.reverse(numbers);
        System.out.println("reversed=" + numbers);
        System.out.println("max=" + Collections.max(numbers));
        System.out.println("min=" + Collections.min(numbers));
    }
}''',
    output: 'sorted=[1, 3, 5, 7, 9]\nindexOf7=3\nmissing4=-3\nswapped=[9, 3, 5, 7, 1]\nreversed=[1, 7, 5, 3, 9]\nmax=9\nmin=1',
    pitfalls: <String>['对未排序的列表调用 binarySearch，得到的下标没有意义。', '误以为 binarySearch 找不到时返回 -1，实际返回负数插入点。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '对列表做降序排序并保持原列表类型。', hint: '用 Collections.sort(numbers, Comparator.reverseOrder())。', answer: 'Collections.sort(numbers, java.util.Comparator.reverseOrder());'),
    ],
  ),
  JavaTopic(
    id: 125,
    level: 'intermediate',
    title: 'Java 125：用 List.copyOf 做防御性拷贝',
    summary: '构造器保存外部列表时先拷贝，避免调用方后续修改影响对象状态。',
    concepts: <String>['List.copyOf', '防御性拷贝', '不可变', '封装'],
    objective: '能在构造器里用 copyOf 固化参数，保证对象内部状态不被外部篡改。',
    explain:
        '直接把外部列表引用存成字段，调用方后续 add 会改变对象内部状态。'
        'List.copyOf 会拷贝到一个不可变列表，之后任何外部修改都影响不到对象。'
        'copyOf 不接受 null 元素，遇到含 null 的列表会直接抛 NullPointerException。',
    code: '''import java.util.ArrayList;
import java.util.List;

public class Main {
    static final class Playlist {
        private final String name;
        private final List<String> songs;

        Playlist(String name, List<String> songs) {
            this.name = name;
            this.songs = List.copyOf(songs);
        }

        List<String> songs() {
            return songs;
        }

        String describe() {
            return name + ":" + songs.size() + ":" + songs;
        }
    }

    public static void main(String[] args) {
        List<String> source = new ArrayList<>(List.of("intro", "verse"));
        Playlist playlist = new Playlist("mix", source);
        source.add("outro");
        System.out.println("source=" + source);
        System.out.println("playlist=" + playlist.describe());
        try {
            playlist.songs().add("extra");
        } catch (UnsupportedOperationException e) {
            System.out.println("playlistIsImmutable=true");
        }
    }
}''',
    output: 'source=[intro, verse, outro]\nplaylist=mix:2:[intro, verse]\nplaylistIsImmutable=true',
    pitfalls: <String>['直接把参数引用赋给字段，外部仍能修改对象内部集合。', '在 getter 里直接返回内部列表，封装被破坏。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '让 songs() 返回的列表可以被调用方排序而不会影响播放列表。', hint: '返回 new ArrayList<>(songs)。', answer: 'return new ArrayList<>(songs);'),
    ],
  ),
  JavaTopic(
    id: 126,
    level: 'intermediate',
    title: 'Java 126：EnumMap 按枚举索引',
    summary: '用枚举做键的专用 Map，遍历顺序与枚举声明顺序一致且更快。',
    concepts: <String>['EnumMap', '枚举', '索引数组', '稳定顺序'],
    objective: '能用 EnumMap 做计数与分组，并解释它为什么顺序稳定、性能更好。',
    explain:
        'EnumMap 内部用数组按枚举 ordinal 索引，查找和写入没有哈希计算开销。'
        '遍历顺序固定为枚举声明顺序，输出天然稳定。'
        '键类型是枚举时优先用 EnumMap，而不是 HashMap。',
    code: '''import java.util.EnumMap;
import java.util.Map;

public class Main {
    enum Level {
        LOW, MEDIUM, HIGH
    }

    public static void main(String[] args) {
        Level[] samples = {Level.HIGH, Level.LOW, Level.HIGH, Level.MEDIUM, Level.HIGH};
        Map<Level, Integer> counts = new EnumMap<>(Level.class);
        for (Level level : samples) {
            counts.merge(level, 1, Integer::sum);
        }
        System.out.println(counts);
        System.out.println("high=" + counts.get(Level.HIGH));
        System.out.println("low=" + counts.getOrDefault(Level.LOW, 0));
        System.out.println("keys=" + counts.keySet());
        System.out.println("hasMedium=" + counts.containsKey(Level.MEDIUM));
    }
}''',
    output: '{LOW=1, MEDIUM=1, HIGH=3}\nhigh=3\nlow=1\nkeys=[LOW, MEDIUM, HIGH]\nhasMedium=true',
    pitfalls: <String>['用 HashMap 存枚举计数，打印顺序与枚举声明顺序无关。', 'EnumMap 构造时忘记传枚举 Class，编译不过。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 counts 换成一个新的 EnumMap，只保留计数大于 1 的等级。', hint: '遍历 entrySet 后按条件 put。', answer: 'Map<Level, Integer> heavy = new EnumMap<>(Level.class); counts.forEach((k, v) -> { if (v > 1) { heavy.put(k, v); } });'),
    ],
  ),
  JavaTopic(
    id: 127,
    level: 'advanced',
    title: 'Java 127：LinkedHashMap 实现 LRU 缓存',
    summary: '开启 accessOrder 并重写 removeEldestEntry，几十行实现 LRU。',
    concepts: <String>['LinkedHashMap', 'accessOrder', 'removeEldestEntry', 'LRU'],
    objective: '能利用访问顺序链表实现固定容量的最近最少使用缓存淘汰。',
    explain:
        'LinkedHashMap 的构造参数 accessOrder 为 true 时，每次 get 都会把该键移到链表尾部。'
        '重写 removeEldestEntry，返回 size() 大于容量即可自动淘汰链表头部的元素。'
        '这样写入和访问的均摊代价都是 O(1)，不需要自己维护双向链表。'
        '子类继承可序列化集合时声明 serialVersionUID，避免可选警告并固定序列化版本。',
    code: '''import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    static final class LruCache extends LinkedHashMap<String, Integer> {
        private static final long serialVersionUID = 1L;
        private final int capacity;

        LruCache(int capacity) {
            super(capacity, 0.75f, true);
            this.capacity = capacity;
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<String, Integer> eldest) {
            return size() > capacity;
        }
    }

    public static void main(String[] args) {
        LruCache cache = new LruCache(3);
        cache.put("a", 1);
        cache.put("b", 2);
        cache.put("c", 3);
        System.out.println("filled=" + cache);
        System.out.println("hit=" + cache.get("a"));
        System.out.println("afterHit=" + cache);
        cache.put("d", 4);
        System.out.println("afterPut=" + cache);
        System.out.println("evictedB=" + (cache.get("b") == null));
        System.out.println("size=" + cache.size());
    }
}''',
    output: 'filled={a=1, b=2, c=3}\nhit=1\nafterHit={b=2, c=3, a=1}\nafterPut={c=3, a=1, d=4}\nevictedB=true\nsize=3',
    pitfalls: <String>['构造器 accessOrder 传 false，get 不会把元素移到尾部，淘汰顺序变成插入顺序。', '容量判断写成大于等于，缓存实际容量会少一个。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把容量改成 2，预测第三次 put 之后缓存内容。', hint: '先写满 a、b，再 put c 会淘汰最久未使用的键。', answer: 'LruCache cache = new LruCache(2);'),
    ],
  ),
  JavaTopic(
    id: 128,
    level: 'advanced',
    title: 'Java 128：TreeMap 区间查询',
    summary: '用 headMap、tailMap、subMap 快速切出有序区间与最近邻。',
    concepts: <String>['TreeMap', 'subMap', 'headMap', 'firstEntry'],
    objective: '能利用红黑树的有序性做区间统计和上下界查找。',
    explain:
        'TreeMap 按键的排序顺序组织，subMap 返回指定区间视图，不再逐个过滤。'
        'headMap 取左开右闭区间，tailMap 取右开区间，Boolean 参数控制边界是否包含。'
        'floorEntry 和 ceilingEntry 可以直接取上下界，适合时间窗口类查询。',
    code: '''import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        TreeMap<Integer, String> events = new TreeMap<>();
        events.put(10, "login");
        events.put(25, "view");
        events.put(40, "edit");
        events.put(55, "logout");
        System.out.println("all=" + events);
        System.out.println("upto40=" + events.headMap(40, true));
        System.out.println("from40=" + events.tailMap(40, false));
        System.out.println("window=" + events.subMap(20, true, 50, true));
        System.out.println("floor30=" + events.floorEntry(30).getValue());
        System.out.println("ceiling30=" + events.ceilingEntry(30).getValue());
        System.out.println("first=" + events.firstEntry());
        Map<Integer, String> window = events.subMap(20, true, 50, true);
        System.out.println("windowSize=" + window.size());
    }
}''',
    output: 'all={10=login, 25=view, 40=edit, 55=logout}\nupto40={10=login, 25=view, 40=edit}\nfrom40={55=logout}\nwindow={25=view, 40=edit}\nfloor30=view\nceiling30=edit\nfirst=10=login\nwindowSize=2',
    pitfalls: <String>['忘了 TreeMap 的 key 必须可比较，否则抛 ClassCastException。', 'subMap 的边界默认是左闭右开，不加 Boolean 参数会漏掉右端点。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '统计 20 到 50 之间（含端点）的事件数量。', hint: '用 subMap(20, true, 50, true).size()。', answer: 'System.out.println(events.subMap(20, true, 50, true).size());'),
    ],
  ),
  JavaTopic(
    id: 129,
    level: 'intermediate',
    title: 'Java 129：PriorityQueue 求 Top-K',
    summary: '用小顶堆维护容量为 K 的集合，一次扫描得到最大的 K 个元素。',
    concepts: <String>['PriorityQueue', '堆', 'Top-K', 'Comparator'],
    objective: '能用容量为 K 的堆替代全量排序，把复杂度降到 O(n log k)。',
    explain:
        '求最大 K 个数时维护一个小顶堆，堆顶是当前第 K 大。'
        '新元素比堆顶大就替换堆顶，堆大小始终不超过 K。'
        '全部排序是 O(n log n)，堆方法只需 O(n log k)，数据量大时优势明显。',
    code: '''import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.PriorityQueue;

public class Main {
    static List<Integer> topK(int[] values, int k) {
        PriorityQueue<Integer> heap = new PriorityQueue<>();
        for (int value : values) {
            heap.offer(value);
            if (heap.size() > k) {
                heap.poll();
            }
        }
        List<Integer> result = new ArrayList<>(heap);
        result.sort(Collections.reverseOrder());
        return result;
    }

    public static void main(String[] args) {
        int[] scores = {88, 95, 70, 99, 62, 91};
        System.out.println("top3=" + topK(scores, 3));
        System.out.println("top1=" + topK(scores, 1));
        System.out.println("topAll=" + topK(scores, scores.length));
        System.out.println("topZero=" + topK(scores, 0));
    }
}''',
    output: 'top3=[99, 95, 91]\ntop1=[99]\ntopAll=[99, 95, 91, 88, 70, 62]\ntopZero=[]',
    pitfalls: <String>['求最大 K 个却用大顶堆，堆顶无法判断谁该被淘汰。', 'K 为 0 时不加保护，poll 空堆返回 null 之后装箱会出错。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '改为求最小的 3 个数。', hint: '把堆改成大顶堆，Comparator.reverseOrder()。', answer: 'PriorityQueue<Integer> heap = new PriorityQueue<>(Collections.reverseOrder());'),
    ],
  ),
  JavaTopic(
    id: 130,
    level: 'beginner',
    title: 'Java 130：用 ArrayDeque 做括号匹配',
    summary: '栈结构检查括号是否成对出现，并指出第一个出错位置。',
    concepts: <String>['ArrayDeque', '栈', '括号匹配', 'peek'],
    objective: '能用双端队列模拟栈，写出带错误位置的括号校验。',
    explain:
        '遇到左括号压栈，遇到右括号检查栈顶是否为对应的左括号。'
        '扫描结束后栈必须为空，否则说明有左括号没有闭合。'
        'ArrayDeque 的 push、pop、peek 都在两端操作，比 Stack 类更现代。',
    code: '''import java.util.ArrayDeque;
import java.util.Deque;

public class Main {
    static String check(String text) {
        Deque<Character> stack = new ArrayDeque<>();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '(' || c == '[') {
                stack.push(c);
            } else if (c == ')' || c == ']') {
                if (stack.isEmpty()) {
                    return "unexpected at " + i;
                }
                char open = stack.pop();
                if ((c == ')' && open != '(') || (c == ']' && open != '[')) {
                    return "mismatch at " + i;
                }
            }
        }
        return stack.isEmpty() ? "ok" : "unclosed " + stack.size();
    }

    public static void main(String[] args) {
        System.out.println(check("(a[b]c)"));
        System.out.println(check("(a[b)"));
        System.out.println(check("a)b("));
        System.out.println(check("((a)"));
        System.out.println(check(""));
    }
}''',
    output: 'ok\nmismatch at 4\nunexpected at 1\nunclosed 1\nok',
    pitfalls: <String>['只统计左右括号数量，忽略嵌套顺序是否合法。', '右括号遇到空栈时直接 pop，抛 NoSuchElementException。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '增加对大括号的支持。', hint: '在左右括号判断里加入花括号分支。', answer: 'if (c == 40 || c == 91 || c == 123) { stack.push(c); }'),
    ],
  ),
  JavaTopic(
    id: 131,
    level: 'advanced',
    title: 'Java 131：单调队列求滑动窗口最大值',
    summary: '用下标双端队列把每个窗口的最大值降到均摊 O(1)。',
    concepts: <String>['单调队列', '滑动窗口', 'ArrayDeque', '均摊复杂度'],
    objective: '能维护一个下标递增、值递减的队列，在线性时间内求出全部窗口最大值。',
    explain:
        '队列里存下标，对应的值从队头到队尾单调递减，队头就是当前窗口最大值。'
        '新元素入队前弹出所有不大于它的队尾元素，保证单调性。'
        '队头下标滑出窗口时把它弹出，整体每个下标最多进出一次，总代价 O(n)。',
    code: '''import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Deque;

public class Main {
    static int[] maxWindow(int[] values, int k) {
        if (k <= 0 || values.length == 0) {
            return new int[0];
        }
        int[] result = new int[values.length - k + 1];
        Deque<Integer> index = new ArrayDeque<>();
        int at = 0;
        for (int i = 0; i < values.length; i++) {
            if (!index.isEmpty() && index.peekFirst() <= i - k) {
                index.pollFirst();
            }
            while (!index.isEmpty() && values[index.peekLast()] <= values[i]) {
                index.pollLast();
            }
            index.offerLast(i);
            if (i >= k - 1) {
                result[at] = values[index.peekFirst()];
                at++;
            }
        }
        return result;
    }

    public static void main(String[] args) {
        int[] values = {1, 3, -1, -3, 5, 3, 6, 7};
        System.out.println(Arrays.toString(maxWindow(values, 3)));
        System.out.println(Arrays.toString(maxWindow(values, 1)));
        System.out.println(Arrays.toString(maxWindow(values, 8)));
        System.out.println(Arrays.toString(maxWindow(values, 0)));
    }
}''',
    output: '[3, 3, 5, 5, 6, 7]\n[1, 3, -1, -3, 5, 3, 6, 7]\n[7]\n[]',
    pitfalls: <String>['弹出队尾时用小于号而不是小于等于，重复最大值会让队列变长。', '先判断窗口输出再清理过期下标，队头可能已经不在窗口内。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '改为求每个窗口的最小值。', hint: '把弹出队尾的比较从小于等于改成大于等于。', answer: 'while (!index.isEmpty() && values[index.peekLast()] >= values[i]) { index.pollLast(); }'),
    ],
  ),
  JavaTopic(
    id: 132,
    level: 'intermediate',
    title: 'Java 132：迭代器删除与并发修改异常',
    summary: '为什么增强 for 里 remove 会抛异常，正确写法是什么。',
    concepts: <String>['Iterator', 'ConcurrentModificationException', 'fail-fast', 'removeIf'],
    objective: '能解释 fail-fast 机制，并用迭代器或 removeIf 安全删除元素。',
    explain:
        'ArrayList 维护一个修改计数器，迭代器每步都校验它是否变化。'
        '增强 for 只是迭代器的语法糖，循环体里直接调用 list.remove 会改变计数器，下一次取值就抛 ConcurrentModificationException。'
        '安全做法是用 iterator.remove，或者直接调用集合的 removeIf。',
    code: '''import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> numbers = new ArrayList<>(List.of(1, 2, 3, 4, 5, 6));
        Iterator<Integer> iterator = numbers.iterator();
        while (iterator.hasNext()) {
            if (iterator.next() % 2 == 0) {
                iterator.remove();
            }
        }
        System.out.println("afterIterator=" + numbers);
        List<Integer> failing = new ArrayList<>(List.of(1, 2, 3));
        try {
            for (Integer value : failing) {
                if (value == 2) {
                    failing.remove(value);
                }
            }
        } catch (java.util.ConcurrentModificationException e) {
            System.out.println("cmeCaught=true");
        }
        System.out.println("afterFailure=" + failing);
        List<Integer> safe = new ArrayList<>(List.of(1, 2, 3));
        safe.removeIf(value -> value == 2);
        System.out.println("removeIf=" + safe);
    }
}''',
    output: 'afterIterator=[1, 3, 5]\nafterFailure=[1, 3]\nremoveIf=[1, 3]',
    pitfalls: <String>['在增强 for 里调用 list.remove，偶数位置之后立刻抛异常。', 'catch 住异常后继续使用同一个迭代器，状态已经不可信。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用一行代码删除列表中所有小于 3 的元素。', hint: '使用 removeIf 配合 Lambda。', answer: 'list.removeIf(value -> value < 3);'),
    ],
  ),
  JavaTopic(
    id: 133,
    level: 'intermediate',
    title: 'Java 133：removeIf、replaceAll 与 compute',
    summary: '集合与映射的默认方法，让批量更新不再需要手写循环。',
    concepts: <String>['removeIf', 'replaceAll', 'computeIfAbsent', 'merge'],
    objective: '能用默认方法完成过滤、批量转换和映射的按键更新。',
    explain:
        'removeIf 接收谓词，内部用迭代器删除，比手写循环更安全。'
        'replaceAll 对每个元素做原地替换，适合统一格式化。'
        'compute、computeIfAbsent、merge 把查找与写入合成一步，并保证原子语义。',
    code: '''import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        List<String> names = new ArrayList<>(List.of("ann", "", "bob", "  "));
        names.removeIf(String::isBlank);
        names.replaceAll(String::toUpperCase);
        System.out.println("names=" + names);
        Map<String, Integer> stock = new HashMap<>();
        stock.put("pen", 2);
        stock.computeIfAbsent("book", key -> 0);
        stock.merge("pen", 3, Integer::sum);
        stock.compute("book", (key, value) -> value + 5);
        System.out.println("stock=" + new TreeMap<>(stock));
        stock.computeIfPresent("pen", (key, value) -> value == 0 ? null : value - 1);
        System.out.println("afterCompute=" + new TreeMap<>(stock));
    }
}''',
    output: 'names=[ANN, BOB]\nstock={book=5, pen=5}\nafterCompute={book=5, pen=4}',
    pitfalls: <String>['在 compute 的回调里修改同一个 Map，会抛 ConcurrentModificationException。', 'computeIfAbsent 返回 null 时不会写入键值对，容易误以为已插入。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '统计单词出现次数，写出 merge 一行。', hint: '计数为 1，冲突时求和。', answer: 'counts.merge(word, 1, Integer::sum);'),
    ],
  ),
  JavaTopic(
    id: 134,
    level: 'intermediate',
    title: 'Java 134：Comparator 多级排序与空值',
    summary: 'thenComparing 组合多个规则，nullsFirst/nullsLast 处理缺失值。',
    concepts: <String>['thenComparing', 'nullsFirst', 'nullsLast', '多级排序'],
    objective: '能组合多级比较规则，并明确 null 排在最前还是最后。',
    explain:
        'Comparator.comparing 生成第一级规则，thenComparing 追加后续规则。'
        '字段可能为 null 时必须用 nullsFirst 或 nullsLast 包装，否则比较时抛 NullPointerException。'
        '比较器链从左到右生效，前一级相等才会比较下一级，最后加姓名可以保证结果唯一稳定。',
    code: '''import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class Main {
    record Employee(String name, String team, Integer score) {}

    public static void main(String[] args) {
        List<Employee> staff = new ArrayList<>(List.of(
            new Employee("Ann", "core", 90),
            new Employee("Bob", "core", 75),
            new Employee("Cara", "apps", 90),
            new Employee("Dan", "apps", null)));
        staff.sort(Comparator.comparing(Employee::team)
            .thenComparing(Employee::score, Comparator.nullsLast(Comparator.<Integer>reverseOrder()))
            .thenComparing(Employee::name));
        for (Employee employee : staff) {
            System.out.println(employee.team() + " " + employee.name() + " " + employee.score());
        }
        long missing = staff.stream().filter(employee -> employee.score() == null).count();
        System.out.println("missing=" + missing);
    }
}''',
    output: 'apps Cara 90\napps Dan null\ncore Ann 90\ncore Bob 75\nmissing=1',
    pitfalls: <String>['对可能为 null 的字段直接比较，排序中途抛 NullPointerException。', '把 nullsLast 写在 thenComparing 之后，顺序不符合预期。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '改为按分数从高到低排序，null 排最前。', hint: 'Comparator.nullsFirst(Comparator.reverseOrder())。', answer: 'staff.sort(Comparator.comparing(Employee::score, Comparator.nullsFirst(Comparator.<Integer>reverseOrder())));'),
    ],
  ),
  JavaTopic(
    id: 135,
    level: 'advanced',
    title: 'Java 135：groupingBy 的嵌套下游收集器',
    summary: '先按客户分组，再按商品分组，同时求和与计数。',
    concepts: <String>['groupingBy', '下游收集器', 'summingInt', 'TreeMap'],
    objective: '能写出两级分组并控制每一级的 Map 实现与聚合方式。',
    explain:
        'groupingBy 的第三个参数是下游收集器，决定每组内部如何聚合。'
        '把另一个 groupingBy 作为下游，就得到 Map 套 Map 的嵌套结构。'
        '显式传 TreeMap::new 可以让键有序，输出的字符串顺序稳定。',
    code: '''import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

public class Main {
    record Order(String customer, String product, int amount) {}

    public static void main(String[] args) {
        List<Order> orders = List.of(
            new Order("ann", "pen", 3),
            new Order("bob", "book", 2),
            new Order("ann", "book", 5),
            new Order("bob", "pen", 1),
            new Order("ann", "pen", 4));
        Map<String, Integer> totals = orders.stream()
            .collect(Collectors.groupingBy(Order::customer, TreeMap::new, Collectors.summingInt(Order::amount)));
        System.out.println("totals=" + totals);
        Map<String, Map<String, Integer>> byProduct = orders.stream()
            .collect(Collectors.groupingBy(Order::customer, TreeMap::new,
                Collectors.groupingBy(Order::product, TreeMap::new, Collectors.summingInt(Order::amount))));
        System.out.println("byProduct=" + byProduct);
        Map<String, Long> counts = orders.stream()
            .collect(Collectors.groupingBy(Order::customer, TreeMap::new, Collectors.counting()));
        System.out.println("counts=" + counts);
        System.out.println("annPens=" + byProduct.get("ann").get("pen"));
    }
}''',
    output: 'totals={ann=12, bob=3}\nbyProduct={ann={book=5, pen=7}, bob={book=2, pen=1}}\ncounts={ann=3, bob=2}\nannPens=7',
    pitfalls: <String>['不指定 Map 工厂，默认 HashMap 的键顺序在输出中不稳定。', '嵌套分组时把下游写成 Collectors.toList，得到的结构层级与预期不同。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '统计每个客户购买的商品种类数。', hint: '下游先用 mapping 去重再 counting，或分组后取 size。', answer: 'orders.stream().collect(Collectors.groupingBy(Order::customer, Collectors.mapping(Order::product, Collectors.collectingAndThen(Collectors.toSet(), java.util.Set::size))));'),
    ],
  ),
  JavaTopic(
    id: 136,
    level: 'intermediate',
    title: 'Java 136：partitioningBy 二分分组',
    summary: '按布尔条件把流分成 true 与 false 两组，键总是存在。',
    concepts: <String>['partitioningBy', '布尔分组', 'averagingInt', 'counting'],
    objective: '能用 partitioningBy 做通过/不通过统计，并理解它与 groupingBy 的差别。',
    explain:
        'partitioningBy 的键固定为 true 和 false，即使某一组没有元素也会保留空列表。'
        '它的下游收集器与 groupingBy 相同，可以计数、求平均或再分组。'
        '按布尔切分比 groupingBy 更明确，也不需要处理键缺失。',
    code: '''import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

public class Main {
    public static void main(String[] args) {
        List<Integer> scores = List.of(88, 42, 95, 61, 30, 77);
        Map<Boolean, List<Integer>> split = scores.stream()
            .collect(Collectors.partitioningBy(score -> score >= 60));
        System.out.println("pass=" + split.get(true));
        System.out.println("fail=" + split.get(false));
        Map<Boolean, Long> counts = scores.stream()
            .collect(Collectors.partitioningBy(score -> score >= 60, Collectors.counting()));
        System.out.println("counts=" + new TreeMap<>(counts));
        Map<Boolean, Double> averages = scores.stream()
            .collect(Collectors.partitioningBy(score -> score >= 60, Collectors.averagingInt(score -> score)));
        System.out.println("avgPass=" + averages.get(true));
        System.out.println("avgFail=" + averages.get(false));
        System.out.println("keys=" + split.keySet());
    }
}''',
    output: 'pass=[88, 95, 61, 77]\nfail=[42, 30]\ncounts={false=2, true=4}\navgPass=80.25\navgFail=36.0\nkeys=[false, true]',
    pitfalls: <String>['以为没有元素的组不会出现在结果里，实际会保留空列表。', '把 partitioningBy 当成 groupingBy 用，误以为键可以是任意值。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把及格线改成 75 分并重新统计人数。', hint: '修改谓词中的阈值即可。', answer: 'Collectors.partitioningBy(score -> score >= 75, Collectors.counting())'),
    ],
  ),
  JavaTopic(
    id: 137,
    level: 'intermediate',
    title: 'Java 137：Collectors.toMap 的冲突合并',
    summary: '键重复时 toMap 会抛异常，必须提供合并函数与目标 Map 工厂。',
    concepts: <String>['toMap', '合并函数', 'IllegalStateException', 'TreeMap'],
    objective: '能写出带合并函数的 toMap，避免重复键导致的运行时异常。',
    explain:
        'toMap 的两参数版本遇到重复键直接抛 IllegalStateException。'
        '第三个参数是合并函数，决定旧值与新值如何合成一个。'
        '第四个参数指定 Map 实现，需要有序输出时传 TreeMap::new。',
    code: '''import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

public class Main {
    record Item(String sku, int qty) {}

    public static void main(String[] args) {
        List<Item> items = List.of(new Item("a", 2), new Item("b", 1), new Item("a", 3));
        Map<String, Integer> merged = items.stream()
            .collect(Collectors.toMap(Item::sku, Item::qty, Integer::sum, TreeMap::new));
        System.out.println("merged=" + merged);
        Map<String, String> joined = items.stream()
            .collect(Collectors.toMap(Item::sku, item -> "q" + item.qty, (left, right) -> left + "+" + right, TreeMap::new));
        System.out.println("joined=" + joined);
        try {
            items.stream().collect(Collectors.toMap(Item::sku, Item::qty));
        } catch (IllegalStateException e) {
            System.out.println("duplicateRejected=true");
        }
        Map<String, Integer> unique = List.of(new Item("x", 5)).stream()
            .collect(Collectors.toMap(Item::sku, Item::qty));
        System.out.println("unique=" + unique);
    }
}''',
    output: 'merged={a=5, b=1}\njoined={a=q2+q3, b=q1}\nduplicateRejected=true\nunique={x=5}',
    pitfalls: <String>['用两参数 toMap 处理可能重复的键，运行到重复项才抛异常。', '合并函数参数顺序写反，字符串拼接结果与预期相反。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把重复键的取值规则改成保留较大的数量。', hint: '合并函数用 Integer::max。', answer: 'Collectors.toMap(Item::sku, Item::qty, Integer::max)'),
    ],
  ),
  JavaTopic(
    id: 138,
    level: 'advanced',
    title: 'Java 138：Collectors.teeing 一次遍历双聚合',
    summary: '同时收集两个结果再合成，避免为了两个统计量遍历两遍。',
    concepts: <String>['teeing', '双聚合', 'minBy', 'averaging'],
    objective: '能用 teeing 组合两个下游收集器，并用合并函数生成最终结果。',
    explain:
        'teeing 接收两个下游收集器和一组合并函数，一次遍历同时喂给两边。'
        '常见用途是同时求最小值与最大值、总和与计数。'
        '合并函数拿到两个下游的最终结果，返回任意类型。',
    code: '''import java.util.List;
import java.util.stream.Collectors;

public class Main {
    record Stats(long count, int sum) {}

    public static void main(String[] args) {
        List<Integer> values = List.of(4, 8, 15, 16, 23, 42);
        Stats stats = values.stream()
            .collect(Collectors.teeing(
                Collectors.counting(),
                Collectors.summingInt(value -> value),
                Stats::new));
        System.out.println("count=" + stats.count() + " sum=" + stats.sum());
        String range = values.stream()
            .collect(Collectors.teeing(
                Collectors.minBy(Integer::compareTo),
                Collectors.maxBy(Integer::compareTo),
                (min, max) -> min.orElse(0) + ".." + max.orElse(0)));
        System.out.println("range=" + range);
        double average = values.stream()
            .collect(Collectors.teeing(
                Collectors.summingInt(value -> value),
                Collectors.counting(),
                (sum, count) -> sum / (double) count));
        System.out.println("average=" + average);
    }
}''',
    output: 'count=6 sum=108\nrange=4..42\naverage=18.0',
    pitfalls: <String>['合并函数里对 Optional 直接 get，空流时抛 NoSuchElementException。', '为了两个统计量写两次 stream 调用，白跑一遍数据。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用 teeing 同时求出元素个数与最大值。', hint: '下游用 counting 和 maxBy，合并成字符串。', answer: 'values.stream().collect(Collectors.teeing(Collectors.counting(), Collectors.maxBy(Integer::compareTo), (count, max) -> count + ":" + max.orElse(0)));'),
    ],
  ),
  JavaTopic(
    id: 139,
    level: 'intermediate',
    title: 'Java 139：IntStream 数值流',
    summary: '用 range、summaryStatistics 和 map 避免装箱开销。',
    concepts: <String>['IntStream', 'rangeClosed', 'summaryStatistics', 'boxed'],
    objective: '能区分对象流与数值流，并在需要集合时正确装箱。',
    explain:
        'IntStream 直接操作 int，避免每个元素装箱成 Integer。'
        'range 左闭右开，rangeClosed 包含右端点，写循环时最容易混淆。'
        'summaryStatistics 一次遍历给出个数、最值、总和与平均。',
    code: '''import java.util.IntSummaryStatistics;
import java.util.stream.IntStream;

public class Main {
    public static void main(String[] args) {
        System.out.println("sum=" + IntStream.rangeClosed(1, 5).sum());
        System.out.println("range=" + IntStream.range(0, 3).boxed().toList());
        IntSummaryStatistics stats = IntStream.of(4, 8, 15, 16, 23, 42).summaryStatistics();
        System.out.println("count=" + stats.getCount() + " min=" + stats.getMin() + " max=" + stats.getMax());
        System.out.println("sumAll=" + stats.getSum());
        System.out.println("average=" + stats.getAverage());
        System.out.println("squares=" + IntStream.rangeClosed(1, 4).map(value -> value * value).boxed().toList());
        System.out.println("evens=" + IntStream.rangeClosed(1, 6).filter(value -> value % 2 == 0).count());
    }
}''',
    output: 'sum=15\nrange=[0, 1, 2]\ncount=6 min=4 max=42\nsumAll=108\naverage=18.0\nsquares=[1, 4, 9, 16]\nevens=3',
    pitfalls: <String>['把 range 当成包含右端点，循环次数少一次。', '数值流调用 toList 前忘记 boxed，类型不匹配编译失败。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '求 1 到 100 中所有 3 的倍数之和。', hint: 'rangeClosed(1, 100).filter(v -> v % 3 == 0).sum()。', answer: 'int total = IntStream.rangeClosed(1, 100).filter(v -> v % 3 == 0).sum();'),
    ],
  ),
  JavaTopic(
    id: 140,
    level: 'intermediate',
    title: 'Java 140：iterate 与 generate 生成流',
    summary: '用种子与函数构造斐波那契、等比数列和常量流。',
    concepts: <String>['Stream.iterate', 'Stream.generate', 'limit', '无限流'],
    objective: '能用迭代与生成构造无限流，并用 limit 截断后收集。',
    explain:
        'iterate 从种子开始，按一元函数不断产生下一个元素。'
        '三参数 iterate 同时提供终止条件，是 Java 9 之后推荐的写法。'
        'generate 不依赖前一个元素，适合常量或随机源；两者都必须配合 limit 或短路操作。',
    code: '''import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) {
        List<Integer> fibonacci = Stream.iterate(new int[] {0, 1}, pair -> new int[] {pair[1], pair[0] + pair[1]})
            .limit(8)
            .map(pair -> pair[0])
            .collect(Collectors.toList());
        System.out.println("fibonacci=" + fibonacci);
        List<Integer> powers = Stream.iterate(1, value -> value * 2)
            .limit(6)
            .collect(Collectors.toList());
        System.out.println("powers=" + powers);
        List<Integer> bounded = Stream.iterate(1, value -> value <= 20, value -> value * 3)
            .collect(Collectors.toList());
        System.out.println("bounded=" + bounded);
        List<Integer> constant = Stream.generate(() -> 7)
            .limit(4)
            .collect(Collectors.toList());
        System.out.println("constant=" + constant);
    }
}''',
    output: 'fibonacci=[0, 1, 1, 2, 3, 5, 8, 13]\npowers=[1, 2, 4, 8, 16, 32]\nbounded=[1, 3, 9]\nconstant=[7, 7, 7, 7]',
    pitfalls: <String>['对无限流直接调用 collect 而不加 limit，程序永不结束。', '把三参数 iterate 的终止条件写成先自增后判断，边界的语义会变。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '生成前 5 个 10 的倍数。', hint: '用 iterate(10, v -> v + 10).limit(5)。', answer: 'Stream.iterate(10, v -> v + 10).limit(5).collect(Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 141,
    level: 'intermediate',
    title: 'Java 141：takeWhile 与 dropWhile',
    summary: '按条件截取前缀，比 filter 更准确地表达有序数据的边界。',
    concepts: <String>['takeWhile', 'dropWhile', '有序流', '前缀'],
    objective: '能区分 filter 与 takeWhile，并在有序数据上正确截取区间。',
    explain:
        'takeWhile 一直取到第一个不满足条件的元素为止，之后即使再满足也丢弃。'
        'dropWhile 丢弃开头满足条件的元素，遇到第一个不满足的之后全部保留。'
        'filter 会检查每个元素，三者语义不同，有序数据用 takeWhile 才符合直觉。',
    code: '''import java.util.List;
import java.util.stream.Collectors;

public class Main {
    public static void main(String[] args) {
        List<Integer> values = List.of(2, 4, 6, 7, 8, 10);
        System.out.println("takeWhile=" + values.stream().takeWhile(value -> value % 2 == 0).collect(Collectors.toList()));
        System.out.println("dropWhile=" + values.stream().dropWhile(value -> value % 2 == 0).collect(Collectors.toList()));
        System.out.println("filter=" + values.stream().filter(value -> value % 2 == 0).collect(Collectors.toList()));
        List<String> lines = List.of("header", "data1", "data2", "footer");
        System.out.println("body=" + lines.stream().dropWhile(line -> line.equals("header")).takeWhile(line -> !line.equals("footer")).collect(Collectors.toList()));
    }
}''',
    output: 'takeWhile=[2, 4, 6]\ndropWhile=[7, 8, 10]\nfilter=[2, 4, 6, 8, 10]\nbody=[data1, data2]',
    pitfalls: <String>['把 takeWhile 当成 filter 用，条件中断后的元素被静默丢弃。', '在无序流上用 takeWhile，结果依赖遍历顺序，不可预测。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '取出一串数字开头连续的负数。', hint: '用 takeWhile(value -> value < 0)。', answer: 'numbers.stream().takeWhile(value -> value < 0).collect(Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 142,
    level: 'intermediate',
    title: 'Java 142：流的惰性与 peek 调试',
    summary: '没有终止操作就不会执行，peek 只用于观察中间过程。',
    concepts: <String>['惰性求值', '终止操作', 'peek', '副作用'],
    objective: '能解释流水线何时真正执行，并用日志验证每个阶段的调用次数。',
    explain:
        'map、filter 等中间操作只记录流水线，只有 count、collect 这类终止操作才会驱动执行。'
        'peek 常用于调试，可以看到元素经过某个阶段的顺序和次数。'
        '正式代码不要依赖 peek 做业务副作用，它的执行次数和顺序都不应被依赖。',
    code: '''import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

public class Main {
    public static void main(String[] args) {
        List<String> log = new ArrayList<>();
        List<Integer> lazy = List.of(1, 2, 3, 4);
        var pipeline = lazy.stream()
            .peek(value -> log.add("peek" + value))
            .map(value -> value * 10);
        System.out.println("beforeTerminal=" + log);
        List<Integer> result = pipeline.collect(Collectors.toList());
        System.out.println("afterTerminal=" + log);
        System.out.println("result=" + result);
        List<String> shortCircuit = new ArrayList<>();
        lazy.stream()
            .peek(value -> shortCircuit.add("p" + value))
            .anyMatch(value -> value == 2);
        System.out.println("shortCircuit=" + shortCircuit);
    }
}''',
    output: 'beforeTerminal=[]\nafterTerminal=[peek1, peek2, peek3, peek4]\nresult=[10, 20, 30, 40]\nshortCircuit=[p1, p2]',
    pitfalls: <String>['只写中间操作不写终止操作，结果什么都没发生。', '在 peek 里修改外部集合，再并行执行时会有线程安全问题。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '观察 anyMatch 命中后 peek 还会不会继续执行。', hint: '在 peek 中累加计数，再调用 anyMatch。', answer: 'lazy.stream().peek(value -> log.add("p" + value)).anyMatch(value -> value == 2);'),
    ],
  ),
  JavaTopic(
    id: 143,
    level: 'beginner',
    title: 'Java 143：anyMatch、allMatch 与 noneMatch',
    summary: '三个短路匹配操作，命中或失败后立即停止遍历。',
    concepts: <String>['anyMatch', 'allMatch', 'noneMatch', '短路'],
    objective: '能根据业务语义选择正确的匹配操作，并知道它们都会短路。',
    explain:
        'anyMatch 只要有一个元素满足就返回 true，allMatch 要求全部满足。'
        'noneMatch 在找到第一个满足条件的元素时立即返回 false。'
        '三者都是短路操作，空流上 allMatch 和 noneMatch 返回 true，anyMatch 返回 false。',
    code: '''import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<Integer> values = List.of(3, 8, 12, 15);
        System.out.println("anyEven=" + values.stream().anyMatch(value -> value % 2 == 0));
        System.out.println("allEven=" + values.stream().allMatch(value -> value % 2 == 0));
        System.out.println("noneNegative=" + values.stream().noneMatch(value -> value < 0));
        System.out.println("allPositive=" + values.stream().allMatch(value -> value > 0));
        List<Integer> empty = List.of();
        System.out.println("emptyAny=" + empty.stream().anyMatch(value -> true));
        System.out.println("emptyAll=" + empty.stream().allMatch(value -> false));
        System.out.println("emptyNone=" + empty.stream().noneMatch(value -> true));
        System.out.println("anyGreaterThan10=" + values.stream().anyMatch(value -> value > 10));
    }
}''',
    output: 'anyEven=true\nallEven=false\nnoneNegative=true\nallPositive=true\nemptyAny=false\nemptyAll=true\nemptyNone=true\nanyGreaterThan10=true',
    pitfalls: <String>['以为空流上 allMatch 返回 false，实际是 true。', '用 anyMatch 判断是否全部满足，语义完全不同。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '判断列表里是否没有任何负数。', hint: '用 noneMatch(value -> value < 0)。', answer: 'boolean safe = values.stream().noneMatch(value -> value < 0);'),
    ],
  ),
  JavaTopic(
    id: 144,
    level: 'intermediate',
    title: 'Java 144：reduce 的三种形态',
    summary: '无初始值、带初始值、带并行合并器的 reduce 分别适合什么场景。',
    concepts: <String>['reduce', '初始值', 'Optional', '结合律'],
    objective: '能根据是否需要空流安全返回选择 reduce 重载，并保证操作满足结合律。',
    explain:
        '单参数 reduce 返回 Optional，因为空流没有结果。'
        '带初始值的 reduce 直接返回同类型结果，空流时返回初始值。'
        '三参数版本用于并行，要求操作满足结合律，否则并行结果可能与串行不同。',
    code: '''import java.util.List;
import java.util.Optional;

public class Main {
    public static void main(String[] args) {
        List<Integer> values = List.of(3, 5, 7, 9);
        Optional<Integer> sum = values.stream().reduce(Integer::sum);
        System.out.println("sum=" + sum.orElse(0));
        int withIdentity = values.stream().reduce(100, Integer::sum);
        System.out.println("withIdentity=" + withIdentity);
        Optional<Integer> max = values.stream().reduce(Integer::max);
        System.out.println("max=" + max.orElseThrow());
        String joined = values.stream().reduce("", (text, value) -> text + value, (left, right) -> left + right);
        System.out.println("joined=" + joined);
        Optional<Integer> emptySum = List.<Integer>of().stream().reduce(Integer::sum);
        System.out.println("emptyPresent=" + emptySum.isPresent());
        System.out.println("emptyIdentity=" + List.<Integer>of().stream().reduce(0, Integer::sum));
    }
}''',
    output: 'sum=24\nwithIdentity=124\nmax=9\njoined=3579\nemptyPresent=false\nemptyIdentity=0',
    pitfalls: <String>['单参数 reduce 直接 get，空流时抛 NoSuchElementException。', '三参数 reduce 的合并器写错，并行执行时结果与串行不一致。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用 reduce 求所有字符串拼接后的长度。', hint: '先用 map 转长度，再 reduce(0, Integer::sum)。', answer: 'int length = words.stream().map(String::length).reduce(0, Integer::sum);'),
    ],
  ),
  JavaTopic(
    id: 145,
    level: 'intermediate',
    title: 'Java 145：flatMap 展开嵌套结构',
    summary: '把每个元素映射成流再合并，处理列表套列表与 Optional 链。',
    concepts: <String>['flatMap', '嵌套集合', 'Optional.stream', '一对多'],
    objective: '能用 flatMap 把嵌套集合拍平，并用 Optional.stream 过滤空值。',
    explain:
        'map 是一对一映射，flatMap 要求返回流，再把所有流连接成一个。'
        '处理 List 套 List 时，flatMap(List::stream) 是最常见的写法。'
        'Optional.stream 把有值与空值统一成零或一个元素的流，过滤空值非常方便。',
    code: '''import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

public class Main {
    record Team(String name, List<String> members) {}

    public static void main(String[] args) {
        List<Team> teams = List.of(
            new Team("core", List.of("ann", "bob")),
            new Team("apps", List.of("cara")));
        List<String> all = teams.stream()
            .flatMap(team -> team.members().stream())
            .collect(Collectors.toList());
        System.out.println("members=" + all);
        System.out.println("count=" + teams.stream().mapToInt(team -> team.members().size()).sum());
        List<Optional<String>> maybe = List.of(Optional.of("x"), Optional.empty(), Optional.of("y"));
        List<String> present = maybe.stream()
            .flatMap(Optional::stream)
            .collect(Collectors.toList());
        System.out.println("present=" + present);
        List<String> letters = List.of("ab", "cd").stream()
            .flatMap(text -> text.chars().mapToObj(c -> String.valueOf((char) c)))
            .collect(Collectors.toList());
        System.out.println("letters=" + letters);
    }
}''',
    output: 'members=[ann, bob, cara]\ncount=3\npresent=[x, y]\nletters=[a, b, c, d]',
    pitfalls: <String>['在 flatMap 里返回 map 的结果而不是流，编译直接失败。', '用 flatMap 处理一对一关系，语义上不如 map 清晰。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把所有团队的成员去重后按字母序输出。', hint: 'flatMap 之后接 distinct 与 sorted。', answer: 'teams.stream().flatMap(team -> team.members().stream()).distinct().sorted().collect(Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 146,
    level: 'beginner',
    title: 'Java 146：distinct 与 sorted 去重排序',
    summary: '去重依赖 equals，排序默认使用自然顺序。',
    concepts: <String>['distinct', 'sorted', 'Comparator', '去重'],
    objective: '能组合去重与排序，并为自定义对象提供比较规则。',
    explain:
        'distinct 基于 equals 和 hashCode 判重，自定义类型必须正确实现这两个方法。'
        'sorted 无参版本要求元素实现 Comparable，带 Comparator 的版本更灵活。'
        '先排序再去重与先去重再排序结果相同，但先去重的数据量更小。',
    code: '''import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

public class Main {
    public static void main(String[] args) {
        List<String> words = List.of("pear", "apple", "pear", "fig", "apple");
        System.out.println("distinct=" + words.stream().distinct().collect(Collectors.toList()));
        System.out.println("sorted=" + words.stream().distinct().sorted().collect(Collectors.toList()));
        System.out.println("byLength=" + words.stream().distinct()
            .sorted(Comparator.comparingInt(String::length).thenComparing(Comparator.naturalOrder()))
            .collect(Collectors.toList()));
        System.out.println("reversed=" + words.stream().distinct()
            .sorted(Comparator.reverseOrder())
            .collect(Collectors.toList()));
        System.out.println("count=" + words.stream().distinct().count());
    }
}''',
    output: 'distinct=[pear, apple, fig]\nsorted=[apple, fig, pear]\nbyLength=[fig, pear, apple]\nreversed=[pear, fig, apple]\ncount=3',
    pitfalls: <String>['自定义对象没重写 equals 与 hashCode，distinct 无法去重。', '对有序性有要求却没排序，distinct 保留的是首次出现的顺序。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '按单词长度降序输出去重后的结果。', hint: 'comparingInt(String::length).reversed()。', answer: 'words.stream().distinct().sorted(Comparator.comparingInt(String::length).reversed()).collect(Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 147,
    level: 'advanced',
    title: 'Java 147：mapMulti 一对一与一对多',
    summary: 'Java 16 的 mapMulti 用命令式写法输出零到多个元素。',
    concepts: <String>['mapMulti', 'Consumer', '一对多', '类型推断'],
    objective: '能用 mapMulti 替代 filter 加 flatMap 的组合，并写出显式类型参数。',
    explain:
        'mapMulti 接收一个双参数 Consumer，第二个参数是下游接收器。'
        '调用接收器几次就输出几个元素，调用零次相当于过滤。'
        '泛型推断有时需要写成 this.<Integer>mapMulti，否则编译器无法确定结果类型。',
    code: '''import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) {
        List<Integer> values = List.of(1, 2, 3, 4, 5, 6);
        List<Integer> repeated = values.stream()
            .<Integer>mapMulti((value, downstream) -> {
                if (value % 2 == 0) {
                    downstream.accept(value);
                    downstream.accept(value * 10);
                }
            })
            .collect(Collectors.toList());
        System.out.println("repeated=" + repeated);
        List<String> pairs = values.stream()
            .<String>mapMulti((value, downstream) -> {
                downstream.accept("v" + value);
                if (value > 4) {
                    downstream.accept("big" + value);
                }
            })
            .collect(Collectors.toList());
        System.out.println("pairs=" + pairs);
        System.out.println("count=" + pairs.size());
        System.out.println("viaStream=" + Stream.of(1, 2, 3).mapMulti((Integer value, java.util.function.Consumer<Integer> out) -> out.accept(value * 2)).collect(Collectors.toList()));
    }
}''',
    output: 'repeated=[2, 20, 4, 40, 6, 60]\npairs=[v1, v2, v3, v4, v5, big5, v6, big6]\ncount=8\nviaStream=[2, 4, 6]',
    pitfalls: <String>['忘记写显式类型参数，mapMulti 的泛型推断失败。', '在 mapMulti 里直接 return 值，它没有返回值，只能调用接收器。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把奇数替换成它的平方，偶数直接丢弃，用 mapMulti 实现。', hint: '条件里只对奇数调用下游接收器。', answer: 'values.stream().<Integer>mapMulti((value, out) -> { if (value % 2 == 1) { out.accept(value * value); } }).collect(Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 148,
    level: 'intermediate',
    title: 'Java 148：用 IntStream.range 带下标遍历',
    summary: '流没有下标，用整数范围生成索引是最直接的方案。',
    concepts: <String>['IntStream.range', 'mapToObj', '索引遍历', 'boxed'],
    objective: '能在流里访问元素下标，并正确选择 range 的边界。',
    explain:
        'IntStream.range(0, list.size()) 产生从 0 到 size-1 的下标。'
        '用 mapToObj 把下标映射成需要的结果，就能在 Lambda 里同时拿到下标与元素。'
        '还有一种写法是原子计数器，但可读性和并行安全性都更差。',
    code: '''import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public class Main {
    public static void main(String[] args) {
        List<String> names = List.of("ann", "bob", "cara");
        List<String> numbered = IntStream.range(0, names.size())
            .mapToObj(index -> (index + 1) + "." + names.get(index))
            .collect(Collectors.toList());
        System.out.println(numbered);
        List<String> skipped = IntStream.range(0, names.size())
            .filter(index -> index % 2 == 0)
            .mapToObj(index -> names.get(index))
            .collect(Collectors.toList());
        System.out.println("evenIndex=" + skipped);
        String joined = IntStream.range(0, names.size())
            .mapToObj(index -> names.get(index).toUpperCase())
            .collect(Collectors.joining("/"));
        System.out.println("joined=" + joined);
        System.out.println("lastIndex=" + (IntStream.range(0, names.size()).max().orElse(-1)));
    }
}''',
    output: '[1.ann, 2.bob, 3.cara]\nevenIndex=[ann, cara]\njoined=ANN/BOB/CARA\nlastIndex=2',
    pitfalls: <String>['把 range 当成包含右端点，访问 list.get(size) 时越界。', '在并行流里用外部可变下标变量，顺序会错乱。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '输出每个名字及其长度，格式为 name:length。', hint: '在下标映射里拼接 name 与 length。', answer: 'IntStream.range(0, names.size()).mapToObj(i -> names.get(i) + ":" + names.get(i).length()).collect(Collectors.toList());'),
    ],
  ),
  JavaTopic(
    id: 149,
    level: 'advanced',
    title: 'Java 149：Collector 与 joining 定制输出',
    summary: '用 joining 的三种重载拼出分隔符、前缀与后缀，再组合 mapping。',
    concepts: <String>['Collectors.joining', 'mapping', 'collectingAndThen', '字符串聚合'],
    objective: '能把流中的对象映射成字符串后按指定格式拼接，并控制最终类型。',
    explain:
        'joining 无参版本直接连接，单参数版本加分隔符，三参数版本再加前后缀。'
        'mapping 是下游收集器，先把元素转成字符串再交给 joining。'
        'collectingAndThen 可以在收集完成后再套一层转换，例如去掉末尾分隔符。',
    code: '''import java.util.List;
import java.util.stream.Collectors;

public class Main {
    record Product(String name, int price) {}

    public static void main(String[] args) {
        List<Product> products = List.of(
            new Product("pen", 3),
            new Product("book", 12),
            new Product("bag", 25));
        System.out.println(products.stream().map(Product::name).collect(Collectors.joining()));
        System.out.println(products.stream().map(Product::name).collect(Collectors.joining(", ")));
        System.out.println(products.stream().map(Product::name).collect(Collectors.joining(", ", "[", "]")));
        System.out.println(products.stream().collect(Collectors.mapping(Product::name, Collectors.joining("+"))));
        String csv = products.stream()
            .map(product -> product.name() + ":" + product.price())
            .collect(Collectors.joining(";", "{", "}"));
        System.out.println("csv=" + csv);
        String trimmed = products.stream()
            .map(Product::name)
            .collect(Collectors.collectingAndThen(Collectors.joining(","), text -> text.substring(0, text.indexOf(","))));
        System.out.println("trimmed=" + trimmed);
    }
}''',
    output: 'penbookbag\npen, book, bag\n[pen, book, bag]\npen+book+bag\ncsv={pen:3;book:12;bag:25}\ntrimmed=pen',
    pitfalls: <String>['拼接前忘记 map，joining 只能用于 CharSequence 流。', '对空流做 substring 裁剪，字符串为空时抛 StringIndexOutOfBoundsException。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把所有价格用逗号连接成一个字符串。', hint: '先 map(String::valueOf) 再 joining。', answer: 'products.stream().map(product -> String.valueOf(product.price())).collect(Collectors.joining(","));'),
    ],
  ),
  JavaTopic(
    id: 150,
    level: 'intermediate',
    title: 'Java 150：Stream.toList 与不可变结果',
    summary: 'toList 返回不可变列表，需要修改时要显式拷贝。',
    concepts: <String>['Stream.toList', '不可变列表', 'Collectors.toList', '拷贝'],
    objective: '能区分 toList 与 Collectors.toList 的可变性，并按需选择。',
    explain:
        'Stream.toList 返回不可变列表，add 和 remove 都会抛 UnsupportedOperationException。'
        'Collectors.toList 不承诺具体实现，但通常返回可变的 ArrayList。'
        '需要后续修改时用 new ArrayList<>(stream.toList()) 做一次显式拷贝。',
    code: '''import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

public class Main {
    public static void main(String[] args) {
        List<Integer> values = List.of(3, 1, 2);
        List<Integer> immutable = values.stream().sorted().toList();
        System.out.println("immutable=" + immutable);
        List<Integer> collected = values.stream().sorted().collect(Collectors.toList());
        collected.add(99);
        System.out.println("collected=" + collected);
        List<Integer> copy = new ArrayList<>(immutable);
        copy.add(0, 100);
        System.out.println("copy=" + copy);
        try {
            immutable.add(4);
        } catch (UnsupportedOperationException e) {
            System.out.println("immutableRejected=true");
        }
        System.out.println("original=" + values);
    }
}''',
    output: 'immutable=[1, 2, 3]\ncollected=[1, 2, 3, 99]\ncopy=[100, 1, 2, 3]\nimmutableRejected=true\noriginal=[3, 1, 2]',
    pitfalls: <String>['对 toList 的结果排序或增删，运行时抛 UnsupportedOperationException。', '以为 Collectors.toList 保证返回 ArrayList，规范只承诺 List。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把过滤后的结果直接收集成可继续追加的列表。', hint: '用 new ArrayList<>(stream.toList())。', answer: 'List<Integer> result = new ArrayList<>(values.stream().filter(v -> v > 1).toList());'),
    ],
  ),
  JavaTopic(
    id: 151,
    level: 'intermediate',
    title: 'Java 151：Optional 链式取值与 orElse 的代价',
    summary: 'map 只在有值时执行，orElse 的参数却总会被求值。',
    concepts: <String>['Optional.map', 'orElse', 'orElseGet', '惰性'],
    objective: '能区分 orElse 与 orElseGet 的求值时机，避免无谓的高代价计算。',
    explain:
        'map 在有值时转换，为空时直接返回空 Optional，链式调用不会抛异常。'
        'orElse 的参数是普通方法调用，无论是否为空都会先算出来。'
        'orElseGet 接收 Supplier，只有确实为空时才执行，适合创建对象或查询。',
    code: '''import java.util.Optional;

public class Main {
    static String expensive(String tag) {
        System.out.println("computed " + tag);
        return tag;
    }

    public static void main(String[] args) {
        Optional<String> present = Optional.of("java");
        Optional<String> empty = Optional.empty();
        System.out.println("mapped=" + present.map(String::length).orElse(0));
        System.out.println("chained=" + empty.map(String::length).map(length -> length * 2).orElse(-1));
        System.out.println("withOrElse=" + present.orElse(expensive("fallback")));
        System.out.println("withOrElseGet=" + present.orElseGet(() -> expensive("supplier")));
        System.out.println("emptyOrElseGet=" + empty.orElseGet(() -> expensive("onlyWhenEmpty")));
    }
}''',
    output: 'mapped=4\nchained=-1\ncomputed fallback\nwithOrElse=java\nwithOrElseGet=java\ncomputed onlyWhenEmpty\nemptyOrElseGet=onlyWhenEmpty',
    pitfalls: <String>['在高频路径用 orElse 创建默认对象，即使有值也会分配内存。', '把 orElseThrow 写在链中间，异常会打断后续的 map。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把 orElse 改成只在为空时才创建默认列表。', hint: '使用 orElseGet 并传 ArrayList::new。', answer: 'Optional.ofNullable(list).orElseGet(ArrayList::new);'),
    ],
  ),
  JavaTopic(
    id: 152,
    level: 'intermediate',
    title: 'Java 152：Optional 安全读取 Map',
    summary: '用 ofNullable 包装 get 结果，避免层层判空与空指针。',
    concepts: <String>['Optional.ofNullable', 'Map.get', 'filter', 'flatMap'],
    objective: '能把可能返回 null 的查询包装成 Optional，并在链上完成校验与转换。',
    explain:
        'Optional.ofNullable 把可能为 null 的值包装成空 Optional 或有值 Optional。'
        'filter 在值为空或不满足条件时都返回空，链式写法不需要显式判空。'
        'flatMap 用于返回值本身就是 Optional 的场景，避免嵌套 Optional。',
    code: '''import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

public class Main {
    static final Map<String, String> SETTINGS = new HashMap<>();

    static {
        SETTINGS.put("theme", "dark");
        SETTINGS.put("timeout", "30");
    }

    static Optional<Integer> intSetting(String key) {
        return Optional.ofNullable(SETTINGS.get(key))
            .filter(value -> value.chars().allMatch(Character::isDigit))
            .map(Integer::parseInt);
    }

    public static void main(String[] args) {
        System.out.println("theme=" + Optional.ofNullable(SETTINGS.get("theme")).orElse("unset"));
        System.out.println("missing=" + Optional.ofNullable(SETTINGS.get("lang")).orElse("unset"));
        System.out.println("timeout=" + intSetting("timeout").orElse(-1));
        System.out.println("themeAsInt=" + intSetting("theme").orElse(-1));
        System.out.println("tooLarge=" + intSetting("timeout").filter(value -> value > 60).orElse(-1));
        System.out.println("upper=" + Optional.ofNullable(SETTINGS.get("theme")).map(String::toUpperCase).orElse("UNSET"));
    }
}''',
    output: 'theme=dark\nmissing=unset\ntimeout=30\nthemeAsInt=-1\ntooLarge=-1\nupper=DARK',
    pitfalls: <String>['直接对 map.get 的结果调用方法，键不存在时抛 NullPointerException。', '用 Optional 作为字段或方法参数，违背它的设计初衷。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '读取配置并转成整数，非法值统一返回 0。', hint: '用 ofNullable、filter 数字校验、map 解析，最后 orElse(0)。', answer: 'Optional.ofNullable(SETTINGS.get(key)).filter(v -> v.chars().allMatch(Character::isDigit)).map(Integer::parseInt).orElse(0);'),
    ],
  ),
  JavaTopic(
    id: 153,
    level: 'intermediate',
    title: 'Java 153：OptionalInt 与 OptionalDouble',
    summary: '数值流的结果是专用 Optional，避免装箱并支持基本类型操作。',
    concepts: <String>['OptionalInt', 'OptionalDouble', 'IntStream', 'orElse'],
    objective: '能使用数值流返回的专用 Optional，并知道它不继承 Optional。',
    explain:
        'IntStream.max、average 返回 OptionalInt 与 OptionalDouble，'
        '而不是 Optional<Integer>。'
        '它们提供 getAsInt、orElse 等基本类型方法，没有 map 与 filter。'
        '需要转换时先 orElse 取值，或调用 stream().boxed() 转回对象流再处理。',
    code: '''import java.util.OptionalDouble;
import java.util.OptionalInt;
import java.util.stream.IntStream;

public class Main {
    public static void main(String[] args) {
        OptionalInt max = IntStream.of(4, 8, 15, 16, 23, 42).max();
        System.out.println("max=" + max.getAsInt());
        OptionalInt emptyMax = IntStream.empty().max();
        System.out.println("emptyMax=" + emptyMax.orElse(-1));
        System.out.println("emptyPresent=" + emptyMax.isPresent());
        OptionalDouble average = IntStream.rangeClosed(1, 4).average();
        System.out.println("average=" + average.getAsDouble());
        System.out.println("averageOr=" + IntStream.empty().average().orElse(0.0));
        System.out.println("boxed=" + IntStream.of(2, 4).boxed().map(value -> value + 1).toList());
    }
}''',
    output: 'max=42\nemptyMax=-1\nemptyPresent=false\naverage=2.5\naverageOr=0.0\nboxed=[3, 5]',
    pitfalls: <String>['对 OptionalInt 调用 map，它没有这个方法。', '空结果直接 getAsInt，抛 NoSuchElementException。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '求数组最大值，空数组时返回 0。', hint: 'Arrays.stream(values).max().orElse(0)。', answer: 'int max = java.util.Arrays.stream(values).max().orElse(0);'),
    ],
  ),
  JavaTopic(
    id: 154,
    level: 'advanced',
    title: 'Java 154：Optional.or 与 orElseThrow 链',
    summary: '多个备选来源依次尝试，全部失败再抛业务异常。',
    concepts: <String>['Optional.or', 'orElseThrow', 'Supplier', '备选链'],
    objective: '能用 or 串联多个数据源，并用 orElseThrow 给出明确错误信息。',
    explain:
        'or 接收返回 Optional 的 Supplier，只有当前为空时才去尝试下一个来源。'
        'orElseThrow 可以传异常构造器，让调用方看到具体缺失的键。'
        '整条链是惰性的，排在前面的来源命中后不会再去查询后面的来源。',
    code: '''import java.util.List;
import java.util.Optional;

public class Main {
    static final List<String> CACHE = List.of("cached");
    static final List<String> DISK = List.of();

    static Optional<String> fromCache() {
        System.out.println("try cache");
        return CACHE.stream().findFirst();
    }

    static Optional<String> fromDisk() {
        System.out.println("try disk");
        return DISK.stream().findFirst();
    }

    static Optional<String> fromNetwork() {
        System.out.println("try network");
        return Optional.of("generated");
    }

    public static void main(String[] args) {
        String value = fromCache()
            .or(Main::fromDisk)
            .or(Main::fromNetwork)
            .orElseThrow(() -> new IllegalStateException("no source"));
        System.out.println("value=" + value);
        Optional<String> first = Optional.of("hit")
            .or(Main::fromNetwork);
        System.out.println("lazyHit=" + first.get());
        try {
            Optional.empty().or(Main::fromDisk).orElseThrow(() -> new IllegalStateException("all empty"));
        } catch (IllegalStateException e) {
            System.out.println("error=" + e.getMessage());
        }
    }
}''',
    output: 'try cache\nvalue=cached\nlazyHit=hit\ntry disk\nerror=all empty',
    pitfalls: <String>['用 orElse 串联备选来源，所有来源都会被提前求值。', 'orElseThrow 不写异常信息，线上排查时无法定位缺失的键。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '按内存、磁盘、默认值顺序取配置，写出链式调用。', hint: 'or(磁盘方法).or(默认值方法)，最后 orElse。', answer: 'fromMemory().or(Main::fromDisk).or(() -> Optional.of("default")).orElse("none");'),
    ],
  ),
  JavaTopic(
    id: 155,
    level: 'intermediate',
    title: 'Java 155：对象数组排序与二分查找',
    summary: 'Arrays.sort 配合 Comparator，Arrays.binarySearch 必须用于有序数组。',
    concepts: <String>['Arrays.sort', 'Arrays.binarySearch', 'Comparator', '区间查找'],
    objective: '能对对象数组按自定义规则排序，并用二分查找定位元素。',
    explain:
        'Arrays.sort 对对象数组使用稳定排序，可以传入 Comparator。'
        'binarySearch 返回命中下标或负数插入点，调用前必须保证数组有序。'
        '对象数组的自然排序要求元素实现 Comparable。',
    code: '''import java.util.Arrays;
import java.util.Comparator;

public class Main {
    record Book(String title, int pages) {}

    public static void main(String[] args) {
        Book[] books = {
            new Book("beta", 300),
            new Book("alpha", 120),
            new Book("gamma", 300),
            new Book("delta", 80)
        };
        Arrays.sort(books, Comparator.comparingInt(Book::pages).thenComparing(Book::title));
        for (Book book : books) {
            System.out.println(book.title() + " " + book.pages());
        }
        int[] numbers = {9, 4, 7, 1, 5};
        Arrays.sort(numbers);
        System.out.println("sortedNumbers=" + Arrays.toString(numbers));
        System.out.println("index5=" + Arrays.binarySearch(numbers, 5));
        System.out.println("index6=" + Arrays.binarySearch(numbers, 6));
        System.out.println("min=" + books[0].title());
    }
}''',
    output: 'delta 80\nalpha 120\nbeta 300\ngamma 300\nsortedNumbers=[1, 4, 5, 7, 9]\nindex5=2\nindex6=-4\nmin=delta',
    pitfalls: <String>['对未排序数组调用 binarySearch，返回的下标没有意义。', '比较器链里遗漏姓名，页数相同的两本书顺序不确定。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '把书按页数降序排列，页数相同按标题升序。', hint: 'comparingInt(Book::pages).reversed().thenComparing(Book::title)。', answer: 'Arrays.sort(books, Comparator.comparingInt(Book::pages).reversed().thenComparing(Book::title));'),
    ],
  ),
  JavaTopic(
    id: 156,
    level: 'intermediate',
    title: 'Java 156：计数排序',
    summary: '当数值范围很小时，用计数数组把排序降到线性时间。',
    concepts: <String>['计数排序', '线性时间', '前缀和', '稳定排序'],
    objective: '能判断计数排序的适用条件，并用前缀和把结果写回稳定顺序。',
    explain:
        '计数排序统计每个值出现的次数，再按值从小到大输出。'
        '把计数数组改成前缀和后，可以确定每个元素在结果中的结束位置，从而保持稳定。'
        '它只适合范围较小的非负整数，范围过大时计数数组会浪费大量内存。',
    code: '''import java.util.Arrays;

public class Main {
    static int[] countingSort(int[] values) {
        if (values.length == 0) {
            return new int[0];
        }
        int max = Arrays.stream(values).max().orElse(0);
        int[] counts = new int[max + 1];
        for (int value : values) {
            counts[value]++;
        }
        for (int i = 1; i < counts.length; i++) {
            counts[i] += counts[i - 1];
        }
        int[] result = new int[values.length];
        for (int i = values.length - 1; i >= 0; i--) {
            int value = values[i];
            counts[value]--;
            result[counts[value]] = value;
        }
        return result;
    }

    public static void main(String[] args) {
        System.out.println(Arrays.toString(countingSort(new int[] {4, 2, 2, 8, 3, 3, 1})));
        System.out.println(Arrays.toString(countingSort(new int[] {0})));
        System.out.println(Arrays.toString(countingSort(new int[] {})));
        System.out.println(Arrays.toString(countingSort(new int[] {5, 5, 5})));
    }
}''',
    output: '[1, 2, 2, 3, 3, 4, 8]\n[0]\n[]\n[5, 5, 5]',
    pitfalls: <String>['数组里有负数时直接当下标使用，抛出数组越界。', '回填时从前往后遍历，相同值的相对顺序会被打乱。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '在排序前先判断最大值是否过大，超过阈值时返回原数组。', hint: '取 max 后与 10000 比较。', answer: 'if (max > 10000) { return values.clone(); }'),
    ],
  ),
  JavaTopic(
    id: 157,
    level: 'advanced',
    title: 'Java 157：并查集与路径压缩',
    summary: '用父数组维护连通分量，按秩合并加路径压缩接近常数时间。',
    concepts: <String>['并查集', '路径压缩', '按秩合并', '连通分量'],
    objective: '能实现 find 与 union，并说明路径压缩如何降低后续查找代价。',
    explain:
        '每个集合用一棵树表示，根节点就是集合代表，find 一路向上找到根。'
        '路径压缩在 find 时把沿途节点直接挂到根上，后续查询几乎一步到位。'
        '合并时把秩小的树挂到秩大的树下，避免树退化成链表。',
    code: '''public class Main {
    static final class DisjointSet {
        private final int[] parent;
        private final int[] rank;
        private int groups;

        DisjointSet(int size) {
            parent = new int[size];
            rank = new int[size];
            groups = size;
            for (int i = 0; i < size; i++) {
                parent[i] = i;
            }
        }

        int find(int node) {
            if (parent[node] != node) {
                parent[node] = find(parent[node]);
            }
            return parent[node];
        }

        boolean union(int left, int right) {
            int a = find(left);
            int b = find(right);
            if (a == b) {
                return false;
            }
            if (rank[a] < rank[b]) {
                parent[a] = b;
            } else if (rank[a] > rank[b]) {
                parent[b] = a;
            } else {
                parent[b] = a;
                rank[a]++;
            }
            groups--;
            return true;
        }
    }

    public static void main(String[] args) {
        DisjointSet set = new DisjointSet(6);
        System.out.println("initialGroups=" + set.groups);
        System.out.println("union01=" + set.union(0, 1));
        System.out.println("union12=" + set.union(1, 2));
        System.out.println("union01Again=" + set.union(0, 2));
        System.out.println("union34=" + set.union(3, 4));
        System.out.println("sameRoot=" + (set.find(0) == set.find(2)));
        System.out.println("differentRoot=" + (set.find(0) == set.find(3)));
        System.out.println("groups=" + set.groups);
    }
}''',
    output: 'initialGroups=6\nunion01=true\nunion12=true\nunion01Again=false\nunion34=true\nsameRoot=true\ndifferentRoot=false\ngroups=3',
    pitfalls: <String>['find 写成 parent[x] == x 的单次判断，没有递归到根。', '合并时忘记减少连通分量计数，结果偏大。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '统计 n 个节点中当前有多少个独立连通分量。', hint: '维护并在 union 成功时自减的 groups 字段。', answer: 'public int groups() { return groups; }'),
    ],
  ),
  JavaTopic(
    id: 158,
    level: 'advanced',
    title: 'Java 158：前缀和与区间求和',
    summary: '预处理一次前缀和，把任意区间求和降到 O(1)。',
    concepts: <String>['前缀和', '区间查询', '预处理', '差分'],
    objective: '能构造长度多一的前缀数组，并正确写出左闭右开区间的求和公式。',
    explain:
        'prefix[i] 表示前 i 个元素之和，长度为 n+1，prefix[0] 为 0。'
        '区间 [left, right) 的和等于 prefix[right] - prefix[left]，两端都不用特判。'
        '多次区间查询时，一次 O(n) 预处理可以换掉每次 O(n) 的重复累加。',
    code: '''import java.util.Arrays;

public class Main {
    static int[] prefix(int[] values) {
        int[] prefix = new int[values.length + 1];
        for (int i = 0; i < values.length; i++) {
            prefix[i + 1] = prefix[i] + values[i];
        }
        return prefix;
    }

    static int range(int[] prefix, int left, int right) {
        return prefix[right] - prefix[left];
    }

    public static void main(String[] args) {
        int[] values = {3, 1, 4, 1, 5, 9, 2};
        int[] prefix = prefix(values);
        System.out.println("prefix=" + Arrays.toString(prefix));
        System.out.println("sum0to7=" + range(prefix, 0, 7));
        System.out.println("sum1to4=" + range(prefix, 1, 4));
        System.out.println("sum0to0=" + range(prefix, 0, 0));
        System.out.println("full=" + prefix[values.length]);
        System.out.println("average=" + (prefix[values.length] / (double) values.length));
    }
}''',
    output: 'prefix=[0, 3, 4, 8, 9, 14, 23, 25]\nsum0to7=25\nsum1to4=6\nsum0to0=0\nfull=25\naverage=3.5714285714285716',
    pitfalls: <String>['前缀数组长度开成 n，右端点取到 n 时越界。', '把 [left, right] 当闭区间，忘记右端点要加一。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '用前缀和求下标 2 到 5（含两端）的元素和。', hint: '换算成左闭右开区间 [2, 6)。', answer: 'int total = range(prefix, 2, 6);'),
    ],
  ),
  JavaTopic(
    id: 159,
    level: 'advanced',
    title: 'Java 159：滑动窗口求最长无重复子串',
    summary: '用左右指针与最后出现位置表，把暴力 O(n^2) 降为 O(n)。',
    concepts: <String>['滑动窗口', 'HashMap', '最长无重复子串', '双指针'],
    objective: '能维护窗口内字符的唯一性，并在出现重复时正确收缩左边界。',
    explain:
        '右指针不断扩张窗口，用 Map 记录每个字符最后出现的下标。'
        '遇到重复字符时，左指针只能右移，不能回退，否则窗口会重新包含重复字符。'
        '每次扩张后用窗口长度更新答案，总时间 O(n)。',
    code: '''import java.util.HashMap;
import java.util.Map;

public class Main {
    static int longestUnique(String text) {
        Map<Character, Integer> lastSeen = new HashMap<>();
        int best = 0;
        int left = 0;
        for (int right = 0; right < text.length(); right++) {
            char c = text.charAt(right);
            Integer previous = lastSeen.get(c);
            if (previous != null && previous >= left) {
                left = previous + 1;
            }
            lastSeen.put(c, right);
            best = Math.max(best, right - left + 1);
        }
        return best;
    }

    public static void main(String[] args) {
        System.out.println("abcabcbb=" + longestUnique("abcabcbb"));
        System.out.println("bbbbb=" + longestUnique("bbbbb"));
        System.out.println("pwwkew=" + longestUnique("pwwkew"));
        System.out.println("empty=" + longestUnique(""));
        System.out.println("single=" + longestUnique("a"));
        System.out.println("allUnique=" + longestUnique("abcdef"));
    }
}''',
    output: 'abcabcbb=3\nbbbbb=1\npwwkew=3\nempty=0\nsingle=1\nallUnique=6',
    pitfalls: <String>['发现重复就把 left 直接设成 right，跳过了可能更长的窗口。', '只用 previous 是否存在判断重复，遇到窗口外的旧下标会错误收缩。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '返回最长无重复子串本身而不是长度。', hint: '记录 bestStart 与 bestLength，最后做一次 substring。', answer: 'return text.substring(bestStart, bestStart + bestLength);'),
    ],
  ),
  JavaTopic(
    id: 160,
    level: 'advanced',
    title: 'Java 160：倒排索引综合练习',
    summary: '把字符串切词、集合去重与流式排序组合成可查询的倒排索引。',
    concepts: <String>['倒排索引', 'Map', 'TreeSet', '综合应用'],
    objective: '能把分词、建索引、查询与排序串成一个完整的小型检索流程。',
    explain:
        '倒排索引是词到文档编号集合的映射，查询时直接取集合而不是扫描全部文档。'
        '用 TreeSet 保存文档编号，既能去重又能保证输出有序。'
        '查询多个词时对集合求交集，再按编号排序输出即可。',
    code: '''import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    static Map<String, TreeSet<Integer>> buildIndex(List<String> documents) {
        Map<String, TreeSet<Integer>> index = new TreeMap<>();
        for (int id = 0; id < documents.size(); id++) {
            String[] words = documents.get(id).toLowerCase().split(" ");
            for (String word : words) {
                index.computeIfAbsent(word, key -> new TreeSet<>()).add(id);
            }
        }
        return index;
    }

    static List<Integer> search(Map<String, TreeSet<Integer>> index, String... words) {
        TreeSet<Integer> result = null;
        for (String word : words) {
            TreeSet<Integer> hits = index.getOrDefault(word, new TreeSet<>());
            if (result == null) {
                result = new TreeSet<>(hits);
            } else {
                result.retainAll(hits);
            }
        }
        return result == null ? List.of() : new ArrayList<>(result);
    }

    public static void main(String[] args) {
        List<String> documents = List.of(
            "java collections map",
            "java streams map filter",
            "kotlin collections");
        Map<String, TreeSet<Integer>> index = buildIndex(documents);
        System.out.println("words=" + index.keySet());
        System.out.println("java=" + index.get("java"));
        System.out.println("map=" + index.get("map"));
        System.out.println("javaAndMap=" + search(index, "java", "map"));
        System.out.println("collectionsAndJava=" + search(index, "collections", "java"));
        System.out.println("missing=" + search(index, "java", "python"));
        System.out.println("docCount=" + documents.size());
    }
}''',
    output: 'words=[collections, filter, java, kotlin, map, streams]\njava=[0, 1]\nmap=[0, 1]\njavaAndMap=[0, 1]\ncollectionsAndJava=[0]\nmissing=[]\ndocCount=3',
    pitfalls: <String>['分词后没有统一小写，Java 与 java 会被当成两个词。', '多词查询时忘记对集合取交集，结果变成任一命中就算匹配。'],
    tasks: <JavaTask>[
      JavaTask(prompt: '让查询返回命中的文档原文而不是编号。', hint: '把编号映射回 documents.get(id)。', answer: 'return result.stream().map(documents::get).collect(java.util.stream.Collectors.toList());'),
    ],
  ),
];
