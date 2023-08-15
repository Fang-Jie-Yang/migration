

VM_DISK_IMAGE="/proj/ntucsie-PG0/fjyang/cloud-hack-ab-bak.img"
NFS_PATH="/proj/ntucsie-PG0/fjyang/cloud-hack-ab.img"

QEMU_PATH="/mydata/qemu"
#VM_KERNEL="/mydata/some-tutorials/files/sekvm/Image.sekvm.guest"
VM_KERNEL="/mydata/some-tutorials/files/Image.sekvm"
SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
MONITOR_PORT="1234"
QEMU_CMD="$QEMU_PATH/aarch64-softmmu/qemu-system-aarch64 \
		-enable-kvm \
		-M virt \
		-cpu host \
		-smp 4 \
		-m 256 \
		-kernel $VM_KERNEL \
		-netdev tap,id=net1,helper=$QEMU_PATH/qemu-bridge-helper,vhost=on \
		-device virtio-net-pci,netdev=net1,mac=de:ad:be:ef:f6:5f \
		-drive if=none,file=$NFS_PATH,id=vda,cache=none,format=raw \
		-device virtio-blk-pci,drive=vda \
		-append \"console=ttyAMA0 root=/dev/vda rw earlycon=pl011,0x09000000\" \
		-display none \
		-daemonize"



