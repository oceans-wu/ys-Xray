#!/usr/bin/env bash

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
magenta=$(tput setaf 5)
aoi=$(tput setaf 6)
reset=$(tput sgr0)

DAT_PATH=${DAT_PATH:-/usr/local/share/xray}

JSON_PATH=${JSON_PATH:-/usr/local/etc/xray}

HOME_PATH=${HOME_PATH:-/etc/xray/yisu}




if [[ -f '/etc/systemd/system/xray.service' ]] && [[ -f '/usr/local/bin/xray' ]]; then
  XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=1
else
  XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=0
fi

# Xray 当前版本
CURRENT_VERSION=''

# Xray 最新版本
RELEASE_LATEST=''

# Xray 最新预发布/发布版本
PRE_RELEASE_LATEST=''

# Xray 将安装此版本
INSTALL_VERSION=''

# install
INSTALL='0'

# 装地理数据
INSTALL_GEODATA='0'

# remove
REMOVE='0'

# help
HELP='0'

# check
CHECK='0'

# --force
FORCE='0'

# --beta
BETA='0'

# --install-user ?
INSTALL_USER=''

# --without-geodata
NO_GEODATA='0'

# --without-logfiles
NO_LOGFILES='0'

# --no-update-service
N_UP_SERVICE='0'

# --reinstall
REINSTALL='0'

# --version ?
SPECIFIED_VERSION=''

# --local ?
LOCAL_FILE=''

# --proxy ?
PROXY=''

# --purge
PURGE='0'

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

