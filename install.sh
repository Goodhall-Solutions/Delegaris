#!/usr/bin/env bash
# Installs or upgrades Delegaris on Linux, without Docker.
#
#   curl -fsSL https://github.com/Goodhall-Solutions/delegaris/releases/latest/download/install.sh | sudo bash
#
# Run with --help for the options. Everything is inside main(), which runs on the last line,
# so a download cut off part-way runs nothing at all.
set -euo pipefail

REPO="Goodhall-Solutions/delegaris"
PREFIX=/opt/delegaris
CONF_DIR=/etc/delegaris
ENV_FILE=$CONF_DIR/delegaris.env
DATA_DIR=/var/lib/delegaris
UNIT=/etc/systemd/system/delegaris.service
CLI=/usr/bin/delegaris
KEEP_RELEASES=3

usage() {
    cat <<'EOF'
Installs or upgrades Delegaris on Linux, without Docker.

  curl -fsSL https://github.com/Goodhall-Solutions/delegaris/releases/latest/download/install.sh | sudo bash
  curl -fsSL .../install.sh | sudo bash -s -- [options]
  sudo bash install.sh [options]

Options:
  --version X.Y.Z    install that release instead of the latest
  --file PATH        install from a downloaded package (no internet needed); a PATH.sha256
                     file next to it is checked too
  --public-url URL   the address people will use (default http://<this host>:8080)
  --listen ADDR      where to listen: 0.0.0.0 (default) or 127.0.0.1 behind a proxy
  --port N           port to listen on (default 8080)
  --no-start         install, but do not start the service
  -h, --help         show this

Supported: Ubuntu 22.04 and 24.04, Debian 12, RHEL / Rocky / Alma 9, Amazon Linux 2023,
on x86_64 or arm64. Running it again upgrades; settings and data are kept, and the
database is backed up first. The options --public-url, --listen and --port only apply
the first time, when the settings file is written.
EOF
}

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

fetch() {  # fetch URL FILE
    if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
    else die "needs curl or wget to download"; fi
}

main() {
    local VERSION="" FILE="" PUBLIC_URL="" LISTEN="0.0.0.0" PORT="8080" START=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --version)    VERSION="${2#v}"; shift 2 ;;
            --file)       FILE="$2"; shift 2 ;;
            --public-url) PUBLIC_URL="$2"; shift 2 ;;
            --listen)     LISTEN="$2"; shift 2 ;;
            --port)       PORT="$2"; shift 2 ;;
            --no-start)   START=0; shift ;;
            -h|--help)    usage; exit 0 ;;
            *)            die "unknown option: $1 (try --help)" ;;
        esac
    done

    # -- checks -------------------------------------------------------------------------------------
    [ "$(id -u)" = 0 ] || die "run this as root, for example with sudo"
    [ "$(uname -s)" = Linux ] || die "this installer is for Linux; elsewhere, use the Docker image"
    case "$(uname -m)" in
        x86_64|amd64)  ARCH=x86_64 ;;
        aarch64|arm64) ARCH=aarch64 ;;
        *) die "unsupported processor $(uname -m): Delegaris runs on x86_64 and arm64" ;;
    esac
    if command -v ldd >/dev/null 2>&1; then
        GLIBC=$(ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+$' || true)
        if [ -n "$GLIBC" ] && [ "$(printf '%s\n2.34\n' "$GLIBC" | sort -V | head -n1)" != 2.34 ]; then
            die "this system has glibc $GLIBC; Delegaris needs 2.34 or later (Ubuntu 22.04, Debian 12, RHEL 9, Amazon Linux 2023 or newer)"
        fi
    fi
    case "$PORT" in ''|*[!0-9]*) die "--port must be a number" ;; esac
    if [ -n "$FILE" ]; then
        [ -f "$FILE" ] || die "no such file: $FILE"
        FILE="$(cd "$(dirname "$FILE")" && pwd -P)/$(basename "$FILE")"
    fi
    HAS_SYSTEMD=0
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && HAS_SYSTEMD=1

    # Unpack next to where it is going, not in /tmp: on some systems /tmp is a small
    # in-memory file system, and the package is a few hundred megabytes unpacked.
    install -d -m 0755 "$PREFIX"
    WORK=$(mktemp -d "$PREFIX/.install.XXXXXX")
    trap 'rm -rf "$WORK"' EXIT

    # -- the package --------------------------------------------------------------------------------
    ASSET="delegaris-linux-$ARCH.tar.gz"
    if [ -n "$FILE" ]; then
        cp "$FILE" "$WORK/$ASSET"
        if [ -f "$FILE.sha256" ]; then
            sed "s#  .*#  $ASSET#" "$FILE.sha256" > "$WORK/$ASSET.sha256"
            (cd "$WORK" && sha256sum -c --quiet "$ASSET.sha256") || die "the package does not match its .sha256 file"
        fi
    else
        if [ -n "$VERSION" ]; then BASE="https://github.com/$REPO/releases/download/v$VERSION"
        else BASE="https://github.com/$REPO/releases/latest/download"; fi
        say "Downloading Delegaris ${VERSION:-(latest)} for $ARCH"
        fetch "$BASE/$ASSET" "$WORK/$ASSET" || die "could not download $BASE/$ASSET"
        fetch "$BASE/$ASSET.sha256" "$WORK/$ASSET.sha256.orig" || die "could not download the checksum"
        sed "s#  .*#  $ASSET#" "$WORK/$ASSET.sha256.orig" > "$WORK/$ASSET.sha256"
        (cd "$WORK" && sha256sum -c --quiet "$ASSET.sha256") || die "the download does not match its checksum"
    fi
    tar -xzf "$WORK/$ASSET" -C "$WORK"
    rm -f "$WORK/$ASSET"
    [ -f "$WORK/delegaris/VERSION" ] || die "that is not a Delegaris package"
    NEW_VERSION=$(cat "$WORK/delegaris/VERSION")
    [ "$(cat "$WORK/delegaris/ARCH" 2>/dev/null || echo "$ARCH")" = "$ARCH" ] || die "that package is for $(cat "$WORK/delegaris/ARCH"), this server is $ARCH"

    UPGRADE=0
    OLD_VERSION=""
    if [ -L "$PREFIX/current" ]; then
        UPGRADE=1
        OLD_VERSION=$(cat "$PREFIX/current/VERSION" 2>/dev/null || echo unknown)
        say "Upgrading Delegaris $OLD_VERSION to $NEW_VERSION"
    else
        say "Installing Delegaris $NEW_VERSION"
    fi

    # -- user and folders ---------------------------------------------------------------------------
    if ! getent group delegaris >/dev/null; then groupadd --system delegaris; fi
    if ! id delegaris >/dev/null 2>&1; then
        useradd --system --gid delegaris --home-dir "$DATA_DIR" --no-create-home \
            --shell "$(command -v nologin || echo /sbin/nologin)" --comment "Delegaris service" delegaris
    fi
    install -d -m 0750 -o delegaris -g delegaris "$DATA_DIR"
    install -d -m 0750 -o root -g delegaris "$CONF_DIR"
    install -d -m 0755 "$PREFIX/releases"

    # -- back up before an upgrade ------------------------------------------------------------------
    if [ "$UPGRADE" = 1 ] && [ -f "$DATA_DIR/delegaris.db" ]; then
        STAMP=$(date -u +%Y%m%dT%H%M%SZ)
        BACKUP="$DATA_DIR/backups/before-$NEW_VERSION-$STAMP.db"
        install -d -m 0750 -o delegaris -g delegaris "$DATA_DIR/backups"
        "$WORK/delegaris/python/bin/python3" - "$DATA_DIR/delegaris.db" "$BACKUP" <<'PY'
