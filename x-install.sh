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
    echo "${RED}error:${RESET} 请使用 root 运行该脚本"
    exit 1
  fi
}

pause() {
  echo
  read -r -p "按回车继续..." _
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
    echo "${RED}error:${RESET} 未检测到 xray，请先安装"
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
    echo "${RED}error:${RESET} 未找到 curl 或 wget，无法下载官方脚本"
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
    echo "${RED}error:${RESET} 未找到 curl 或 wget，无法下载配置模板"
    exit 1
  fi
}

setup_shortcut() {
  local target="/usr/local/bin/daili"
  if [[ -e "$target" ]]; then
    return 0
  fi
  if ln -s "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
    echo "${GREEN}info:${RESET} 已创建快捷命令: daili"
  else
    if cp "$SCRIPT_DIR/x-install.sh" "$target" 2>/dev/null; then
      chmod +x "$target"
      echo "${GREEN}info:${RESET} 已复制快捷命令: daili"
    else
      echo "${RED}warning:${RESET} 无法创建快捷命令，请手动设置"
    fi
  fi
}

write_config() {
  local uuid="$1"
  local domain="$2"
  local private_key="$3"
  local short_ids="$4"

  escape_sed() {
    printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
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

  echo "${GREEN}info:${RESET} 配置已写入: $TARGET_CONFIG"
}

install_xray() {
  echo "${AQUA}>>> 安装 Xray（使用官方脚本）${RESET}"

  local uuid domain private_key short_ids public_key

  uuid="$(prompt_value "请输入 UUID（回车自动生成）: ")"
  if [[ -z "$uuid" ]]; then
    uuid="$(gen_uuid)"
    echo "${GREEN}info:${RESET} 已自动生成 UUID: $uuid"
  fi

  domain="$(prompt_value "请输入伪装域名（回车使用 www.samsung.com）: ")"
  if [[ -z "$domain" ]]; then
    domain="www.samsung.com"
  fi
  if ! validate_domain "$domain"; then
    echo "${RED}error:${RESET} 域名格式不正确"
    return 1
  fi

  short_ids="$(prompt_value "请输入 shortIds（逗号分隔，回车自动生成 8 位）: ")"
  if [[ -z "$short_ids" ]]; then
    short_ids="$(random_hex 8)"
    echo "${GREEN}info:${RESET} 已自动生成 shortIds: $short_ids"
  fi

  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" install

  ensure_xray_installed

  private_key="$(prompt_value "请输入 privateKey（回车自动生成）: ")"
  if [[ -z "$private_key" ]]; then
    local keypair
    keypair="$(gen_x25519_keypair)"
    private_key="$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}')"
    public_key="$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}')"
    echo "${GREEN}info:${RESET} 已自动生成 privateKey / publicKey"
  else
    public_key="$(prompt_value "请输入 publicKey（回车尝试自动推导）: ")"
    if [[ -z "$public_key" ]]; then
      local derived
      derived="$(/usr/local/bin/xray x25519 -i "$private_key" 2>/dev/null || true)"
      public_key="$(echo "$derived" | awk -F': ' '/Public key/ {print $2}')"
      if [[ -z "$public_key" ]]; then
        public_key="无法自动推导，请手动确认"
      else
        echo "${GREEN}info:${RESET} 已自动推导 publicKey"
      fi
    fi
  fi

  fetch_template
  write_config "$uuid" "$domain" "$private_key" "$short_ids"

  systemctl restart xray
  sleep 1s
  if systemctl -q is-active xray; then
    echo "${GREEN}info:${RESET} Xray 已启动"
  else
    echo "${RED}warning:${RESET} Xray 启动失败，请检查配置"
  fi

  local ip_addr
  if command -v curl >/dev/null 2>&1; then
    ip_addr="$(curl -s https://api.ipify.org || true)"
  fi
  if [[ -z "$ip_addr" ]]; then
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -z "$ip_addr" ]] && ip_addr="(未获取到)"

  echo
  echo "${AQUA}=== 安装结果 ===${RESET}"
  echo "1. IP: $ip_addr"
  echo "2. UUID: $uuid"
  echo "3. 域名: $domain"
  echo "4. public-key: $public_key"
  echo "5. short-id: $short_ids"
}

update_menu() {
  while true; do
    clear
    echo "${AQUA}=== 更新菜单 ===${RESET}"
    echo "1. 更新内核"
    echo "2. 更新 GEO 数据"
    echo "0. 返回"
    echo
    read -r -p "请选择: " choice
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
        echo "无效选择"
        pause
        ;;
    esac
  done
}

start_xray() {
  systemctl start xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 已启动" || echo "${RED}error:${RESET} 启动失败"
}

stop_xray() {
  systemctl stop xray
  systemctl -q is-active xray && echo "${RED}error:${RESET} 停止失败" || echo "${GREEN}info:${RESET} Xray 已停止"
}

restart_xray() {
  systemctl restart xray
  systemctl -q is-active xray && echo "${GREEN}info:${RESET} Xray 已重启" || echo "${RED}error:${RESET} 重启失败"
}

get_xray_status() {
  if ! systemctl list-unit-files | grep -qw 'xray'; then
    echo "待安装"
    return
  fi
  if systemctl -q is-active xray; then
    echo "运行中"
  else
    echo "已停止"
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
    echo "${RED}error:${RESET} 未检测到可用的包管理器"
    return 1
  fi
  echo "⚠️ 危险操作检测！"
  echo "操作类型：安装依赖包"
  echo "影响范围：系统包管理器全局安装 $pkg"
  echo "风险评估：需要联网，可能修改系统软件源状态"
  echo
  read -r -p "请确认是否继续？(输入 y 继续): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消"
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
    echo "${RED}warning:${RESET} 未检测到 curl 或 wget"
    install_pkg "curl" || ok=0
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "${RED}warning:${RESET} 未检测到 unzip"
    install_pkg "unzip" || ok=0
  fi
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "${RED}error:${RESET} 仍未检测到 curl 或 wget"
    ok=0
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "${RED}error:${RESET} 仍未检测到 unzip"
    ok=0
  fi
  if [[ "$ok" -eq 0 ]]; then
    return 1
  fi
}

remove_xray() {
  echo "⚠️ 危险操作检测！"
  echo "操作类型：卸载并清理 Xray"
  echo "影响范围：Xray 程序、服务、日志、配置、GEO 数据、快捷命令 daili、管理脚本、模板文件"
  echo "风险评估：卸载后服务将不可用，配置不可恢复"
  echo
  read -r -p "请确认是否继续？(输入 y 继续): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消"
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

  echo "${GREEN}info:${RESET} 清理完成"
}

main_menu() {
  while true; do
    clear
    local status
    status="$(get_xray_status)"
    echo "${AQUA}=== Xray 管理菜单 ===${RESET}"
    echo "状态：${status}"
    echo "1. 安装"
    echo "2. 更新"
    echo "3. 启动"
    echo "4. 停止"
    echo "5. 重启"
    echo "0. 卸载"
    echo "q. 退出"
    echo
    read -r -p "请选择: " choice
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
        echo "无效选择"
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
