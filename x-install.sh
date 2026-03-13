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
    echo "${RED}error:${RESET} 璇蜂娇鐢?root 杩愯璇ヨ剼鏈?
    exit 1
  fi
}

pause() {
  echo
  read -r -p "鎸夊洖杞︾户缁?.." _
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
    echo "${RED}error:${RESET} 鏈娴嬪埌 xray锛岃鍏堝畨瑁?
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
    echo "${RED}error:${RESET} 鏈壘鍒?curl 鎴?wget锛屾棤娉曚笅杞藉畼鏂硅剼鏈?
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
    echo "${RED}error:${RESET} 鏈壘鍒?curl 鎴?wget锛屾棤娉曚笅杞介厤缃ā鏉?
    exit 1
  fi
}

setup_shortcut() {
  local target="/usr/local/bin/daili"
  if [[ -e "$target" ]]; then
    return 0
  fi
  if ln -s "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
    echo "${GREEN}info:${RESET} 宸插垱寤哄揩鎹峰懡浠? daili"
  else
    if cp "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
      chmod +x "$target"
      echo "${GREEN}info:${RESET} 宸插鍒跺揩鎹峰懡浠? daili"
    else
      echo "${RED}warning:${RESET} 鏃犳硶鍒涘缓蹇嵎鍛戒护锛岃鎵嬪姩璁剧疆"
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

  echo "${GREEN}info:${RESET} 閰嶇疆宸插啓鍏? $TARGET_CONFIG"
}

install_xray() {
  echo "${AQUA}>>> 瀹夎 Xray锛堜娇鐢ㄥ畼鏂硅剼鏈級${RESET}"

  local uuid domain private_key short_ids public_key

  uuid="$(prompt_value "璇疯緭鍏?UUID锛堝洖杞﹁嚜鍔ㄧ敓鎴愶級: ")"
  if [[ -z "$uuid" ]]; then
    uuid="$(gen_uuid)"
    echo "${GREEN}info:${RESET} 宸茶嚜鍔ㄧ敓鎴?UUID: $uuid"
  fi

  domain="$(prompt_value "璇疯緭鍏ヤ吉瑁呭煙鍚嶏紙鍥炶溅浣跨敤 YOUR_DOMAIN 榛樿鍊硷級: ")"
  if [[ -z "$domain" ]]; then
    domain="www.samsung.com"
  fi
  if ! validate_domain "$domain"; then
    echo "${RED}error:${RESET} 鍩熷悕鏍煎紡涓嶆纭?
    return 1
  fi

  short_ids="$(prompt_value "璇疯緭鍏?shortIds锛堥€楀彿鍒嗛殧锛屽洖杞﹁嚜鍔ㄧ敓鎴?8 浣嶏級: ")"
  if [[ -z "$short_ids" ]]; then
    short_ids="$(random_hex 8)"
    echo "${GREEN}info:${RESET} 宸茶嚜鍔ㄧ敓鎴?shortIds: $short_ids"
  fi

  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" install

  ensure_xray_installed

  private_key="$(prompt_value "璇疯緭鍏?privateKey锛堝洖杞﹁嚜鍔ㄧ敓鎴愶級: ")"
  if [[ -z "$private_key" ]]; then
    local keypair
    keypair="$(gen_x25519_keypair)"
    private_key="$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}')"
    public_key="$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}')"
    echo "${GREEN}info:${RESET} 宸茶嚜鍔ㄧ敓鎴?privateKey / publicKey"
  else
    public_key="$(prompt_value "璇疯緭鍏?publicKey锛堝洖杞﹀皾璇曡嚜鍔ㄦ帹瀵硷級: ")"
    if [[ -z "$public_key" ]]; then
      local derived
      derived="$(/usr/local/bin/xray x25519 -i "$private_key" 2>/dev/null || true)"
      public_key="$(echo "$derived" | awk -F': ' '/Public key/ {print $2}')"
      if [[ -z "$public_key" ]]; then
        public_key="(鏃犳硶鑷姩鎺ㄥ锛岃鎵嬪姩纭)"
      else
        echo "${GREEN}info:${RESET} 宸茶嚜鍔ㄦ帹瀵?publicKey"
      fi
    fi
  fi

  fetch_template
  write_config "$uuid" "$domain" "$private_key" "$short_ids"

  systemctl restart xray
  sleep 1s
  if systemctl -q is-active xray; then
    echo "${GREEN}info:${RESET} Xray 宸插惎鍔?
  else
    echo "${RED}warning:${RESET} Xray 鍚姩澶辫触锛岃妫€鏌ラ厤缃?
  fi

  local ip_addr
  if command -v curl >/dev/null 2>&1; then
    ip_addr="$(curl -s https://api.ipify.org || true)"
  fi
  if [[ -z "$ip_addr" ]]; then
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -z "$ip_addr" ]] && ip_addr="(鏈幏鍙栧埌)"

  echo
  echo "${AQUA}=== 瀹夎缁撴灉 ===${RESET}"
  echo "1. IP: $ip_addr"
  echo "2. UUID: $uuid"
  echo "3. 鍩熷悕: $domain"
  echo "4. public-key: $public_key"
  echo "5. short-id: $short_ids"
}

