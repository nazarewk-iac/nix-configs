XDG_DATA_HOME="${XDG_DATA_HOME:-"$HOME/.local/share"}"
SCRIPT_DIR="$XDG_DATA_HOME/netmaker/nm-quick"
echo "Running in $SCRIPT_DIR"
mkdir -p "${SCRIPT_DIR}"
cd "${SCRIPT_DIR}"
PREFIX="${SCRIPT_DIR}"
export PATH
PATH="@path@:${PATH}"
PATH="${PREFIX}/bin:${PATH}"
mkdir -p "${PREFIX}/bin"
NM_SKIP_BUILD=1
NM_SKIP_DEPS=1

# do not clone other sources
NM_SKIP_CLONE=1
[ ! -d "${SCRIPT_DIR}/netmaker-tmp" ] || rm -rf "${SCRIPT_DIR}/netmaker-tmp"
mkdir -p "${PREFIX}/netmaker-tmp"
ln -sf '@src@' "${SCRIPT_DIR}/netmaker-tmp/netmaker"
# TODO: fix this to work when NM_SKIP_DEPS=1 , https://github.com/gravitl/netmaker/blob/82bbf9277aa360ce6e4f7782445eb70f7336919c/scripts/nm-quick.sh#L430-L439
ARCH=$(uname -m)
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architechure" && exit 1 ;;
esac
