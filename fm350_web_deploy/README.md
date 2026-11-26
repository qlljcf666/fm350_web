# FM350 Web Console v2 — 完整功能 Web 后台

> 部署方式: ADB push 到 FM350 (MT6880 / OpenWrt 19.07 / aarch64 musl)
> 前端: 纯 HTML + CSS + JS (无构建, 直接 busybox httpd 托管)
> 后端: Shell CGI (busybox ash + FM350 自带的 fibocom_cmd 或 microcom/gcom)

---

## 🆕 v2 新增 (对比 v1)

| 功能 | 模块 | 关键 AT 命令 |
|---|---|---|
| ✉️ 短信收发 | `fm350_sms.sh` + `/cgi-bin/sms.sh` | `AT+CMGF=1`, `AT+CMGS`, `AT+CMGL`, `AT+CNMI` |
| 🔒 锁网 | `fm350_lock.sh` + `/cgi-bin/lock.sh` | `AT+COPS=1,2,"46001"`, `AT%LOCK` |
| 🔒 锁频段 | 同上 | `AT%CBAND=1,78` |
| 🔒 锁频点 (ARFCN) | 同上 | `AT%FREQLOCK=1,632688` |
| ⚡ 断网自动重拨 (增强版) | 重写的 `fm350_dial.sh` | 真实 ping 健康检查 + 退避重试 + 连续失败 reboot |
| ⏰ 定时重启 | `fm350_reboot.sh` + crond | 标准 cron |

### 修复的问题
- SMS 发送流程正确实现 `AT+CMGS=<num>` → 等 `>` prompt → 发内容 → `CTRL+Z`
- 断网重拨加入 **"接口 IP 还在但 ping 不通"** 的中间态修复（刷 NAT + 等 5 秒再 ping），不是一断就硬重拨
- 连续失败 **指数退避** (10s → 20s → ... → 120s)
- 连续失败超阈值 (默认 15) → **自动 reboot**，每 5 次失败发一次 `AT%REBOOT=1` 做 modem 软重启
- 引入统一 `at_helper.sh`，AT 工具/端口探测/发送都走一套

---

## 📦 目录结构

```
fm350_web_deploy/
├── README.md                    ← 本文档
├── deploy.sh                    ← ADB 一键部署
└── rootfs/                      ← 推到 FM350 的文件树
    ├── etc/
    │   ├── init.d/fm350_web     ← 统一启动 (Web+DHCP+NAT+Dial+SMS+Cron)
    │   └── gcom/*.gcom          ← FM350 官方 AT 拨号脚本 (4 个)
    ├── lib/netifd/proto/fm350.sh ← OpenWrt netifd 协议层
    ├── usr/bin/
    │   ├── at_helper.sh          ← AT 通用辅助库 (工具/端口/发送/解析)
    │   ├── fm350_dial.sh         ← 自动拨号 + 断网重拨守护
    │   ├── fm350_sms.sh          ← 短信收发守护 + 工具
    │   ├── fm350_lock.sh         ← 锁网锁频锁频段
    │   └── fm350_reboot.sh       ← 定时重启
    └── www/
        ├── index.html + style.css + app.js
        └── cgi-bin/
            ├── status.sh          ← GET JSON 状态
            ├── dial.sh            ← POST 拨号/重拨/断开
            ├── mode.sh            ← POST AT%MODE=40/41/42
            ├── dhcp.sh            ← POST DHCP 启停/租约表
            ├── sms.sh             ← POST 短信收发
            ├── lock.sh            ← POST 锁网锁频
            ├── reboot.sh          ← POST 定时重启
            └── net.sh             ← POST 网络工具
```

---

## 🚀 快速部署

```bash
# 1. 确认 ADB 连上 FM350
adb devices

# 2. 一键安装 + 启动
bash deploy.sh start

# 3. 浏览器访问 (先 find IP)
adb shell ifconfig usb0        # 找到 usb0 的 IP, 通常是 192.168.42.x
# 然后 PC 浏览器访问那个 IP, 就是 Web 控制台

# 4. 开机自启
bash deploy.sh enable

# 其他
bash deploy.sh status          # 看运行状态
bash deploy.sh restart         # 重启服务
bash deploy.sh uninstall       # 全部卸载
```

### 首次启动操作指引

