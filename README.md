# VPS Tools

个人使用的 VPS 工具脚本，目前包含：

- `vpstools.sh`：VPS 常用工具菜单
- `xray-onekey.sh`：Xray VLESS + REALITY 交互式一键部署脚本

> 建议先阅读脚本内容，并在测试环境确认后再使用。涉及安装软件、修改系统配置和重启服务的功能需要 root 权限。

## VPS 常用工具箱

### 使用 Bash + curl 直接运行

以 root 用户运行：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/vpstools.sh)"
```

非 root 用户可以使用：

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

脚本支持安装 Xray 稳定版、交互生成 VLESS + REALITY 配置、按香港服务器/流媒体/PayPal/AI 场景选择分流、选择是否通过 `geoip:cn` 屏蔽回国流量，以及输出 PassWall2 可导入的 `vless://` 链接。每组分流均可独立选择 Trojan 或 Shadowsocks 出站。

### 尚未安装 Xray

使用 Bash + curl 直接运行：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)"
```

非 root 用户：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)"
```

### 已经安装 Xray

跳过安装，只重新生成并应用配置：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)" -- --skip-install
```

非 root 用户：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh)" -- --skip-install
```

### 下载后运行

```bash
curl -fL https://raw.githubusercontent.com/ohbaby30/vpstools/main/xray-onekey.sh -o xray-onekey.sh
chmod +x xray-onekey.sh
```

安装 Xray 并配置：

```bash
sudo ./xray-onekey.sh
```

跳过安装，只配置现有 Xray：

```bash
sudo ./xray-onekey.sh --skip-install
```

查看帮助：

```bash
./xray-onekey.sh --help
```

## 使用同机 Caddy 或 Nginx 作为 REALITY 目标网站

例如 Xray 监听 `443`，Caddy HTTPS 监听 `44422`，可以这样填写：

```text
Reality 监听端口：443
Reality 目标网站：127.0.0.1
Reality 目标网站的端口：44422
Reality 目标网站域名：Caddy 或 Nginx 证书对应的域名
客户端连接地址：VPS 公网 IP 或指向该 VPS 的域名
```

REALITY 的监听端口与同机目标网站端口不能相同，否则会回连 Xray 自身。
