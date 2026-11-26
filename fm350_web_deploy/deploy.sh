#!/bin/bash
# ================================================================
# FM350 Web Console · ADB 一键部署 / 卸载 v2 (新增 SMS/锁网/定时重启)
# ================================================================
#   ./deploy.sh install    部署到设备 (需要 root)
#   ./deploy.sh start      部署 + 启动
#   ./deploy.sh stop       停止
#   ./deploy.sh restart    重启
#   ./deploy.sh status     查看运行状态
#   ./deploy.sh enable     挂载开机自启到 /etc/rc.local
#   ./deploy.sh disable    移除自启
#   ./deploy.sh push       仅推送文件
#   ./deploy.sh uninstall  全部卸载
# ================================================================

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOTFS="$HERE/rootfs"
REMOTE_ROOT="/tmp/fm350_web"

R='\033[31m'; G='\033[32m'; Y='\033[33m'; C='\033[36m'; N='\033[0m'
info() { echo -e "${G}[+]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
err()  { echo -e "${R}[x]${N} $*"; }
step() { echo -e "${C}>>>${N} $*"; }

command -v adb >/dev/null 2>&1 || { err "adb not in PATH"; exit 1; }

DEVICES=$(adb devices | grep -w device | head -1 | awk '{print $1}')
[ -z "$DEVICES" ] && { err "no adb device. adb connect <ip>:5555 或插 USB"; exit 1; }
info "target: $DEVICES"
adb root 2>/dev/null || true

do_push() {
    step "creating remote dirs ..."
    adb shell "mkdir -p $REMOTE_ROOT/{www/cgi-bin,etc/init.d,etc/gcom,usr/bin,lib/netifd/proto}"
    step "pushing files ..."
    adb push "$ROOTFS/www/"           "$REMOTE_ROOT/www/"           >/dev/null
    adb push "$ROOTFS/etc/init.d/"    "$REMOTE_ROOT/etc/init.d/"    >/dev/null
    adb push "$ROOTFS/etc/gcom/"      "$REMOTE_ROOT/etc/gcom/"      >/dev/null
    adb push "$ROOTFS/usr/bin/"       "$REMOTE_ROOT/usr/bin/"       >/dev/null
    adb push "$ROOTFS/lib/netifd/"    "$REMOTE_ROOT/lib/netifd/"    >/dev/null
    info "files pushed"
}

do_install() {
    do_push
    step "copying to system paths ..."
    adb shell "cp -r $REMOTE_ROOT/www/*        /www/ 2>/dev/null || mkdir -p /www && cp -r $REMOTE_ROOT/www/* /www/"
    adb shell "cp  $REMOTE_ROOT/etc/init.d/*   /etc/init.d/"
    adb shell "cp -r $REMOTE_ROOT/etc/gcom/*   /etc/gcom/ 2>/dev/null || { mkdir -p /etc/gcom && cp -r $REMOTE_ROOT/etc/gcom/* /etc/gcom/; }"
    adb shell "cp  $REMOTE_ROOT/usr/bin/*      /usr/bin/"
    adb shell "cp  $REMOTE_ROOT/lib/netifd/proto/*  /lib/netifd/proto/"

    step "setting permissions ..."
    adb shell "chmod +x /etc/init.d/fm350_web"
    adb shell "chmod +x /usr/bin/*.sh"
    adb shell "chmod +x /www/cgi-bin/*.sh"
    adb shell "chmod +x /lib/netifd/proto/fm350.sh"

    # gcom / crond 可能缺
    local plugin_gcom="$HERE/../fm350_plugin_extract/ipk_unpacked/fm350-modem/unpacked/data/usr/sbin/gcom"
    if [ -f "$plugin_gcom" ]; then
        step "pushing gcom binary ..."
        adb push "$plugin_gcom" /usr/sbin/gcom 2>/dev/null || true
        adb shell "chmod +x /usr/sbin/gcom"
    fi

    info "install done. run '$0 start'"
}

do_start() {
    step "starting fm350_web ..."
    adb shell "/etc/init.d/fm350_web stop" 2>/dev/null || true
    sleep 1
    adb shell "/etc/init.d/fm350_web start"
    sleep 3
    do_status
    info "Web console: http://<FM350-IP>/"
    info "  hint: find IP via 'adb shell ifconfig usb0'"
}

do_stop() { adb shell "/etc/init.d/fm350_web stop" 2>/dev/null || true; info "stopped"; }
do_restart() { do_stop; do_start; }

do_enable() {
    step "hooking rc.local ..."
    adb shell "cp /etc/rc.local /etc/rc.local.bak 2>/dev/null || touch /etc/rc.local"
    adb shell "
if ! grep -q 'FM350 WEB CONSOLE AUTO START' /etc/rc.local 2>/dev/null; then
    sed -i '/exit 0/i\\
# === FM350 WEB CONSOLE AUTO START ===\\
( sleep 10 \\&\\& /etc/init.d/fm350_web start ) \\&\\
# === FM350 WEB END ===' /etc/rc.local
fi
chmod +x /etc/rc.local
echo 'hooked'
"
    info "开机自启已挂载 (10s 后启动全部服务)"
}

do_disable() {
    step "removing hook ..."
    adb shell "sed -i '/FM350 WEB CONSOLE AUTO START/,/FM350 WEB END/d' /etc/rc.local"
    info "removed"
}

do_uninstall() {
    step "stopping ..."
    do_stop
    step "removing files ..."
    adb shell "
rm -f  /www/index.html /www/style.css /www/app.js
rm -f  /www/cgi-bin/*.sh
rm -f  /etc/init.d/fm350_web
rm -f  /usr/bin/at_helper.sh
rm -f  /usr/bin/fm350_dial.sh
rm -f  /usr/bin/fm350_sms.sh
rm -f  /usr/bin/fm350_lock.sh
rm -f  /usr/bin/fm350_reboot.sh
rm -rf /etc/gcom
rm -f  /lib/netifd/proto/fm350.sh
rm -rf /var/run/fm350
rm -rf $REMOTE_ROOT
sed -i '/FM350 WEB CONSOLE AUTO START/,/FM350 WEB END/d' /etc/rc.local 2>/dev/null
"
    info "uninstalled"
}

do_status() {
    step "runtime state:"
    adb shell "
echo '=== procd service list ==='; ls /etc/init.d/*fm350* 2>/dev/null || true
echo '=== processes ==='; ps | grep -E 'httpd|udhcpd|fm350|crond' | grep -v grep || echo '(none)'
echo '=== interfaces ==='; ip -4 addr show 2>/dev/null | grep -E 'inet ' || ifconfig 2>/dev/null | grep -E 'inet '
echo '=== default route ==='; ip route | grep default || echo '(none)'
echo '=== dial state ==='; cat /var/run/fm350/dial_state 2>/dev/null || echo '(no state)'
echo '=== last ping ==='; cat /var/run/fm350/last_ping_ok 2>/dev/null || echo '(none)'
echo '=== crontab ==='; grep FM350 /etc/crontabs/root 2>/dev/null || echo '(none)'
echo '=== port 80 ==='; netstat -tlnp 2>/dev/null | grep ':80 ' || echo '(not listening)'
echo '=== iptables nat ==='; iptables -t nat -nvL POSTROUTING 2>/dev/null | head -5 || echo '(need iptables binary)'
"
}

ACTION="${1:-status}"
case "$ACTION" in
    install)   do_install ;;
    push)      do_push ;;
    start)     do_install; do_start ;;
    stop)      do_stop ;;
    restart)   do_restart ;;
    enable)    do_enable ;;
    disable)   do_disable ;;
    status)    do_status ;;
    uninstall) do_uninstall ;;
    *)
        echo "usage: $0 {install|push|start|stop|restart|enable|disable|status|uninstall}"
        exit 1 ;;
esac
