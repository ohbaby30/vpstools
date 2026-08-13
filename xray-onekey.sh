#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="Xray VLESS + REALITY 一键部署脚本"
readonly XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
readonly XRAY_CONFIG_DIR="/usr/local/etc/xray"
readonly XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"

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

info() {
    printf '%b[信息]%b %s\n' "$BLUE" "$RESET" "$*"
}

success() {
    printf '%b[成功]%b %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
    printf '%b[提示]%b %s\n' "$YELLOW" "$RESET" "$*"
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
        '  --skip-install  跳过 Xray 安装，仅重新生成配置' \
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

install_xray() {
    local installer
    require_command curl
    installer=$(mktemp /tmp/xray-install.XXXXXX.sh)
    trap 'rm -f "${installer:-}"' RETURN

    info "正在下载 Xray 官方稳定版安装脚本……"
    curl -fL --retry 3 --connect-timeout 15 "$XRAY_INSTALL_URL" -o "$installer"
    chmod 700 "$installer"
    info "正在安装 Xray，并将 systemd 服务用户设置为 root……"
    bash "$installer" install -u root
    rm -f "$installer"
    trap - RETURN

    require_command xray
    success "Xray 安装完成：$(xray version | head -n 1)"
}

select_uuid() {
    local choice custom
    while true; do
        printf '%s\n' 'UUID 生成方式：' '  1. 自动生成（推荐）' '  2. 手动填写'
        printf '请选择 [1-2]：'
        IFS= read -r choice || die "输入已中断。"
        case "$choice" in
            1|'')
                CLIENT_UUID=$(xray uuid | tr -d '[:space:]')
                is_valid_uuid "$CLIENT_UUID" || die "Xray 自动生成的 UUID 格式异常。"
                success "已生成 UUID：$CLIENT_UUID"
                return 0
                ;;
            2)
                while true; do
                    printf '请输入 UUID：'
                    IFS= read -r custom || die "输入已中断。"
                    if is_valid_uuid "$custom"; then
                        CLIENT_UUID=${custom,,}
                        return 0
                    fi
                    warn "UUID 格式不正确。示例：123e4567-e89b-42d3-a456-426614174000"
                done
                ;;
            *) warn "请选择 1 或 2。" ;;
        esac
    done
}

generate_reality_keys() {
    local output
    output=$(xray x25519 2>&1) || {
        printf '%s\n' "$output" >&2
        die "执行 xray x25519 失败。"
    }

    PRIVATE_KEY=$(awk -F':[[:space:]]*' 'tolower($1) ~ /^private[ _-]*key$/ {print $2; exit}' <<<"$output")
    PUBLIC_KEY=$(awk -F':[[:space:]]*' 'tolower($1) ~ /public/ || tolower($1) ~ /^password/ {print $2; exit}' <<<"$output")

    [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || {
        printf '%s\n' "$output" >&2
        die "无法识别 xray x25519 的输出格式。"
    }
    success "Reality 密钥已生成，私钥将自动写入服务端配置。"
    info "客户端需要的公钥/Password：$PUBLIC_KEY"
}

generate_short_id() {
    SHORT_ID=$(xray uuid | tr -d '-' | cut -c 1-16)
    SHORT_ID=${SHORT_ID,,}
    [[ "$SHORT_ID" =~ ^[0-9a-f]{16}$ ]] || die "shortId 生成失败。"
    success "已生成 shortId：$SHORT_ID"
}

select_server_name() {
    local choice
    if is_valid_domain "$DEST_HOST" && ! is_valid_ipv4 "$DEST_HOST"; then
        while true; do
            printf '%s\n' \
                'Reality 目标网站域名设置方式：' \
                "  1. 使用刚才填写的 Reality 目标网站域名（${DEST_HOST}，默认）" \
                '  2. 自定义域名'
            printf '请选择 [1-2]（默认 1）：'
            IFS= read -r choice || die "输入已中断。"
            case "${choice:-1}" in
                1)
                    SERVER_NAME=$DEST_HOST
                    return 0
                    ;;
                2)
                    prompt_domain '请输入自定义的 Reality 目标网站域名'
                    SERVER_NAME=$REPLY
                    return 0
                    ;;
                *) warn "请选择 1 或 2。" ;;
            esac
        done
    fi

    info "前面填写的是 IP，请填写 Caddy/Nginx 网站证书对应的域名。"
    prompt_domain '请输入 Reality 目标网站域名'
    SERVER_NAME=$REPLY
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
        if command -v timeout >/dev/null 2>&1; then
            timeout 20 xray tls ping "$dest" >/dev/null 2>&1 && check_ok=0
        else
            xray tls ping "$dest" >/dev/null 2>&1 && check_ok=0
        fi
    elif [[ "$DEST_HOST" != *:* ]]; then
        curl -sSI --noproxy '*' --connect-timeout 8 --max-time 15 \
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
            '  2. Shadowsocks（ss-rust，aes-256-gcm）'
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

    printf '\n%b========== Reality 入站配置 ==========%b\n\n' "$GREEN" "$RESET"
    prompt_port '请输入 Reality 监听端口' 443
    REALITY_PORT=$REPLY
    select_uuid

    while true; do
        prompt_host '请输入 Reality 目标网站（如目标网站为本机的 Caddy 或 Nginx，则填入 127.0.0.1）'
        DEST_HOST=$REPLY
        prompt_port '请输入 Reality 目标网站的端口' 443
        DEST_PORT=$REPLY
        select_server_name
        check_reality_dest && break
    done

    generate_reality_keys
    generate_short_id

    printf '\n%b========== 网站分流配置 ==========%b\n\n' "$GREEN" "$RESET"
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

    printf '\n%b========== 回国流量设置 ==========%b\n\n' "$GREEN" "$RESET"
    warn "屏蔽回国流量会阻止目标 IP 属于中国大陆的连接，可能带来意想不到的问题，请慎用。"
    if ask_yes_no '是否需要屏蔽回国流量（geoip:cn IP 检测）？' n; then
        BLOCK_CN_IP=1
        info "将加入 geoip:cn 屏蔽规则。"
    else
        BLOCK_CN_IP=0
        info "不会生成 geoip:cn 屏蔽规则。"
    fi

    prompt_host '请输入客户端连接的服务器域名或 IP' "$detected_ip"
    CLIENT_ADDRESS=$REPLY

    printf '请输入节点名称（默认 Xray-Reality）：'
    IFS= read -r value || die "输入已中断。"
    CLIENT_NAME=${value:-Xray-Reality}
}

