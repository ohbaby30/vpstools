#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="sing-box VLESS + REALITY 一键部署脚本"
readonly SING_BOX_REPO="SagerNet/sing-box"
readonly CONFIG_DIR="/usr/local/etc/sing-box"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly CACHE_DIR="/var/lib/sing-box"
readonly SERVICE_NAME="sing-box"

# rule-set 使用 remote 类型(MetaCubeX 源),sing-box 首次启动自动下载并缓存
readonly GEOSITE_RS_BASE="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite"
readonly GEOIP_RS_BASE="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip"

readonly RED='\033[1;31m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;34m'
readonly RESET='\033[0m'

SKIP_INSTALL=0
REALITY_PORT=''
CLIENT_UUID=''
DEST_HOST=''
DEST_PORT=''
SERVER_NAME=''
PRIVATE_KEY=''
PUBLIC_KEY=''
SHORT_ID=''
ENABLE_SITE_ROUTING=0
BLOCK_CN_IP=0
CLIENT_ADDRESS=''
CLIENT_NAME=''
VLESS_URL=''
SERVER_PUBLIC_IPV4=''

declare -a ROUTING_KEYS=()
declare -a ROUTING_TAGS=()
declare -a ROUTING_NAMES=()
declare -a ROUTING_PROTOCOLS=()
declare -a ROUTING_ADDRESSES=()
declare -a ROUTING_PORTS=()
declare -a ROUTING_PASSWORDS=()
declare -a SERVER_NAMES=()

info() {
    printf '%b[信息]%b %s\n' "$BLUE" "$RESET" "$*"
}

success() {
    printf '%b[成功]%b %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
    printf '%b[提示]%b %s\n' "$YELLOW" "$RESET" "$*"
}

section_header() {
    printf '\n%b========== %s ==========%b\n\n' "$GREEN" "$1" "$RESET"
}

die() {
    printf '%b[错误]%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

usage() {
    printf '%s\n' \
        "用法：sudo bash $0 [选项]" \
        '' \
        '选项：' \
        '  --skip-install  跳过 sing-box 安装，仅重新生成配置' \
        '  -h, --help      显示帮助'
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --skip-install)
                SKIP_INSTALL=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "未知参数：$1"
                ;;
        esac
        shift
    done
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "请使用 root 用户运行，或执行：sudo bash $0"
}

require_linux_systemd() {
    [[ "$(uname -s)" == "Linux" ]] || die "本脚本只支持 Linux。"
    command -v systemctl >/dev/null 2>&1 || die "未找到 systemctl，本脚本需要 systemd。"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少必要命令：$1"
}

ask_yes_no() {
    local prompt=$1
    local default=${2:-n}
    local answer suffix

    if [[ "$default" == "y" ]]; then
        suffix='[Y/n]'
    else
        suffix='[y/N]'
    fi

    while true; do
        printf '%s %s: ' "$prompt" "$suffix"
        IFS= read -r answer || die "输入已中断。"
        answer=${answer:-$default}
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "请输入 y 或 n。" ;;
        esac
    done
}

