#!/bin/bash

#Color definition
red=$'\e[1;31m'
grn=$'\e[1;32m'
end=$'\e[0m'

if [ $# -ne 1 ]; then
	printf "%s\n" "${red}Usage: Provide the username (only one).${end}"
	printf "%s\n" "${grn}Example: $0 juanperez${end}"
	exit 1
else

# Remove non-ASCII characters of the paramenter 1, the username
	export LC_ALL=C 
	username=$(echo "$1" | tr -cd '[:alnum:]')
	
	# easy-rsa directory
	EasyRsaDir="/etc/openvpn/easy-rsa"
	#OpenVPN Dir
	OpenVpnDir="/etc/openvpn"
	
	#User's certificate
	CertificateFile="$EasyRsaDir/keys/$username.crt"
	
	# Verify if the user can read the certificate and can find the certificate
	if [ ! -r "$CertificateFile" ]; then
		printf "%s\n" "${red}Error. User $username not found or you don't have permission to read the certificate $CertificateFile.${end}"
		exit 1
	fi
	
	
	cd $EasyRsaDir
	if [ $? -ne 0 ]; then
	printf "%s\n" "${red}Error to access to the directory $EasyRsaDir.${end}"
	exit 1
	fi
	
	#Importing the openvpn variables
	
	source $EasyRsaDir/vars 1 >> /dev/null 2 >> /dev/null
	
	if [ $? -ne 0 ]; then
	printf "%s\n" "${red}Error to import variables.${end}"
	exit 1
	fi
	

	#After revocation the command send this line
	#error 23 at 0 depth lookup:certificate revoked
	
	#Revoke the certificate and check if the status 23 to the CancellSuccess variable
	CancellSuccess=$($EasyRsaDir/revoke-full $username 2> /dev/null | tail -1 | awk '{print $2}')
	UserStatus=$(cat $EasyRsaDir/keys/index.txt | grep $username | tail -1 | awk '{ print $1 }' | tr -cd '[:alnum:]')
	
	#Logical OR in bash script is used with operator -o.
	
	if [ "$CancellSuccess" -eq 23 -o "$UserStatus" == "R" ]; then 
		/bin/cp -fbp $EasyRsaDir/keys/crl.pem $OpenVpnDir/keys/crl.pem
		#Move the revoved certificate to a direcotory for backup
		/bin/mv $EasyRsaDir/keys/$username.crt $EasyRsaDir/revoke-keys/
		/bin/mv $EasyRsaDir/keys/$username.key $EasyRsaDir/revoke-keys/
		/bin/mv $EasyRsaDir/keys/$username.csr $EasyRsaDir/revoke-keys/
		printf "%s\n" "${grn}The user $username was deleted${end}"
	else
		printf "%s\n" "${red}Error to revoke user $username${end}"
		exit 1
	fi 
fi