write_routing_rules() {
    local index key tag
    for index in "${!ROUTING_KEYS[@]}"; do
        key=${ROUTING_KEYS[$index]}
        tag=${ROUTING_TAGS[$index]}
        case "$key" in
            hongkong)
                printf ',\n%s' "        {
          \"type\": \"field\",
          \"domain\": [
            \"geosite:openai\",
            \"geosite:x\",
            \"geosite:yahoo\",
            \"geosite:google-deepmind\",
            \"geosite:google-gemini\",
            \"geosite:tiktok\"
          ],
          \"outboundTag\": \"$tag\"
        }"
                ;;
            media)
                printf ',\n%s' "        {
          \"type\": \"field\",
          \"domain\": [\"geosite:netflix\", \"geosite:disney\"],
          \"outboundTag\": \"$tag\"
        }"
                ;;
            paypal)
                printf ',\n%s' "        {
          \"type\": \"field\",
          \"domain\": [\"geosite:paypal\"],
          \"outboundTag\": \"$tag\"
        }"
                ;;
            ai)
                printf ',\n%s' "        {
          \"type\": \"field\",
          \"domain\": [
            \"geosite:openai\",
            \"geosite:x\",
            \"geosite:google-deepmind\",
            \"geosite:google-gemini\"
          ],
          \"outboundTag\": \"$tag\"
        }"
                ;;
        esac
    done
}

write_cn_ip_block_rule() {
    if ((BLOCK_CN_IP == 1)); then
        printf '%s' ',
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "block"
      }'
    fi
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
      \"tag\": \"$tag\",
      \"protocol\": \"trojan\",
      \"settings\": {
        \"address\": \"$address\",
        \"port\": $port,
        \"password\": \"$password\"
      },
      \"streamSettings\": {
        \"network\": \"tcp\",
        \"security\": \"tls\",
        \"tlsSettings\": {
          \"serverName\": \"$address\",
          \"allowInsecure\": false
        }
      }
    }"
    else
        printf ',\n%s' "    {
      \"tag\": \"$tag\",
      \"protocol\": \"shadowsocks\",
      \"settings\": {
        \"address\": \"$address\",
        \"port\": $port,
        \"method\": \"aes-256-gcm\",
        \"password\": \"$password\"
      }
    }"
    fi
}

