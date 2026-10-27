#!/usr/bin/env python3
import os
import sys

OLD = b"/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0"
NEW = b"usr//lib/x86_64-linux-gnu/webkit2gtk-4.0"


def main() -> int:
    if len(OLD) != len(NEW):
        print("replacement string must have the same length", file=sys.stderr)
        return 1
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <appdir-or-libdir>", file=sys.stderr)
        return 2

    root = sys.argv[1]
    total = 0
    already = 0
    touched = 0
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            with open(path, "rb") as f:
                data = f.read()
            count = data.count(OLD)
            if count == 0:
                already += data.count(NEW)
                continue
            with open(path, "r+b") as f:
                f.write(data.replace(OLD, NEW))
            print(f"  {path}: {count}")
            total += count
            touched += 1

    if total:
        print(f"patched {total} occurrence(s) in {touched} file(s)")
        return 0
    if already:
        print(f"WebKit helper path already patched ({already} occurrence(s))")
        return 0
    print("WebKit helper path not found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
