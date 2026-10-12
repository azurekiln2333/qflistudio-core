import 'python_topic.dart';
import 'topics_basics.dart';
import 'topics_containers_functions.dart';
import 'topics_modules_oop.dart';
import 'python_topics_advanced.dart';

/// The full authored Python curriculum, ordered by id 1..N.
///
/// Split into staged files to keep each reviewable:
///   - [pythonTopicsBasics]               001-016 起步与流程控制
///   - [pythonTopicsContainersFunctions]  017-040 容器与函数
///   - [pythonTopicsModulesOop]           041-060 模块/异常/文件 与 OOP
///   - [pythonTopicsAdvanced]             061-120 进阶/高级/工程/CPython
const List<PythonTopic> pythonTopics = <PythonTopic>[
  ...pythonTopicsBasics,
  ...pythonTopicsContainersFunctions,
  ...pythonTopicsModulesOop,
  ...pythonTopicsAdvanced,
];
