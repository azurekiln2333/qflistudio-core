/// Java topics 161-220: sandbox-local I/O, byte buffers, charsets, regex,
/// time, math, serialization and crypto.
///
/// Everything here runs offline with the JDK only. Each program is a complete,
/// formatted `Main.java` whose stdout is byte-for-byte reproducible (no
/// absolute paths, no wall-clock time, no hash-map iteration order, no default
/// locale or time zone in the output).
library;

import 'java_topic.dart';

const List<JavaTopic> javaIoTimeTopics = <JavaTopic>[
  JavaTopic(
    id: 161,
    level: 'intermediate',
    title: 'Java 161：临时目录与临时文件',
    summary: '用 Files.createTempDirectory/createTempFile 在沙箱里安全地创建和清理临时文件。',
    concepts: <String>['Files', '临时文件', 'Path', '资源清理'],
    objective: '能用临时目录隔离一次任务的中间产物，并在结束时确认文件与目录都被删除。',
    explain:
        '`Files.createTempDirectory(prefix)` 会在系统临时目录下创建一个名字随机、权限受控的新目录；'
        '`Files.createTempFile(dir, prefix, suffix)` 在同一目录里创建空文件并返回它的 `Path`。'
        '两者的文件名都带随机串，所以程序只能判断前缀/后缀与父目录，不能打印完整路径——'
        '否则输出无法复现。`Files.exists` 用来验证删除结果，`Files.delete` 只能删空目录，'
        '删非空目录要用 `Files.deleteIfExists` 逐个清理或改用递归删除。'
        '示例用 try/finally 把 `Files.walk` 倒序删除包起来，'
        '即使中途抛异常也不会把文件留在沙箱里。',
    code: r'''import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-demo-");
        try {
            Path file = Files.createTempFile(dir, "note-", ".txt");
            Files.writeString(file, "沙箱临时文件", StandardCharsets.UTF_8);
            System.out.println("hasPrefix=" + file.getFileName().toString().startsWith("note-"));
            System.out.println("hasSuffix=" + file.getFileName().toString().endsWith(".txt"));
            System.out.println("parentIsDir=" + file.getParent().equals(dir));
            System.out.println("content=" + Files.readString(file, StandardCharsets.UTF_8));
            System.out.println("bytes=" + Files.size(file));
            Files.delete(file);
            System.out.println("fileExists=" + Files.exists(file));
            Files.delete(dir);
            System.out.println("dirExists=" + Files.exists(dir));
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'hasPrefix=true\n'
        'hasSuffix=true\n'
        'parentIsDir=true\n'
        'content=沙箱临时文件\n'
        'bytes=18\n'
        'fileExists=false\n'
        'dirExists=false',
    pitfalls: <String>[
      '不要打印临时文件的绝对路径，随机文件名会让输出每次都不同。',
      'Files.delete 遇到非空目录会抛 DirectoryNotEmptyException。',
      '临时文件不是「重启后自动消失」的保证，任务结束要显式删除。',
      '不传字符集的 readString/writeString 使用平台默认编码，设备上可能不是 UTF-8。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '在同一临时目录里再创建一个子目录，写入一个文件，然后按「先文件后目录」的顺序删除。',
        hint: 'Files.createDirectories 创建子目录，删除顺序必须由内向外。',
        answer:
            'Path sub = Files.createDirectories(dir.resolve("sub")); Files.delete(sub);',
      ),
    ],
  ),
  JavaTopic(
    id: 162,
    level: 'intermediate',
    title: 'Java 162：原子替换写文件',
    summary: '先写临时文件再 ATOMIC_MOVE，避免中途崩溃留下半个文件。',
    concepts: <String>['Files.move', 'ATOMIC_MOVE', 'REPLACE_EXISTING', '崩溃安全'],
    objective: '能实现「写临时文件 + 原子改名」的更新流程，并解释它为什么比直接覆盖更安全。',
    explain:
        '直接 `Files.writeString(target, ...)` 在写到一半时崩溃，会留下被截断的文件。'
        '更安全的做法是：把新内容写进同目录的临时文件，落盘后再用 `Files.move` 原子地替换目标。'
        '`StandardCopyOption.ATOMIC_MOVE` 要求移动不可分割，`REPLACE_EXISTING` 允许覆盖已有目标；'
        '同一文件系统内的改名通常是原子的，所以读者只会看到旧版本或新版本。'
        '移动成功后临时文件就不存在了，这一点可以用 `Files.exists` 验证。',
    code: r'''import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-atomic-");
        try {
            Path target = dir.resolve("config.txt");
            Path staging = dir.resolve("config.txt.tmp");
            Files.writeString(target, "version=1\n", StandardCharsets.UTF_8);
            Files.writeString(staging, "version=2\nmode=offline\n", StandardCharsets.UTF_8);
            Files.move(staging, target, StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING);
            System.out.println("stagingExists=" + Files.exists(staging));
            System.out.println("lines=" + Files.readAllLines(target, StandardCharsets.UTF_8).size());
            System.out.println("first=" + Files.readAllLines(target, StandardCharsets.UTF_8).get(0));
            System.out.println("second=" + Files.readAllLines(target, StandardCharsets.UTF_8).get(1));
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'stagingExists=false\n'
        'lines=2\n'
        'first=version=2\n'
        'second=mode=offline',
    pitfalls: <String>[
      '临时文件必须和目标在同一个文件系统，跨卷的 ATOMIC_MOVE 会抛 AtomicMoveNotSupportedException。',
      '忘了 REPLACE_EXISTING 时，目标已存在会让 move 失败。',
      '原子替换只保证「不会看到半个文件」，不保证旧内容还有备份。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '改成先写三次不同内容，每次都用原子替换，最后打印目标文件的最终内容。',
        hint: '把「写 staging + move」抽成一个方法，循环调用。',
        answer:
            'for (int v = 1; v <= 3; v++) { Files.writeString(staging, "v" + v); Files.move(staging, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }',
      ),
    ],
  ),
  JavaTopic(
    id: 163,
    level: 'intermediate',
    title: 'Java 163：复制文件与保留属性',
    summary:
        'Files.copy 的 REPLACE_EXISTING 与 COPY_ATTRIBUTES，以及用 mismatch 比较差异。',
    concepts: <String>[
      'Files.copy',
      'COPY_ATTRIBUTES',
      'Files.mismatch',
      '文件时间',
    ],
    objective: '能复制文件并决定是否保留时间戳，能用 Files.mismatch 精确判断两份内容是否一致。',
    explain:
        '`Files.copy(source, target, options)` 默认在目标已存在时抛 `FileAlreadyExistsException`，'
        '加 `REPLACE_EXISTING` 才会覆盖。`COPY_ATTRIBUTES` 会把修改时间等基本属性一起复制过来。'
        '`Files.mismatch(a, b)` 返回第一个不同字节的下标，完全相同返回 `-1`；'
        '它比先读完两个文件再比较更省内存，也比比较大小更准确。',
    code: r'''import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.FileTime;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-copy-");
        try {
            Path source = dir.resolve("source.txt");
            Path copy = dir.resolve("copy.txt");
            Files.writeString(source, "abcdef");
            Files.setLastModifiedTime(source, FileTime.fromMillis(1_700_000_000_000L));
            Files.copy(source, copy, StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.COPY_ATTRIBUTES);
            System.out.println("identical=" + (Files.mismatch(source, copy) == -1L));
            System.out.println("sameTime="
                    + Files.getLastModifiedTime(source).equals(Files.getLastModifiedTime(copy)));
            Files.writeString(source, "abc");
            System.out.println("sizeDiffers=" + (Files.size(source) != Files.size(copy)));
            System.out.println("copyStill=" + Files.readString(copy));
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'identical=true\n'
        'sameTime=true\n'
        'sizeDiffers=true\n'
        'copyStill=abcdef',
    pitfalls: <String>[
      '不加 REPLACE_EXISTING 时复制到已存在的目标会直接失败。',
      'COPY_ATTRIBUTES 不是所有属性都能跨文件系统复制，部分属性可能被忽略。',
      'Files.mismatch 返回 long，比较时写 -1 而不是 -1L 也能通过自动提升，但保持类型一致更清晰。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '复制后修改源文件的第 3 个字节，打印 mismatch 的结果。',
        hint: '用 Files.writeString 写入 "abXdef" 之类的内容，下标从 0 开始。',
        answer:
            'Files.writeString(source, "abXdef"); System.out.println(Files.mismatch(source, copy)); // 2',
      ),
    ],
  ),
  JavaTopic(
    id: 164,
    level: 'intermediate',
    title: 'Java 164：Files.walk 遍历目录树',
    summary: '用 Stream 遍历目录、限制深度、排序输出，并在 finally 中正确关闭流。',
    concepts: <String>[
      'Files.walk',
      'Stream',
      'try-with-resources',
      'relativize',
    ],
    objective: '能遍历目录树并按稳定顺序输出相对路径，知道为什么必须关闭 walk 返回的流。',
    explain:
        '`Files.walk(root)` 返回一个惰性 `Stream<Path>`，它持有打开的目录句柄，'
        '必须用 try-with-resources 关闭，否则在 Windows 上会锁住目录导致删不掉。'
        '`root.relativize(p)` 把绝对路径变成相对路径，这样输出与临时目录的随机名字无关。'
        '目录遍历顺序由文件系统决定，要可复现就必须 `sorted()`。'
        '`Files.walk(root, 1)` 的第二个参数是最大深度，1 表示只看直接子项。',
    code: r'''import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path root = Files.createTempDirectory("qfli-walk-");
        try {
            Path deep = Files.createDirectories(root.resolve("a/b"));
            Path other = Files.createDirectories(root.resolve("c"));
            Files.writeString(root.resolve("readme.txt"), "root");
            Files.writeString(deep.resolve("deep.txt"), "deep");
            Files.writeString(other.resolve("data.bin"), "bin");
            try (Stream<Path> walk = Files.walk(root)) {
                List<String> names = walk
                        .filter(path -> !path.equals(root))
                        .map(path -> root.relativize(path).toString().replace('\\', '/'))
                        .sorted()
                        .collect(Collectors.toList());
                System.out.println("entries=" + names.size());
                names.forEach(name -> System.out.println(" - " + name));
            }
            try (Stream<Path> shallow = Files.walk(root, 1)) {
                System.out.println("depth1=" + shallow.count());
            }
        } finally {
            cleanup(root);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'entries=6\n'
        ' - a\n'
        ' - a/b\n'
        ' - a/b/deep.txt\n'
        ' - c\n'
        ' - c/data.bin\n'
        ' - readme.txt\n'
        'depth1=4',
    pitfalls: <String>[
      '忘记关闭 Files.walk 的流会泄漏目录句柄，后续删除目录可能失败。',
      '不排序就输出，不同文件系统上的顺序不一致。',
      'relativize 只有在两个路径同属一棵树时才有意义。',
      '遍历后必须清理临时目录，否则反复运行会不断积累文件。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '只输出以 .txt 结尾的文件，并统计它们的字节总数。',
        hint:
            'filter 里用 path.toString().endsWith(".txt")，再用 mapToLong(Files::size)。',
        answer:
            'walk.filter(p -> p.toString().endsWith(".txt")).mapToLong(p -> { try { return Files.size(p); } catch (IOException e) { return 0; } }).sum()',
      ),
    ],
  ),
  JavaTopic(
    id: 165,
    level: 'advanced',
    title: 'Java 165：walkFileTree 与访问者模式',
    summary: '用 SimpleFileVisitor 分别处理目录和文件，并读取 BasicFileAttributes。',
    concepts: <String>[
      'walkFileTree',
      'SimpleFileVisitor',
      'BasicFileAttributes',
      'FileVisitResult',
    ],
    objective: '能自定义文件树遍历行为，例如按目录/文件分类收集信息或提前跳过子树。',
    explain:
        '`Files.walkFileTree` 是比 `Files.walk` 更底层的遍历方式：它按深度优先回调访问者，'
        '`preVisitDirectory` 在进入目录前调用，`visitFile` 对每个普通文件调用。'
        '回调返回 `FileVisitResult.CONTINUE` 表示继续，`SKIP_SUBTREE` 跳过整个子树，'
        '`TERMINATE` 立即结束遍历。`BasicFileAttributes` 提供大小、创建/修改时间等元数据，'
        '读取它不会额外打开文件。',
    code: r'''import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path root = Files.createTempDirectory("qfli-visit-");
        try {
            Files.createDirectories(root.resolve("src/main"));
            Files.writeString(root.resolve("src/main/App.java"), "class App {}");
            Files.writeString(root.resolve("build.gradle"), "plugins {}");
            List<String> dirs = new ArrayList<>();
            List<String> files = new ArrayList<>();
            Files.walkFileTree(root, new SimpleFileVisitor<Path>() {
                @Override
                public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) {
                    if (!dir.equals(root)) {
                        dirs.add(root.relativize(dir).toString().replace('\\', '/'));
                    }
                    return FileVisitResult.CONTINUE;
                }

                @Override
                public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) {
                    String name = root.relativize(file).toString().replace('\\', '/');
                    files.add(name + ":" + attrs.size());
                    return FileVisitResult.CONTINUE;
                }
            });
            Collections.sort(dirs);
            Collections.sort(files);
            System.out.println("dirs=" + dirs);
            System.out.println("files=" + files);
        } finally {
            cleanup(root);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'dirs=[src, src/main]\n'
        'files=[build.gradle:10, src/main/App.java:12]',
    pitfalls: <String>[
      '根目录也会触发 preVisitDirectory，relativize 之后是空字符串，通常需要自己过滤。',
      'visitFileFailed 默认会抛出异常，遇到无权限文件时要重写它才能继续遍历。',
      '在访问者里抛受检异常需要自己包成 IOException 或 UncheckedIOException。',
      '遍历完要按「先文件后目录」的顺序删除，否则会报 DirectoryNotEmptyException。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '让遍历在遇到名为 main 的目录时跳过它的子树，观察 dirs 的变化。',
        hint:
            '在 preVisitDirectory 中判断 dir.getFileName() 并返回 FileVisitResult.SKIP_SUBTREE。',
        answer:
            'if ("main".equals(String.valueOf(dir.getFileName()))) { return FileVisitResult.SKIP_SUBTREE; }',
      ),
    ],
  ),
  JavaTopic(
    id: 166,
    level: 'intermediate',
    title: 'Java 166：用 mismatch 定位第一处差异',
    summary: 'Files.mismatch 返回首个不同字节的下标，长度不同时返回较短文件的长度。',
    concepts: <String>['Files.mismatch', '内容比较', '返回值语义'],
    objective: '能读懂 Files.mismatch 的三种返回值，并用它做增量比较而不是整读整比。',
    explain:
        '`Files.mismatch(a, b)` 的语义是：内容完全相同返回 `-1`；'
        '在某个位置字节不同就返回那个下标；'
        '一个文件是另一个的前缀时返回较短文件的字节长度。'
        '返回值类型是 `long`，因为文件可以超过 2GB。'
        '这个方法适合比较日志、导出的备份或二进制资源，'
        '不需要把两个文件同时读进内存。',
    code: r'''import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-mismatch-");
        try {
            Path left = dir.resolve("left.txt");
            Path right = dir.resolve("right.txt");
            Files.writeString(left, "hello world");
            Files.writeString(right, "hello world");
            System.out.println("equal=" + (Files.mismatch(left, right) == -1L));
            Files.writeString(right, "helloWorld");
            System.out.println("sameLength=" + Files.mismatch(left, right));
            Files.writeString(right, "hello world!");
            System.out.println("prefixCase=" + Files.mismatch(left, right));
            Files.writeString(right, "hel");
            System.out.println("shorterCase=" + Files.mismatch(left, right));
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'equal=true\n'
        'sameLength=5\n'
        'prefixCase=11\n'
        'shorterCase=3',
    pitfalls: <String>[
      '把 -1 当成「不同」是反向理解：-1 表示完全相同。',
      '返回值是 long，和 int 变量比较时要注意提升规则。',
      'mismatch 只比较内容，不比较权限、时间戳等属性。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '写一个方法，返回两份内容第一处差异的行号（提示：按行切分后逐行比较）。',
        hint: '先用 Files.readAllLines 读入，再循环比较，找不到就返回 -1。',
        answer:
            'for (int i = 0; i < Math.min(a.size(), b.size()); i++) { if (!a.get(i).equals(b.get(i))) return i + 1; } return a.size() == b.size() ? -1 : Math.min(a.size(), b.size()) + 1;',
      ),
    ],
  ),
  JavaTopic(
    id: 167,
    level: 'beginner',
    title: 'Java 167：按行读取与行号输出',
    summary: 'readAllLines 的换行处理、空行保留，以及配合 Stream 做行过滤。',
    concepts: <String>['readAllLines', '换行符', 'Stream 过滤', 'UTF-8'],
    objective: '能读入小文本文件并带行号输出，理解空行也会成为一个元素。',
    explain:
        '`Files.readAllLines(path, charset)` 把整个文件读成 `List<String>`，'
        '行尾的 `\\n`、`\\r\\n`、`\\r` 都会被识别为行分隔符并且不保留在结果里。'
        '文件末尾的换行不会产生额外的空元素，但中间的空行会产生空字符串元素。'
        '它适合小文件；大文件应该用 `Files.lines` 或 `BufferedReader` 边读边处理，'
        '避免一次性占用大量内存。',
    code: r'''import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-lines-");
        try {
            Path log = dir.resolve("app.log");
            Files.writeString(log, "INFO start\nWARN slow\nERROR disk full\n",
                    StandardCharsets.UTF_8);
            List<String> lines = Files.readAllLines(log, StandardCharsets.UTF_8);
            System.out.println("lines=" + lines.size());
            for (int i = 0; i < lines.size(); i++) {
                System.out.println((i + 1) + ": " + lines.get(i));
            }
            long errors = lines.stream().filter(line -> line.startsWith("ERROR")).count();
            System.out.println("errors=" + errors);
            Path blank = dir.resolve("blank.txt");
            Files.writeString(blank, "a\n\nb\n");
            System.out.println("blankKept=" + Files.readAllLines(blank).size());
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'lines=3\n'
        '1: INFO start\n'
        '2: WARN slow\n'
        '3: ERROR disk full\n'
        'errors=1\n'
        'blankKept=3',
    pitfalls: <String>[
      '不指定 charset 会使用平台默认编码，跨平台可能乱码。',
      '空行是长度为 0 的元素，不是 null，判断要用 isEmpty。',
      'readAllLines 会把整个文件载入内存，大文件应改用流式读取。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '统计每个日志级别出现的次数，并按级别字母序输出。',
        hint: '用 split(" ")[0] 取级别，收集到 TreeMap 后遍历输出。',
        answer:
            'Map<String, Long> counts = new TreeMap<>(); for (String line : lines) { counts.merge(line.split(" ")[0], 1L, Long::sum); } counts.forEach((k, v) -> System.out.println(k + "=" + v));',
      ),
    ],
  ),
  JavaTopic(
    id: 168,
    level: 'intermediate',
    title: 'Java 168：缓冲流分块复制',
    summary: 'BufferedInputStream/OutputStream 配合 8KB 缓冲区复制字节，并校验字节数。',
    concepts: <String>[
      'BufferedInputStream',
      'BufferedOutputStream',
      'read 返回值',
      '字节计数',
    ],
    objective: '能手写分块复制循环，正确使用 read 的返回值而不是假设一次读满。',
    explain:
        '`InputStream.read(byte[])` 返回实际读到的字节数，可能小于数组长度，'
        '流结束时返回 `-1`。循环必须用 `write(buffer, 0, read)` 只写出有效部分，'
        '否则会把上一次的残留字节写进目标文件。'
        '`BufferedInputStream`/`BufferedOutputStream` 在底层流之上再加一层缓冲区，'
        '减少系统调用次数。try-with-resources 会按「后开先关」的顺序关闭两个流。',
    code: r'''import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-buffer-");
        try {
            Path source = dir.resolve("in.txt");
            Path target = dir.resolve("out.txt");
            Files.writeString(source, "分块复制 8KB 缓冲区示例", StandardCharsets.UTF_8);
            long copied = 0;
            try (InputStream in = new BufferedInputStream(Files.newInputStream(source));
                    OutputStream out = new BufferedOutputStream(Files.newOutputStream(target))) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                    copied += read;
                }
            }
            System.out.println("copied=" + copied);
            System.out.println("content=" + Files.readString(target, StandardCharsets.UTF_8));
            System.out.println("sizeMatch=" + (copied == Files.size(target)));
            System.out.println("bufferUnused=" + (copied < 8192));
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'copied=32\n'
        'content=分块复制 8KB 缓冲区示例\n'
        'sizeMatch=true\n'
        'bufferUnused=true',
    pitfalls: <String>[
      '写成 out.write(buffer) 会把缓冲区里未使用的尾部字节也写出去。',
      '用 read() 单字节读取再循环虽然正确，但性能差很多。',
      '忘记关闭输出流时，缓冲区里最后一批数据可能没有落盘。',
      '字节流复制不需要字符集，但如果用 Reader/Writer 读写文本，必须显式指定 UTF-8。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把缓冲区改成 4 字节，观察 copied 是否变化，并解释为什么内容仍然正确。',
        hint: '缓冲区大小只影响循环次数，不影响总字节数。',
        answer: 'byte[] buffer = new byte[4]; 循环会执行 8 次，copied 仍是 32。',
      ),
    ],
  ),
  JavaTopic(
    id: 169,
    level: 'advanced',
    title: 'Java 169：RandomAccessFile 定位读写',
    summary: '用 seek 在文件任意位置读写，构造带头部、整数和长整数的二进制记录。',
    concepts: <String>['RandomAccessFile', 'seek', 'readFully', '二进制记录'],
    objective: '能写出固定布局的二进制文件，并能在任意偏移处读回指定字段。',
    explain:
        '`RandomAccessFile` 同时支持读和写，并且有文件指针：'
        '`seek(long)` 把指针移到指定字节偏移，之后 `readInt`/`writeLong` 等按大端字节序读写。'
        '`readFully(byte[])` 保证读满数组，读不到就抛 `EOFException`，'
        '比 `read` 更适合解析固定长度头部。'
        '这类「头部 + 定长字段」的布局是很多二进制格式的基础。',
    code: r'''import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-raf-");
        try {
            Path file = dir.resolve("data.bin");
            try (RandomAccessFile writer = new RandomAccessFile(file.toFile(), "rw")) {
                writer.write("HEADER:0001".getBytes(StandardCharsets.US_ASCII));
                writer.writeInt(42);
                writer.writeLong(1_700_000_000_000L);
            }
            try (RandomAccessFile reader = new RandomAccessFile(file.toFile(), "r")) {
                byte[] header = new byte[11];
                reader.readFully(header);
                System.out.println("header=" + new String(header, StandardCharsets.US_ASCII));
                System.out.println("number=" + reader.readInt());
                System.out.println("stamp=" + reader.readLong());
                System.out.println("length=" + reader.length());
                reader.seek(7);
                byte[] sequence = new byte[4];
                reader.readFully(sequence);
                System.out.println("sequence="
                        + new String(sequence, StandardCharsets.US_ASCII));
            }
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'header=HEADER:0001\n'
        'number=42\n'
        'stamp=1700000000000\n'
        'length=23\n'
        'sequence=0001',
    pitfalls: <String>[
      'readInt/writeInt 固定使用大端序，跨语言对接时要确认字节序。',
      '用 read 而不是 readFully 可能只读到一部分字节，解析就错位了。',
      'seek 超出文件末尾后写入会在中间填 0，形成「稀疏文件」。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '在偏移 0 处改写头部为 "HEADER:0002"，再读回验证。',
        hint: '用 "rw" 模式打开，seek(0) 后 write 相同长度的 ASCII 字节。',
        answer:
            'writer.seek(0); writer.write("HEADER:0002".getBytes(StandardCharsets.US_ASCII));',
      ),
    ],
  ),
  JavaTopic(
    id: 170,
    level: 'intermediate',
    title: 'Java 170：ByteBuffer 的四个基本量',
    summary: 'position/limit/capacity 的含义，以及 put、flip、compact、clear 的状态变化。',
    concepts: <String>['ByteBuffer', 'position', 'limit', 'flip'],
    objective: '能画出 ByteBuffer 在写模式和读模式下 position/limit 的位置，并解释 flip 的作用。',
    explain:
        '`ByteBuffer` 有三个关键值：`capacity` 是总容量，固定不变；'
        '`position` 是下一个要读/写的下标；`limit` 是读/写的边界。'
        '写模式下 limit 等于 capacity；写完后 `flip()` 把 limit 设为当前 position、'
        'position 归零，切换到读模式。读了一部分后想继续追加，用 `compact()`：'
        '它把未读字节移到开头，position 设为剩余字节数，limit 恢复为 capacity。'
        '`clear()` 不擦除数据，只是把 position 归零、limit 设为 capacity。',
    code: r'''import java.nio.ByteBuffer;

public class Main {
    public static void main(String[] args) {
        ByteBuffer buffer = ByteBuffer.allocate(16);
        System.out.println("capacity=" + buffer.capacity());
        buffer.put((byte) 'A').put((byte) 'B').put((byte) 'C');
        System.out.println("afterPut=" + buffer.position() + "/" + buffer.limit());
        buffer.flip();
        System.out.println("afterFlip=" + buffer.position() + "/" + buffer.limit());
        System.out.println("first=" + (char) buffer.get());
        System.out.println("remaining=" + buffer.remaining());
        buffer.compact();
        System.out.println("afterCompact=" + buffer.position() + "/" + buffer.limit());
        buffer.clear();
        System.out.println("afterClear=" + buffer.position() + "/" + buffer.limit());
        System.out.println("hasRemaining=" + buffer.hasRemaining());
    }
}''',
    output:
        'capacity=16\n'
        'afterPut=3/16\n'
        'afterFlip=0/3\n'
        'first=A\n'
        'remaining=2\n'
        'afterCompact=2/16\n'
        'afterClear=0/16\n'
        'hasRemaining=true',
    pitfalls: <String>[
      '写完不 flip 直接 get，读到的是位置 3 之后的未初始化字节。',
      'clear 不会清零内容，只是重置指针，误以为数据被删除是常见误解。',
      'compact 之后原来已读的字节被丢弃，未读字节前移，偏移量会变化。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '在 flip 之后连续 get 三次，打印每次的 remaining，观察第三次之后的值。',
        hint: '读空之后 remaining 为 0，再 get 会抛 BufferUnderflowException。',
        answer:
            'System.out.println(buffer.get()); System.out.println(buffer.get()); System.out.println(buffer.get()); System.out.println(buffer.remaining()); // 0',
      ),
    ],
  ),
  JavaTopic(
    id: 171,
    level: 'advanced',
    title: 'Java 171：ByteBuffer 视图与字节序',
    summary: '用 order() 切换大小端，用 asIntBuffer 把字节缓冲区当成 int 数组读取。',
    concepts: <String>['ByteOrder', 'asIntBuffer', '视图缓冲区', '大端小端'],
    objective: '能解释同一段字节在不同字节序下会被解析成什么整数，并会创建类型化视图。',
    explain:
        '`ByteBuffer.order(ByteOrder)` 决定 `putInt`/`getInt` 等方法的字节顺序：'
        '`BIG_ENDIAN` 把最高有效字节放在最前，`LITTLE_ENDIAN` 相反。'
        'x86 与 ARM 常用小端，而网络协议和 Java 的 `DataOutputStream` 固定用大端。'
        '`asIntBuffer()` 返回一个共享同一块内存的 `IntBuffer` 视图：'
        '它的 position 从 0 开始、limit 等于剩余字节数除以 4，'
        '读写视图会直接改动原始缓冲区，不会复制数据。',
    code: r'''import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.IntBuffer;

public class Main {
    public static void main(String[] args) {
        ByteBuffer big = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN);
        big.putInt(0x01020304);
        big.flip();
        System.out.print("big=");
        while (big.hasRemaining()) {
            System.out.print(String.format("%02X", big.get() & 0xFF));
        }
        System.out.println();
        ByteBuffer little = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN);
        little.putInt(0x01020304);
        little.flip();
        System.out.print("little=");
        while (little.hasRemaining()) {
            System.out.print(String.format("%02X", little.get() & 0xFF));
        }
        System.out.println();
        ByteBuffer numbers = ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN);
        numbers.putInt(7).putInt(9).putInt(11);
        numbers.flip();
        IntBuffer view = numbers.asIntBuffer();
        System.out.println("viewLimit=" + view.limit());
        System.out.println("firstTwo=" + view.get() + "," + view.get());
        System.out.println("viewPosition=" + view.position());
    }
}''',
    output:
        'big=01020304\n'
        'little=04030201\n'
        'viewLimit=3\n'
        'firstTwo=7,9\n'
        'viewPosition=2',
    pitfalls: <String>[
      'get() 读到的是有符号 byte，转十六进制要先 & 0xFF 再格式化。',
      '视图缓冲区的字节序在创建时就固定了，之后改父缓冲区的 order 不影响已有视图。',
      '视图的 limit 是「剩余字节数 / 元素大小」向下取整，尾部多出的字节会被忽略。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 12 字节缓冲区的字节数改成 10，观察 viewLimit 变成多少。',
        hint: '10 / 4 向下取整为 2。',
        answer: 'ByteBuffer.allocate(10) 时 asIntBuffer().limit() == 2。',
      ),
    ],
  ),
  JavaTopic(
    id: 172,
    level: 'advanced',
    title: 'Java 172：内存映射文件读取',
    summary: '用 FileChannel.map 把文件映射成 MappedByteBuffer，按定长记录顺序解析。',
    concepts: <String>[
      'MappedByteBuffer',
      'FileChannel.map',
      'MapMode',
      '定长记录',
    ],
    objective: '能用只读内存映射读取二进制文件，理解它和普通流读取的差别。',
    explain:
        '`FileChannel.map(MapMode.READ_ONLY, 0, size)` 把文件区域映射到进程地址空间，'
        '返回的 `MappedByteBuffer` 可以直接 `getInt`/`get`，不必显式 read。'
        '操作系统负责按需换页，所以处理大文件时内存压力小于整读。'
        '映射是只读的，写入会抛 `ReadOnlyBufferException`。'
        '映射期间文件长度不能变，因此适合读取固定布局的记录文件，'
        '写入路径通常仍然用流或通道。'
        '另外，映射会占住文件：缓冲区没被释放前，Windows 上删除会报 AccessDeniedException。'
        '所以这里把映射放在一个独立方法里，返回后引用失效，再 `System.gc()` 让 Cleaner 解除映射；'
        '通道同时用 `StandardOpenOption.DELETE_ON_CLOSE`（Linux/OHOS 上 open 时就 unlink），'
        '最后再递归删除目录，并用 `deleteOnExit` 兑底。'
        '删除时机与平台有关，所以输出里不打印任何删除结果。',
    code: r'''import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Comparator;