systemd_cat_config() {
  if systemd-analyze --help | grep -qw 'cat-config'; then
    systemd-analyze --no-pager cat-config "$@"
    echo
  else
    echo "${aoi}~~~~~~~~~~~~~~~~"
    cat "$@" "$1".d/*
    echo "${aoi}~~~~~~~~~~~~~~~~"
    warn_log "当前操作系统上的systemd版本过低."
    warn_log "请考虑升级systemd或操作系统."
    echo
  fi
}

check_if_running_as_root() {
  #如果要作为其他用户运行，请将$EUID修改为该用户所有
  if [[ "$EUID" -ne '0' ]]; then
    error_log "您必须以root身份运行此脚本!"
    exit 1
  fi
}

identify_the_operating_system_and_architecture() {
  if [[ "$(uname)" == 'Linux' ]]; then
    case "$(uname -m)" in
      'i386' | 'i686')
        MACHINE='32'
        ;;
      'amd64' | 'x86_64')
        MACHINE='64'
        ;;
      'armv5tel')
        MACHINE='arm32-v5'
        ;;
      'armv6l')
        MACHINE='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
      'armv7' | 'armv7l')
        MACHINE='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
      'armv8' | 'aarch64')
        MACHINE='arm64-v8a'
        ;;
      'mips')
        MACHINE='mips32'
        ;;
      'mipsle')
        MACHINE='mips32le'
        ;;
      'mips64')
        MACHINE='mips64'
        lscpu | grep -q "Little Endian" && MACHINE='mips64le'
        ;;
      'mips64le')
        MACHINE='mips64le'
        ;;
      'ppc64')
        MACHINE='ppc64'
        ;;
      'ppc64le')
        MACHINE='ppc64le'
        ;;
      'riscv64')
        MACHINE='riscv64'
        ;;
      's390x')
        MACHINE='s390x'
        ;;
      *)
        error_log "不支持该体系结构."
        exit 1
        ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      error_log "不要使用过时的Linux发行版."
      exit 1
    fi
    # 请勿将此判断条件与以下判断条件组合
    ## 请注意像Gentoo这样的Linux发行版，它的内核支持在Systemd和OpenRC之间切换
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
      true
    elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
      true
    else
      error_log "仅支持使用systemd的Linux发行版."
      exit 1
    fi
    if [[ "$(type -P apt)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
      PACKAGE_MANAGEMENT_REMOVE='apt purge'
      package_provide_tput='ncurses-bin'
    elif [[ "$(type -P dnf)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
      PACKAGE_MANAGEMENT_REMOVE='dnf remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P yum)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='yum -y install'
      PACKAGE_MANAGEMENT_REMOVE='yum remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P zypper)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
      PACKAGE_MANAGEMENT_REMOVE='zypper remove'
      package_provide_tput='ncurses-utils'
    elif [[ "$(type -P pacman)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
      PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
      package_provide_tput='ncurses'
     elif [[ "$(type -P emerge)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='emerge -v'
      PACKAGE_MANAGEMENT_REMOVE='emerge -Cv'
      package_provide_tput='ncurses'
    else
      error_log "此脚本不支持此操作系统中的包管理器."
      exit 1
    fi
  else
    error_log "不支持此操作系统."
    exit 1
  fi
}

## 处理参数的演示功能
judgment_parameters() {
  local local_install='0'
  local temp_version='0'
#  while [[ "$#" -gt '0' ]]; do
#    case "$1" in
#      'install')
#        INSTALL='1'
#        ;;
#      'install-geodata')
#        INSTALL_GEODATA='1'
#        ;;
#      'remove')
#        REMOVE='1'
#        ;;
#      'help')
#        HELP='1'
#        ;;
#      'check')
#        CHECK='1'
#        ;;
#      '--without-geodata')
#        NO_GEODATA='1'
#        ;;
#      '--without-logfiles')
#        NO_LOGFILES='1'
#        ;;
#      '--purge')
#        PURGE='1'
#        ;;
#      '--version')
#        if [[ -z "$2" ]]; then
#          echo "error: 请指定正确的版本."
#          exit 1
#        fi
#        temp_version='1'
#        SPECIFIED_VERSION="$2"
#        shift
#        ;;
#      '-f' | '--force')
#        FORCE='1'
#        ;;
#      '--beta')
#        BETA='1'
#        ;;
#      '-l' | '--local')
#        local_install='1'
#        if [[ -z "$2" ]]; then
#          echo "error: 请指定正确的本地文件."
#          exit 1
#        fi
#        LOCAL_FILE="$2"
#        shift
#        ;;
#      '-p' | '--proxy')
#        if [[ -z "$2" ]]; then
#          echo "error: 请指定代理服务器地址."
#          exit 1
#        fi
#        PROXY="$2"
#        shift
#        ;;
#      '-u' | '--install-user')
#        if [[ -z "$2" ]]; then
#          echo "error: 请指定安装用户.}"
#          exit 1
#        fi
#        INSTALL_USER="$2"
#        shift
#        ;;
#      '--reinstall')
#        REINSTALL='1'
#        ;;
#      '--no-update-service')
#        N_UP_SERVICE='1'
#        ;;
#      *)
#        echo "$0: unknown option -- -"
#        exit 1
#        ;;
#    esac
#    shift
#  done
#  if ((INSTALL+INSTALL_GEODATA+HELP+CHECK+REMOVE==0)); then
#    INSTALL='1'
#  elif ((INSTALL+INSTALL_GEODATA+HELP+CHECK+REMOVE>1)); then
#    echo '您只能选择一个操作.'
#    exit 1
#  fi
#  if [[ "$INSTALL" -eq '1' ]] && ((temp_version+local_install+REINSTALL+BETA>1)); then
#    echo "--version,--reinstall,--beta and --local 不能一起使用."
#    exit 1
#  fi
}

check_install_user() {
  if [[ -z "$INSTALL_USER" ]]; then
    if [[ -f '/usr/local/bin/xray' ]]; then
      INSTALL_USER="$(grep '^[ '$'\t]*User[ '$'\t]*=' /etc/systemd/system/xray.service | tail -n 1 | awk -F = '{print $2}' | awk '{print $1}')"
      if [[ -z "$INSTALL_USER" ]]; then
        INSTALL_USER='root'
      fi
    else
      INSTALL_USER='nobody'
    fi
  fi
  if ! id $INSTALL_USER > /dev/null 2>&1; then
    warn_log "用户 '$INSTALL_USER' 这是无效的"
    exit 1
  fi
  INSTALL_USER_UID="$(id -u $INSTALL_USER)"
  INSTALL_USER_GID="$(id -g $INSTALL_USER)"
}

install_software() {
  package_name="$1"
  file_to_detect="$2"
  type -P "$file_to_detect" > /dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name"; then
    info_log "$package_name 已安装."
  else
    error_log "安装 $package_name 失败, 请检查您的网络."
    exit 1
  fi
}

get_current_version() {
  #获取当前_版本
  if [[ -f '/usr/local/bin/xray' ]]; then
    CURRENT_VERSION="$(/usr/local/bin/xray -version | awk 'NR==1 {print $2}')"
    CURRENT_VERSION="v${CURRENT_VERSION#v}"
  else
    CURRENT_VERSION=""
  fi
}

get_latest_version() {
  # 获取 Xray 最新版本号
  local tmp_file
  tmp_file="$(mktemp)"
  if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'; then
    "rm" "$tmp_file"
    error_log "获取发布列表失败，请检查您的网络."
    exit 1
  fi
  RELEASE_LATEST="$(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')"
  if [[ -z "$RELEASE_LATEST" ]]; then
    if grep -q "API rate limit exceeded" "$tmp_file"; then
      error_log "超过github API速率限制"
    else
      error_log "无法获取最新版本."
      echo "欢迎来到错误报告:https://github.com/XTLS/Xray-install/issues"
    fi
    "rm" "$tmp_file"
    exit 1
  fi
  "rm" "$tmp_file"
  RELEASE_LATEST="v${RELEASE_LATEST#v}"
  if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/XTLS/Xray-core/releases'; then
    "rm" "$tmp_file"
    error_log "获取发布列表失败，请检查您的网络."
    exit 1
  fi
  local releases_list
  releases_list=($(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}'))
  if [[ "${#releases_list[@]}" -eq '0' ]]; then
    if grep -q "API rate limit exceeded" "$tmp_file"; then
      error_log "超过github API速率限制"
    else
      error_log "无法获取最新版本."
      echo "欢迎来到错误报告:https://github.com/XTLS/Xray-install/issues"
    fi
    "rm" "$tmp_file"
    exit 1
  fi
  local i
  for i in ${!releases_list[@]}
  do
    releases_list[$i]="v${releases_list[$i]#v}"
    grep -q "https://github.com/XTLS/Xray-core/releases/download/${releases_list[$i]}/Xray-linux-$MACHINE.zip" "$tmp_file" && break
  done
  "rm" "$tmp_file"
  PRE_RELEASE_LATEST="${releases_list[$i]}"
}

version_gt() {
  # 比较两个版本
  # 0: $1 >  $2
  # 1: $1 <= $2

  if [[ "$1" != "$2" ]]; then
    local temp_1_version_number="${1#v}"
    local temp_1_major_version_number="${temp_1_version_number%%.*}"
    local temp_1_minor_version_number
    temp_1_minor_version_number="$(echo "$temp_1_version_number" | awk -F '.' '{print $2}')"
    local temp_1_minimunm_version_number="${temp_1_version_number##*.}"
    # shellcheck disable=SC2001
    local temp_2_version_number="${2#v}"
    local temp_2_major_version_number="${temp_2_version_number%%.*}"
    local temp_2_minor_version_number
    temp_2_minor_version_number="$(echo "$temp_2_version_number" | awk -F '.' '{print $2}')"
    local temp_2_minimunm_version_number="${temp_2_version_number##*.}"
    if [[ "$temp_1_major_version_number" -gt "$temp_2_major_version_number" ]]; then
      return 0
    elif [[ "$temp_1_major_version_number" -eq "$temp_2_major_version_number" ]]; then
      if [[ "$temp_1_minor_version_number" -gt "$temp_2_minor_version_number" ]]; then
        return 0
      elif [[ "$temp_1_minor_version_number" -eq "$temp_2_minor_version_number" ]]; then
        if [[ "$temp_1_minimunm_version_number" -gt "$temp_2_minimunm_version_number" ]]; then
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    else
      return 1
    fi
  elif [[ "$1" == "$2" ]]; then
    return 1
  fi
}

download_xray() {
  DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/$INSTALL_VERSION/Xray-linux-$MACHINE.zip"
  echo "下载 Xray 档案: $DOWNLOAD_LINK"
  if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
    error_log "下载失败！请检查网络或重试."
    return 1
  fi
  return 0
  info_log "下载 Xray 存档的验证文件: $DOWNLOAD_LINK.dgst"
  if ! curl -x "${PROXY}" -sSR -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst"; then
    error_log "下载失败！请检查网络或重试."
    return 1
  fi
  if [[ "$(cat "$ZIP_FILE".dgst)" == 'Not Found' ]]; then
    warn_log "此版本不支持验证。请替换为其他版本."
    return 1
  fi

  # Xray 档案的验证
  for LISTSUM in 'md5' 'sha1' 'sha256' 'sha512'; do
    SUM="$(${LISTSUM}sum "$ZIP_FILE" | sed 's/ .*//')"
    CHECKSUM="$(grep ${LISTSUM^^} "$ZIP_FILE".dgst | grep "$SUM" -o -a | uniq)"
    if [[ "$SUM" != "$CHECKSUM" ]]; then
      error_log "检查失败！请检查网络或重试."
      return 1
    fi
  done
}

