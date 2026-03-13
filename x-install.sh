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
    echo "${RED}error:${RESET} 鐠囪渹濞囬悽?root 鏉╂劘顢戠拠銉ㄥ壖閺?
    exit 1
  fi
}

pause() {
  echo
  read -r -p "閹稿娲栨潪锔炬埛缂?.." _
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
  if [[ -x /usr/local/bin/xray ]]; then
    /usr/local/bin/xray uuid
  elif command -v xray >/dev/null 2>&1; then
    xray uuid
  else
    echo "error: xray 鏈畨瑁咃紝鏃犳硶鐢熸垚 UUID" >&2
    return 1
  fi
}

ensure_xray_installed() {
  if [[ ! -x /usr/local/bin/xray ]]; then
    echo "${RED}error:${RESET} 閺堫亝顥呭ù瀣煂 xray閿涘矁顕崗鍫濈暔鐟?
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
    echo "${RED}error:${RESET} 閺堫亝澹橀崚?curl 閹?wget閿涘本妫ゅ▔鏇氱瑓鏉炶棄鐣奸弬纭呭壖閺?
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
    echo "${RED}error:${RESET} 閺堫亝澹橀崚?curl 閹?wget閿涘本妫ゅ▔鏇氱瑓鏉炰粙鍘ょ純顔侥侀弶?
    exit 1
  fi
}

setup_shortcut() {
  local target="/usr/local/bin/daili"
  if [[ -e "$target" ]]; then
    return 0
  fi
  if ln -s "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
    echo "${GREEN}info:${RESET} 瀹告彃鍨卞鍝勬彥閹瑰嘲鎳℃禒? daili"
  else
    if cp "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
      chmod +x "$target"
      echo "${GREEN}info:${RESET} 瀹告彃顦查崚璺烘彥閹瑰嘲鎳℃禒? daili"
    else
      echo "${RED}warning:${RESET} 閺冪姵纭堕崚娑樼紦韫囶偅宓庨崨鎴掓姢閿涘矁顕幍瀣З鐠佸墽鐤?
    fi
  fi
}

write_config() {
  local uuid="$1"
  local domain="$2"
  local private_key="$3"
  local short_ids="$4"

  escape_sed() {
    printf '%s' "$1" | sed -e 's/[\\/|&]/\\&/g'
  }

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

  local uuid_esc domain_esc private_key_esc
  uuid_esc="$(escape_sed "$uuid")"
  domain_esc="$(escape_sed "$domain")"
  private_key_esc="$(escape_sed "$private_key")"

  sed -i \
    -e "s|YOUR_UUID|$uuid_esc|g" \
    -e "s|YOUR_PRIVATE_KEY|$private_key_esc|g" \
    -e "s|YOUR_DOMAIN|$domain_esc|g" \
    -e "s|\"shortIds\": \\[\"SHORT_ID\"\\]|\"shortIds\": $short_ids_json|" \
    "$tmp_file"

  install -d "$(dirname "$TARGET_CONFIG")"
  install -m 644 "$tmp_file" "$TARGET_CONFIG"
  rm -f "$tmp_file"

  echo "${GREEN}info:${RESET} 闁板秶鐤嗗鎻掑晸閸? $TARGET_CONFIG"
}

