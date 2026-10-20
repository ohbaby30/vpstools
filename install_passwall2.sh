#!/bin/sh
#
# install_passwall2.sh
# 在 immortalwrt (apk 包管理器版本) 本机运行,支持 x86_64 / R4S,
# 从 ohbaby30/immortalwrt-Build 的固定更新清单下载通用 PassWall2 APK 并本地安装。
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
UPDATE_URL="https://raw.githubusercontent.com/${REPO}/passwall2-update/passwall2-release-api.json"

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
            ;;
        aarch64|armv8*)
            PLATFORM="r4s"
            case "$MODEL" in
                *R4S*|*r4s*|*NanoPi*|*Rockchip*|*rk3399*) : ;;
                *)
                    log "警告: 检测到 aarch64 架构,但设备型号(${MODEL:-未知})看起来不像 R4S,"
                    log "本脚本仅保证该仓库的 x86_64 / R4S 固件兼容性,如不对请手动中断 (Ctrl+C)。"
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
    command -v apk >/dev/null 2>&1 || {
        echo "本脚本仅支持使用 apk 包管理器的 ImmortalWrt。"
        exit 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        echo "缺少 sha256sum,无法校验下载文件。"
        exit 1
    }
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

# ---------- 读取已发布的通用 APK 更新清单 ----------
pick_release() {
    log "正在获取 PassWall2 更新清单..."
    if ! RELEASE_JSON="$(curl -fsSL "$UPDATE_URL")"; then
        echo "获取更新清单失败,请检查路由器能否访问 raw.githubusercontent.com。"
        exit 1
    fi
    if ! printf '%s\n' "$RELEASE_JSON" | jq -e --arg repo "$REPO" '
        (.tag_name | type == "string" and length > 0) and
        (.html_url == ("https://github.com/" + $repo + "/releases/tag/passwall2-" + .tag_name)) and
        (.assets | type == "array")' >/dev/null 2>&1; then
        echo "更新清单格式无效或 Release 来源不匹配,已停止。"
        exit 1
    fi
    TAG_NAME="$(printf '%s\n' "$RELEASE_JSON" | jq -r '.tag_name')"
    log "使用 PassWall2 版本: ${TAG_NAME}"
}

# ---------- 仅选取通用主程序和简体中文包,验证来源与摘要 ----------
pick_assets() {
    if ! PW_ASSETS="$(printf '%s\n' "$RELEASE_JSON" | jq -er --arg repo "$REPO" '
        .tag_name as $tag |
        [.assets[] | select(.name | test("^luci-(app-passwall2|i18n-passwall2-zh-cn)-[A-Za-z0-9._-]+\\.apk$"))] |
        if length == 2 and
           ([.[] | select(.name | startswith("luci-app-passwall2-"))] | length == 1) and
           ([.[] | select(.name | startswith("luci-i18n-passwall2-zh-cn-"))] | length == 1) and
           all(.[];
               .browser_download_url == ("https://github.com/" + $repo + "/releases/download/passwall2-" + $tag + "/" + .name) and
               (.digest | test("^sha256:[0-9a-f]{64}$")))
        then .[] | [.name, .browser_download_url, (.digest | sub("^sha256:"; ""))] | @tsv
        else error("invalid APK assets") end')"; then
        echo "更新清单必须包含唯一的 PassWall2 主程序和中文 APK,且下载地址和 SHA-256 摘要有效,已停止。"
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
    WORK_DIR="$(mktemp -d /tmp/passwall2_install.XXXXXX)"
    trap 'rm -f "$WORK_DIR"/*.apk; rmdir "$WORK_DIR"' EXIT
    trap 'exit 1' HUP INT TERM

    while IFS="$(printf '\t')" read -r name url digest; do
        log "下载 ${name} ..."
        curl -fsSL -o "${WORK_DIR}/${name}" "$url"
        if ! printf '%s  %s\n' "$digest" "${WORK_DIR}/${name}" | sha256sum -c -; then
            echo "${name} SHA-256 校验失败,未执行安装。"
            exit 1
        fi
    done <<EOF
$PW_ASSETS
EOF

    log "开始安装 (apk add --allow-untrusted) ..."
    if ! apk add --allow-untrusted "$WORK_DIR"/*.apk; then
        echo "PassWall2 安装失败,请检查上方 apk 错误与依赖状态。"
        exit 1
    fi

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
