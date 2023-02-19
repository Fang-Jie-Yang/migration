#! /bin/bash

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

# generate ssh key for github/cloudlab
if [[ ! -f ~/.ssh/id_rsa.pub || ! -f ~/.ssh/id_rsa ]]; then

	echo -e "${BCYAN}no key pair for m400, generating...${NC}"
	ssh-keygen
	echo -e "${BCYAN}please add ~/.ssh/id_rsa.pub to your github account, and cloudlab key list.${NC}"
	exit

else
	echo -e "${BCYAN}key pair exists, remember to add ~/.ssh/id_rsa.pub to github and cloudlab${NC}"
fi