install_xray() {
  echo "${AQUA}>>> 鐎瑰顥?Xray閿涘牅濞囬悽銊ョ暭閺傜鍓奸張顒婄礆${RESET}"

  local uuid domain private_key short_ids public_key

  # 閸忓牆鐣ㄧ憗鍛箛閸?  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" install

  ensure_xray_installed

  # 鐎瑰顥婄€瑰本鍨氶崥搴ｇ埠娑撯偓鏉堟挸鍙嗛柊宥囩枂閸欏倹鏆?  uuid="$(prompt_value "鐠囩柉绶崗?UUID閿涘牆娲栨潪锕佸殰閸斻劎鏁撻幋鎰剁礆: ")"
  if [[ -z "$uuid" ]]; then
    uuid="$(gen_uuid)"
    echo "${GREEN}info:${RESET} 瀹歌尪鍤滈崝銊ф晸閹?UUID: $uuid"
  fi

  while true; do
    domain="$(prompt_value "鐠囩柉绶崗銉ゅ悏鐟佸懎鐓欓崥宥忕礄娑撳秷鍏樻稉铏光敄閿? ")"
    if [[ -z "$domain" ]]; then
      echo "${RED}error:${RESET} 娴碱亣顥婇崺鐔锋倳娑撳秷鍏樻稉铏光敄"
      continue
    fi
    if ! validate_domain "$domain"; then
      echo "${RED}error:${RESET} 閸╃喎鎮曢弽鐓庣础娑撳秵顒滅涵?
      continue
    fi
    break
  done

  short_ids="$(prompt_value "鐠囩柉绶崗?shortIds閿涘牆娲栨潪锕佸殰閸斻劎鏁撻幋?8 娴ｅ稄绱? ")"
  if [[ -z "$short_ids" ]]; then
    short_ids="$(random_hex 8)"
    echo "${GREEN}info:${RESET} 瀹歌尪鍤滈崝銊ф晸閹?shortIds: $short_ids"
  fi

  private_key="$(prompt_value "鐠囩柉绶崗?privateKey閿涘牆娲栨潪锕佸殰閸斻劎鏁撻幋鎰剁礆: ")"
  if [[ -z "$private_key" ]]; then
    local keypair
    keypair="$(gen_x25519_keypair)"
    private_key="$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}' | xargs)"
    public_key="$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}' | xargs)"
    if [[ -z "$private_key" || -z "$public_key" ]]; then
      echo "${RED}error:${RESET} privateKey / publicKey 閻㈢喐鍨氭径杈Е"
      return 1
    fi
    echo "${GREEN}info:${RESET} 瀹歌尪鍤滈崝銊ф晸閹?privateKey / publicKey"
  else
    public_key="$(prompt_value "鐠囩柉绶崗?publicKey閿涘牆娲栨潪锕€鐨剧拠鏇″殰閸斻劍甯圭€电》绱? ")"
    if [[ -z "$public_key" ]]; then
      local derived
      derived="$(/usr/local/bin/xray x25519 -i "$private_key" 2>/dev/null || true)"
      public_key="$(echo "$derived" | awk -F': ' '/Public key/ {print $2}' | xargs)"
      if [[ -z "$public_key" ]]; then
        public_key="閺冪姵纭堕懛顏勫З閹恒劌顕遍敍宀冾嚞閹靛濮╃涵顔款吇"
      else
        echo "${GREEN}info:${RESET} 瀹歌尪鍤滈崝銊﹀腹鐎?publicKey"
      fi
    fi
  fi

  fetch_template
  write_config "$uuid" "$domain" "$private_key" "$short_ids"

  systemctl restart xray
  sleep 1s
  if systemctl -q is-active xray; then
    echo "${GREEN}info:${RESET} Xray 瀹告彃鎯庨崝?
  else
    echo "${RED}warning:${RESET} Xray 閸氼垰濮╂径杈Е閿涘矁顕Λ鈧弻銉╁帳缂?
  fi

  local ip_addr
  if command -v curl >/dev/null 2>&1; then
    ip_addr="$(curl -s https://api.ipify.org || true)"
  fi
  if [[ -z "$ip_addr" ]]; then
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -z "$ip_addr" ]] && ip_addr="(閺堫亣骞忛崣鏍у煂)"

  echo
  echo "${AQUA}=== 鐎瑰顥婄紒鎾寸亯 ===${RESET}"
  echo "1. IP: $ip_addr"
  echo "2. UUID: $uuid"
  echo "3. 閸╃喎鎮? $domain"
  echo "4. public-key: $public_key"
  echo "5. short-id: $short_ids"
}

update_menu() {
  while true; do
    clear
    echo "${AQUA}=== 閺囧瓨鏌婇懣婊冨礋 ===${RESET}"
    echo "1. 閺囧瓨鏌婇崘鍛壋"
    echo "2. 閺囧瓨鏌?GEO 閺佺増宓?
    echo "0. 鏉╂柨娲?
    echo
    read -r -p "鐠囩兘鈧瀚? " choice
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
        echo "閺冪姵鏅ラ柅澶嬪"
        pause
        ;;
    esac
  done
}

start_xray() {
  systemctl start xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 瀹告彃鎯庨崝? || echo "${RED}error:${RESET} 閸氼垰濮╂径杈Е"
}

stop_xray() {
  systemctl stop xray
  systemctl -q is-active xray && echo "${RED}error:${RESET} 閸嬫粍顒涙径杈Е" || echo "${GREEN}info:${RESET} Xray 瀹告彃浠犲?
}

restart_xray() {
  systemctl restart xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 瀹告煡鍣搁崥? || echo "${RED}error:${RESET} 闁插秴鎯庢径杈Е"
}

get_xray_status() {
  if ! systemctl list-unit-files | grep -qw 'xray'; then
    echo "瀵板懎鐣ㄧ憗?
    return
  fi
  if systemctl -q is-active xray; then
    echo "鏉╂劘顢戞稉?
  else
    echo "瀹告彃浠犲?
  fi
}

