# Python consumer fixture identity clarification

Date: 2026-11-27. Source-only coordination with Python owner w50:p1 and bounded core reviewer w63:p3; no local product tooling or content change.

At provisional core `476a30acee21dc486ee2849dd8064a7be665e4d5`, `assets/content/examples.json` is blob `4021b3df3edc706aa79a252eb2a6fec4cf58c0ba`. Its 120 Python examples have no `pricing/__init__.py` or `pricing/totals.py` fixture. Example 008 supplies stdin. Example 117 is authored in `tool/python_content/python_topics_advanced.dart` as CPython standard-library/pip/venv content, with `PythonRuntime.cpython`, empty `inputFixtures`, and `sourceLessonId` `python-tutorial-117-lesson`.

The source pipeline introduced in `e7f2cd90e0179cb252a07d1b58d9529c8fad0a02` and first 120-row emission `504925a7fbc6fe3c798f044944c107b59f7724fb` agree on that identity. The generator emits fixtures from `PythonTopic.input`; topic 117 has none. This bounded evidence does not support lost pricing content, renaming a different stable ID, or restoring a pricing package over example 117.

Python's owner reported the conflicting expectation in its app-check `45961737494` at Python `0bf2f3805966d2c4381612dd17250b17d7a94237`. The owner accepted correction to the shipped 008/117 contracts while retaining package import/native execution coverage using a separately named test-owned package fixture. That implementation and hosted evidence belong to Python. Core does not edit the consumer, weaken its assertions, change the catalog, or claim its rerun passed.

Core-last publication remains in force; this clarification requires no new core content revision.
