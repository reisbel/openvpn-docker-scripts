# Copyright 2019 Itopia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to install the OpenVPN Server docker container, a watchtower docker container
# (to automatically update the server), and to create a new OpenVPN user.

set -euo pipefail

function display_usage() {
  cat <<EOF
Usage: install_server.sh [--hostname <hostname>] [--api-port <port>] [--keys-port <port>] [--management-port <port>]

  --hostname   The hostname to be used to access the management API and access keys
  --api-port   The port number for the management API
  --keys-port  The port number for the access keys
  --management-port The port number for the monitor app
EOF
}

readonly SENTRY_LOG_FILE=${SENTRY_LOG_FILE:-}

function log_error() {
  local -r ERROR_TEXT="\033[0;31m"  # red
  local -r NO_COLOR="\033[0m"
  >&2 printf "${ERROR_TEXT}${1}${NO_COLOR}\n"
}

# Pretty prints text to stdout, and also writes to sentry log file if set.
function log_start_step() {
  log_for_sentry "$@"
  str="> $@"
  lineLength=47
  echo -n "$str"
  numDots=$(expr $lineLength - ${#str} - 1)
  if [[ $numDots > 0 ]]; then
    echo -n " "
    for i in $(seq 1 "$numDots"); do echo -n .; done
  fi
  echo -n " "
}

function run_step() {
  local -r msg=$1
  log_start_step $msg
  shift 1
  if "$@"; then
    echo "OK"
  else
    # Propagates the error code
    return
  fi
}

function confirm() {
  echo -n "$1"
  local RESPONSE
  read RESPONSE
  RESPONSE=$(echo "$RESPONSE" | tr '[A-Z]' '[a-z]')
  if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" = "y" ]] || [[ "$RESPONSE" = "yes" ]]; then
    return 0
  fi
  return 1
}

function command_exists {
  command -v "$@" > /dev/null 2>&1
}

function log_for_sentry() {
  if [[ -n "$SENTRY_LOG_FILE" ]]; then
    echo [$(date "+%Y-%m-%d@%H:%M:%S")] "install_server.sh" "$@" >>$SENTRY_LOG_FILE
  fi
}

# Check to see if docker is installed.
function verify_docker_installed() {
  if command_exists docker; then
    return 0
  fi
  log_error "NOT INSTALLED"
  echo -n
  if ! confirm "> Would you like to install Docker? This will run 'curl -sS https://get.docker.com/ | sh'. [Y/n] "; then
    exit 0
  fi
  if ! run_step "Installing Docker" install_docker; then
    log_error "Docker installation failed, please visit https://docs.docker.com/install for instructions."
    exit 1
  fi
  echo -n "> Verifying Docker installation................ "
  command_exists docker
}

function verify_docker_running() {
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker info 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  elif [[ $STDERR_OUTPUT = *"Is the docker daemon running"* ]]; then
    start_docker
  fi
}

function install_docker() {
  curl -sS https://get.docker.com/ | sh > /dev/null 2>&1
}

function start_docker() {
  systemctl start docker.service > /dev/null 2>&1
  systemctl enable docker.service > /dev/null 2>&1
}

function docker_container_exists() {
  docker ps | grep $1 >/dev/null 2>&1
}

function remove_shadowbox_container() {
  remove_docker_container shadowbox
}

function remove_watchtower_container() {
  remove_docker_container watchtower
}

function remove_docker_container() {
  docker rm -f $1 > /dev/null
}

function handle_docker_container_conflict() {
  local readonly CONTAINER_NAME=$1
  local readonly EXIT_ON_NEGATIVE_USER_RESPONSE=$2
  local PROMPT="> The container name \"$CONTAINER_NAME\" is already in use by another container. This may happen when running this script multiple times."
  if $EXIT_ON_NEGATIVE_USER_RESPONSE; then
    PROMPT="$PROMPT We will attempt to remove the existing container and restart it. Would you like to proceed? [Y/n] "
  else
    PROMPT="$PROMPT Would you like to replace this container? If you answer no, we will proceed with the remainder of the installation. [Y/n] "
  fi
  if ! confirm "$PROMPT"; then
    if $EXIT_ON_NEGATIVE_USER_RESPONSE; then
      exit 0
    fi
    return 0
  fi
  if run_step "Removing $CONTAINER_NAME container" remove_"$CONTAINER_NAME"_container ; then
    echo -n "> Restarting $CONTAINER_NAME ........................ "
    start_"$CONTAINER_NAME"
    return $?
  fi
  return 1
}

# Set trap which publishes error tag only if there is an error.
function finish {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]
  then
    log_error "\nSorry! Something went wrong. If you can't figure this out, please copy and paste all this output and send it to us, to see if we can help you."
  fi
}

function get_random_port {
  local num=0  # Init to an invalid value, to prevent "unbound variable" errors.
  until (( 1024 <= num && num < 65536)); do
    num=$(( $RANDOM + ($RANDOM % 2) * 32768 ));
  done;
  echo $num;
}

function create_persisted_state_dir() {
  readonly STATE_DIR="$SHADOWBOX_DIR/persisted-state"
  mkdir -p --mode=770 "${STATE_DIR}"
  chmod g+s "${STATE_DIR}"
}

# Generate a secret key for access to the Management API and store it in a tag.
# 16 bytes = 128 bits of entropy should be plenty for this use.
function safe_base64() {
  # Implements URL-safe base64 of stdin, stripping trailing = chars.
  # Writes result to stdout.
  # TODO: this gives the following errors on Mac:
  #   base64: invalid option -- w
  #   tr: illegal option -- -
  local url_safe="$(base64 -w 0 - | tr '/+' '_-')"
  echo -n "${url_safe%%=*}"  # Strip trailing = chars
}

function join() {
  local IFS="$1"
  shift
  echo "$*"
}

function init_pki() {
  sudo docker run -v ${OPEN_VPN_DATA_DIR}:/etc/openvpn --rm -it ${SB_IMAGE} ovpn_initpki
}

function generate_openvpn_config_file() {
  # By itself, local messes up the return code.
  local readonly STDERR_OUTPUT
  
  STDERR_OUTPUT=$(docker run -v ${OPEN_VPN_DATA_DIR}:/etc/openvpn --rm ${SB_IMAGE} ovpn_genconfig -u udp://${PUBLIC_HOSTNAME}:${API_PORT} -e "management 0.0.0.0 ${MANAGEMENT_PORT}" 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
}

function start_openvpn() {
  # By itself, local messes up the return code.
  local readonly STDERR_OUTPUT

  STDERR_OUTPUT=$(docker run --name openvpn -v ${OPEN_VPN_DATA_DIR}:/etc/openvpn -d -p ${API_PORT}:${API_PORT}/udp ${MANAGEMENT_PORT}:${MANAGEMENT_PORT} --cap-add=NET_ADMIN ${SB_IMAGE} 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
}

function start_watchtower() {
  # Start watchtower to automatically fetch docker image updates.
  # Set watchtower to refresh every 30 seconds if a custom SB_IMAGE is used (for
  # testing).  Otherwise refresh every hour.
  local WATCHTOWER_REFRESH_SECONDS="${WATCHTOWER_REFRESH_SECONDS:-3600}"
  declare -a docker_watchtower_flags=(--name watchtower --restart=always)
  docker_watchtower_flags+=(-v /var/run/docker.sock:/var/run/docker.sock)
  # By itself, local messes up the return code.
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker run -d "${docker_watchtower_flags[@]}" v2tec/watchtower --cleanup --tlsverify --interval $WATCHTOWER_REFRESH_SECONDS 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
  if docker_container_exists watchtower; then
    handle_docker_container_conflict watchtower false
  else
    log_error "$STDERR_OUTPUT"
    return 1
  fi
}

# Waits for the service to be up and healthy
function wait_openvpn() {
  until curl --insecure -s "${LOCAL_API_URL}" >/dev/null; do sleep 1; done
}

install_openvpn() {
  # Make sure we don't leak readable files to other users.
  umask 0007

  run_step "Verifying that Docker is installed" verify_docker_installed
  run_step "Verifying that Docker daemon is running" verify_docker_running

  log_for_sentry "Creating OpenVPN Data directory"
  export OPEN_VPN_DATA_DIR="${OPEN_VPN_DATA_DIR:-/opt/openvpn/vpn-data}"

  log_for_sentry "Setting API port"
  API_PORT="${FLAGS_API_PORT}"

  if [[ $API_PORT == 0 ]]; then
    API_PORT=${SB_API_PORT:-$(get_random_port)}
  fi

  log_for_sentry "Setting MANAGEMENT por"
  MANAGEMENT_PORT="${FLAGS_MANAGEMENT_PORT}"

  if [[$MANAGEMENT_PORT == $API_PORT ]]; then
    log_error "Api MANAGEMENT port don't igual to api port"
    exit 1
  fi

  log_for_sentry "Setting PUBLIC_HOSTNAME"
  # TODO(fortuna): Make sure this is IPv4
  PUBLIC_HOSTNAME=${FLAGS_HOSTNAME:-${SB_PUBLIC_IP:-$(curl -4s https://ipinfo.io/ip)}}

  while [[$MANAGEMENT_PORT == 0 || $MANAGEMENT_PORT == $API_PORT]]; do
    MANAGEMENT_PORT=${SB_MANAGEMENT_PORT:-$(get_random_port)}
  done
  
  readonly SB_IMAGE=${SB_IMAGE:-kylemanna/openvpn}
  
  if [[ -z $PUBLIC_HOSTNAME ]]; then
    local readonly MSG="Failed to determine the server's IP address."
    log_error "$MSG"
    log_for_sentry "$MSG"
    exit 1
  fi

  #Generate OpenVPN config file
  run_step "Generate OpenVPN config file" generate_openvpn_config_file
  
  #init PKI
  run_step "Init OpenVPN PKI" init_pki
  
  #run_step "Starting OpenVPN" start_openvpn
  run_step "Starting OpenVPN" start_openvpn

  # TODO(fortuna): Don't wait for Shadowbox to run this.
  run_step "Starting Watchtower" start_watchtower

  readonly PUBLIC_API_URL="${PUBLIC_HOSTNAME}:${API_PORT}"
  readonly LOCAL_API_URL="localhost:${API_PORT}"
  #run_step "Waiting for OpenVPN server to be healthy" wait_openvpn
  
  FIREWALL_STATUS=""
  #run_step "Checking host firewall" check_firewall

  # Output JSON.  This relies on apiUrl and certSha256 (hex characters) requiring
  # no string escaping.  TODO: look for a way to generate JSON that doesn't
  # require new dependencies.
  cat <<END_OF_SERVER_OUTPUT

CONGRATULATIONS! Your OpenVPN server is up and running.

${FIREWALL_STATUS}
END_OF_SERVER_OUTPUT
} # end of install_openvpn

function is_valid_port() {
  (( 0 < "$1" && "$1" <= 65535 ))
}

function parse_flags() {
  params=$(getopt --longoptions hostname:,api-port:,keys-port: -n $0 -- $0 "$@")
  [[ $? == 0 ]] || exit 1
  eval set -- $params

  while [[ "$#" > 0 ]]; do
    local flag=$1
    shift
    case "$flag" in
      --hostname)
        FLAGS_HOSTNAME=${1}
        shift
        ;;
      --api-port)
        FLAGS_API_PORT=${1}
        shift
        if ! is_valid_port $FLAGS_API_PORT; then
          log_error "Invalid value for $flag: $FLAGS_API_PORT"
          exit 1
        fi
        ;;
      --keys-port)
        FLAGS_KEYS_PORT=$1
        shift
        if ! is_valid_port $FLAGS_KEYS_PORT; then
          log_error "Invalid value for $flag: $FLAGS_KEYS_PORT"
          exit 1
        fi
        ;;
      --management-port)
        FLAGS_MANAGEMENT_PORT=$1
        if ! is_valid_port $FLAGS_MANAGEMENT_PORT; then
          log_error "Invalid value for $flag: $FLAGS_MANAGEMENT_PORT"
          exit 1
        fi
      --)
        break
        ;;
      *) # This should not happen
        log_error "Unsupported flag $flag"
        display_usage
        exit 1
        ;;
    esac
  done
  if [[ $FLAGS_API_PORT != 0 && $FLAGS_API_PORT == $FLAGS_KEYS_PORT ]]; then
    log_error "--api-port must be different from --keys-port"
    exit 1
  fi
  return 0
}

function main() {
  trap finish EXIT
  declare FLAGS_HOSTNAME=""
  declare -i FLAGS_API_PORT=1194
  declare -i FLAGS_KEYS_PORT=0
  parse_flags "$@"
  install_openvpn
}

main "$@"