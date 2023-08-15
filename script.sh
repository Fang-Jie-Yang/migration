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

    cmd="$QEMU_CMD -monitor telnet:$1:$MONITOR_PORT,server,nowait"

    ret=$( { ssh $(whoami)@$1 << EOF
    sudo /srv/vm/net.sh; sudo nohup $cmd
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

function do_migration_eval() {

    if ! setup_vm_env ; then
        err_msg "Failed to setup environment"
        return $RETRY;
    fi

    if ! boot_vm "$SRC_IP" ; then
	ret=$?
        err_msg "Failed to boot at src"
        return $ret
    fi
}


source config.sh
do_migration_eval
