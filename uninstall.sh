#!/usr/bin/env bash
# Removes Delegaris installed by the Linux installer.
#
#   sudo /opt/delegaris/uninstall.sh            remove the program; keep settings and data
#   sudo /opt/delegaris/uninstall.sh --purge    also delete settings, data, backups and the user
#
# --yes skips the confirmation that --purge asks for.
#
# Uninstalling does not touch anything in your AWS accounts: the roles you created there
# (DelegarisRole and the service's own role) stay until you delete their CloudFormation
# stacks. Machines being kept on stay on, with their schedule tags off, until put back.
set -euo pipefail

PREFIX=/opt/delegaris
CONF_DIR=/etc/delegaris
DATA_DIR=/var/lib/delegaris
UNIT=/etc/systemd/system/delegaris.service
PURGE=0 YES=0

usage() {
    cat <<'EOF'
Removes Delegaris installed by the Linux installer.

  sudo /opt/delegaris/uninstall.sh            remove the program; keep settings and data
  sudo /opt/delegaris/uninstall.sh --purge    also delete settings, data, backups and the user

--yes skips the confirmation that --purge asks for.

Uninstalling does not touch anything in your AWS accounts: the roles you created there
stay until you delete them. Machines being kept on stay on, with their schedule tags
off, until put back; put them back in Delegaris first if that matters.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --yes|-y) YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
[ "$(id -u)" = 0 ] || { echo "Run this as root, for example with sudo." >&2; exit 1; }

if [ "$PURGE" = 1 ] && [ "$YES" != 1 ]; then
    echo "This deletes Delegaris, its settings ($CONF_DIR) and all its data ($DATA_DIR),"
    echo "including the database, its backups and the record of what was kept on."
    printf 'Type DELETE to go ahead: '
    read -r answer < /dev/tty || answer=""
    [ "$answer" = DELETE ] || { echo "Nothing was removed."; exit 1; }
fi

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now delegaris >/dev/null 2>&1 || true
    rm -f "$UNIT"
    systemctl daemon-reload
    systemctl reset-failed delegaris >/dev/null 2>&1 || true
else
    pkill -u delegaris -f "$PREFIX/" >/dev/null 2>&1 || true
fi

if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -d "$PREFIX/releases/[^/]+/(bin|python/bin)(/.*)?" >/dev/null 2>&1 || true
fi

for link in /usr/bin/delegaris /usr/local/bin/delegaris; do
    if [ "$(readlink "$link" 2>/dev/null)" = "$PREFIX/current/bin/delegaris" ]; then rm -f "$link"; fi
done
rm -rf "${PREFIX:?}"
echo "Removed the program from $PREFIX."

if [ "$PURGE" = 1 ]; then
    rm -rf "${CONF_DIR:?}" "${DATA_DIR:?}"
    if id delegaris >/dev/null 2>&1; then userdel delegaris >/dev/null 2>&1 || true; fi
    if getent group delegaris >/dev/null; then groupdel delegaris >/dev/null 2>&1 || true; fi
    echo "Removed the settings, the data and the delegaris user."
else
    echo "Kept the settings in $CONF_DIR and the data in $DATA_DIR."
    echo "Installing again picks them up. To remove them too: run this again with --purge."
fi