import java.util.stream.Stream;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-mmap-");
        dir.toFile().deleteOnExit();
        try {
            Path file = dir.resolve("records.bin");
            ByteBuffer payload = ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN);
            payload.putInt(1).putInt(10);
            payload.putInt(2).putInt(20);
            payload.putInt(3).putInt(30);
            Files.write(file, payload.array());
            readMapped(file);
            System.gc();
        } finally {
            cleanup(dir);
        }
    }

    static void readMapped(Path file) throws IOException {
        try (FileChannel channel = FileChannel.open(file, StandardOpenOption.READ,
                StandardOpenOption.DELETE_ON_CLOSE)) {
            MappedByteBuffer mapped = channel.map(FileChannel.MapMode.READ_ONLY, 0,
                    channel.size());
            mapped.order(ByteOrder.BIG_ENDIAN);
            int sum = 0;
            while (mapped.remaining() >= 8) {
                int id = mapped.getInt();
                int value = mapped.getInt();
                sum += value;
                System.out.println("id=" + id + " value=" + value);
            }
            System.out.println("sum=" + sum);
            System.out.println("capacity=" + mapped.capacity());
            System.out.println("readOnly=" + mapped.isReadOnly());
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }
}''',
    output:
        'id=1 value=10\n'
        'id=2 value=20\n'
        'id=3 value=30\n'
        'sum=60\n'
        'capacity=24\n'
        'readOnly=true',
    pitfalls: <String>[
      '映射大小必须小于等于文件当前长度，否则抛 IOException。',
      '映射是只读时写入会抛 ReadOnlyBufferException，不是静默失败。',
      '映射过的文件在映射未释放前无法删除，要先丢掉引用并触发 GC，再用 deleteOnExit 兑底。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给每条记录加一个 4 字节的校验位，让记录变成 12 字节并重新解析。',
        hint: 'putInt(id).putInt(value).putInt(id ^ value) 写入，读取时跳过第三个 int。',
        answer:
            '写入时多 putInt(checksum)；读取时 int id = getInt(), value = getInt(); getInt() 跳过校验位。',
      ),
    ],
  ),
  JavaTopic(
    id: 173,
    level: 'intermediate',
    title: 'Java 173：DataOutputStream 写二进制协议',
    summary: '把不同类型按固定顺序写进字节数组，并逐个字段读回验证。',
    concepts: <String>[
      'DataOutputStream',
      'DataInputStream',
      'writeUTF',
      '字节长度',
    ],
    objective: '能算出「固定长度字段 + 变长字符串」记录的总字节数，并正确读回。',
    explain:
        '`DataOutputStream` 把基本类型按大端序写入，`writeUTF` 用「2 字节长度 + 修改版 UTF-8 字节」保存字符串。'
        '它不能单独用，必须包在 `ByteArrayOutputStream`、文件流或通道流之上。'
        '读取时必须严格按写入顺序调用对应方法，读错类型会得到完全不同的值而不是报错。'
        '`ByteArrayInputStream.available()` 可以用来确认有没有多余或缺失字节。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

public class Main {
    public static void main(String[] args) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (DataOutputStream out = new DataOutputStream(bytes)) {
            out.writeByte(1);
            out.writeShort(300);
            out.writeInt(70_000);
            out.writeLong(9_000_000_000L);
            out.writeUTF("日志");
            out.writeBoolean(true);
        }
        byte[] payload = bytes.toByteArray();
        System.out.println("size=" + payload.length);
        try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(payload))) {
            System.out.println("flag=" + in.readByte());
            System.out.println("code=" + in.readShort());
            System.out.println("count=" + in.readInt());
            System.out.println("stamp=" + in.readLong());
            System.out.println("label=" + in.readUTF());
            System.out.println("ok=" + in.readBoolean());
            System.out.println("left=" + in.available());
        }
    }
}''',
    output:
        'size=24\n'
        'flag=1\n'
        'code=300\n'
        'count=70000\n'
        'stamp=9000000000\n'
        'label=日志\n'
        'ok=true\n'
        'left=0',
    pitfalls: <String>[
      'readByte 是有符号的，超过 127 的字节读回来是负数，需要 & 0xFF。',
      'writeUTF 只支持 65535 字节以内的字符串，超长要自己写长度前缀。',
      '读完不检查 available，字段错位时不会立刻报错，错误会一直传播到后面。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 writeUTF 换成「先写 int 长度再写 UTF-8 字节」，说明为什么能突破 65535 限制。',
        hint:
            'out.writeInt(nameBytes.length); out.write(nameBytes); 读取时先 readInt 再 readFully。',
        answer:
            'int length = in.readInt(); byte[] raw = new byte[length]; in.readFully(raw); String name = new String(raw, StandardCharsets.UTF_8);',
      ),
    ],
  ),
  JavaTopic(
    id: 174,
    level: 'advanced',
    title: 'Java 174：解析自定义二进制记录',
    summary: '用「长度前缀 + 结束标记」读取记录列表，配合 readFully 防止半包。',
    concepts: <String>['记录格式', 'readUnsignedByte', 'readFully', 'EOF 处理'],
    objective: '能设计并实现一个可扩展的二进制记录列表格式，并安全处理读到结尾的情况。',
    explain:
        '自定义二进制格式要同时解决三件事：字段顺序、变长字段的长度、以及列表何时结束。'
        '这里用 `writeByte(name.length)` 给字符串加 1 字节长度前缀，'
        '用 id 为负数作为列表结束标记。'
        '`readUnsignedByte()` 返回 0..255，避免负数长度；'
        '`readFully(byte[])` 保证读满，比循环 `read` 更不容易出错。'
        '生产格式通常还会加魔数、版本号和总长度，便于向前兼容。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class Main {
    static class Item {
        final int id;
        final String name;
        final double price;

        Item(int id, String name, double price) {
            this.id = id;
            this.name = name;
            this.price = price;
        }
    }

    public static void main(String[] args) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (DataOutputStream out = new DataOutputStream(bytes)) {
            writeItem(out, new Item(1, "键盘", 199.0));
            writeItem(out, new Item(2, "鼠标", 89.5));
            out.writeInt(-1);
        }
        System.out.println("bytes=" + bytes.size());
        int count = 0;
        double sum = 0.0;
        try (DataInputStream in = new DataInputStream(
                new ByteArrayInputStream(bytes.toByteArray()))) {
            while (true) {
                int id = in.readInt();
                if (id < 0) {
                    break;
                }
                byte[] raw = new byte[in.readUnsignedByte()];
                in.readFully(raw);
                double price = in.readDouble();
                count++;
                sum += price;
                System.out.println("item=" + id + " " + new String(raw, StandardCharsets.UTF_8));
            }
        }
        System.out.println("count=" + count);
        System.out.println("sum=" + sum);
    }

    static void writeItem(DataOutputStream out, Item item) throws IOException {
        byte[] name = item.name.getBytes(StandardCharsets.UTF_8);
        out.writeInt(item.id);
        out.writeByte(name.length);
        out.write(name);
        out.writeDouble(item.price);
    }
}''',
    output:
        'bytes=42\n'
        'item=1 键盘\n'
        'item=2 鼠标\n'
        'count=2\n'
        'sum=288.5',
    pitfalls: <String>[
      'readByte 会返回负数，用它当数组长度会抛 NegativeArraySizeException，务必用 readUnsignedByte。',
      '结束标记必须和真实字段取值范围不重叠，否则正常数据会被当成结束。',
      'double 在二进制格式里占 8 字节且是 IEEE 754，不代表金额精确，金额应改存分或用定点。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把价格从 double 改成「以分为单位的 int」，重新计算总字节数。',
        hint: '199.0 元 = 19900 分，用 writeInt 写 4 字节。',
        answer:
            '每条记录由 4(id) + 1(len) + n(name) + 8(double) 变成 4 + 1 + n + 4；两条记录总长减少 8 字节。',
      ),
    ],
  ),
  JavaTopic(
    id: 175,
    level: 'intermediate',
    title: 'Java 175：手写大小端转换',
    summary: '用移位与掩码实现 int 与字节数组互转，理解 Integer.reverseBytes 的作用。',
    concepts: <String>['位移', '掩码', '大端小端', 'reverseBytes'],
    objective: '能不依赖 ByteBuffer 手写 int 与 byte[] 的双向转换，并解释掩码为什么必须存在。',
    explain:
        '`value >>> (8 * (3 - i))` 依次取出最高到最低的 8 位，强转成 `byte` 会截断到低 8 位，'
        '这就是大端排列。小端则从 `8 * 0` 开始，先放最低字节。'
        '反向解码时必须写 `(b & 0xFF)`：`b` 是带符号的 8 位值，'
        '负数直接参与 `|` 运算会把高位全变成 1。'
        '`Integer.reverseBytes` 等价于把一个 int 的四个字节整体倒序。',
    code: r'''public class Main {
    public static void main(String[] args) {
        int value = 0x0A0B0C0D;
        byte[] big = new byte[4];
        byte[] little = new byte[4];
        for (int i = 0; i < 4; i++) {
            big[i] = (byte) (value >>> (8 * (3 - i)));
            little[i] = (byte) (value >>> (8 * i));
        }
        System.out.println("big=" + toHex(big));
        System.out.println("little=" + toHex(little));
        System.out.println("decodeBig=" + decodeBig(big));
        System.out.println("decodeLittle=" + decodeLittle(little));
        System.out.println("reverseBytes=" + Integer.toHexString(Integer.reverseBytes(value)));
        byte[] pair = new byte[] {0x00, 0x0A, 0x01, 0x2C};
        System.out.println("uint16=" + (((pair[2] & 0xFF) << 8) | (pair[3] & 0xFF)));
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder();
        for (byte b : data) {
            builder.append(String.format("%02X", b & 0xFF));
        }
        return builder.toString();
    }

    static int decodeBig(byte[] data) {
        int result = 0;
        for (byte b : data) {
            result = (result << 8) | (b & 0xFF);
        }
        return result;
    }

    static int decodeLittle(byte[] data) {
        int result = 0;
        for (int i = data.length - 1; i >= 0; i--) {
            result = (result << 8) | (data[i] & 0xFF);
        }
        return result;
    }
}''',
    output:
        'big=0A0B0C0D\n'
        'little=0D0C0B0A\n'
        'decodeBig=168496141\n'
        'decodeLittle=168496141\n'
        'reverseBytes=d0c0b0a\n'
        'uint16=300',
    pitfalls: <String>[
      '忘记 & 0xFF 时，0x0D 这类字节没问题，但 0x8A 会被当成负数并污染高位。',
      '用 >> 而不是 >>> 做无符号右移，负数的符号位会被带进来。',
      '用 int 拼接 4 字节没问题，拼接 8 字节必须用 long，否则高位被丢弃。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 value 改成 0xFF000001，观察 toHex 与 reverseBytes 的输出变化。',
        hint: '最高字节全 1 会让 reverseBytes 之后的最低位变成 ff。',
        answer:
            'big=FF000001, little=010000FF, Integer.reverseBytes 得到 10000ff。',
      ),
    ],
  ),
  JavaTopic(
    id: 176,
    level: 'intermediate',
    title: 'Java 176：Charset 与严格解码',
    summary: '用 CharsetDecoder 的 REPORT/REPLACE 策略区分「合法字节」与「损坏字节」。',
    concepts: <String>[
      'Charset',
      'CharsetDecoder',
      'CodingErrorAction',
      'CharacterCodingException',
    ],
    objective: '能用严格解码判断一段字节是否是合法 UTF-8，并知道宽松解码会静默替换。',
    explain:
        '`String.getBytes(charset)` 和 `new String(bytes, charset)` 使用的是宽松策略：'
        '遇到无法映射的字符会变成 `?` 或 U+FFFD，不会报错。'
        '需要「这段字节到底合法吗」的判断时，必须用 `CharsetDecoder`：'
        '`onMalformedInput(REPORT)` 让非法字节抛 `CharacterCodingException`，'
        '`REPLACE` 则用一个替换字符顶上。'
        '`REPORT` 才是导入文件、解析协议时应该用的默认策略。',
    code: r'''import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) {
        Charset utf8 = StandardCharsets.UTF_8;
        System.out.println("name=" + utf8.name());
        System.out.println("utf8Bytes=" + "中文".getBytes(utf8).length);
        System.out.println("utf16Bytes=" + "中文".getBytes(StandardCharsets.UTF_16LE).length);
        System.out.println("asciiBytes=" + "AB".getBytes(StandardCharsets.US_ASCII).length);
        System.out.println("latin1=" + new String("AB".getBytes(StandardCharsets.ISO_8859_1),
                StandardCharsets.ISO_8859_1));
        byte[] broken = new byte[] {(byte) 0xFF};
        CharsetDecoder strict = utf8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT);
        try {
            CharBuffer decoded = strict.decode(ByteBuffer.wrap(broken));
            System.out.println("strict=" + decoded);
        } catch (CharacterCodingException error) {
            System.out.println("strict=CharacterCodingException");
        }
        CharsetDecoder lenient = utf8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPLACE)
                .onUnmappableCharacter(CodingErrorAction.REPLACE);
        try {
            CharBuffer decoded = lenient.decode(ByteBuffer.wrap(broken));
            System.out.println("lenient=" + decoded.length() + ":" + decoded);
        } catch (CharacterCodingException error) {
            System.out.println("lenient=CharacterCodingException");
        }
    }
}''',
    output:
        'name=UTF-8\n'
        'utf8Bytes=6\n'
        'utf16Bytes=4\n'
        'asciiBytes=2\n'
        'latin1=AB\n'
        'strict=CharacterCodingException\n'
        'lenient=1:\uFFFD',
    pitfalls: <String>[
      'new String(bytes, UTF_8) 遇到坏字节不会报错，判断合法性必须用 REPORT 解码器。',
      'CharsetDecoder 不是线程安全的，每次使用要 newDecoder() 新建。',
      '只用 java.base 里的字符集（UTF-8/UTF-16/ISO-8859-1/US-ASCII）能保证离线运行时一定可用。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 broken 改成 UTF-8 截断序列 {0xE4, 0xB8}，观察严格与宽松解码的结果。',
        hint: '两个字节只够三分之一，仍然是 malformed。',
        answer: '严格解码抛 CharacterCodingException，宽松解码得到长度为 1 的替换字符。',
      ),
    ],
  ),
  JavaTopic(
    id: 177,
    level: 'intermediate',
    title: 'Java 177：UTF-8 BOM 的识别与剥离',
    summary: '检测 EF BB BF 开头、理解 BOM 会被解码成 U+FEFF，并安全地剥掉它。',
    concepts: <String>['BOM', 'UTF-8', 'U+FEFF', '字节前缀'],
    objective: '能判断一段 UTF-8 数据是否带 BOM，并在解析前正确剥离。',
    explain:
        'UTF-8 本身没有字节序问题，但 Windows 记事本等工具会在文件开头写入 `EF BB BF`，'
        '解码之后就是 U+FEFF（零宽不换行空格）。'
        'Java 的 `new String(bytes, UTF_8)` 不会自动去掉它，'
        '结果就是字符串长度多 1、首字符不是预期的字母或汉字，'
        '常见症状是 JSON 解析报「意外的 BOM」或第一行比较失败。'
        '正确做法是在解码前检查前三字节并剥离，而不是在字符串里去掉 U+FEFF。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        byte[] text = "标题".getBytes(StandardCharsets.UTF_8);
        byte[] withBom = new byte[3 + text.length];
        withBom[0] = (byte) 0xEF;
        withBom[1] = (byte) 0xBB;
        withBom[2] = (byte) 0xBF;
        System.arraycopy(text, 0, withBom, 3, text.length);
        System.out.println("withBomBytes=" + withBom.length);
        System.out.println("prefix=" + (withBom[0] & 0xFF) + "," + (withBom[1] & 0xFF)
                + "," + (withBom[2] & 0xFF));
        String decoded = new String(withBom, StandardCharsets.UTF_8);
        System.out.println("firstCode=" + (int) decoded.charAt(0));
        System.out.println("lengthWithBom=" + decoded.length());
        byte[] stripped = stripBom(withBom);
        System.out.println("strippedLength=" + new String(stripped, StandardCharsets.UTF_8).length());
        System.out.println("sameAsOriginal=" + Arrays.equals(stripped, text));
        System.out.println("plainHasBom=" + hasBom(text));
    }

    static boolean hasBom(byte[] data) {
        return data.length >= 3
                && (data[0] & 0xFF) == 0xEF
                && (data[1] & 0xFF) == 0xBB
                && (data[2] & 0xFF) == 0xBF;
    }

    static byte[] stripBom(byte[] data) {
        if (!hasBom(data)) {
            return data;
        }
        byte[] result = new byte[data.length - 3];
        System.arraycopy(data, 3, result, 0, result.length);
        return result;
    }
}''',
    output:
        'withBomBytes=9\n'
        'prefix=239,187,191\n'
        'firstCode=65279\n'
        'lengthWithBom=3\n'
        'strippedLength=2\n'
        'sameAsOriginal=true\n'
        'plainHasBom=false',
    pitfalls: <String>[
      '比较前三字节时要 & 0xFF，否则负的 byte 永远不等于 0xEF。',
      '只在字符串层面去掉 \\uFEFF 是错的：它后面可能还有真实的零宽字符。',
      'UTF-16 的 BOM 是 2 字节，检测逻辑和 UTF-8 完全不同，不能复用。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '写一个方法，把带 BOM 的字节数组转成不带 BOM 的字符串。',
        hint: '先 stripBom 再 new String(..., UTF_8)。',
        answer:
            'String clean = new String(stripBom(withBom), StandardCharsets.UTF_8);',
      ),
    ],
  ),
  JavaTopic(
    id: 178,
    level: 'intermediate',
    title: 'Java 178：乱码是怎么产生的',
    summary: '用错误的字符集解码、再正确解码还原，理解替换字符与不可逆丢失。',
    concepts: <String>['乱码', '替换字符', '可逆解码', '编码探测'],
    objective: '能解释「用错编码解码」与「编码时字符不可映射」两种不同的数据损坏。',
    explain:
        '乱码有两种成因，性质完全不同。'
        '第一种是解码用错字符集：UTF-8 字节被当成 ISO-8859-1 读出，'
        '得到一串「看起来像 Latin 字母」的错误字符，但只要按同样字节重新以 UTF-8 解码就能完全还原。'
        '第二种是编码时目标字符集表示不了该字符，例如把中文写进 US-ASCII，'
        '每个字符被替换成 `?`，字节已经变了，无法还原。'
        '排查时先确认「是不是可逆」，可逆就换解码器，不可逆只能找回原始文件。',
    code: r'''import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) {
        String text = "成绩 A+";
        byte[] utf8 = text.getBytes(StandardCharsets.UTF_8);
        System.out.println("utf8Bytes=" + utf8.length);
        String wrong = new String(utf8, StandardCharsets.ISO_8859_1);
        System.out.println("wrongLength=" + wrong.length());
        System.out.println("firstCode=" + (int) wrong.charAt(0));
        String restored = new String(wrong.getBytes(StandardCharsets.ISO_8859_1),
                StandardCharsets.UTF_8);
        System.out.println("restored=" + restored);
        System.out.println("reversible=" + restored.equals(text));
        byte[] lossy = text.getBytes(StandardCharsets.US_ASCII);
        System.out.println("asciiBytes=" + lossy.length);
        System.out.println("lossy=" + new String(lossy, StandardCharsets.US_ASCII));
        System.out.println("validUtf8=" + isValidUtf8(utf8));
        System.out.println("validBroken=" + isValidUtf8(new byte[] {(byte) 0xC3}));
    }

    static boolean isValidUtf8(byte[] data) {
        try {
            StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(data));
            return true;
        } catch (CharacterCodingException error) {
            return false;
        }
    }
}''',
    output:
        'utf8Bytes=9\n'
        'wrongLength=9\n'
        'firstCode=230\n'
        'restored=成绩 A+\n'
        'reversible=true\n'
        'asciiBytes=5\n'
        'lossy=?? A+\n'
        'validUtf8=true\n'
        'validBroken=false',
    pitfalls: <String>[
      'ISO-8859-1 是「单字节透明」的，所有字节都能映射，所以用它解码永远不报错，最容易被误用。',
      'US-ASCII 编码时不可映射的字符变成 ?，这是有损操作，不能再还原。',
      '判断字节是否为合法 UTF-8 要用 REPORT 策略，不能靠 new String 的结果。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 text 换成只有 ASCII 的内容，观察 asciiBytes 与 utf8Bytes 是否相等。',
        hint: 'ASCII 字符在 UTF-8 下就是 1 字节，长度相同。',
        answer: 'text = "grade A+"; 时两个长度都等于 8。',
      ),
    ],
  ),
  JavaTopic(
    id: 179,
    level: 'advanced',
    title: 'Java 179：手写百分号编码',
    summary: '按 RFC 3986 保留非保留字符，其余字节转成 %XX，并实现对应的解码。',
    concepts: <String>['percent-encoding', 'RFC 3986', 'UTF-8 字节', '解码'],
    objective: '能自己实现 URL 的编码与解码，并说明为什么编码前必须先转成 UTF-8 字节。',
    explain:
        '百分号编码的规则很简单：`A-Z a-z 0-9 - _ . ~` 原样保留，'
        '其余每个 UTF-8 字节写成 `%` 加两位大写十六进制。'
        '必须先编码成字节再处理，因为中文一个字符会变成 3 个 `%XX`，'
        '直接对 `char` 编码会得到错误的码位。'
        '解码时把 `%XX` 还原成字节，最后整体按 UTF-8 解码，'
        '否则多个 `%XX` 拼不成一个汉字。'
        '表单提交里的 `+` 代表空格是另一套规则，标准 URL 编码中 `+` 必须写成 `%2B`。',
    code: r'''import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) {
        String text = "a b+c/测试";
        String encoded = encode(text);
        System.out.println("encoded=" + encoded);
        System.out.println("decoded=" + decode(encoded));
        System.out.println("roundTrip=" + decode(encoded).equals(text));
        System.out.println("query=" + encode("k=1&v=2"));
        System.out.println("reserved=" + encode("-_.~"));
        System.out.println("emptyLen=" + encode("").length());
    }

    static String encode(String text) {
        StringBuilder out = new StringBuilder();
        for (byte b : text.getBytes(StandardCharsets.UTF_8)) {
            int value = b & 0xFF;
            if (isUnreserved(value)) {
                out.append((char) value);
            } else {
                out.append('%')
                        .append(hex(value >> 4))
                        .append(hex(value & 0xF));
            }
        }
        return out.toString();
    }

    static String decode(String text) {
        byte[] buffer = new byte[text.length()];
        int length = 0;
        int index = 0;
        while (index < text.length()) {
            char current = text.charAt(index);
            if (current == '%' && index + 2 < text.length()) {
                int high = Character.digit(text.charAt(index + 1), 16);
                int low = Character.digit(text.charAt(index + 2), 16);
                if (high >= 0 && low >= 0) {
                    buffer[length++] = (byte) ((high << 4) | low);
                    index += 3;
                    continue;
                }
            }
            buffer[length++] = (byte) current;
            index++;
        }
        return new String(buffer, 0, length, StandardCharsets.UTF_8);
    }

    static boolean isUnreserved(int value) {
        return (value >= 'A' && value <= 'Z')
                || (value >= 'a' && value <= 'z')
                || (value >= '0' && value <= '9')
                || value == '-' || value == '_' || value == '.' || value == '~';
    }

    static char hex(int nibble) {
        return Character.toUpperCase(Character.forDigit(nibble, 16));
    }
}''',
    output:
        'encoded=a%20b%2Bc%2F%E6%B5%8B%E8%AF%95\n'
        'decoded=a b+c/测试\n'
        'roundTrip=true\n'
        'query=k%3D1%26v%3D2\n'
        'reserved=-_.~\n'
        'emptyLen=0',
    pitfalls: <String>[
      '对 char 而不是字节做编码，会让中文变成 4 位的 \\uXXXX 形式而不是 UTF-8 的 %XX。',
      '解码时逐个 %XX 单独 new String 会得到乱码，必须拼齐字节再整体解码。',
      '不完整的 % 序列（如 "%G1"）要原样保留，否则会把非法输入变成异常。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '支持「+ 解码成空格」的表单风格，并说明它和标准 URL 编码的冲突。',
        hint: '在 decode 里遇到 + 时写入 0x20，编码端则要把空格写成 +。',
        answer:
            'if (current == \'+\') { buffer[length++] = (byte) \' \'; index++; continue; } 但这样原文里真实的 + 必须编码为 %2B。',
      ),
    ],
  ),
  JavaTopic(
    id: 180,
    level: 'beginner',
    title: 'Java 180：Base64 编解码',
    summary: '用 java.util.Base64 把二进制转成可打印文本，理解填充符 = 与严格解码。',
    concepts: <String>['Base64', '编码器', '填充符', 'IllegalArgumentException'],
    objective: '能说出 Base64 输出的长度规律，并用标准解码器识别非法输入。',
    explain:
        'Base64 把每 3 个字节重排成 4 个可打印字符，字母表是 `A-Z a-z 0-9 + /`，'
        '所以输出长度是原字节数除以 3 向上取整再乘 4。'
        '不足 3 字节时用 `=` 补齐：剩 1 字节补两个 `==`，剩 2 字节补一个 `=`。'
        '`Base64.getDecoder()` 是严格模式，长度不对或含非法字符会抛 `IllegalArgumentException`。'
        'Base64 只是编码不是加密，任何人都能解开，不能用来保护数据。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class Main {
    public static void main(String[] args) {
        System.out.println("m1=" + Base64.getEncoder()
                .encodeToString("M".getBytes(StandardCharsets.UTF_8)));
        System.out.println("m2=" + Base64.getEncoder()
                .encodeToString("Ma".getBytes(StandardCharsets.UTF_8)));
        System.out.println("m3=" + Base64.getEncoder()
                .encodeToString("Man".getBytes(StandardCharsets.UTF_8)));
        byte[] chinese = "离线".getBytes(StandardCharsets.UTF_8);
        System.out.println("bytes=" + chinese.length);
        String encoded = Base64.getEncoder().encodeToString(chinese);
        System.out.println("encoded=" + encoded);
        System.out.println("padded=" + encoded.contains("="));
        System.out.println("decoded="
                + new String(Base64.getDecoder().decode(encoded), StandardCharsets.UTF_8));
        try {
            Base64.getDecoder().decode("56a7*7q/");
            System.out.println("partial=accepted");
        } catch (IllegalArgumentException error) {
            System.out.println("partial=IllegalArgumentException");
        }
    }
}''',
    output:
        'm1=TQ==\n'
        'm2=TWE=\n'
        'm3=TWFu\n'
        'bytes=6\n'
        'encoded=56a757q/\n'
        'padded=false\n'
        'decoded=离线\n'
        'partial=IllegalArgumentException',
    pitfalls: <String>[
      '把 Base64 当加密用，会泄漏全部原始内容。',
      '换行符会让标准解码器报错，多行 Base64 要用 MIME 解码器。',
      '中文要先 getBytes(UTF_8) 再编码，直接对 String 编码会依赖平台默认字符集。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 "Man" 改成 4 字节内容，观察输出长度与填充符的变化。',
        hint: '4 字节 = 3 + 1，最后一组仍剩 1 字节，结尾出现 ==。',
        answer: '4 字节编码后是 8 个字符并以 "==" 结尾。',
      ),
    ],
  ),
  JavaTopic(
    id: 181,
    level: 'beginner',
    title: 'Java 181：手写十六进制编解码',
    summary: '把字节数组转成 hex 字符串再转回来，处理奇数长度与非法字符。',
    concepts: <String>['十六进制', '字节转文本', '参数校验', 'Character.digit'],
    objective: '能自己实现 toHex/fromHex，并在输入非法时抛出有意义的异常。',
    explain:
        '十六进制是二进制的紧凑写法：1 个字节正好对应 2 个 hex 字符。'
        '编码时把每个字节拆成高 4 位和低 4 位，用 `Character.forDigit` 转成字符；'
        '解码时用 `Character.digit(c, 16)` 得到 0..15，非法字符返回 -1。'
        '长度必须是偶数，否则最后一组凑不齐一个字节，应该报错而不是猜。'
        '日志里打印密钥、摘要、协议帧时几乎都用这套转换。',
    code: r'''import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) {
        byte[] data = "QFLI".getBytes(StandardCharsets.UTF_8);
        String hex = toHex(data);
        System.out.println("hex=" + hex);
        System.out.println("upper=" + hex.toUpperCase());
        System.out.println("decoded=" + new String(fromHex(hex), StandardCharsets.UTF_8));
        System.out.println("byteLen=" + data.length + " hexLen=" + hex.length());
        System.out.println("chineseHex=" + toHex("中".getBytes(StandardCharsets.UTF_8)));
        try {
            fromHex("abc");
            System.out.println("odd=accepted");
        } catch (IllegalArgumentException error) {
            System.out.println("odd=IllegalArgumentException");
        }
        try {
            fromHex("zz");
            System.out.println("bad=accepted");
        } catch (IllegalArgumentException error) {
            System.out.println("bad=IllegalArgumentException");
        }
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte b : data) {
            builder.append(Character.forDigit((b >> 4) & 0xF, 16));
            builder.append(Character.forDigit(b & 0xF, 16));
        }
        return builder.toString();
    }

    static byte[] fromHex(String text) {
        if (text.length() % 2 != 0) {
            throw new IllegalArgumentException("hex length must be even: " + text.length());
        }
        byte[] result = new byte[text.length() / 2];
        for (int i = 0; i < result.length; i++) {
            int high = Character.digit(text.charAt(i * 2), 16);
            int low = Character.digit(text.charAt(i * 2 + 1), 16);
            if (high < 0 || low < 0) {
                throw new IllegalArgumentException("invalid hex at index " + (i * 2));
            }
            result[i] = (byte) ((high << 4) | low);
        }
        return result;
    }
}''',
    output:
        'hex=51464c49\n'
        'upper=51464C49\n'
        'decoded=QFLI\n'
        'byteLen=4 hexLen=8\n'
        'chineseHex=e4b8ad\n'
        'odd=IllegalArgumentException\n'
        'bad=IllegalArgumentException',
    pitfalls: <String>[
      '用 (b >> 4) 而不加 & 0xF，负数会带出符号位，得到 f 开头的一长串字符。',
      '忘记校验长度，奇数长度的输入会让最后一个字符被静默丢弃。',
      'Character.digit 对大小写都接受，但会接受非 ASCII 的「全角数字」，需要更严格时自行判断范围。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '增加一个带分隔符的输出格式，例如 "51 46 4c 49"。',
        hint: '在循环里追加空格，注意不要留下结尾空格。',
        answer:
            'for (int i = 0; i < data.length; i++) { if (i > 0) builder.append(\' \'); builder.append(...); }',
      ),
    ],
  ),
  JavaTopic(
    id: 182,
    level: 'intermediate',
    title: 'Java 182：Base64 的三种变体',
    summary: '标准、URL 安全、去填充三种 Base64 的区别与互换场景。',
    concepts: <String>['Base64', 'URL-safe', 'withoutPadding', '字符表'],
    objective: '能根据场景选择正确的 Base64 变体，并解释为什么 URL 参数里必须用 URL-safe。',
    explain:
        '标准 Base64 的字符表包含 `+` 和 `/`，这两个字符在 URL 里有特殊含义'
        '（`+` 表示空格，`/` 是路径分隔符），直接放进查询参数或文件名会出问题。'
        'URL-safe 变体把 `+` 换成 `-`、`/` 换成 `_`，其余不变。'
        '`withoutPadding()` 去掉结尾的 `=`，让编码结果更短，'
        '解码端必须能接受缺少填充的形式（Java 的 URL 解码器可以）。'
        '三种变体编码的是同样的字节，只是字符映射不同，不能混用解码器。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class Main {
    public static void main(String[] args) {
        byte[] data = new byte[] {(byte) 0xFB, (byte) 0xFF, (byte) 0xBF, 0x01};
        System.out.println("standard=" + Base64.getEncoder().encodeToString(data));
        System.out.println("url=" + Base64.getUrlEncoder().encodeToString(data));
        System.out.println("urlNoPad="
                + Base64.getUrlEncoder().withoutPadding().encodeToString(data));
        System.out.println("standardNoPad="
                + Base64.getEncoder().withoutPadding().encodeToString(data));
        System.out.println("urlDecoded="
                + Base64.getUrlDecoder().decode("-_-_AQ==").length);
        byte[] text = ">>>".getBytes(StandardCharsets.UTF_8);
        System.out.println("textStandard=" + Base64.getEncoder().encodeToString(text));
        System.out.println("textUrl=" + Base64.getUrlEncoder().encodeToString(text));
        try {
            Base64.getDecoder().decode("-_-_AQ==");
            System.out.println("crossDecode=accepted");
        } catch (IllegalArgumentException error) {
            System.out.println("crossDecode=IllegalArgumentException");
        }
    }
}''',
    output:
        'standard=+/+/AQ==\n'
        'url=-_-_AQ==\n'
        'urlNoPad=-_-_AQ\n'
        'standardNoPad=+/+/AQ\n'
        'urlDecoded=4\n'
        'textStandard=Pj4+\n'
        'textUrl=Pj4-\n'
        'crossDecode=IllegalArgumentException',
    pitfalls: <String>[
      '把 URL-safe 结果交给标准解码器会抛 IllegalArgumentException，反之亦然。',
      '去掉填充后，某些语言的解码器要求手动补回 = 才能解。',
      'Base64 不是加密；URL 里放敏感数据仍然会被任何人解开。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '写一个方法，把标准 Base64 字符串安全地转成 URL-safe 形式（不去填充）。',
        hint: '做字符替换即可：+ 换成 -，/ 换成 _。',
        answer: 'return standard.replace(\'+\', \'-\').replace(\'/\', \'_\');',
      ),
    ],
  ),
  JavaTopic(
    id: 183,
    level: 'intermediate',
    title: 'Java 183：CRC32 校验和',
    summary: '用 CRC32 计算校验和，验证增量 update 与一次 update 结果一致。',
    concepts: <String>['CRC32', 'Checksum', '增量更新', '校验向量'],
    objective: '能用 CRC32 校验数据完整性，并知道它只查错不防篡改。',
    explain:
        'CRC32 把任意长度的数据压成 32 位整数，用于检测传输或存储中的意外损坏。'
        '它计算极快，硬件也有指令支持，所以 zip、png、以太网帧都用它。'
        '`update(byte[])` 可以多次调用，结果等价于一次性传入拼接后的全部数据，'
        '这让流式校验成为可能。'
        '`getValue()` 返回 long，但实际只有低 32 位有效。'
        'CRC32 是线性校验，攻击者可以构造出碰撞，因此不能用来防篡改，防篡改要用 HMAC 或签名。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.util.zip.CRC32;
import java.util.zip.Checksum;

public class Main {
    public static void main(String[] args) {
        byte[] vector = "123456789".getBytes(StandardCharsets.US_ASCII);
        CRC32 known = new CRC32();
        known.update(vector);
        System.out.println("vector=" + Long.toHexString(known.getValue()));
        CRC32 split = new CRC32();
        split.update("12345".getBytes(StandardCharsets.US_ASCII));
        split.update("6789".getBytes(StandardCharsets.US_ASCII));
        System.out.println("incremental=" + Long.toHexString(split.getValue()));
        Checksum asInterface = new CRC32();
        asInterface.update(vector, 0, vector.length);
        System.out.println("interface=" + Long.toHexString(asInterface.getValue()));
        CRC32 empty = new CRC32();
        empty.update(new byte[0]);
        System.out.println("empty=" + empty.getValue());
        byte[] text = "QFLI 离线".getBytes(StandardCharsets.UTF_8);
        CRC32 chinese = new CRC32();
        chinese.update(text);
        System.out.println("chineseBytes=" + text.length);
        System.out.println("chineseCrc=" + Long.toHexString(chinese.getValue()));
    }
}''',
    output:
        'vector=cbf43926\n'
        'incremental=cbf43926\n'
        'interface=cbf43926\n'
        'empty=0\n'
        'chineseBytes=11\n'
        'chineseCrc=57d6723b',
    pitfalls: <String>[
      'getValue 返回 long，直接强转 int 会丢失高位的符号语义，打印时用 Long.toHexString。',
      'CRC32 不能防篡改：它是公开的线性算法，可以人为构造相同校验值。',
      '计算前要确认字节内容已经确定，字符集不同会导致校验值完全不同。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 "123456789" 的最后一个字符改成 "0"，观察校验值是否变化。',
        hint: 'CRC32 对任意一位变化都极敏感，几乎必然改变。',
        answer: '把 US_ASCII 字符串改为 "123456780"，得到的十六进制值与原值不同。',
      ),
    ],
  ),
  JavaTopic(
    id: 184,
    level: 'intermediate',
    title: 'Java 184：Adler32 与 CRC32 的取舍',
    summary: '比较两种校验算法的已知向量、检出能力与适用场景。',
    concepts: <String>['Adler32', 'CRC32', '校验算法', '性能权衡'],
    objective: '能说明 Adler32 更快但检错能力更弱，并据此选择算法。',
    explain:
        'Adler32 由两个 16 位累加和组成，只需要加法和取模，实现极其简单、速度很快，'
        'zlib 的快速模式就用它。代价是它对短数据块的检错能力弱于 CRC32，'
        '尤其对某些位模式的变化不敏感。'
        'CRC32 基于多项式除法，检错能力强，是 zip、png、gzip 的默认校验。'
        '两者都是 32 位、都不防篡改。'
        '已知向量：`"123456789"` 的 Adler32 是 `091e01de`，CRC32 是 `cbf43926`。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.util.zip.Adler32;
import java.util.zip.CRC32;

public class Main {
    public static void main(String[] args) {
        byte[] vector = "123456789".getBytes(StandardCharsets.US_ASCII);
        Adler32 adler = new Adler32();
        adler.update(vector);
        CRC32 crc = new CRC32();
        crc.update(vector);
        System.out.println("adlerVector=" + Long.toHexString(adler.getValue()));
        System.out.println("crcVector=" + Long.toHexString(crc.getValue()));
        byte[] changed = "123456780".getBytes(StandardCharsets.US_ASCII);
        Adler32 adlerChanged = new Adler32();
        adlerChanged.update(changed);
        CRC32 crcChanged = new CRC32();
        crcChanged.update(changed);
        System.out.println("adlerDetects=" + (adler.getValue() != adlerChanged.getValue()));
        System.out.println("crcDetects=" + (crc.getValue() != crcChanged.getValue()));
        Adler32 emptyAdler = new Adler32();
        emptyAdler.update(new byte[0]);
        System.out.println("emptyAdler=" + emptyAdler.getValue());
        System.out.println("reuseAfterReset=" + resetAndCount(adler));
    }

    static long resetAndCount(Adler32 adler) {
        adler.reset();
        adler.update("123456789".getBytes(StandardCharsets.US_ASCII));
        return adler.getValue();
    }
}''',
    output:
        'adlerVector=91e01de\n'
        'crcVector=cbf43926\n'
        'adlerDetects=true\n'
        'crcDetects=true\n'
        'emptyAdler=1\n'
        'reuseAfterReset=152961502',
    pitfalls: <String>[
      'Adler32 的初始值是 1（不是 0），空数据的校验值是 1，这一点常被误认为 bug。',
      'reset 之后必须重新 update 全部数据，否则校验值只覆盖新数据。',
      '两个算法都只做完整性检查，不能替代摘要或签名。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把校验对象换成 1000 个相同字节，比较两个算法对「字节顺序被打乱」的敏感度。',
        hint: '全相同字节交换顺序不改变内容，可以改为交换两个不同字节再比较。',
        answer: '交换相邻两个不同字节后，Adler32 与 CRC32 通常都会变化，但 CRC32 对位翻转更敏感。',
      ),
    ],
  ),
  JavaTopic(
    id: 185,
    level: 'intermediate',
    title: 'Java 185：MessageDigest 摘要',
    summary: '用 SHA-256/SHA-1 计算摘要，理解摘要长度、增量更新与不可逆性。',
    concepts: <String>['MessageDigest', 'SHA-256', '摘要长度', '增量更新'],
    objective: '能计算并校验文件摘要，知道摘要不是加密、不能用它还原原文。',
    explain:
        '摘要函数把任意长度输入映射成固定长度输出：SHA-256 是 32 字节，SHA-1 是 20 字节。'
        '它有三个性质：相同输入永远得到相同输出、不同输入几乎不可能得到相同输出（抗碰撞）、'
        '从输出无法反推输入（单向）。'
        '`digest()` 调用后会自动重置，所以同一个对象可以连续处理多份数据；'
        '`update()` 可以分段喂入，适合大文件流式计算。'
        '`getInstance` 抛 `NoSuchAlgorithmException`，Java 保证 SHA-256 一定存在。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

public class Main {
    public static void main(String[] args) throws NoSuchAlgorithmException {
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        byte[] hash = sha256.digest("abc".getBytes(StandardCharsets.US_ASCII));
        System.out.println("sha256=" + toHex(hash));
        System.out.println("bytes=" + hash.length);
        MessageDigest sha1 = MessageDigest.getInstance("SHA-1");
        System.out.println("sha1=" + toHex(sha1.digest("abc".getBytes(StandardCharsets.US_ASCII))));
        MessageDigest incremental = MessageDigest.getInstance("SHA-256");
        incremental.update("a".getBytes(StandardCharsets.US_ASCII));
        incremental.update("bc".getBytes(StandardCharsets.US_ASCII));
        System.out.println("incremental=" + Arrays.equals(hash, incremental.digest()));
        System.out.println("emptyPrefix=" + toHex(sha256.digest(new byte[0])).substring(0, 8));
        System.out.println("reused=" + toHex(sha256.digest("abc".getBytes(StandardCharsets.US_ASCII))).equals(toHex(hash)));
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte b : data) {
            builder.append(Character.forDigit((b >> 4) & 0xF, 16));
            builder.append(Character.forDigit(b & 0xF, 16));
        }
        return builder.toString();
    }
}''',
    output:
        'sha256=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n'
        'bytes=32\n'
        'sha1=a9993e364706816aba3e25717850c26c9cd0d89d\n'
        'incremental=true\n'
        'emptyPrefix=e3b0c442\n'
        'reused=true',
    pitfalls: <String>[
      'digest() 会重置内部状态，想要「先算一次再继续 update」必须重新组织调用顺序。',
      '把摘要当加密用是根本性错误：摘要不可逆，无法解密。',
      '校验下载文件时要用 equals 比较十六进制串，注意大小写与空格。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '计算 "abc" 与 "abd" 的 SHA-256，比较两者有多少位相同。',
        hint: '雪崩效应：输入只差 1 位，输出大约一半的位会翻转。',
        answer: '两次摘要的十六进制串几乎完全不同，没有可用于猜测原文的规律。',
      ),
    ],
  ),
  JavaTopic(
    id: 186,
    level: 'advanced',
    title: 'Java 186：HMAC-SHA256 消息认证',
    summary: '用 javax.crypto.Mac 生成带密钥的认证标签，验证密钥与数据都影响结果。',
    concepts: <String>['HmacSHA256', 'Mac', 'SecretKeySpec', '认证标签'],
    objective: '能用 HMAC 校验消息未被篡改且来自持有密钥的一方。',
    explain:
        '单纯的摘要任何人都能重算，所以不能证明消息来自谁。'
        'HMAC 把密钥混入摘要计算：只有持有同一密钥的人才能算出相同的标签。'
        '接收方重新计算标签并比较，一致就说明消息完整且来源可信。'
        '`Mac` 的用法是「getInstance → init(密钥) → doFinal(数据)」，'
        '密钥必须是 `SecretKeySpec`，算法名要与 getInstance 一致。'
        'RFC 4231 给出了标准测试向量，可以用来验证实现是否正确。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public class Main {
    public static void main(String[] args) throws NoSuchAlgorithmException, InvalidKeyException {
        byte[] tag = hmac("Jefe", "what do ya want for nothing?");
        System.out.println("tag=" + toHex(tag));
        System.out.println("bytes=" + tag.length);
        System.out.println("deterministic="
                + Arrays.equals(tag, hmac("Jefe", "what do ya want for nothing?")));
        System.out.println("keyMatters="
                + !Arrays.equals(tag, hmac("jefe", "what do ya want for nothing?")));
        System.out.println("dataMatters="
                + !Arrays.equals(tag, hmac("Jefe", "what do ya want for nothing!")));
        System.out.println("verify=" + Arrays.equals(tag, hmac("Jefe", "what do ya want for nothing?")));
    }

    static byte[] hmac(String key, String message)
            throws NoSuchAlgorithmException, InvalidKeyException {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return mac.doFinal(message.getBytes(StandardCharsets.UTF_8));
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte b : data) {
            builder.append(Character.forDigit((b >> 4) & 0xF, 16));
            builder.append(Character.forDigit(b & 0xF, 16));
        }
        return builder.toString();
    }
}''',
    output:
        'tag=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843\n'
        'bytes=32\n'
        'deterministic=true\n'
        'keyMatters=true\n'
        'dataMatters=true\n'
        'verify=true',
    pitfalls: <String>[
      '比较标签要用 MessageDigest.isEqual 之类的常量时间比较，避免逐字节比较泄漏信息。',
      '把密钥硬编码在源码里等于没有密钥，真实场景要从安全存储读取。',
      'HMAC 与「先摘要再拼接密钥」不是一回事，后者存在长度扩展攻击风险。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把密钥换成空字符串，观察结果是否仍然稳定，并解释安全性。',
        hint: '空密钥在 Java 里会抛 IllegalArgumentException（密钥长度为 0）。',
        answer:
            'new SecretKeySpec(new byte[0], "HmacSHA256") 会抛 IllegalArgumentException: Empty key。',
      ),
    ],
  ),
  JavaTopic(
    id: 187,
    level: 'advanced',
    title: 'Java 187：AES-GCM 认证加密',
    summary: '用 AES/GCM/NoPadding 加密并自动校验完整性，演示篡改会被拒绝。',
    concepts: <String>['AES', 'GCM', 'GCMParameterSpec', 'AEADBadTagException'],
    objective: '能完成一次认证加密与解密，理解 IV 不能重复、标签会自动校验。',
    explain:
        'GCM 是带认证的加密模式（AEAD）：密文尾部附加 16 字节认证标签，'
        '解密时会先验证标签，数据被改过就抛 `AEADBadTagException`，不会返回错误明文。'
        '`GCMParameterSpec(128, iv)` 的 128 是标签位数；'
        'IV 通常是 12 字节，同一密钥下绝不能重复使用，否则密钥流复用会泄漏明文。'
        '真实场景应当用 `SecureRandom` 生成 IV 并与密文一起保存，'
        '这里为了输出可复现而使用了固定 IV。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

public class Main {
    public static void main(String[] args) throws GeneralSecurityException {
        byte[] key = new byte[16];
        for (int i = 0; i < key.length; i++) {
            key[i] = (byte) i;
        }
        byte[] iv = new byte[12];
        iv[11] = 7;
        byte[] plain = "QFLI secret".getBytes(StandardCharsets.UTF_8);
        Cipher encryptor = Cipher.getInstance("AES/GCM/NoPadding");
        encryptor.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"),
                new GCMParameterSpec(128, iv));
        byte[] sealed = encryptor.doFinal(plain);
        System.out.println("plainBytes=" + plain.length);
        System.out.println("sealedBytes=" + sealed.length);
        System.out.println("tagBytes=" + (sealed.length - plain.length));
        System.out.println("sealedHex=" + toHex(sealed));
        Cipher decryptor = Cipher.getInstance("AES/GCM/NoPadding");
        decryptor.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"),
                new GCMParameterSpec(128, iv));
        System.out.println("plain=" + new String(decryptor.doFinal(sealed), StandardCharsets.UTF_8));
        byte[] tampered = sealed.clone();
        tampered[0] ^= 0x01;
        Cipher checker = Cipher.getInstance("AES/GCM/NoPadding");
        checker.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"),
                new GCMParameterSpec(128, iv));
        try {
            checker.doFinal(tampered);
            System.out.println("tampered=accepted");
        } catch (GeneralSecurityException error) {
            System.out.println("tampered=rejected");
        }
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte b : data) {
            builder.append(Character.forDigit((b >> 4) & 0xF, 16));
            builder.append(Character.forDigit(b & 0xF, 16));
        }
        return builder.toString();
    }
}''',
    output:
        'plainBytes=11\n'
        'sealedBytes=27\n'
        'tagBytes=16\n'
        'sealedHex=18d565bb4487d8ae176f6d958cbf907d199860180895c5288f18b8\n'
        'plain=QFLI secret\n'
        'tampered=rejected',
    pitfalls: <String>[
      '同一密钥重复使用同一 IV 会彻底破坏 GCM 的安全性。',
      '不要把固定 IV 写进产品代码，示例固定 IV 只是为了输出可复现。',
      'GCM 的标签校验失败会抛 AEADBadTagException，不要吞掉异常当成「解密为空」。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 IV 的最后一位从 7 改成 8，观察解密是否还能成功。',
        hint: 'GCM 的认证覆盖 IV，IV 不同则标签校验失败。',
        answer: '用错误 IV 解密会抛 AEADBadTagException，被 catch 后输出 rejected。',
      ),
    ],
  ),
  JavaTopic(
    id: 188,
    level: 'intermediate',
    title: 'Java 188：SecureRandom 生成密钥材料',
    summary: '用 SecureRandom 生成盐与随机数，并说明它与 Random 的关键差别。',
    concepts: <String>['SecureRandom', '盐', 'nextLong(bound)', '随机性'],
    objective: '能用安全随机源生成盐和随机 ID，知道 Random 不能用于安全用途。',
    explain:
        '`java.util.Random` 是可预测的线性同余生成器：知道少量输出就能推出后续序列，'
        '绝不能用于密钥、盐、令牌。'
        '`SecureRandom` 由操作系统熵源（Windows 上是 BCryptGenRandom）提供，'
        '默认算法在不同平台不同，但都满足密码学随机性。'
        'Java 17 给 `Random`/`SecureRandom` 增加了 `nextLong(long bound)`，'
        '可以直接在区间内取随机 long，不必再手写取模（取模会引入偏差）。'
        '盐不需要保密，但必须每次不同，否则相同口令会算出相同派生密钥。',
    code: r'''import java.security.SecureRandom;
