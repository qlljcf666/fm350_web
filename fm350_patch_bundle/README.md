# FM350 一键补齐 bundle

> Fibocom FM350 5G RedCap 模块 · ADB 一键补齐 OpenWrt 路由管理能力
> 补齐来源：FG360 recovery squashfs（同平台 MTK aarch64 musl，ABI 兼容）

---

## 一、FM350 原生缺陷

FM350 原厂 rootfs（`4.19.205 aarch64`）虽然内核已编译进完整 netfilter 模块（51 个 `.ko`），但**用户态几乎空白**：

| 缺失项 | 原厂状态 | 补齐后 |
|---|---|---|
| **防火墙 fw3** | 有 netfilter .ko 但 `/sbin/fw3` 二进制不存在 | `/sbin/fw3` + `/etc/config/firewall` + `/etc/firewall.user` |
| **路由管理 (netifd)** | `/sbin/netifd` 有，但 `/etc/init.d/network` 全是注释 | 完整 init.d/network + `/etc/config/network`（usb0=LAN, ppp0=WAN） |
| **Web 后台** | 无 uhttpd / rpcd / Lua / LuCI | LuCI 全套（312 Lua 文件）+ uhttpd + rpcd + bootstrap 主题 |
| **DHCP / DNS** | 无 dnsmasq | dnsmasq + odhcpd(IPv6) + 静态 DNS |
| **SSH** | 无 dropbear | dropbear SSH server（port 22） |
| **自动拨号** | 内核 ppp 模块有，用户态 pppd/dhcpc 缺失 | pppd + odhcp6c + iptables MASQ NAT |
| **证书 / SSL** | 无 CA | `/etc/ssl/ca-certificates.crt`（200+ CA） |
| **NTP 时间** | 无 | sysntpd |
| **UPnP** | 无 | miniupnpd |
| **网络工具** | 缺 ethtool/bridge/tc/conntrack | 完整工具链 |

**补齐后：FM350 变成一台完整的 OpenWrt 路由终端，PC 通过 USB 接入自动分配 192.168.45.x。**

---

## 二、快速开始

### Windows（推荐）
```
双击: 一键补齐.bat
      → 菜单 [1] 安装并启动
```

### 命令行
```bat
一键补齐.bat install       :: 一步到位
一键补齐.bat status        :: 查看状态
一键补齐.bat uninstall     :: 卸载
```

### Mac / Linux / Git Bash
```bash
bash deploy.sh install     # 推送 + 启动
bash deploy.sh status      # 状态检查
bash deploy.sh restart     # 重启服务
```

### 部署后
| 服务 | 地址 |
|---|---|
| **LuCI Web 管理** | http://192.168.45.1/ |
| **SSH** | `ssh root@192.168.45.1`（默认密码空） |
| **PC 网关** | 192.168.45.1 / 24 |

---

## 三、前置条件

| 项 | 要求 |
|---|---|
| 模块 | Fibocom FM350（或同 MTK aarch64 musl 平台） |
| USB 连接 | USB 线接 PC，`adb devices` 能看到设备 |
| PC 环境 | Android Platform Tools（adb）+ Git Bash / WSL bash |
| 模块内核 | ≥ 4.19（netfilter .ko 已内置） |

```bash
# 快速自检
adb devices           # 必须有设备
adb root && adb shell uname -a   # aarch64 + 4.19.x
```

---

## 四、命令一览

| 命令 | 作用 |
|---|---|
| `install` | 完整部署：push → chmod → enable → start |
| `push` | 只推文件到 `/tmp/fm350_patch` + 复制到系统路径（不启动服务） |
| `start` | 启动补齐服务（network → fw3 → dnsmasq → dropbear → uhttpd → rpcd → sysntpd → odhcpd） |
| `stop` | 停止补齐服务 |
| `restart` | stop + start |
| `status` | 进程 / 二进制 / 关键文件 / 接口 / iptables 全面检查 |
| `enable` | 设置全部服务开机自启（procd enable） |
| `disable` | 取消全部服务开机自启 |
| `uninstall` | 停服务 + disable + 删除补齐 config（重启回原生） |

---

## 五、bundle 目录结构

