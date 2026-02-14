#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/components"
COMPONENTS_JSON="$SCRIPT_DIR/components.json"

# Pick GUI helper: prefer whiptail, fallback to dialog.
if command -v whiptail >/dev/null 2>&1; then
  UI_TOOL="whiptail"
elif command -v dialog >/dev/null 2>&1; then
  UI_TOOL="dialog"
else
  echo "Error: install 'whiptail' or 'dialog' to run this menu." >&2
  exit 1
fi

if [[ ! -d "$COMPONENTS_DIR" ]]; then
  echo "Error: missing components directory: $COMPONENTS_DIR" >&2
  exit 1
fi

MENU_ITEMS=()

load_from_json() {
  [[ -f "$COMPONENTS_JSON" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  mapfile -t json_rows < <(jq -r '.components[] | [.script, .name, .desc] | @tsv' "$COMPONENTS_JSON")
  [[ ${#json_rows[@]} -gt 0 ]] || return 1

  local row script name desc file
  for row in "${json_rows[@]}"; do
    IFS=$'\t' read -r script name desc <<<"$row"
    file="$COMPONENTS_DIR/$script"

    if [[ -x "$file" ]]; then
      MENU_ITEMS+=("$file" "$name - $desc")
    fi
  done

  [[ ${#MENU_ITEMS[@]} -gt 0 ]]
}

load_from_scripts() {
  local custom_name custom_desc
  mapfile -t COMPONENT_FILES < <(find "$COMPONENTS_DIR" -maxdepth 1 -type f -name '*.sh' -perm -u+x | sort)

  [[ ${#COMPONENT_FILES[@]} -gt 0 ]] || return 1

  for file in "${COMPONENT_FILES[@]}"; do
    name="$(basename "$file")"
    desc="$name"

    # Optional metadata header in component file:
    #   # NAME: My Component
    #   # DESC: What it does
    custom_name="$(grep -m1 '^# NAME:' "$file" | sed 's/^# NAME:[[:space:]]*//')" || true
    custom_desc="$(grep -m1 '^# DESC:' "$file" | sed 's/^# DESC:[[:space:]]*//')" || true

    [[ -n "$custom_name" ]] && name="$custom_name"
    [[ -n "$custom_desc" ]] && desc="$custom_desc"

    MENU_ITEMS+=("$file" "$name - $desc")
  done

  [[ ${#MENU_ITEMS[@]} -gt 0 ]]
}

load_from_json || load_from_scripts || {
  echo "No executable components found in $COMPONENTS_DIR" >&2
  exit 1
}

show_menu() {
  local choice

  if [[ "$UI_TOOL" == "whiptail" ]]; then
    choice=$(whiptail \
      --title "VM Setup Components" \
      --menu "Select a component to run:" \
      20 100 10 \
      "${MENU_ITEMS[@]}" \
      3>&1 1>&2 2>&3) || return 1
  else
    choice=$(dialog \
      --stdout \
      --title "VM Setup Components" \
      --menu "Select a component to run:" \
      20 100 10 \
      "${MENU_ITEMS[@]}") || return 1
  fi

  printf '%s\n' "$choice"
}

while true; do
  selected="$(show_menu || true)"

  if [[ -z "${selected:-}" ]]; then
    echo "Menu closed. Exiting."
    exit 0
  fi

  clear
  echo "Running component: $selected"
  echo "----------------------------------------"
  "$selected"
  echo "----------------------------------------"
  read -r -p "Press Enter to return to menu (Ctrl+C to quit)..." _
done
