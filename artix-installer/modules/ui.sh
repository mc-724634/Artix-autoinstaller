#!/usr/bin/env bash
#
# modules/ui.sh — dialog wrappers + state-file helpers + error checking
#
# RULES THIS FILE ENFORCES:
#   - never capture dialog output via a broken subshell pipeline
#   - always use `dialog ... 3>&1 1>&2 2>&3` for menus that return a value
#   - every screen blocks until the user responds (no timeouts, no -- )
#   - every failed command is checked explicitly and reported via msgbox

# ---- low-level dialog wrappers -------------------------------------------

ui_msgbox() {
    local text="$1" h="${2:-8}" w="${3:-60}"
    dialog --msgbox "$text" "$h" "$w"
}

ui_yesno() {
    local text="$1" h="${2:-8}" w="${3:-60}"
    dialog --yesno "$text" "$h" "$w"
}

# ui_menu "Title" height width menu_height tag1 item1 tag2 item2 ...
# Echoes the chosen tag on stdout. Returns 1 if cancelled.
ui_menu() {
    local title="$1"; shift
    local h="$1"; shift
    local w="$1"; shift
    local mh="$1"; shift

    local choice
    choice=$(dialog --title "$title" --menu "$title" "$h" "$w" "$mh" "$@" 3>&1 1>&2 2>&3)
    local status=$?
    if [[ $status -ne 0 ]]; then
        return 1
    fi
    echo "$choice"
    return 0
}

# ui_inputbox "Prompt" "default"
ui_inputbox() {
    local prompt="$1" default="${2:-}"
    local result
    result=$(dialog --inputbox "$prompt" 8 60 "$default" 3>&1 1>&2 2>&3)
    local status=$?
    if [[ $status -ne 0 ]]; then
        return 1
    fi
    echo "$result"
    return 0
}

ui_passwordbox() {
    local prompt="$1"
    local result
    result=$(dialog --insecure --passwordbox "$prompt" 8 60 3>&1 1>&2 2>&3)
    local status=$?
    if [[ $status -ne 0 ]]; then
        return 1
    fi
    echo "$result"
    return 0
}

ui_gauge_run() {
    # ui_gauge_run "Title" "command" -- shows an infinite pulse gauge while
    # a long-running command executes in the background.
    local title="$1"; shift
    ( "$@" ) &
    local pid=$!
    (
        while kill -0 "$pid" 2>/dev/null; do
            echo "XXX"
            echo "0"
            echo "$title in progress..."
            echo "XXX"
            sleep 1
        done
    ) | dialog --gauge "$title" 8 60 0
    wait "$pid"
    return $?
}

# ---- error checking --------------------------------------------------

# check_exit <exit_code> "message shown on failure"
# Call this immediately after any command whose failure should stop the
# installer instead of being silently swallowed.
check_exit() {
    local code="$1" msg="$2"
    if [[ "$code" -ne 0 ]]; then
        dialog --msgbox "ERROR: $msg\n\nSee $LOG_FILE for details." 10 60
        exit 1
    fi
}

die() {
    local msg="$1"
    dialog --msgbox "FATAL: $msg\n\nSee $LOG_FILE for details." 10 60
    exit 1
}

# ---- state file (/tmp/artix.conf) helpers --------------------------------

# conf_set KEY VALUE — upserts KEY=VALUE in $CONF_FILE
conf_set() {
    local key="$1" value="$2"
    touch "$CONF_FILE"
    if grep -q "^${key}=" "$CONF_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$CONF_FILE"
    else
        echo "${key}=${value}" >> "$CONF_FILE"
    fi
}

# conf_get KEY — prints the value, empty string if unset
conf_get() {
    local key="$1"
    [[ -f "$CONF_FILE" ]] || { echo ""; return; }
    grep "^${key}=" "$CONF_FILE" | tail -n1 | cut -d'=' -f2-
}

# conf_load — sources the state file as shell variables (DISK, ROOT, etc.)
conf_load() {
    # shellcheck disable=SC1090
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
}
