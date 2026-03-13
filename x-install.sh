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
    echo "${RED}error:${RESET} 闁荤姴娲╁〒瑙勭箾閸ヮ剚鍋?root 闁哄鏅滈崝姗€銆侀幋鐘冲珰闁靛鍔屾竟鏍煛?
    exit 1
  fi
}

pause() {
  echo
  read -r -p "闂佸湱顭堥ˇ顖毭洪弽銊﹀闁挎梻鍋撻崺娑氱磽?.." _
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
    echo "${RED}error:${RESET} 闂佸搫鐗滄禍婵嬎夐崨顒煎湱鈧綆浜滈悡?xray闂佹寧绋戦惌渚€顢氶鍕闁割偅绻勯弳鏃堟偡?
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
    echo "${RED}error:${RESET} 闂佸搫鐗滄禍婵囩珶濮椻偓瀹?curl 闂?wget闂佹寧绋戦張顒€螞閵堝應鏋栭柡鍥ㄦ皑閻熸捇寮堕悙鑸殿棄闁伙絽銈稿顒傛兜閸涱厼顥涢梺?
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
    echo "${RED}error:${RESET} 闂佸搫鐗滄禍婵囩珶濮椻偓瀹?curl 闂?wget闂佹寧绋戦張顒€螞閵堝應鏋栭柡鍥ㄦ皑閻熸捇寮堕悙鎵煓闁告ǜ鍊楃槐鏃堫敊娓氥儰绶氬?
    exit 1
  fi
}

setup_shortcut() {
  local target="/usr/local/bin/daili"
  if [[ -e "$target" ]]; then
    return 0
  fi
  if ln -s "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
    echo "${GREEN}info:${RESET} 閻庣懓鎲¤ぐ鍐垂閸楃儐鍤堥柛婵嗗瑜般儵鏌熼悷鏉挎Щ闁规枼鍓濈粋? daili"
  else
    if cp "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
      chmod +x "$target"
      echo "${GREEN}info:${RESET} 閻庣懓鎲¤ぐ鍐囬弻銉ョ閻犺櫣鍎よぐ銉╂煙閻熸澘妲婚柟鏂ュ墲缁? daili"
    else
      echo "${RED}warning:${RESET} 闂佸搫鍟版慨鐢垫兜閸洖绀嗘繛鎴烆焽缁憋箓鐓崶璺轰簼鐎规挸閰ｅ畷銊╁箣閹烘挸袘闂佹寧绋戦惌渚€顢氶鍕閻庯綆浜滆闁荤姳绀佹晶浠嬫偪?
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

  echo "${GREEN}info:${RESET} 闂備焦婢樼粔鍫曟偪閸℃鍟呴柟缁樺笒閺呮悂鏌? $TARGET_CONFIG"
}

