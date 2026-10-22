# VPS Tools

个人自用的 VPS 交互式工具脚本集：一条命令打开菜单，装常用工具、开 BBR、一键部署 Xray / sing-box（VLESS + REALITY）。

> 脚本会安装软件、修改配置并重启服务。请先在测试环境确认，并自行保留配置备份。

## 能做什么

| 脚本 | 作用 |
| --- | --- |
| `vpstools.sh` | 主菜单：安装常用工具、校准时区、流媒体测试、开启/验证 BBR，并可调用下面几个脚本 |
| `xray-onekey.sh` | 交互式部署 Xray：VLESS + REALITY，支持按场景分流 |
| `sing-box-onekey.sh` | 交互式部署 sing-box：VLESS + REALITY，交互流程与 Xray 版相近 |
| `install_passwall2.sh` | ImmortalWrt 上一键升级 PassWall2，仅保证适配 `ohbaby30/immortalwrt-Build` 的 x86_64 / R4S 固件 |

Xray / sing-box 脚本的共同能力：

- 自动生成 REALITY 配置和 `vless://` 导入链接。
- 按场景选择分流（香港服务器、流媒体、PayPal、AI、Twitter），每组可选 Trojan 或 Shadowsocks 出站。
- 可选屏蔽回国流量：Xray 使用 `geoip:cn`，sing-box 使用远程 rule-set。
- 配置先检查再生效；替换前备份旧配置，重启失败时尝试恢复备份并重新启动。

## 怎么用

**VPS 环境：** Linux + systemd，以 root 运行（非 root 在命令前加 `sudo`），能访问 GitHub 和 GitHub Raw，并具备 `curl`、`ip` 等基础工具。sing-box 支持 `amd64`、`arm64`、`armv7`、`386`。ImmortalWrt 脚本单独使用 `sh` 和 APK 包管理器，不要求 systemd。

**打开工具箱菜单：**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/vpstools.sh)"
```

**也可以单独运行某个脚本：**

```bash
# Xray 首次安装：可选稳定版或 Beta
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)"

# sing-box 首次安装：最新正式稳定版
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/sing-box-onekey.sh)"

# 已安装，只重新生成并应用配置（会重启服务，并非仅升级内核）
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)" -- --skip-install
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/sing-box-onekey.sh)" -- --skip-install

