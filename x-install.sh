#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
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

random_hex() {
  local len="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex $((len / 2))
  else
    hexdump -v -n $((len / 2)) -e '1/1 "%02x"' /dev/urandom
  fi
}

gen_uuid() {
  if command -v xray >/dev/null 2>&1; then
    xray uuid
  else
    echo "error: xray 未安装，无法生成 UUID" >&2
    return 1
  fi
}

ensure_xray_installed() {
  if [[ ! -x /usr/local/bin/xray ]]; then
    echo "${RED}error:${RESET} 未检测到 xray，请先安装"
    return 1
  fi
}

gen_x25519_keypair() {
  xray x25519
}

extract_xray_field() {
  local label="$1"
  awk -v key="$label" '
    BEGIN { IGNORECASE=1 }
    $0 ~ ("^" key "[[:space:]]*:") {
      sub("^[^:]*:[[:space:]]*", "", $0)
      print $0
      exit
    }
  '
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

  echo "${GREEN}info:${RESET} 配置已写入: $TARGET_CONFIG"
}

install_xray() {
  echo "${AQUA}>>> 安装 Xray（使用官方脚本）${RESET}"

  local uuid domain private_key short_ids public_key

  # 先安装服务
  fetch_official_script
  bash "$OFFICIAL_SCRIPT_LOCAL" install

  ensure_xray_installed

  # 自动生成参数
  uuid="$(gen_uuid)"
  if [[ -z "$uuid" ]]; then
    echo "${RED}error:${RESET} UUID 生成失败"
    return 1
  fi

  while true; do
    domain="$(read -r -p "请输入伪装域名（不能为空）: " _tmp; printf '%s' "$_tmp")"
    if [[ -z "$domain" ]]; then
      echo "${RED}error:${RESET} 伪装域名不能为空"
      continue
    fi
    if ! validate_domain "$domain"; then
      echo "${RED}error:${RESET} 域名格式不正确"
      continue
    fi
    break
  done

  short_ids="$(random_hex 8)"

  local keypair
  keypair="$(gen_x25519_keypair)"
  private_key="$(echo "$keypair" | extract_xray_field "PrivateKey" | xargs)"
  public_key="$(echo "$keypair" | extract_xray_field "Password" | xargs)"
  if [[ -z "$private_key" || -z "$public_key" ]]; then
    echo "${RED}error:${RESET} privateKey / publicKey 生成失败"
    echo "${RED}error:${RESET} 原始输出如下："
    echo "$keypair"
    return 1
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
  # 1. 优先检查核心二进制文件
  # 只要文件在，就说明安装过，不会再误报“待安装”
  if [[ ! -x "/usr/local/bin/xray" ]]; then
    echo "待安装"
    return
  fi

  # 2. 检查服务运行状态
  if systemctl -q is-active xray; then
    echo "${GREEN}运行中${RESET}"
  # 3. 如果没运行，检查是否是因为报错而崩溃 (failed)
  elif systemctl -q is-failed xray; then
    echo "${RED}运行异常 (Failed)${RESET}"
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
  exit 0
}

main_menu() {
  while true; do
    clear
    local status
    status="$(get_xray_status)"
    echo -e "${AQUA}=== Xray 管理菜单 ===${RESET}"
    # 使用 echo -e 确保颜色转义字符正常渲染
    echo -e "状态：${status}"
    echo "====================="
    echo "1. 安装"
    echo "2. 更新"
    echo "3. 启动"
    echo "4. 停止"
    echo "5. 重启"
    echo "99. 卸载"
    echo "0. 退出"
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
      99)
        remove_xray
        ;;
      0)
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
