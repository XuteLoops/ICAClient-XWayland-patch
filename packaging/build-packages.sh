#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
NAME="citrix-workspace-app"
VERSION="${VERSION:-26.04.10.1}"
RELEASE="${RELEASE:-1}"
ARCH="x86_64"
APP_ID="io.github.citrixworkspace.CitrixWorkspace"
APPIMAGE="${APPIMAGE:-$ROOT/dist/Citrix_Workspace_${VERSION}-x86_64.AppImage}"
OUT="${OUT:-$ROOT/dist}"
WORK="${WORK:-$HOME/.cache/citrix-package-build}"

formats=("$@")
if [[ ${#formats[@]} -eq 0 ]]; then
    formats=(deb rpm arch flatpak)
fi

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

[[ -f "$APPIMAGE" ]] || die "missing AppImage: $APPIMAGE"
mkdir -p "$OUT" "$WORK"

need tar
need zstd
for f in "${formats[@]}"; do
    case "$f" in
        deb) need dpkg-deb ;;
        rpm) need rpmbuild ;;
        arch) need tar; need zstd ;;
        flatpak) need flatpak-builder; need flatpak ;;
        *) die "unknown format: $f" ;;
    esac
done

say "Extracting AppImage payload"
rm -rf "$WORK/extract"
mkdir -p "$WORK/extract"
(
    cd "$WORK/extract"
    "$APPIMAGE" --appimage-extract >/dev/null
)
APPDIR="$WORK/extract/squashfs-root"
[[ -x "$APPDIR/AppRun" ]] || die "AppRun missing from payload"
[[ -x "$APPDIR/opt/Citrix/ICAClient/selfservice" ]] || die "selfservice missing from payload"

install -m 0755 "$ROOT/appimage/install-usb.sh" "$APPDIR/install-usb.sh"

stage_native() {
    local stage="$WORK/native-root"
    say "Staging native package tree"
    rm -rf "$stage"
    mkdir -p "$stage/opt"
    cp -a "$APPDIR" "$stage/opt/citrix-workspace"
    chmod -R a+rX "$stage/opt/citrix-workspace"
    install -m 0755 "$ROOT/appimage/install-usb.sh" "$stage/opt/citrix-workspace/install-usb.sh"
    install -Dm755 "$HERE/files/native/citrix-workspace.sh" "$stage/usr/bin/citrix-workspace"

    local f
    for f in "$HERE/files/native/"*.desktop; do
        install -Dm644 "$f" "$stage/usr/share/applications/$(basename "$f")"
    done

    install -Dm644 "$stage/opt/citrix-workspace/opt/Citrix/ICAClient/desktop/Citrix-mime_types.xml" \
        "$stage/usr/share/mime/packages/citrix-workspace.xml"
    install -Dm644 "$stage/opt/citrix-workspace/citrix-workspace.png" \
        "$stage/usr/share/icons/hicolor/256x256/apps/citrix-workspace.png"
    install -Dm644 "$HERE/files/native/mimeapps.list" "$stage/etc/xdg/mimeapps.list"
    install -Dm644 "$HERE/files/native/copyright" "$stage/usr/share/doc/$NAME/copyright"
}

build_deb() {
    local stage="$WORK/deb-root"
    say "Building Debian package"
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -a "$WORK/native-root/." "$stage/"
    mkdir -p "$stage/DEBIAN"

    local size
    size="$(du -sk "$stage" | awk '{print $1}')"

    cat > "$stage/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION-$RELEASE
Section: net
Priority: optional
Architecture: amd64
Maintainer: Charles <charles@localhost>
Installed-Size: $size
Depends: bash, coreutils, libc6 (>= 2.35), libice6, libsm6, libx11-6, libxext6, libxmu6, libxpm4, libasound2t64 | libasound2, libstdc++6, libidn12 | libidn11, zlib1g, libcurl4t64 | libcurl4, libsqlite3-0, libspeexdsp1, libva2, libva-x11-2, libva-drm2, net-tools, libgtk-3-0t64 | libgtk-3-0, libgl1, libglx0, libopengl0, libegl1, libharfbuzz-icu0, libwayland-server0, libwayland-client0, libxkbcommon0, libxkbcommon-x11-0, libcups2t64 | libcups2, libfontconfig1, libfreetype6, libcairo2, libpango-1.0-0, libpangocairo-1.0-0, libgdk-pixbuf-2.0-0, libatk1.0-0t64 | libatk1.0-0, libatk-bridge2.0-0t64 | libatk-bridge2.0-0, libepoxy0, libwebp7, libvpx7 | libvpx9, libopus0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, libxml2, shared-mime-info, desktop-file-utils, hicolor-icon-theme
Recommends: libproxy1v5, libpugixml1v5, libgpgme11, libwoff1, gstreamer1.0-libav, gstreamer1.0-plugins-bad, pulseaudio
Suggests: libpcsclite1
Homepage: https://www.citrix.com/
Description: Citrix Workspace app repackaged for Wayland desktops
 Citrix Workspace app $VERSION for Linux, using a portable installation
 under /opt/citrix-workspace. The client runs through XWayland on Wayland
 sessions and includes the compatibility changes needed for that mode.
 .
 This is an unofficial repackaging. Citrix licensing terms apply.
EOF

    install -m 0755 "$HERE/files/deb/postinst" "$stage/DEBIAN/postinst"
    install -m 0755 "$HERE/files/deb/postrm" "$stage/DEBIAN/postrm"
    printf '%s\n' "/etc/xdg/mimeapps.list" > "$stage/DEBIAN/conffiles"

    dpkg-deb --root-owner-group -Zxz -z6 --build "$stage" \
        "$OUT/${NAME}_${VERSION}-${RELEASE}_amd64.deb"
}

