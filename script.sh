#! /bin/bash


NEED_REBOOT=-1
RETRY=-2
STOP=-3

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

function vm_env_setup() {
    echo -e "${BCYAN}setting up environment${NC}" >&2
	# TODO: disk image
	if scp ; then
		echo -e "${BRED}cannot setup disk image${NC}" >&2
		return $RETRY
	fi 
}

function boot_vm() {
    echo -e "${BCYAN}booting VM on $1${NC}" >&2

	# TODO: script expand
	log=$(ssh $(whoami)@$1 << EOF
    sudo /srv/vm/net.sh; sudo nohup $script --bridge
EOF
    2>&1)

	# Since it's hard to seperate stdout & stderr for ssh(tty),
	# we have to check for error manually.
	err="Failed to retrieve host CPU features"
    if echo "$log" | grep $err ; then
		echo -e "${BRED}$err${NC}" >&2
		return $NEED_REBOOT
	fi
	err="Address already in use"
	if echo "$log" | grep $err; then
		echo -e "${BRED}$err${NC}" >&2
		return $RETRY
	fi
	err="No such file or directory"
	if echo "$log" | grep $err; then 
		echo -e "${BRED}$err${NC}" >&2
		return $STOP
    fi
}

function do_migration_eval() {

	if vm_env_setup ; then
		echo "do_migration_eval: failed to setup environment\n" >&2
		return -1;
	fi
}

