#!/bin/bash
set -euo pipefail

# --- CONFIGURATION ---
# Add or remove hosts here. The first one is the default selection.
KNOWN_HOSTS=(
    "lofa@100.81.183.71"
    "lofa@100.119.186.119"
    "lofa@100.92.64.41"
    "lofa-srv@100.80.149.123"
    "ubuntu@100.103.26.55"
    "root@100.125.7.95"
)

# --- HELPER: QUIET ZENITY ---
function quiet_zenity() {
    zenity "$@" 2> >(grep -v "Adwaita-WARNING" >&2)
}

# --- PRE-FLIGHT CHECKS ---
function check_gpu_permissions() {
    local render_node="/dev/dri/renderD128"

    if [ -e "$render_node" ] && [ ! -w "$render_node" ]; then
        echo "⚠️  Warning: No write permission for $render_node"

        MSG="<b>GPU Permission Issue Detected</b>\n\nwaypipe needs access to <i>$render_node</i> for hardware acceleration.\n\nTo fix this permanently, run this command in a terminal and then <b>reboot</b>:\n\n<tt>sudo usermod -aG render \$USER</tt>\n\nProceed anyway? (Performance may be poor)"

        if command -v zenity >/dev/null; then
            quiet_zenity --question --title="Permission Warning" \
                --text="$MSG" --width=500 || exit 0
        else
            echo "-----------------------------------------------------"
            echo "⚠️  WARNING: PERMISSION DENIED FOR GPU"
            echo "Run this to fix: sudo usermod -aG render \$USER"
            echo "-----------------------------------------------------"
            read -p "Press Enter to continue anyway (or Ctrl+C to cancel)..."
        fi
    fi
}

# --- MAIN LOGIC ---

# 1. CHECK PERMISSIONS
check_gpu_permissions

# 2. DETERMINE REMOTE HOST
REMOTE_HOST="${1:-}"

