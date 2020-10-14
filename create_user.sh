function main() {
  readonly SB_IMAGE=${SB_IMAGE:-kylemanna/openvpn:2.3}
  export OPEN_VPN_DATA_DIR="${OPEN_VPN_DATA_DIR:-/opt/openvpn/vpn-data}"

  sudo docker run -v ${OPEN_VPN_DATA_DIR}:/etc/openvpn --rm -it ${SB_IMAGE} easyrsa build-client-full $1 nopass

  sudo docker run -v ${OPEN_VPN_DATA_DIR}:/etc/openvpn --rm ${SB_IMAGE} ovpn_getclient $1 > $1.ovpn
}

main "$@"