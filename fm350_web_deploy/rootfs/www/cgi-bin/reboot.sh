#!/bin/sh
# FM350 Web CGI: 定时重启

echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

ACTION="status"
MIN=""
HOUR=""
DAY="*"
MONTH="*"
WEEKDAY="*"

[ -n "$QUERY_STRING" ] && {
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        case "$k" in
            action)  echo "ACTION='$v'" ;;
            minute|m) echo "MIN='$v'" ;;
            hour|h)   echo "HOUR='$v'" ;;
            day|d)    echo "DAY='$v'" ;;
            month)    echo "MONTH='$v'" ;;
            weekday)  echo "WEEKDAY='$v'" ;;
        esac
    done)"
}

RB="/usr/bin/fm350_reboot.sh"

case "$ACTION" in
    status)
        out=$("$RB" status 2>&1)
        # 转 JSON
        cron_line=$(grep "FM350 AUTO REBOOT" /etc/crontabs/root 2>/dev/null || echo "")
        crond=$(pgrep -af crond 2>/dev/null || echo "not running")
        up=$(uptime | awk -F'up |,' '{print $2}')
        cat <<JSON
{"schedule":"$(echo "$cron_line" | sed 's/"/\\"/g')","crond":"$(echo "$crond" | sed 's/"/\\"/g')","uptime":"$(echo "$up" | sed 's/^ *//')","raw":"$(echo "$out" | sed 's/"/\\"/g' | tr -d '\n' | sed 's/  */ /g')"}
JSON
        ;;
    set)
        [ -z "$MIN" ] || [ -z "$HOUR" ] && { echo '{"error":"need minute & hour"}'; exit 1; }
        out=$("$RB" set "$MIN" "$HOUR" "$DAY" "$MONTH" "$WEEKDAY" 2>&1)
        echo "{\"raw\":\"$(echo "$out" | sed 's/"/\\"/g')\"}"
        ;;
    unset|clear)
        out=$("$RB" unset 2>&1)
        echo "{\"raw\":\"$(echo "$out" | sed 's/"/\\"/g')\"}"
        ;;
    now|reboot)
        out=$("$RB" now 2>&1)
        echo "{\"raw\":\"$(echo "$out" | sed 's/"/\\"/g')\"}"
        ;;
    *)
        echo '{"error":"action must be status|set|unset|now"}'
        ;;
esac