update_menu() {
  while true; do
    clear
    echo "${AQUA}=== 鏇存柊鑿滃崟 ===${RESET}"
    echo "1. 鏇存柊鍐呮牳"
    echo "2. 鏇存柊 GEO 鏁版嵁"
    echo "0. 杩斿洖"
    echo
    read -r -p "璇烽€夋嫨: " choice
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
        echo "鏃犳晥閫夋嫨"
        pause
        ;;
    esac
  done
}

start_xray() {
  systemctl start xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 宸插惎鍔? || echo "${RED}error:${RESET} 鍚姩澶辫触"
}

stop_xray() {
  systemctl stop xray
  systemctl -q is-active xray && echo "${RED}error:${RESET} 鍋滄澶辫触" || echo "${GREEN}info:${RESET} Xray 宸插仠姝?
}

restart_xray() {
  systemctl restart xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 宸查噸鍚? || echo "${RED}error:${RESET} 閲嶅惎澶辫触"
}

get_xray_status() {
  if ! systemctl list-unit-files | grep -qw 'xray'; then
    echo "寰呭畨瑁?
    return
  fi
  if systemctl -q is-active xray; then
    echo "杩愯涓?
  else
    echo "宸插仠姝?
  fi
}

remove_xray() {
  echo "鈿狅笍 鍗遍櫓鎿嶄綔妫€娴嬶紒"
  echo "鎿嶄綔绫诲瀷锛氬嵏杞藉苟娓呯悊 Xray"
  echo "褰卞搷鑼冨洿锛歑ray 绋嬪簭銆佹湇鍔°€佹棩蹇椼€侀厤缃€丟EO 鏁版嵁銆佸揩鎹峰懡浠?daili銆佺鐞嗚剼鏈€佹ā鏉挎枃浠?
  echo "椋庨櫓璇勪及锛氬嵏杞藉悗鏈嶅姟灏嗕笉鍙敤锛岄厤缃笉鍙仮澶?
  echo
  read -r -p "璇风‘璁ゆ槸鍚︾户缁紵(杈撳叆 y 缁х画): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "宸插彇娑?
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

  echo "${GREEN}info:${RESET} 娓呯悊瀹屾垚"
}

main_menu() {
  while true; do
    clear
    local status
    status="$(get_xray_status)"
    echo "${AQUA}=== Xray 绠＄悊鑿滃崟 ===${RESET}"
    echo "鐘舵€侊細${status}"
    echo "1. 瀹夎"
    echo "2. 鏇存柊"
    echo "3. 鍚姩"
    echo "4. 鍋滄"
    echo "5. 閲嶅惎"
    echo "0. 鍗歌浇"
    echo "q. 閫€鍑?
    echo
    read -r -p "璇烽€夋嫨: " choice
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
      0)
        remove_xray
        pause
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "鏃犳晥閫夋嫨"
        pause
        ;;
    esac
  done
}

init_colors
require_root
setup_shortcut
main_menu
