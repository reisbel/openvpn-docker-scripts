# openvpn-docker-scripts

 Scripts for creating your own [OpenVPN](https://openvpn.net/) server with [Docker](https://www.docker.com/),  based on [this](https://medium.com/@gurayy/set-up-a-vpn-server-with-docker-in-5-minutes-a66184882c45) article and this [repository](https://github.com/kylemanna/docker-openvpn)

## Steps

Clone repository

```bash
git clone https://github.com/reisbel/openvpn-docker-scripts.git && cd openvpn-docker-scripts
```

OpenVPN install and dependencies

```bash
./install_openvpn.sh
```

## Create user

```bash
./create_user.sh user1
```

## References

Outline install script
<https://github.com/Jigsaw-Code/outline-server/blob/master/src/server_manager/install_scripts/install_server.sh>

Set Up a VPN Server With Docker In 5 Minutes
<https://medium.com/@gurayy/set-up-a-vpn-server-with-docker-in-5-minutes-a66184882c45>

## License

Apache License - See [LICENSE](LICENSE) for more information.