# ImmortalWrt：SSH 里以 root 执行
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/install_passwall2.sh)"
```

**REALITY 目标网站怎么填：** 如果同机已有 Caddy / Nginx，可以作为目标。例如 REALITY 监听 `443`，Caddy HTTPS 监听 `12345`，那么目标地址填 `127.0.0.1`、端口填 `12345`、域名填 Caddy 证书对应的域名。客户端连接地址则填 VPS 的公网 IP 或指向它的域名。目标不能回连到 REALITY 自己的监听端口。

## 安装与权限说明

- **Xray：** 调用官方安装脚本，已有安装暂缓重启，等新配置及权限检查通过后统一重启。全新安装时，官方脚本可能先启动默认空配置。
- **Xray 配置权限：** 当前默认 xray 服务使用 `640 root:xray`；`--skip-install` 沿用现有运行用户，旧 root 服务使用 `600 root:root`，其他用户使用 `640 root:<服务组>`。配置会按实际服务身份检查读取权限。
- **中途退出：** Xray 安装阶段开始后若取消或失败，脚本会检查现有配置并尝试补做重启；检查失败则提示手动处理，不能视为升级完成。强制结束进程或断电无法触发退出处理。
- **sing-box：** 使用 MetaCubeX 远程规则集，首次使用时需要联网下载，后续缓存和更新；生成配置兼容 1.13 与 1.14+ 的规则集下载格式。
- **PassWall2：** 从固定更新清单下载主程序和中文 APK，校验 SHA-256 后安装。其他固件不保证兼容。

## 技术栈

- **Shell：** VPS 脚本使用 Bash，PassWall2 升级脚本使用 POSIX sh，并调用系统命令。
- **代理核心：** [Xray-core](https://github.com/XTLS/Xray-core)、[sing-box](https://github.com/SagerNet/sing-box)。
- **协议：** VLESS + REALITY。
- **系统：** 常见 Debian / Ubuntu + systemd；BBR 开启项面向 Debian 13，时区校准设置为 `Asia/Shanghai`。
- **ImmortalWrt：** APK 包管理，PassWall2。

## 备份、回滚与卸载

旧配置自动备份，只留最近 3 份：

- Xray：`/usr/local/etc/xray/config.json.bak.时间戳`
- sing-box：`/usr/local/etc/sing-box/config.json.bak.时间戳`

**手动回滚 Xray：** 替换实际备份文件名。先用 `systemctl show xray -p User -p Group` 核对；下面适用于默认的 `xray:xray` 服务。若服务仍为 root，所属组改用 root、权限改为 600，检查命令直接执行 `xray run -test -config /usr/local/etc/xray/config.json`；其他用户则对应调整组名及检查身份。备份仅 root 可读，不能只复制后直接重启。

```bash
(
  set -e
  cp -a /usr/local/etc/xray/config.json.bak.时间戳 /usr/local/etc/xray/config.json
  chown root:xray /usr/local/etc/xray/config.json
  chmod 640 /usr/local/etc/xray/config.json
  runuser -u xray -g xray -- /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
  systemctl restart xray
  systemctl status xray --no-pager -l
)
```

**手动回滚 sing-box：**

```bash
cp -a /usr/local/etc/sing-box/config.json.bak.时间戳 /usr/local/etc/sing-box/config.json
systemctl restart sing-box
```

自动或手动恢复后，都应确认服务状态并用客户端实际连接。配置检查不代表代理连接一定正常；配置回滚也不会回退核心程序或服务文件。

**卸载：** 先自行备份配置。Xray 的 `--purge` 会删除程序、服务、配置和日志；下面 sing-box 命令保留配置和规则集缓存。

```bash
# Xray：彻底卸载
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge

# sing-box：停止服务，移除服务文件和程序
systemctl disable --now sing-box
rm -f /etc/systemd/system/sing-box.service /usr/local/bin/sing-box
systemctl daemon-reload
```

## 常见问题

**REALITY 目标网站能用 Cloudflare 吗？** 不建议使用经 Cloudflare 橙云等共享 CDN 代理的网站：认证失败的流量会转发到目标，VPS 可能被扫描者当成转发入口。仅使用 Cloudflare DNS、灰云直连源站不属于这个场景。建议选可访问、证书域名匹配且不经共享 CDN 的 TLS 网站。

**为什么同机 Caddy / Nginx 不能和 REALITY 都用 443？** 同一 IP 的同一 TCP 端口不能由这两个服务同时监听。REALITY 用 443 时，Caddy / Nginx 改用其他 HTTPS 端口（如 `12345`），目标指向 `127.0.0.1:该端口`。

**客户端连接地址和节点名称会影响服务端吗？** 不会，它们只用于生成 `vless://` 导入链接。链接包含连接凭据，请妥善保管。

**sing-box 有 Beta 版可选吗？** 此脚本没有，只安装最新正式稳定版；Xray 脚本可以选正式版或 Beta。

**PassWall2 升级后要做什么？** 建议在 LuCI 执行一次重置：`PassWall2 → 基本设置 → 维护 → 执行重置`。**重置会清空所有设置和节点。** 请先保存完整的 `/etc/config/passwall2`，另行复制其中所有 `config nodes` 区块；重置后可尝试追加节点区块恢复，但不保证兼容新版本。

**下载或启动失败怎么办？** 下载失败先检查 GitHub / GitHub Raw、网络、代理和 DNS；启动失败查看 `journalctl -u xray -n 40 --no-pager -l`，sing-box 则把服务名改为 `sing-box`。遇到 `permission denied` 时核对服务用户及配置权限，不要直接放宽为 `777`。
