#!/usr/bin/env bash

set -u
set -o pipefail

readonly SCRIPT_NAME="VPS 常用工具箱"
readonly STREAM_TEST_URL="https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh"
readonly XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
readonly SING_BOX_INSTALL_URL="https://sing-box.app/install.sh"
readonly RESET='\033[0m'
readonly BOLD='\033[1m'
readonly META_COLOR='\033[1;33m'
readonly SERVER_COLOR='\033[1;36m'
readonly XRAY_COLOR='\033[1;31m'
readonly SING_BOX_COLOR='\033[1;32m'

info() {
    printf '\033[1;34m[信息]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[提示]\033[0m %s\n' "$*"
}

error() {
    printf '\033[1;31m[错误]\033[0m %s\n' "$*" >&2
}

pause() {
    printf '\n按 Enter 键返回主菜单...'
    read -r _
}

confirm() {
    local answer
    printf '%s [y/N]: ' "$1"
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        error "缺少必要命令：$1"
        return 1
    fi
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        error "此功能需要 root 权限，请使用 root 用户运行工具箱。"
        return 1
    fi
}

confirm_system_change() {
    warn "$1"
    confirm "确认继续执行吗？"
}

run_stream_test() {
    clear
    printf '========== 流媒体测试 ==========\n\n'
    info "脚本来源：$STREAM_TEST_URL"
    warn "此功能会从 GitHub 下载并执行第三方脚本。"

    if ! confirm "确认继续执行吗？"; then
        info "已取消。"
        return 0
    fi

    require_command curl || return 1
    bash <(curl -fsSL "$STREAM_TEST_URL")
}

enable_bbr() {
    clear
    printf '========== Debian 13 开启 BBR ==========\n\n'
    require_root || return 1
    require_command sysctl || return 1
    confirm_system_change "将写入 /etc/sysctl.d/99-bbr.conf 并重新加载内核参数。" || {
        info "已取消。"
        return 0
    }

    printf '%s\n' \
        'net.core.default_qdisc=fq' \
        'net.ipv4.tcp_congestion_control=bbr' \
        > /etc/sysctl.d/99-bbr.conf

    if sysctl --system; then
        info "BBR 配置已写入并加载。建议继续运行菜单 3 验证。"
    else
        error "内核参数加载失败，请检查系统内核是否支持 BBR。"
        return 1
    fi
}

verify_bbr() {
    clear
    printf '========== 验证 BBR 是否开启 ==========\n\n'
    require_command sysctl || return 1
    sysctl net.ipv4.tcp_congestion_control
    sysctl net.core.default_qdisc
    sysctl net.ipv4.tcp_available_congestion_control
}

install_xray() {
    clear
    printf '========== 安装 Xray 稳定版 ==========\n\n'
    require_root || return 1
    require_command curl || return 1
    info "安装脚本来源：$XRAY_INSTALL_URL"
    confirm_system_change "将从 GitHub 下载并以 root 身份执行 Xray 官方安装脚本。" || {
        info "已取消。"
        return 0
    }
    bash -c "$(curl -fsSL "$XRAY_INSTALL_URL")" @ install -u root
}

generate_xray_key() {
    clear
    printf '========== Xray 生成密钥 ==========\n\n'
    require_command xray || return 1
    xray x25519
}

start_xray() {
    clear
    printf '========== 启用并启动 Xray ==========\n\n'
    require_root || return 1
    require_command systemctl || return 1
    confirm_system_change "将设置 Xray 开机自启并立即启动服务。" || {
        info "已取消。"
        return 0
    }
    systemctl enable --now xray
    systemctl --no-pager --full status xray || true
}

install_sing_box() {
    clear
    printf '========== 安装 sing-box 稳定版 ==========\n\n'
    require_root || return 1
    require_command curl || return 1
    info "安装脚本来源：$SING_BOX_INSTALL_URL"
    confirm_system_change "将下载并以 root 身份执行 sing-box 官方安装脚本。" || {
        info "已取消。"
        return 0
    }
    curl -fsSL "$SING_BOX_INSTALL_URL" | sh
}

