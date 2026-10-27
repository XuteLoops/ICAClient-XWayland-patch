#!/usr/bin/env python3
import gzip
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

PACKAGES = [
    "libjpeg-turbo8",
    "libsoup2.4-1",
    "libenchant-2-2",
    "libhunspell-1.7-0",
    "libhyphen0",
    "libmanette-0.2-0",
    "libsecret-1-0",
    "libnotify4",
]

SOURCES = [
    ("jammy-updates", "https://archive.ubuntu.com/ubuntu", ["main", "universe"]),
    ("jammy-security", "https://security.ubuntu.com/ubuntu", ["main", "universe"]),
    ("jammy", "https://archive.ubuntu.com/ubuntu", ["main", "universe"]),
]

LIB_SUBDIRS = ["usr/lib/x86_64-linux-gnu", "lib/x86_64-linux-gnu"]


def fetch(url: str, dest: str) -> None:
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "citrix-appimage-build/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, open(dest, "wb") as out:
        shutil.copyfileobj(response, out)


def extract_deb(deb_path: str, root: str) -> None:
    if shutil.which("dpkg-deb"):
        subprocess.run(["dpkg-deb", "-x", deb_path, root], check=True)
        return
    if shutil.which("bsdtar"):
        subprocess.run(["bsdtar", "-xf", deb_path, "-C", root], check=True)
        return
    ar = shutil.which("ar")
    tar = shutil.which("tar")
    if not ar or not tar:
        raise RuntimeError("cannot extract .deb: install dpkg-deb, bsdtar, or ar and tar")
    listing = subprocess.run(
        [ar, "t", deb_path], check=True, capture_output=True, text=True
    ).stdout.splitlines()
    member = next((name for name in listing if name.startswith("data.tar")), "")
    if not member:
        raise RuntimeError(f"no data.tar member in {deb_path}")
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        temp_path = tmp.name
    try:
        with open(temp_path, "wb") as out:
            subprocess.run([ar, "p", deb_path, member], check=True, stdout=out)
        subprocess.run([tar, "-xf", temp_path, "-C", root], check=True)
    finally:
        os.unlink(temp_path)


def stanzas(text: str):
    current = {}
    for line in text.splitlines():
        if not line.strip():
            if current:
                yield current
                current = {}
            continue
        if line[0] in " \t":
            continue
        key, _, value = line.partition(":")
        current[key.strip()] = value.strip()
    if current:
        yield current


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <appdir> <workdir>", file=sys.stderr)
        return 2
    appdir = os.path.abspath(sys.argv[1])
    workdir = os.path.abspath(sys.argv[2])
    os.makedirs(workdir, exist_ok=True)

    index_dir = os.path.join(workdir, "indexes")
    os.makedirs(index_dir, exist_ok=True)

    candidates = {}
    for suite, base, components in SOURCES:
        for component in components:
            name = f"{suite}-{component}.Packages.gz"
            path = os.path.join(index_dir, name)
            url = f"{base}/dists/{suite}/{component}/binary-amd64/Packages.gz"
            try:
                fetch(url, path)
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    continue
                raise
            with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
                for stanza in stanzas(f.read()):
                    package = stanza.get("Package")
                    if package not in PACKAGES:
                        continue
                    if stanza.get("Architecture") not in ("amd64", "all"):
                        continue
                    candidates.setdefault(package, []).append((base, stanza))

    missing = [package for package in PACKAGES if package not in candidates]
    if missing:
        print(f"missing Ubuntu 22.04 packages: {', '.join(missing)}", file=sys.stderr)
        return 1

    deb_dir = os.path.join(workdir, "debs")
    extract_dir = os.path.join(workdir, "extract")
    os.makedirs(deb_dir, exist_ok=True)
    os.makedirs(extract_dir, exist_ok=True)

    for package in PACKAGES:
        base, stanza = candidates[package][0]
        filename = stanza["Filename"]
        version = stanza["Version"]
        deb_path = os.path.join(deb_dir, os.path.basename(filename))
        url = f"{base}/{filename}"
        print(f"  {package} {version}")
        fetch(url, deb_path)

        root = os.path.join(extract_dir, package)
        if os.path.isdir(root):
            shutil.rmtree(root)
        os.makedirs(root)
        extract_deb(deb_path, root)

        for subdir in LIB_SUBDIRS:
            source = os.path.join(root, subdir)
            if not os.path.isdir(source):
                continue
            target = os.path.join(appdir, subdir)
            os.makedirs(target, exist_ok=True)
            for entry in os.scandir(source):
                if entry.is_dir(follow_symlinks=False):
                    continue
                destination = os.path.join(target, entry.name)
                if os.path.lexists(destination):
                    os.unlink(destination)
                shutil.copy2(entry.path, destination, follow_symlinks=False)

    print(f"bundled {len(PACKAGES)} Ubuntu 22.04 packages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