decompression() {
  if ! unzip -q "$1" -d "$TMP_DIRECTORY"; then
    error_log "Xray 解压缩失败."
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    exit 1
  fi
  info_log "将 Xray 解压缩到 $TMP_DIRECTORY and 并准备安装."
}

install_file() {
  NAME="$1"
  if [[ "$NAME" == 'xray' ]]; then
    install -m 755 "${TMP_DIRECTORY}/$NAME" "/usr/local/bin/$NAME"
  elif [[ "$NAME" == 'geoip.dat' ]] || [[ "$NAME" == 'geosite.dat' ]]; then
    install -m 644 "${TMP_DIRECTORY}/$NAME" "${DAT_PATH}/$NAME"
  fi
}

install_xray() {
  # Install Xray binary to /usr/local/bin/ and $DAT_PATH
  install_file xray
  # 如果文件存在, geoip.dat and geosite.dat 不会安装或更新
  if [[ "$NO_GEODATA" -eq '0' ]] && [[ ! -f "${DAT_PATH}/.undat" ]]; then
    install -d "$DAT_PATH"
    install_file geoip.dat
    install_file geosite.dat
    GEODATA='1'
  fi

  # 将 Xray 将配置文件安装到 $JSON_PATH
  # shellcheck disable=SC2153
  if [[ -z "$JSONS_PATH" ]] && [[ ! -d "$JSON_PATH" ]]; then
    install -d "$JSON_PATH"
    echo "{}" > "${JSON_PATH}/config.json"
    CONFIG_NEW='1'
  fi

  # 将 Xray 将配置文件安装到 $JSON_PATH
  if [[ -n "$JSONS_PATH" ]] && [[ ! -d "$JSONS_PATH" ]]; then
    install -d "$JSONS_PATH"
    for BASE in 00_log 01_api 02_dns 03_routing 04_policy 05_inbounds 06_outbounds 07_transport 08_stats 09_reverse; do
      echo '{}' > "${JSONS_PATH}/${BASE}.json"
    done
    CONFDIR='1'
  fi

  # 用于存储 Xray 日志文件
  if [[ "$NO_LOGFILES" -eq '0' ]]; then
    if [[ ! -d '/var/log/xray/' ]]; then
      install -d -m 700 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /var/log/xray/
      install -m 600 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /dev/null /var/log/xray/access.log
      install -m 600 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /dev/null /var/log/xray/error.log
      LOG='1'
    else
      chown -R "$INSTALL_USER_UID:$INSTALL_USER_GID" /var/log/xray/
    fi
  fi
}