generate_sing_box_key() {
    clear
    printf '========== sing-box 生成密钥 ==========\n\n'
    require_command sing-box || return 1
    sing-box generate reality-keypair
}

start_sing_box() {
    clear
    printf '========== 启用并启动 sing-box ==========\n\n'
    require_root || return 1
    require_command systemctl || return 1
    confirm_system_change "将设置 sing-box 开机自启并立即启动服务。" || {
        info "已取消。"
        return 0
    }
    systemctl enable --now sing-box
    systemctl --no-pager --full status sing-box || true
}

set_shanghai_timezone() {
    clear
    printf '========== Debian 校准时间 ==========\n\n'
    require_root || return 1
    require_command ln || return 1

    if [[ ! -e /usr/share/zoneinfo/Asia/Shanghai ]]; then
        error "未找到 Asia/Shanghai 时区数据。"
        return 1
    fi

    confirm_system_change "将系统时区设置为 Asia/Shanghai。" || {
        info "已取消。"
        return 0
    }
    ln -sfn /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone Asia/Shanghai
        timedatectl status
    else
        date
    fi
    info "系统时区已设置为 Asia/Shanghai。"
}

show_menu() {
    clear
    printf '%b========== %s ==========%b\n' "$BOLD" "$SCRIPT_NAME" "$RESET"
    printf '%b作者：ohbaby30  |  用途：个人自用%b\n\n' "$META_COLOR" "$RESET"
    printf '%b【Debian / 服务器工具】%b\n' "$SERVER_COLOR" "$RESET"
    printf '%b  1. Debian 校准时间（Asia/Shanghai）%b\n' "$SERVER_COLOR" "$RESET"
    printf '%b  2. 流媒体测试%b\n' "$SERVER_COLOR" "$RESET"
    printf '%b  3. Debian 13 开启 BBR%b\n' "$SERVER_COLOR" "$RESET"
    printf '%b  4. 验证 BBR 是否开启%b\n\n' "$SERVER_COLOR" "$RESET"
    printf '%b【Xray 工具】%b\n' "$XRAY_COLOR" "$RESET"
    printf '%b  5. 安装 Xray 稳定版%b\n' "$XRAY_COLOR" "$RESET"
    printf '%b  6. Xray 生成密钥%b\n' "$XRAY_COLOR" "$RESET"
    printf '%b  7. 开机自启并启动 Xray%b\n\n' "$XRAY_COLOR" "$RESET"
    printf '%b【sing-box 工具】%b\n' "$SING_BOX_COLOR" "$RESET"
    printf '%b  8. 安装 sing-box 稳定版%b\n' "$SING_BOX_COLOR" "$RESET"
    printf '%b  9. sing-box 生成密钥%b\n' "$SING_BOX_COLOR" "$RESET"
    printf '%b 10. 开机自启并启动 sing-box%b\n\n' "$SING_BOX_COLOR" "$RESET"
    printf '  0. 退出\n'
    printf '======================================\n'
}

main() {
    local choice

    while true; do
        show_menu
        printf '请输入序号：'
        read -r choice

        case "$choice" in
            1)
                set_shanghai_timezone
                pause
                ;;
            2)
                run_stream_test
                pause
                ;;
            3)
                enable_bbr
                pause
                ;;
            4)
                verify_bbr
                pause
                ;;
            5)
                install_xray
                pause
                ;;
            6)
                generate_xray_key
                pause
                ;;
            7)
                start_xray
                pause
                ;;
            8)
                install_sing_box
                pause
                ;;
            9)
                generate_sing_box_key
                pause
                ;;
            10)
                start_sing_box
                pause
                ;;
            0)
                info "已退出。"
                exit 0
                ;;
            *)
                warn "无效序号，请重新输入。"
                sleep 1
                ;;
        esac
    done
}

main "$@"
