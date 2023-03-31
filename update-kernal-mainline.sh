#! /bin/bash

if [[ $# -ne 2 ]]; then
	echo "usage: ./update-kernel-mainline.sh username ip_addr"
	exit
fi

ssh $1@$2 << EOF

	cd /mydata/linux
	make -j8
	sudo make modules_install
	sudo make install
	
	cd /srv/u-boot/
	sudo ./update-kernel.sh
	sudo ./update-initrd.sh /boot/initrd.img-4.18.0

	sudo reboot
EOF

