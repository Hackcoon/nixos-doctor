# journal checks [U]
check_journal() {
    have journalctl || { finding_status SKIP journal journal.command system high "command not installed" journalctl "journalctl missing"; return 0; }
    # Count the FULL error set (a capped sample here once hid a 397k-line flood).
    if ! errors=$(journalctl -b -p err --no-pager 2>/dev/null); then
        finding_status ERROR journal journal.current_errors system high "journal query failed" journalctl "could not read current-boot errors"
        return 0
    fi
    n=$(printf '%s\n' "$errors" | grep -vcE "^[[:space:]]*$|-- Boot|Journal " || true)
    if [ "${n:-0}" -eq 0 ]; then
        finding PASS journal "no errors this boot"
    else
        # attribute to units via structured log (short format often omits them)
        worst=$(journalctl -b -p err -o json --no-pager 2>/dev/null | python3 -c "
import json,sys
from collections import Counter
c = Counter()
for line in sys.stdin:
    try: e = json.loads(line)
    except Exception: continue
    u = e.get('_SYSTEMD_UNIT') or e.get('SYSLOG_IDENTIFIER') or '?'
    c[u] += 1
print(';'.join('%s x%d' % kv for kv in c.most_common(3)))")
        [ -z "$worst" ] && worst="unspecified units"
        finding FAIL journal "${n} error lines this boot (worst: $worst)" "journalctl -b -p err --no-pager | head -30"
    fi
    disk_usage=$(journalctl --disk-usage 2>/dev/null || true)
    du_out=$(printf '%s\n' "$disk_usage" | grep -oE '[0-9.]+[KMG]' | head -1)
    if [ -n "$du_out" ]; then
        case "$du_out" in
            *G) finding_fix WARN journal "journal using $du_out" journal_vacuum_size "journalctl --vacuum-size=500M" 500M ;;
            *) finding PASS journal "journal using $du_out" ;;
        esac
    fi
    if have coredumpctl; then
        n=$(coredumpctl --no-legend 2>/dev/null | grep -c . || true)
        [ "${n:-0}" -gt 0 ] && finding WARN journal "$n coredumps recorded" "coredumpctl list; coredumpctl info <pid>"
    fi
    if ! kernel_log=$(journalctl -b -k --no-pager 2>/dev/null); then
        finding_status ERROR journal journal.kernel system high "kernel journal query failed" journalctl "could not read current-boot kernel journal"
        return 0
    fi
    if printf '%s\n' "$kernel_log" | grep -qiE "oom-killer|killed process|out of memory"; then
        finding FAIL journal "OOM kills detected in kernel log" "free more RAM/swap; check memory area"
    fi
    if printf '%s\n' "$kernel_log" | grep -qiE "tainted|firmware.*failed|Direct firmware load.*failed"; then
        finding WARN journal "kernel taint or missing firmware lines present" "journalctl -k --no-pager | grep -iE 'taint|firmware'"
    fi
}