build_rpm() {
    local top="$WORK/rpmbuild"
    local spec="$top/SPECS/$NAME.spec"
    say "Building RPM package"
    rm -rf "$top"
    mkdir -p "$top/BUILD" "$top/BUILDROOT" "$top/RPMS" "$top/SOURCES" "$top/SPECS" "$top/SRPMS"

    sed "s|@NATIVE@|$WORK/native-root|g" > "$spec" <<'SPEC'
Name:           citrix-workspace-app
Version:        26.04.10.1
Release:        1
Summary:        Citrix Workspace app repackaged for Wayland desktops
License:        Proprietary
URL:            https://www.citrix.com/
BuildArch:      x86_64
AutoReqProv:    no
Source0:        none
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Requires:       bash
Requires:       coreutils
Requires:       glibc
Requires:       libstdc++
Requires:       gtk3
Requires:       libX11
Requires:       libXext
Requires:       libXmu
Requires:       libXpm
Requires:       alsa-lib
Requires:       pulseaudio-libs
Requires:       libglvnd-glx
Requires:       libglvnd-opengl
Requires:       libglvnd-egl
Requires:       harfbuzz-icu
Requires:       libwayland-server
Requires:       libwayland-client
Requires:       libxkbcommon
Requires:       libxkbcommon-x11
Requires:       libcurl
Requires:       sqlite-libs
Requires:       speexdsp
Requires:       libva
Requires:       libdrm
Requires:       mesa-libgbm
Requires:       libXcomposite
Requires:       libXdamage
Requires:       libXrandr
Requires:       cups-libs
Requires:       fontconfig
Requires:       freetype
Requires:       cairo
Requires:       pango
Requires:       gdk-pixbuf2
Requires:       atk
Requires:       at-spi2-atk
Requires:       libepoxy
Requires:       libwebp
Requires:       libvpx
Requires:       opus
Requires:       gstreamer1
Requires:       gstreamer1-plugins-base
Requires:       zlib-ng-compat
Requires:       libidn2
Requires:       libxml2
Requires:       pugixml
Requires:       gpgme
Requires:       libproxy
Requires:       woff2
Requires:       net-tools
Requires:       shared-mime-info
Requires:       desktop-file-utils
Requires:       hicolor-icon-theme

%description
Citrix Workspace app 26.04.10.1 for Linux, using a portable installation
under /opt/citrix-workspace. The client runs through XWayland on Wayland
sessions and includes the compatibility changes needed for that mode.

This is an unofficial repackaging. Citrix licensing terms apply.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a @NATIVE@/. %{buildroot}/

%post
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime >/dev/null 2>&1 || :
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t /usr/share/icons/hicolor >/dev/null 2>&1 || :
fi
exit 0

%postun
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime >/dev/null 2>&1 || :
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t /usr/share/icons/hicolor >/dev/null 2>&1 || :
fi
exit 0

%files
%defattr(-,root,root,-)
/opt/citrix-workspace
/usr/bin/citrix-workspace
/usr/share/applications/citrix-workspace.desktop
/usr/share/applications/citrix-wfica.desktop
/usr/share/applications/citrix-new-store.desktop
/usr/share/applications/citrix-app.desktop
/usr/share/applications/citrix-receiver.desktop
/usr/share/applications/citrix-webhelper.desktop
/usr/share/applications/citrix-configmgr.desktop
/usr/share/applications/citrix-conncenter.desktop
/usr/share/mime/packages/citrix-workspace.xml
/usr/share/icons/hicolor/256x256/apps/citrix-workspace.png
/usr/share/doc/citrix-workspace-app/copyright
%config(noreplace) /etc/xdg/mimeapps.list
SPEC

    rpmbuild --define "_topdir $top" --define "_binary_payload w13.zstdio" -bb "$spec"
    local rpmfile
    rpmfile="$(find "$top/RPMS" -name '*.rpm' -print -quit)"
    [[ -n "$rpmfile" ]] || die "RPM output not found"
    cp -f "$rpmfile" "$OUT/"
}

