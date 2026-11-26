#!/bin/bash
# ============================================================
# FM350 一键补齐 ADB 部署脚本
# ============================================================
# 用法:
#   bash deploy.sh install    # 安装全部 (push + chmod + enable services)
#   bash deploy.sh push       # 只推送文件不启动
#   bash deploy.sh start      # 启动所有补齐服务
#   bash deploy.sh stop       # 停止所有补齐服务
#   bash deploy.sh restart    # 重启所有补齐服务
#   bash deploy.sh status     # 检查服务状态
#   bash deploy.sh enable     # 开机自启
#   bash deploy.sh disable    # 关闭开机自启
#   bash deploy.sh uninstall  # 卸载 (还原 network + 停服务)
# ============================================================

set -e

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="$THIS_DIR/rootfs"
TMP_ON_DEV="/tmp/fm350_patch"

echo "============================================================"
echo "  FM350 一键补齐 — ADB 部署工具"
echo "============================================================"
echo "包路径: $THIS_DIR"
echo ""

# ---- 检查 adb ----
if ! command -v adb >/dev/null 2>&1; then
    echo "错误: 未找到 adb 命令"
    exit 1
fi

# ---- 检查设备 ----
check_device() {
    local devs
    devs="$(adb devices | grep -v List | grep -v '^$' | head -1)"
    if [ -z "$devs" ]; then
        echo "错误: 没有检测到 USB 设备 (adb devices 空)"
        exit 1
    fi
    echo "✓ ADB 设备: $devs"
}

# ---- ADB root ----
ensure_root() {
    adb root 2>/dev/null || true
    sleep 1
    adb wait-for-device
    adb remount 2>/dev/null || true
}

# ============================================================
# PUSH 阶段
# ============================================================
do_push() {
    echo ""
    echo "--- [1/4] 推送到设备临时目录 $TMP_ON_DEV ---"
    adb shell "rm -rf $TMP_ON_DEV && mkdir -p $TMP_ON_DEV"

    # 推送所有文件 (用 find + cp 保持权限)
    cd "$ROOTFS"

    # 推送目录结构
    find . -type d | while read d; do
        [ "$d" = "." ] && continue
        adb shell "mkdir -p $TMP_ON_DEV/$d"
    done

    # 推送文件
    local count=0
    find . -type f | while read f; do
        local target="$TMP_ON_DEV/$f"
        adb push "$f" "$target" 2>/dev/null || {
            echo "  ! 推送失败: $f"
        }
        count=$((count+1))
        # 每 50 个打印一次
        if [ $((count % 50)) -eq 0 ]; then
            echo "  ... 已推送 $count 个文件"
        fi
    done
    echo "✓ 推送完成"

    echo ""
    echo "--- [2/4] 复制到系统路径 ---"
    # 二进制
    adb shell "cp -f $TMP_ON_DEV/sbin/* /sbin/ 2>/dev/null; cp -f $TMP_ON_DEV/usr/sbin/* /usr/sbin/ 2>/dev/null; cp -f $TMP_ON_DEV/usr/bin/* /usr/bin/ 2>/dev/null; echo ' binaries OK'"
    
    # 共享库
    adb shell "cp -f $TMP_ON_DEV/lib/*.so /lib/ 2>/dev/null; cp -f $TMP_ON_DEV/lib/*.so.* /lib/ 2>/dev/null; echo ' libs OK'"
    
    # Init.d
    adb shell "cp -f $TMP_ON_DEV/etc/init.d/* /etc/init.d/ 2>/dev/null; echo ' init.d OK'"
    
    # Config
    adb shell "cp -f $TMP_ON_DEV/etc/config/* /etc/config/ 2>/dev/null; echo ' config OK'"
    
    # Firewall
    adb shell "cp -f $TMP_ON_DEV/etc/firewall.user /etc/firewall.user 2>/dev/null; cp -f $TMP_ON_DEV/etc/firewall.fibocom /etc/firewall.fibocom 2>/dev/null; echo ' firewall OK'"
    
    # SSL
    adb shell "rm -rf /etc/ssl && cp -rf $TMP_ON_DEV/etc/ssl /etc/ssl 2>/dev/null; echo ' ssl OK'"
    
    # PPP
    adb shell "cp -f $TMP_ON_DEV/etc/ppp/* /etc/ppp/ 2>/dev/null; echo ' ppp OK'"
    
    # rc.local (追加到末尾, 保留原有)
    adb shell "cat >> /etc/rc.local < $TMP_ON_DEV/etc/rc.local 2>/dev/null || cp -f $TMP_ON_DEV/etc/rc.local /etc/rc.local; chmod +x /etc/rc.local; echo ' rc.local OK'"
    
    # LuCI
    adb shell "cp -rf $TMP_ON_DEV/usr/lib/lua/luci /usr/lib/lua/luci 2>/dev/null; echo ' luci OK'"
    
    # rpcd plugins
    adb shell "cp -rf $TMP_ON_DEV/usr/libexec/rpcd /usr/libexec/rpcd 2>/dev/null; echo ' rpcd plugins OK'"
    
    # netifd proto
    adb shell "cp -f $TMP_ON_DEV/lib/netifd/proto/*.sh /lib/netifd/proto/ 2>/dev/null; echo ' netifd proto OK'"
    
    # 设置可执行权限
    echo ""
    echo "--- [3/4] chmod +x ---"
    adb shell "
        chmod +x /sbin/fw3 /sbin/rpcd 2>/dev/null
        chmod +x /usr/sbin/dnsmasq /usr/sbin/dropbear /usr/sbin/pppd 2>/dev/null
        chmod +x /usr/sbin/odhcpd /usr/sbin/odhcp6c /usr/sbin/miniupnpd 2>/dev/null
        chmod +x /usr/sbin/ntpclient /usr/sbin/sshd /usr/sbin/uhttpd 2>/dev/null
        chmod +x /usr/sbin/ebtables /usr/sbin/tc /usr/sbin/conntrack 2>/dev/null
        chmod +x /usr/sbin/bridge /usr/sbin/ethtool 2>/dev/null
        for s in /etc/init.d/dnsmasq /etc/init.d/dropbear /etc/init.d/firewall \
                  /etc/init.d/odhcpd /etc/init.d/rpcd /etc/init.d/uhttpd \
                  /etc/init.d/sysntpd /etc/init.d/miniupnpd /etc/init.d/network; do
            [ -f \$s ] && chmod +x \$s
        done
        echo ' chmod OK'
    "
    
    # 清理
    echo ""
    echo "--- [4/4] 清理临时文件 ---"
    adb shell "rm -rf $TMP_ON_DEV"
    echo "✓ 推送+安装完成"
}

