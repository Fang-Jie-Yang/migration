
ROUNDS=2

# directory to store output file for each round
OUTPUT_DIR="./"
# skip round when output file exists in OUTPUT_DIR
USE_PREV_FILE="true"
# file for final statistic result of all rounds
OUTPUT_FILE="result.txt"

SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
GUEST_IP="10.10.1.5"

QEMU_PATH="/mydata/qemu"
VM_KERNEL="/mydata/some-tutorials/files/Image.sekvm"
VM_DISK_IMAGE="/proj/ntucsie-PG0/fjyang/cloud-hack-ab-bak.img"
NFS_PATH="/proj/ntucsie-PG0/fjyang/cloud-hack-ab.img"
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
MIGRATION_PROPERTIES=(
    "migrate_set_parameter downtime-limit 3000"
    "migrate_set_parameter max-bandwidth 102400"
    "migrate_set_parameter multifd-channels 4"
    "migrate_set_parameter max-postcopy-bandwidth 107374182400"
    #"migrate_set_capability multifd on"
    #"migrate_set_capability postcopy-ram off"
)
MIGRATION_TIMEOUT=60
# Fields to record and count for
DATA_FIELDS=(
    "downtime"
    "total time"
    "throughput"
    "setup"
    "transferred ram"
    "ab downtime"
)

# return values for callback functions
NEED_REBOOT=1
RETRY=2
ABORT=3

# Will be called before migration started,
# with current round as argument ($1)
function benchmark_setup() {
    AB_BIN="/users/fjyang/httpd-2.4.54/support/ab"
    AB_PID=-1
    while ! curl -m 10 "http://$GUEST_IP/" > /dev/null 2>&1; do
        log_msg "waiting for guest's apache server"
    done
    $AB_BIN -c 100 -n 1000000 -s 30 -g "$OUTPUT_DIR/ab$1" http://$GUEST_IP/ >&2 & 
    AB_PID=$!
	return 0	
}

# Will be called just after migration started,
function post_migration() {
    #sleep 12s
    #if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "migrate_start_postcopy"; then
    #    return $RETRY
    #fi
	return 0
}

# Will be called after migration completed,
# with current round as argument ($1)
function benchmark_clean_up() {
    log_msg "Checking ab validity"
    if ! ps -p $AB_PID > /dev/null; then
        err_msg "Ab stopped early"
        return $RETRY
    fi
    log_msg "Stopping ab"
    sudo kill -SIGINT "$AB_PID"
    sleep 5s
	if [ ! -f "$OUTPUT_DIR/ab$1" ]; then
        err_msg "Ab output missing"
        return $RETRY
	fi 
    if ! curl -m 10 "http://$GUEST_IP/" > /dev/null 2>&1 ; then
        err_msg "Guest's apache server downed after migration"
        return $RETRY
    fi
    dt=$(python3 ~/some-tutorials/files/migration/plot.py $OUTPUT_DIR/ab$1 | awk '{print $2}')
    echo "ab downtime: $dt" | tee -a $OUTPUT_DIR/$1
	return 0
}

