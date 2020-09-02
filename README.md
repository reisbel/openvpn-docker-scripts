# openvpn-docker-scripts

 Scripts for creating your own [OpenVPN](https://openvpn.net/) server with [Docker](https://www.docker.com/) and optional openvpn monitor,  based on [this](https://medium.com/@gurayy/set-up-a-vpn-server-with-docker-in-5-minutes-a66184882c45) article, this [repository](https://github.com/kylemanna/docker-openvpn) and this [repository](https://github.com/ruimarinho/docker-openvpn-monitor) for openvpn monitor.

## Steps

Install OpenVPN and dependencies

```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/reisbel/openvpn-docker-scripts/master/install_openvpn.sh)"
```

Install OpenVPN and Monitor
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/reisbel/openvpn-docker-scripts/master/install_openvpn.sh) --monitor-enable true"
```

## Create user

```bash
sudo bash  -c "$(wget -qO- https://raw.githubusercontent.com/reisbel/openvpn-docker-scripts/master/create_user.sh)" --dump-strings user1
```

## References

Outline install script
<https://github.com/Jigsaw-Code/outline-server/blob/master/src/server_manager/install_scripts/install_server.sh>

Set Up a VPN Server With Docker In 5 Minutes
<https://medium.com/@gurayy/set-up-a-vpn-server-with-docker-in-5-minutes-a66184882c45>

## License

Apache License - See [LICENSE](LICENSE) for more information.