import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        SecureRandom random = new SecureRandom();
        byte[] salt = new byte[16];
        random.nextBytes(salt);
        byte[] other = new byte[16];
        random.nextBytes(other);
        System.out.println("saltBytes=" + salt.length);
        System.out.println("notAllZero=" + !allZero(salt));
        System.out.println("freshSalt=" + !Arrays.equals(salt, other));
        int first = random.nextInt(100);
        int second = random.nextInt(100);
        System.out.println("inRange=" + (first >= 0 && first < 100)
                + "," + (second >= 0 && second < 100));
        long big = random.nextLong(1_000_000_000_000L);
        System.out.println("longInRange=" + (big >= 0 && big < 1_000_000_000_000L));
        System.out.println("fiveDraws=" + random.ints(5, 0, 10).count());
    }

    static boolean allZero(byte[] data) {
        for (byte b : data) {
            if (b != 0) {
                return false;
            }
        }
        return true;
    }
}''',
    output:
        'saltBytes=16\n'
        'notAllZero=true\n'
        'freshSalt=true\n'
        'inRange=true,true\n'
        'longInRange=true\n'
        'fiveDraws=5',
    pitfalls: <String>[
      '用 new Random(seed) 生成令牌是可预测的，即使种子来自时间戳也不行。',
      '用 nextInt() % bound 取随机范围会引入取模偏差，应直接用 nextInt(bound)。',
      'SecureRandom 首次初始化可能较慢，不要在高频循环里反复 new。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '生成 32 字节盐并转成十六进制，说明为什么长度不是越长越好。',
        hint: '盐长度超过摘要块大小后收益递减，16~32 字节已足够。',
        answer: 'byte[] salt = new byte[32]; random.nextBytes(salt); 再用十六进制输出。',
      ),
    ],
  ),
  JavaTopic(
    id: 189,
    level: 'advanced',
    title: 'Java 189：PBKDF2 口令派生',
    summary: '用 PBEKeySpec 与 PBKDF2WithHmacSHA256 把口令变成密钥，并比较迭代次数的影响。',
    concepts: <String>['PBKDF2', 'PBEKeySpec', 'SecretKeyFactory', '迭代次数'],
    objective: '能实现口令加盐派生，理解迭代次数是「拖慢暴力破解」的成本参数。',
    explain:
        '口令通常很短、熵很低，不能直接当 AES 密钥用。'
        'PBKDF2 把「口令 + 盐 + 迭代次数」反复做 HMAC，输出定长密钥。'
        '盐保证相同口令得到不同密钥，迭代次数让每次猜测都要付出成倍的 CPU 时间。'
        'Java 通过 `SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")` 提供实现，'
        '`PBEKeySpec(password, salt, iterations, keyLengthBits)` 描述参数，'
        '`getEncoded()` 取出派生出的字节。'
        '用完口令字符数组后调用 `clearPassword()` 及时清空内存。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Arrays;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

public class Main {
    static final byte[] SALT = {1, 2, 3, 4, 5, 6, 7, 8};

    public static void main(String[] args) throws GeneralSecurityException {
        byte[] first = derive("password", 1000);
        byte[] second = derive("password", 1000);
        byte[] other = derive("Password", 1000);
        System.out.println("bytes=" + first.length);
        System.out.println("stable=" + Arrays.equals(first, second));
        System.out.println("caseSensitive=" + !Arrays.equals(first, other));
        System.out.println("hex=" + toHex(first));
        System.out.println("iterationsMatter=" + !Arrays.equals(first, derive("password", 2000)));
        System.out.println("saltMatters=" + !Arrays.equals(first, deriveWithSalt("password", 1000,
                new byte[] {9, 9, 9, 9, 9, 9, 9, 9})));
    }

    static byte[] derive(String password, int iterations) throws GeneralSecurityException {
        return deriveWithSalt(password, iterations, SALT);
    }

    static byte[] deriveWithSalt(String password, int iterations, byte[] salt)
            throws GeneralSecurityException {
        PBEKeySpec spec = new PBEKeySpec(password.toCharArray(), salt, iterations, 256);
        try {
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec)
                    .getEncoded();
        } finally {
            spec.clearPassword();
        }
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte b : data) {
            builder.append(Character.forDigit((b >> 4) & 0xF, 16));
            builder.append(Character.forDigit(b & 0xF, 16));
        }
        return builder.toString();
    }
}''',
    output:
        'bytes=32\n'
        'stable=true\n'
        'caseSensitive=true\n'
        'hex=5ce847a8c3daa60b98da70c6b06031296d2534320c3431813b84b3fa4473c54d\n'
        'iterationsMatter=true\n'
        'saltMatters=true',
    pitfalls: <String>[
      '迭代次数必须随硬件提升而上调，1000 次在现代机器上已经太弱。',
      '盐要随派生结果一起保存，否则无法校验口令。',
      'PBEKeySpec 的 keyLength 单位是位，不是字节。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 keyLength 从 256 改成 128，观察输出长度变化。',
        hint: '128 位 = 16 字节。',
        answer:
            'new PBEKeySpec(password.toCharArray(), salt, iterations, 128) 时 getEncoded().length == 16。',
      ),
    ],
  ),
  JavaTopic(
    id: 190,
    level: 'advanced',
    title: 'Java 190：常量时间比较',
    summary: '手写 XOR 累加比较，理解为什么比较标签时不能提前 return。',
    concepts: <String>['常量时间', 'MessageDigest.isEqual', '侧信道', 'XOR 累加'],
    objective: '能写出不随内容提前退出的比较函数，并解释它防的是什么攻击。',
    explain:
        '普通的 `Arrays.equals` 在发现第一个不同字节时就返回，'
        '耗时与「前多少个字节相同」成正比。'
        '攻击者可以通过精确测量响应时间，一个字节一个字节地猜出正确的标签，'
        '这叫计时侧信道攻击。'
        '常量时间比较的做法是把所有字节的差异用 `|=` 累积起来，'
        '无论内容如何都遍历完全部字节，最后只比较累加结果是否为零。'
        'JDK 提供了 `MessageDigest.isEqual`，长度相同时就是常量时间的。'
        '注意：长度不同仍然会提前返回，所以长度本身必须公开。',
    code: r'''import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public class Main {
    public static void main(String[] args) {
        byte[] expected = "token-abc".getBytes(StandardCharsets.UTF_8);
        byte[] same = "token-abc".getBytes(StandardCharsets.UTF_8);
        byte[] firstDiffers = "Token-abc".getBytes(StandardCharsets.UTF_8);
        byte[] lastDiffers = "token-abd".getBytes(StandardCharsets.UTF_8);
        byte[] shorter = "token-ab".getBytes(StandardCharsets.UTF_8);
        System.out.println("same=" + MessageDigest.isEqual(expected, same));
        System.out.println("firstDiffers=" + MessageDigest.isEqual(expected, firstDiffers));
        System.out.println("lastDiffers=" + MessageDigest.isEqual(expected, lastDiffers));
        System.out.println("shorter=" + MessageDigest.isEqual(expected, shorter));
        System.out.println("manualSame=" + constantTimeEquals(expected, same));
        System.out.println("manualDiffers=" + constantTimeEquals(expected, lastDiffers));
        System.out.println("manualShorter=" + constantTimeEquals(expected, shorter));
    }

    static boolean constantTimeEquals(byte[] left, byte[] right) {
        if (left.length != right.length) {
            return false;
        }
        int diff = 0;
        for (int i = 0; i < left.length; i++) {
            diff |= left[i] ^ right[i];
        }
        return diff == 0;
    }
}''',
    output:
        'same=true\n'
        'firstDiffers=false\n'
        'lastDiffers=false\n'
        'shorter=false\n'
        'manualSame=true\n'
        'manualDiffers=false\n'
        'manualShorter=false',
    pitfalls: <String>[
      '在循环里写 if (left[i] != right[i]) return false; 就退化成非常量时间了。',
      '先比较长度再常量时间比较是标准做法，长度不属于需要保密的信息。',
      '常量时间比较不能弥补协议设计缺陷，例如允许无限次尝试。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把常量时间比较改成「先算摘要再比较摘要」，说明这样做的好处。',
        hint: '固定长度输出让长度差异也消失，但要多一次摘要计算。',
        answer:
            'boolean ok = MessageDigest.isEqual(sha256(left), sha256(right)); 输出长度固定为 32 字节。',
      ),
    ],
  ),
  JavaTopic(
    id: 191,
    level: 'intermediate',
    title: 'Java 191：重复密钥 XOR 为什么不能用',
    summary: '手写 XOR 流加密并还原，再用重复明文块暴露它的致命弱点。',
    concepts: <String>['异或', '密钥重用', '已知明文攻击', '对称加密'],
    objective: '能解释「异或本身没问题，问题在于重复使用短密钥」，并知道正确做法。',
    explain:
        '异或的自反性（`a ^ b ^ b == a`）让它天然可以当加解密：密文再异或一次密钥就还原。'
        '问题出在密钥比数据短：同一密钥字节会被反复使用，'
        '两段相同明文会得到两段相同密文，攻击者立刻能看出明文结构；'
        '只要猜到任意一段明文，就能异或出该位置的密钥，进而解开其他位置。'
        '这就是维吉尼亚密码的现代版本，历史上的「一次性密码本」之所以安全，'
        '正是因为密钥真随机、只使用一次、且与明文等长。'
        '工程上必须使用 AES-GCM 这类认证加密。',
    code: r'''import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) {
        byte[] key = {0x0F, 0x1E, 0x2D};
        byte[] plain = "QFLI".getBytes(StandardCharsets.UTF_8);
        byte[] cipher = xor(plain, key);
        System.out.println("plainHex=" + toHex(plain));
        System.out.println("cipherHex=" + toHex(cipher));
        System.out.println("sameLength=" + (cipher.length == plain.length));
        System.out.println("roundTrip=" + new String(xor(cipher, key), StandardCharsets.UTF_8));
        byte[] repeated = xor("QFLQFL".getBytes(StandardCharsets.UTF_8), key);
        String hex = toHex(repeated);
        System.out.println("repeated=" + hex);
        System.out.println("patternLeaks=" + hex.substring(0, 6).equals(hex.substring(6)));
    }

    static byte[] xor(byte[] data, byte[] key) {
        byte[] result = new byte[data.length];
        for (int i = 0; i < data.length; i++) {
            result[i] = (byte) (data[i] ^ key[i % key.length]);
        }
        return result;
    }

    static String toHex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte b : data) {
            builder.append(Character.forDigit((b >> 4) & 0xF, 16));
            builder.append(Character.forDigit(b & 0xF, 16));
        }
        return builder.toString();
    }
}''',
    output:
        'plainHex=51464c49\n'
        'cipherHex=5e586146\n'
        'sameLength=true\n'
        'roundTrip=QFLI\n'
        'repeated=5e58615e5861\n'
        'patternLeaks=true',
    pitfalls: <String>[
      '把「能还原明文」当成「安全」，XOR 加密几乎没有强度可言。',
      '密钥长度短于数据时必然重复使用密钥字节。',
      'XOR 加密不提供完整性保护，攻击者可以按位翻转密文来精确篡改明文。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用已知明文 "QFL" 与它的密文反推出密钥前三个字节，验证密钥被完全暴露。',
        hint: 'key[i] = plain[i] ^ cipher[i]。',
        answer: '0x51^0x5E=0x0F，0x46^0x58=0x1E，0x4C^0x61=0x2D，正好还原出密钥。',
      ),
    ],
  ),
  JavaTopic(
    id: 192,
    level: 'intermediate',
    title: 'Java 192：GZIP 压缩与解压',
    summary: '用 GZIPOutputStream 压缩字节数组，检查魔数并用 GZIPInputStream 还原。',
    concepts: <String>['GZIPOutputStream', 'GZIPInputStream', '魔数', '压缩率'],
    objective: '能在内存里完成一次 gzip 往返，并看懂 1f 8b 这个 gzip 魔数。',
    explain:
        'gzip 是「deflate 数据 + 头部 + 尾部 CRC」的容器格式，'
        '文件前两个字节固定是 `1F 8B`，很多程序靠这个判断是不是 gzip 文件。'
        '`GZIPOutputStream` 默认使用最佳压缩级别，适合文本、JSON、日志这类重复度高的内容；'
        '已经压缩过的东西（jpg、zip）再压几乎不会变小。'
        '解压时用 `readAllBytes()` 一次读回全部内容，注意它只在 JDK 9+ 才存在。'
        '压缩流必须显式 `close()`，否则尾部数据（含 CRC）不会写出，解压会失败。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

public class Main {
    public static void main(String[] args) throws IOException {
        String text = "离线编程学习平台 QFLI ".repeat(20);
        byte[] raw = text.getBytes(StandardCharsets.UTF_8);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (GZIPOutputStream gzip = new GZIPOutputStream(buffer)) {
            gzip.write(raw);
        }
        byte[] packed = buffer.toByteArray();
        System.out.println("rawBytes=" + raw.length);
        System.out.println("packedBytes=" + packed.length);
        System.out.println("smaller=" + (packed.length < raw.length));
        System.out.println("magic=" + (packed[0] & 0xFF) + "," + (packed[1] & 0xFF));
        try (GZIPInputStream gunzip = new GZIPInputStream(
                new ByteArrayInputStream(packed))) {
            byte[] restored = gunzip.readAllBytes();
            System.out.println("restoredBytes=" + restored.length);
            System.out.println("identical=" + Arrays.equals(raw, restored));
        }
    }
}''',
    output:
        'rawBytes=600\n'
        'packedBytes=60\n'
        'smaller=true\n'
        'magic=31,139\n'
        'restoredBytes=600\n'
        'identical=true',
    pitfalls: <String>[
      '忘记 close 压缩流，尾部 CRC 与长度不会写出，解压时报「unexpected end of ZLIB input stream」。',
      'gzip 与 zip 的魔数不同（zip 是 50 4B），不要用 gzip 流去读 zip 文件。',
      '压缩对随机数据无效，甚至因为头部开销而变大。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把文本改成只重复 1 次，观察 packedBytes 是否还比 rawBytes 小。',
        hint: '短数据压缩后往往比原文更大，因为要加 18 字节以上的头部。',
        answer: '去掉 repeat(20) 后 packedBytes 通常大于 rawBytes，smaller 变为 false。',
      ),
    ],
  ),
  JavaTopic(
    id: 193,
    level: 'intermediate',
    title: 'Java 193：用 ZipOutputStream 打包',
    summary: '在内存里生成含多级目录的 zip，再用 ZipInputStream 逐条读回。',
    concepts: <String>['ZipOutputStream', 'ZipEntry', 'ZipInputStream', '条目顺序'],
    objective: '能生成与读取 zip 归档，理解条目名里的 / 就是目录分隔符，不需要单独的目录条目。',
    explain:
        'zip 是「条目（entry）序列」而不是真正的树结构：'
        '目录只是条目名里的 `/` 前缀，解压工具会按需创建文件夹。'
        '`putNextEntry` 开始一个新条目，写入内容后必须 `closeEntry`，'
        '否则下一条会追加到当前条目里。'
        '`ZipInputStream` 只能顺序读取，`getNextEntry` 返回 null 表示结束；'
        '如果要随机访问某个条目，应该用 `ZipFile` 而不是流。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

public class Main {
    public static void main(String[] args) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(buffer)) {
            put(zip, "a.txt", "alpha");
            put(zip, "dir/b.txt", "beta");
            put(zip, "dir/c.txt", "");
        }
        byte[] archive = buffer.toByteArray();
        System.out.println("emptyAllowed=" + hasEntry(archive, "dir/c.txt"));
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(archive))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                byte[] content = zip.readAllBytes();
                System.out.println(entry.getName() + " " + content.length + " "
                        + new String(content, StandardCharsets.UTF_8));
                zip.closeEntry();
            }
        }
    }

    static void put(ZipOutputStream zip, String name, String content) throws IOException {
        zip.putNextEntry(new ZipEntry(name));
        zip.write(content.getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
    }

    static boolean hasEntry(byte[] archive, String name) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(archive))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (entry.getName().equals(name)) {
                    return true;
                }
            }
        }
        return false;
    }
}''',
    output:
        'emptyAllowed=true\n'
        'a.txt 5 alpha\n'
        'dir/b.txt 4 beta\n'
        'dir/c.txt 0 ',
    pitfalls: <String>[
      '漏掉 closeEntry 会把下一条内容追加到上一个条目里。',
      'ZipInputStream 是顺序流，想随机取条目要用 ZipFile。',
      '条目名用反斜杠在部分解压工具上会创建带 \\ 的文件名，必须用正斜杠。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给每个条目设置固定时间（setTime）并观察结果是否更需要它。',
        hint: '默认时间取当前时刻，会导致同样的输入产生不同的归档字节。',
        answer:
            'entry.setTime(0L) 或 entry.setTimeLocal(LocalDateTime.of(2020,1,1,0,0)) 后归档可复现。',
      ),
    ],
  ),
  JavaTopic(
    id: 194,
    level: 'advanced',
    title: 'Java 194：Deflater 与 Inflater 裸压缩',
    summary: '直接操作 deflate 流：循环 deflate/inflate、判断 finished()、处理 needsInput()。',
    concepts: <String>['Deflater', 'Inflater', '压缩级别', '分块处理'],
    objective: '能手写 deflate/inflate 循环，并解释为什么必须检查 finished() 而不是只读一次。',
    explain:
        '`Deflater` 是 gzip 和 zip 里真正做压缩的引擎，输出的是裸 deflate 流，没有头部和校验。'
        '`deflate` 会尽量填满输出缓冲区，一次调用不一定处理完全部输入，'
        '必须用 `while (!finished())` 循环，直到内部状态报告结束。'
        '`Inflater` 侧则要处理「输出缓冲区满了但输入还没读完」和「输入读完了但还没结束」两种情况，'
        '所以循环条件同时看 `finished()`、`needsInput()` 和 `needsDictionary()`。'
        '两个对象内部持有本地内存，用完必须 `end()`。',
    code: r'''import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.zip.DataFormatException;
import java.util.zip.Deflater;
import java.util.zip.Inflater;

public class Main {
    public static void main(String[] args) throws DataFormatException, IOException {
        byte[] raw = "abcdefghij".repeat(50).getBytes(StandardCharsets.UTF_8);
        byte[] packed = deflate(raw, Deflater.DEFAULT_COMPRESSION);
        byte[] fast = deflate(raw, Deflater.BEST_SPEED);
        System.out.println("rawBytes=" + raw.length);
        System.out.println("smaller=" + (packed.length < raw.length));
        System.out.println("fastUnderRaw=" + (fast.length < raw.length));
        byte[] restored = inflate(packed);
        System.out.println("restoredBytes=" + restored.length);
        System.out.println("identical=" + Arrays.equals(raw, restored));
        System.out.println("emptyRoundTrip=" + inflate(deflate(new byte[0],
                Deflater.DEFAULT_COMPRESSION)).length);
    }

    static byte[] deflate(byte[] raw, int level) throws IOException {
        Deflater deflater = new Deflater(level);
        try {
            deflater.setInput(raw);
            deflater.finish();
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[256];
            while (!deflater.finished()) {
                int produced = deflater.deflate(chunk);
                buffer.write(chunk, 0, produced);
            }
            return buffer.toByteArray();
        } finally {
            deflater.end();
        }
    }

    static byte[] inflate(byte[] packed) throws DataFormatException, IOException {
        Inflater inflater = new Inflater();
        try {
            inflater.setInput(packed);
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[256];
            while (!inflater.finished()) {
                int produced = inflater.inflate(chunk);
                if (produced == 0 && (inflater.needsInput() || inflater.needsDictionary())) {
                    break;
                }
                buffer.write(chunk, 0, produced);
            }
            return buffer.toByteArray();
        } finally {
            inflater.end();
        }
    }
}''',
    output:
        'rawBytes=500\n'
        'smaller=true\n'
        'fastUnderRaw=true\n'
        'restoredBytes=500\n'
        'identical=true\n'
        'emptyRoundTrip=0',
    pitfalls: <String>[
      '不调用 end() 会泄漏本地内存，直到对象被回收才释放。',
      '只调用一次 deflate 就当作完成，会截断数据。',
      'Inflater 遇到 ZIP 的 deflate 流需要 new Inflater(true)（nowrap），否则头两字节会被当成 zlib 头解析而报错。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '改用 new Inflater(true) 去解 gzip 里的裸 deflate 数据，说明 nowrap 参数的意义。',
        hint: 'nowrap=true 表示「没有 zlib 头」，zip 条目里存的就是这种裸流。',
        answer:
            'Inflater inflater = new Inflater(true); 否则会抛「incorrect header check」。',
      ),
    ],
  ),
  JavaTopic(
    id: 195,
    level: 'intermediate',
    title: 'Java 195：序列化基础与魔数',
    summary: '用 ObjectOutputStream 写出对象、读回副本，检查 aced 魔数与实例身份。',
    concepts: <String>[
      'Serializable',
      'ObjectOutputStream',
      'serialVersionUID',
      '深拷贝',
    ],
    objective: '能完成一次对象序列化往返，并说明反序列化得到的是新对象而不是原对象引用。',
    explain:
        '序列化把对象图写成字节，反序列化再重建一份等价的新对象。'
        '流的前两个字节固定是 `AC ED`，后面跟流版本号，所以看到 `aced` 就知道是 Java 序列化流。'
        '只有实现了 `Serializable` 的类才能被写出，否则抛 `NotSerializableException`。'
        '反序列化不走构造方法，而是按需从流里分配对象并填字段，'
        '所以 `restored == original` 是 false，但字段值相同。'
        '显式声明 `serialVersionUID` 可以避免兼容性检查失效。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;

public class Main {
    static class Point implements Serializable {
        private static final long serialVersionUID = 1L;
        private final int x;
        private final int y;

        Point(int x, int y) {
            this.x = x;
            this.y = y;
        }

        @Override
        public String toString() {
            return "Point(" + x + "," + y + ")";
        }
    }

    public static void main(String[] args) throws IOException, ClassNotFoundException {
        Point point = new Point(3, 4);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(buffer)) {
            out.writeObject(point);
        }
        byte[] bytes = buffer.toByteArray();
        System.out.print("magic=");
        System.out.println(String.format("%02x%02x", bytes[0] & 0xFF, bytes[1] & 0xFF));
        try (ObjectInputStream in = new ObjectInputStream(
                new ByteArrayInputStream(bytes))) {
            Object restored = in.readObject();
            System.out.println("type=" + restored.getClass().getSimpleName());
            System.out.println("value=" + restored);
            System.out.println("sameInstance=" + (restored == point));
            System.out.println("sameValue=" + restored.toString().equals(point.toString()));
        }
    }
}''',
    output:
        'magic=aced\n'
        'type=Point\n'
        'value=Point(3,4)\n'
        'sameInstance=false\n'
        'sameValue=true',
    pitfalls: <String>[
      '内部类（非静态）会隐式持有外部类引用，序列化时容易连带失败。',
      '不写 serialVersionUID 时，任何字段改动都会让旧数据反序列化失败。',
      '反序列化不调用构造方法，所以构造器里的校验逻辑不会执行。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 Point 改成不实现 Serializable，观察程序报什么错。',
        hint: 'writeObject 会抛 NotSerializableException 并带上类名。',
        answer: 'java.io.NotSerializableException: Main\$Point',
      ),
    ],
  ),
  JavaTopic(
    id: 196,
    level: 'advanced',
    title: 'Java 196：transient 与自定义 writeObject',
    summary: '用 transient 排除字段，再用 writeObject/readObject 显式补写与恢复。',
    concepts: <String>[
      'transient',
      'writeObject',
      'readObject',
      'defaultWriteObject',
    ],
    objective: '能控制哪些字段进入序列化流，并在反序列化时重建派生状态。',
    explain:
        '`transient` 告诉默认序列化「跳过这个字段」：'
        '典型用途是缓存、日志句柄、会话令牌、Socket 引用等不该被持久化的东西。'
        '但有时候需要「有条件地保存」，这时可以自己声明 `writeObject`：'
        '先 `defaultWriteObject()` 写出普通字段，再 `writeUTF` 追加令牌。'
        '对应的 `readObject` 里先 `defaultReadObject()`，再读回额外字段。'
        '这两个方法必须是 `private`，由序列化机制反射调用，'
        '写读顺序必须严格一致，否则会读错类型。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;

public class Main {
    static class Session implements Serializable {
        private static final long serialVersionUID = 2L;
        private final String user;
        private transient String token;
        private transient int restoreCount;

        Session(String user, String token) {
            this.user = user;
            this.token = token;
        }

        private void writeObject(ObjectOutputStream out) throws IOException {
            out.defaultWriteObject();
            out.writeUTF(token == null ? "" : token);
        }

        private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
            in.defaultReadObject();
            String stored = in.readUTF();
            this.token = stored.isEmpty() ? null : stored;
            this.restoreCount++;
        }

        @Override
        public String toString() {
            return user + "/" + token + "/" + restoreCount;
        }
    }

    public static void main(String[] args) throws IOException, ClassNotFoundException {
        Session session = new Session("lichengyu", "t-123");
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(buffer)) {
            out.writeObject(session);
        }
        System.out.println("before=" + session);
        Session restored;
        try (ObjectInputStream in = new ObjectInputStream(
                new ByteArrayInputStream(buffer.toByteArray()))) {
            restored = (Session) in.readObject();
        }
        System.out.println("after=" + restored);
        System.out.println("tokenKept=" + "t-123".equals(restored.token));
        System.out.println("originalUntouched=" + (session.restoreCount == 0));
    }
}''',
    output:
        'before=lichengyu/t-123/0\n'
        'after=lichengyu/t-123/1\n'
        'tokenKept=true\n'
        'originalUntouched=true',
    pitfalls: <String>[
      '声明成 public 的 writeObject 不会被识别，必须是 private。',
      'writeObject 里调用 defaultWriteObject 的位置决定了普通字段与额外字段的顺序。',
      'transient 字段在反序列化后是默认值（null/0），需要重建就必须在 readObject 里赋值。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 restoreCount 从 transient 改成普通字段，观察 after 行的计数。',
        hint: '普通字段会被保存，反序列化后仍是 0 再加 1。',
        answer: '改成普通字段后 after 仍然是 lichengyu/t-123/1。',
      ),
    ],
  ),
  JavaTopic(
    id: 197,
    level: 'advanced',
    title: 'Java 197：Externalizable 完全自定义',
    summary: '实现 writeExternal/readExternal，观察反序列化会调用公开无参构造。',
    concepts: <String>[
      'Externalizable',
      'writeExternal',
      'readExternal',
      '无参构造',
    ],
    objective: '能说明 Externalizable 与 Serializable 的差异，并正确提供公开无参构造方法。',
    explain:
        '`Serializable` 是「默认帮你写」，`Externalizable` 是「全部自己写」：'
        '框架只负责调用 `writeExternal`/`readExternal`，字段顺序、类型、压缩全由你决定。'
        '关键差异是反序列化过程：`Externalizable` **会调用公开无参构造方法**，'
        '然后再调 `readExternal` 填字段；所以缺少无参构造会直接失败。'
        '`Serializable` 则完全不调用任何构造方法。'
        '自定义格式的好处是体积小、可跨版本控制，代价是必须自己维护兼容性。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.Externalizable;
import java.io.IOException;
import java.io.ObjectInput;
import java.io.ObjectInputStream;
import java.io.ObjectOutput;
import java.io.ObjectOutputStream;

public class Main {
    static class Money implements Externalizable {
        private static int constructions = 0;
        private long cents;
        private String currency;

        public Money() {
            constructions++;
            this.currency = "CNY";
        }

        Money(long cents, String currency) {
            constructions++;
            this.cents = cents;
            this.currency = currency;
        }

        @Override
        public void writeExternal(ObjectOutput out) throws IOException {
            out.writeLong(cents);
            out.writeUTF(currency);
        }

        @Override
        public void readExternal(ObjectInput in) throws IOException {
            cents = in.readLong();
            currency = in.readUTF();
        }

        @Override
        public String toString() {
            return cents + " " + currency;
        }
    }

    public static void main(String[] args) throws IOException, ClassNotFoundException {
        Money money = new Money(12345, "CNY");
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(buffer)) {
            out.writeObject(money);
        }
        System.out.println("selectedFieldOnly=" + (buffer.size() < 100));
        Money.constructions = 0;
        Money restored;
        try (ObjectInputStream in = new ObjectInputStream(
                new ByteArrayInputStream(buffer.toByteArray()))) {
            restored = (Money) in.readObject();
        }
        System.out.println("value=" + restored);
        System.out.println("constructionsDuringRead=" + Money.constructions);
        System.out.println("sameInstance=" + (restored == money));
    }
}''',
    output:
        'selectedFieldOnly=true\n'
        'value=12345 CNY\n'
        'constructionsDuringRead=1\n'
        'sameInstance=false',
    pitfalls: <String>[
      'Externalizable 的无参构造必须是 public，否则反序列化抛 InvalidClassException。',
      'readExternal 的读取顺序必须与 writeExternal 完全一致。',
      '没有 defaultWriteObject 之类的兼容机制，字段变更需要自己写版本号处理。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把无参构造改成 private，观察反序列化报什么错。',
        hint: '框架需要反射创建实例，非 public 会失败。',
        answer: 'java.io.InvalidClassException: no valid constructor。',
      ),
    ],
  ),
  JavaTopic(
    id: 198,
    level: 'advanced',
    title: 'Java 198：ObjectInputFilter 白名单',
    summary: '用反序列化过滤器只允许指定类，理解为什么反序列化需要设防。',
    concepts: <String>[
      'ObjectInputFilter',
      '白名单',
      'InvalidClassException',
      '反序列化漏洞',
    ],
    objective: '能配置一个只允许可信类的过滤器，并验证不在白名单里的类会被拒绝。',
    explain:
        '反序列化会在读取过程中构造任意 `Serializable` 类，'
        '攻击者可以构造恶意流触发这些类的副作用，形成「反序列化 gadget 链」。'
        '防御的核心是白名单：`ObjectInputFilter.Config.createFilter(...)` 支持'
        '「类名模式;maxdepth=N;maxbytes=N」这样的语法，'
        '`ClassName` 精确匹配，`package.*` 匹配包内所有类。'
        '要注意**只写正向模式并不构成白名单**：未匹配任何模式的类返回 UNDECIDED，'
        '最终仍会被放行，因此末尾必须补上 `!*` 才能拒绝其余全部类。'
        '`setObjectInputFilter` 注册在流上，返回 REJECTED 时抛 `InvalidClassException`。'
        '从 Java 17 起还能用 `jdk.serialFilter` 系统属性全局设置。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InvalidClassException;
import java.io.ObjectInputFilter;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;

public class Main {
    static class Safe implements Serializable {
        private static final long serialVersionUID = 1L;
        private final String label = "safe";
    }

    static class Forbidden implements Serializable {
        private static final long serialVersionUID = 1L;
        private final String label = "forbidden";
    }

    public static void main(String[] args) throws IOException, ClassNotFoundException {
        ObjectInputFilter filter = ObjectInputFilter.Config.createFilter(
                "Main$Safe;!*");
        byte[] safe = write(new Safe());
        byte[] forbidden = write(new Forbidden());
        System.out.println("safeAccepted=" + (read(safe, filter) instanceof Safe));
        try {
            read(forbidden, filter);
            System.out.println("forbidden=accepted");
        } catch (InvalidClassException error) {
            System.out.println("forbidden=rejected");
        }
        try {
            read(forbidden, null);
            System.out.println("withoutFilter=accepted");
        } catch (InvalidClassException error) {
            System.out.println("withoutFilter=rejected");
        }
        ObjectInputFilter tiny = ObjectInputFilter.Config.createFilter(
                "Main$*;maxbytes=8");
        try {
            read(safe, tiny);
            System.out.println("maxbytesLimited=accepted");
        } catch (InvalidClassException error) {
            System.out.println("maxbytesLimited=rejected");
        }
    }

    static byte[] write(Object value) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(buffer)) {
            out.writeObject(value);
        }
        return buffer.toByteArray();
    }

    static Object read(byte[] data, ObjectInputFilter filter)
            throws IOException, ClassNotFoundException {
        try (ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(data))) {
            if (filter != null) {
                in.setObjectInputFilter(filter);
            }
            return in.readObject();
        }
    }
}''',
    output:
        'safeAccepted=true\n'
        'forbidden=rejected\n'
        'withoutFilter=accepted\n'
        'maxbytesLimited=rejected',
    pitfalls: <String>[
      '只写白名单是不够的，末尾必须加 !* 把未匹配的类显式拒绝。',
      '类名匹配区分内部类的 \$ 写法，Main\$Safe 与 Main.Safe 不等价。',
      'maxbytes 统计的是整个流（含类描述），设得太小会误伤正常对象。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把过滤器改成 "Main\$*" 并给 maxbytes=64，观察大对象是否被拒绝。',
        hint: 'maxbytes 限制流的总字节数，超过会返回 REJECTED。',
        answer:
            'ObjectInputFilter.Config.createFilter("Main\$*;maxbytes=64")，超限时抛 InvalidClassException。',
      ),
    ],
  ),
  JavaTopic(
    id: 199,
    level: 'intermediate',
    title: 'Java 199：record 与序列化',
    summary: 'record 实现 Serializable 时的规范构造、组件反射与 equals 语义。',
    concepts: <String>['record', 'Serializable', 'RecordComponents', '紧凑构造'],
    objective: '能序列化 record 并说明它为什么比普通类更适合做数据传输对象。',
    explain:
        '`record` 只要声明 `implements Serializable` 就能序列化，'
        '它的反序列化会调用**规范构造方法**，因此紧凑构造里的校验在还原时同样生效——'
        '这一点和普通类的「反序列化绕过构造方法」刚好相反。'
        '组件本身就是 `private final` 字段，字段名与访问器一一对应，'
        '序列化格式因此非常稳定。'
        '`getRecordComponents()` 可以在运行时拿到组件名、类型与访问器，'
        '常用于日志、反射映射和协议序列化。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;

public class Main {
    record User(String name, int level) implements Serializable {
    }

    record Score(int value) implements Serializable {
        Score {
            if (value < 0 || value > 100) {
                throw new IllegalArgumentException("out of range: " + value);
            }
        }
    }

    public static void main(String[] args) throws IOException, ClassNotFoundException {
        User user = new User("lichengyu", 7);
        byte[] bytes = write(user);
        User restored = (User) read(bytes);
        System.out.println("restored=" + restored);
        System.out.println("equals=" + restored.equals(user));
        System.out.println("isRecord=" + restored.getClass().isRecord());
        System.out.println("components=" + restored.getClass().getRecordComponents().length);
        System.out.println("scoreRoundTrip=" + read(write(new Score(50))));
        try {
            new Score(200);
            System.out.println("rangeCheck=missing");
        } catch (IllegalArgumentException error) {
            System.out.println("rangeCheck=IllegalArgumentException");
        }
    }

    static byte[] write(Object value) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ObjectOutputStream out = new ObjectOutputStream(buffer)) {
            out.writeObject(value);
        }
        return buffer.toByteArray();
    }

    static Object read(byte[] data) throws IOException, ClassNotFoundException {
        try (ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(data))) {
            return in.readObject();
        }
    }
}''',
    output:
        'restored=User[name=lichengyu, level=7]\n'
        'equals=true\n'
        'isRecord=true\n'
        'components=2\n'
        'scoreRoundTrip=Score[value=50]\n'
        'rangeCheck=IllegalArgumentException',
    pitfalls: <String>[
      'record 不能声明实例字段，额外状态只能放 static 字段或外部结构。',
      'record 的 toString/equals/hashCode 自动生成，手写会覆盖默认行为并可能破坏一致性。',
      '参数校验放在紧凑构造里，普通构造器已经被替换，不要再写一遍重复逻辑。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 User 增加一个 email 组件，观察序列化前后 components 与输出变化。',
        hint: 'record 增加组件会自动改构造、访问器、equals 与 toString。',
        answer:
            'record User(String name, int level, String email) 后 components 变为 3。',
      ),
    ],
  ),
  JavaTopic(
    id: 200,
    level: 'advanced',
    title: 'Java 200：检查序列化契约',
    summary: '用 ObjectStreamClass 读取 serialVersionUID、序列化字段列表与类名。',
    concepts: <String>['ObjectStreamClass', 'serialVersionUID', '字段契约', '兼容性'],
    objective: '能在运行时检查一个类的序列化契约，定位「旧数据读不出来」的原因。',
    explain:
        '`ObjectStreamClass.lookup(Class)` 返回一个类在序列化系统中的「契约」：'
        '`getSerialVersionUID()` 给出 UID（显式声明的或按结构计算出来的），'
        '`getFields()` 列出真正会被写出的字段——'
        '也就是非 static、非 transient、且没被 `serialPersistentFields` 覆盖的那些。'
        '两个版本的类只有在 UID 相同的情况下才会尝试字段级兼容；'
        'UID 不同会直接抛 `InvalidClassException`，'
        '这也是为什么每个需要持久化的类都应该显式声明 `serialVersionUID`。'
        '没有显式声明时，UID 是根据类名、修饰符、接口与字段签名计算的，'
        '任何签名变化都会改变它。',
    code: r'''import java.io.ObjectStreamClass;