is_valid_port() {
    local value=$1
    [[ "$value" =~ ^[0-9]+$ ]] && ((10#$value >= 1 && 10#$value <= 65535))
}

is_valid_uuid() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

is_valid_ipv4() {
    local value=$1 part
    local -a parts
    IFS='.' read -r -a parts <<<"$value"
    ((${#parts[@]} == 4)) || return 1
    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[0-9]{1,3}$ ]] || return 1
        ((10#$part <= 255)) || return 1
    done
}

is_valid_domain() {
    local value=${1%.} label
    local -a labels

    ((${#value} >= 1 && ${#value} <= 253)) || return 1
    [[ "$value" == *.* ]] || return 1
    IFS='.' read -r -a labels <<<"$value"
    for label in "${labels[@]}"; do
        ((${#label} >= 1 && ${#label} <= 63)) || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

is_valid_host() {
    local value=${1#[}
    value=${value%]}
    is_valid_ipv4 "$value" || is_valid_domain "$value" || [[ "$value" == *:* && "$value" =~ ^[0-9A-Fa-f:]+$ ]]
}

prompt_port() {
    local prompt=$1 default=${2:-} value
    while true; do
        if [[ -n "$default" ]]; then
            printf '%s（默认 %s）：' "$prompt" "$default"
        else
            printf '%s：' "$prompt"
        fi
        IFS= read -r value || die "输入已中断。"
        value=${value:-$default}
        if is_valid_port "$value"; then
            REPLY=$((10#$value))
            return 0
        fi
        warn "端口必须是 1 到 65535 之间的整数。"
    done
}

prompt_domain() {
    local prompt=$1 value
    while true; do
        printf '%s：' "$prompt"
        IFS= read -r value || die "输入已中断。"
        value=${value%.}
        if is_valid_domain "$value"; then
            REPLY=${value,,}
            return 0
        fi
        warn "请输入完整域名，例如 www.example.com；不要包含 http://、路径或端口。"
    done
}

prompt_host() {
    local prompt=$1 default=${2:-} value
    while true; do
        if [[ -n "$default" ]]; then
            printf '%s（默认 %s）：' "$prompt" "$default"
        else
            printf '%s：' "$prompt"
        fi
        IFS= read -r value || die "输入已中断。"
        value=${value:-$default}
        if is_valid_host "$value"; then
            REPLY=${value%.}
            return 0
        fi
        warn "请输入有效的域名、IPv4 或 IPv6 地址。"
    done
}

prompt_password() {
    local prompt=$1 first second
    while true; do
        printf '%s：' "$prompt"
        IFS= read -r -s first || die "输入已中断。"
        printf '\n请再次输入以确认：'
        IFS= read -r -s second || die "输入已中断。"
        printf '\n'
        if [[ -z "$first" ]]; then
            warn "密码不能为空。"
        elif [[ "$first" =~ [[:cntrl:]] ]]; then
            warn "密码不能包含控制字符。"
        elif [[ "$first" != "$second" ]]; then
            warn "两次输入不一致，请重新输入。"
        else
            REPLY=$first
            return 0
        fi
    done
}

json_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\t'/\\t}
    value=${value//$'\r'/\\r}
    value=${value//$'\n'/\\n}
    REPLY=$value
}

url_encode() {
    local value=$1 char encoded='' hex index
    local LC_ALL=C
    for ((index = 0; index < ${#value}; index++)); do
        char=${value:index:1}
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+=$char ;;
            *)
                printf -v hex '%02X' "'$char"
                hex=${hex: -2}
                encoded+="%${hex}"
                ;;
        esac
    done
    REPLY=$encoded
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) REPLY='amd64' ;;
        aarch64|arm64) REPLY='arm64' ;;
        armv7l|armhf) REPLY='armv7' ;;
        i386|i686) REPLY='386' ;;
        *) die "不支持的 CPU 架构：$(uname -m)" ;;
    esac
}

# 获取最新正式版版本号(通过 releases/latest 302 重定向,不依赖 api)
# 注意:set -e 下 curl 失败会让脚本静默退出,必须用 || true 兜底
get_latest_stable_version() {
    local redirect_version=''
    redirect_version=$(curl -4fsSL -o /dev/null -w '%{url_effective}' \
        --connect-timeout 5 --max-time 12 \
        -L "https://github.com/${SING_BOX_REPO}/releases/latest" 2>/dev/null \
        | sed -E 's|.*/tag/v||') || true
    if [[ "$redirect_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        REPLY=$redirect_version
        return 0
    fi
    die "无法获取 sing-box 最新正式版版本号(访问 github.com 失败)。请检查网络后重试。"
}

install_singbox() {
    local arch version url tmpdir
    require_command curl
    require_command tar
    require_command install

    detect_arch
    arch=$REPLY

    info "正在获取 sing-box 最新正式版版本号……"
    get_latest_stable_version
    version=$REPLY
    info "安装正式版：v${version}"

    url="https://github.com/${SING_BOX_REPO}/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
    tmpdir=$(mktemp -d /tmp/sing-box-install.XXXXXX)
    trap 'rm -rf "${tmpdir:-}"' RETURN

    info "正在下载 sing-box v${version}（${arch}）……"
    curl -4fL --retry 3 --connect-timeout 10 --max-time 120 "$url" -o "$tmpdir/sing-box.tar.gz" \
        || die "sing-box 下载失败，请检查网络后重试。"
    tar -xzf "$tmpdir/sing-box.tar.gz" -C "$tmpdir"
    install -m 755 "$tmpdir"/sing-box-*/sing-box /usr/local/bin/sing-box
    rm -rf "$tmpdir"
    trap - RETURN

    require_command sing-box
    success "sing-box 安装完成：$(sing-box version | head -n 1)"
}

# 准备 rule-set 缓存目录(remote 规则集由 sing-box 首次启动时自动下载)
# 必须提前创建:1.14 及以后版本,目录不存在会导致启动失败
prepare_cache_dir() {
    mkdir -p "$CACHE_DIR"
    chmod 700 "$CACHE_DIR"
    success "规则集缓存目录已就绪：$CACHE_DIR"
}

install_systemd_service() {
    cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=3s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    success "systemd 服务已创建：${SERVICE_NAME}.service"
}

select_uuid() {
    local choice custom
    while true; do
        printf '%s\n' \
            '客户端 ID 设置方式：' \
            '  1. 自动生成 UUID（推荐）' \
            '  2. 自定义 UUID'
        printf '请选择 [1-2]：'
        IFS= read -r choice || die "输入已中断。"
        case "$choice" in
            1|'')
                CLIENT_UUID=$(sing-box generate uuid | tr -d '[:space:]')
                is_valid_uuid "$CLIENT_UUID" || die "sing-box 自动生成的 UUID 格式异常。"
                success "已生成 UUID：$CLIENT_UUID"
                return 0
                ;;
            2)
                while true; do
                    printf '请输入 UUID（标准格式，如 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）：'
                    IFS= read -r custom || die "输入已中断。"
                    if is_valid_uuid "$custom"; then
                        CLIENT_UUID=${custom,,}
                        success "已使用自定义 UUID：$CLIENT_UUID"
                        return 0
                    fi
                    warn "请输入有效的标准 UUID。"
                done
                ;;
            *) warn "请选择 1 或 2。" ;;
        esac
    done
}

generate_reality_keys() {
    local output
    output=$(sing-box generate reality-keypair 2>&1) || {
        printf '%s\n' "$output" >&2
        die "执行 sing-box generate reality-keypair 失败。"
    }

    PRIVATE_KEY=$(awk -F':[[:space:]]*' 'tolower($1) ~ /private/ {print $2; exit}' <<<"$output")
    PUBLIC_KEY=$(awk -F':[[:space:]]*' 'tolower($1) ~ /public/ {print $2; exit}' <<<"$output")

    [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || {
        printf '%s\n' "$output" >&2
        die "无法识别 sing-box reality-keypair 的输出格式。"
    }
    success "Reality 密钥已生成，私钥将自动写入服务端配置。"
    info "客户端需要的公钥/Password：$PUBLIC_KEY"
}

generate_short_id() {
    SHORT_ID=$(sing-box generate rand 16 --hex 2>/dev/null | tr -d '[:space:]' || true)
    if [[ ! "$SHORT_ID" =~ ^[0-9a-f]{16}$ ]]; then
        SHORT_ID=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c 1-16)
    fi
    [[ "$SHORT_ID" =~ ^[0-9a-f]{16}$ ]] || die "shortId 生成失败。"
    success "已生成 shortId：$SHORT_ID"
}

select_server_name() {
    local input item existing duplicate
    local -a candidates=()

    SERVER_NAMES=()
    if is_valid_domain "$DEST_HOST" && ! is_valid_ipv4 "$DEST_HOST"; then
        SERVER_NAME=$DEST_HOST
        SERVER_NAMES=("$DEST_HOST")
        info "已自动加入目标网站域名：$DEST_HOST"
        warn "追加的域名必须被目标网站的 HTTPS 证书覆盖。"

        if ! ask_yes_no '是否还要增加其他可用域名？' n; then
            return 0
        fi

        while true; do
            printf '请输入要增加的域名（多个域名用英文逗号分隔）：'
            IFS= read -r input || die "输入已中断。"
            IFS=',' read -r -a candidates <<<"$input"
            ((${#candidates[@]} > 0)) || {
                warn "请至少输入一个域名。"
                continue
            }

            duplicate=0
            for item in "${candidates[@]}"; do
                item=${item#"${item%%[![:space:]]*}"}
                item=${item%"${item##*[![:space:]]}"}
                item=${item%.}
                if ! is_valid_domain "$item" || is_valid_ipv4 "$item"; then
                    warn "域名格式不正确：${item:-空值}"
                    duplicate=1
                    break
                fi
            done
            ((duplicate == 0)) || continue

            for item in "${candidates[@]}"; do
                item=${item#"${item%%[![:space:]]*}"}
                item=${item%"${item##*[![:space:]]}"}
                item=${item%.}
                item=${item,,}
                duplicate=0
                for existing in "${SERVER_NAMES[@]}"; do
                    if [[ "$existing" == "$item" ]]; then
                        duplicate=1
                        break
                    fi
                done
                ((duplicate == 1)) || SERVER_NAMES+=("$item")
            done
            return 0
        done
    fi

    info "前面填写的是 IP，请填写 Caddy/Nginx 网站证书对应的域名。"
    prompt_domain '请输入 Reality 目标网站域名'
    SERVER_NAME=$REPLY
    SERVER_NAMES=("$SERVER_NAME")
}

build_server_names_json() {
    local item escaped output='' separator=''
    for item in "${SERVER_NAMES[@]}"; do
        json_escape "$item"
        escaped=$REPLY
        output+="${separator}\"${escaped}\""
        separator=', '
    done
    REPLY=$output
}

check_reality_dest() {
    local dest="${DEST_HOST}:${DEST_PORT}"
    local check_ok=1
    local resolved_ipv4=''

    if command -v getent >/dev/null 2>&1; then
        resolved_ipv4=$(getent ahostsv4 "$DEST_HOST" 2>/dev/null | awk '{print $1}' | sort -u || true)
    fi
    if ((DEST_PORT == REALITY_PORT)) &&
       { [[ "$DEST_HOST" == '127.0.0.1' || "$DEST_HOST" == '::1' ]] ||
         { [[ -n "$SERVER_PUBLIC_IPV4" ]] && grep -Fqx "$SERVER_PUBLIC_IPV4" <<<"$resolved_ipv4"; }; }; then
        warn "Reality 目标网站 $dest 指向本机，端口又与 Reality 监听端口相同。"
        warn "如果目标网站是同机 Caddy/Nginx，请填写它实际监听的另一个 HTTPS 端口。"
        return 1
    fi

    info "正在测试 Reality 目标网站：${dest}（网站域名：${SERVER_NAME}）"
    if [[ "$SERVER_NAME" == "$DEST_HOST" ]]; then
        curl -4fsSI --noproxy '*' --connect-timeout 8 --max-time 15 \
            "https://${DEST_HOST}:${DEST_PORT}/" >/dev/null 2>&1 && check_ok=0
    elif [[ "$DEST_HOST" != *:* ]]; then
        curl -4fsSI --noproxy '*' --connect-timeout 8 --max-time 15 \
            --connect-to "${SERVER_NAME}:${DEST_PORT}:${DEST_HOST}:${DEST_PORT}" \
            "https://${SERVER_NAME}:${DEST_PORT}/" >/dev/null 2>&1 && check_ok=0
    fi
    if ((check_ok == 0)); then
        success "Reality 目标网站 TLS 测试通过。"
    else
        warn "未能确认目标网站的 TLS 响应或证书，可能是地址、端口、网站域名、证书或网络问题。"
        ask_yes_no "仍然使用目标网站 $dest 和网站域名 $SERVER_NAME 吗？" n || return 1
    fi
}

select_routing_protocol() {
    local choice
    while true; do
        printf '%s\n' \
            '分流服务器协议：' \
            '  1. Trojan + TLS' \
            '  2. Shadowsocks（sing-box 内置，aes-256-gcm）'
        printf '请选择 [1-2]：'
        IFS= read -r choice || die "输入已中断。"
        case "$choice" in
            1) REPLY='trojan'; return 0 ;;
            2) REPLY='shadowsocks'; return 0 ;;
            *) warn "请选择 1 或 2。" ;;
        esac
    done
}

add_routing_group() {
    local key=$1 tag=$2 name=$3 index
    index=${#ROUTING_KEYS[@]}
    ROUTING_KEYS[$index]=$key
    ROUTING_TAGS[$index]=$tag
    ROUTING_NAMES[$index]=$name

    printf '\n---- %s 分流服务器 ----\n' "$name"
    select_routing_protocol
    ROUTING_PROTOCOLS[$index]=$REPLY
    prompt_domain "请输入 $name 分流服务器域名"
    ROUTING_ADDRESSES[$index]=$REPLY
    prompt_port "请输入 $name 分流服务器端口" 443
    ROUTING_PORTS[$index]=$REPLY
    prompt_password "请输入 $name 分流服务器密码"
    ROUTING_PASSWORDS[$index]=$REPLY
}

collect_configuration() {
    local detected_ip='' is_hong_kong=0 value

    detected_ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)
    if is_valid_ipv4 "$detected_ip"; then
        SERVER_PUBLIC_IPV4=$detected_ip
    else
        detected_ip=''
        SERVER_PUBLIC_IPV4=''
    fi

    section_header 'Reality 入站配置'
    prompt_port '请输入 Reality 监听端口' 443
    REALITY_PORT=$REPLY
    select_uuid
    generate_reality_keys
    generate_short_id

    section_header 'Reality 目标网站设置'
    while true; do
        if ask_yes_no '是否使用本机 Caddy/Nginx 网站作为 Reality 目标网站？' n; then
            DEST_HOST='127.0.0.1'
            info "Reality 目标网站地址已设置为：127.0.0.1"
            prompt_port '请输入本机 Caddy/Nginx 的 HTTPS 监听端口' 443
            DEST_PORT=$REPLY
            warn "该域名必须与 Caddy/Nginx 的 HTTPS 证书匹配。"
            prompt_domain '请输入本机 Caddy/Nginx 网站使用的 HTTPS 域名'
            SERVER_NAME=$REPLY
            SERVER_NAMES=("$SERVER_NAME")
        else
            prompt_host '请输入 Reality 目标网站的地址（域名或 IP）'
            DEST_HOST=$REPLY
            prompt_port '请输入 Reality 目标网站的端口' 443
            DEST_PORT=$REPLY
            select_server_name
        fi
        check_reality_dest && break
    done

    section_header '网站分流配置'
    ENABLE_SITE_ROUTING=0
    ROUTING_KEYS=()
    ROUTING_TAGS=()
    ROUTING_NAMES=()
    ROUTING_PROTOCOLS=()
    ROUTING_ADDRESSES=()
    ROUTING_PORTS=()
    ROUTING_PASSWORDS=()

    if ask_yes_no '这台 VPS 是否为香港服务器？' n; then
        is_hong_kong=1
        ENABLE_SITE_ROUTING=1
        info "香港服务器将强制加入以下分流：OpenAI、X、Yahoo、Google DeepMind、Google Gemini、TikTok。"
        add_routing_group 'hongkong' 'hkProxy' '香港服务器专用（OpenAI、X、Yahoo、Google DeepMind、Google Gemini、TikTok）'
    fi

    if ask_yes_no '是否需要流媒体分流（Netflix、Disney）？' n; then
        ENABLE_SITE_ROUTING=1
        add_routing_group 'media' 'mediaProxy' '流媒体（Netflix、Disney）'
    fi

    if ask_yes_no '是否需要支付服务分流（PayPal）？' n; then
        ENABLE_SITE_ROUTING=1
        add_routing_group 'paypal' 'ppProxy' '支付服务（PayPal）'
    fi

    if ((is_hong_kong == 0)) && ask_yes_no '是否需要 AI 分流（OpenAI、X、Google DeepMind、Google Gemini）？' n; then
        ENABLE_SITE_ROUTING=1
        add_routing_group 'ai' 'aiProxy' 'AI（OpenAI、X、Google DeepMind、Google Gemini）'
    fi

    if ((ENABLE_SITE_ROUTING == 0)); then
        info "未启用额外分流。广告和 BT 屏蔽规则仍会保留。"
    fi

    section_header '回国流量设置'
    warn "屏蔽回国流量会阻止目标 IP 属于中国大陆的连接，可能带来意想不到的问题，请慎用。"
    if ask_yes_no '是否需要屏蔽回国流量（geoip:cn IP 检测）？' n; then
        BLOCK_CN_IP=1
        info "将加入 geoip:cn 屏蔽规则。"
    else
        BLOCK_CN_IP=0
        info "不会生成 geoip:cn 屏蔽规则。"
    fi

    section_header '客户端链接生成'
    info "以下内容仅用于生成客户端导入链接，不会写入 sing-box 服务端配置。"
    prompt_host '请输入客户端连接地址（VPS 公网 IP 或解析到该 VPS 的域名）' "$detected_ip"
    CLIENT_ADDRESS=$REPLY

    printf '请输入客户端节点名称（仅用于客户端显示，默认 sing-box-Reality）：'
    IFS= read -r value || die "输入已中断。"
    CLIENT_NAME=${value:-sing-box-Reality}
}

write_routing_rules() {
    local index key tag
    for index in "${!ROUTING_KEYS[@]}"; do
        key=${ROUTING_KEYS[$index]}
        tag=${ROUTING_TAGS[$index]}
        case "$key" in
            hongkong)
                printf ',\n%s' "        {
          \"rule_set\": [\"openai\", \"x\", \"yahoo\", \"google-deepmind\", \"google-gemini\", \"tiktok\"],
          \"action\": \"route\",
          \"outbound\": \"$tag\"
        }"
                ;;
            media)
                printf ',\n%s' "        {
          \"rule_set\": [\"netflix\", \"disney\"],
          \"action\": \"route\",
          \"outbound\": \"$tag\"
        }"
                ;;
            paypal)
                printf ',\n%s' "        {
          \"rule_set\": [\"paypal\"],
          \"action\": \"route\",
          \"outbound\": \"$tag\"
        }"
                ;;
            ai)
                printf ',\n%s' "        {
          \"rule_set\": [\"openai\", \"x\", \"google-deepmind\", \"google-gemini\"],
          \"action\": \"route\",
          \"outbound\": \"$tag\"
        }"
                ;;
        esac
    done
}

write_cn_ip_block_rule() {
    if ((BLOCK_CN_IP == 1)); then
        printf '%s' ',
      {
        "rule_set": ["geoip-cn"],
        "action": "reject",
        "method": "drop"
      }'
    fi
}

# 是否输出 http_clients(1.14+ 特性;1.13 正式版不识别该字段,必须设为 0)
USE_HTTP_CLIENTS=0

write_rule_set_declarations() {
    local index key name output='' separator=''
    local base="$GEOSITE_RS_BASE" ip_base="$GEOIP_RS_BASE"

    # 始终需要:广告屏蔽
    output+="${separator}    {
      \"type\": \"remote\",
      \"tag\": \"category-ads-all\",
      \"format\": \"binary\",
      \"url\": \"${base}/category-ads-all.srs\",
      \"update_interval\": \"1d\"
    }"
    separator=','
    if ((BLOCK_CN_IP == 1)); then
        output+="${separator}    {
      \"type\": \"remote\",
      \"tag\": \"geoip-cn\",
      \"format\": \"binary\",
      \"url\": \"${ip_base}/cn.srs\",
      \"update_interval\": \"1d\"
    }"
        separator=','
    fi
    for index in "${!ROUTING_KEYS[@]}"; do
        key=${ROUTING_KEYS[$index]}
        case "$key" in
            hongkong)
                for name in openai x yahoo google-deepmind google-gemini tiktok; do
                    output+="${separator}    {
      \"type\": \"remote\",
      \"tag\": \"${name}\",
      \"format\": \"binary\",
      \"url\": \"${base}/${name}.srs\",
      \"update_interval\": \"1d\"
    }"
                    separator=','
                done
                ;;
            media)
                for name in netflix disney; do
                    output+="${separator}    {
      \"type\": \"remote\",
      \"tag\": \"${name}\",
      \"format\": \"binary\",
      \"url\": \"${base}/${name}.srs\",
      \"update_interval\": \"1d\"
    }"
                    separator=','
                done
                ;;
            paypal)
                output+="${separator}    {
      \"type\": \"remote\",
      \"tag\": \"paypal\",
      \"format\": \"binary\",
      \"url\": \"${base}/paypal.srs\",
      \"update_interval\": \"1d\"
    }"
                separator=','
                ;;
            ai)
                for name in openai x google-deepmind google-gemini; do
                    output+="${separator}    {
      \"type\": \"remote\",
      \"tag\": \"${name}\",
      \"format\": \"binary\",
      \"url\": \"${base}/${name}.srs\",
      \"update_interval\": \"1d\"
    }"
                    separator=','
                done
                ;;
        esac
    done
    REPLY=$output
}

