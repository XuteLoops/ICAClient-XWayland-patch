#!/usr/bin/env bash
set -euo pipefail

APPIMAGE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$APPIMAGE_DIR/.." && pwd)"
DEFAULT_WORK="${WORK:-$HOME/.cache/citrix-wayland}"

say() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

abs_path() {
    local path="$1"
    if [[ "$path" != /* ]]; then
        path="$PWD/$path"
    fi
    readlink -f -- "$path"
}

find_usb_next_to() {
    local dir="$1"
    local candidate
    for candidate in \
        "$dir"/ctxusb*.deb \
        "$dir"/ctxusb*.rpm \
        "$dir"/ctxusb*.tar \
        "$dir"/ctxusb*.tar.gz \
        "$dir"/ctxusb*.tgz \
        "$dir"/ctxusb*.tar.xz \
        "$dir"/ctxusb*.txz \
        "$dir"/ctxusb*.tar.bz2 \
        "$dir"/ctxusb*.tbz2 \
        "$dir"/ctxusb*.tar.zst \
        "$dir"/ctxusb*.tzst; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

extract_package() {
    local package="$1"
    local dest="$2"

    [[ -f "$package" ]] || die "package not found: $package"
    mkdir -p "$dest"

    case "${package,,}" in
        *.deb)
            if have dpkg-deb; then
                dpkg-deb -x "$package" "$dest"
            else
                need ar
                need tar
                local member
                member="$(ar t "$package" | awk '/^data\.tar(\.|$)/ { print; exit }')"
                [[ -n "$member" ]] || die "no data.tar member in $package"
                ar p "$package" "$member" | tar -xf - -C "$dest"
            fi
            ;;
        *.rpm)
            if have bsdtar; then
                bsdtar -xf "$package" -C "$dest"
            elif have rpm2cpio && have cpio; then
                rpm2cpio "$package" | (cd "$dest" && cpio -idm --quiet)
            else
                die "cannot extract RPM: install bsdtar or rpm2cpio and cpio"
            fi
            ;;
        *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz2|*.tar.zst|*.tzst)
            need tar
            tar -xf "$package" -C "$dest"
            ;;
        *)
            die "unsupported package type: $package"
            ;;
    esac
}

is_client_root() {
    local dir="$1"
    [[ -f "$dir/selfservice" && -f "$dir/wfica" ]]
}

find_client_root() {
    local root="$1"
    local candidate

    for candidate in \
        "$root/opt/Citrix/ICAClient" \
        "$root" \
        "$root/ICAClient"; do
        if is_client_root "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    candidate="$(find "$root" -type f -name selfservice -print -quit 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        candidate="$(dirname "$candidate")"
        if is_client_root "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    return 1
}

find_setupwfc() {
    local root="$1"
    find "$root" -type f -name setupwfc -print -quit 2>/dev/null
}

run_setupwfc() {
    local installer="$1"
    local target="$2"
    local log="$3"

    need timeout
    mkdir -p "$target"
    local answers
    answers="$(dirname "$log")/setupwfc.answers"
    printf '1\n%s\ny\nn\nn\n3\n' "$target" >"$answers"
    (
        cd -- "$(dirname "$installer")"
        chmod +x "$installer" 2>/dev/null || true
        LANG=C timeout 300 ./setupwfc <"$answers" >"$log" 2>&1
    ) || {
        warn "setupwfc failed; last lines of $log:"
        tail -n 30 "$log" >&2 || true
        return 1
    }
}

prepare_appdir_from_package() {
    local package="$1"
    local appdir="$2"
    local work="$3"
    local extract="$work/extracted-package"
    local root
    local installer

    rm -rf "$extract"
    mkdir -p "$extract"
    say "Extracting $(basename "$package")"
    extract_package "$package" "$extract"

    if root="$(find_client_root "$extract")"; then
        :
    elif installer="$(find_setupwfc "$extract")"; then
        say "Running the Citrix tarball installer"
        root="$work/tarball-install"
        rm -rf "$root"
        run_setupwfc "$installer" "$root" "$work/setupwfc.log" ||
            die "the tarball installer did not complete; install it manually and use the existing mode"
        root="$(find_client_root "$root")" ||
            die "could not locate ICAClient after setupwfc"
    else
        die "could not find selfservice and wfica in $package"
    fi

    root="$(abs_path "$root")"
    rm -rf "$appdir"
    mkdir -p "$appdir"

    if [[ "$root" == "$extract/opt/Citrix/ICAClient" ]]; then
        cp -a "$extract/." "$appdir/"
    elif [[ "$root" == "$extract" ]]; then
        cp -a "$extract/." "$appdir/"
    else
        mkdir -p "$appdir/opt/Citrix"
        cp -a "$root" "$appdir/opt/Citrix/ICAClient"
        local sub
        for sub in etc usr lib; do
            if [[ -d "$extract/$sub" ]]; then
                mkdir -p "$appdir/$sub"
                cp -a "$extract/$sub/." "$appdir/$sub/"
            fi
        done
    fi

    rm -rf "$appdir/DEBIAN" "$appdir/var" "$appdir/.build-id"
    mkdir -p "$appdir/opt/Citrix/ICAClient"
    is_client_root "$appdir/opt/Citrix/ICAClient" ||
        die "client files were not placed in $appdir/opt/Citrix/ICAClient"
}

merge_usb_package() {
    local package="$1"
    local icaroot="$2"
    local rulesdir="$3"
    local work="$4"
    local extract="$work/extracted-usb"
    local usbdir

    rm -rf "$extract"
    mkdir -p "$extract"
    say "Extracting USB support from $(basename "$package")"
    extract_package "$package" "$extract"

    usbdir="$(find "$extract" -type f -name ctxusbd -printf '%h\n' -quit 2>/dev/null || true)"
    if [[ -z "$usbdir" ]]; then
        warn "ctxusbd was not found in $package"
        return 1
    fi

    mkdir -p "$icaroot"
    cp -a "$usbdir/." "$icaroot/"

    if [[ -d "$extract/etc/udev/rules.d" ]]; then
        mkdir -p "$rulesdir"
        cp -a "$extract/etc/udev/rules.d/." "$rulesdir/"
    fi

    local rule
    while IFS= read -r -d '' rule; do
        mkdir -p "$rulesdir"
        install -m 0644 "$rule" "$rulesdir/$(basename "$rule")"
    done < <(find "$extract" -type f -path '*/udev/rules.d/*.rules' -print0 2>/dev/null)

    chmod 0755 "$icaroot/ctxusbd" "$icaroot/ctx_usb_isactive" 2>/dev/null || true
    [[ -f "$icaroot/ctxusb" ]] || die "ctxusb was not found in $package"
    chmod 4755 "$icaroot/ctxusb"
}

ensure_webkit() {
    local icaroot="$1"
    local appdir="$2"
    local work="$3"
    local dest="$appdir/usr/lib/x86_64-linux-gnu"
    local source=""
    local tarball=""
    local lib=""
    local extract="$work/webkit"

    if [[ -f "$dest/libwebkit2gtk-4.0.so.37" && -x "$dest/webkit2gtk-4.0/WebKitWebProcess" ]]; then
        return 0
    fi

    lib="$(find "$icaroot" -type f -name libwebkit2gtk-4.0.so.37 -print -quit 2>/dev/null || true)"
    if [[ -n "$lib" ]]; then
        source="$(dirname "$lib")"
        if [[ ! -x "$source/webkit2gtk-4.0/WebKitWebProcess" ]]; then
            source=""
        fi
    fi

    if [[ -z "$source" ]]; then
        tarball="$(find "$icaroot" -type f -name webkit2gtk-4.0.tar.gz -print -quit 2>/dev/null || true)"
        if [[ -n "$tarball" ]]; then
            say "Extracting bundled WebKitGTK 4.0"
            rm -rf "$extract"
            mkdir -p "$extract"
            tar -xzf "$tarball" -C "$extract"
            lib="$(find "$extract" -type f -name libwebkit2gtk-4.0.so.37 -print -quit 2>/dev/null || true)"
            [[ -n "$lib" ]] || die "unexpected WebKit bundle layout"
            source="$(dirname "$lib")"
        fi
    fi

    if [[ -z "$source" ]]; then
        for source in \
            /usr/lib/x86_64-linux-gnu \
            /usr/lib64 \
            /usr/lib; do
            if [[ -f "$source/libwebkit2gtk-4.0.so.37" &&
                -x "$source/webkit2gtk-4.0/WebKitWebProcess" ]]; then
                warn "using system WebKitGTK 4.0 from $source"
                break
            fi
            source=""
        done
    fi
    [[ -n "$source" ]] || die "WebKitGTK 4.0 was not found in $icaroot or the system"

    mkdir -p "$dest"
    if [[ "$(abs_path "$source")" != "$(abs_path "$dest")" ]]; then
        cp -a "$source/." "$dest/"
    fi
    [[ -f "$dest/libwebkit2gtk-4.0.so.37" ]] || die "WebKitGTK libraries were not installed"
    [[ -x "$dest/webkit2gtk-4.0/WebKitWebProcess" ]] || die "WebKitWebProcess was not installed"
}

patch_webkit_libraries() {
    local libdir="$1"
    local backup="${2:-}"
    need python3

    if [[ -n "$backup" && ! -e "$backup/.complete" ]]; then
        mkdir -p "$backup"
        cp -a "$libdir/." "$backup/"
        : >"$backup/.complete"
    fi

    python3 "$APPIMAGE_DIR/patch_webkit.py" "$libdir"
}

prepare_config() {
    local icaroot="$1"
    local mode="$2"
    local source=""
    local f

    mkdir -p "$icaroot/config"

    if [[ "$mode" == "fresh" ]]; then
        source="$icaroot/../../../etc/icaclient/nls/en/module.ini"
        if [[ ! -f "$source" ]]; then
            source="$(find "$icaroot/../../.." -type f -path '*/etc/icaclient/nls/en/module.ini' -print -quit 2>/dev/null || true)"
        fi
    elif [[ -f "$icaroot/config/module.ini" ]]; then
        source="$icaroot/config/module.ini"
    fi

    if [[ -z "$source" || ! -f "$source" ]]; then
        for source in \
            "$icaroot/nls/en/module.ini" \
            "$icaroot/config/module.ini"; do
            if [[ -f "$source" ]]; then
                break
            fi
            source=""
        done
    fi

    if [[ -n "$source" && "$(abs_path "$source")" != "$(abs_path "$icaroot/config/module.ini")" ]]; then
        cp -f "$source" "$icaroot/config/module.ini"
    fi
    [[ -f "$icaroot/config/module.ini" ]] || die "no module.ini found in $icaroot"
    need python3
    python3 "$APPIMAGE_DIR/patch_module_ini.py" "$icaroot/config/module.ini"

    local nls_en="$icaroot/nls/en"
    local nls_utf8="$icaroot/nls/en.UTF-8"
    if [[ "$mode" == "fresh" ]]; then
        [[ -d "$nls_en" ]] || nls_en="$icaroot/../../../etc/icaclient/nls/en"
        [[ -d "$nls_utf8" ]] || nls_utf8="$icaroot/../../../etc/icaclient/nls/en.UTF-8"
    fi

    for f in wfclient.template appsrv.template; do
        if [[ -f "$nls_en/$f" ]]; then
            cp -f "$nls_en/$f" "$icaroot/config/$f"
        fi
    done
    for f in eula.txt debug.ini; do
        if [[ -f "$nls_utf8/$f" ]]; then
            cp -f "$nls_utf8/$f" "$icaroot/config/$f"
        fi
    done
    if [[ -f "$nls_utf8/eula.txt" ]]; then
        cp -f "$nls_utf8/eula.txt" "$icaroot/eula.txt"
    fi

    [[ -f "$icaroot/eula.txt" && -f "$icaroot/config/eula.txt" ]] ||
        warn "EULA files are incomplete in $icaroot"
}

install_fresh_launcher() {
    local appdir="$1"
    local icaroot="$2"
    local icon=""

    install -m 0755 "$APPIMAGE_DIR/AppRun" "$appdir/AppRun"
    install -m 0755 "$APPIMAGE_DIR/integrate.sh" "$appdir/integrate.sh"
    install -m 0755 "$APPIMAGE_DIR/install-usb.sh" "$appdir/install-usb.sh"
    install -m 0755 "$APPIMAGE_DIR/diagnose.sh" "$appdir/diagnose.sh"
    install -m 0644 "$APPIMAGE_DIR/citrix-workspace.desktop" "$appdir/citrix-workspace.desktop"

    for icon in "$icaroot/icons/receiver.png" "$icaroot/icons/citrix-workspace.png"; do
        if [[ -f "$icon" ]]; then
            break
        fi
        icon=""
    done
    if [[ -z "$icon" ]]; then
        icon="$(find "$icaroot/icons" -maxdepth 1 -name '*.png' -print -quit 2>/dev/null || true)"
    fi
    [[ -n "$icon" ]] || die "no application icon found"
    cp -f "$icon" "$appdir/citrix-workspace.png"
    ln -sfn citrix-workspace.png "$appdir/.DirIcon"
}

install_existing_launcher() {
    local icaroot="$1"

    install -m 0755 "$APPIMAGE_DIR/run-existing.sh" "$icaroot/citrix-workspace"
    install -m 0755 "$APPIMAGE_DIR/install-usb.sh" "$icaroot/install-usb.sh"
    install -m 0755 "$APPIMAGE_DIR/diagnose.sh" "$icaroot/diagnose.sh"
}

prepare_appimagetool() {
    local tool_image="${APPIMAGETOOL_APPIMAGE:-$HOME/.cache/appimagetool-x86_64.AppImage}"
    local tool_dir="${APPIMAGETOOL_DIR:-$HOME/.cache/appimagetool}"

    need curl
    need file
    mkdir -p "$(dirname "$tool_image")"
    if [[ ! -x "$tool_dir/squashfs-root/AppRun" ]]; then
        if [[ ! -f "$tool_image" ]]; then
            curl -fL --retry 3 -o "$tool_image" \
                "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
            chmod +x "$tool_image"
        fi
        rm -rf "$tool_dir"
        mkdir -p "$tool_dir"
        (
            cd "$tool_dir"
            "$tool_image" --appimage-extract >/dev/null
        )
    fi
    [[ -x "$tool_dir/squashfs-root/AppRun" ]] || die "failed to prepare appimagetool"
    printf '%s\n' "$tool_dir/squashfs-root/AppRun"
}

validate_fresh_appdir() {
    local appdir="$1"
    local icaroot="$2"
    local libdir="$appdir/usr/lib/x86_64-linux-gnu"

    grep -a -q 'usr//lib/x86_64-linux-gnu/webkit2gtk-4.0' \
        "$libdir/libwebkit2gtk-4.0.so.37" ||
        die "WebKit helper path patch was not applied"
    for lib in libjpeg.so.8 libsoup-2.4.so.1 libwebkit2gtk-4.0.so.37 libjavascriptcoregtk-4.0.so.18; do
        [[ -e "$libdir/$lib" ]] || die "missing bundled library: $lib"
    done
    grep -q '^GenericUSB=on' "$icaroot/config/module.ini" ||
        die "GenericUSB was not enabled in module.ini"
    [[ -f "$icaroot/eula.txt" ]] ||
        die "missing $icaroot/eula.txt (required for ICAROOT validation)"
    [[ -f "$icaroot/config/eula.txt" ]] || die "missing $icaroot/config/eula.txt"
}