import sqlite3, sys
src, dst = sqlite3.connect(sys.argv[1]), sqlite3.connect(sys.argv[2])
src.backup(dst)
dst.close(); src.close()
PY
        chown delegaris:delegaris "$BACKUP"; chmod 0640 "$BACKUP"
        say "Backed up the database to $BACKUP"
    fi

    # -- the files ----------------------------------------------------------------------------------
    TARGET="$PREFIX/releases/$NEW_VERSION"
    rm -rf "$TARGET.new"
    mv "$WORK/delegaris" "$TARGET.new"
    rm -rf "$TARGET"
    mv "$TARGET.new" "$TARGET"
    chown -R root:root "$TARGET"
    chmod -R u=rwX,go=rX "$TARGET"
    ln -sfn "releases/$NEW_VERSION" "$PREFIX/current"
    install -m 0755 "$TARGET/uninstall.sh" "$PREFIX/uninstall.sh"
    # In /usr/bin so that "sudo delegaris ..." works everywhere: on RHEL, Rocky, Alma and
    # Amazon Linux, sudo's path leaves out /usr/local/bin. Older releases linked it there.
    ln -sfn "$PREFIX/current/bin/delegaris" "$CLI"
    if [ "$(readlink /usr/local/bin/delegaris 2>/dev/null)" = "$PREFIX/current/bin/delegaris" ]; then
        rm -f /usr/local/bin/delegaris
    fi

    # SELinux (RHEL, Rocky, Alma): let systemd run the bundled programs.
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" != Disabled ]; then
        if command -v semanage >/dev/null 2>&1; then
            semanage fcontext -a -t bin_t "$PREFIX/releases/[^/]+/(bin|python/bin)(/.*)?" 2>/dev/null \
                || semanage fcontext -m -t bin_t "$PREFIX/releases/[^/]+/(bin|python/bin)(/.*)?" 2>/dev/null || true
            restorecon -R "$PREFIX" >/dev/null 2>&1 || true
        else
            chcon -R -t bin_t "$TARGET/bin" "$TARGET/python/bin" 2>/dev/null || true
        fi
    fi

    # Keep the newest few releases, so going back is a symlink away.
    ls -1t "$PREFIX/releases" | { grep -v -x -F "$NEW_VERSION" || true; } | tail -n +"$KEEP_RELEASES" | while read -r old; do
        rm -rf "${PREFIX:?}/releases/$old"
    done

    # -- settings: written once, never overwritten --------------------------------------------------
    FIRST_PASSWORD=""
    if [ ! -f "$ENV_FILE" ]; then
        rand() { "$TARGET/python/bin/python3" -c "import secrets; print(secrets.token_urlsafe($1))"; }
        FIRST_PASSWORD=$(rand 18)
        KEY=$(rand 32)
        if [ -z "$PUBLIC_URL" ]; then
            HOST=$(hostname -f 2>/dev/null || hostname 2>/dev/null || cat /proc/sys/kernel/hostname)
            PUBLIC_URL="http://$HOST:$PORT"
        fi
        sed -e "s#__PUBLIC_URL__#$PUBLIC_URL#" -e "s#__LISTEN_HOST__#$LISTEN#" -e "s#__LISTEN_PORT__#$PORT#" \
            -e "s#__LOCAL_ADMIN_PASSWORD__#$FIRST_PASSWORD#" -e "s#__ENCRYPTION_KEY__#$KEY#" \
            "$TARGET/delegaris.env.example" > "$ENV_FILE"
        chown root:delegaris "$ENV_FILE"
        chmod 0640 "$ENV_FILE"
        say "Wrote the settings to $ENV_FILE"
    elif [ -n "$PUBLIC_URL" ] || [ "$LISTEN" != 0.0.0.0 ] || [ "$PORT" != 8080 ]; then
        warn "$ENV_FILE already exists, so --public-url, --listen and --port were not applied; edit that file instead"
    fi

    # -- the service --------------------------------------------------------------------------------
    PORT_NOW=$(sed -n 's/^LISTEN_PORT=\([0-9]*\).*/\1/p' "$ENV_FILE" | tail -n1)
    if [ "$HAS_SYSTEMD" = 1 ]; then
        install -m 0644 "$TARGET/delegaris.service" "$UNIT"
        systemctl daemon-reload
        systemctl enable delegaris >/dev/null 2>&1
        if [ "$START" = 1 ]; then
            systemctl restart delegaris
            say "Waiting for Delegaris to start"
            STARTED=0
            for _ in $(seq 1 60); do
                if "$PREFIX/current/bin/delegaris" health >/dev/null 2>&1; then STARTED=1; break; fi
                sleep 1
            done
            [ "$STARTED" = 1 ] || warn "it has not answered yet; see: journalctl -u delegaris -n 50"
        fi
    else
        warn "systemd was not found, so Delegaris was not set up as a service. Start it with:"
        echo "    sudo -u delegaris env \$(grep -v '^#' $ENV_FILE | xargs) $PREFIX/current/bin/delegaris serve"
    fi

    # -- done ---------------------------------------------------------------------------------------
    URL=$(sed -n 's/^PUBLIC_URL=//p' "$ENV_FILE" | tail -n1)
    echo
    if [ "$UPGRADE" = 1 ]; then
        say "Delegaris $NEW_VERSION is installed (was $OLD_VERSION)."
    else
        say "Delegaris $NEW_VERSION is installed."
    fi
    echo "    Open:      $URL"
    if [ -n "$FIRST_PASSWORD" ]; then
        echo "    Sign in:   admin / $FIRST_PASSWORD   (the break-glass administrator; it is in $ENV_FILE)"
    fi
    echo "    Settings:  $ENV_FILE   (then: sudo systemctl restart delegaris)"
    echo "    Data:      $DATA_DIR   (keep the ENCRYPTION_KEY from the settings with your backups)"
    echo "    Logs:      journalctl -u delegaris -f"
    echo "    Uninstall: sudo $PREFIX/uninstall.sh"
    echo "    Docs:      https://docs.delegaris.co.uk"
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        echo
        echo "    firewalld is running. To let people reach port ${PORT_NOW:-$PORT}:"
        echo "      sudo firewall-cmd --permanent --add-port=${PORT_NOW:-$PORT}/tcp && sudo firewall-cmd --reload"
    fi
}

main "$@"