import java.io.ObjectStreamField;
import java.io.Serializable;

public class Main {
    static class WithUid implements Serializable {
        private static final long serialVersionUID = 42L;
        private int count;
        private String name;
        private transient String cache;
    }

    static class WithoutUid implements Serializable {
        private int count;
        private String[] tags;
    }

    public static void main(String[] args) {
        ObjectStreamClass declared = ObjectStreamClass.lookup(WithUid.class);
        System.out.println("declaredUid=" + declared.getSerialVersionUID());
        System.out.println("declaredFields=" + declared.getFields().length);
        System.out.println("declaredTransientSkipped="
                + !hasField(declared, "cache"));
        ObjectStreamClass computed = ObjectStreamClass.lookup(WithoutUid.class);
        System.out.println("computedNonZero=" + (computed.getSerialVersionUID() != 0L));
        System.out.println("computedStable=" + (computed.getSerialVersionUID()
                == ObjectStreamClass.lookup(WithoutUid.class).getSerialVersionUID()));
        System.out.println("computedFields=" + computed.getFields().length);
        System.out.println("simpleName=" + computed.getName().endsWith("WithoutUid"));
    }

    static boolean hasField(ObjectStreamClass descriptor, String name) {
        for (ObjectStreamField field : descriptor.getFields()) {
            if (field.getName().equals(name)) {
                return true;
            }
        }
        return false;
    }
}''',
    output:
        'declaredUid=42\n'
        'declaredFields=2\n'
        'declaredTransientSkipped=true\n'
        'computedNonZero=true\n'
        'computedStable=true\n'
        'computedFields=2\n'
        'simpleName=true',
    pitfalls: <String>[
      'getFields 只返回会被序列化的字段，transient 与 static 都不在其中。',
      '没有显式 UID 时，改字段类型或名称都会改变计算出的 UID，导致旧数据读取失败。',
      'UID 只影响兼容性检查，不解决「字段语义变了」的问题。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给 WithoutUid 增加一个字段，观察计算出的 UID 是否改变。',
        hint: 'UID 基于字段签名计算，加字段必然改变结果。',
        answer: '增加 private long stamp; 后 getSerialVersionUID() 返回不同的值。',
      ),
    ],
  ),
  JavaTopic(
    id: 201,
    level: 'intermediate',
    title: 'Java 201：命名捕获组',
    summary: '用 (?<name>...) 给分组命名，通过 group("name") 读取并配合 find 遍历。',
    concepts: <String>['Pattern', 'Matcher', '命名分组', 'group 索引'],
    objective: '能写出带命名分组、带编号引用的正则，并从匹配结果中取出每个分组。',
    explain:
        '捕获组用括号声明，`group(1)` 按「左括号出现的顺序」编号。'
        '编号在复杂正则里非常脆弱：插入一个新括号就会让所有下标错位。'
        '命名分组 `(?<name>...)` 给分组起名，用 `group("name")` 读取，'
        '重构正则时不会影响其他分组。'
        '`group()` 不带参数返回整段匹配，`start()` 返回匹配在输入中的起始下标。'
        '`matches()` 要求整串匹配，`find()` 只要求找到一段。',
    code: r'''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        Pattern date = Pattern.compile("(\\d{4})-(\\d{2})-(\\d{2})");
        Matcher matcher = date.matcher("2024-10-22");
        System.out.println("groupCount=" + matcher.groupCount());
        if (matcher.matches()) {
            System.out.println("year=" + matcher.group(1));
            System.out.println("month=" + matcher.group(2));
            System.out.println("day=" + matcher.group(3));
            System.out.println("whole=" + matcher.group());
        }
        Pattern pair = Pattern.compile("(?<key>[a-z]+)=(?<value>\\d+)");
        Matcher keyValue = pair.matcher("port=8080;timeout=30");
        while (keyValue.find()) {
            System.out.println("kv=" + keyValue.group("key") + ":"
                    + keyValue.group("value") + "@" + keyValue.start());
        }
        System.out.println("findCount=" + count(pair, "a=1 b=2 c=3"));
    }

    static int count(Pattern pattern, String input) {
        Matcher matcher = pattern.matcher(input);
        int total = 0;
        while (matcher.find()) {
            total++;
        }
        return total;
    }
}''',
    output:
        'groupCount=3\n'
        'year=2024\n'
        'month=10\n'
        'day=22\n'
        'whole=2024-10-22\n'
        'kv=port:8080@0\n'
        'kv=timeout:30@10\n'
        'findCount=3',
    pitfalls: <String>[
      'groupCount 只统计捕获组，命名分组也算在内。',
      'matches() 之后调用 find() 会从上次匹配位置继续，通常需要 reset()。',
      '分组名只能包含字母和数字，且必须以字母开头。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把日期正则改成命名分组，并用 group("year") 取年份。',
        hint: '写法是 (?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})。',
        answer:
            'Pattern.compile("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})") 后用 group("year")。',
      ),
    ],
  ),
  JavaTopic(
    id: 202,
    level: 'advanced',
    title: 'Java 202：贪婪、懒惰与占有量词',
    summary: '用同一段输入对比 .+ / .+? / .++ 三种量词的匹配行为与回溯代价。',
    concepts: <String>['贪婪量词', '懒惰量词', '占有量词', '回溯'],
    objective: '能根据匹配需求选择量词类型，并知道占有量词可以防止灾难性回溯。',
    explain:
        '量词默认是贪婪的：`.*` 会尽量多吃，然后再回退找后续模式。'
        '在 `.?` 加问号变成懒惰：先尽量少吃，逐步扩大。'
        '加加号变成占有：吃完就不退还，即使因此导致整体失败。'
        '所以占有量词经常「一个都匹配不到」——它不会为了凑出结果而回退。'
        '占有量词和「原子组 `(?>)`」能消除回溯，'
        '所以对 `(a+)+b` 这类嵌套量词改用 `(a++)+b` 可以避免指数级回溯；'
        '代价是它不保证能找到所有可行解，只有在你确认语义等价时才可替换。',
    code: r'''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        String input = "<a><b><c>";
        show("greedy", "<.+>", input);
        show("reluctant", "<.+?>", input);
        show("possessive", "<.++>", input);
        System.out.println("possessiveMatches=" + Pattern.matches("<.++>", "<a><b>"));
        System.out.println("greedyMatches=" + Pattern.matches("<.+>", "<a><b>"));
        System.out.println("bounded=" + Pattern.matches("<.{1,3}>", "<abc>"));
    }

    static void show(String label, String regex, String input) {
        Matcher matcher = Pattern.compile(regex).matcher(input);
        StringBuilder out = new StringBuilder(label).append('=');
        while (matcher.find()) {
            out.append('[').append(matcher.group()).append(']');
        }
        if (out.charAt(out.length() - 1) == '=') {
            out.append("[none]");
        }
        System.out.println(out);
    }
}''',
    output:
        'greedy=[<a><b><c>]\n'
        'reluctant=[<a>][<b>][<c>]\n'
        'possessive=[none]\n'
        'possessiveMatches=false\n'
        'greedyMatches=true\n'
        'bounded=true',
    pitfalls: <String>[
      '嵌套量词 (a+)+ 在长输入上会指数级回溯，是常见的性能事故来源。',
      '占有量词不会为后续模式让步，替换前必须确认语义等价。',
      '懒惰量词并不总是更快，每次扩大都要重新尝试后续匹配。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 show("reluctant", ...) 的正则改成 "<[^>]+>"，比较输出是否相同。',
        hint: '否定字符类不依赖回溯，通常比懒惰量词更快。',
        answer: '两者输出都是 [<a>][<b>][<c>]，但否定字符类没有回溯开销。',
      ),
    ],
  ),
  JavaTopic(
    id: 203,
    level: 'advanced',
    title: 'Java 203：零宽断言',
    summary: '用前瞻、后顾与单词边界做条件匹配，而不会消耗字符。',
    concepts: <String>['前瞻', '后顾', '单词边界', '零宽'],
    objective: '能写出「匹配但不要包含上下文」的正则，例如提取带单位的数字。',
    explain:
        '零宽断言只检查某个位置前后的内容，不把它计入匹配结果。'
        '`(?=X)` 正向前瞻要求右边是 X，`(?!X)` 负向前瞻要求右边不是 X，'
        '`(?<=X)` 正向后顾要求左边是 X，`(?<!X)` 负向后顾要求左边不是 X。'
        '后顾要求左边是 X，`(?<!X)` 负向后顾要求左边不是 X。'
        '从 Java 9 起后顾允许有上限的可变长度（如 `(?<=ab+)`），'
        '但最大长度必须在编译期可判定，且不能太大。'
        '`\\b` 是单词边界：一侧是单词字符、另一侧不是的零宽位置。'
        '它们最常见的用途是「提取数字但排除单位本身」。',
    code: r'''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        String text = "price 100 USD, cost 250 CNY";
        print("cny", "\\d+(?= CNY)", text);
        print("price", "(?<=price )\\d+", text);
        print("notUsd", "\\b(?!USD\\b)\\w+\\b", "USD RMB EUR");
        print("word", "\\bc\\w*\\b", "cat cut ct ac");
        print("varLookbehind", "(?<=ab+)c", "abbc");
        System.out.println("badRange=" + compile("[z-a]"));
    }

    static void print(String label, String regex, String input) {
        Matcher matcher = Pattern.compile(regex).matcher(input);
        while (matcher.find()) {
            System.out.println(label + "=" + matcher.group());
        }
    }

    static boolean compile(String regex) {
        try {
            Pattern.compile(regex);
            return true;
        } catch (RuntimeException error) {
            return false;
        }
    }
}''',
    output:
        'cny=250\n'
        'price=100\n'
        'notUsd=RMB\n'
        'notUsd=EUR\n'
        'word=cat\n'
        'word=cut\n'
        'word=ct\n'
        'varLookbehind=c\n'
        'badRange=false',
    pitfalls: <String>[
      '可变长后顾只支持有上限的写法，无界量词在复杂表达式里可能被拒绝。',
      '断言里的分组同样会参与编号，会影响 group(n) 的下标。',
      '过度使用断言会让正则难以调试，通常可以改用两次简单匹配加逻辑判断。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '提取所有「数字 + 空格 + 单位」，但只保留单位为大写三字母的情况。',
        hint: '用 \\d+(?=\\s[A-Z]{3}) 做前瞻。',
        answer: 'Pattern.compile("\\\\d+(?=\\\\s[A-Z]{3})") 会匹配 100 和 250。',
      ),
    ],
  ),
  JavaTopic(
    id: 204,
    level: 'advanced',
    title: 'Java 204：appendReplacement 重写文本',
    summary: '在循环里用 appendReplacement/appendTail 精确重建字符串，并处理 \$ 转义。',
    concepts: <String>[
      'appendReplacement',
      'appendTail',
      'quoteReplacement',
      'replaceAll',
    ],
    objective: '能用 appendReplacement 做逐匹配改写，并解释为什么替换串里的 \$ 需要转义。',
    explain:
        '`replaceAll` 适合「整体一次性替换」，但如果替换结果依赖额外状态（计数器、查表），'
        '就必须用 `appendReplacement` 在循环里逐段拼接：'
        '它会把「上次匹配结束到本次匹配开始」之间的文本和替换结果一起写进 `StringBuilder`，'
        '最后用 `appendTail` 补上剩余部分。'
        '替换串里的 `\$1` 表示分组引用、`\\` 表示转义，'
        '所以拼接出来的文本里如果本身就含 `\$`，必须用 `Matcher.quoteReplacement` 包裹。',
    code: r'''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        String text = "user:alice, admin:bob";
        Pattern pattern = Pattern.compile("(\\w+):(\\w+)");
        Matcher matcher = pattern.matcher(text);
        StringBuilder out = new StringBuilder();
        while (matcher.find()) {
            matcher.appendReplacement(out, "$2($1)");
        }
        matcher.appendTail(out);
        System.out.println("rewritten=" + out);
        System.out.println("groupRef=" + matcher.replaceAll("$2@$1"));
        Matcher quoted = pattern.matcher("r:x");
        StringBuilder safe = new StringBuilder();
        while (quoted.find()) {
            quoted.appendReplacement(safe, Matcher.quoteReplacement("$" + quoted.group(2)));
        }
        quoted.appendTail(safe);
        System.out.println("quoted=" + safe);
        System.out.println("counted=" + numberItems("a b c"));
    }

    static String numberItems(String text) {
        Matcher matcher = Pattern.compile("\\b\\w+\\b").matcher(text);
        StringBuilder out = new StringBuilder();
        int index = 1;
        while (matcher.find()) {
            matcher.appendReplacement(out, index++ + "." + matcher.group());
        }
        matcher.appendTail(out);
        return out.toString();
    }
}''',
    output:
        'rewritten=alice(user), bob(admin)\n'
        'groupRef=alice@user, bob@admin\n'
        'quoted=\$x\n'
        'counted=1.a 2.b 3.c',
    pitfalls: <String>[
      '在 appendReplacement 的替换串里直接拼入用户输入，含 \$ 或 \\ 时会抛异常或产生错误结果。',
      '忘记 appendTail 会丢掉最后一段未匹配的尾部文本。',
      'appendReplacement 里的分组引用只对当前这次匹配有效。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 counted 改成倒序编号，观察 appendReplacement 的输出顺序。',
        hint: '先收集所有匹配，再按倒序编号重建。',
        answer: '先 find 收集到 List，再按倒序 append，得到 3.a 2.b 1.c。',
      ),
    ],
  ),
  JavaTopic(
    id: 205,
    level: 'intermediate',
    title: 'Java 205：split 的 limit 参数',
    summary: '对比 split 的三个重载：默认丢尾部空串、limit 截断、负数保留全部空串。',
    concepts: <String>['String.split', 'Pattern.split', 'limit', '尾部空串'],
    objective: '能解释为什么解析 CSV 时要用负数 limit，避免最后一个字段被丢掉。',
    explain:
        '`split(regex)` 等价于 `split(regex, 0)`：尾部连续的空串会被全部删除。'
        '`split(regex, n)` 最多切出 n 个元素，最后一段包含剩余全部内容。'
        '`split(regex, -1)` 保留尾部所有空串。'
        '解析 CSV、TSV、配置行时必须用负数 limit：'
        '像 `"a,b,,"` 这样最后两列为空的记录，默认 split 只返回两个元素，字段数就对不上了。'
        '还有一个隐蔽行为：如果输入以分隔符开头，会得到首元素为空串。',
    code: r'''import java.util.Arrays;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        System.out.println("all=" + Arrays.toString("a,b,,c".split(",")));
        System.out.println("limit2=" + Arrays.toString("a,b,,c".split(",", 2)));
        System.out.println("limitNeg=" + Arrays.toString("a,b,,c".split(",", -1)));
        System.out.println("trailing=" + Arrays.toString("a,b,,".split(",")));
        System.out.println("trailingNeg=" + Arrays.toString("a,b,,".split(",", -1)));
        System.out.println("trimmed=" + Arrays.toString("  a  b  ".split("\\s+")));
        System.out.println("digits=" + Arrays.toString(Pattern.compile("\\d+")
                .split("a1b22c333")));
        System.out.println("fields=" + "id,,3".split(",", -1).length);
    }
}''',
    output:
        'all=[a, b, , c]\n'
        'limit2=[a, b,,c]\n'
        'limitNeg=[a, b, , c]\n'
        'trailing=[a, b]\n'
        'trailingNeg=[a, b, , ]\n'
        'trimmed=[, a, b]\n'
        'digits=[a, b, c]\n'
        'fields=3',
    pitfalls: <String>[
      '默认 split 会静默丢掉尾部空字段，CSV 解析必须用 -1。',
      'split 的参数是正则，用 "." 作分隔符会切开所有字符，要点号转义。',
      '输入以分隔符开头时首元素是空串，不是被跳过。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 split("\\.") 解析 "1.2.3"，再改为 split(".") 观察结果。',
        hint: '点号在正则里表示任意字符。',
        answer: 'split("\\\\.") 得到 [1, 2, 3]；split(".") 返回空数组。',
      ),
    ],
  ),
  JavaTopic(
    id: 206,
    level: 'intermediate',
    title: 'Java 206：Pattern 标志位',
    summary: '掌握 MULTILINE、DOTALL、CASE_INSENSITIVE、COMMENTS、LITERAL 的作用范围。',
    concepts: <String>['Pattern 标志', 'MULTILINE', 'DOTALL', 'LITERAL'],
    objective: '能针对多行文本、大小写不敏感、含特殊字符的字面量匹配选择正确标志。',
    explain:
        '默认情况下 `^` 只匹配整个输入的起点、`\$` 只匹配终点，`.` 不匹配换行符。'
        '`Pattern.MULTILINE` 让 `^`/`\$` 在每个换行处生效；'
        '`Pattern.DOTALL` 让 `.` 也能匹配换行；'
        '`Pattern.CASE_INSENSITIVE` 忽略大小写，配合 `UNICODE_CASE` 才覆盖非 ASCII 字母；'
        '`Pattern.COMMENTS` 允许在正则里写空白和 `#` 注释，便于维护长正则；'
        '`Pattern.LITERAL` 把整段正则当普通字符串，不再解释任何元字符。'
        '标志也可以通过内联写法 `(?m)`、`(?s)` 在正则内部开启。',
    code: r'''import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        String lines = "a\nb\nb";
        System.out.println("plain=" + count(Pattern.compile("^b"), lines));
        System.out.println("multiline=" + count(
                Pattern.compile("^b", Pattern.MULTILINE), lines));
        System.out.println("dotAll=" + Pattern.compile("a.b").matcher("a\nb").find());
        System.out.println("dotAllFlag=" + Pattern.compile("a.b", Pattern.DOTALL)
                .matcher("a\nb").find());
        System.out.println("ignoreCase=" + Pattern.compile("qfli", Pattern.CASE_INSENSITIVE)
                .matcher("QFLI").find());
        System.out.println("caseSensitive=" + Pattern.compile("qfli").matcher("QFLI").find());
        System.out.println("comments=" + Pattern.compile("a # 中间注释\n b", Pattern.COMMENTS)
                .matcher("ab").find());
        System.out.println("literal=" + Pattern.compile("a.b", Pattern.LITERAL)
                .matcher("a.b").find());
        System.out.println("inline=" + Pattern.compile("(?im)^qfli$").matcher("QFLI").find());
    }

    static int count(Pattern pattern, String input) {
        Matcher matcher = pattern.matcher(input);
        int total = 0;
        while (matcher.find()) {
            total++;
        }
        return total;
    }
}''',
    output:
        'plain=0\n'
        'multiline=2\n'
        'dotAll=false\n'
        'dotAllFlag=true\n'
        'ignoreCase=true\n'
        'caseSensitive=false\n'
        'comments=true\n'
        'literal=true\n'
        'inline=true',
    pitfalls: <String>[
      'MULTILINE 只影响 ^ 和 \$，不会让 . 跨行；跨行要 DOTALL。',
      'COMMENTS 模式下正则里的空格会被忽略，匹配真实空格要写成 \\ 或 [ ]。',
      '标志是编译期属性，运行时改不了，需要重新 compile。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '同时开启 MULTILINE 与 DOTALL，用 "^a.*b\$" 匹配两行文本。',
        hint: 'Pattern.MULTILINE | Pattern.DOTALL。',
        answer:
            'Pattern.compile("^a.*b\$", Pattern.MULTILINE | Pattern.DOTALL).matcher("a\\nx\\nb").find() 返回 true。',
      ),
    ],
  ),
  JavaTopic(
    id: 207,
    level: 'intermediate',
    title: 'Java 207：正则转义与 Pattern.quote',
    summary: '处理用户输入里的元字符，用 Pattern.quote 与 quoteReplacement 保证字面匹配。',
    concepts: <String>['Pattern.quote', '转义', '元字符', '字面量匹配'],
    objective: '能把任意用户输入安全地拼进正则，避免元字符导致的错误匹配。',
    explain:
        '正则里的 `. * + ? ( ) [ ] { } ^ \$ | \\` 都有特殊含义。'
        '把用户输入直接拼进正则，轻则匹配错误，重则抛 `PatternSyntaxException`。'
        '`Pattern.quote(s)` 用 `\\Q...\\E` 包裹整段文本，让其中所有字符都按字面处理，'
        '这是拼接不可信输入的推荐做法。'
        '替换串则用 `Matcher.quoteReplacement(s)`，它转义 `\$` 和 `\\`。'
        '在 Java 源码里写正则还要再过一层字符串转义，'
        '所以「反斜杠」在正则里是 `\\\\`，在字符串里就要写 `\\\\\\\\`。',
    code: r'''import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        String userInput = "a.b*c(d)";
        System.out.println("raw=" + "a.b*c(d)".matches(userInput));
        Pattern quoted = Pattern.compile(Pattern.quote(userInput));
        System.out.println("quoted=" + quoted.matcher(userInput).matches());
        System.out.println("quotedText=" + Pattern.quote(userInput));
        System.out.println("escapeDollar=" + "价格$5".replaceAll("\\$", "USD"));
        System.out.println("backslash=" + Pattern.matches("a\\\\b", "a\\b"));
        System.out.println("charClass=" + Pattern.matches("[a-c]+", "abc"));
        System.out.println("negated=" + Pattern.matches("[^a-c]+", "xyz"));
        System.out.println("unicodeEscape=" + Pattern.matches("\\u6210\\u7ee9", "成绩"));
    }
}''',
    output:
        'raw=false\n'
        'quoted=true\n'
        'quotedText=\\Qa.b*c(d)\\E\n'
        'escapeDollar=价格USD5\n'
        'backslash=true\n'
        'charClass=true\n'
        'negated=true\n'
        'unicodeEscape=true',
    pitfalls: <String>[
      '用 replaceAll 做字面替换时，替换串里的 \$ 会被当成分组引用。',
      'Java 字符串转义与正则转义叠加，反斜杠数量容易数错。',
      'Pattern.quote 处理不了定长要求，把它拼进后顾时要注意。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt:
            '把用户输入 "1+1" 用 replaceAll 做字面替换成 "2"，观察不加 quoteReplacement 的结果。',
        hint: '替换串里没有 \$ 时不会出问题，可以再试 "\$1"。',
        answer:
            '"1+1".replaceAll(Pattern.quote("1+1"), Matcher.quoteReplacement("\$2")) 得到 \$2。',
      ),
    ],
  ),
  JavaTopic(
    id: 208,
    level: 'intermediate',
    title: 'Java 208：Instant 与 Duration',
    summary: '用时间戳与时长做加减，理解 Instant 是 UTC 瞬时点、Duration 是时间量。',
    concepts: <String>['Instant', 'Duration', 'toMinutes', '时间戳'],
    objective: '能用 Instant 表示绝对时刻、用 Duration 表示间隔，并正确换算单位。',
    explain:
        '`Instant` 表示时间轴上的一个点（UTC），内部是「秒 + 纳秒」；'
        '`Duration` 表示两个时刻之间的量，可以是负数。'
        '`Instant.parse` 接受 ISO-8601 的 `...Z` 形式，'
        '`plus/minus(Duration)` 做加减，`Duration.between(a, b)` 求差。'
        '`toMinutes()` 是总分钟数，而 `toMinutesPart()` 只取超出小时后剩下的分钟，'
        '这两个方法名字很像但语义完全不同。'
        '`Instant` 不带时区，打印出来永远是 UTC，需要本地时间就转成 `ZonedDateTime`。',
    code: r'''import java.time.Duration;
