#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFICIAL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
OFFICIAL_SCRIPT_LOCAL="${SCRIPT_DIR}/x-install/xray-install.sh"
TEMPLATE_URL="https://raw.githubusercontent.com/zjjscwt/x-install/main/config-example.json"
TEMPLATE_FILE="${SCRIPT_DIR}/x-install/config-example.json"
TARGET_CONFIG="/usr/local/etc/xray/config.json"

RED=""
GREEN=""
AQUA=""
RESET=""

init_colors() {
  if command -v tput >/dev/null 2>&1; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    AQUA="$(tput setaf 6)"
    RESET="$(tput sgr0)"
  fi
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "${RED}error:${RESET} Please run as root"
    exit 1
  fi
}

pause() {
  echo
  read -r -p "Press Enter to continue..." _
}

prompt_value() {
  local prompt="$1"
  local value=""
  read -r -p "$prompt" value
  printf '%s' "$value"
}

random_hex() {
  local len="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex $((len / 2))
  else
    hexdump -v -n $((len / 2)) -e '1/1 "%02x"' /dev/urandom
  fi
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

ensure_xray_installed() {
  if [[ ! -x /usr/local/bin/xray ]]; then
    echo "${RED}error:${RESET} xray not found, please install first"
    return 1
  fi
}

gen_x25519_keypair() {
  /usr/local/bin/xray x25519
}

validate_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]
}

fetch_official_script() {
  mkdir -p "$(dirname "$OFFICIAL_SCRIPT_LOCAL")"
  if command -v curl >/dev/null 2>&1; then
    curl -fLsS "$OFFICIAL_URL" -o "$OFFICIAL_SCRIPT_LOCAL"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$OFFICIAL_SCRIPT_LOCAL" "$OFFICIAL_URL"
  else
    echo "${RED}error:${RESET} curl or wget is required"
    exit 1
  fi
  chmod +x "$OFFICIAL_SCRIPT_LOCAL"
}

fetch_template() {
  mkdir -p "$(dirname "$TEMPLATE_FILE")"
  if command -v curl >/dev/null 2>&1; then
    curl -fLsS "$TEMPLATE_URL" -o "$TEMPLATE_FILE"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TEMPLATE_FILE" "$TEMPLATE_URL"
  else
    echo "${RED}error:${RESET} curl or wget is required"
    exit 1
  fi
}

setup_shortcut() {
  local target="/usr/local/bin/daili"
  if [[ -e "$target" ]]; then
    return 0
  fi
  if ln -s "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
    echo "${GREEN}info:${RESET} Shortcut created: daili"
  else
    if cp "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
      chmod +x "$target"
      echo "${GREEN}info:${RESET} Shortcut copied: daili"
    else
      echo "${RED}warning:${RESET} Failed to create shortcut"
    fi
  fi
}

write_config() {
  local uuid="$1"
  local domain="$2"
  local private_key="$3"
  local short_ids="$4"

  local short_ids_json
  if [[ "$short_ids" == *","* ]]; then
    short_ids_json="["
    local first=1
    IFS=',' read -ra arr <<<"$short_ids"
    for sid in "${arr[@]}"; do
      sid="$(echo "$sid" | xargs)"
      [[ -z "$sid" ]] && continue
      if (( first )); then
        short_ids_json+="\"$sid\""
        first=0
      else
        short_ids_json+=",\"$sid\""
      fi
    done
    short_ids_json+="]"
  else
    short_ids_json="[\"$short_ids\"]"
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  cat "$TEMPLATE_FILE" >"$tmp_file"

  sed -i \
    -e "s/YOUR_UUID/$uuid/g" \
    -e "s/YOUR_PRIVATE_KEY/$private_key/g" \
    -e "s/YOUR_DOMAIN/$domain/g" \
    -e "s/\"shortIds\": \[\"SHORT_ID\"\]/\"shortIds\": $short_ids_json/" \
    "$tmp_file"

  install -d "$(dirname "$TARGET_CONFIG")"
  install -m 644 "$tmp_file" "$TARGET_CONFIG"
  rm -f "$tmp_file"

  echo "${GREEN}info:${RESET} Config written: $TARGET_CONFIG"
}