detect_pkg_manager() {
  if command -v apt >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v zypper >/dev/null 2>&1; then
    echo "zypper"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo ""
  fi
}

install_pkg() {
  local pkg="$1"
  local pm
  pm="$(detect_pkg_manager)"
  if [[ -z "$pm" ]]; then
    echo "${RED}error:${RESET} 閺堫亝顥呭ù瀣煂閸欘垳鏁ら惃鍕瘶缁狅紕鎮婇崳?
    return 1
  fi
  echo "閳跨媴绗?閸楅亶娅撻幙宥勭稊濡偓濞村绱?
  echo "閹垮秳缍旂猾璇茬€烽敍姘暔鐟佸懍绶风挧鏍у瘶"
  echo "瑜板崬鎼烽懠鍐ㄦ纯閿涙氨閮寸紒鐔峰瘶缁狅紕鎮婇崳銊ュ弿鐏炩偓鐎瑰顥?$pkg"
  echo "妞嬪酣娅撶拠鍕強閿涙岸娓剁憰浣戒粓缂冩埊绱濋崣顖濆厴娣囶喗鏁肩化鑽ょ埠鏉烆垯娆㈠┃鎰Ц閹?
  echo
  read -r -p "鐠囬鈥樼拋銈嗘Ц閸氾妇鎴风紒顓ㄧ吹(鏉堟挸鍙?y 缂佈呯敾): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "瀹告彃褰囧☉?
    return 1
  fi
  case "$pm" in
    apt)
      apt update && apt install -y "$pkg"
      ;;
    dnf)
      dnf install -y "$pkg"
      ;;
    yum)
      yum install -y "$pkg"
      ;;
    zypper)
      zypper install -y "$pkg"
      ;;
    pacman)
      pacman -Syy --noconfirm "$pkg"
      ;;
  esac
}

check_deps() {
  local ok=1
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "${RED}warning:${RESET} 閺堫亝顥呭ù瀣煂 curl 閹?wget"
    install_pkg "curl" || ok=0
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "${RED}warning:${RESET} 閺堫亝顥呭ù瀣煂 unzip"
    install_pkg "unzip" || ok=0
  fi
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "${RED}error:${RESET} 娴犲秵婀Λ鈧ù瀣煂 curl 閹?wget"
    ok=0
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "${RED}error:${RESET} 娴犲秵婀Λ鈧ù瀣煂 unzip"
    ok=0
  fi
  if [[ "$ok" -eq 0 ]]; then
    return 1
  fi
}

remove_xray() {
  echo "閳跨媴绗?閸楅亶娅撻幙宥勭稊濡偓濞村绱?
  echo "閹垮秳缍旂猾璇茬€烽敍姘祻鏉炶棄鑻熷〒鍛倞 Xray"
  echo "瑜板崬鎼烽懠鍐ㄦ纯閿涙瓚ray 缁嬪绨妴浣规箛閸斅扳偓浣规）韫囨ぜ鈧線鍘ょ純顔衡偓涓烢O 閺佺増宓侀妴浣告彥閹瑰嘲鎳℃禒?daili閵嗕胶顓搁悶鍡氬壖閺堫兙鈧焦膩閺夋寧鏋冩禒?
  echo "妞嬪酣娅撶拠鍕強閿涙艾宓忔潪钘夋倵閺堝秴濮熺亸鍡曠瑝閸欘垳鏁ら敍宀勫帳缂冾喕绗夐崣顖涗划婢?
  echo
  read -r -p "鐠囬鈥樼拋銈嗘Ц閸氾妇鎴风紒顓ㄧ吹(鏉堟挸鍙?y 缂佈呯敾): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "瀹告彃褰囧☉?
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

  echo "${GREEN}info:${RESET} 濞撳懐鎮婄€瑰本鍨?
}

main_menu() {
  while true; do
    clear
    local status
    status="$(get_xray_status)"
    echo "${AQUA}=== Xray 缁狅紕鎮婇懣婊冨礋 ===${RESET}"
    echo "閻樿埖鈧緤绱?{status}"
    echo "1. 鐎瑰顥?
    echo "2. 閺囧瓨鏌?
    echo "3. 閸氼垰濮?
    echo "4. 閸嬫粍顒?
    echo "5. 闁插秴鎯?
    echo "0. 閸楁瓕娴?
    echo "q. 闁偓閸?
    echo
    read -r -p "鐠囩兘鈧瀚? " choice
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
        echo "閺冪姵鏅ラ柅澶嬪"
        pause
        ;;
    esac
  done
}

init_colors
require_root
check_deps
setup_shortcut
main_menu
