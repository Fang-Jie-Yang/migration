#! /bin/bash

username="fjyang"
src_ip="10.10.1.1"
dst_ip="10.10.1.2"
qemu_branch="v4.2.1"
sekvm_branch='v4.18'

github_ssh_key="github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

# $1: username
# $2: ip

# $1: username
# $2: ip
function setupDataDir() {
    ssh $1@$2 << EOF
        sudo chown -R $1 /mydata
EOF
}

# $1: username
# $2: ip
function installQEMU() {
    echo -e "${BCYAN}installing qemu for sekvm, could take a while...${NC}"
    ssh $1@$2 << EOF
        cd /mydata
        git clone git@github.com:qemu/qemu.git
        cd qemu
        git checkout $qemu_branch

        ./configure --target-list=aarch64-softmmu --disable-werror	
        make -j8
EOF
}

# $1: username
# $2: ip
function installTutorials() {
    echo -e "${BCYAN}getting scripts up for VMs...${NC}"
    ssh $1@$2 << EOF
        cd /mydata
        git clone git@github.com:ntu-ssl/some-tutorials.git
EOF
}

# $1: username
# $2: ip
function installKVM() {
    echo -e "${BCYAN}installing sekvm, could take a while...${NC}"
    ssh $1@$2 << EOF

        sudo apt install libncurses-dev

        cd /mydata
        git clone git@github.com:torvalds/linux.git
        cd linux
        git checkout $sekvm_branch

        cp /mydata/some-tutorials/files/defconfig .config
        yes "" | make oldconfig
        make -j8
        sudo make modules_install
        sudo make install
        
        cd /srv/u-boot/
        sudo sed -i 's/\/usr\/src\/linux/\/mydata\/linux/' update-kernel.sh
	sudo ./update-kernel.sh
        sudo ./update-initrd.sh /boot/initrd-img-4.18.0
        sudo reboot
EOF
}

# $1: username
# $2: ip
function setup() {
    setupGitHubKey $1 $2
    setupDataDir $1 $2
    installQEMU $1 $2
    installTutorials $1 $2
    installKVM $1 $2
}

# upload key pair to m400
echo -e "${BCYAN}uploading key pair to src, dst${NC}"
scp ~/.ssh/id_rsa "$username@$src_ip:~/.ssh"
scp ~/.ssh/id_rsa "$username@$dst_ip:~/.ssh"
scp ~/.ssh/id_rsa.pub "$username@$src_ip:~/.ssh"
scp ~/.ssh/id_rsa.pub "$username@$dst_ip:~/.ssh"

setup $username $src_ip &
setup $username $dst_ip &

wait 

yes | sudo apt update
yes | sudo apt install apache2-utils
yes | sudo apt install dos2unix
yes | sudo apt install ncat
