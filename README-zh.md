[English](README.md) | [简体中文](README-zh.md) | [繁體中文](README-zh-Hant.md) | [Русский](README-ru.md)

# Docker 上的 IPsec VPN 服务器

[![Build Status](https://github.com/hwdsl2/docker-ipsec-vpn-server/actions/workflows/main-alpine.yml/badge.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/actions/workflows/main-alpine.yml) [![GitHub Stars](https://raw.githubusercontent.com/hwdsl2/badges/main/img/github-stars-docker-ipsec-vpn-server.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/stargazers) [![Docker Stars](https://raw.githubusercontent.com/hwdsl2/badges/main/img/docker-stars-ipsec-vpn-server.svg)](https://hub.docker.com/r/hwdsl2/ipsec-vpn-server/) [![Docker Pulls](https://raw.githubusercontent.com/hwdsl2/badges/main/img/docker-pulls-ipsec-vpn-server.svg)](https://hub.docker.com/r/hwdsl2/ipsec-vpn-server/)

使用这个 Docker 镜像快速搭建 IPsec VPN 服务器。支持 IPsec/L2TP，Cisco IPsec 和 IKEv2 协议。

本镜像以 Alpine 3.23 或 Debian 12 为基础，并使用 [strongSwan](https://www.strongswan.org) (IPsec VPN 软件) 和 [xl2tpd](https://github.com/xelerance/xl2tpd) (L2TP 服务进程)。这是 [hwdsl2/docker-ipsec-vpn-server](https://github.com/hwdsl2/docker-ipsec-vpn-server) 的衍生版本：IPsec 守护进程由 Libreswan 换成 strongSwan。原有的 IPsec/L2TP、IPsec/XAuth 和 IKEv2 单证书模式保持不变，并增加 IKEv2 EAP-MSCHAPv2（用户名/密码）。

IPsec VPN 可以加密你的网络流量，以防止在通过因特网传送时，你和 VPN 服务器之间的任何人对你的数据的未经授权的访问。在使用不安全的网络时，这是特别有用的，例如在咖啡厅，机场或旅馆房间。

**功能特性：**

- 首次启动时自动生成 VPN 凭证、CA、服务端证书和 IKEv2 客户端证书
- IKEv2 单证书模式会生成与原项目一致的 `.p12`、`.sswan` 和 `.mobileconfig`
- 新增 IKEv2 EAP-MSCHAPv2：服务端证书认证，客户端用户名和密码认证
- 支持具有强大和快速加密算法（例如 AES-GCM）的 IKEv2 模式
- 生成 Apple 描述文件，便于配置 iOS 和 macOS
- 支持 Windows, macOS, iOS, Android, Chrome OS 和 Linux 客户端
- 同一组用户名和密码可用于 IKEv2、IPsec/L2TP 和 Cisco IPsec
- 通过 [GitHub Actions](https://github.com/hwdsl2/docker-ipsec-vpn-server/actions) 自动构建和发布
- 使用 Docker 卷实现数据持久化
- 多架构支持：`linux/amd64`、`linux/arm64`、`linux/arm/v7`

**另提供：**

- VPN：[IPsec 无 Docker 版](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README-zh.md)、[WireGuard](https://github.com/hwdsl2/docker-wireguard/blob/main/README-zh.md)、[OpenVPN](https://github.com/hwdsl2/docker-openvpn/blob/main/README-zh.md)、[Headscale](https://github.com/hwdsl2/docker-headscale/blob/main/README-zh.md)
- AI：[自托管 AI 套件](https://github.com/hwdsl2/self-hosted-ai-stack/blob/main/README-zh.md)，用于本地 LLM、聊天、RAG、语音和 AI 工具

> 📘 对自托管 AI 感兴趣吗？[The Self-Hosted AI Builder’s Guide](https://books2read.com/aiguide?store=amazon) 是一本关于构建、保护和运维自己的私有 AI 技术栈的实用指南。

## 快速开始

使用以下命令在 Docker 上快速搭建 IPsec VPN 服务器：

```bash
docker run \
    --name ipsec-vpn-server \
    --restart=always \
    -v ikev2-vpn-data:/etc/ipsec.d \
    -v /lib/modules:/lib/modules:ro \
    -p 500:500/udp \
    -p 4500:4500/udp \
    -d --privileged \
    ipsec-vpn-server:strongswan
```

你的 VPN 登录凭证将会被自动随机生成。请参见[获取 VPN 登录信息](#获取-vpn-登录信息)。

另外，你也可以在不使用 Docker 的情况下[安装 IPsec VPN](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README-zh.md)。要了解更多有关如何使用本镜像的信息，请继续阅读以下部分。

## 社区

- 📬 [获取项目更新和免费部署指南](https://selfhostedstack.beehiiv.com/subscribe?utm_campaign=vpn-zh)（每月 1–2 封邮件；指南为英文 PDF）
- 💬 加入 [r/selfhostedstack](https://www.reddit.com/r/selfhostedstack/) 社区参与讨论
- ⭐ 如果你觉得本项目有用，请为仓库加星——这有助于让更多人发现它。

## 系统要求

- 具有公网 IP 地址或 DNS 名称的 Linux 服务器
- 已安装 Docker
- 在防火墙中开放 VPN 端口（UDP 500 和 4500）
- 你也可以使用 [Podman](https://docs.podman.io) 运行本镜像，需要首先为 `docker` 命令创建一个别名

**注：** 高级用户可以在 macOS 上通过安装 [Docker for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) 使用本镜像。在使用 IPsec/L2TP 模式之前，你可能需要运行 `docker restart ipsec-vpn-server` 重启一次容器。本镜像不支持 Docker for Windows。

## 下载

预构建的可信任镜像可在 [Docker Hub registry](https://hub.docker.com/r/hwdsl2/ipsec-vpn-server/) 下载：

```bash
docker pull hwdsl2/ipsec-vpn-server
```

或者，你也可以从 [Quay.io](https://quay.io/repository/hwdsl2/ipsec-vpn-server) 下载：

```bash
docker pull quay.io/hwdsl2/ipsec-vpn-server
docker image tag quay.io/hwdsl2/ipsec-vpn-server hwdsl2/ipsec-vpn-server
```

支持的平台：`linux/amd64`、`linux/arm64` 和 `linux/arm/v7`。

高级用户可以自己从 GitHub [编译源代码](docs/advanced-usage-zh.md#从源代码构建)。

### 镜像对照表

有两个预构建的镜像可用。默认的基于 Alpine 的镜像大小仅 ~19 MB。

|                 | 基于 Alpine               | 基于 Debian                     |
| --------------- | ------------------------ | ------------------------------ |
| 镜像名称          | hwdsl2/ipsec-vpn-server  | hwdsl2/ipsec-vpn-server:debian |
| 压缩后大小        | ~ 19 MB                  | ~ 62 MB                        |
| 基础镜像          | Alpine Linux 3.23        | Debian Linux 12                |
| 系统架构          | amd64, arm64, arm/v7     | amd64, arm64, arm/v7           |
| IPsec 软件        | strongSwan               | strongSwan                     |
| IPsec/L2TP      | ✅                       | ✅                              |
| Cisco IPsec     | ✅                       | ✅                              |
| IKEv2 单证书        | ✅                       | ✅                              |
| IKEv2 EAP-MSCHAPv2 | ✅                    | ✅                              |

**注：** 要使用基于 Debian 的镜像，请将本自述文件中所有的 `hwdsl2/ipsec-vpn-server` 替换为 `hwdsl2/ipsec-vpn-server:debian`。这些镜像当前与 Synology NAS 系统不兼容。

在本机构建镜像：

```bash
docker build -t ipsec-vpn-server:strongswan .
# Debian 基础镜像
docker build -f Dockerfile.debian -t ipsec-vpn-server:strongswan-debian .
```

## 如何使用本镜像

### 环境变量

**注：** 所有这些变量对于本镜像都是可选的，也就是说无需定义它们就可以搭建 IPsec VPN 服务器。你可以运行 `touch vpn.env` 创建一个空的 `env` 文件，然后跳到下一节。

这个 Docker 镜像使用以下几个变量，可以在一个 `env` 文件中定义（参见[示例](vpn.env.example)）：

```
VPN_IPSEC_PSK=your_ipsec_pre_shared_key
VPN_USER=your_vpn_username
VPN_PASSWORD=your_vpn_password
```

这将创建一个用于 VPN 登录的用户账户，它可以在你的多个设备上使用[\*](#重要提示)。IPsec PSK (预共享密钥) 由 `VPN_IPSEC_PSK` 环境变量指定。VPN 用户名和密码分别在 `VPN_USER` 和 `VPN_PASSWORD` 中定义。

支持创建额外的 VPN 用户，如果需要，可以像下面这样在你的 `env` 文件中定义。用户名和密码必须分别使用空格进行分隔，并且用户名不能有重复。所有的 VPN 用户将共享同一个 IPsec PSK。

```
VPN_ADDL_USERS=additional_username_1 additional_username_2
VPN_ADDL_PASSWORDS=additional_password_1 additional_password_2
```

同一组用户名和密码用于 IPsec/L2TP、IPsec/XAuth ("Cisco IPsec") 和 IKEv2 EAP-MSCHAPv2。IPsec PSK 只用于前两种模式。IKEv2 单证书模式使用客户端证书，不使用这组用户名和密码。客户端配置见[配置并使用 IKEv2 VPN](#配置并使用-ikev2-vpn)。

> [!IMPORTANT]
> 在 `env` 文件中填写值时，不要在值外添加引号，也不要在 `=` 两侧添加空格。值中不能包含 `\`、`"` 或 `'`。一个安全的 IPsec PSK 应该至少包含 20 个随机字符。

**注：** 如果在创建 Docker 容器后修改 `env` 文件，则必须删除并重新创建容器才能使更改生效。参见[更新 Docker 镜像](#更新-docker-镜像)。

### 其他环境变量

高级用户可以指定一个域名，客户端名称和/或另外的 DNS 服务器。这是可选的。

<details>
<summary>
了解如何指定一个域名，客户端名称和/或另外的 DNS 服务器。
</summary>

高级用户可以指定一个域名作为 IKEv2 服务器地址。这是可选的。该域名必须是一个全称域名 (FQDN)。示例如下：

```
VPN_DNS_NAME=vpn.example.com
```

你可以指定第一个 IKEv2 客户端的名称。该名称不能包含空格或者除 `-` `_` 之外的任何特殊字符。如果未指定，则使用默认值 `vpnclient`。

```
VPN_CLIENT_NAME=your_client_name
```

在 VPN 已连接时，客户端默认配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。你可以为所有的 VPN 模式指定另外的 DNS 服务器。示例如下：

```
VPN_DNS_SRV1=1.1.1.1
VPN_DNS_SRV2=1.0.0.1
```

有关详细信息以及一些流行的公共 DNS 提供商的列表，参见[使用其他的 DNS 服务器](docs/advanced-usage-zh.md)。

默认情况下，导入 IKEv2 客户端配置时不需要密码。你可以选择使用随机密码保护客户端配置文件。

```
VPN_PROTECT_CONFIG=yes
```

**注：** 如果在 Docker 容器中已经配置了 IKEv2，则以上变量对 IKEv2 模式无效。在这种情况下，你可以移除 IKEv2 并使用自定义选项重新配置它。参见[配置并使用 IKEv2 VPN](#配置并使用-ikev2-vpn)。
</details>

### 运行 IPsec VPN 服务器

使用本镜像创建一个新的 Docker 容器（将 `./vpn.env` 替换为你自己的 `env` 文件）：

```bash
docker run \
    --name ipsec-vpn-server \
    --env-file ./vpn.env \
    --restart=always \
    -v ikev2-vpn-data:/etc/ipsec.d \
    -v /lib/modules:/lib/modules:ro \
    -p 500:500/udp \
    -p 4500:4500/udp \
    -d --privileged \
    ipsec-vpn-server:strongswan
```

在该命令中，我们使用 `docker run` 的 `-v` 选项来创建一个名为 `ikev2-vpn-data` 的新 [Docker 卷](https://docs.docker.com/storage/volumes/)，并且将它挂载到容器内的 `/etc/ipsec.d` 目录下。IKEv2 的相关数据（比如证书和密钥）在该卷中保存，之后当你需要重新创建 Docker 容器的时候，只需指定同一个卷。

推荐在使用本镜像时启用 IKEv2。如果你不想启用 IKEv2 而仅使用 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式连接到 VPN，可以去掉上面 `docker run` 命令中的第一个 `-v` 选项。

**注：** 高级用户也可以[不启用 privileged 模式运行](docs/advanced-usage-zh.md#不启用-privileged-模式运行)。

### 获取 VPN 登录信息

如果你在上述 `docker run` 命令中没有指定 `env` 文件，`VPN_USER` 会默认为 `vpnuser`，并且 `VPN_IPSEC_PSK` 和 `VPN_PASSWORD` 会被自动随机生成。要获取这些登录信息，可以查看容器的日志：

```bash
docker logs ipsec-vpn-server
```

在命令输出中查找这些行：

```
Connect to your new VPN with these details:

Server IP: 你的VPN服务器IP
IPsec PSK: 你的IPsec预共享密钥
Username: 你的VPN用户名
Password: 你的VPN密码
```

在命令输出中也会包含 IKEv2 配置信息（如果已启用）。

（可选步骤）备份自动生成的 VPN 登录信息（如果有）到当前目录：

```bash
docker cp ipsec-vpn-server:/etc/ipsec.d/vpn-gen.env ./
```

## 使用 docker-compose

```bash
cp vpn.env.example vpn.env
# 如果需要，编辑 vpn.env，然后：
docker compose up -d
docker logs ipsec-vpn-server
```

示例 `docker-compose.yml`（已包含在内）：

```yaml
volumes:
  ikev2-vpn-data:

services:
  vpn:
    image: ipsec-vpn-server:strongswan
    restart: always
    env_file:
      - ./vpn.env
    ports:
      - "500:500/udp"
      - "4500:4500/udp"
    privileged: true
    hostname: ipsec-vpn-server
    container_name: ipsec-vpn-server
    volumes:
      - ikev2-vpn-data:/etc/ipsec.d
      - /lib/modules:/lib/modules:ro
```

## 下一步

*其他语言版本: [English](README.md#next-steps), [简体中文](README-zh.md#下一步), [繁體中文](README-zh-Hant.md#下一步), [Русский](README-ru.md#следующие-шаги)。*

配置你的计算机或其它设备使用 VPN。请参见：

**[配置并使用 IKEv2 VPN（推荐）](#配置并使用-ikev2-vpn)**

**[配置 IPsec/L2TP VPN 客户端](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-zh.md)**

**[配置 IPsec/XAuth ("Cisco IPsec") VPN 客户端](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-xauth-zh.md)**

**阅读 [📘 VPN book](docs/vpn-book-zh.md) 以访问[额外内容](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)。**

开始使用自己的专属 VPN! :sparkles::tada::rocket::sparkles:

## 重要提示

**Windows 用户** 对于 IPsec/L2TP 模式，在首次连接之前需要[修改注册表](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-zh.md#windows-错误-809)，以解决 VPN 服务器或客户端与 NAT（比如家用路由器）的兼容问题。

同一个 VPN 账户可以在你的多个设备上使用。但是由于 IPsec/L2TP 的局限性，如果需要连接在同一个 NAT（比如家用路由器）后面的多个设备，你必须使用 [IKEv2](#配置并使用-ikev2-vpn) 或者 [IPsec/XAuth](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-xauth-zh.md) 模式。

如需添加，修改或者删除 VPN 用户账户，首先更新你的 `env` 文件，然后你必须按照[下一节](#更新-docker-镜像)的说明来删除并重新创建 Docker 容器。高级用户可以[绑定挂载](docs/advanced-usage-zh.md#绑定挂载-env-文件) `env` 文件。

对于有外部防火墙的服务器（比如 [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)），请为 VPN 打开 UDP 端口 500 和 4500。阿里云用户请参见 [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433)。

在 VPN 已连接时，客户端配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。如果偏好其它的域名解析服务，请看[这里](docs/advanced-usage-zh.md#使用其他的-dns-服务器)。

## 更新 Docker 镜像

要更新 Docker 镜像和容器，首先[下载](#下载)最新版本：

```bash
docker pull hwdsl2/ipsec-vpn-server
```

如果 Docker 镜像已经是最新的，你会看到提示：

```
Status: Image is up to date for hwdsl2/ipsec-vpn-server:latest
```

否则将会下载最新版本。要更新你的 Docker 容器，首先记下你所有的 [VPN 登录信息](#获取-vpn-登录信息)。然后删除 Docker 容器： `docker rm -f ipsec-vpn-server`。最后按照[如何使用本镜像](#如何使用本镜像)的说明来重新创建它。

## 配置并使用 IKEv2 VPN

容器必须把 Docker 卷挂载到 `/etc/ipsec.d`。首次启动会生成 CA、服务端证书，以及名为 `vpnclient`（或 `VPN_CLIENT_NAME`）的 IKEv2 客户端证书。服务端地址来自公网 IP，或者来自 `VPN_DNS_NAME`。客户端填写的服务器地址必须和证书身份一致。

支持两种 IKEv2 模式，可以同时使用：

- **单证书：** 与原项目相同。每个客户端有自己的证书。地址池与 Cisco IPsec 相同（默认 `192.168.43.10-192.168.43.250`）。
- **EAP-MSCHAPv2：** 服务端出示证书，客户端使用 `VPN_USER` / `VPN_PASSWORD`（以及 `VPN_ADDL_USERS`）。地址池默认 `192.168.44.10-192.168.44.250`。不使用 IPsec PSK。

查看容器日志：

```bash
docker logs ipsec-vpn-server
```

日志里会打印 VPN 用户名和密码，以及单证书配置文件的路径。只有设置了 `VPN_PROTECT_CONFIG=yes` 时，才会额外打印 `.p12` 导入密码。证书私钥和 charon 调试信息不会写入这条日志。

复制单证书客户端配置：

```bash
docker cp ipsec-vpn-server:/etc/ipsec.d/vpnclient.p12 ./
docker cp ipsec-vpn-server:/etc/ipsec.d/vpnclient.sswan ./
docker cp ipsec-vpn-server:/etc/ipsec.d/vpnclient.mobileconfig ./
docker exec -it ipsec-vpn-server ikev2.sh --listclients
docker exec -it ipsec-vpn-server ikev2.sh --addclient myphone
```

`.p12` 内含客户端证书、私钥和 CA。默认导入密码为空。`.sswan` 的类型是 `ikev2-cert`。`.mobileconfig` 使用证书认证。添加、导出、吊销或删除客户端的命令与原项目一致：`--addclient`、`--exportclient`、`--listclients`、`--revokeclient`、`--deleteclient`、`--removeikev2`。

EAP-MSCHAPv2 的配置文件按用户名分开存放，避免覆盖单证书文件：

```bash
docker cp ipsec-vpn-server:/etc/ipsec.d/eap-vpnuser.p12 ./
docker cp ipsec-vpn-server:/etc/ipsec.d/eap-vpnuser.sswan ./
docker cp ipsec-vpn-server:/etc/ipsec.d/eap-vpnuser.mobileconfig ./
```

`eap-<用户名>.p12` 里是 CA 证书，用来信任服务器，不是客户端证书。默认导入密码为空；`VPN_PROTECT_CONFIG=yes` 时与单证书配置使用同一个导入密码，并且只在日志里打印一次。

客户端设置：

- **单证书：** Windows 和 Linux 导入 `.p12`；Android 用 strongSwan 客户端导入 `.sswan`；iOS / macOS 安装 `.mobileconfig`。
- **EAP-MSCHAPv2：** Windows 导入 `eap-<用户名>.p12` 后，IKEv2 身份验证选 “Microsoft: 安全密码 (EAP-MSCHAP v2)”。Android 导入 `eap-<用户名>.sswan`，或在 Android 11 及以上使用系统 IKEv2/IPSec MSCHAPv2。iOS / macOS 安装 `eap-<用户名>.mobileconfig`。

修改用户后删除并重新创建容器，继续使用同一个卷，已安装的 CA 可以保持不变。更换 `VPN_DNS_NAME` 或服务器 IP 时，启动脚本会用原来的 CA 重新签发服务端证书，并更新已有客户端配置里的服务器地址。

要彻底更换 CA，先记下登录信息，再执行 `docker rm -f ipsec-vpn-server` 和 `docker volume rm ikev2-vpn-data`，然后重新创建容器。

## 高级用法

请参见[高级用法](docs/advanced-usage-zh.md)。

- [使用其他的 DNS 服务器](docs/advanced-usage-zh.md#使用其他的-dns-服务器)
- [不启用 privileged 模式运行](docs/advanced-usage-zh.md#不启用-privileged-模式运行)
- [选择 VPN 模式](docs/advanced-usage-zh.md#选择-vpn-模式)
- [启用 IKEv2 前向保密](docs/advanced-usage-zh.md#启用-ikev2-前向保密)
- [访问 Docker 主机上的其它容器](docs/advanced-usage-zh.md#访问-docker-主机上的其它容器)
- [指定 VPN 服务器的公有 IP](docs/advanced-usage-zh.md#指定-vpn-服务器的公有-ip)
- [为 VPN 客户端指定静态 IP](docs/advanced-usage-zh.md#为-vpn-客户端指定静态-ip)
- [自定义 VPN 子网](docs/advanced-usage-zh.md#自定义-vpn-子网)
- [IPv6 支持](docs/advanced-usage-zh.md#ipv6-支持)
- [VPN 分流](docs/advanced-usage-zh.md#vpn-分流)
- [关于 host network 模式](docs/advanced-usage-zh.md#关于-host-network-模式)
- [启用 Libreswan 日志](docs/advanced-usage-zh.md#启用-libreswan-日志)
- [查看服务器状态](docs/advanced-usage-zh.md#查看服务器状态)
- [从源代码构建](docs/advanced-usage-zh.md#从源代码构建)
- [在容器中运行 Bash shell](docs/advanced-usage-zh.md#在容器中运行-bash-shell)
- [绑定挂载 env 文件](docs/advanced-usage-zh.md#绑定挂载-env-文件)
- [部署 Google BBR 拥塞控制](docs/advanced-usage-zh.md#部署-google-bbr-拥塞控制)

## 技术细节

需要运行以下两个服务：`strongSwan (charon)` 提供 IPsec VPN，`xl2tpd` 提供 L2TP 支持。

默认的 IPsec 配置支持以下协议：

* IPsec/L2TP with PSK
* IKEv1 with PSK and XAuth ("Cisco IPsec")
* IKEv2 with a client certificate
* IKEv2 with EAP-MSCHAPv2

所需端口：`500/udp` 和 `4500/udp`（IPsec）

## 授权协议

**注：** 镜像中的软件组件（例如 strongSwan 和 xl2tpd）在其各自版权所有者选择的相应许可下。对于任何预构建的镜像的使用，用户有责任确保对该镜像的任何使用符合其中包含的所有软件的任何相关许可。

版权所有 (C) 2016-2026 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
基于 [Thomas Sarlandie 的工作](https://github.com/sarfata/voodooprivacy) (版权所有 2012)

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
这个项目是以[知识共享署名-相同方式共享3.0](http://creativecommons.org/licenses/by-sa/3.0/) 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