write_proxy_outbound() {
    local index=$1 tag address port password
    tag=${ROUTING_TAGS[$index]}
    address=${ROUTING_ADDRESSES[$index]}
    port=${ROUTING_PORTS[$index]}
    password=${ROUTING_PASSWORDS[$index]}
    json_escape "$tag"; tag=$REPLY
    json_escape "$address"; address=$REPLY
    json_escape "$password"; password=$REPLY

    if [[ "${ROUTING_PROTOCOLS[$index]}" == 'trojan' ]]; then
        printf ',\n%s' "    {
      \"type\": \"trojan\",
      \"tag\": \"$tag\",
      \"server\": \"$address\",
      \"server_port\": $port,
      \"password\": \"$password\",
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"$address\"
      }
    }"
    else
        printf ',\n%s' "    {
      \"type\": \"shadowsocks\",
      \"tag\": \"$tag\",
      \"server\": \"$address\",
      \"server_port\": $port,
      \"method\": \"aes-256-gcm\",
      \"password\": \"$password\",
      \"network\": \"tcp\"
    }"
    fi
}

write_config() {
    local output_file=$1 index
    local uuid dest_host server_name private_key short_id rule_set_decls use_http_clients
    json_escape "$CLIENT_UUID"; uuid=$REPLY
    json_escape "$DEST_HOST"; dest_host=$REPLY
    json_escape "$SERVER_NAME"; server_name=$REPLY
    json_escape "$PRIVATE_KEY"; private_key=$REPLY
    json_escape "$SHORT_ID"; short_id=$REPLY
    write_rule_set_declarations; rule_set_decls=$REPLY
    use_http_clients=$USE_HTTP_CLIENTS
    if ((use_http_clients == 1)); then
        info "已启用 http_clients（规则集下载走直连）。"
    fi

    {
        printf '%s' '{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": '"$REALITY_PORT"',
      "users": [
        {
          "name": "sing-box",
          "uuid": "'"$uuid"'",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "'"$server_name"'",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "'"$dest_host"'",
            "server_port": '"$DEST_PORT"'
          },
          "private_key": "'"$private_key"'",
          "short_id": ["", "'"$short_id"'"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }'
        if ((ENABLE_SITE_ROUTING == 1)); then
            for index in "${!ROUTING_TAGS[@]}"; do
                write_proxy_outbound "$index"
            done
        fi
        printf '%s' '
  ]'
        if ((use_http_clients == 1)); then
            printf '%s' ',
  "http_clients": [
    {
      "tag": "rule-set-direct",
      "detour": "direct"
    }
  ]'
        fi
        printf '%s' ',
  "route": {'
        if ((use_http_clients == 1)); then
            printf '%s' '
    "default_http_client": "rule-set-direct",'
        fi
        printf '%s' '
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": ["quic"],
        "action": "reject",
        "method": "drop"
      },
      {
        "rule_set": ["category-ads-all"],
        "action": "reject",
        "method": "drop"
      },
      {
        "protocol": ["bittorrent"],
        "action": "reject",
        "method": "drop"
      }'
        write_cn_ip_block_rule
        write_routing_rules
        printf '%s' '
    ],
    "rule_set": ['
        printf '%s' "$rule_set_decls"
        printf '%s' '
    ],
    "final": "direct"
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/lib/sing-box/cache.db"
    }
  }
}
'
    } >"$output_file"
    chmod 600 "$output_file"
}

