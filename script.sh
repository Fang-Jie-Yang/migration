#! /bin/bash


NEED_REBOOT=1
RETRY=2
ABORT=3

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

function log_msg() {
    echo -e "${BCYAN}$1${NC}" >&2
}

function err_msg() {
    echo -e "${BRED}$1${NC}" >&2
}

function setup_vm_env() {
    log_msg "Setting up environment"
    if ! sudo cp $VM_DISK_IMAGE $NFS_PATH; then
        err_msg "Cannot setup disk image"
        return $RETRY
    fi 
    return 0
}

function boot_vm() {
    log_msg "Booting VM on $1"

    ret=$( { ssh $(whoami)@$1 << EOF
    sudo /srv/vm/net.sh; sudo nohup $2
EOF
    } 2>&1 > /dev/null)

    #err_msg "$ret"

    # We have to check for error manually to decide return value
    err="Failed to retrieve host CPU features"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return "$NEED_REBOOT"
    fi
    err="Address already in use"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return $RETRY
    fi
    err="No such file or directory"
    if echo "$ret" | grep -q "$err"; then 
        err_msg "$err"
        return $ABORT
    fi
    err="qemu-system-aarch64:"
    if echo "$ret" | grep "$err"; then 
        err_msg "$err"
        return $ABORT
    fi
    return 0
}

function check_guest_status() {
    log_msg "Checking vm's status"
    if ! ping -c 3 "$GUEST_IP" >&2 ; then
        return $RETRY
    fi
    return 0
}

# qemu_monitor_send(ip, port, cmd)
# * We only allow idle timeout error
function qemu_monitor_send() {
    { err=$(echo "$3" | ncat -w 2 -i 1 $1 $2 2>&1 >&3 3>&-); } 3>&1
    if [[ "$err" != *"Ncat: Idle timeout expired"* ]]; then
        return $RETRY
    fi
    echo ""
    return 0
}

function start_migration() {
    log_msg "Starting migration"
    for cmd in "${MIGRATION_PROPERTIES[@]}"; do
        if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "$cmd"; then
            return $RETRY
        fi
    done
    cmd="migrate -d tcp:$DST_IP:$MIGRATION_PORT"
    if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "$cmd"; then
        return $RETRY
    fi
    return 0
}

# * We don't apply error check here,
# * let the function that use the info to detect failure
function qemu_migration_info_fetch() {
    echo "info migrate" | \
    ncat -w 1 -i 1 $SRC_IP $MONITOR_PORT 2> /dev/null | \
    strings | \
    tail -n +14 | \
    head -n -1
}

# qemu_migration_info_get_field(info, field_name)
function qemu_migration_info_get_field() {
    val=$(echo "$1" | grep "$2:")
    val=${val#$2: }
    val=${val%\ *}
    echo "$val"
}

function migration_is_completed() {
    info=$(qemu_migration_info_fetch)
    status=$(qemu_migration_info_get_field "$info" "Migration status")
    log_msg "Migration status: $status"
    if [[ $status != "completed" ]]; then
        return $RETRY
    fi
    return 0
}


# qemu_migration_info_save(file_path)
# * We check data validity here
function qemu_migration_info_save() {
    log_msg "Saving migration outcome"
    info=$(qemu_migration_info_fetch)
    for field in "${DATA_FIELDS[@]}"; do
        val=$(qemu_migration_info_get_field "$info" "$field")
        if [[ -z "$val" ]]; then
            err_msg "No $field value"
            return $RETRY
        else
            log_msg "$field: $val"
        fi
    done
    echo "$info" > $1
    dos2unix $1
    return 0
}

function force_clean_up() {
    log_msg "Cleaning up w/ pkill"
    cmd="sudo pkill -9 qemu"
    echo "$cmd" | ssh -q $(whoami)@$1 >/dev/null
    if [[ $? -eq 255 ]]; then
        err_msg "Failed to force clean up"
        exit 1
    fi
    return 0
}

function clean_up() {
    log_msg "Cleaning up"
    if ! qemu_monitor_send $1 $MONITOR_PORT "quit"; then
        err_msg "Failed to clean up"
        force_clean_up $1
    fi
    return 0
}

function do_migration_eval() {

    if ! setup_vm_env ; then
        err_msg "Failed to setup environment"
        return $RETRY;
    fi
    boot_vm "$SRC_IP" "$SRC_QEMU_CMD"; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to boot at src"
        return $ret
    fi
    boot_vm "$DST_IP" "$DST_QEMU_CMD"; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to boot at dst"
        return $ret
    fi
    sleep 10s
    if ! check_guest_status; then
        # second chance
        if ! check_guest_status; then
            err_msg "VM status unknown"
            return $RETRY
        fi
    fi
    benchmark_setup; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to setup benchmark"
        return $ret
    fi
    if ! start_migration; then
        err_msg "Failed to start migration"
        return $RETRY
    fi
    post_migration; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "post_migration() failed"
        return $ret
    fi
    elapsed=0
    while ! migration_is_completed; do
        if [[ $elapsed -gt $MIGRATION_TIMEOUT ]]; then
            err_msg "Migration timout"
            return $RETRY
        fi 
        sleep 10s
        (( elapsed += 10 ))
    done
    if ! qemu_migration_info_save "$OUTPUT_DIR/$1"; then
        err_msg "Failed to save data"
        return $RETRY
    fi
    benchmark_clean_up; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to clean up benchmark"
        return $ret
    fi
}

# reboot_m400(ip)
function reboot_m400() {
    log_msg "Rebooting m400"
    ret=$( { ssh $(whoami)@$1 << EOF
        sudo reboot $2
EOF
    } 2>&1 > /dev/null)
    expected="Connection to $1 closed by remote host."
    if ! echo "$ret" | grep -q "$expected"; then
        err_msg "Failed to reboot m400 at $1"
        exit 1
    fi
}


source config.sh
i=0
while [[ -e "$OUTPUT_DIR/$i" ]]; do
    (( i += 1 ))
done

while [[ $i -lt $ROUNDS ]]; do
    log_msg "now: $i"
    do_migration_eval $i
    case $? in
        $NEED_REBOOT)
            reboot_m400 $SRC_IP
            reboot_m400 $DST_IP
            # TODO: busy waiting
            sleep 8m
            ;;
        $ABORT)
            exit 1
            ;;
        $RETRY)
            clean_up $SRC_IP
            clean_up $DST_IP
            ;;
        *)
            clean_up $SRC_IP
            clean_up $DST_IP
            (( i += 1 ))
            ;;
    esac
    sleep 10s
done