```
fm350_patch_bundle/
├── 一键补齐.bat                 Windows 启动器（UTF-8 BOM, CRLF, chcp 65001）
├── deploy.sh                    ADB 部署脚本（bash, 330 行）
├── README.md                    本文件
│
└── rootfs/                      ← 推送目标：/
    ├── sbin/
    │   ├── fw3                  防火墙 3 CLI (117 KB)
    │   └── rpcd                 LuCI RPC 后端
    │
    ├── usr/sbin/
    │   ├── dnsmasq               DNS + DHCP (229 KB)
    │   ├── dropbear              SSH server (175 KB)
    │   ├── uhttpd                HTTP server
    │   ├── rpcd                 (重复副本)
    │   ├── pppd                  PPP 拨号
    │   ├── odhcpd / odhcp6c      DHCPv6
    │   ├── miniupnpd             UPnP
    │   ├── ntpclient / sshd
    │   ├── ebtables / tc / bridge / ethtool / conntrack
    │   └── ...
    │
    ├── usr/bin/
    │   ├── openssl
    │   └── ssh-keygen
    │
    ├── lib/
    │   ├── libubus.so
    │   ├── libustream-ssl.so
    │   └── ...
    │
    ├── etc/
    │   ├── config/               FM350 专用配置
    │   │   ├── network           usb0=LAN(192.168.45.1/24) ppp0=WAN(dhcp)
    │   │   ├── firewall          简化版 MASQ zone
    │   │   ├── dhcp              dnsmasq 配置
    │   │   ├── dropbear          SSH port 22, root login on
    │   │   ├── uhttpd            关闭 https, :80
    │   │   ├── rpcd              LuCI RPC
    │   │   ├── luci              UCI 权限
    │   │   └── ntpclient
    │   ├── init.d/               procd 启动脚本
    │   │   ├── network · firewall · dnsmasq
    │   │   ├── dropbear · uhttpd · rpcd
    │   │   ├── odhcpd · sysntpd · miniupnpd · cron
    │   ├── ppp/                  pppd chap-secrets / filter / options
    │   ├── ssl/certs/            CA 证书 (ca-certificates.crt 200 KB)
    │   ├── firewall.user         MASQUERADE 兜底规则
    │   ├── firewall.fibocom       FM350 专用 iptables
    │   └── rc.local              开机挂载 tmpfs + ip_forward + ifconfig usb0 up
    │
    ├── lib/netifd/proto/*.sh     netifd 协议脚本（ppp/dhcpv6/464xlat/gre...）
    │
    ├── usr/lib/lua/luci/         LuCI Lua 框架（312 个文件）
    │   ├── dispatcher.lua
    │   ├── controller/
    │   ├── model/
    │   ├── view/cbi/*.htm
    │   └── template/
    │
    └── www/                      LuCI 前端静态资源（131 文件, 2.4 MB）
        ├── index.html            meta refresh → /cgi-bin/luci/
        ├── cgi-bin/luci          uhttpd Lua CGI dispatcher
        └── luci-static/
            ├── bootstrap/
            │   ├── cascade.css   LuCI 主题样式 (34 KB)
            │   ├── mobile.css
            │   └── favicon.png
            └── resources/
                ├── jquery-3.5.1.min.js
                ├── luci.js · cbi.js · form.js · rpc.js · uci.js
                ├── chartist.min.js / .css
                ├── protocol/*.js  (16 协议)
                ├── view/network/* · view/status/* · view/system/*
                └── tools/widgets.js
```

**统计：503 文件 / ~7.9 MB（其中前端 131 文件 / 2.4 MB）**

---

## 六、关键配置（FM350 专用适配）

### /etc/config/network
```
config interface 'lan'
    option ifname 'usb0'
    option proto 'static'
    option ipaddr '192.168.45.1'
    option netmask '255.255.255.0'

config interface 'wan'
    option ifname 'ppp0'
    option proto 'dhcp'
```

### /etc/config/firewall（简化版）
```
config zone
    option name 'lan'
    option network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'wan'
    option network 'wan'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'MASQ'
```

### /etc/rc.local（开机兜底）
```
mount -t tmpfs tmpfs /tmp
echo 1 > /proc/sys/net/ipv4/ip_forward
ifconfig usb0 up
exit 0
```

---

## 七、架构图（补齐后）

```
USB Host (PC/Mac/Linux)
  │
  └── usb0 ← FM350 RNDIS/NCM/ECM 网卡, 192.168.45.1
       │
       ├── uhttpd (:80) ──── LuCI Web UI
       │        │
       │        └── /cgi-bin/luci ── Lua ── rpcd ── UCI ── /etc/config/*
       │
       ├── dropbear (:22) ── SSH root@192.168.45.1
       │
       ├── dnsmasq (DHCP :67 + DNS :53)
       │        └── PC 自动获 192.168.45.x, 网关/DNS = 192.168.45.1
       │
       ├── fw3 ──── iptables MASQ (lan → wan NAT)
       │        └── /etc/firewall.user 兜底: ppp0/usb1/wwan0 三种 WAN 接口
       │
       ├── netifd ── ppp0 (拨号获得 IP)
       │        └── iptables MASQUERADE 让 PC 出网
       │
       └── odhcpd ── DHCPv6 + miniupnpd ── UPnP + sysntpd ── NTP
```

---

## 八、常见问题

### Q1：推完后访问 192.168.45.1 打不开
```bash
adb shell "ifconfig usb0 192.168.45.1 netmask 255.255.255.0 up"
adb shell "/etc/init.d/uhttpd start"
adb shell "/etc/init.d/dnsmasq start"
# PC 端: ipconfig /release && ipconfig /renew
```

### Q2：LuCI 登录密码？
默认 root 密码空。建议登录后立即改：**System → Administration → Router Password**

### Q3：fw3 启动失败 / iptables -L 报错
FM350 内核 4.19.205 已有 netfilter .ko，但需要手动加载：
```bash
adb shell "modprobe ip_tables && modprobe xt_nat && modprobe xt_conntrack && fw3 start"
```

