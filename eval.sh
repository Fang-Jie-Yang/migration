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

function boot_vm() {
    log_msg "Booting VM on $1"

    local ret=$( { ssh $(whoami)@$1 << EOF
    sudo /srv/vm/net.sh; sudo nohup $2
EOF
    } 2>&1 > /dev/null)

    #err_msg "$ret"

    # We have to check for error manually to decide return value
    local err="Failed to retrieve host CPU features"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return "$NEED_REBOOT"
    fi
    local err="Address already in use"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return $RETRY
    fi
    local err="No such file or directory"
    if echo "$ret" | grep -q "$err"; then 
        err_msg "$err"
        return $ABORT
    fi
    local err="qemu-system-aarch64:"
    if echo "$ret" | grep "$err"; then 
        local out=$(echo "$ret" | grep "$err")
        err_msg "$out"
        return $ABORT
    fi
    return 0
}


# qemu_monitor_send(ip, port, cmd)
# * We only allow idle timeout error
function qemu_monitor_send() {
    { local err=$(echo "$3" | ncat -w 2 -i 1 $1 $2 2>&1 >&3 3>&-); } 3>&1
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
        if ! qemu_monitor_send $DST_IP $MONITOR_PORT "$cmd"; then
            return $RETRY
        fi
    done
    local cmd="migrate -d tcp:$DST_IP:$MIGRATION_PORT"
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
    local val=$(echo "$1" | grep "^$2:")
    local val=${val#$2: }
    local val=${val%\ *}
    echo "$val"
}

function migration_is_completed() {
    local info=$(qemu_migration_info_fetch)
    local status=$(qemu_migration_info_get_field "$info" "Migration status")
    log_msg "Migration status: $status"
    if [[ $status != "completed" ]]; then
        return $RETRY
    fi
    return 0
}


# qemu_migration_info_save(file_path)
# * We still don't check data validity here
function qemu_migration_info_save() {
    log_msg "Saving migration outcome"
    local info=$(qemu_migration_info_fetch)
    for field in "${DATA_FIELDS[@]}"; do
        local val=$(qemu_migration_info_get_field "$info" "$field")
        log_msg "$field: $val"
    done
    echo "$info" > $1
    dos2unix $1
    return 0
}

function force_clean_up() {
    log_msg "Cleaning up w/ pkill"
    local cmd="sudo pkill -9 qemu"
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

    setup_vm_env; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to setup environment"
        return $ret
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
            err_msg "VM status broken"
            return $RETRY
        fi
    fi
    benchmark_setup $1; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to setup benchmark"
        return $ret
    fi
    start_migration; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to start migration"
        return $ret
    fi
    post_migration; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "post_migration() failed"
        return $ret
    fi
    local elapsed=0
    while ! migration_is_completed; do
        if [[ $elapsed -gt $MIGRATION_TIMEOUT ]]; then
            err_msg "Migration timout"
            return $RETRY
        fi 
        sleep 10s
        (( elapsed += 10 ))
    done
    qemu_migration_info_save "$OUTPUT_DIR/$1"; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to save data"
        return $ret
    fi
    benchmark_clean_up $1; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to clean up benchmark"
        return $ret
    fi
    if ! check_guest_status; then
        # second chance
        if ! check_guest_status; then
            err_msg "VM status broken after migration"
            return $RETRY
        fi
    fi
}

# reboot_m400(ip)
function reboot_m400() {
    log_msg "Rebooting m400"
    local ret=$( { ssh $(whoami)@$1 << EOF
        sudo reboot $2
EOF
    } 2>&1 > /dev/null)
    local expected="Connection to $1 closed by remote host."
    if ! echo "$ret" | grep -q "$expected"; then
        err_msg "Failed to reboot m400 at $1"
        exit 1
    fi
}

# wait_for(ip)
function wait_for() {
    while ! ssh -q $(whoami)@$1 exit; do
        err_msg "$1 not up yet"
        sleep 30s
    done
    return 0
}

function result() {
    declare -A values
    for field in "${DATA_FIELDS[@]}"; do
        values["$field"]=0
    done
    for (( n = 0; n < $ROUNDS; n++ )); do
        local file="$OUTPUT_DIR/$n"
        if ! [[ -e "$file" ]]; then
            err_msg "$file does not exist!"
            return $ABORT
        fi
        local info=$(cat "$file")
        for field in "${DATA_FIELDS[@]}"; do
            local val=$(qemu_migration_info_get_field "$info" "$field")
            if [[ -z "$val" ]]; then
                err_msg "$file has no $field value"
                return $ABORT
            else
                values["$field"]=$(echo "$val" + ${values["$field"]}|bc)
            fi
        done
    done
    for field in "${DATA_FIELDS[@]}"; do
        local avg=$(echo "scale=4; ${values[$field]} / $ROUNDS"|bc)
        echo -n "$avg "
    done
    echo ""
}


# * Main *
source $1
mkdir $OUTPUT_DIR

i=0
while [[ $i -lt $ROUNDS ]]; do

    if [[ "$USE_PREV_FILE" == "true" ]]; then
        # Skip round if we have previous output
        if [[ -e "$OUTPUT_DIR/$i" ]]; then
            log_msg "Skipping round $i"
            (( i += 1 ))
            continue
        fi
    fi

    log_msg "Evaluation round: $i"
    do_migration_eval $i

    case $? in
        $NEED_REBOOT)
            reboot_m400 $SRC_IP
            reboot_m400 $DST_IP
            wait_for $SRC_IP
            wait_for $DST_IP
	    sleep 20s
            ;;
        $ABORT)
            exit 1
            ;;
        $RETRY)
            clean_up $SRC_IP
            clean_up $DST_IP
            rm $OUTPUT_DIR/$i
            ;;
        *)
            clean_up $SRC_IP
            clean_up $DST_IP
            (( i += 1 ))
            ;;
    esac
    sleep 10s
done

result >> $OUTPUT_FILE