if [ -z "$REMOTE_HOST" ]; then
    if command -v zenity >/dev/null; then
        # Build the Zenity list arguments dynamically
        ZENITY_ARGS=()

        # Add the first host as TRUE (selected by default)
        ZENITY_ARGS+=(TRUE "${KNOWN_HOSTS[0]}")

        # Add the rest as FALSE
        for ((i=1; i<${#KNOWN_HOSTS[@]}; i++)); do
            ZENITY_ARGS+=(FALSE "${KNOWN_HOSTS[i]}")
        done

        # Add the Manual option
        ZENITY_ARGS+=(FALSE "Enter manually...")

        CHOICE=$(quiet_zenity --list --radiolist \
            --title="Select Remote Host" \
            --text="Choose a server or enter a new one:" \
            --column="" --column="Host" \
            --hide-header \
            --width=400 --height=300 \
            "${ZENITY_ARGS[@]}") || exit 0

        if [ "$CHOICE" == "Enter manually..." ]; then
            REMOTE_HOST=$(quiet_zenity --entry \
                --title="Manual Connection" \
                --text="Enter user@ip:" \
                --entry-text="${KNOWN_HOSTS[0]}") || exit 1
        else
            REMOTE_HOST="$CHOICE"
        fi
    elif command -v fzf >/dev/null; then
        # FZF fallback
        CHOICE=$(printf "%s\nEnter manually..." "${KNOWN_HOSTS[*]}" | tr ' ' '\n' | fzf --header="SELECT HOST")
        if [ "$CHOICE" == "Enter manually..." ]; then
            read -p "Enter user@ip: " REMOTE_HOST
        else
            REMOTE_HOST="$CHOICE"
        fi
    else
        REMOTE_HOST="${KNOWN_HOSTS[0]}"
        echo "ℹ️  No interactive tool found. Using default: $REMOTE_HOST"
    fi
fi

if [ -z "$REMOTE_HOST" ]; then
    echo "❌ No host provided. Exiting."
    exit 1
fi

echo "🔍 Scanning $REMOTE_HOST for apps..."

# 3. FETCH RAW DATA
# Use find+xargs so missing globs don't cause a non-zero exit.
REMOTE_CMD="find /usr/share/applications ~/.local/share/applications -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null | xargs -0 -r cat 2>/dev/null"
if ! RAW_TEXT=$(ssh -q "$REMOTE_HOST" "$REMOTE_CMD"); then
    echo "❌ SSH Connection failed."
    if command -v zenity >/dev/null; then
        quiet_zenity --error --text="Could not connect to $REMOTE_HOST\nCheck your SSH connection."
    fi
    exit 1
fi

if [ -z "$RAW_TEXT" ]; then
    echo "❌ No apps found on remote host."
    exit 1
fi

echo "📋 Processing list..."

# 4. PROCESS LOCALLY (Parses .desktop files for Name, Exec, and Icon)
PARSED_LIST=$(echo "$RAW_TEXT" | tr -d '\r' | awk '
    /^\[Desktop Entry\]/{
        if (name != "" && exec_cmd != "" && skip != 1) {
            print name "|" exec_cmd "|" icon
        }
        name=""; exec_cmd=""; icon=""; skip=0; in_entry=1; next
    }
    /^\[Desktop Action/ { in_entry=0; next }
    in_entry {
        if (/^Name=/) { sub(/^Name=/, ""); name=$0 }
        if (/^Exec=/) {
            sub(/^Exec=/, "");
            sub(/ %[a-zA-Z].*/, "");     # Remove field codes (%u, %F)
            sub(/ --no-sandbox/, "");     # Remove common sandbox flags
            exec_cmd=$0
        }
        if (/^Icon=/) { sub(/^Icon=/, ""); icon=$0 }
        if (/^NoDisplay=true/) { skip=1 }
    }
    END {
        if (name != "" && exec_cmd != "" && skip != 1) {
            print name "|" exec_cmd "|" icon
        }
    }
' | sort -u)

# 5. INTERACTIVE SELECTION
if command -v zenity >/dev/null; then
    # Prepare arguments array for Zenity (triplets of Name, Exec, Icon)
    ZENITY_ARGS=()
    IFS=$'\n'
    for line in $PARSED_LIST; do
        NAME=$(echo "$line" | cut -d'|' -f1)
        EXEC=$(echo "$line" | cut -d'|' -f2)
        ICON=$(echo "$line" | cut -d'|' -f3)

        # If no icon name is provided, use a generic one
        [ -z "$ICON" ] && ICON="application-x-executable"

        ZENITY_ARGS+=("$NAME" "$EXEC" "$ICON")
    done
    unset IFS

    # Show list: Column 1 (Name) is shown, Column 2 (Exec) is hidden but returned
    SELECTED_EXEC=$(quiet_zenity --list \
        --title="Waypipe Quick Launch ($REMOTE_HOST)" \
        --text="Select an application to launch:" \
        --column="Application" --column="Command" --column="Icon" \
        --hide-column=2 \
        --print-column=2 \
        --width=600 --height=600 \
        "${ZENITY_ARGS[@]}") || exit 0

elif command -v fzf >/dev/null; then
    # Fallback to FZF
    SELECTED_EXEC=$(echo "$PARSED_LIST" | fzf --delimiter='|' --with-nth=1 \
        --header="SELECT APP TO LAUNCH" \
        --preview="echo 'Command: {2}'" \
        --cycle | cut -d'|' -f2)
else
    echo "❌ No interactive tool (zenity/fzf) found."
    exit 1
fi

if [ -z "$SELECTED_EXEC" ]; then exit 0; fi

# 6. LAUNCH
echo "🚀 Launching: $SELECTED_EXEC"

# Special flags for known problematic apps
EXTRA_FLAGS=""
if [[ "$SELECTED_EXEC" == *"chrome"* ]] || [[ "$SELECTED_EXEC" == *"brave"* ]] || [[ "$SELECTED_EXEC" == *"code"* ]]; then
    EXTRA_FLAGS="--ozone-platform=wayland --disable-gpu --no-sandbox"
fi

if command -v notify-send >/dev/null; then
    notify-send "Waypipe" "Launching remote app from $REMOTE_HOST..." -i network-server
fi

# 'exec' replaces the script process with the ssh process
exec waypipe ssh -q "$REMOTE_HOST" "$SELECTED_EXEC $EXTRA_FLAGS"
