# time/locale checks [U]
check_time() {
    if have timedatectl; then
        if ! time_state=$(timedatectl show -p NTPSynchronized --value 2>/dev/null); then
            finding_status ERROR time time.ntp system high "timedatectl query failed" timedatectl "NTP synchronization state unavailable"
        elif [ "$time_state" = yes ]; then
            finding PASS time "NTP synchronized"
        elif [ "$time_state" = no ]; then
            finding_status FAIL time time.ntp system high "NTPSynchronized=$time_state" timedatectl "clock not NTP-synced (breaks TLS, caches)"
        else
            finding_status UNKNOWN time time.ntp system low "unexpected NTPSynchronized value" timedatectl "NTP synchronization state unrecognized"
        fi
    else
        finding_status SKIP time time.ntp system high "command not installed" timedatectl "NTP synchronization check unavailable"
    fi
    if [ -z "${LANG:-}" ]; then
        finding WARN time "LANG unset" "i18n.defaultLocale in /etc/nixos"
    else
        if ! locales=$(locale -a 2>/dev/null); then
            finding_status ERROR time time.locale system high "locale query failed" locale "generated locales could not be read"
        elif printf '%s\n' "$locales" | grep -qi "^${LANG%%.*}"; then
            finding PASS time "locale $LANG available"
        else
            finding WARN time "locale $LANG not generated" "i18n.supportedLocales / glibcLocales"
        fi
    fi
}
