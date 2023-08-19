
ROUNDS=10

# directory to store output file for each round
OUTPUT_DIR="./eval_output"
# skip round when output file exists in OUTPUT_DIR
USE_PREV_FILE="true"
# file for final statistic result of all rounds
OUTPUT_FILE="eval_result.txt"

SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
GUEST_IP="10.10.1.1"

QEMU_PATH="/mydata/qemu"
NFS_PATH="/proj/ntucsie-PG0/fjyang/cloud-hack-ab.img"
INITRD="/mydata/some-tutorials/files/ramfs/core-image-minimal-qemuarm.cpio.gz"
VM_KERNEL="/mydata/some-tutorials/files/Image"
MONITOR_PORT="1234"
MIGRATION_PORT="8888"
QEMU_CMD="$QEMU_PATH/aarch64-softmmu/qemu-system-aarch64 \
    -enable-kvm \
    -M virt \
    -cpu host \
    -smp 4 \
    -m 256 \
    -kernel $VM_KERNEL \
    -initrd $INITRD \
    -net none \
    -append 'console=hvc0 earlycon=pl011,0x09000000' \
    -display none \
    -daemonize"

SRC_QEMU_CMD="$QEMU_CMD \
    -monitor telnet:$SRC_IP:$MONITOR_PORT,server,nowait"
DST_QEMU_CMD="$QEMU_CMD \
    -monitor telnet:$DST_IP:$MONITOR_PORT,server,nowait \
    -incoming tcp:0:$MIGRATION_PORT"
MIGRATION_PROPERTIES=(
    #"migrate_set_parameter downtime-limit 3000"
    "migrate_set_parameter max-bandwidth 102400"
    "migrate_set_parameter multifd-channels 8"
    #"migrate_set_parameter max-postcopy-bandwidth 107374182400"
    "migrate_set_capability multifd on"
    #"migrate_set_capability postcopy-ram off"
)
MIGRATION_TIMEOUT=30
# Fields to record and count for
DATA_FIELDS=(
    "downtime"
    "total time"
    "throughput"
    "setup"
    "transferred ram"
)

# return values for callback functions
NEED_REBOOT=1
RETRY=2
ABORT=3

# Will be called at the start of each round
function setup_vm_env() {
    log_msg "Setting up environment"
    return 0
}

# Will be called after the guest booted,
# and after the migration
function check_guest_status() {
    log_msg "Checking vm's status"
    return 0
}

# Will be called before migration started,
# with current round as argument ($1)
function benchmark_setup() {

    log_msg "Setting up benchmark"
    return 0	
}

# Will be called just after migration started
function post_migration() {

    log_msg "post_migration()"
    #
    # Example usage: postcopy 
    #
    #sleep 5s
    #if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "migrate_start_postcopy"; then
    #    return $RETRY
    #fi

    return 0
}

# Will be called after migration completed,
# with current round as argument ($1)
function benchmark_clean_up() {

    log_msg "Cleaning up benchmark"
    return 0
}

