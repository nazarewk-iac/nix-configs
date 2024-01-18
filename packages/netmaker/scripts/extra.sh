PATH="@path@:${PATH}"

# don't build docker image
NM_SKIP_BUILD=1
# don't install dependencies
NM_SKIP_DEPS=1
# don't configure client at all
NM_SKIP_CLIENT=1

# symlink sources
NM_SKIP_CLONE=1
[ ! -d "${DATA_DIR}/netmaker-tmp" ] || rm -rf "${DATA_DIR}/netmaker-tmp"
mkdir -p "${DATA_DIR}/netmaker-tmp"
ln -sf '@src@' "${DATA_DIR}/netmaker-tmp/netmaker"
