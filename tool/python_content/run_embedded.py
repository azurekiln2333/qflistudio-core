#!/usr/bin/env python3
"""Run a batch of Python snippets on the real embedded MicroPython DLL.

Usage:  python run_embedded.py <dll_path> <batch.json> [out.json]

The batch is a JSON list of {"id": str, "code": str, "stdin": str}. The result
is a JSON list of {"id", "exitCode", "output", "error"} written to out.json (or
stdout). This is the authoritative verification path for `runtime == embedded`
samples: it must be the shipped MicroPython build, never CPython.
"""
import ctypes
import json
import os
import sys
import tempfile


class QfliPyRunResult(ctypes.Structure):
    _fields_ = [
        ("exit_code", ctypes.c_int),
        ("output", ctypes.c_char_p),
        ("error", ctypes.c_char_p),
        ("truncated", ctypes.c_int),
    ]


def load(dll_path):
    lib = ctypes.CDLL(os.path.abspath(dll_path))
    lib.qfli_py_version.restype = ctypes.c_char_p
    lib.qfli_py_run_into.argtypes = [
        ctypes.POINTER(QfliPyRunResult),
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_int,
    ]
    lib.qfli_py_result_free.argtypes = [ctypes.POINTER(QfliPyRunResult)]
    return lib


def run(lib, project, code, stdin):
    result = QfliPyRunResult()
    lib.qfli_py_run_into(
        ctypes.byref(result),
        code.encode("utf-8"),
        stdin.encode("utf-8"),
        8192,
        project.encode("utf-8"),
        os.path.join(project, "main.py").encode("utf-8"),
        0,
    )
    out = result.output.decode("utf-8", "replace") if result.output else ""
    err = result.error.decode("utf-8", "replace") if result.error else ""
    code_exit = result.exit_code
    lib.qfli_py_result_free(ctypes.byref(result))
    return code_exit, out, err


def main():
    dll_path, batch_path = sys.argv[1], sys.argv[2]
    out_path = sys.argv[3] if len(sys.argv) > 3 else None
    lib = load(dll_path)
    with open(batch_path, encoding="utf-8") as handle:
        batch = json.load(handle)
    results = []
    with tempfile.TemporaryDirectory(prefix="qfli_py_verify_") as project:
        for item in batch:
            code_exit, out, err = run(
                lib, project, item["code"], item.get("stdin", "")
            )
            results.append(
                {
                    "id": item["id"],
                    "exitCode": code_exit,
                    "output": out,
                    "error": err,
                }
            )
    payload = json.dumps(results, ensure_ascii=False)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as handle:
            handle.write(payload)
    else:
        print(payload)


if __name__ == "__main__":
    main()
