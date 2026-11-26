#!/bin/sh
# FM350 Web CGI: 锁网锁频
# =========================

echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")/../../usr/bin" && pwd)"

ACTION="status"
NET=""
BAND=""
FREQ=""

[ -n "$QUERY_STRING" ] && {
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        case "$k" in
            action) echo "ACTION='$v'" ;;
            net|plmn|mccmnc) echo "NET='$v'" ;;
            band)   echo "BAND='$v'" ;;
            freq)   echo "FREQ='$v'" ;;
        esac
    done)"
}

LOCK="$SCRIPT_DIR/fm350_lock.sh"

case "$ACTION" in
    status|show)
        "$LOCK" status
        ;;
    auto|unlock)
        "$LOCK" auto 2>&1 | tail -n +1
        ;;
    net|plmn)
        [ -z "$NET" ] && { echo '{"error":"need net=46001"}'; exit 1; }
        "$LOCK" net "$NET" 2>&1
        ;;
    band)
        [ -z "$BAND" ] && { echo '{"error":"need band=78"}'; exit 1; }
        "$LOCK" band "$BAND" 2>&1
        ;;
    freq)
        [ -z "$FREQ" ] && { echo '{"error":"need freq=632688"}'; exit 1; }
        "$LOCK" freq "$FREQ" 2>&1
        ;;
    full)
        [ -z "$NET" ] || [ -z "$BAND" ] && { echo '{"error":"need net & band"}'; exit 1; }
        "$LOCK" full "$NET" "$BAND" "$FREQ" 2>&1
        ;;
    scan)
        out=$("$LOCK" scan 2>&1)
        echo "{\"raw\":\"$(echo "$out" | sed 's/"/\\"/g' | tr -d '\n' | sed 's/  */ /g')\"}"
        ;;
    help)
        "$LOCK" help
        ;;
    *)
        echo '{"error":"action must be status|auto|net|band|freq|full|scan|help"}'
        ;;
esac
