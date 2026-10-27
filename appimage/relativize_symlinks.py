#!/usr/bin/env python3
import os
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <appdir>", file=sys.stderr)
        return 2

    appdir = os.path.abspath(sys.argv[1])
    changed = 0
    skipped = 0

    for dirpath, dirnames, filenames in os.walk(appdir):
        for name in list(dirnames) + filenames:
            path = os.path.join(dirpath, name)
            if not os.path.islink(path):
                continue
            target = os.readlink(path)
            if not target.startswith("/"):
                continue
            host_target = appdir + target
            if not os.path.exists(host_target):
                skipped += 1
                continue
            relative = os.path.relpath(host_target, os.path.dirname(path))
            os.unlink(path)
            os.symlink(relative, path)
            changed += 1

    print(f"rewrote {changed} absolute symlink(s), skipped {skipped} dangling link(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