import java.time.Instant;

public class Main {
    public static void main(String[] args) {
        Instant start = Instant.parse("2024-10-22T08:00:00Z");
        Instant end = start.plus(Duration.ofMinutes(95));
        System.out.println("end=" + end);
        System.out.println("totalMinutes=" + Duration.between(start, end).toMinutes());
        System.out.println("minusThirty=" + end.minusSeconds(30));
        System.out.println("roundTrip=" + Instant.ofEpochMilli(start.toEpochMilli()).equals(start));
        System.out.println("nano=" + start.getNano());
        Duration span = Duration.ofSeconds(3661);
        System.out.println("parts=" + span.toHours() + "h"
                + span.toMinutesPart() + "m" + span.toSecondsPart() + "s");
        System.out.println("negative=" + Duration.ofSeconds(-1).isNegative());
        System.out.println("compared=" + Duration.ofSeconds(60).compareTo(Duration.ofMinutes(1)));
        System.out.println("totalSeconds=" + span.toSeconds());
    }
}''',
    output:
        'end=2024-10-22T09:35:00Z\n'
        'totalMinutes=95\n'
        'minusThirty=2024-10-22T09:34:30Z\n'
        'roundTrip=true\n'
        'nano=0\n'
        'parts=1h1m1s\n'
        'negative=true\n'
        'compared=0\n'
        'totalSeconds=3661',
    pitfalls: <String>[
      'Duration 不支持月/年，需要日历运算请用 Period。',
      'toMinutes 是总分钟，toMinutesPart 是分解后的余数，混用会导致数值错得离谱。',
      'Instant.now() 依赖系统时钟，测试里要注入 Clock 才能稳定。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '计算 2024-10-22T08:00:00Z 到 2025-01-01T00:00:00Z 之间的小时数。',
        hint: 'Duration.between(...).toHours()。',
        answer:
            'Duration.between(Instant.parse("2024-10-22T08:00:00Z"), Instant.parse("2025-01-01T00:00:00Z")).toHours()',
      ),
    ],
  ),
  JavaTopic(
    id: 209,
    level: 'intermediate',
    title: 'Java 209：LocalDate、Period 与 ChronoUnit',
    summary: '日期加减的月末截断、Period 的字段语义与 ChronoUnit 的总天数之差。',
    concepts: <String>['LocalDate', 'Period', 'ChronoUnit', '闰年'],
    objective: '能正确计算两个日期之间的年数/月数/天数，并解释 1 月 31 日加一个月的结​果。',
    explain:
        '`LocalDate` 是不可变的日期值，`plusMonths` 遇到月末会自动截断：'
        '1 月 31 日加 1 个月得到 2 月 29 日（闰年），而不是 3 月 2 日。'
        '`Period` 是「年 + 月 + 日」的日历量，`Period.between` 按日历字段逐级相减，'
        '所以它和「总天数」不是一回事。'
        '需要总天数时用 `ChronoUnit.DAYS.between`，需要总月数用 `ChronoUnit.MONTHS.between`。'
        '`lengthOfMonth()`、`isLeapYear()`、`getDayOfWeek()` 可以直接读日历信息。',
    code: r'''import java.time.LocalDate;