write_config() {
    local output_file=$1 index
    local uuid dest_host server_name private_key short_id
    json_escape "$CLIENT_UUID"; uuid=$REPLY
    json_escape "$DEST_HOST"; dest_host=$REPLY
    json_escape "$SERVER_NAME"; server_name=$REPLY
    json_escape "$PRIVATE_KEY"; private_key=$REPLY
    json_escape "$SHORT_ID"; short_id=$REPLY

    {
        printf '%s' '{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      }'
        write_cn_ip_block_rule
        write_routing_rules
        printf '%s' "
    ]
  },
  \"inbounds\": [
    {
      \"listen\": \"0.0.0.0\",
      \"port\": $REALITY_PORT,
      \"protocol\": \"vless\",
      \"settings\": {
        \"clients\": [
          {
            \"id\": \"$uuid\",
            \"flow\": \"xtls-rprx-vision\"
          }
        ],
        \"decryption\": \"none\"
      },
      \"streamSettings\": {
        \"network\": \"tcp\",
        \"security\": \"reality\",
        \"realitySettings\": {
          \"show\": false,
          \"dest\": \"$dest_host:$DEST_PORT\",
          \"xver\": 0,
          \"serverNames\": [\"$server_name\"],
          \"privateKey\": \"$private_key\",
          \"shortIds\": [\"\", \"$short_id\"]
        }
      },
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\", \"quic\"],
        \"routeOnly\": true
      }
    }
  ],
  \"outbounds\": [
    {
      \"protocol\": \"freedom\",
      \"tag\": \"direct\"
    },
    {
      \"protocol\": \"blackhole\",
      \"tag\": \"block\"
    }"
        if ((ENABLE_SITE_ROUTING == 1)); then
            for index in "${!ROUTING_TAGS[@]}"; do
                write_proxy_outbound "$index"
            done
        fi
        printf '\n%s\n' '  ]' '}'
    } >"$output_file"
    chmod 600 "$output_file"
}

install_configuration() {
    local temp_dir temp_config backup_file='' timestamp test_output
    mkdir -p "$XRAY_CONFIG_DIR"
    temp_dir=$(mktemp -d "${XRAY_CONFIG_DIR}/.config-build.XXXXXX")
    temp_config="${temp_dir}/config.json"
    write_config "$temp_config"

    info "正在检查 Xray 配置……"
    if ! test_output=$(xray run -test -config "$temp_config" 2>&1); then
        printf '%s\n' "$test_output" >&2
        rm -f "$temp_config"
        rmdir "$temp_dir" 2>/dev/null || true
        die "生成的配置未通过 Xray 检查，原配置没有被修改。"
    fi
    success "Xray 配置检查通过。"

    if [[ -f "$XRAY_CONFIG_FILE" ]]; then
        timestamp=$(date +%Y%m%d-%H%M%S)
        backup_file="${XRAY_CONFIG_FILE}.bak.${timestamp}"
        cp -a "$XRAY_CONFIG_FILE" "$backup_file"
        info "旧配置已备份到：$backup_file"
    fi
    mv -f "$temp_config" "$XRAY_CONFIG_FILE"
    rmdir "$temp_dir" 2>/dev/null || true
    chmod 600 "$XRAY_CONFIG_FILE"

    systemctl daemon-reload
    systemctl enable xray >/dev/null
    if systemctl restart xray && systemctl is-active --quiet xray; then
        success "Xray 已设置为开机自启并成功启动。"
        systemctl --no-pager --full status xray || true
        return 0
    fi

    warn "Xray 启动失败，最近的服务日志如下："
    journalctl -u xray --no-pager -n 50 || true
    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        warn "正在恢复启动前的配置：$backup_file"
        cp -a "$backup_file" "$XRAY_CONFIG_FILE"
        systemctl restart xray >/dev/null 2>&1 || true
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
    printf '\n%b========== 部署完成 ==========%b\n\n' "$GREEN" "$RESET"
    printf '配置文件：%s\n' "$XRAY_CONFIG_FILE"
    printf 'Reality 端口：%s\n' "$REALITY_PORT"
    printf 'UUID：%s\n' "$CLIENT_UUID"
    printf 'Reality 目标网站：%s:%s\n' "$DEST_HOST" "$DEST_PORT"
    printf 'Reality 目标网站域名：%s\n' "$SERVER_NAME"
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
    warn "脚本会安装 Xray、生成 Reality 配置并重启 xray 服务。"
    ask_yes_no '确认继续吗？' y || exit 0

    if ((SKIP_INSTALL == 0)); then
        install_xray
    else
        require_command xray
        info "已跳过安装，使用现有版本：$(xray version | head -n 1)"
    fi
    require_command curl

    while true; do
        collect_configuration
        if install_configuration; then
            print_result
            return 0
        fi
        ask_yes_no '是否重新填写配置并再试一次？' y || die "部署未完成。"
    done
}

main "$@"