build_arch() {
    local stage="$WORK/arch-root"
    say "Building Arch package"
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -a "$WORK/native-root/." "$stage/"

    local size builddate
    size="$(du -sb "$stage" | awk '{print $1}')"
    builddate="$(date +%s)"

    {
        printf '# Generated by build-packages.sh\n'
        printf 'pkgname = %s\n' "$NAME"
        printf 'pkgbase = %s\n' "$NAME"
        printf 'pkgver = %s-%s\n' "$VERSION" "$RELEASE"
        printf 'pkgdesc = Citrix Workspace app repackaged for Wayland desktops\n'
        printf 'url = https://www.citrix.com/\n'
        printf 'builddate = %s\n' "$builddate"
        printf 'packager = Charles <charles@localhost>\n'
        printf 'size = %s\n' "$size"
        printf 'arch = x86_64\n'
        printf 'license = custom\n'
        printf 'backup = etc/xdg/mimeapps.list\n'
        local dep
        for dep in \
            bash coreutils glibc gcc-libs gtk3 libx11 libxext libxmu libxpm alsa-lib libpulse \
            libglvnd harfbuzz-icu wayland libxkbcommon libxkbcommon-x11 curl sqlite speexdsp \
            libva libdrm mesa libxcomposite libxdamage libxrandr cups fontconfig freetype2 \
            cairo pango gdk-pixbuf2 atk at-spi2-atk libepoxy libwebp libvpx opus gstreamer \
            gst-plugins-base zlib libidn2 libxml2 pugixml gpgme libproxy woff2 net-tools \
            shared-mime-info desktop-file-utils hicolor-icon-theme; do
            printf 'depend = %s\n' "$dep"
        done
    } > "$stage/.PKGINFO"

    cat > "$stage/.INSTALL" <<'INSTALL'
post_install() {
    update-mime-database usr/share/mime 2>/dev/null || true
    update-desktop-database usr/share/applications 2>/dev/null || true
    gtk-update-icon-cache -q -t usr/share/icons/hicolor 2>/dev/null || true
}

post_upgrade() {
    post_install
}

post_remove() {
    update-mime-database usr/share/mime 2>/dev/null || true
    update-desktop-database usr/share/applications 2>/dev/null || true
    gtk-update-icon-cache -q -t usr/share/icons/hicolor 2>/dev/null || true
}
INSTALL

    local mtree=()
    if command -v bsdtar >/dev/null 2>&1; then
        (
            cd "$stage"
            bsdtar -czf .MTREE --format=mtree \
                --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
                .PKGINFO .INSTALL opt usr etc
        )
        mtree=(.MTREE)
    fi

    tar -C "$stage" --owner=0 --group=0 --numeric-owner -cf - \
        .PKGINFO .INSTALL "${mtree[@]}" opt usr etc | zstd -q -T0 -12 -f -o \
        "$OUT/${NAME}-${VERSION}-${RELEASE}-x86_64.pkg.tar.zst"
}

build_flatpak() {
    local src="$WORK/flatpak-src"
    local repo="$WORK/flatpak-repo"
    local build="$WORK/flatpak-build"
    say "Building Flatpak bundle"
    rm -rf "$src" "$repo" "$build"
    mkdir -p "$src/files"
    cp -a "$APPDIR" "$src/appdir"
    if [[ -e /usr/lib64/libxml2.so.2 ]]; then
        install -m 0755 /usr/lib64/libxml2.so.2 "$src/appdir/usr/lib/x86_64-linux-gnu/libxml2.so.2"
    fi
    install -m 0755 "$HERE/files/flatpak/citrix-workspace-wrapper.sh" "$src/files/citrix-workspace-wrapper.sh"
    install -m 0644 "$HERE/files/flatpak/io.github.citrixworkspace.CitrixWorkspace.desktop" "$src/files/io.github.citrixworkspace.CitrixWorkspace.desktop"
    install -m 0644 "$HERE/files/native/copyright" "$src/files/copyright"
    cp -f "$HERE/files/flatpak/io.github.citrixworkspace.CitrixWorkspace.yml" "$src/manifest.yml"

    flatpak-builder --force-clean --disable-rofiles-fuse --state-dir="$WORK/flatpak-state" \
        --repo="$repo" "$build" "$src/manifest.yml"
    flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
        "$repo" "$OUT/Citrix_Workspace_${VERSION}-x86_64.flatpak" "$APP_ID"
}

need_native=false
for f in "${formats[@]}"; do
    case "$f" in
        deb|rpm|arch) need_native=true ;;
    esac
done
if [[ "$need_native" == true ]]; then
    stage_native
fi

for f in "${formats[@]}"; do
    case "$f" in
        deb) build_deb ;;
        rpm) build_rpm ;;
        arch) build_arch ;;
        flatpak) build_flatpak ;;
    esac
done

say "Artifacts"
find "$OUT" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' -o -name '*.pkg.tar.zst' -o -name '*.flatpak' \) \
    -printf '%f %s bytes\n' | sort
