#!/usr/bin/env bash

set -Eeuo pipefail

readonly ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

assert_contains() {
    local text=$1 expected=$2
    [[ "$text" == *"$expected"* ]] || {
        printf '断言失败：未找到 %s\n' "$expected" >&2
        return 1
    }
}

assert_not_contains() {
    local text=$1 unexpected=$2
    [[ "$text" != *"$unexpected"* ]] || {
        printf '断言失败：不应包含 %s\n' "$unexpected" >&2
        return 1
    }
}

assert_equals() {
    local actual=$1 expected=$2
    [[ "$actual" == "$expected" ]] || {
        printf '断言失败：期望 %s，实际 %s\n' "$expected" "$actual" >&2
        return 1
    }
}

load_script_functions() {
    local script=$1 source_text
    source_text=$(sed '/^main /d' "$script")
    eval "$source_text"
}

(
    load_script_functions "$ROOT_DIR/xray-onekey.sh"
    XRAY_RELEASE_CHANNEL=''
    select_xray_release <<<''
    assert_equals "$XRAY_RELEASE_CHANNEL" 'stable'
    build_xray_install_args
    assert_equals "${XRAY_INSTALL_ARGS[*]}" 'install -u root'
)

(
    load_script_functions "$ROOT_DIR/xray-onekey.sh"
    XRAY_RELEASE_CHANNEL=''
    select_xray_release <<<'2'
    assert_equals "$XRAY_RELEASE_CHANNEL" 'beta'
    build_xray_install_args
    assert_equals "${XRAY_INSTALL_ARGS[*]}" 'install -u root --beta'
)

(
    load_script_functions "$ROOT_DIR/xray-onekey.sh"
    ROUTING_KEYS=(ai)
    ROUTING_TAGS=(aiProxy)
    xray_rules=$(write_routing_rules)
    assert_contains "$xray_rules" '"domain": ["geosite:category-ai-!cn"]'
    assert_not_contains "$xray_rules" 'geosite:openai'
)

(
    load_script_functions "$ROOT_DIR/sing-box-onekey.sh"
    ROUTING_KEYS=(ai)
    ROUTING_TAGS=(aiProxy)
    singbox_rules=$(write_routing_rules)
    assert_contains "$singbox_rules" '"rule_set": ["category-ai-!cn"]'
    assert_not_contains "$singbox_rules" '"openai"'
    write_rule_set_declarations
    assert_contains "$REPLY" '"tag": "category-ai-!cn"'
    assert_contains "$REPLY" '/category-ai-!cn.srs'
    assert_not_contains "$REPLY" '"tag": "openai"'
)

printf 'AI 分流规则测试通过。\n'
