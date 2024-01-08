
XDG_DATA_HOME="${XDG_DATA_HOME:-"$HOME/.local/share"}"
SCRIPT_DIR="$XDG_DATA_HOME/netmaker/nm-quick"
echo "Running in $SCRIPT_DIR"
mkdir -p "${SCRIPT_DIR}"
cd "${SCRIPT_DIR}"
PREFIX="${SCRIPT_DIR}"
export PATH
PATH="@path@:${PATH}"
PATH="${PREFIX}/bin:${PATH}"
NM_SKIP_BUILD=1
NM_SKIP_DEPS=1

# do not clone other sources
NM_SKIP_CLONE=1
[ ! -d "${SCRIPT_DIR}/netmaker-tmp" ] || rm -rf "${SCRIPT_DIR}/netmaker-tmp"
mkdir -p "${PREFIX}/netmaker-tmp"
ln -sf '@src@' "${SCRIPT_DIR}/netmaker-tmp/netmaker"