import java.time.Period;
import java.time.temporal.ChronoUnit;

public class Main {
    public static void main(String[] args) {
        LocalDate start = LocalDate.of(2024, 1, 31);
        System.out.println("plusMonth=" + start.plusMonths(1));
        LocalDate leapDay = start.plusDays(29);
        System.out.println("plusDays=" + leapDay);
        System.out.println("leapYear=" + leapDay.isLeapYear());
        LocalDate from = LocalDate.of(2020, 2, 29);
        LocalDate to = LocalDate.of(2024, 3, 1);
        System.out.println("period=" + Period.between(from, to));
        System.out.println("totalDays=" + ChronoUnit.DAYS.between(from, to));
        System.out.println("totalMonths=" + ChronoUnit.MONTHS.between(from, to));
        System.out.println("isBefore=" + start.isBefore(leapDay));
        System.out.println("dayOfWeek=" + LocalDate.of(2024, 10, 22).getDayOfWeek());
        System.out.println("lengthOfMonth=" + LocalDate.of(2024, 2, 1).lengthOfMonth());
        System.out.println("withDay=" + start.withDayOfMonth(30));
    }
}''',
    output:
        'plusMonth=2024-02-29\n'
        'plusDays=2024-02-29\n'
        'leapYear=true\n'
        'period=P4Y1D\n'
        'totalDays=1462\n'
        'totalMonths=48\n'
        'isBefore=true\n'
        'dayOfWeek=TUESDAY\n'
        'lengthOfMonth=29\n'
        'withDay=2024-01-30',
    pitfalls: <String>[
      'plusMonths 会截断到月末，不要指望它「溢出」到下个月。',
      'Period 只保留年月日字段，拿它当总天数会得到误导性的结果。',
      'LocalDate 没有时区，跨时区换算日期必须经由 ZonedDateTime。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '计算 2024 年有多少个周一。',
        hint: '从 1 月 1 日开始按周推进，或用 ChronoUnit.WEEKS 结合当天星期。',
        answer:
            'LocalDate.of(2024,1,1).datesUntil(LocalDate.of(2025,1,1)).filter(d -> d.getDayOfWeek() == DayOfWeek.MONDAY).count() == 53',
      ),
    ],
  ),
  JavaTopic(
    id: 210,
    level: 'advanced',
    title: 'Java 210：时区转换与夏令时空洞',
    summary: '用 ZonedDateTime 表示带时区的时刻，观察 DST 跳变让 02:30 不存在。',
    concepts: <String>['ZoneId', 'ZonedDateTime', '夏令时', '时刻转换'],
    objective: '能解释「本地时间加一小时可能不等于时刻加一小时」，并正确做跨时区展示。',
    explain:
        '`LocalDateTime` 只是一个日历读数，`ZonedDateTime` 才是「读数 + 时区规则」。'
        '2024-03-10 美国东部夏令时开始：02:00 直接跳到 03:00，'
        '所以 `LocalDateTime.of(2024,3,10,2,30)` 在这个时区没有对应时刻，'
        'Java 会把它顺延到 03:30 EDT。'
        '反方向（秋季回拨）会出现同一本地时间对应两个时刻的重叠，'
        '默认取较早的那个偏移。'
        '做跨时区展示时，应该先确定绝对的 `Instant` 再用 `withZoneSameInstant` 换算，'
        '而不是对本地时间做加减。',
    code: r'''import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;

