#!/bin/sh
# FM350 Web CGI: SMS 短信收发
# =================================

echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")/../../usr/bin" && pwd)"
. "$SCRIPT_DIR/at_helper.sh"

# 解析 query
ACTION="list"
NUM=""
TEXT=""
IDX=""

[ -n "$QUERY_STRING" ] && {
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        case "$k" in
            action) echo "ACTION='$v'" ;;
            num)    echo "NUM='$v'" ;;
            text)   echo "TEXT='$v'" ;;
            idx)    echo "IDX='$v'" ;;
            filter) echo "FILTER='$v'" ;;
        esac
    done)"
}

# POST body 补充
if [ "$REQUEST_METHOD" = "POST" ]; then
    BODY=$(cat)
    [ -z "$ACTION" ] && ACTION=$(echo "$BODY" | grep -oE 'action=[^&]+' | cut -d= -f2-)
    [ -z "$NUM" ] && NUM=$(echo "$BODY" | grep -oE 'num=[^&]+' | cut -d= -f2-)
    [ -z "$TEXT" ] && TEXT=$(echo "$BODY" | grep -oE 'text=[^&]+' | cut -d= -f2-)
    [ -z "$IDX" ] && IDX=$(echo "$BODY" | grep -oE 'idx=[^&]+' | cut -d= -f2-)
fi

SMS_TOOL="$SCRIPT_DIR/fm350_sms.sh"

case "$ACTION" in
    list)
        FILTER="${FILTER:-ALL}"
        out=$("$SMS_TOOL" list "$FILTER" 2>&1)
        if [ $? -eq 0 ]; then
            echo "$out"
        else
            echo "{\"error\":\"$out\"}"
        fi
        ;;

    send)
        [ -z "$NUM" ] || [ -z "$TEXT" ] && {
            echo '{"error":"need num & text"}'; exit 1
        }
        out=$("$SMS_TOOL" send "$NUM" "$TEXT" 2>&1)
        case "$out" in
            OK*) echo "{\"ok\":true,\"msg\":\"$out\"}" ;;
            *)   echo "{\"ok\":false,\"msg\":\"$out\"}" ;;
        esac
        ;;

    read)
        [ -z "$IDX" ] && { echo '{"error":"need idx"}'; exit 1; }
        out=$("$SMS_TOOL" read "$IDX" 2>&1)
        echo "{\"ok\":true,\"raw\":\"$(echo "$out" | at_clean | json_escape)\"}"
        ;;

    delete)
        [ -z "$IDX" ] && { echo '{"error":"need idx"}'; exit 1; }
        out=$("$SMS_TOOL" delete "$IDX" 2>&1)
        echo "{\"raw\":\"$(echo "$out" | at_clean | json_escape)\"}"
        ;;

    delete_all)
        out=$("$SMS_TOOL" delete_all 2>&1)
        echo "{\"raw\":\"$(echo "$out" | at_clean | json_escape)\"}"
        ;;

    status)
        tool=$(at_find_tool)
        port=$(at_find_port)
        sim=$(at_get_sim_state)
        op=$(at_get_operator)
        csq=$(at_get_csq)
        daemon=$(pgrep -f fm350_sms.sh >/dev/null 2>&1 && echo "running" || echo "stopped")
        cat <<JSON
{"tool":"$tool","port":"$port","sim":"$(echo "$sim" | json_escape)","operator":"$op","csq":"$csq","daemon":"$daemon"}
JSON
        ;;

    *)
        echo '{"error":"action must be list|send|read|delete|delete_all|status"}'
        ;;
esac