install_startup_service_file() {
  mkdir -p '/etc/systemd/system/xray.service.d'
  mkdir -p '/etc/systemd/system/xray@.service.d/'
  local temp_CapabilityBoundingSet="CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
  local temp_AmbientCapabilities="AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
  local temp_NoNewPrivileges="NoNewPrivileges=true"
  if [[ "$INSTALL_USER_UID" -eq '0' ]]; then
    temp_CapabilityBoundingSet="#${temp_CapabilityBoundingSet}"
    temp_AmbientCapabilities="#${temp_AmbientCapabilities}"
    temp_NoNewPrivileges="#${temp_NoNewPrivileges}"
  fi
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=$INSTALL_USER
${temp_CapabilityBoundingSet}
${temp_AmbientCapabilities}
${temp_NoNewPrivileges}
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/xray@.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=$INSTALL_USER
${temp_CapabilityBoundingSet}
${temp_AmbientCapabilities}
${temp_NoNewPrivileges}
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/%i.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 /etc/systemd/system/xray.service /etc/systemd/system/xray@.service
  if [[ -n "$JSONS_PATH" ]]; then
    "rm" '/etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf' \
      '/etc/systemd/system/xray@.service.d/10-donot_touch_single_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -confdir $JSONS_PATH" |
      tee '/etc/systemd/system/xray.service.d/10-donot_touch_multi_conf.conf' > \
        '/etc/systemd/system/xray@.service.d/10-donot_touch_multi_conf.conf'
  else
    "rm" '/etc/systemd/system/xray.service.d/10-donot_touch_multi_conf.conf' \
      '/etc/systemd/system/xray@.service.d/10-donot_touch_multi_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config ${JSON_PATH}/config.json" > \
      '/etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf'
    echo "# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config ${JSON_PATH}/%i.json" > \
      '/etc/systemd/system/xray@.service.d/10-donot_touch_single_conf.conf'
  fi
  info_log "已成功安装Systemd服务文件!"
  warn_log "以下是Xray服务启动的实际参数."
  warn_log "确保配置文件路径设置正确."
  systemd_cat_config /etc/systemd/system/xray.service
  # shellcheck disable=SC2154
  if [[ x"${check_all_service_files:0:1}" = x'y' ]]; then
    echo
    echo
    systemd_cat_config /etc/systemd/system/xray@.service
  fi
  systemctl daemon-reload
  SYSTEMD='1'
}

start_xray() {
  if [[ -f '/etc/systemd/system/xray.service' ]]; then
    systemctl start "${XRAY_CUSTOMIZE:-xray}"
    sleep 1s
    if systemctl -q is-active "${XRAY_CUSTOMIZE:-xray}"; then
      info_log "启动 Xray 服务."
    else
      error_log "无法启动 Xray 服务."
      exit 1
    fi
  fi
}

stop_xray() {
  XRAY_CUSTOMIZE="$(systemctl list-units | grep 'xray@' | awk -F ' ' '{print $1}')"
  if [[ -z "$XRAY_CUSTOMIZE" ]]; then
    local xray_daemon_to_stop='xray.service'
  else
    local xray_daemon_to_stop="$XRAY_CUSTOMIZE"
  fi
  if ! systemctl stop "$xray_daemon_to_stop"; then
    error_log "停止 Xray 服务失败."
    exit 1
  fi
  info_log "停止 Xray 服务."
}