1. **USB 模式用户**: 先在 Web 里点 `AT%MODE=40 RNDIS`（最通用），如果已经是 RNDIS 就跳过
2. **拨号**: 点 `▶ 自动拨号` → APN 填运营商标识（`CMCC` / `CTNET` / `CUINTERNET` / 直接留空 `internet`）
3. **下位机 PC**: USB 数据线接 FM350，PC 会被分配 `192.168.42.2+`，网关 `192.168.42.1`
4. **锁网**: 进 "锁网锁频" Tab，快速预设按钮一键锁移动/联通/电信
5. **定时重启**: 进 "定时重启" Tab，预设 `每天 02:30` 是经典配置

---

## ⚠️ 必须注意的运行时依赖

| 能力 | FM350 有? | 必要 action |
|---|---|---|
| busybox httpd | ✅ 有 (applet) | 直接用 |
| busybox udhcpd | ✅ 有 | 直接用 |
| busybox crond | ✅ 有 | 直接用 |
| fibocom_cmd | ✅ **FM350 自带** | 首选 AT 工具 |
| gcom | ❌ 可能没有 | deploy.sh 会尝试从官方插件提取并 push；不行就退化到 fibocom_cmd / microcom |
| microcom | ❌ 不确定 | `opkg install microcom` 或直接用 fibocom_cmd |
| **iptables 二进制** | ❌ **rootfs 只有 .so, 没主程序** | ⚠️ **从 NR90 提取 `iptables` push 过去** (架构相同 aarch64 musl): `adb push ./iptables_binary /usr/sbin/iptables && adb shell chmod +x /usr/sbin/iptables` |

### 缺 iptables 会怎样？
- **NAT MASQUERADE 不生效**: PC 拿到 IP 但无法通过 FM350 上网
- **功能降级**: 其他功能（拨号、短信、锁频、定时重启）**不受影响**

---

## 🔧 FM350 相关 AT 命令速查

### 拨号
```
AT+CMEE=2                  # 详细错误
AT+CGPIAF=1,0,0,0
AT+CGDCONT=3,"IP","<APN>"
AT+CGACT=1,3               # 激活 PDP
AT+CGACT=0                 # 关闭所有 PDP
AT+CGPADDR=3               # 取 IP
AT+GTDNS=3                 # 取 DNS
```

### 模式切换 (USB)
```
AT%MODE=40                 # RNDIS (推荐)
AT%MODE=41                 # NCM
AT%MODE=42                 # ECM
AT%MODE?                   # 查询当前
```

### 锁网
```
AT+COPS?                   # 查询当前 PLMN
AT+COPS=0                  # 自动选网
AT+COPS=1,2,"46001"        # 锁联通 (46000=移动 46001=联通 46003=电信 46008=广电)
AT+COPS=?                  # 扫描可用 PLMN (慢)
```

### 锁频段
```
AT%CBAND?                  # 查询
AT%CBAND=1,78              # 锁 n78
AT%CBAND=1,41,78           # 锁 n41+n78
AT%CBAND=0                 # 全部 (解锁)
```
**FM350 NR 频段编号**: n1=1, n3=3, n28=28, n41=41, n77=77, n78=78, n79=79

### 锁频点 (ARFCN)
```
AT%FREQLOCK?               # 查询
AT%FREQLOCK=1,632688       # FR1 n78 常见点
AT%FREQLOCK=0              # 解锁
```
**常用 ARFCN (FR1 Sub-6)**:
| 频段 | ARFCN 范围 | 典型值 |
|---|---|---|
| n78 (5G 主力) | 620000 ~ 680000 | 632688 / 640864 / 661632 |
| n41 | 499200 ~ 640000 | 504990 / 529920 / 551680 |
| n28 | 145408 ~ 158944 | 145952 / 148480 |

### 短信
```
AT+CMGF=1                  # 文本模式 (必须!)
AT+CMGS="13800138000"      # 等 > prompt, 发文本, CTRL+Z 发送
AT+CMGL="ALL"              # 列出全部
AT+CMGL="REC UNREAD"       # 只列未读
AT+CMGR=<index>            # 读一条
AT+CMGD=<index>            # 删一条
AT+CMGD=0,4                # 清空全部
AT+CNMI=2,1,0,0,0          # 新消息通知 (UCI)
```

### 信号 / 状态
```
AT+CSQ                     # 信号 0-31
AT%HCSQ?                   # 网络类型 + 频段 + 信号强度
AT^HCSQ?                   # 华为兼容 HCSQ
AT+CIMI                    # IMSI
AT+CPIN?                   # SIM 状态
```

### 其他
```
AT%REBOOT=1                # FM350 私有: 软重启 modem
AT&F                       # 恢复出厂设置 (⚠ 慎用)
```

---

## 🧭 架构图

