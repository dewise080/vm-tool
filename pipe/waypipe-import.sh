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
)

DEST_DIR="$HOME/.local/share/applications/waypipe-remote"
TAG="(Remote)"

mkdir -p "$DEST_DIR"

# --- HELPER: QUIET ZENITY ---
# Wraps zenity to suppress GTK/Adwaita warnings while keeping real errors
function quiet_zenity() {
    zenity "$@" 2> >(grep -v "Adwaita-WARNING" >&2)
}

# --- PRE-FLIGHT CHECKS ---
function check_gpu_permissions() {
    local render_node="/dev/dri/renderD128"

    if [ -e "$render_node" ] && [ ! -w "$render_node" ]; then
        # We only check this once per run to avoid spamming if importing multiple times
        if [ -z "${GPU_CHECKED:-}" ]; then
            echo "⚠️  Warning: No write permission for $render_node"

            MSG="<b>GPU Permission Issue Detected</b>\n\nwaypipe needs access to <i>$render_node</i> for hardware acceleration.\n\nTo fix this permanently, run this command in a terminal and then <b>reboot</b>:\n\n<tt>sudo usermod -aG render \$USER</tt>\n\nProceed anyway?"

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
            export GPU_CHECKED=1
        fi
    fi
}

# --- CLEANUP FUNCTION ---
function cleanup_mode() {
    echo "🧹 Cleanup Mode"

    # Check if dir is empty or no files exist
    shopt -s nullglob
    FILES=("$DEST_DIR"/*.desktop)
    shopt -u nullglob

    if [ ${#FILES[@]} -eq 0 ]; then
        if command -v zenity >/dev/null; then
             quiet_zenity --info --text="No remote apps found in:\n$DEST_DIR" --title="Cleanup"
        else
             echo "No remote apps found in $DEST_DIR"
        fi
        exit 0
    fi

    if command -v zenity >/dev/null; then
        # Build arguments array for Zenity
        ZENITY_ARGS=()
        for f in "${FILES[@]}"; do
             # Extract Name for display
             NAME=$(grep "^Name=" "$f" | head -n1 | cut -d= -f2-)
             [ -z "$NAME" ] && NAME=$(basename "$f")
             ZENITY_ARGS+=(FALSE "$NAME" "$f")
        done

        TO_DELETE=$(quiet_zenity --list --checklist \
            --title="Select Apps to Remove" \
            --text="Select the applications you want to DELETE:" \
            --column="Select" --column="Name" --column="Path" \
            --hide-column=3 \
            --print-column=3 \
            --separator=$'\n' \
            --width=600 --height=500 "${ZENITY_ARGS[@]}") || exit 0

    elif command -v fzf >/dev/null; then
        # FZF fallback: List Name|Path, return Path
        LIST_FOR_FZF=""
        for f in "${FILES[@]}"; do
             NAME=$(grep "^Name=" "$f" | head -n1 | cut -d= -f2-)
             [ -z "$NAME" ] && NAME=$(basename "$f")
             LIST_FOR_FZF+="$NAME|$f"$'\n'
        done

        TO_DELETE=$(echo -n "$LIST_FOR_FZF" | fzf --multi --delimiter='|' --with-nth=1 --header="TAB to select apps to DELETE" | cut -d'|' -f2)
    else
        echo "No interactive tool found. Listing files:"
        ls "$DEST_DIR"/*.desktop
        echo "Run 'rm <file>' manually."
        exit 1
    fi

    if [ -z "$TO_DELETE" ]; then
        echo "No apps selected for deletion."
        exit 0
    fi

    # Confirm and Delete
    echo "$TO_DELETE" | while read -r file; do
        if [ -f "$file" ]; then
            rm "$file"
            echo "   [-] Deleted: $(basename "$file")"
        fi
    done

    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    echo "✅ Cleanup complete."
}

# --- IMPORT FUNCTION ---
function import_mode() {
    # 0. DETERMINE REMOTE HOST
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
                --title="Waypipe Import - Select Host" \
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

    echo "🔍 Scanning $REMOTE_HOST..."

    # 1. FETCH RAW DATA
    # We use 'cat' to dump all desktop files.
    if ! RAW_TEXT=$(ssh -q "$REMOTE_HOST" "cat /usr/share/applications/*.desktop ~/.local/share/applications/*.desktop 2>/dev/null"); then
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

    echo "📋 Processing list (removing junk)..."

    # 2. PROCESS LOCALLY
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
                sub(/ %[a-zA-Z].*/, "");
                sub(/ --no-sandbox/, "");
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

    # 3. INTERACTIVE SELECTION
    if command -v zenity >/dev/null; then
        echo "🎨 Opening Zenity dialog..."
        ZENITY_INPUT=$(echo "$PARSED_LIST" | awk -F'|' '{ print "FALSE"; print $1; print $2; print $3 }')

        SELECTED_APPS=$(echo "$ZENITY_INPUT" | quiet_zenity --list --checklist \
            --title="Select Apps to Import from $REMOTE_HOST" \
            --text="Select the applications you want to create shortcuts for:" \
            --column="Pick" --column="Name" --column="Exec" --column="Icon" \
            --print-column=2,3,4 \
            --separator=$'\n' \
            --width=700 --height=600) || { echo "Cancelled."; exit 0; }

    elif command -v fzf >/dev/null; then
        echo "👉 Use TAB to select apps, ENTER to confirm."
        SELECTED_APPS=$(echo "$PARSED_LIST" | fzf --multi --delimiter='|' --with-nth=1 \
            --header="SELECT APPS (Tab=Select, Enter=Import)" \
            --preview="echo 'Command: {2}'" \
            --cycle)
    else
        echo "⚠️ Neither 'zenity' nor 'fzf' found. Importing ALL detected apps..."
        SELECTED_APPS="$PARSED_LIST"
    fi

    if [ -z "$SELECTED_APPS" ]; then echo "No apps selected."; exit 0; fi

    # 4. INSTALL SHORTCUTS
    echo "📦 Importing selected apps..."
    IFS=$'\n'
    for line in $SELECTED_APPS; do
        APP_NAME=$(echo "$line" | cut -d'|' -f1)
        APP_EXEC=$(echo "$line" | cut -d'|' -f2)
        APP_ICON=$(echo "$line" | cut -d'|' -f3)

        if [ -z "$APP_NAME" ] || [ -z "$APP_EXEC" ]; then continue; fi

        SAFE_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
        FILENAME="$DEST_DIR/$SAFE_NAME.desktop"

        EXTRA_FLAGS=""
        if [[ "$APP_EXEC" == *"chrome"* ]] || [[ "$APP_EXEC" == *"brave"* ]] || [[ "$APP_EXEC" == *"code"* ]]; then
            EXTRA_FLAGS="--ozone-platform=wayland --disable-gpu --no-sandbox"
        fi

        cat > "$FILENAME" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME $TAG
Exec=waypipe ssh -q $REMOTE_HOST "$APP_EXEC $EXTRA_FLAGS"
Icon=$APP_ICON
Categories=Network;
Terminal=false
EOF
        echo "   [+] $APP_NAME"
    done

    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    echo "✅ Done! Search for '$TAG' in your menu."
}

# --- MAIN EXECUTION FLOW ---

# 0. Check Permissions (warn user early if they might have issues launching later)
check_gpu_permissions

# 1. CLI Override for Cleanup
if [[ "${1:-}" == "--clean" ]] || [[ "${1:-}" == "-c" ]]; then
    cleanup_mode
    exit 0
fi

# 2. Interactive Menu (if no args provided and Zenity exists)
if [ -z "${1:-}" ] && command -v zenity >/dev/null; then
    MODE=$(quiet_zenity --list --radiolist \
        --title="Waypipe Manager" \
        --text="What would you like to do?" \
        --column="Select" --column="Action" \
        TRUE "Import Apps" \
        FALSE "Clean Up Apps" \
        --height=220 --width=300) || exit 0

    if [[ "$MODE" == "Clean Up Apps" ]]; then
        cleanup_mode
    else
        import_mode ""
    fi
else
    # Default behavior: Import (pass args if any)
    import_mode "$@"
fi