install_geodata() {
  download_geodata() {
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "${dir_tmp}/${2}" "${1}"; then
      error_log "下载失败！请检查网络或重试."
      exit 1
    fi
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "${dir_tmp}/${2}.sha256sum" "${1}.sha256sum"; then
      error_log "下载失败！请检查网络或重试."
      exit 1
    fi
  }
  local download_link_geoip="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
  local download_link_geosite="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
  local file_ip='geoip.dat'
  local file_dlc='dlc.dat'
  local file_site='geosite.dat'
  local dir_tmp
  dir_tmp="$(mktemp -d)"
  [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '0' ]] && echo "warning: Xray 未安装"
  download_geodata $download_link_geoip $file_ip
  download_geodata $download_link_geosite $file_dlc
  cd "${dir_tmp}" || exit
  for i in "${dir_tmp}"/*.sha256sum; do
    if ! sha256sum -c "${i}"; then
      error_log "检查失败！请检查网络或重试."
      exit 1
    fi
  done
  cd - > /dev/null
  install -d "$DAT_PATH"
  install -m 644 "${dir_tmp}"/${file_dlc} "${DAT_PATH}"/${file_site}
  install -m 644 "${dir_tmp}"/${file_ip} "${DAT_PATH}"/${file_ip}
  rm -r "${dir_tmp}"
  exit 0
}

check_update() {
  if [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '1' ]]; then
    get_current_version
    info_log "Xray 当前版本是 $CURRENT_VERSION ."
  else
    warn_log "Xray 未安装."
  fi
  get_latest_version
  info_log "Xray 最新发布版本是 $RELEASE_LATEST ."
  info_log "Xray 新的预发布/发布版本是 $PRE_RELEASE_LATEST ."
  exit 0
}

remove_xray() {
  if systemctl list-unit-files | grep -qw 'xray'; then
    if [[ -n "$(pidof xray)" ]]; then
      stop_xray
    fi
    local delete_files=('/usr/local/bin/xray' '/etc/systemd/system/xray.service' '/etc/systemd/system/xray@.service' '/etc/systemd/system/xray.service.d' '/etc/systemd/system/xray@.service.d')
    [[ -d "$DAT_PATH" ]] && delete_files+=("$DAT_PATH")
    [[ -d "$HOME_PATH" ]] && delete_files+=("$HOME_PATH")
    if [[ "$PURGE" -eq '1' ]]; then
      if [[ -z "$JSONS_PATH" ]]; then
        delete_files+=("$JSON_PATH")
      else
        delete_files+=("$JSONS_PATH")
      fi
      [[ -d '/var/log/xray' ]] && delete_files+=('/var/log/xray')
    fi
    systemctl disable xray
    if ! ("rm" -r "${delete_files[@]}"); then
      error_log "未能删除 Xray."
      exit 1
    else
      for i in ${!delete_files[@]}
      do
        echo "removed: ${delete_files[$i]}"
      done
      systemctl daemon-reload
      info_log "您可能需要执行命令以删除相关软件: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
      info_log "Xray 已被移除."
      if [[ "$PURGE" -eq '0' ]]; then
        info_log "如有必要，请手动删除配置和日志文件."
        if [[ -n "$JSONS_PATH" ]]; then
          info_log "info: e.g., $JSONS_PATH and /var/log/xray/ ..."
        else
          info_log "info: e.g., $JSON_PATH and /var/log/xray/ ..."
        fi
      fi
      exit 0
    fi
  else
    error_log "Xray 未安装."
    exit 1
  fi
}

# Explanation of parameters in the script
show_help() {
#  echo "usage: $0 ACTION [OPTION]..."
  echo
#  echo 'ACTION:'
#  echo '  install                   Install/Update Xray'
#  echo '  install-geodata           Install/Update geoip.dat and geosite.dat only'
#  echo '  remove                    Remove Xray'
#  echo '  help                      Show help'
#  echo '  check                     Check if Xray can be updated'
#  echo 'If no action is specified, then install will be selected'
#  echo
#  echo 'OPTION:'
#  echo '  install:'
#  echo '    --version                 Install the specified version of Xray, e.g., --version v1.0.0'
#  echo '    -f, --force               Force install even though the versions are same'
#  echo '    --beta                    Install the pre-release version if it is exist'
#  echo '    -l, --local               Install Xray from a local file'
#  echo '    -p, --proxy               Download through a proxy server, e.g., -p http://127.0.0.1:8118 or -p socks5://127.0.0.1:1080'
#  echo '    -u, --install-user        Install Xray in specified user, e.g, -u root'
#  echo '    --reinstall               Reinstall current Xray version'
#  echo "    --no-update-service       Don't change service files if they are exist"
#  echo "    --without-geodata         Don't install/update geoip.dat and geosite.dat"
#  echo "    --without-logfiles        Don't install /var/log/xray"
#  echo '  install-geodata:'
#  echo '    -p, --proxy               Download through a proxy server'
#  echo '  remove:'
#  echo '    --purge                   Remove all the Xray files, include logs, configs, etc'
#  echo '  check:'
#  echo '    -p, --proxy               Check new version through a proxy server'
#  exit 0
}

main() {
  check_if_running_as_root
  identify_the_operating_system_and_architecture
  judgment_parameters

  install_software "$package_provide_tput" 'tput'


  # 参数信息
#  [[ "$HELP" -eq '1' ]] && show_help
#  [[ "$CHECK" -eq '1' ]] && check_update
#  [[ "$REMOVE" -eq '1' ]] && remove_xray
#  [[ "$INSTALL_GEODATA" -eq '1' ]] && install_geodata

  # 检查用户是否有效
  check_install_user

  # 两个非常重要的变量
  TMP_DIRECTORY="$(mktemp -d)"
  ZIP_FILE="${TMP_DIRECTORY}/Xray-linux-$MACHINE.zip"



  # Install Xray from a local file, but still need to make sure the network is available
  if [[ -n "$LOCAL_FILE" ]]; then
    warn_log "从本地文件安装 Xray 但仍需要确保网络可用."
    warn_log "请确保该文件有效，因为我们无法确认。（按任意键） ..."
    read -r
    install_software 'unzip' 'unzip'
    decompression "$LOCAL_FILE"
  else
    get_current_version
    if [[ "$REINSTALL" -eq '1' ]]; then
      if [[ -z "$CURRENT_VERSION" ]]; then
        error_log "Xray 未安装"
        exit 1
      fi
      INSTALL_VERSION="$CURRENT_VERSION"
      info_log "Reinstalling Xray $CURRENT_VERSION"
    elif [[ -n "$SPECIFIED_VERSION" ]]; then
      SPECIFIED_VERSION="v${SPECIFIED_VERSION#v}"
      if [[ "$CURRENT_VERSION" == "$SPECIFIED_VERSION" ]] && [[ "$FORCE" -eq '0' ]]; then
        info_log "当前版本与指定的版本相同。版本是 $CURRENT_VERSION ."
        exit 0
      fi
      INSTALL_VERSION="$SPECIFIED_VERSION"
      info_log "正在安装指定的 Xray 版本 $INSTALL_VERSION for $(uname -m)"
    else
      install_software 'curl' 'curl'
      get_latest_version
      if [[ "$BETA" -eq '0' ]]; then
        INSTALL_VERSION="$RELEASE_LATEST"
      else
        INSTALL_VERSION="$PRE_RELEASE_LATEST"
      fi
      if ! version_gt "$INSTALL_VERSION" "$CURRENT_VERSION" && [[ "$FORCE" -eq '0' ]]; then
        info_log "没有新版本。当前版本的 Xray 是 $CURRENT_VERSION ."
        exit 0
      fi

      info_log "正在安装 Xray $INSTALL_VERSION for $(uname -m)"

    fi
    define_port
    define_protocol
    get_ip
    install_info

    install_software 'curl' 'curl'
    install_software 'unzip' 'unzip'
    if ! download_xray; then
      "rm" -r "$TMP_DIRECTORY"
      echo "removed: $TMP_DIRECTORY"
      exit 1
    fi
    decompression "$ZIP_FILE"
  fi

  clone_obj
  set_config
  enter_config

  # 确定Xray是否正在运行
  if systemctl list-unit-files | grep -qw 'xray'; then
    if [[ -n "$(pidof xray)" ]]; then
      stop_xray
      XRAY_RUNNING='1'
    fi
  fi
  install_xray
  ([[ "$N_UP_SERVICE" -eq '1' ]] && [[ -f '/etc/systemd/system/xray.service' ]]) || install_startup_service_file
  echo 'installed: /usr/local/bin/xray'
  # 如果文件存在, 则显示安装或更新 geoip.dat and geosite.dat 将不显示
  if [[ "$GEODATA" -eq '1' ]]; then
    echo "installed: ${DAT_PATH}/geoip.dat"
    echo "installed: ${DAT_PATH}/geosite.dat"
  fi
  if [[ "$CONFIG_NEW" -eq '1' ]]; then
    echo "installed: ${JSON_PATH}/config.json"
  fi
  if [[ "$CONFDIR" -eq '1' ]]; then
    echo "installed: ${JSON_PATH}/00_log.json"
    echo "installed: ${JSON_PATH}/01_api.json"
    echo "installed: ${JSON_PATH}/02_dns.json"
    echo "installed: ${JSON_PATH}/03_routing.json"
    echo "installed: ${JSON_PATH}/04_policy.json"
    echo "installed: ${JSON_PATH}/05_inbounds.json"
    echo "installed: ${JSON_PATH}/06_outbounds.json"
    echo "installed: ${JSON_PATH}/07_transport.json"
    echo "installed: ${JSON_PATH}/08_stats.json"
    echo "installed: ${JSON_PATH}/09_reverse.json"
  fi
  if [[ "$LOG" -eq '1' ]]; then
    echo 'installed: /var/log/xray/'
    echo 'installed: /var/log/xray/access.log'
    echo 'installed: /var/log/xray/error.log'
  fi
  if [[ "$SYSTEMD" -eq '1' ]]; then
    echo 'installed: /etc/systemd/system/xray.service'
    echo 'installed: /etc/systemd/system/xray@.service'
  fi
  "rm" -r "$TMP_DIRECTORY"
  echo "removed: $TMP_DIRECTORY"
  get_current_version
  info_log "Xray $CURRENT_VERSION 已经安装."
  echo "您可能需要执行命令以删除相关软件: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
  if [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '1' ]] && [[ "$FORCE" -eq '0' ]] && [[ "$REINSTALL" -eq '0' ]]; then
    [[ "$XRAY_RUNNING" -eq '1' ]] && start_xray
  else
    systemctl start xray
    systemctl enable xray
    sleep 1s
    if systemctl -q is-active xray; then
      info_log "启用并启动 Xray 服务"
    else
      warn_log "未能启用和启动 Xray 服务"
    fi
  fi
}

info_log() {
  echo "INFO: $* "
}

warn_log() {
  echo "${yellow}WARNNING: $* ${reset}"
}

error_log() {
  echo "${red}ERROR: $* ${reset}"
}

error() {
    echo -e "${red} 输入错误! ${reset}"
}

pause() {
    read -rsp "$(echo -e "按 ${green} Enter 回车键 ${reset} 继续....或按 ${red} Ctrl + C ${reset} 取消.")" -d $'\n'
    echo
}

old_uuid="a61a533e-59d2-4743-9d17-330f05d072d8"
XRAY_UUID=$(cat /proc/sys/kernel/random/uuid)
XRAY_GLOBAL_CONF="$HOME_PATH/xray_ys.conf"
XRAY_VLESS_MODULE="$HOME_PATH/xray_vless_module.json"
XRAY_VMESS_MODULE="$HOME_PATH/xray_vmess_module.json"


get_ip() {
  ip=$(curl -s https://ipinfo.io/ip)
  [[ -z "$ip" ]] && ip=$(curl -s https://api.ip.sb/ip)
  [[ -z "$ip" ]] && ip=$(curl -s https://api.ipify.org)
  [[ -z "$ip" ]] && ip=$(curl -s https://ip.seeip.org)
  [[ -z "$ip" ]] && ip=$(curl -s https://ifconfig.co/ip)
  [[ -z "$ip" ]] && ip=$(curl -s https://api.myip.com | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
  [[ -z "$ip" ]] && ip=$(curl -s icanhazip.com)
  [[ -z "$ip" ]] && ip=$(curl -s myip.ipip.net | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
  [[ -z "$ip" ]] && echo -e "\n${red} 脚本不支持！${reset}\n" && exit
}

protocol_and=(
  "VLESS + TCP + XTLS"
  "VLESS + TCP + TLS"
  "VLESS + WS + TLS"
  "VLESS + TCP"
  "VMESS + TCP + TLS"
  "VMESS + TCP"
  "VMESS + WS + TLS"
  "VMESS + WS"
)

flow=(
  xtls-rprx-origin
  xtls-rprx-origin-udp443
  xtls-rprx-direct
  xtls-rprx-direct-udp443
)

define_port() {

  local random=$(shuf -i10001-65535 -n1)

  echo
  while :; do
    echo -e "请输入 "${yellow}"XRAY"${reset}" 端口 ["${magenta}"10000-65535"${reset}"]"
    read -p "$(echo -e "(默认端口: ${magenta}${random}${reset}):")" XRAY_PORT
    [[ -z "$XRAY_PORT" ]] && XRAY_PORT=$random
    case $XRAY_PORT in
      [1-9][0-9][0-9][0-9] | [1-5][0-9][0-9][0-9][0-9] | 6[0-4][0-9][0-9][0-9] | 65[0-4][0-9][0-9] | 655[0-3][0-5])

        echo
        echo -e "${yellow} XRAY 端口${reset} = ${magenta}$XRAY_PORT${reset}"
        echo "----------------------------------------------------------------"
        echo
        break
        ;;
      *)
        error
        continue
        ;;
    esac
  done
}

define_protocol() {
  echo
  while :; do
    echo -e "请选择 "${yellow}"传输协议"${reset}" [${magenta}1-${#protocol_and[*]}${reset}]"
    for ((i = 1; i <= ${#protocol_and[*]}; i++)) ; do
      protocol_show="${protocol_and[$i - 1]}"
      echo
      echo -e "${yellow} $i${reset}. ${aoi}${protocol_show}${reset}"
	done
    echo
    read -p "$(echo -e "(默认传输组合: ${aoi}${protocol_and[0]}${reset})"):" protocol_num
	[[ -z "$protocol_num" ]] && protocol_num=1
    case $protocol_num in
      1)
        XRAY_PROTOCOL='vless'
        XRAY_NETWORK='tcp'
        XRAY_SECURITY='xtls'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      2)
        XRAY_PROTOCOL='vless'
        XRAY_NETWORK='tcp'
        XRAY_SECURITY='tls'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      3)
        XRAY_PROTOCOL='vless'
        XRAY_NETWORK='ws'
        XRAY_SECURITY='tls'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      4)
        XRAY_PROTOCOL='vless'
        XRAY_NETWORK='tcp'
        XRAY_SECURITY='none'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      5)
        XRAY_PROTOCOL='vmess'
        XRAY_NETWORK='tcp'
        XRAY_SECURITY='tls'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      6)
        XRAY_PROTOCOL='vmess'
        XRAY_NETWORK='tcp'
        XRAY_SECURITY='none'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      7)
        XRAY_PROTOCOL='vmess'
        XRAY_NETWORK='ws'
        XRAY_SECURITY='tls'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      8)
        XRAY_PROTOCOL='vmess'
        XRAY_NETWORK='ws'
        XRAY_SECURITY='none'
        PROTOCOL_NETWORK_SECURITY=${protocol_and[${protocol_num} - 1]}
        echo
        break
        ;;
      *)
        error
        continue
        ;;
    esac
  done
  echo -e "${yellow} 传输组合 = ${aoi}${PROTOCOL_NETWORK_SECURITY}${reset}"
  echo "----------------------------------------------------------------"
  echo
  define_flow
}

define_flow() {

  echo
  case $XRAY_PROTOCOL in
    "vless")
      while :; do
        echo
        echo -e "请选择流控:[${magenta}1-${#flow[@]}${reset}]"
        for (( i=1;i<=${#flow[@]};i++ ));do
          echo
          echo -e "${yellow}$i. ${aoi}${flow[$i-1]}${reset}"
        done
        echo
        read -p "(默认流控:${aoi}${flow[2]}${reset})" flow_num
        [[ -z "$flow_num" ]] && flow_num=3
        case $flow_num in
          1|2|3|4)
            XRAY_FLOW=${flow[$flow_num-1]}
            break
            ;;
          *)
          error
          continue
          ;;
        esac
      done
      ;;
    "vmess")
      XRAY_FLOW="none"
      ;;
    *)
      error
    ;;
  esac

}

install_info() {

  clear
  echo
  echo " ....准备安装了咯..看看配置..."
  echo
  echo "---------- 安装信息 -------------"
  info_mes
  echo "------------- END ----------------"
  echo
  pause
  echo
}

info_mes() {
  if [[ "$XRAY_SECURITY" == "none" ]];then
    echo -e "${yellow} 地址 (Address) ${reset} = ${aoi}$ip${reset}"
    echo
    echo -e "${yellow} 端 口 (Port)${reset} = ${aoi}$XRAY_PORT${reset}"
    echo
    echo -e "${yellow} 用户ID (User ID / UUID) ${reset} = ${aoi}$XRAY_UUID${reset}"
    echo
    echo -e "${yellow} 传输组合(Protocol) ${reset} = ${aoi}$XRAY_PROTOCOL + $XRAY_NETWORK${reset}"
    echo
    echo -e "${yellow} 流控(Flow) ${reset} = ${aoi}$XRAY_FLOW${reset}"
  else
    echo -e "${yellow} 地址 (Address) ${reset} = ${aoi}$ip${reset}"
    echo
    echo -e "${yellow} 端 口 (Port)${reset} = ${aoi}$XRAY_PORT${reset}"
    echo
    echo -e "${yellow} 用户ID (User ID / UUID) ${reset} = ${aoi}$XRAY_UUID${reset}"
    echo
    echo -e "${yellow} 传输组合(Protocol) ${reset} = ${aoi}$XRAY_PROTOCOL + $XRAY_NETWORK + $XRAY_SECURITY${reset}"
    echo
    echo -e "${yellow} 流控(Flow) ${reset} = ${aoi}$XRAY_FLOW${reset}"
  fi
}

clone_obj() {
  if [[ -d "$HOME_PATH" ]]; then
    rm -rf "$HOME_PATH"
  fi
  install_software git git
  install -d "$HOME_PATH"
  if git clone https://github.com/oceans-wu/ys-Xray -b "main" "$HOME_PATH" --depth=1; then
    info_log "项目克隆完成"
  else
    error_log "项目克隆失败,请检查网络"
    exit 1
  fi

}

set_config() {

  case $XRAY_PROTOCOL in
    "vless")
      if [[ ! -f "$XRAY_VLESS_MODULE" ]]; then
        error_log "模板文件不存在:$XRAY_VLESS_MODULE"
        exit 1
      fi

      if [[ -f "$JSON_PATH/config.json" ]]; then
        rm -rf "$JSON_PATH/config.json"
      fi
      cp $XRAY_VLESS_MODULE "$JSON_PATH/config.json"

      sed -i "9s/44330/$XRAY_PORT/; 14s/$old_uuid/$XRAY_UUID/; 15s/xtls-rprx-direct/$XRAY_FLOW/; 27s/tcp/$XRAY_NETWORK/; 28s/xtls/$XRAY_SECURITY/"  "$JSON_PATH/config.json"
      ;;
    "vmess")
      if [[ ! -f "$XRAY_VMESS_MODULE" ]]; then
        error_log "模板文件不存在:$XRAY_VMESS_MODULE"
        exit 1
      fi
      if [[ -f "$JSON_PATH/config.json" ]]; then
        rm -rf "$JSON_PATH/config.json"
      fi
      cp $XRAY_VMESS_MODULE "$JSON_PATH/config.json"
      sed -i "9s/44330/$XRAY_PORT/; 14s/$old_uuid/$XRAY_UUID/; 30s/tcp/$XRAY_NETWORK/; 31s/tls/$XRAY_SECURITY/"  "$JSON_PATH/config.json"
      ;;
    *)
      error_log "协议有误: $XRAY_PROTOCOL"
      ;;
  esac
}

enter_config() {
  cat > "$XRAY_GLOBAL_CONF" <<EOF
##
## 请不要删除.修改此文件
##

# 端口号
XRAY_PORT=${XRAY_PORT}

# 协议
XRAY_PROTOCOL=${XRAY_PROTOCOL}

# UUID
XRAY_UUID=${XRAY_UUID}

# 流控
XRAY_FLOW=${XRAY_FLOW}

# 传输协议
XRAY_NETWORK=${XRAY_NETWORK}

# 加密协议
XRAY_SECURITY=${XRAY_SECURITY}

EOF
}

get_install_info() {
  if [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq 0 ]]; then
    error_log "Xray 未安装"
    return
  fi

  if [ -z "$PROTOCOL_NETWORK_SECURITY" ]; then
    if [ -f "$XRAY_GLOBAL_CONF" ]; then
    . $XRAY_GLOBAL_CONF
    get_ip
    else
    error_log "文件不存在 请重新安装!"
    exit 1
    fi
  fi
  clear
  echo
  echo
  echo "---------- 配置信息 -------------"
  info_mes
  echo "------------- END ----------------"
  echo

}

change_choose() {
  while :;do
    echo "--------------------"
    echo
    echo "${yellow}1${reset}.${aoi}修改端口${reset}"
    echo
    echo "${yellow}2${reset}.${aoi}修改传输协议${reset}"
    echo
    echo "--------------------"
    read -p "请选择[${magenta}1-2${reset}]:" change_sum
    case $change_sum in
      1)
        change_port
        break
        ;;
      2)
        change_protocol
        break
        ;;
      *)
        continue
        ;;
    esac
  done
}

change_port() {
  old_port=$XRAY_PORT
  define_port
  sed -i "s/$old_port/$XRAY_PORT/"  $XRAY_GLOBAL_CONF
  sed -i "s/$old_port/$XRAY_PORT/" "${JSON_PATH}/config.json"
  stop_xray
  start_xray
  get_install_info
}

change_protocol() {
  define_protocol
  set_config
  enter_config
  stop_xray
  start_xray
  get_install_info
}


main_run() {
  main
}

change_conf() {
  if [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq 0 ]]; then
    error_log "Xray 未安装"
    return
  fi
  get_install_info
  change_choose
}


check_xray() {
  check_update
}

uninstall() {
  while :; do
    echo "------------------------------"
    echo
    echo "${yellow}是否卸载Xray${reset}"
    echo
    read -p "请输入[${red}Y/N${reset}]:" Y_N
    [[ -z "$Y_N" ]] && continue
    case "$Y_N" in
      "Y")
        pause
        remove_xray
        ;;
      "N")
        break
        ;;
      *)
        continue
      ;;
    esac
  done
}

while :; do
  echo
  echo -e "----------${yellow} Xray by www.yisu.com ${reset}----------"
  echo
  echo
  echo "${yellow}香港高速服务器: https://www.yisu.com${reset}"
  echo
  echo
  echo "${yellow} 1 ${reset}.${aoi} 安   装 ${reset}"
  echo
  echo "${yellow} 2 ${reset}.${aoi} 修改配置 ${reset}"
  echo
  echo "${yellow} 3 ${reset}.${aoi} 查看配置 ${reset}"
  echo
  echo "${yellow} 4 ${reset}.${aoi} 检查升级${reset}"
  echo
  echo "${yellow} 5 ${reset}.${aoi} 卸   载 ${reset}"
  echo
  echo
  echo "-------------------- END --------------------"
  echo
  read -p "$(echo -e "请选择 [${magenta}1-5${reset}]:")" choose
  case $choose in
    1)
      main_run
      break
      ;;
    2)
      change_conf
      ;;
    3)
      get_install_info
      ;;
    4)
      check_xray
      break
      ;;
    5)
      uninstall
      ;;
    *)
      error
      ;;
  esac
done