# ============================================================
# START 阶段
# ============================================================
do_start() {
    echo ""
    echo "--- 启动补齐服务 ---"
    
    # 先加载 netfilter 模块
    adb shell "
        for m in ip_tables ip6_tables iptable_filter ip6table_filter nf_conntrack xt_conntrack xt_nat xt_TCPMSS; do
            modprobe \$m 2>/dev/null
        done
        echo ' modules loaded'
    "
    
    # network (netifd)
    adb shell "/etc/init.d/network enable 2>/dev/null; /etc/init.d/network start 2>/dev/null && echo '✓ network started' || echo '✗ network failed'"
    
    # firewall (fw3)
    adb shell "fw3 start 2>/dev/null && echo '✓ firewall started' || echo '✗ firewall (fw3 not found? try iptables fallback)'"
    
    # dnsmasq
    adb shell "/etc/init.d/dnsmasq enable 2>/dev/null; /etc/init.d/dnsmasq start 2>/dev/null && echo '✓ dnsmasq started' || echo '✗ dnsmasq failed'"
    
    # dropbear
    adb shell "/etc/init.d/dropbear enable 2>/dev/null; /etc/init.d/dropbear start 2>/dev/null && echo '✓ dropbear SSH started on port 22' || echo '✗ dropbear failed'"
    
    # uhttpd + rpcd (LuCI)
    adb shell "/etc/init.d/rpcd enable 2>/dev/null; /etc/init.d/rpcd start 2>/dev/null && echo '✓ rpcd started' || echo '✗ rpcd failed'"
    adb shell "/etc/init.d/uhttpd enable 2>/dev/null; /etc/init.d/uhttpd start 2>/dev/null && echo '✓ uhttpd (LuCI) on :80 started' || echo '✗ uhttpd failed'"
    
    # ntp
    adb shell "/etc/init.d/sysntpd enable 2>/dev/null; /etc/init.d/sysntpd start 2>/dev/null && echo '✓ sysntpd started' || true"
    
    # odhcpd (DHCPv6, 可选)
    adb shell "/etc/init.d/odhcpd enable 2>/dev/null; /etc/init.d/odhcpd start 2>/dev/null || true"
    
    # 打印状态
    echo ""
    echo "--- 服务状态 ---"
    adb shell "
        echo '进程:'
        ps | grep -E 'dnsmasq|dropbear|uhttpd|rpcd|fw3|odhcpd' | grep -v grep
        echo ''
        echo 'iptables nat rules (前 5):'
        iptables -t nat -L POSTROUTING -n 2>/dev/null | head -10 || echo '  (无 iptables)'
        echo ''
        echo '网络接口:'
        ifconfig usb0 2>/dev/null | head -3 || echo '  usb0 未 up'
    "
    
    echo ""
    echo "============================================================"
    echo " 补齐完成!"
    echo "  访问 LuCI Web: http://192.168.45.1/"
    echo "  SSH: ssh root@192.168.45.1"
    echo "============================================================"
}

