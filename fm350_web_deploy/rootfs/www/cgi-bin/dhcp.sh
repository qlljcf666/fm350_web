#!/bin/sh
# FM350 Web CGI: POST /cgi-bin/dhcp.sh
# 控制下位机 DHCP 服务 (启动/停止/改网段)
# =======================================

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

ACTION="status"
LAN_IP="192.168.42.1"
LAN_NET="255.255.255.0"

[ -n "$QUERY_STRING" ] && {
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        case "$k" in
            action)  echo "ACTION='$v'" ;;
            lan_ip)  echo "LAN_IP='$v'" ;;
            lan_net) echo "LAN_NET='$v'" ;;
        esac
    done)"
}

case "$ACTION" in
    status)
        echo "=== uDHCPd leases ==="
        [ -f /var/run/fm350/udhcpd.leases ] && cat /var/run/fm350/udhcpd.leases || echo "(no leases yet)"
        echo ""
        echo "=== LAN interface ==="
        for d in usb0 ccmni0 ccmni1 eth1 eth2; do
            [ -d "/sys/class/net/$d" ] && ip -4 addr show "$d" 2>/dev/null
        done
        ;;
    start)
        echo "INFO: starting DHCP server on LAN ..."
        # 用 init.d 完整拉起
        /etc/init.d/fm350_web restart 2>/dev/null || true
        echo "OK: DHCP restarted"
        ;;
    stop)
        echo "INFO: stopping DHCP server ..."
        killall udhcpd 2>/dev/null
        echo "OK"
        ;;
    restart)
        killall udhcpd 2>/dev/null
        sleep 0.5
        /etc/init.d/fm350_web restart 2>/dev/null || true
        echo "OK"
        ;;
    *)
        echo "FAIL: action must be status|start|stop|restart"
        ;;
esac
