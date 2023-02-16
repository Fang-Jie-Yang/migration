#! /bin/bash

## TODO: Edit the parameters here
src_ip="10.10.1.1"
dst_ip="10.10.1.2"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888
rounds=10
result_file="res-ab-1G"
output_dir="./test"
expected_max_totaltime="50s"

ParamsToSet[0]="multifd-channels"
ParamsToSet[1]="max-bandwidth"
ParamsToSet[2]="downtime-limit"

CapsToSet[0]="multifd"
CapsToSet[1]="compress"

ParamSettings[0]="1 102400 300"
CapsSettings[0]="off off"

# Note: field val can only be number
FieldsToCollect[0]="downtime"
FieldsToCollect[1]="total time"
FieldsToCollect[2]="throughput"
FieldsToCollect[3]="setup"
FieldsToCollect[4]="transferred ram"
FieldsToCollect[5]="multifd bytes"

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

###############################
# $1: log file name           #
# $2: expected settings (Str) #
# $3: setting names     (Arr) #
# --------------------------- #
# ret: null / "Failed"        # 
###############################
function checkValidity() {

    local file=$1
    shift
    local Expects=($1)
    shift
    local Names=($@)

    for (( i = 0; i < ${#Names[@]}; i++ )); do
        param_name=${Names[$i]}
        #TODO: find ways to get field behind keyword
        setting=$(cat $file | awk -v prefix="$param_name:" '$1 == prefix {print $2}')
        expected=${Expects[$i]}
        if [[ $param_name == "max-bandwidth" ]]; then
            (( expected *= 1024 * 1024 ))
        fi
        if [[ "$setting" != "$expected" ]]; then
            echo -e "${BRED}$param_name: $setting, expect $expected${NC}" >&2
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


# *Script Starts Here* #

if [[ ${#ParamSettings[@]} != ${#CapsSettings[@]} ]]; then
    echo -e "number of ParamSettings should equal to CapsSettings" >&2
    exit
fi
setting_num=${#ParamSettings[@]}
echo "settings_num: $setting_num"

mkdir $output_dir

for (( n = 0; n < setting_num; n++ )); do
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


        echo -e "${BCYAN}waiting for VMs${NC}"      
        sleep 30s


        echo -e "${BCYAN}setting migration parameters${NC}"
        values=(${ParamSettings[$n]})
        for (( p = 0; p < ${#ParamsToSet[@]}; p++ )); do
            cmd="migrate_set_parameter ${ParamsToSet[$p]} ${values[$p]}"
            ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
            ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
        done
        echo -e "${BCYAN}setting migration capabilities${NC}"
        values=(${CapsSettings[$n]})
        for (( c = 0; c < ${#CapsToSet[@]}; c++ )); do
            cmd="migrate_set_capability ${CapsToSet[$c]} ${values[$c]}"
            ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
            ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
        done

        
        echo -e "${BCYAN}starting ab${NC}"
        #TODO


        echo -e "${BCYAN}starting the migration${NC}"
        ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_migrate"
        echo -e "${BCYAN}wait for the migration to complete${NC}"
        sleep "$expected_max_totaltime"


        echo -e "${BCYAN}fetching migration results${NC}"
        src_fn="$output_dir/src_$i.txt"
        dst_fn="$output_dir/dst_$i.txt"
        ncat -w 10 -i 10 $src_ip $src_monitor_port <<< "$command_info" | strings > $src_fn
        ncat -w 10 -i 10 $dst_ip $dst_monitor_port <<< "$command_info" | strings > $dst_fn
        dos2unix $src_fn
        dos2unix $dst_fn


        echo -e "${BCYAN}stopping ab${NC}"
        #TODO
        

        echo -e "${BCYAN}checking ab validity${NC}"
        #TODO


        result=$(checkValidity $src_fn "${ParamSettings[$n]}" "${ParamsToSet[@]}")
        result+=$(checkValidity $src_fn "${CapsSettings[$n]}" "${CapsToSet[@]}")
        result+=$(checkValidity $dst_fn "${ParamSettings[$n]}" "${ParamsToSet[@]}")
        result+=$(checkValidity $dst_fn "${CapsSettings[$n]}" "${CapsToSet[@]}")
        if [[ -n "$result" ]]; then
            echo -e "${BRED}migration failed${NC}"
            (( i -= 1 ))
        else
            collectData $src_fn
        fi


        echo -e "${BCYAN}cleaning up VMs${NC}"
        ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_shutdown"
        ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$command_shutdown"
        echo -e "${BCYAN}wait for VMs to shutdown${NC}"
        sleep 40s

    done
done
