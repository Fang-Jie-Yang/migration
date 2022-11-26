#! /bin/bash

if [[ $# -ne 2 ]]; then
	echo "usage: ./m400-migration.sh username ip_addr"
	exit
fi
username=$1
ip_addr=$2

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

# generate ssh key for github in working directory
if [[ ! -f m400-rsa.pub || ! -f m400-rsa ]]; then

	echo -e "${BCYAN}no key pair for m400, generating...${NC}"
	ssh-keygen -f "$PWD/m400-rsa" 
	echo -e "${BCYAN}please add m400-rsa.pub to your github account, and run the script again.${NC}"
	exit

else
	echo -e "${BGREEN}already have key pair, remember to add m400-rsa.pub to your github account${NC}"
fi

# upload key pair to m400
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


github_ssh_key="github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
qemu_branch='migration-demand-decrypt-v4.2.1-fjyang'
echo -e "${BCYAN}installing qemu for sekvm, could take a while...${NC}"
ssh $1@$2 << EOF

	sudo chown -R $1 /mydata
	cd /mydata

	echo $github_ssh_key >> ~/.ssh/known_hosts
	git clone git@github.com:ntu-ssl/qemu.git	

	cd qemu
	git checkout $qemu_branch
	./configure --target-list=aarch64-softmmu --disable-werror	
	make -j8
EOF

echo -e "${BCYAN}getting scripts up for VMs...${NC}"
ssh $1@$2 << EOF
	cd /mydata
	git clone git@github.com:ntu-ssl/some-tutorials.git
	cp /proj/ntucsie-PG0/fjyang/blk.sh /mydata/some-tutorials/files/blk
	cp /proj/ntucsie-PG0/fjyang/resume-blk.sh /mydata/some-tutorials/files/blk
EOF

echo -e "${BCYAN}installing sekvm, could take a while...${NC}"
sekvm_branch='demand-decrypt-v2'
ssh $1@$2 << EOF

	cd /mydata
	git clone git@github.com:ntu-ssl/linux-sekvm.git 
	cd linux-sekvm
	git checkout $sekvm_branch
	make sekvm_defconfig
	make -j8
	sudo make modules_install
	sudo make install
	
	cd /srv/u-boot/
	sudo sed -i 's/\/usr\/src\/linux/\/mydata\/linux-sekvm/' update-kernel.sh
	./update-kernel.sh
	sudo ./update-initrd.sh /boot/initrd.img-4.18.0+

	sudo reboot
EOF
echo -e "${BCYAN}rebooting machine, please wait before connecting again.${NC}"

