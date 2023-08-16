

VM_DISK_IMAGE="/proj/ntucsie-PG0/fjyang/cloud-hack-ab-bak.img"
NFS_PATH="/proj/ntucsie-PG0/fjyang/cloud-hack-ab.img"

SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
QEMU_PATH="/mydata/qemu"
VM_KERNEL="/mydata/some-tutorials/files/Image.sekvm"
#VM_KERNEL="/mydata/some-tutorials/files/sekvm/Image.sekvm.guest"
MONITOR_PORT="1234"
MIGRATION_PORT="8888"
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
    -append 'console=ttyAMA0 root=/dev/vda rw earlycon=pl011,0x09000000' \
    -display none \
    -daemonize"
SRC_QEMU_CMD="$QEMU_CMD \
    -monitor telnet:$SRC_IP:$MONITOR_PORT,server,nowait"
DST_QEMU_CMD="$QEMU_CMD \
    -monitor telnet:$DST_IP:$MONITOR_PORT,server,nowait \
    -incoming tcp:0:$MIGRATION_PORT"

GUEST_IP="10.10.1.5"

MIGRATION_PROPERTIES=(
    "migrate_set_parameter downtime-limit 300"
    "migrate_set_parameter max-bandwidth 102400"
    "migrate_set_parameter multifd-channels 4"
    "migrate_set_parameter max-postcopy-bandwidth 107374182400"
)
    #"migrate_set_capability multifd on"
    #"migrate_set_capability postcopy-ram off"

function benchmark_setup() {
	return 0	
}

function benchmark_clean_up() {
	return 0
}

function post_migration() {
	return 0
}