```
                    PC 浏览器 (192.168.42.x)
                           │
                     http://192.168.42.1/
                           │
                    ┌──────┴──────┐
                    │ busybox httpd  │  :80
                    │  /www/ + CGI   │
                    └──────┬──────┘
                           │ shell CGI
      ┌────────────────────┼────────────────────┬────────────────────┐
      │                    │                    │                    │
 fm350_dial.sh       fm350_sms.sh       fm350_lock.sh      fm350_reboot.sh
  (自动拨号守护)       (短信收发守护)      (锁网锁频)          (cron 定时重启)
      │                    │                    │                    │
      └───────┬────────────┴────────────┬───────┘                    │
              │         at_helper.sh      │                          │
              │    (AT 工具/端口/发送)     │                          │
              └────────────┬─────────────┘                          │
                           │ AT command                              │
                  fibocom_cmd / microcom / gcom                     │
                           │                                         │
                  /dev/ttyUSBx (AT port)                             │
                           │                                         │
                  ┌────────┴────────┐                                │
                  │  FM350 Modem     │ ← LTE/NR 数据连接              │
                  │  PCIe / USB RNDIS│                                │
                  └────────┬────────┘                                │
                           │                                         │
      ┌────────────────────┼────────────────────┐                   │
      │                    │                    │                   │
   ccmni0 (PCIe)      usb0 (RNDIS)         路由 + NAT               │
   ┌────────┐           ┌────────┐           ┌────────┐             │
   │ 拨号IP  │           │ 拨号IP  │           │iptables│             │
   └────────┘           └────────┘           └────────┘             │
                           │                                         │
                           ▼                                    crond (FM350)
                     互联网 223.5.5.5                              │
                                                              定时 reboot
```

---

## 🐛 常见问题

### Q1: 页面打开但功能全点不动 / 返回 JSON 错误
**A**: 检查 `/var/log/fm350_sms.log` 和 CGI 脚本执行权限：
```bash
adb shell "chmod +x /www/cgi-bin/*.sh; ls -la /www/cgi-bin/"
```

### Q2: 点 "自动拨号" 没反应 / 返回 NO_AT_TOOL
**A**: FM350 需要一个 AT 工具（fibocom_cmd / microcom / gcom 三选一）。
```bash
adb shell "ls /usr/bin/fibocom_cmd /bin/microcom /usr/sbin/gcom 2>&1"
# 如果 fibocom_cmd 有 → 自动用它, 不用装别的
# 如果 microcom 有 → 自动用
# 如果都没有: opkg install microcom
```

### Q3: PC 连上拿不到 IP
**A**: 检查 udhcpd 和网关 IP：
```bash
adb shell "ifconfig usb0; cat /etc/udhcpd.conf; ps | grep udhcpd"
# 应该看到 usb0 = 192.168.42.1, udhcpd 进程在
```

### Q4: PC 拿到 IP 但无法上网
**A**: 缺 iptables 二进制 (见上方"运行时依赖"表格)，push 过去就行。
或者直接先验证 `ping 223.5.5.5 -I usb0` 在 FM350 上通不通。

### Q5: AT%MODE 后 USB 消失
**A**: 正常现象，FM350 切模式会重枚举 USB。等 5-10 秒后重新 adb root，Web 自动刷新状态。

### Q6: 连续重拨后设备 reboot 了
**A**: 这是设计行为 —— 默认连续 15 次重拨失败就 reboot 自救。
改阈值: 编辑 `/usr/bin/fm350_dial.sh` 的 `MAX_FAIL_BEFORE_REBOOT` 变量。

---

## 📚 参考文档

- **FM350 AT Commands v2.2**: `FM350系列资料/Zh/3-软件/通用/Fibocom FM350 AT Commands v2.2.pdf`
- **FM350 USB 拨号插件**: `FM350系列资料/Zh/3-软件/Linux&Android/FM350-GL OpenWRT USB拨号插件.zip`
- **FM350 PCIe MBIM 指南**: `FM350系列资料/Zh/3-软件/Linux&Android/Fibocom_FM350_PCIE模式下MBIM拨号指南_Linux_V1.0.0.pdf`

---

## 📝 日志路径

| 日志 | 位置 |
|---|---|
| 自动拨号 | `/var/log/fm350_dial.log` |
| 短信守护 | `/var/log/fm350_sms.log` |
| 定时重启 | `/var/log/fm350_reboot.log` |
| 最近拨号状态 | `/var/run/fm350/dial_state` |
| 最后一次 ping 成功标记 | `/var/run/fm350/last_ping_ok` |
| 连续失败计数 | `/var/run/fm350/lock_fail_count` |

查看: `adb shell tail -f /var/log/fm350_dial.log`