install_xray() {
  echo "${AQUA}>>> 闁诲海鎳撻ˇ鎶剿?Xray闂佹寧绋戦悧鍛箾閸ヮ剚鍋ㄩ柕濞垮劤閺嗩參鏌￠崒婊庢敯闁告挸銈稿鐢割敆婵犲嫮顦?{RESET}"

  local uuid domain private_key short_ids public_key

  uuid="$(prompt_value "闁荤姴娲ㄩ弻澶屾椤撱垹绀?UUID闂佹寧绋戦悧鍡椕洪弽銊﹀闁挎洑绀佸▓浼存煕閺傝濡块柡浣规崌楠炲骞囬崜浣侯槴: ")"
  if [[ -z "$uuid" ]]; then
    uuid="$(gen_uuid)"
    echo "${GREEN}info:${RESET} 閻庤鐡曠亸顏堝吹濠婂牆绀夐柕濞у嫭娅㈤梺?UUID: $uuid"
  fi

  domain="$(prompt_value "闁荤姴娲ㄩ弻澶屾椤撱垹绀傞柕澶堝€曢幃蹇涙偡娴ｅ憡鍣归柣鎾寸懇瀹曘儱顓艰箛鏇狀槱闂佹悶鍎抽崑鐘测攦閸涱喗濯撮悹鎭掑妽閺?YOUR_DOMAIN 婵帗绋掗…鍫ヮ敇婵犳艾纾圭痪顓㈩棑缁€? ")"
  if [[ -z "$domain" ]]; then
    domain="www.samsung.com"
  fi
  if ! validate_domain "$domain"; then
    echo "${RED}error:${RESET} 闂佺硶鏅濋崰搴ㄥ箖閺囥垹鍐€闁绘挸娴风涵鈧繛鎴炴尭缁夌敻顢楀鍛厹?
    return 1
  fi

  short_ids="$(prompt_value "闁荤姴娲ㄩ弻澶屾椤撱垹绀?shortIds闂佹寧绋戦悧鎾诲焵椤掍緡娈旂憸鏉挎健瀹曟岸宕卞☉娆樺悩闂佹寧绋戦懟顖毭洪弽銊﹀闁挎洑绀佸▓浼存煕閺傝濡块柡浣规崌楠?8 婵炶揪绲界粙鍕? ")"
  if [[ -z "$short_ids" ]]; then
    short_ids="$(random_hex 8)"
    echo "${GREEN}info:${RESET} 閻庤鐡曠亸顏堝吹濠婂牆绀夐柕濞у嫭娅㈤梺?shortIds: $short_ids"
  fi

  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" install

  ensure_xray_installed

  private_key="$(prompt_value "闁荤姴娲ㄩ弻澶屾椤撱垹绀?privateKey闂佹寧绋戦悧鍡椕洪弽銊﹀闁挎洑绀佸▓浼存煕閺傝濡块柡浣规崌楠炲骞囬崜浣侯槴: ")"
  if [[ -z "$private_key" ]]; then
    local keypair
    keypair="$(gen_x25519_keypair)"
    private_key="$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}')"
    public_key="$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}')"
    echo "${GREEN}info:${RESET} 閻庤鐡曠亸顏堝吹濠婂牆绀夐柕濞у嫭娅㈤梺?privateKey / publicKey"
  else
    public_key="$(prompt_value "闁荤姴娲ㄩ弻澶屾椤撱垹绀?publicKey闂佹寧绋戦悧鍡椕洪弽銊﹀闁挎洍鍋撻柣銊ュ⒔閹风娀寮撮垾铏唶闂佸憡鏌ｉ崝宥囨暜閸︻厸鍋撻悽鐐光偓瀣? ")"
    if [[ -z "$public_key" ]]; then
      local derived
      derived="$(/usr/local/bin/xray x25519 -i "$private_key" 2>/dev/null || true)"
      public_key="$(echo "$derived" | awk -F': ' '/Public key/ {print $2}')"
      if [[ -z "$public_key" ]]; then
        public_key="无法自动推导，请手动确认"
      else
        echo "${GREEN}info:${RESET} 閻庤鐡曠亸顏堝吹濠婂牆绀夐柕濠忕畱閼靛綊鎮?publicKey"
      fi
    fi
  fi

  fetch_template
  write_config "$uuid" "$domain" "$private_key" "$short_ids"

  systemctl restart xray
  sleep 1s
  if systemctl -q is-active xray; then
    echo "${GREEN}info:${RESET} Xray 閻庣懓鎲¤ぐ鍐箚鎼淬劌绀?
  else
    echo "${RED}warning:${RESET} Xray 闂佸憡鍑归崹鐗堟叏閳哄倸绶為弶鍫亯琚濋梺鎸庣☉閻線顢氶鈧灋闁逞屽墴瀵濡烽埡浣歌祴缂?
  fi

  local ip_addr
  if command -v curl >/dev/null 2>&1; then
    ip_addr="$(curl -s https://api.ipify.org || true)"
  fi
  if [[ -z "$ip_addr" ]]; then
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -z "$ip_addr" ]] && ip_addr="(闂佸搫鐗滄禍锝夌嵁韫囨稑鐭楅柡宓啰鍘?"

  echo
  echo "${AQUA}=== 闁诲海鎳撻ˇ鎶剿夋繝鍕＜闁规儳顕禍?===${RESET}"
  echo "1. IP: $ip_addr"
  echo "2. UUID: $uuid"
  echo "3. 闂佺硶鏅濋崰搴ㄥ箖? $domain"
  echo "4. public-key: $public_key"
  echo "5. short-id: $short_ids"
}

update_menu() {
  while true; do
    clear
    echo "${AQUA}=== 闂佸搫娲ら悺銊╁蓟婵犲洦鍤曟繝濠傚暙缁€?===${RESET}"
    echo "1. 闂佸搫娲ら悺銊╁蓟婵犲洤绀冮柛娑卞枤婢?
    echo "2. 闂佸搫娲ら悺銊╁蓟?GEO 闂佽桨鑳舵晶妤€鐣?
    echo "0. 闁哄鏅滈弻銊ッ?
    echo
    read -r -p "闁荤姴娲ㄩ崗姗€鍩€椤掆偓椤︽壆鈧? " choice
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
        echo "闂佸搫鍟版慨鐢稿疾閵夆晜鐒诲璺侯儏椤?
        pause
        ;;
    esac
  done
}

start_xray() {
  systemctl start xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 閻庣懓鎲¤ぐ鍐箚鎼淬劌绀? || echo "${RED}error:${RESET} 闂佸憡鍑归崹鐗堟叏閳哄倸绶為弶鍫亯琚?
}

