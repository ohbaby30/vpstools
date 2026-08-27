# VPS Tools

个人使用的 VPS 交互式工具脚本：

- `vpstools.sh`：VPS 常用工具菜单
- `xray-onekey.sh`：Xray VLESS + REALITY 一键部署
- `sing-box-onekey.sh`：sing-box VLESS + REALITY 一键部署

> 脚本会安装软件、修改配置并重启服务。请先阅读本说明，并在测试环境确认后再用于正式服务器。

## 目录

- [运行环境](#运行环境)
- [VPS 常用工具箱](#vps-常用工具箱)
- [Xray 一键部署](#xray-一键部署)
- [sing-box 一键部署](#sing-box-一键部署)
- [Reality 目标网站怎么填写](#reality-目标网站怎么填写)
- [配置备份与回滚](#配置备份与回滚)
- [卸载](#卸载)
- [常见问题](#常见问题)

## 运行环境

- Linux 系统，且使用 systemd。
- 以 root 运行；非 root 用户使用 `sudo`。
- VPS 需要能访问 GitHub 和 GitHub Raw；下载失败时，先检查网络、代理与 DNS。
- sing-box 支持 `amd64`、`arm64`、`armv7`、`386` 架构。
- 脚本会使用系统自带的 `ip`、`curl`、`systemctl` 等命令；常见 Debian/Ubuntu VPS 默认具备这些组件。

`vpstools.sh` 中的 BBR 项目面向 Debian 13；时区校准会设置为 `Asia/Shanghai`。它们不是 Xray 或 sing-box 部署的前置条件。

## VPS 常用工具箱

### Bash + curl 直接运行

以 root 用户运行：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/vpstools.sh)"
```

非 root 用户：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/vpstools.sh)"
```

### 下载后运行

```bash
curl -fL https://raw.githubusercontent.com/ohbaby30/vpstools/main/vpstools.sh -o vpstools.sh
chmod +x vpstools.sh
sudo ./vpstools.sh
```

## Xray 一键部署

脚本会交互生成 VLESS + REALITY 配置，安装时可选择 Xray 正式稳定版或 Beta 预发布版，按香港服务器、流媒体、PayPal、AI、Twitter 场景选择分流，并可选择是否通过 `geoip:cn` 屏蔽回国流量。每组分流均可独立选择 Trojan 或 Shadowsocks 出站。服务端路由使用 `AsIs`：域名按域名规则匹配，直接传入的 IP 仍可匹配 IP 规则，但不会为域名额外解析 IP。

客户端 ID 可以自动生成 UUID，也可以手动填写有效 UUID，或填写长度为 1–30 位、仅包含英文字母和数字的自定义 ID。客户端连接地址和节点名称只用于生成客户端导入链接，不写入 Xray 服务端配置。

### 安装版本

- 正式稳定版（默认、推荐）：执行官方 `install -u root`。
- Beta 预发布版：执行官方 `install -u root --beta`，适合测试新特性。

### 直接运行

首次安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)"
```

已安装 Xray，只重新生成并应用配置：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)" -- --skip-install
```

非 root 用户只需在命令前加 `sudo`。

### 下载后运行

```bash
curl -fL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh -o xray-onekey.sh
chmod +x xray-onekey.sh
sudo ./xray-onekey.sh
```

跳过安装，只配置现有 Xray：

```bash
sudo ./xray-onekey.sh --skip-install
```

## sing-box 一键部署

sing-box 脚本与 Xray 版的交互流程相同：生成 VLESS + REALITY 配置、按网站类别选择分流、可选 `geoip:cn` 屏蔽，并输出可导入的 `vless://` 链接。

当前脚本只安装 GitHub Releases 的**最新正式稳定版** sing-box，**没有 Beta/测试版选择**。脚本使用 MetaCubeX remote rule-set；首次启动会下载规则集，随后由 sing-box 缓存并更新。

客户端 ID 可自动生成 UUID，或手动填写有效 UUID。客户端连接地址和节点名称只用于生成客户端导入链接，不写入 sing-box 服务端配置。

### 直接运行

首次安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/sing-box-onekey.sh)"
```

已安装 sing-box，只重新生成并应用配置：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/sing-box-onekey.sh)" -- --skip-install
```

非 root 用户只需在命令前加 `sudo`。

### 下载后运行

```bash
curl -fL https://raw.githubusercontent.com/ohbaby30/vpstools/main/sing-box-onekey.sh -o sing-box-onekey.sh
chmod +x sing-box-onekey.sh
sudo ./sing-box-onekey.sh
```

跳过安装，只配置现有 sing-box：

```bash
sudo ./sing-box-onekey.sh --skip-install
```

## Reality 目标网站怎么填写

如果同一台 VPS 已有 Caddy 或 Nginx，可以让 Reality 把认证失败的普通 TLS 流量转发给它。

例如 Xray 或 sing-box 监听 `443`，本机 Caddy HTTPS 监听 `12345`：

```text
Reality 监听端口：443
是否使用本机 Caddy/Nginx 网站作为 Reality 目标网站：是
Reality 目标网站的地址：自动设置为 127.0.0.1
本机 Caddy/Nginx 的 HTTPS 监听端口：12345
本机 Caddy/Nginx 网站使用的 HTTPS 域名：与其 HTTPS 证书匹配的域名
客户端连接地址：VPS 公网 IP 或指向该 VPS 的域名
```

Reality 监听端口不能与**同机目标网站端口**相同，否则会回连到自身。脚本会在端口相同时解析目标网站的 IPv4/IPv6 地址，并通过本机路由表拦截所有指回本机的地址。

Xray 在连接地址填写域名时，会保留该域名，并询问是否增加同一 HTTPS 证书覆盖的其他域名；若填写的是 `127.0.0.1`、其他 IPv4 或 IPv6，则必须填写一个证书对应域名。sing-box 的入站 TLS 只支持一个 `server_name`，因此只使用一个目标网站证书域名，不会询问追加域名。IPv6 地址会自动写成 `[IPv6]:端口`，无需手动添加方括号。

## 配置备份与回滚

每次成功生成新配置前，脚本会备份旧配置，并只保留最近 3 份：

- Xray：`/usr/local/etc/xray/config.json.bak.时间戳`
- sing-box：`/usr/local/etc/sing-box/config.json.bak.时间戳`

新配置会先进行语法检查；检查失败时不会修改正在使用的配置。若新配置通过检查但服务重启失败，脚本会立即恢复本次启动前的备份并尝试重新启动服务。

手动回滚示例（将时间戳替换为实际文件名）：

```bash
cp -a /usr/local/etc/xray/config.json.bak.时间戳 /usr/local/etc/xray/config.json
systemctl restart xray
```

```bash
cp -a /usr/local/etc/sing-box/config.json.bak.时间戳 /usr/local/etc/sing-box/config.json
systemctl restart sing-box
```

## 卸载

卸载前如需保留配置，先自行复制配置目录到安全位置。以下命令会影响正在运行的代理服务。

### Xray

使用 Xray 官方安装脚本彻底卸载：

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
```

`--purge` 会删除 Xray 程序、systemd 服务、配置和日志；不想丢失配置时，请先备份 `/usr/local/etc/xray/`。

### sing-box

仅停止并移除服务与程序，保留配置和规则集缓存：

```bash
systemctl disable --now sing-box
rm -f /etc/systemd/system/sing-box.service /usr/local/bin/sing-box
systemctl daemon-reload
```

如确认不再需要配置和缓存，再额外删除：

```bash
rm -rf /usr/local/etc/sing-box /var/lib/sing-box
```

## 常见问题

### Reality 目标网站可以使用 Cloudflare 吗？

不建议把解析到 Cloudflare 等共享 CDN 边缘 IP 的网站作为目标。最常见的情况是 Cloudflare 开启橙云代理：认证失败的普通流量会被 Xray/sing-box 转发至目标，扫描者可能借你的 VPS 访问该 CDN，使 VPS 成为可被滥用的转发入口。

这不等于“使用 Cloudflare DNS 就一定有问题”：仅做 DNS 解析、处于灰云直连状态且目标实际连接源站 IP，不属于上述典型 CDN 转发场景。有效的 Reality 客户端连接也不会走这条认证失败转发路径。

更适合的目标是可正常访问、证书域名与填写的目标网站域名匹配、且不经共享 CDN 的 TLS 网站。若不得不用 CDN，官方建议考虑前置 Nginx 过滤不需要的 SNI，或限制认证失败流量的速率；这些措施也有额外配置与特征风险。

### 为什么同机 Caddy/Nginx 不能和 Reality 都用 443？

同一台服务器、同一 IP、同一 TCP 端口只能由一个程序监听。Reality 监听 `443` 时，同机 Caddy/Nginx 应改用另一个 HTTPS 端口，例如 `12345`；Reality 的目标网站地址填写 `127.0.0.1`，端口填写 Caddy/Nginx 的实际 HTTPS 监听端口。

### 客户端连接地址和节点名称会影响服务端吗？

不会。它们只影响脚本最后生成的 `vless://` 导入链接：连接地址决定客户端连接哪台服务器，节点名称只决定客户端列表中显示的备注。
