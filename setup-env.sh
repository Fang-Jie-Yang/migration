#! /bin/bash

username="fjyang"
src_ip="10.10.1.1"
dst_ip="10.10.1.2"
guest_branch="pv-v4.18-upcall"
qemu_branch="migration-demand-decrypt-v4.2.1-sw-multifd"
sekvm_branch='demand-decrypt-v2'

#github_ssh_key="github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
github_ssh_key="github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

# $1: username
# $2: ip
function setupGitHubKey() {
    ssh $1@$2 << EOF
        echo $github_ssh_key >> ~/.ssh/known_hosts
EOF
}

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
        git clone git@github.com:ntu-ssl/qemu.git	
        cd qemu
        git checkout $qemu_branch

        ./configure --target-list=aarch64-softmmu --disable-werror	
        make -j8
EOF
}

# $1: username
# $2: ip
function installGuestKernel() {
    echo -e "${BCYAN}installing guest kernel, could take a while...${NC}"
    ssh $1@$2 << EOF
        cd /mydata
        git clone git@github.com:ntu-ssl/linux-guest.git
        cd linux-guest
        git checkout $guest_branch
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
function installSeKVM() {
    echo -e "${BCYAN}installing sekvm, could take a while...${NC}"
    ssh $1@$2 << EOF

        sudo apt install libncurses-dev

        cd /mydata
        git clone --depth 1 --branch $sekvm_branch git@github.com:ntu-ssl/linux-sekvm.git 
        cd linux-sekvm

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
}

# $1: username
# $2: ip
function setup() {
    setupGitHubKey $1 $2
    setupDataDir $1 $2
    installQEMU $1 $2
    #installGuestKernel $1 $2
    installTutorials $1 $2
    installSeKVM $1 $2
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
yes | sudo apt install python3-pip
pip3 install matplotlib
pip3 install pandas


cd ~
git clone git@github.com:ntu-ssl/some-tutorials.git

cd ~
wget https://dlcdn.apache.org//apr/apr-1.7.4.tar.gz
tar xvf apr-1.7.4.tar.gz
cd apr-1.7.4
./configure; sudo make && sudo make install

cd ~
wget https://dlcdn.apache.org//apr/apr-util-1.6.3.tar.gz
tar xvf apr-util-1.6.3.tar.gz
cd apr-util-1.6.3
./configure --with-apr=/usr/local/apr; sudo make && sudo make install

cd ~
wget https://archive.apache.org/dist/httpd/httpd-2.4.54.tar.gz
tar xvf httpd-2.4.54.tar.gz
cd httpd-2.4.54
cp ~/some-tutorials/files/migration/ab.c support
./configure --with-apr=/usr/local/apr; sudo make && sudo make install
