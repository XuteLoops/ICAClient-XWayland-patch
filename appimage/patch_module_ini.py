#!/usr/bin/env python3
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <module.ini>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    out = []
    in_ica = False
    have_generic_flag = any(line.strip() == "GenericUSB=on" for line in lines)
    have_generic_section = any(line.strip() == "[GenericUSB]" for line in lines)

    for line in lines:
        stripped = line.strip()
        if stripped == "[ICA 3.0]":
            in_ica = True
        elif stripped.startswith("[") and stripped != "[ICA 3.0]":
            in_ica = False

        if line.startswith("VirtualDriver") and "GenericUSB" not in line:
            line = line.rstrip("\n") + ", GenericUSB\n"

        if stripped == "[GenericUSB]":
            have_generic_section = True

        out.append(line)

        if in_ica and stripped == "[ICA 3.0]" and not have_generic_flag:
            out.append("GenericUSB=on\n")
            have_generic_flag = True

    if not have_generic_section:
        out.append("[GenericUSB]\n")
        out.append("DriverName = VDGUSB.DLL\n")

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(out)

    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
