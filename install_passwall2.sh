#!/bin/sh
#
# install_passwall2.sh
# 在 immortalwrt (apk 包管理器版本) 本机运行,自动判断 x86_64 / R4S,
# 从 ohbaby30/immortalwrt-Build 的 Releases 下载对应架构的 passwall2 apk 包并本地安装。
#
# 仓库: https://github.com/ohbaby30/immortalwrt-Build/releases
#
# 用法(在路由器上,以 root 执行):
#   chmod +x install_passwall2.sh
#   ./install_passwall2.sh
#
# 说明:
#   - 这里的 .apk 是 immortalwrt/openwrt 新版 apk 包管理器的包格式,不是安卓 apk。
#   - 第三方编译的包通常没有官方签名,安装时用 apk add --allow-untrusted。
#   - 脚本用 POSIX sh 编写,兼容 busybox ash。

set -e

REPO="ohbaby30/immortalwrt-Build"
API_BASE="https://api.github.com/repos/${REPO}"
WORK_DIR="/tmp/passwall2_install"

log() {
    echo "[passwall2] $*"
}

# ---------- 判断本机是 x86_64 还是 R4S ----------
detect_platform() {
    ARCH="$(uname -m)"
    MODEL=""
    [ -f /tmp/sysinfo/model ] && MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"

    case "$ARCH" in
        x86_64)
            PLATFORM="x86_64"
            TAG_KEYWORD="x86_64"
            ;;
        aarch64|armv8*)
            PLATFORM="r4s"
            TAG_KEYWORD="r4s"
            case "$MODEL" in
                *R4S*|*r4s*|*NanoPi*|*Rockchip*|*rk3399*) : ;;
                *)
                    log "警告: 检测到 aarch64 架构,但设备型号(${MODEL:-未知})看起来不像 R4S,"
                    log "该仓库目前只发布 x86_64 和 r4s 两种固件对应的包,继续按 r4s 处理,如不对请手动中断 (Ctrl+C)。"
                    ;;
            esac
            ;;
        *)
            echo "无法识别的架构: ${ARCH} (型号: ${MODEL:-未知})"
            echo "本脚本目前只支持 x86_64 与 R4S(aarch64)两种设备。"
            exit 1
            ;;
    esac
    log "检测到本机架构: ${ARCH} , 型号: ${MODEL:-未知} -> 匹配平台: ${PLATFORM}"
}

# ---------- 检查/安装依赖 ----------
ensure_tools() {
    if ! command -v curl >/dev/null 2>&1; then
        log "未检测到 curl,尝试通过 apk 安装..."
        apk update >/dev/null 2>&1 || true
        apk add curl >/dev/null 2>&1 || {
            echo "自动安装 curl 失败,请手动执行: apk update && apk add curl"
            exit 1
        }
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log "未检测到 jq,尝试通过 apk 安装..."
        apk update >/dev/null 2>&1 || true
        apk add jq >/dev/null 2>&1 || {
            echo "自动安装 jq 失败,请手动执行: apk update && apk add jq"
            exit 1
        }
    fi
}

# ---------- 找到对应架构最新的 release ----------
pick_release() {
    log "正在获取 release 列表..."
    RELEASES_JSON="$(curl -fsSL "${API_BASE}/releases")"
    if [ -z "$RELEASES_JSON" ]; then
        echo "获取 release 列表失败,请检查路由器能否访问 github.com / api.github.com。"
        exit 1
    fi

    TAG_NAME="$(echo "$RELEASES_JSON" | jq -r --arg kw "$TAG_KEYWORD" \
        '[.[] | select(.tag_name | contains($kw))] | sort_by(.published_at) | last | .tag_name // empty')"

    if [ -z "$TAG_NAME" ]; then
        echo "未找到匹配 \"${TAG_KEYWORD}\" 的 release,可能仓库命名规则变了,请手动去页面确认:"
        echo "  https://github.com/${REPO}/releases"
        exit 1
    fi
    log "使用 release: ${TAG_NAME}"

    RELEASE_JSON="$(echo "$RELEASES_JSON" | jq -c --arg tag "$TAG_NAME" '.[] | select(.tag_name == $tag)')"
}

# ---------- 从该 release 里筛出 passwall2 相关的 .apk ----------
pick_assets() {
    ASSET_LIST="$(echo "$RELEASE_JSON" | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)"')"

    PW_ASSETS="$(echo "$ASSET_LIST" | grep -i '\.apk$' | grep -Ei 'passwall2|passwall_packages|v2ray-geo|geoview|xray' || true)"

    if [ -z "$PW_ASSETS" ]; then
        echo "在 release ${TAG_NAME} 中没有找到 passwall2 相关的 .apk 文件。"
        echo "该 release 全部资产如下,请手动确认命名规则,再调整脚本里的过滤关键字:"
        echo "$ASSET_LIST"
        exit 1
    fi

    log "匹配到以下待安装文件:"
    echo "$PW_ASSETS" | while IFS="$(printf '\t')" read -r name _url; do
        echo "  - ${name}"
    done
}

# ---------- 用户确认 ----------
confirm() {
    printf '确认下载并安装以上文件到本机吗? [y/N] '
    read -r ans
    case "$ans" in
        y|Y|yes|YES) : ;;
        *) echo "已取消。"; exit 0 ;;
    esac
}

# ---------- 下载并安装 ----------
download_and_install() {
    mkdir -p "$WORK_DIR"
    rm -f "$WORK_DIR"/*.apk 2>/dev/null || true

    echo "$PW_ASSETS" | while IFS="$(printf '\t')" read -r name url; do
        log "下载 ${name} ..."
        curl -fsSL -o "${WORK_DIR}/${name}" "$url"
    done

    log "开始安装 (apk add --allow-untrusted) ..."
    for f in "$WORK_DIR"/*.apk; do
        [ -e "$f" ] || continue
        log "安装 $(basename "$f") ..."
        apk add --allow-untrusted "$f" || log "警告: $(basename "$f") 安装失败,可能需要手动处理依赖或先安装缺失的依赖包。"
    done

    log "安装流程结束。请到 LuCI -> 服务 (Services) 菜单确认 Passwall2 是否已出现,并重启一次服务。"
}

main() {
    detect_platform
    ensure_tools
    pick_release
    pick_assets
    confirm
    download_and_install
}

main "$@"
