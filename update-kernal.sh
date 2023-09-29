#! /bin/bash

if [[ $# -ne 2 ]]; then
	echo "usage: ./update-kernel.sh username ip_addr"
	exit
fi

ssh -A $1@$2 << EOF

	cd /mydata/linux-sekvm
	make -j8
	sudo make modules_install
	sudo make install
	
	cd /srv/u-boot/
	./update-kernel.sh
	sudo ./update-initrd.sh /boot/initrd.img-4.18.0+

	sudo reboot
EOF

