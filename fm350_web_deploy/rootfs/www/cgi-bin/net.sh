#!/bin/sh
# FM350 Web CGI: POST /cgi-bin/net.sh
# 网络工具: ping, traceroute, iptables 状态, 路由表
# ===================================================

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

CMD=""
TARGET=""

[ -n "$QUERY_STRING" ] && {
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        case "$k" in
            cmd)    echo "CMD='$v'" ;;
            target) echo "TARGET='$v'" ;;
        esac
    done)"
}

case "$CMD" in
    ping)
        [ -z "$TARGET" ] && TARGET="223.5.5.5"
        echo "=== ping $TARGET (5x) ==="
        ping -c 5 -W 2 "$TARGET" 2>&1
        ;;
    route)
        echo "=== ip route ==="
        ip route
        echo ""
        echo "=== ip -6 route ==="
        ip -6 route
        ;;
    ifconfig)
        echo "=== interfaces ==="
        ip link show
        echo ""
        echo "=== addresses ==="
        ip addr show
        ;;
    iptables)
        echo "=== iptables -t nat -nvL POSTROUTING ==="
        iptables -t nat -nvL POSTROUTING 2>&1
        echo ""
        echo "=== iptables -nvL FORWARD ==="
        iptables -nvL FORWARD 2>&1
        ;;
    log)
        echo "=== dial log (last 50 lines) ==="
        tail -n 50 /var/log/fm350_dial.log 2>/dev/null || echo "(no log)"
        ;;
    info)
        echo "=== system info ==="
        echo "uptime: $(uptime)"
        echo "model:  $(cat /etc/device_info 2>/dev/null)"
        echo "arch:   $(uname -m)"
        echo "kernel: $(uname -r)"
        echo ""
        echo "=== openwrt_release ==="
        cat /etc/openwrt_release 2>/dev/null
        ;;
    reboot)
        echo "OK: rebooting in 3s ..."
        (sleep 3; reboot) &
        ;;
    *)
        echo "usage: cmd=ping[&target=HOST] | route | ifconfig | iptables | log | info | reboot"
        ;;
esac