public class Main {
    public static void main(String[] args) {
        ZoneId newYork = ZoneId.of("America/New_York");
        LocalDateTime local = LocalDateTime.of(2024, 3, 10, 1, 30);
        ZonedDateTime beforeGap = ZonedDateTime.of(local, newYork);
        System.out.println("beforeGap=" + beforeGap.toLocalTime()
                + " offset=" + beforeGap.getOffset());
        ZonedDateTime afterGap = ZonedDateTime.of(local.plusHours(1), newYork);
        System.out.println("afterGap=" + afterGap.toLocalTime()
                + " offset=" + afterGap.getOffset());
        System.out.println("utcInstant=" + afterGap.toInstant());
        System.out.println("shanghaiLocal="
                + afterGap.withZoneSameInstant(ZoneId.of("Asia/Shanghai")).toLocalDateTime());
        System.out.println("beforeUtc=" + beforeGap.toInstant());
        System.out.println("hoursBetween=" + java.time.Duration
                .between(beforeGap.toInstant(), afterGap.toInstant()).toMinutes());
    }
}''',
    output:
        'beforeGap=01:30 offset=-05:00\n'
        'afterGap=03:30 offset=-04:00\n'
        'utcInstant=2024-03-10T07:30:00Z\n'
        'shanghaiLocal=2024-03-10T15:30\n'
        'beforeUtc=2024-03-10T06:30:00Z\n'
        'hoursBetween=60',
    pitfalls: <String>[
      '对 LocalDateTime 加 1 小时不等于对时刻加 1 小时，跨越 DST 时两者结果不同。',
      'ZoneId.of("Asia/Shanghai") 才是合法 ID，写 "CST" 会抛异常或匹配到错误时区。',
      '存储时间应存 Instant 或带偏移的字符串，不要只存本地时间字符串。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把日期换成 2024-11-03（美国夏令时结束），观察 01:30 的两个可能偏移。',
        hint: '重叠时刻默认取较早偏移，可用 withLaterOffsetAtOverlap 取另一个。',
        answer:
            'ZonedDateTime.of(LocalDateTime.of(2024,11,3,1,30), newYork) 默认 -04:00，withLaterOffsetAtOverlap() 得到 -05:00。',
      ),
    ],
  ),
  JavaTopic(
    id: 211,
    level: 'intermediate',
    title: 'Java 211：DateTimeFormatter 自定义模式',
    summary: '用固定 Locale 格式化日期时间，避免默认语言导致输出不一致。',
    concepts: <String>['DateTimeFormatter', 'ofPattern', 'Locale', '解析与格式化'],
    objective: '能写出稳定的日期格式串，并解释为什么格式化必须显式指定 Locale。',
    explain:
        '`DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")` 定义输出布局，'
        '其中 `M` 是月份、`m` 是分钟、`s` 是秒、`S` 是毫秒、`E` 是星期缩写。'
        '像 `MMM`（月份名）和 `EEE`（星期名）这类文本字段依赖 Locale，'
        '不指定就用 JVM 默认语言，同一份代码在不同系统上会输出「十月」或「October」。'
        '要可复现就固定 `Locale.US` 或 `Locale.CHINA`。'
        '`DateTimeFormatter` 是不可变且线程安全的，可以做成静态常量复用；'
        '解析用 `LocalDate.parse(text, formatter)`。',
    code: r'''import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

public class Main {
    static final String PATTERN = "yyyy-MM-dd HH:mm:ss";
    static final DateTimeFormatter ISO = DateTimeFormatter.ofPattern(
            PATTERN, Locale.US);
    static final DateTimeFormatter TEXT = DateTimeFormatter.ofPattern(
            "EEE MMM d, yyyy", Locale.US);

    public static void main(String[] args) {
        LocalDateTime moment = LocalDateTime.of(2024, 10, 22, 9, 5, 7);
        System.out.println("iso=" + moment.format(ISO));
        System.out.println("text=" + moment.format(TEXT));
        System.out.println("parse=" + LocalDateTime.parse("2024-10-22 09:05:07", ISO));
        System.out.println("roundTrip=" + LocalDateTime.parse(moment.format(ISO), ISO)
                .equals(moment));
        System.out.println("pattern=" + PATTERN);
        System.out.println("chinese=" + moment.format(
                DateTimeFormatter.ofPattern("yyyy 年 M 月 d 日", Locale.CHINA)));
        System.out.println("padded=" + LocalDateTime.of(2024, 1, 2, 3, 4, 5)
                .format(DateTimeFormatter.ofPattern("yy/M/d H:m:s", Locale.US)));
    }
}''',
    output:
        'iso=2024-10-22 09:05:07\n'
        'text=Tue Oct 22, 2024\n'
        'parse=2024-10-22T09:05:07\n'
        'roundTrip=true\n'
        'pattern=yyyy-MM-dd HH:mm:ss\n'
        'chinese=2024 年 10 月 22 日\n'
        'padded=24/1/2 3:4:5',
    pitfalls: <String>[
      'M 是月份、m 是分钟，写错会得到完全错误的结果且不报错。',
      'y 是 year-of-era，跨纪元场景应使用 u（proleptic year）。',
      'DateTimeFormatter 是线程安全的，而旧版 SimpleDateFormat 不是，不要套用旧经验。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 TEXT 的 Locale 改成 Locale.CHINA，观察月份与星期文本的变化。',
        hint: '中文 Locale 下 EEE 与 MMM 会输出中文缩写。',
        answer: '输出变成「周二 10月 22, 2024」这类中文文本。',
      ),
    ],
  ),
  JavaTopic(
    id: 212,
    level: 'intermediate',
    title: 'Java 212：TemporalAdjusters 常用调整',
    summary: '用 next、nextOrSame、firstDayOfMonth 等调整器计算「下一个周一」「月末」。',
    concepts: <String>['TemporalAdjusters', 'DayOfWeek', '月末', 'with'],
    objective: '能用现成调整器表达业务日期规则，不再手写循环推算。',
    explain:
        '`TemporalAdjusters` 提供一批 `TemporalAdjuster`，配合 `date.with(...)` 使用。'
        '`next(DayOfWeek.MONDAY)` 严格取「之后的周一」，如果当天就是周一则跳到下周一；'
        '`nextOrSame(...)` 则允许返回当天。'
        '`firstDayOfMonth()`、`lastDayOfMonth()`、`firstDayOfNextMonth()` 处理月末边界，'
        '比自己加 1 个月再减 1 天更安全，因为不用考虑闰年和大小月。'
        '`dayOfWeekInMonth(2, DayOfWeek.FRIDAY)` 表示「当月第二个周五」。',
    code: r'''import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;

public class Main {
    public static void main(String[] args) {
        LocalDate friday = LocalDate.of(2024, 10, 25);
        System.out.println("dayOfWeek=" + friday.getDayOfWeek());
        System.out.println("nextMonday=" + friday.with(
                TemporalAdjusters.next(DayOfWeek.MONDAY)));
        System.out.println("nextOrSame=" + friday.with(
                TemporalAdjusters.nextOrSame(DayOfWeek.FRIDAY)));
        System.out.println("previousFriday=" + friday.with(
                TemporalAdjusters.previous(DayOfWeek.FRIDAY)));
        System.out.println("firstDay=" + friday.with(TemporalAdjusters.firstDayOfMonth()));
        System.out.println("lastDay=" + friday.with(TemporalAdjusters.lastDayOfMonth()));
        System.out.println("secondFriday=" + friday.with(
                TemporalAdjusters.dayOfWeekInMonth(2, DayOfWeek.FRIDAY)));
        System.out.println("nextMonthFirst=" + friday.with(
                TemporalAdjusters.firstDayOfNextMonth()));
        System.out.println("lastDayFeb=" + LocalDate.of(2024, 2, 10).with(
                TemporalAdjusters.lastDayOfMonth()));
    }
}''',
    output:
        'dayOfWeek=FRIDAY\n'
        'nextMonday=2024-10-28\n'
        'nextOrSame=2024-10-25\n'
        'previousFriday=2024-10-18\n'
        'firstDay=2024-10-01\n'
        'lastDay=2024-10-31\n'
        'secondFriday=2024-10-11\n'
        'nextMonthFirst=2024-11-01\n'
        'lastDayFeb=2024-02-29',
    pitfalls: <String>[
      'next() 永远向前跳，即使当天就是目标星期；需要包含当天时用 nextOrSame。',
      '手写「加一个月减一天」求月末在 1 月 31 日会出错，应该用 lastDayOfMonth。',
      'TemporalAdjuster 只返回新对象，原 LocalDate 不会被修改。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '计算 2024 年 10 月的最后一个工作日（周一到周五）。',
        hint: '从 lastDayOfMonth 往前退，遇到周末继续退。',
        answer:
            'LocalDate last = date.with(TemporalAdjusters.lastDayOfMonth()); while (last.getDayOfWeek() == DayOfWeek.SATURDAY || last.getDayOfWeek() == DayOfWeek.SUNDAY) { last = last.minusDays(1); }',
      ),
    ],
  ),
  JavaTopic(
    id: 213,
    level: 'advanced',
    title: 'Java 213：用 Clock 注入时间',
    summary: '把 Clock.fixed 传给业务方法，让依赖「现在」的逻辑可测试且可复现。',
    concepts: <String>['Clock', 'Clock.fixed', '可测试性', '依赖注入'],
    objective: '能改造依赖当前时间的代码，使其在测试中产生完全确定的输出。',
    explain:
        '直接调用 `LocalDate.now()` 或 `Instant.now()` 会让逻辑依赖系统时钟，'
        '测试只能靠「差不多等于」来断言，既脆弱又无法复现历史时刻。'
        '`Clock` 是时间来源的抽象：生产用 `Clock.systemUTC()`，'
        '测试用 `Clock.fixed(instant, zone)` 或 `Clock.offset(...)`。'
        '业务方法接收 `Clock` 参数，内部写 `LocalDate.now(clock)`，'
        '这样同一份代码在测试里永远得到同一个日期。'
        '这是「可测试性驱动设计」最典型的例子之一。',
    code: r'''import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;

public class Main {
    public static void main(String[] args) {
        Clock fixed = Clock.fixed(Instant.parse("2024-10-22T20:00:00Z"), ZoneOffset.UTC);
        System.out.println("utcToday=" + today(fixed));
        System.out.println("shanghaiToday=" + LocalDate.now(
                fixed.withZone(ZoneId.of("Asia/Shanghai"))));
        System.out.println("stable=" + today(fixed).equals(today(fixed)));
        System.out.println("instant=" + fixed.instant());
        System.out.println("zone=" + fixed.getZone());
        System.out.println("dueDate=" + dueDate(fixed, 7));
    }

    static LocalDate today(Clock clock) {
        return LocalDate.now(clock);
    }

