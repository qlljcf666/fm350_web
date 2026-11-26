#!/bin/sh
# FM350 Web CGI: POST /cgi-bin/dial.sh
# 触发拨号 / 断线 / 重拨
# ====================================

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

ACTION="dial"
APN="${FM350_APN:-internet}"

[ -n "$QUERY_STRING" ] && {
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        case "$k" in
            action) echo "ACTION='$v'" ;;
            apn)    echo "APN='$v'" ;;
        esac
    done)"
}

case "$ACTION" in
    dial|up)
        export FM350_APN="$APN"
        echo "INFO: starting auto-dial, APN=$APN"
        # 确保守护进程在跑
        /etc/init.d/fm350_web enabled 2>/dev/null || {
            echo "WARN: fm350_web not enabled, starting once"
            /etc/init.d/fm350_web start
        } || true
        # 如果守护没跑，前台跑一次
        if ! pgrep -f fm350_dial.sh >/dev/null 2>&1; then
            nohup /usr/bin/fm350_dial.sh dial >> /var/log/fm350_dial.log 2>&1 &
            echo "OK: dial daemon launched"
        else
            echo "OK: dial daemon already running"
        fi
        ;;
    stop|down|disconnect)
        echo "INFO: disconnecting ..."
        # USB 模式: AT+CGACT=0
        tty=$(ls /dev/ttyUSB* 2>/dev/null | head -1)
        if [ -n "$tty" ] && command -v microcom >/dev/null 2>&1; then
            echo -ne "AT+CGACT=0\r\n" | timeout 2 microcom -t 500 "$tty" >/dev/null 2>&1
        elif command -v fibocom_cmd >/dev/null 2>&1; then
            fibocom_cmd "" "AT+CGACT=0" >/dev/null 2>&1
        fi
        /usr/bin/fm350_dial.sh stop 2>/dev/null
        echo "OK: disconnected"
        ;;
    redial|restart)
        echo "INFO: re-dialing ..."
        /usr/bin/fm350_dial.sh stop 2>/dev/null
        sleep 1
        export FM350_APN="$APN"
        nohup /usr/bin/fm350_dial.sh dial >> /var/log/fm350_dial.log 2>&1 &
        echo "OK: re-dial launched"
        ;;
    *)
        echo "FAIL: action must be dial|stop|redial"
        ;;
esac
