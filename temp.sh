#! /bin/bash


# -------------------- Setting --------------------- #

## Network Settings
src_ip="10.10.1.1"
dst_ip="10.10.1.2"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888

## Output Settings
result_file="res-ab-1G"

## Evaluation Settings
rounds=10
expected_max_totaltime="20s"
ParamsToSet[0]="multifd-channels"
ParamsToSet[1]="max-bandwidth"
ParamsToSet[2]="downtime-limit"
CapsToSet[0]="multifd"
CapsToSet[1]="compress"

# Note: field val can only be number
FieldsToCollect[0]="downtime"
FieldsToCollect[1]="total time"
FieldsToCollect[2]="throughput"
FieldsToCollect[3]="setup"
FieldsToCollect[4]="transferred ram"
FieldsToCollect[5]="multifd bytes"

# ----------------- Setting Ends ------------------- #



declare -A DataSums
for field in "${FieldsToCollect[@]}"; do
    DataSums[$field]=0
done
command_migrate="migrate -d tcp:$dst_ip:$migration_port"
command_info="info migrate
info migrate_parameters
info migrate_capabilities"
command_shutdown="quit"

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

#########################
# $1: ip addr           #
# $2: "src" / "dst"     #
# --------------------- #
# ret: null / "Failed"  #
# --------------------- #
# use $username         #
#########################
function bootVM() {

    echo -e "${BCYAN}starting VM on $1 as $2${NC}" >&2

    if [[ $2 == "src" ]]; then
        script="./blk.sh"
    elif [[ $2 == "dst" ]]; then
        script="./resume-blk.sh"
    fi

    log=$( { ssh $username@$1 << EOF
    cd /mydata/some-tutorials/files/blk
    sudo nohup $script --bridge
EOF
    } 2>&1 )

    err=""
    err+=$(echo "$log" | grep "Failed to retrieve host CPU features")
    err+=$(echo "$log" | grep "Address already in use")
    err+=$(echo "$log" | grep "No such file or directory")
    if [[ -n "$err" ]]; then
        echo "Failed"
    fi
}

#########################
# $1: ip addr           #
# --------------------- #
# ret: null             #
# --------------------- #
# use $username         #
#########################
function rebootM400() {

    echo -e "${BRED}rebooting $1${NC}" >&2

    ssh $username@$1 << EOF
    sudo reboot
EOF
}

###########################
# $1: log file name       #
# ----------------------- #
# ret: null / "Failed"    # 
# ----------------------- #
# use MigrationSettings[] #
###########################
function checkValidity() {
    for (( i = 0; i < ${#Names[@]}; i++ )); do
        name=${Names[$i]}
        setting=$(cat $1 | awk -v prefix="$name:" '$1 == prefix {print $2}')
        expected=${MigrationSettings[$name]}
        if [[ $name == "max-bandwidth" ]]; then
            (( expected *= 1024 * 1024 ))
        fi
        if [[ "$setting" != "$expected" ]]; then
            echo -e "${BRED}$name: $setting, expect $expected${NC}" >&2
            echo "Failed"
            return
        fi
    done
}


###########################
# $1: log file name       #
# ----------------------- #
# ret: null / "Failed"    # 
# ----------------------- #
# use $FieldsToCollect[]  #
# use $DataSums{}         #
###########################
function collectData() {
    for field in "${FieldsToCollect[@]}"; do
        val=$(cat $1 | grep "$field:" | grep -o '[0-9.]\+')
        if [[ -z "$val" ]]; then
            echo -e "${BRED}no $field value${NC}" >&2
            echo "Failed"
            return
        fi
        echo -e "${BGREEN}$field: $val${NC}" >&2
        DataSums[$field]=$(echo "$val + ${DataSums[$field]}"|bc)
    done
}


# ****************** Script Starts Here ****************** #

(( argc = ${#ParamsToSet[@]} + ${#CapsToSet[@]} + 1 ))
if [[ $# -ne $argc ]]; then
    echo "usage: ./eval.sh [output dir] [param setttings] [cap settings]"
    echo "[param setttings] need to have same order as ParamsToSet[]"
    echo "[cap setttings] need to have same order as CapsToSet[]"
    exit
fi
output_dir=$1
shift
declare -A MigrationSettings
declare -A ParamSettings
declare -A CapsSettings
for param in "${ParamsToSet[@]}"; do
    MigrationSettings["$param"]=$1
    ParamSettings["$param"]=$1
    shift
done
for cap in "${CapsToSet[@]}"; do
    MigrationSettings["$cap"]=$1
    CapsSettings["$cap"]=$1
    shift
done

mkdir $output_dir 2>/dev/null

for (( i = 0; i < 1; i++ )); do

    # boot VM
    result=""
    result=$(bootVM $src_ip "src")
    result+=$(bootVM $dst_ip "dst")
    if [[ -n "$result" ]]; then
    echo -e "${BRED}boot VM failed${NC}" >&2
    exit
        rebootM400 $src_ip
        rebootM400 $dst_ip
        sleep 8m
        (( i -= 1 ))
        continue
    fi


    echo -e "${BCYAN}waiting for VMs${NC}" >&2
    sleep 30s


    echo -e "${BCYAN}setting migration parameters${NC}" >&2
    for param in ${#ParamsToSet[@]}; do
        cmd="migrate_set_parameter $param ${ParamSettings[$param]}"
        ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
        ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
    done
    echo -e "${BCYAN}setting migration capabilities${NC}" >&2
    for cap in ${#CapsToSet[@]}; do
        cmd="migrate_set_capability $cap ${CapSettings[$cap]}"
        ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
        ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
    done


    
    echo -e "${BCYAN}starting ab${NC}" >&2
    #TODO


    echo -e "${BCYAN}starting the migration${NC}" >&2
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_migrate"
    echo -e "${BCYAN}wait for the migration to complete${NC}" >&2
    sleep "$expected_max_totaltime"


    echo -e "${BCYAN}fetching migration results${NC}" >&2
    src_fn="$output_dir/src_$i.txt"
    dst_fn="$output_dir/dst_$i.txt"
    ncat -w 10 -i 10 $src_ip $src_monitor_port <<< "$command_info" | strings > $src_fn
    ncat -w 10 -i 10 $dst_ip $dst_monitor_port <<< "$command_info" | strings > $dst_fn
    dos2unix $src_fn
    dos2unix $dst_fn


    echo -e "${BCYAN}stopping ab${NC}" >&2
    #TODO
    

    echo -e "${BCYAN}checking ab validity${NC}" >&2
    #TODO


    result=""
    result+=$(checkValidity $src_fn)
    result+=$(checkValidity $dst_fn)
    if [[ -n "$result" ]]; then
        echo -e "${BRED}migration failed${NC}" >&2
        (( i -= 1 ))
    else
        collectData $src_fn
    fi


    echo -e "${BCYAN}cleaning up VMs${NC}" >&2
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_shutdown"
    ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$command_shutdown"
    echo -e "${BCYAN}wait for VMs to shutdown${NC}" >&2
    sleep 40s

done