install_configuration() {
    local temp_dir temp_config backup_file='' timestamp test_output
    mkdir -p "$CONFIG_DIR"
    temp_dir=$(mktemp -d "${CONFIG_DIR}/.config-build.XXXXXX")
    temp_config="${temp_dir}/config.json"
    write_config "$temp_config"

    info "正在检查 sing-box 配置……"
    if ! test_output=$(sing-box check -c "$temp_config" 2>&1); then
        printf '%s\n' "$test_output" >&2
        rm -f "$temp_config"
        rmdir "$temp_dir" 2>/dev/null || true
        die "生成的配置未通过 sing-box 检查，原配置没有被修改。"
    fi
    success "sing-box 配置检查通过。"

    if [[ -f "$CONFIG_FILE" ]]; then
        timestamp=$(date +%Y%m%d-%H%M%S)
        backup_file="${CONFIG_FILE}.bak.${timestamp}"
        cp -a "$CONFIG_FILE" "$backup_file"
        info "旧配置已备份到：$backup_file"
    fi
    mv -f "$temp_config" "$CONFIG_FILE"
    rmdir "$temp_dir" 2>/dev/null || true
    chmod 600 "$CONFIG_FILE"

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null
    if systemctl restart "$SERVICE_NAME" && systemctl is-active --quiet "$SERVICE_NAME"; then
        success "sing-box 已设置为开机自启并成功启动。"
        systemctl --no-pager --full status "$SERVICE_NAME" || true
        return 0
    fi

    warn "sing-box 启动失败，最近的服务日志如下："
    journalctl -u "$SERVICE_NAME" --no-pager -n 50 || true
    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        warn "正在恢复启动前的配置：$backup_file"
        cp -a "$backup_file" "$CONFIG_FILE"
        systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    return 1
}

