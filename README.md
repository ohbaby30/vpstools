# VPS Tools

面向个人使用的 VPS 交互式运维脚本集：通过单条命令进入管理菜单，完成基础环境初始化、BBR 拥塞控制配置，以及 Xray / sing-box（VLESS + REALITY）的自动化部署。

> ⚠️ 脚本会安装软件、修改系统配置并重启服务。本项目仅供个人使用，请先在测试环境中验证，使用风险由使用者自行承担。

## 功能概览

| 脚本                     | 说明                                                                |
| ---------------------- | ----------------------------------------------------------------- |
| `vpstools.sh`          | 工具箱主菜单：基础工具安装、时区校准、流媒体解锁检测、BBR 开启与验证，并可调用下列脚本                     |
| `xray-onekey.sh`       | 交互式部署 Xray（VLESS + REALITY），支持按场景配置路由分流                           |
| `sing-box-onekey.sh`   | 交互式部署 sing-box（VLESS + REALITY），交互流程与 Xray 版一致                    |
| `install_passwall2.sh` | 在 ImmortalWrt 上升级 PassWall2（仅适用于 `ohbaby30/immortalwrt-Build` 固件） |

Xray / sing-box 脚本的通用特性：

- 自动生成 REALITY 服务端配置及 `vless://` 分享链接
- 支持按场景配置路由分流（香港服务器、流媒体、PayPal、AI、Twitter），各分组可独立选择 Trojan 或 Shadowsocks 作为出站协议
- 可选屏蔽回国流量（`geoip:cn`）
- 新配置通过语法校验后才会生效；变更前自动备份旧配置，服务重启失败时自动回滚

## 快速开始

**环境要求：** Linux（systemd）；以 root 身份运行，非 root 用户请使用 `sudo`；服务器可访问 GitHub 及 GitHub Raw。

**启动工具箱（推荐）：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/vpstools.sh)"

```

**单独运行各脚本：**
```bash
# Xray 首次安装
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)"

# sing-box 首次安装
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/sing-box-onekey.sh)"

# 已安装核心程序，仅重新生成并应用配置：追加 -- --skip-install
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)" -- --skip-install

# ImmortalWrt（通过 SSH 以 root 身份执行）
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/install_passwall2.sh)"

```

**REALITY 目标站点配置示例：** 若同机已部署 Caddy / Nginx，可将其作为 REALITY 的目标站点。例如 REALITY 监听 `443`，Caddy 的 HTTPS 监听端口为 `12345`，则目标地址设置为 `127.0.0.1`，目标端口设置为 `12345`，目标域名设置为 Caddy 证书对应的域名。

## 技术栈

- **脚本：** Bash，依赖 `curl`、`systemctl`、`ip` 等系统预装命令
- **代理核心：** [Xray-core](https://github.com/XTLS/Xray-core)、[sing-box](https://github.com/SagerNet/sing-box)
- **协议：** VLESS + REALITY
- **运行环境：** Debian / Ubuntu + systemd（工具箱中的 BBR 与时区校准功能面向 Debian 13）
- **ImmortalWrt：** APK 包管理，PassWall2

## 备份、回滚与卸载

每次生成新配置前自动备份旧配置，仅保留最近 3 份：

- Xray：`/usr/local/etc/xray/config.json.bak.<时间戳>`
- sing-box：`/usr/local/etc/sing-box/config.json.bak.<时间戳>`

手动回滚（以 Xray 为例，sing-box 操作相同）：
```bash
cp -a /usr/local/etc/xray/config.json.bak.<时间戳> /usr/local/etc/xray/config.json
systemctl restart xray

```

卸载（如需保留配置，请事先备份）：
```bash
# Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge

# sing-box
systemctl disable --now sing-box
rm -f /etc/systemd/system/sing-box.service /usr/local/bin/sing-box
systemctl daemon-reload

```

## FAQ

**REALITY 目标站点是否可以使用 Cloudflare？** 不建议。若目标站点解析到 Cloudflare 等共享 CDN 的边缘 IP，认证失败的流量将被转发至该 CDN，服务器可能被恶意扫描者用作访问 CDN 的中转。建议选择证书域名与配置一致、且不经过共享 CDN 的 TLS 站点。

**同机的 Caddy / Nginx 为什么不能与 REALITY 同时监听 443？** 同一 IP 的同一 TCP 端口只能由一个进程监听。REALITY 占用 `443` 时，Caddy / Nginx 需改用其他 HTTPS 端口（如 `12345`），REALITY 目标地址指向 `127.0.0.1:<该端口>`。

**客户端连接地址和节点名称是否影响服务端配置？** 不影响。二者仅用于生成 `vless://` 分享链接。

**sing-box 是否支持选择 Beta 版本？** 不支持。脚本仅安装 GitHub Releases 上的最新正式稳定版。Xray 脚本可选择稳定版或 Beta 版。

**升级 PassWall2 后需要执行哪些操作？** 建议在 LuCI 中执行一次重置：`PassWall2 → 基本设置 → 维护 → 执行重置`。**重置将清空全部设置和节点**，请事先备份 `/etc/config/passwall2` 中所有 `config nodes` 区块，重置完成后追加至该文件末尾。该方式不保证完全恢复，请另行保留完整配置备份。

**下载失败如何排查？** 依次检查服务器到 GitHub / GitHub Raw 的网络连通性、代理设置与 DNS 解析。