    static LocalDate dueDate(Clock clock, int days) {
        return LocalDate.now(clock).plusDays(days);
    }
}''',
    output:
        'utcToday=2024-10-22\n'
        'shanghaiToday=2024-10-23\n'
        'stable=true\n'
        'instant=2024-10-22T20:00:00Z\n'
        'zone=Z\n'
        'dueDate=2024-10-29',
    pitfalls: <String>[
      '只在最外层固定 Clock、内部又调用 now() 的代码仍然不可测试。',
      'Clock.fixed 的时区参数决定 LocalDate.now(clock) 的结果，UTC 与东八区可能差一天。',
      '生产环境不要固定时钟，否则时间会永远停在某一天。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 Clock.fixed 把时间设成 2024-12-31T20:00:00Z，观察 UTC 与上海日期的差异。',
        hint: '东八区比 UTC 早 8 小时，20:00Z 已经是次日 04:00。',
        answer: 'UTC 下 today 是 2024-12-31，上海时区下是 2025-01-01。',
      ),
    ],
  ),
  JavaTopic(
    id: 214,
    level: 'beginner',
    title: 'Java 214：epoch 秒与毫秒互转',
    summary: '在 Instant、epoch 秒、epoch 毫秒与字符串之间做无损转换。',
    concepts: <String>['epoch', 'toEpochMilli', 'ofEpochSecond', '精度'],
    objective: '能安全地在各种时间戳表示之间转换，并知道秒级转换会丢精度。',
    explain:
        'Unix 时间戳是「自 1970-01-01T00:00:00Z 起的秒数」，'
        'Java 用 `Instant.ofEpochSecond(sec)` 或 `Instant.ofEpochMilli(ms)` 构造，'
        '反向用 `toEpochMilli()`、`getEpochSecond()`。'
        '秒级表示会丢掉毫秒和纳秒，所以「秒 ↔ 毫秒」往返必须注意取整方向。'
        '`Instant.ofEpochSecond(sec, nanoAdjustment)` 可以同时给秒和纳秒。'
        '存储时间时优先用毫秒或 ISO-8601 字符串，秒级只适合对精度无要求的场景。',
    code: r'''import java.time.Instant;

public class Main {
    public static void main(String[] args) {
        Instant moment = Instant.parse("2024-10-22T08:00:00.123Z");
        long millis = moment.toEpochMilli();
        System.out.println("millis=" + millis);
        System.out.println("back=" + Instant.ofEpochMilli(millis));
        System.out.println("lossless=" + Instant.ofEpochMilli(millis).equals(moment));
        long seconds = moment.getEpochSecond();
        System.out.println("seconds=" + seconds);
        System.out.println("secondsDropMillis=" + Instant.ofEpochSecond(seconds)
                .equals(moment));
        System.out.println("withNano=" + Instant.ofEpochSecond(seconds, 123_000_000));
        System.out.println("nano=" + moment.getNano());
        System.out.println("plusMillis=" + Instant.ofEpochMilli(millis + 1000));
        System.out.println("before=" + Instant.EPOCH);
    }
}''',
    output:
        'millis=1729584000123\n'
        'back=2024-10-22T08:00:00.123Z\n'
        'lossless=true\n'
        'seconds=1729584000\n'
        'secondsDropMillis=false\n'
        'withNano=2024-10-22T08:00:00.123Z\n'
        'nano=123000000\n'
        'plusMillis=2024-10-22T08:00:01.123Z\n'
        'before=1970-01-01T00:00:00Z',
    pitfalls: <String>[
      '用秒级时间戳存储带毫秒的事件，会永久丢失精度。',
      '把 int 当毫秒时间戳会溢出（2038 年问题），必须用 long。',
      'epoch 毫秒不受时区影响，格式化成本地时间才需要时区。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把 millis 除以 1000 再乘 1000，观察往返后是否仍等于原时刻。',
        hint: '123 毫秒会被截断。',
        answer:
            'Instant.ofEpochMilli(millis / 1000 * 1000) 是 2024-10-22T08:00:00Z，丢掉了 123 毫秒。',
      ),
    ],
  ),
  JavaTopic(
    id: 215,
    level: 'intermediate',
    title: 'Java 215：精确运算与溢出检测',
    summary: '对比静默溢出的 + 与抛异常的 Math.addExact/multiplyExact。',
    concepts: <String>[
      '溢出',
      'Math.addExact',
      'Math.multiplyExact',
      'ArithmeticException',
    ],
    objective: '能在关键计算里用 exact 方法把溢出变成显式错误，而不是错误的结果。',
    explain:
        'Java 的整数运算在溢出时**静默回绕**：`Integer.MAX_VALUE + 1` 等于 `Integer.MIN_VALUE`。'
        '这类错误极难发现，因为结果看起来仍是一个合法数字。'
        '`Math.addExact`、`subtractExact`、`multiplyExact`、`toIntExact` 会在溢出时抛 `ArithmeticException`，'
        '把「悄悄算错」变成「立刻失败」。'
        '`Math.abs(Integer.MIN_VALUE)` 也是负数，因为它的相反数超出范围，'
        '所以取绝对值要用 `Math.absExact`（Java 15+）或先提升到 long。',
    code: r'''public class Main {
    public static void main(String[] args) {
        int max = Integer.MAX_VALUE;
        System.out.println("wraps=" + (max + 1));
        System.out.println("minValue=" + Integer.MIN_VALUE);
        System.out.println("absMin=" + Math.abs(Integer.MIN_VALUE));
        System.out.println("addExact=" + guarded(() -> Math.addExact(max, 1)));
        System.out.println("multiplyExact=" + guarded(() -> Math.multiplyExact(100_000, 100_000)));
        System.out.println("toIntExact=" + guarded(() -> Math.toIntExact(5_000_000_000L)));
        System.out.println("safe=" + Math.addExact(1_000, 2_000));
        System.out.println("longMath=" + ((long) max + 1));
        System.out.println("promoted=" + ((long) max + 1 == 2_147_483_648L));
    }

    static String guarded(Runnable action) {
        try {
            action.run();
            return "ok";
        } catch (ArithmeticException error) {
            return "ArithmeticException";
        }
    }
}''',
    output:
        'wraps=-2147483648\n'
        'minValue=-2147483648\n'
        'absMin=-2147483648\n'
        'addExact=ArithmeticException\n'
        'multiplyExact=ArithmeticException\n'
        'toIntExact=ArithmeticException\n'
        'safe=3000\n'
        'longMath=2147483648\n'
        'promoted=true',
    pitfalls: <String>[
      'Math.abs(Integer.MIN_VALUE) 仍然是负数，这是最容易踩的坑之一。',
      'Math.multiplyExact(int, int) 与 (long, long) 是不同重载，选错仍可能溢出。',
      '不要用 try/catch 包住整个循环来兜底溢出，应该提前用 long 或 BigInteger。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 Math.multiplyExact 计算 2_000_000_000 * 5，观察抛出的异常类型。',
        hint: '两个 int 相乘溢出，返回 long 的重载不会抛。',
        answer:
            'Math.multiplyExact(2_000_000_000, 5) 抛 ArithmeticException: integer overflow。',
      ),
    ],
  ),
  JavaTopic(
    id: 216,
    level: 'intermediate',
    title: 'Java 216：floorMod 与 floorDiv',
    summary: '负数取模的两种语义：Java 的 % 向零取整，floorMod 向负无穷取整。',
    concepts: <String>['floorMod', 'floorDiv', '取模', '环形索引'],
    objective: '能解释 -7 % 3 的结果，并用 floorMod 实现循环数组下标。',
    explain:
        'Java 的 `%` 遵循「被除数符号」：`-7 % 3 == -1`，'
        '因为 `-7 / 3 == -2`（向零取整），余数是 -1。'
        '数学上更常用的是「余数恒为非负」，即 `floorMod(-7, 3) == 2`，'
        '对应 `floorDiv(-7, 3) == -3`。'
        '做循环数组、时间回绕、角度归一化时，负下标会直接导致 `IndexOutOfBoundsException`，'
        '所以这些场景必须用 `Math.floorMod`。'
        '`floorMod` 对 long 和 int 都有重载。',
    code: r'''public class Main {
    public static void main(String[] args) {
        System.out.println("remainder=" + (-7 % 3));
        System.out.println("floorMod=" + Math.floorMod(-7, 3));
        System.out.println("division=" + (-7 / 3));
        System.out.println("floorDiv=" + Math.floorDiv(-7, 3));
        System.out.println("positive=" + Math.floorMod(7, 3));
        String[] week = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
        System.out.println("ringForward=" + week[Math.floorMod(8, week.length)]);
        System.out.println("ringBackward=" + week[Math.floorMod(-1, week.length)]);
        System.out.println("hourWrap=" + Math.floorMod(-3, 24));
        System.out.println("longOverload=" + Math.floorMod(-7L, 3L));
        System.out.println("zeroDenominator=" + guarded());
    }

    static String guarded() {
        try {
            return String.valueOf(Math.floorMod(1, 0));
        } catch (ArithmeticException error) {
            return "ArithmeticException";
        }
    }
}''',
    output:
        'remainder=-1\n'
        'floorMod=2\n'
        'division=-2\n'
        'floorDiv=-3\n'
        'positive=1\n'
        'ringForward=Tue\n'
        'ringBackward=Sun\n'
        'hourWrap=21\n'
        'longOverload=2\n'
        'zeroDenominator=ArithmeticException',
    pitfalls: <String>[
      '用 % 计算循环下标，遇到负偏移会得到负下标并抛数组越界。',
      'floorDiv 与 / 在正数上结果相同，只有负数才不同，测试要覆盖负数。',
      '除数为 0 时两种方法都抛 ArithmeticException，不是返回 0。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 floorMod 把任意角度（度）归一化到 [0, 360)。',
        hint: 'Math.floorMod(angle, 360)。',
        answer: 'Math.floorMod(-30, 360) 得到 330。',
      ),
    ],
  ),
  JavaTopic(
    id: 217,
    level: 'advanced',
    title: 'Java 217：数值稳定性与 hypot',
    summary: '比较手写 sqrt(x*x+y*y) 与 Math.hypot 在极大值下的溢出行为。',
    concepts: <String>['Math.hypot', '溢出', 'NaN', '数值稳定性'],
    objective: '能解释为什么几何距离应该用 hypot，而不是自己算平方和再开方。',
    explain:
        '`Math.hypot(x, y)` 计算 `sqrt(x² + y²)`，但内部做了缩放，'
        '即使 `x²` 会超出 double 范围也不会溢出成 Infinity。'
        '手写 `Math.sqrt(x * x + y * y)` 在 `x = 1e200` 时平方就变成 Infinity，结果直接失真。'
        '同理 `Math.pow`、`Math.exp` 在边界附近会返回 Infinity 或 0，'
        '需要判断 `Double.isInfinite` / `Double.isNaN`。'
        '注意 `Math.hypot` 比手写版本慢，但正确性优先。',
    code: r'''public class Main {
    public static void main(String[] args) {
        double x = 3.0;
        double y = 4.0;
        System.out.println("hypot=" + Math.hypot(x, y));
        System.out.println("manual=" + Math.sqrt(x * x + y * y));
        double big = 1e200;
        System.out.println("manualBig=" + Math.sqrt(big * big + big * big));
        System.out.println("hypotBig=" + Math.hypot(big, big));
        System.out.println("hypotBigFinite=" + Double.isFinite(Math.hypot(big, big)));
        System.out.println("powOverflow=" + Math.pow(1e300, 2));
        System.out.println("expUnderflow=" + Math.exp(-1000));
        System.out.println("nanPropagates=" + (Math.sqrt(-1.0) != Math.sqrt(-1.0)));
        System.out.println("logZero=" + Math.log(0));
        System.out.println("cbrtNegative=" + Math.cbrt(-27.0));
    }
}''',
    output:
        'hypot=5.0\n'
        'manual=5.0\n'
        'manualBig=Infinity\n'
        'hypotBig=1.414213562373095E200\n'
        'hypotBigFinite=true\n'
        'powOverflow=Infinity\n'
        'expUnderflow=0.0\n'
        'nanPropagates=true\n'
        'logZero=-Infinity\n'
        'cbrtNegative=-3.0',
    pitfalls: <String>[
      '手写平方和在大数下会溢出成 Infinity，且无法通过后续判断恢复。',
      'NaN 与任何值比较（包括它自己）都是 false，只能用 Double.isNaN 判断。',
      'Math.log(0) 返回 -Infinity 而不是抛异常，调用方必须自己检查。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 hypot 计算三维距离，并说明为什么不直接相加三个平方。',
        hint: '可以先 hypot(x, y) 再 hypot(结果, z)。',
        answer: 'Math.hypot(Math.hypot(x, y), z) 逐级缩放，避免中间结果溢出。',
      ),
    ],
  ),
  JavaTopic(
    id: 218,
    level: 'intermediate',
    title: 'Java 218：种子随机数可复现',
    summary: '用 new Random(seed) 生成完全可复现的序列，理解它与 SecureRandom 的分工。',
    concepts: <String>['Random', '种子', '可复现', 'nextInt(bound)'],
    objective: '能写出可复现的随机序列用于测试与模拟，并知道它不能用于安全场景。',
    explain:
        '`new Random(42)` 的序列由种子完全决定：同一 JDK 版本、同一算法下，'
        '两次运行得到的数字完全相同。'
        '这让你可以给「洗牌」「抽样」「模拟」写确定性测试。'
        '`nextInt(bound)` 返回 `[0, bound)`，内部做了拒绝采样以避免取模偏差；'
        '`ints(count, origin, bound)` 生成流，便于配合 Stream 使用。'
        '但 `Random` 是可预测的，绝不能用于令牌、密钥、验证码；'
        '那类场景必须用 `SecureRandom`。',
    code: r'''import java.util.Arrays;
import java.util.Random;

public class Main {
    public static void main(String[] args) {
        Random first = new Random(42);
        Random second = new Random(42);
        int[] a = new int[5];
        int[] b = new int[5];
        for (int i = 0; i < a.length; i++) {
            a[i] = first.nextInt(100);
            b[i] = second.nextInt(100);
        }
        System.out.println("first=" + Arrays.toString(a));
        System.out.println("same=" + Arrays.equals(a, b));
        Random different = new Random(43);
        System.out.println("differentSeed=" + (different.nextInt(100) != a[0]));
        System.out.println("bounded=" + (first.nextInt(10) >= 0));
        System.out.println("streamCount=" + new Random(7).ints(6, 0, 6).count());
        System.out.println("range=" + new Random(7).ints(6, 0, 6).allMatch(v -> v >= 0 && v < 6));
        int[] deck = {1, 2, 3, 4, 5};
        shuffle(deck, new Random(1));
        System.out.println("shuffled=" + Arrays.toString(deck));
    }

    static void shuffle(int[] values, Random random) {
        for (int i = values.length - 1; i > 0; i--) {
            int j = random.nextInt(i + 1);
            int tmp = values[i];
            values[i] = values[j];
            values[j] = tmp;
        }
    }
}''',
    output:
        'first=[30, 63, 48, 84, 70]\n'
        'same=true\n'
        'differentSeed=true\n'
        'bounded=true\n'
        'streamCount=6\n'
        'range=true\n'
        'shuffled=[3, 4, 2, 5, 1]',
    pitfalls: <String>[
      'Random 的具体算法在不同 JDK 版本可能变化，跨版本不要依赖同一序列。',
      '用 nextInt() % n 会产生取模偏差，应直接用 nextInt(n)。',
      '共享一个 Random 实例在多线程下会有竞争，并发场景用 ThreadLocalRandom。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '把种子从 42 改成 7，观察 first 序列是否变化。',
        hint: '不同种子产生完全不同的序列。',
        answer: 'new Random(7) 生成的 5 个 [0,100) 整数与种子 42 的结果不同。',
      ),
    ],
  ),
  JavaTopic(
    id: 219,
    level: 'advanced',
    title: 'Java 219：浮点比较与 -0.0',
    summary: '用 Double.compare 处理 NaN 与 -0.0，避免 == 带来的三个经典陷阱。',
    concepts: <String>['Double.compare', 'NaN', '负零', 'BigDecimal'],
    objective: '能解释 NaN != NaN、-0.0 == 0.0 的含义，并写出正确的排序比较器。',
    explain:
        'IEEE 754 有三条反直觉的规则：`NaN == NaN` 是 false；'
        '`0.0 == -0.0` 是 true，但 `Double.compare(0.0, -0.0)` 是 1（不相等）；'
        '`0.1 + 0.2 != 0.3`，因为二进制无法精确表示这些十进制小数。'
        '因此「比较浮点数」几乎总要用 `Double.compare`，'
        '它把 NaN 视为最大值、把 -0.0 排在 0.0 之前，形成全序，适合排序。'
        '判断相等要用「差的绝对值小于容差」，金额计算则应该用 `BigDecimal`。',
    code: r'''import java.math.BigDecimal;
import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        double nan = Double.NaN;
        System.out.println("nanEquals=" + (nan == nan));
        System.out.println("isNan=" + Double.isNaN(nan));
        System.out.println("zeroEquals=" + (0.0 == -0.0));
        System.out.println("zeroCompared=" + Double.compare(0.0, -0.0));
        System.out.println("pointThree=" + (0.1 + 0.2));
        System.out.println("pointThreeEquals=" + (0.1 + 0.2 == 0.3));
        System.out.println("tolerant=" + (Math.abs(0.1 + 0.2 - 0.3) < 1e-9));
        System.out.println("bigDecimal=" + new BigDecimal("0.1").add(new BigDecimal("0.2")));
        double[] values = {3.0, Double.NaN, -0.0, 0.0, 1.0};
        Arrays.sort(values);
        System.out.println("sorted=" + Arrays.toString(values));
        System.out.println("compareNaN=" + Double.compare(1.0, Double.NaN));
    }
}''',
    output:
        'nanEquals=false\n'
        'isNan=true\n'
        'zeroEquals=true\n'
        'zeroCompared=1\n'
        'pointThree=0.30000000000000004\n'
        'pointThreeEquals=false\n'
        'tolerant=true\n'
        'bigDecimal=0.3\n'
        'sorted=[-0.0, 0.0, 1.0, 3.0, NaN]\n'
        'compareNaN=-1',
    pitfalls: <String>[
      '用 == 比较 NaN 永远为 false，判断必须用 Double.isNaN。',
      '金额不能用 double，0.1 + 0.2 的误差会累积成对不上账。',
      '容差比较的 epsilon 要按数值量级选择，固定 1e-9 对大数没有意义。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '用 BigDecimal 计算 1.0 减 0.9 再减 0.1，观察结果是否为零。',
        hint: 'BigDecimal 的 subtract 保留十进制精度。',
        answer:
            'new BigDecimal("1.0").subtract(new BigDecimal("0.9")).subtract(new BigDecimal("0.1")) 得到 0.0。',
      ),
    ],
  ),
  JavaTopic(
    id: 220,
    level: 'advanced',
    title: 'Java 220：沙箱迷你键值存储',
    summary: '综合 Files、DataOutputStream、CRC32 与 Base64，做一个带校验的临时文件存储。',
    concepts: <String>['综合应用', '二进制格式', 'CRC32', 'Base64'],
    objective: '能把前面学过的 I/O、校验与编码组合成一个可验证的小型持久化格式。',
    explain:
        '这个练习把所有零件装到一起：'
        '用 `Files.createTempDirectory` 隔离存储，'
        '`DataOutputStream` 写出「key 长度 + key + value 长度 + value + CRC32」的记录，'
        '`CRC32` 覆盖 value 内容，读取时逐条校验，'
        '最后用 `Base64` 把整段字节转成可打印文本方便展示。'
        '真实存储还要加魔数、版本号、原子替换和索引，'
        '但「长度前缀 + 校验和」这两点已经能覆盖绝大多数自研格式的需求。',
    code: r'''import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.stream.Stream;
import java.util.zip.CRC32;

public class Main {
    public static void main(String[] args) throws IOException {
        Path dir = Files.createTempDirectory("qfli-store-");
        try {
            Path file = dir.resolve("store.bin");
            Map<String, String> data = new LinkedHashMap<>();
            data.put("theme", "dark");
            data.put("lang", "java");
            data.put("region", "cn");
            byte[] encoded = encode(data);
            Files.write(file, encoded);
            System.out.println("records=" + data.size());
            System.out.println("bytes=" + encoded.length);
            Map<String, String> restored = decode(Files.readAllBytes(file));
            System.out.println("equal=" + restored.equals(data));
            System.out.println("first=" + restored.keySet().iterator().next());
            System.out.println("base64Head=" + Base64.getEncoder().encodeToString(encoded)
                    .substring(0, 8));
            System.out.println("corrupted=" + corrupted(encoded));
        } finally {
            cleanup(dir);
        }
    }

    static void cleanup(Path root) {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.sorted(Comparator.reverseOrder()).forEach(Main::deleteIfPossible);
        } catch (IOException error) {
            root.toFile().deleteOnExit();
        }
    }

    static void deleteIfPossible(Path path) {
        try {
            Files.deleteIfExists(path);
        } catch (IOException error) {
            path.toFile().deleteOnExit();
        }
    }

    static byte[] encode(Map<String, String> data) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (DataOutputStream out = new DataOutputStream(buffer)) {
            for (Map.Entry<String, String> entry : data.entrySet()) {
                byte[] key = entry.getKey().getBytes(StandardCharsets.UTF_8);
                byte[] value = entry.getValue().getBytes(StandardCharsets.UTF_8);
                out.writeByte(key.length);
                out.write(key);
                out.writeShort(value.length);
                out.write(value);
                CRC32 crc = new CRC32();
                crc.update(value);
                out.writeInt((int) crc.getValue());
            }
            out.writeByte(0);
        }
        return buffer.toByteArray();
    }

    static Map<String, String> decode(byte[] payload) throws IOException {
        Map<String, String> result = new LinkedHashMap<>();
        try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(payload))) {
            while (true) {
                int keyLength = in.readUnsignedByte();
                if (keyLength == 0) {
                    break;
                }
                byte[] key = new byte[keyLength];
                in.readFully(key);
                byte[] value = new byte[in.readUnsignedShort()];
                in.readFully(value);
                int expected = in.readInt();
                CRC32 crc = new CRC32();
                crc.update(value);
                if ((int) crc.getValue() != expected) {
                    throw new IOException("checksum mismatch");
                }
                result.put(new String(key, StandardCharsets.UTF_8),
                        new String(value, StandardCharsets.UTF_8));
            }
        }
        return result;
    }

    static boolean corrupted(byte[] payload) {
        byte[] copy = payload.clone();
        copy[7] = (byte) (copy[7] ^ 0xFF);
        try {
            decode(copy);
            return false;
        } catch (IOException | RuntimeException error) {
            return true;
        }
    }
}''',
    output:
        'records=3\n'
        'bytes=47\n'
        'equal=true\n'
        'first=theme\n'
        'base64Head=BXRoZW1l\n'
        'corrupted=true',
    pitfalls: <String>[
      '用 writeByte 存长度时上限只有 255，key 更长必须改用 writeShort 或 writeInt。',
      'CRC 校验只能发现意外损坏，不能防止有意篡改，而且这里只覆盖 value 不覆盖 key。',
      '整段重写不是原子操作，真实场景应写入临时文件再 rename。',
    ],
    tasks: <JavaTask>[
      JavaTask(
        prompt: '给格式加上 4 字节魔数与 1 字节版本号，并让 decode 先校验它们。',
        hint: '在写记录前 writeInt(0x51464C49) 和 writeByte(1)，读取时对应读取并比较。',
        answer:
            'out.writeInt(0x51464C49); out.writeByte(1); 读取端 in.readInt() != 0x51464C49 时抛 IOException("bad magic")。',
      ),
    ],
  ),
];