stop_xray() {
  systemctl stop xray
  systemctl -q is-active xray && echo "${RED}error:${RESET} 闂佺顑嗙划宥夘敆濞戞瑥绶為弶鍫亯琚? || echo "${GREEN}info:${RESET} Xray 閻庣懓鎲¤ぐ鍐╃閻樺樊娼?
}

restart_xray() {
  systemctl restart xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 閻庣懓鎲￠悡锟犲闯閹间礁瑙? || echo "${RED}error:${RESET} 闂備焦褰冪粔鎾箚鎼淬垹绶為弶鍫亯琚?
}

get_xray_status() {
  if ! systemctl list-unit-files | grep -qw 'xray'; then
    echo "閻庡灚婢橀幊搴ㄦ偩閵娧勫晳?
    return
  fi
  if systemctl -q is-active xray; then
    echo "闁哄鏅滈崝姗€銆侀幋鐐碘枖?
  else
    echo "閻庣懓鎲¤ぐ鍐╃閻樺樊娼?
  fi
}

remove_xray() {
  echo "闂佸疇娉曟刊瀵哥箔?闂佸憡顨婃禍璺衡枍閹捐绠肩€广儱瀚粙濠冧繆椤愮喎浜惧┑鐐存綑椤戞垹妲?
  echo "闂佺懓鐏濈粔宕囩礊閺冨倻灏甸悹鍥皺閳ь剛鍏橀弫宥咁潩椤掆偓缁佸寮堕悙鑸殿棄闁艰崵鍠庨妴鎺楀川椤栨稑鈧?Xray"
  echo "閻熸粍婢樺畷顒勫箹閻戣姤鍤戦柛鎰╁妽缁绢垶鏌ㄥ☉娆戞憥ray 缂備礁顑呴鍛姳椤撱垹违濞达綀顫夌粻娑㈡煕閺傚懏澹嬮崑鎾存媴鐟欏嫸绱氶棅顐㈡处閵囨粓鍩€椤戣法绐旈柛妯稿€楃槐鏃堫敊鐞涒€充壕濞戞挾鍎甇 闂佽桨鑳舵晶妤€鐣垫笟鈧俊瀛樻媴閸涘﹤娓愰梺鍦嚀閸㈡煡骞婇埄鍐浄?daili闂侀潧妫旈懗鍫曨敇閹间焦鍋犻柛鈩冭壘婢规牠鏌￠崼顐㈠幍闁逞屽厸閻掞箒鍟梺鍝勵槹鐎笛囧几閸愨晝顩?
  echo "婵＄偛顑呴柊锝呪枍閹捐埖瀚氶柛鏇ㄤ簻瀵兘鏌ㄥ☉娆掑鐎规挸绻戝顏堟寠婢跺鈧敻鏌￠崼婵埿㈠┑顔惧枔娴滄悂宕遍弴鐘垫喒闂佸憡鐟崹鎶藉极閵堝鏅€光偓閸曨偄璧嬬紓鍌氬枤閸犳洜绮径鎰煑妞ゆ牗绋愰崚鎺戭熆?
  echo
  read -r -p "闁荤姴娲ˉ鎾诲灳濡吋濯奸柕鍫濇绗戦梺鍛婄啲婵″洭骞嬫搴ｇ＜妞ゆ挶鍔庨崥?闁哄鐗婇幐鎼佸矗?y 缂傚倷缍€閸涱垱鏆?: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "閻庣懓鎲¤ぐ鍐亹閸パ€妲?
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

  echo "${GREEN}info:${RESET} 濠电偞鎸搁幊鎰板箖婵犲嫧鍋撻悷鐗堟拱闁?
}

main_menu() {
  while true; do
    clear
    local status
    status="$(get_xray_status)"
    echo "${AQUA}=== Xray 缂備胶濯寸槐鏇㈠箖婵犲洦鍤曟繝濠傚暙缁€?===${RESET}"
    echo "闂佺粯顭堥崺鏍焵椤戣法绛忕紒?{status}"
    echo "1. 闁诲海鎳撻ˇ鎶剿?
    echo "2. 闂佸搫娲ら悺銊╁蓟?
    echo "3. 闂佸憡鍑归崹鐗堟叏?
    echo "4. 闂佺顑嗙划宥夘敆?
    echo "5. 闂備焦褰冪粔鎾箚?
    echo "0. 闂佸憡顨嗛悺鏇灻?
    echo "q. 闂備緡鍋€閸嬫捇鏌?
    echo
    read -r -p "闁荤姴娲ㄩ崗姗€鍩€椤掆偓椤︽壆鈧? " choice
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
        echo "闂佸搫鍟版慨鐢稿疾閵夆晜鐒诲璺侯儏椤?
        pause
        ;;
    esac
  done
}

init_colors
require_root
setup_shortcut
main_menu