do_stop() {
    echo "停止补齐服务..."
    adb shell "
        /etc/init.d/dnsmasq stop 2>/dev/null
        /etc/init.d/dropbear stop 2>/dev/null
        /etc/init.d/uhttpd stop 2>/dev/null
        /etc/init.d/rpcd stop 2>/dev/null
        /etc/init.d/odhcpd stop 2>/dev/null
        fw3 flush 2>/dev/null
        echo 'done'
    "
}

do_status() {
    echo "--- 服务状态检查 ---"
    adb shell "
        echo '=== 进程 ==='
        for p in netifd dnsmasq dropbear uhttpd rpcd fw3 odhcpd; do
            if pidof \$p >/dev/null 2>&1; then
                echo -e '  ✓ '\$p '(PID '\$(pidof \$p)')'
            else
                echo -e '  ✗ '\$p '未运行'
            fi
        done
        echo ''
        echo '=== 二进制检查 ==='
        for f in fw3 dnsmasq dropbear uhttpd rpcd odhcpd pppd; do
            if [ -x /usr/sbin/\$f ] || [ -x /sbin/\$f ]; then
                echo '  ✓ '\$f '存在'
            else
                echo '  ✗ '\$f '缺失'
            fi
        done
        echo ''
        echo '=== 关键文件 ==='
        [ -f /etc/config/network ] && echo '  ✓ /etc/config/network' || echo '  ✗ /etc/config/network'
        [ -f /etc/config/firewall ] && echo '  ✓ /etc/config/firewall' || echo '  ✗ /etc/config/firewall'
        [ -f /etc/firewall.user ] && echo '  ✓ /etc/firewall.user' || echo '  ✗ /etc/firewall.user'
        [ -f /etc/rc.local ] && echo '  ✓ /etc/rc.local' || echo '  ✗ /etc/rc.local'
        echo ''
        echo '=== 网络接口 ==='
        ifconfig -a 2>/dev/null | grep -E '^[a-z]'
        echo ''
        echo '=== iptables NAT ==='
        iptables -t nat -L POSTROUTING -n 2>/dev/null | head -10 || echo '  (fw3 未运行)'
    "
}

do_enable() {
    echo "设置开机自启..."
    adb shell "
        /etc/init.d/dnsmasq enable 2>/dev/null
        /etc/init.d/dropbear enable 2>/dev/null
        /etc/init.d/firewall enable 2>/dev/null
        /etc/init.d/uhttpd enable 2>/dev/null
        /etc/init.d/rpcd enable 2>/dev/null
        /etc/init.d/odhcpd enable 2>/dev/null
        /etc/init.d/sysntpd enable 2>/dev/null
        /etc/init.d/miniupnpd enable 2>/dev/null
        echo '已全部 enable'
    "
}

do_disable() {
    echo "取消开机自启..."
    adb shell "
        /etc/init.d/dnsmasq disable 2>/dev/null
        /etc/init.d/dropbear disable 2>/dev/null
        /etc/init.d/firewall disable 2>/dev/null
        /etc/init.d/uhttpd disable 2>/dev/null
        /etc/init.d/rpcd disable 2>/dev/null
        /etc/init.d/odhcpd disable 2>/dev/null
        /etc/init.d/sysntpd disable 2>/dev/null
        echo '已全部 disable'
    "
}

do_uninstall() {
    echo "⚠  卸载补齐服务..."
    do_stop
    adb shell "
        /etc/init.d/dnsmasq disable 2>/dev/null
        /etc/init.d/dropbear disable 2>/dev/null
        /etc/init.d/firewall disable 2>/dev/null
        /etc/init.d/uhttpd disable 2>/dev/null
        /etc/init.d/rpcd disable 2>/dev/null
        /etc/init.d/odhcpd disable 2>/dev/null
        rm -f /etc/config/network /etc/config/dhcp /etc/config/firewall
        rm -f /etc/config/dropbear /etc/config/uhttpd /etc/config/rpcd
        rm -f /etc/firewall.user /etc/firewall.fibocom
        echo '已卸载, 重启恢复原生状态'
    "
}

# ============================================================
# 入口
# ============================================================
ACTION="${1:-install}"

case "$ACTION" in
    install)
        check_device
        ensure_root
        do_push
        do_start
        ;;
    push)
        check_device; ensure_root; do_push ;;
    start)
        check_device; do_start ;;
    stop)
        check_device; do_stop ;;
    restart)
        check_device; do_stop; do_start ;;
    status)
        check_device; do_status ;;
    enable)
        check_device; do_enable ;;
    disable)
        check_device; do_disable ;;
    uninstall)
        check_device; do_uninstall ;;
    *)
        echo "用法: $0 {install|push|start|stop|restart|status|enable|disable|uninstall}"
        exit 1
        ;;
esac
