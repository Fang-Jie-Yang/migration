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

    # Since it's hard to seperate stdout & stderr for ssh(tty),
    # we have to check for error manually.
    err="Failed to retrieve host CPU features"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return $NEED_REBOOT
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
# * We only allow idle timeout
function qemu_monitor_send() {
    { err=$(echo "$3" | ncat -w 2 -i 1 $1 $2 2>&1 >&3 3>&-); } 3>&1
    if [[ "$err" != *"Ncat: Idle timeout expired"* ]]; then
        return $RETRY
    fi
    return 0
}

function start_migration() {
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

# qemu_migration_info_get_field(field_name)
function qemu_migration_info_get_field() {
    val=$(qemu_migration_info_fetch | grep "$1:")
    val=${val#$1: }
    val=${val%\ *}
    echo "$val"
}

function migration_complete() {
    status=$(qemu_migration_info_get_field "Migration status")
    echo "$status"
    if [[ $status != "completed" ]]; then
        return $RETRY
    fi
    return 0
}

function force_clean_up() {
    cmd="sudo pkill -9 qemu"
    echo "$cmd" | ssh -q $(whoami)@$1 >/dev/null
    if [[ $? -eq 255 ]]; then
        err_msg "Failed to force clean up"
        return $ABORT
    fi
    return 0
}

function clean_up() {
    if ! qemu_monitor_send $1 $MONITOR_PORT "quit"; then
        err_msg "Failed to clean up"
        if ! force_clean_up $1; then
            return $ABORT
        fi
    fi
    return 0
}

function do_migration_eval() {

    if ! setup_vm_env ; then
        ret=$?
        err_msg "Failed to setup environment"
        return $ret;
    fi
    if ! boot_vm "$SRC_IP" "$SRC_QEMU_CMD"; then
        ret=$?
        err_msg "Failed to boot at src"
        return $ret
    fi
    if ! boot_vm "$DST_IP" "$DST_QEMU_CMD"; then
        ret=$?
        err_msg "Failed to boot at dst"
        return $ret
    fi
    sleep 10s
    if ! check_guest_status; then
        ret=$?
        err_msg "VM status unknown"
        return $ret
    fi
    if ! benchmark_setup; then
        ret=$?
        err_msg "Failed to setup benchmark"
        return $ret
    fi
    if ! start_migration; then
        ret=$?
        err_msg "Failed to start migration"
        return $ret
    fi
    if ! post_migration; then
        ret=$?
        err_msg "Failed to execute post migration"
        return $ret
    fi

    sleep 5s
    while ! migration_complete; do
        sleep 10s
    done

    qemu_migration_info_fetch

}



source config.sh
do_migration_eval
clean_up $SRC_IP
clean_up $DST_IP