build_vless_url() {
    local uri_host encoded_name
    uri_host=$CLIENT_ADDRESS
    if [[ "$uri_host" == *:* && "$uri_host" != \[*\] ]]; then
        uri_host="[$uri_host]"
    fi
    url_encode "$CLIENT_NAME"
    encoded_name=$REPLY
    VLESS_URL="vless://${CLIENT_UUID}@${uri_host}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none&spx=%2F#${encoded_name}"
}

print_result() {
    build_vless_url
    section_header '部署完成'
    printf '配置文件：%s\n' "$CONFIG_FILE"
    printf 'Reality 端口：%s\n' "$REALITY_PORT"
    printf '客户端 ID：%s\n' "$CLIENT_UUID"
    printf 'Reality 目标网站：%s:%s\n' "$DEST_HOST" "$DEST_PORT"
    printf 'Reality 目标网站域名：%s\n' "$(IFS='、'; printf '%s' "${SERVER_NAMES[*]}")"
    printf 'Reality 公钥/Password：%s\n' "$PUBLIC_KEY"
    printf 'shortId：%s\n\n' "$SHORT_ID"
    printf '%bPassWall2 / 客户端导入链接：%b\n%s\n' "$GREEN" "$RESET" "$VLESS_URL"
    printf '\n请妥善保管该链接，链接包含完整的客户端连接凭据。\n'
}

main() {
    parse_args "$@"
    require_root
    require_linux_systemd
    printf '%b========== %s ==========%b\n' "$GREEN" "$SCRIPT_NAME" "$RESET"
    warn "脚本会安装 sing-box、生成 Reality 配置并重启 sing-box 服务。"
    ask_yes_no '确认继续吗？' y || exit 0

    if ((SKIP_INSTALL == 0)); then
        section_header '安装 sing-box'
        install_singbox
        install_systemd_service
    else
        section_header '检查 sing-box'
        require_command sing-box
        info "已跳过安装，使用现有版本：$(sing-box version | head -n 1)"
    fi
    require_command curl

    while true; do
        collect_configuration
        section_header '准备规则集缓存'
        prepare_cache_dir
        section_header '应用配置'
        if install_configuration; then
            print_result
            return 0
        fi
        ask_yes_no '是否重新填写配置并再试一次？' y || die "部署未完成。"
    done
}

main "$@"