### Q4：ppp0 没 IP（WAN 没拨号）
FM350 原生用 PCIe 数据连接（4dipcd/MTK 驱动），不是 PPP。补齐的 pppd 是**备用**。生产环境如果 MTK 数据连接正常，LAN MASQ 走 wwan0 或 ppp0 均可——`/etc/firewall.user` 已兜底。

### Q5：恢复出厂 / 卸载
```bash
一键补齐.bat uninstall        # 或 bash deploy.sh uninstall
adb reboot                     # 重启回原生状态
```

### Q6：bundle 跨平台安全吗？
**是**。补齐包全部来自 FG360 recovery squashfs（MediaTek MT6890 / OpenWrt / aarch64 / musl libc），和 FM350（MediaTek MT6880 / aarch64 / musl libc / kernel 4.19.190 vs 4.19.205）ABI 100% 兼容。二进制直接复用，无需重编译。

---

## 九、版本 / 来源

| 项 | 值 |
|---|---|
| bundle 版本 | 2026-11-26 |
| 提取来源 | `c:/Users/ZH/Desktop/临时文件/160/fg360/recovery_extracted/` (rootfs squashfs) |
| 适配目标 | Fibocom FM350（MT6880 / aarch64 musl / kernel 4.19.205） |
| 补齐内容 | LuCI 全套 + fw3 + dnsmasq + dropbear + uhttpd + rpcd + pppd + odhcpd + miniupnpd + ethtool + bridge + tc + conntrack + openssl + SSH keygen + CA 证书 |
| 前端静态资源 | `recovery_extracted/www/` (bootstrap 主题, jquery 3.5.1, luci.js) |

---

## 十、中文界面 (zh-cn i18n)

补齐 bundle 自带完整 LuCI 中文翻译，**无需额外安装 luci-i18n-zh-cn 包**。

### 翻译文件位置
```
/usr/lib/lua/luci/i18n/*.zh-cn.lmo    ← 53 个 .lmo, 213.7 KB
```

### 覆盖模块 (53 个 .lmo 文件)

| 模块 | 文件 | 大小 | 覆盖页面 |
|---|---|---|---|
| base | base.zh-cn.lmo | 155 KB | **LuCI 核心 13749 条** (通用表单/按钮/标签) |
| firewall | firewall.zh-cn.lmo | 19 KB | 防火墙规则/区域/NAT/转发 |
| ddns | ddns.zh-cn.lmo | 11.7 KB | DDNS 动态 DNS 客户端 |
| openvpn | openvpn.zh-cn.lmo | 11.7 KB | OpenVPN VPN 配置 |
| uhttpd | uhttpd.zh-cn.lmo | 4.3 KB | uHTTPd Web 服务器 |
| admin_network | admin_network.zh-cn.lmo | 2.6 KB | 网络接口/DHCP/路由 |
| advanced_logger | advanced_logger.zh-cn.lmo | 1.7 KB | 高级日志 |
| qos | qos.zh-cn.lmo | 0.6 KB | QoS 流量控制 |
| ntpc | ntpc.zh-cn.lmo | 0.5 KB | NTP 时间同步 |
| vnstat | vnstat.zh-cn.lmo | 0.4 KB | VnStat 流量监控 |
| 其他 43 个 | statistics-*/admin_*/... | ~10 KB | 统计插件/MTK WiFi/IPsec/HWNAT/Diag 等 |

### LuCI .lmo 格式 (自定义二进制)
```
头部: b"nplurals=1; plural=0;\x00"
内容: key1\x00value1\x00key2\x00value2\x00...
```
不是标准 gettext MO，是 LuCI 自己的格式。本 bundle 用 `gen_lmo.py` 自动生成。

### 设置中文 (FM350 部署后)
```bash
# 浏览器访问 LuCI → System → Language → 选 "Chinese (Simplified)" → Save & Apply
# 或 uci 命令:
adb shell "uci set luci.main.lang=zh_cn && uci commit luci"
# 刷新浏览器 (Ctrl+Shift+R)
```

### 重新生成 .lmo (开发)
```bash
python gen_lmo.py ./rootfs
# 会扫描所有 Lua/HTM 中 translate()/_() 调用
# 用内置 2500+ 条英中字典翻译
# 缺失的 key LuCI 自动 fallback 显示英文
```

---

## 十一、日志路径

补齐服务 log 位置：
```
/var/log/messages           # 系统 log (procd 启动输出)
/var/log/dnsmasq.log        # dnsmasq
/var/log/fw3.log            # fw3
/var/log/dropbear.log       # SSH
/var/log/uhttpd.log         # Web
logread | grep -i dnsmasq   # procd logread
```

进程/端口快速检查：
```bash
adb shell "ps | grep -E 'dnsmasq|dropbear|uhttpd|rpcd|fw3|odhcpd'"
adb shell "netstat -tlnp 2>/dev/null || ss -tlnp"
adb shell "ifconfig -a"
adb shell "iptables -t nat -L POSTROUTING -n"
```
