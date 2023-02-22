#!/bin/bash

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

if [[ $# -ne 2 ]]; then
	echo "usage: ./setup-key.sh username client_ip"
	exit
fi

# upload key pair to m400(client)
echo -e "${BCYAN}uploading key pair to m400${NC}"
scp "m400-rsa" "$1@$2:~/.ssh/id_rsa"
if [[ $? -ne 0 ]]; then
	echo -e "${BRED}upload failed, exiting...${NC}"
	exit
fi
scp "m400-rsa.pub" "$1@$2:~/.ssh/id_rsa.pub"
if [[ $? -ne 0 ]]; then
	echo -e "${BRED}upload failed, exiting...${NC}"
	exit
fi
echo -e "${BGREEN}key pair uploaded${NC}"