install_xray() {
  echo "${AQUA}>>> Install Xray (official script)${RESET}"

  local uuid domain private_key short_ids public_key

  uuid="$(prompt_value "UUID (Enter to auto-generate): ")"
  if [[ -z "$uuid" ]]; then
    uuid="$(gen_uuid)"
    echo "${GREEN}info:${RESET} UUID generated: $uuid"
  fi

  domain="$(prompt_value "Domain (Enter for www.samsung.com): ")"
  if [[ -z "$domain" ]]; then
    domain="www.samsung.com"
  fi
  if ! validate_domain "$domain"; then
    echo "${RED}error:${RESET} Invalid domain"
    return 1
  fi

  short_ids="$(prompt_value "shortIds (comma separated, Enter for random 8 hex): ")"
  if [[ -z "$short_ids" ]]; then
    short_ids="$(random_hex 8)"
    echo "${GREEN}info:${RESET} shortIds generated: $short_ids"
  fi

  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" install

  ensure_xray_installed

  private_key="$(prompt_value "privateKey (Enter to auto-generate): ")"
  if [[ -z "$private_key" ]]; then
    local keypair
    keypair="$(gen_x25519_keypair)"
    private_key="$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}')"
    public_key="$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}')"
    echo "${GREEN}info:${RESET} privateKey/publicKey generated"
  else
    public_key="$(prompt_value "publicKey (Enter to derive): ")"
    if [[ -z "$public_key" ]]; then
      local derived
      derived="$(/usr/local/bin/xray x25519 -i "$private_key" 2>/dev/null || true)"
      public_key="$(echo "$derived" | awk -F': ' '/Public key/ {print $2}')"
      if [[ -z "$public_key" ]]; then
        public_key="(derive failed)"
      else
        echo "${GREEN}info:${RESET} publicKey derived"
      fi
    fi
  fi

  fetch_template
  write_config "$uuid" "$domain" "$private_key" "$short_ids"

  systemctl restart xray
  sleep 1s
  if systemctl -q is-active xray; then
    echo "${GREEN}info:${RESET} Xray started"
  else
    echo "${RED}warning:${RESET} Xray failed to start"
  fi

  local ip_addr
  if command -v curl >/dev/null 2>&1; then
    ip_addr="$(curl -s https://api.ipify.org || true)"
  fi
  if [[ -z "$ip_addr" ]]; then
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -z "$ip_addr" ]] && ip_addr="(unknown)"

  echo
  echo "${AQUA}=== Install Result ===${RESET}"
  echo "1. IP: $ip_addr"
  echo "2. UUID: $uuid"
  echo "3. Domain: $domain"
  echo "4. public-key: $public_key"
  echo "5. short-id: $short_ids"
}

update_menu() {
  while true; do
    clear
    echo "${AQUA}=== Update Menu ===${RESET}"
    echo "1. Update core"
    echo "2. Update GEO data"
    echo "0. Back"
    echo
    read -r -p "Select: " choice
    case "$choice" in
      1)
        fetch_official_script
        bash "$OFFICIAL_SCRIPT_LOCAL" install
        pause
        ;;
      2)
        fetch_official_script
        bash "$OFFICIAL_SCRIPT_LOCAL" install-geodata
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Invalid choice"
        pause
        ;;
    esac
  done
}

start_xray() {
  systemctl start xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray started" || echo "${RED}error:${RESET} Start failed"
}

stop_xray() {
  systemctl stop xray
  systemctl -q is-active xray && echo "${RED}error:${RESET} Stop failed" || echo "${GREEN}info:${RESET} Xray stopped"
}

restart_xray() {
  systemctl restart xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray restarted" || echo "${RED}error:${RESET} Restart failed"
}

status_xray() {
  systemctl --no-pager --full status xray
}

remove_xray() {
  echo "WARNING: This will remove Xray and all related files"
  read -r -p "Continue? (y to proceed): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Canceled"
    return
  fi

  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" remove --purge

  rm -f /usr/local/bin/daili
  rm -rf "${SCRIPT_DIR}/x-install"
  rm -f "$TARGET_CONFIG"
  if [[ -d "$(dirname "$TARGET_CONFIG")" ]]; then
    rmdir "$(dirname "$TARGET_CONFIG")" 2>/dev/null || true
  fi

  rm -f "$SCRIPT_DIR/x-install.sh"

  echo "${GREEN}info:${RESET} Removed"
}

main_menu() {
  while true; do
    clear
    echo "${AQUA}=== Xray Manager ===${RESET}"
    echo "1. Install"
    echo "2. Update"
    echo "3. Start"
    echo "4. Stop"
    echo "5. Restart"
    echo "6. Status"
    echo "0. Uninstall"
    echo "q. Quit"
    echo
    read -r -p "Select: " choice
    case "$choice" in
      1)
        install_xray
        pause
        ;;
      2)
        update_menu
        ;;
      3)
        start_xray
        pause
        ;;
      4)
        stop_xray
        pause
        ;;
      5)
        restart_xray
        pause
        ;;
      6)
        status_xray
        pause
        ;;
      0)
        remove_xray
        pause
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "Invalid choice"
        pause
        ;;
    esac
  done
}

init_colors
require_root
setup_shortcut
main_menu