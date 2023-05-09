#! /bin/bash


# -------------------- Setting --------------------- #

## VM scripts
script_dir="qemu_scripts"
#vm_src="ab.sh"
#vm_dst="ab-res.sh"
#vm_src="blk.sh"
#vm_dst="resume-blk.sh"
vm_src="$1"
shift
vm_dst="$1"
shift

## Network Settings
src_ip="10.10.1.1"
dst_ip="10.10.1.2"
guest_ip="10.10.1.5"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888

## Evaluation Settings
ab="$1"
shift
rounds=10
expected_max_totaltime="40s"
ParamsToSet[0]="downtime-limit"
ParamsToSet[1]="max-bandwidth" #Mbps
ParamsToSet[2]="multifd-channels"
ParamsToSet[3]="max-postcopy-bandwidth" #bps
CapsToSet[0]="multifd"
CapsToSet[1]="postcopy-ram"
CapsToSet[2]="compress"

# Note: field val can only be number
FieldsToCollect[0]="downtime"
FieldsToCollect[1]="total time"
FieldsToCollect[2]="throughput"
FieldsToCollect[3]="setup"
FieldsToCollect[4]="transferred ram"

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
# $2: vm script         #
# --------------------- #
# ret: null / "Failed"  #
# --------------------- #
# use $username         #
#########################
function bootVM() {

    echo -e "${BCYAN}booting VM on $1 using $2${NC}" >&2

    script="./$2"

    log=$( { ssh $username@$1 << EOF
    sudo /srv/vm/net.sh
    sudo nohup $script --bridge
EOF
    } 2>&1 )

    err=""
    err+=$(echo "$log" | grep "Failed to retrieve host CPU features")
    err+=$(echo "$log" | grep "Address already in use")
    err+=$(echo "$log" | grep "No such file or directory")
    if [[ -n "$err" ]]; then
        echo "Failed"
	echo "$log" | tail -n 1 >&2
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

    log=$( { ssh $username@$1 << EOF
    sudo reboot
EOF
    } 2>&1 )
}

#########################
# $1: ip addr           #
# --------------------- #
# ret: null             #
# --------------------- #
# use $username         #
#########################
function stressCPU() {

    echo -e "${BCYAN}stressing CPUs on $1${NC}" >&2

    log=$( { ssh $username@$1 << EOF
        nohup stress-ng --cpu 8 -t $expected_max_totaltime 2>&1 & 
EOF
    } 2>&1 )
}

function stressNetwork() {

    echo -e "${BCYAN}stressing network${NC}" >&2

    log=$( { ssh $username@$1 << EOF
        nohup iperf -s 2>&1 & 
EOF
    } 2>&1 )
    log=$( { ssh $username@$2 << EOF
        nohup iperf -c $1 -t $expected_max_totaltime 2>&1 & 
EOF
    } 2>&1 )
    echo "$log" >&2
}

#########################
# $1: ip addr           #
# --------------------- #
# ret: null             #
# --------------------- #
# use $username         #
#########################
function setupBridgeNetwork() {

    log=$( { ssh $username@$1 << EOF
    sudo /srv/vm/net.sh
EOF
    } 2>&1 )
}

###########################
# $1: log file name       #
# ----------------------- #
# ret: null / "Failed"    # 
# ----------------------- #
# use MigrationSettings[] #
###########################
function checkValidity() {

    status=$(cat $1 | awk '$1 == "Migration" && $2 == "status:" {print $3}')

    if [[ "$status" != "completed" ]]; then
        echo -e "${BRED}Migration status: $status${NC}" >&2
	echo "Failed"
	return
    fi

    for name in ${!MigrationSettings[@]}; do
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
        #echo "${BGREEN}$name = $setting${NC}" >&2
    done
}


###########################
# $1: log file name       #
# ----------------------- #
# ret: data / null        # 
# ----------------------- #
# use $FieldsToCollect[]  #
###########################
function collectData() {
    for field in "${FieldsToCollect[@]}"; do
        val=$(cat $1 | grep "$field:" | grep -o '[0-9.]\+')
        if [[ -z "$val" ]]; then
            echo -e "${BRED}no $field value${NC}" >&2
            return
        fi
    done
    for field in "${FieldsToCollect[@]}"; do
        val=$(cat $1 | grep "$field:" | grep -o '[0-9.]\+')
        echo -e "${BGREEN}$field: $val${NC}" >&2
        echo -n "$val "
    done
}


# ****************** Script Starts Here ****************** #

(( argc = ${#ParamsToSet[@]} + ${#CapsToSet[@]} + 1 ))
if [[ $# -ne $argc ]]; then
    echo "usage: ./eval.sh [output dir] [param setttings] [cap settings]"
    echo -n "[param setttings]: "
    for param in ${ParamsToSet[@]}; do
        echo -n "$param "
    done
    echo ""
    echo -n "[cap setttings]: "
    for cap in ${CapsToSet[@]}; do
        echo -n "$cap "
    done
    echo ""
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

echo -e "${BCYAN}uploading VM boot scripts${NC}" >&2
scp "$script_dir/$vm_src" $username@$src_ip:~/"$vm_src" >&2
scp "$script_dir/$vm_dst" $username@$dst_ip:~/"$vm_dst" >&2

#setupBridgeNetwork $src_ip
#setupBridgeNetwork $dst_ip

mkdir $output_dir 2>/dev/null

consecutive_failure=0

for (( i = 0; i < $rounds; i++ )); do

    if [[ $consecutive_failure -gt 5 ]]; then
        echo -e "${BRED}too much failure, rebooting${NC}" >&2
	consecutive_failure=0
        rebootM400 $src_ip
        rebootM400 $dst_ip
        sleep 10m
        (( i -= 1 ))
        continue
    fi

    # FIXME: hard coded path
    if [[ "$ab" == "on" ]]; then
    	sudo cp /proj/ntucsie-PG0/fjyang/cloud-hack-ab-bak.img /proj/ntucsie-PG0/fjyang/cloud-hack-ab.img
    else
    	sudo cp /proj/ntucsie-PG0/fjyang/cloud-hack-backup.img /proj/ntucsie-PG0/fjyang/cloud-hack.img
    fi

    # boot VM
    result=""
    result=$(bootVM $src_ip "$vm_src")
    result+=$(bootVM $dst_ip "$vm_dst")
    if [[ -n "$result" ]]; then
        echo -e "${BRED}boot VM failed${NC}" >&2
        rebootM400 $src_ip
        rebootM400 $dst_ip
        sleep 10m
        #setupBridgeNetwork $src_ip
        #setupBridgeNetwork $dst_ip
        (( i -= 1 ))
        continue
    fi


    echo -e "${BCYAN}waiting for VMs${NC}" >&2
    sleep 20s


    echo -e "${BCYAN}setting migration parameters${NC}" >&2
    for param in ${ParamsToSet[@]}; do
        cmd="migrate_set_parameter $param ${ParamSettings[$param]}"
        ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
        ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
    done
    echo -e "${BCYAN}setting migration capabilities${NC}" >&2
    for cap in ${CapsToSet[@]}; do
        cmd="migrate_set_capability $cap ${CapsSettings[$cap]}"
        ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
        ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd" 2>/dev/null >/dev/null
    done


    if [[ $ab == "on" ]]; then 
        ab_fn="$output_dir/ab_$i.txt"
        while ! curl -m 10 "http://$guest_ip/" >&2 --output index.html ; do
            echo -e "${BRED}apache not up yet${NC}" >&2
    	done
        echo -e "${BCYAN}starting ab${NC}" >&2
        /users/fjyang/httpd-2.4.54/support/ab -c 50 -n 60000 -s 10 -g "$ab_fn" http://10.10.1.5/ >&2 & 
        ab_pid=$!
	sleep 5s
    fi

    #stressNetwork $src_ip $dst_ip
    #stressCPU $dst_ip
    #stressCPU $src_ip
    #sleep 3s

    echo -e "${BCYAN}starting the migration${NC}" >&2
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_migrate" 2>/dev/null > /dev/null
    # FIXME: hard coded postcopy start
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "migrate_start_postcopy" 2> /dev/null > /dev/null
    echo -e "${BCYAN}wait for the migration to complete${NC}" >&2
    sleep "$expected_max_totaltime"

    echo -e "${BCYAN}fetching migration results${NC}" >&2
    src_fn="$output_dir/src_$i.txt"
    dst_fn="$output_dir/dst_$i.txt"
    ncat -w 10 -i 10 $src_ip $src_monitor_port <<< "$command_info" 2> /dev/null | strings > $src_fn
    ncat -w 10 -i 10 $dst_ip $dst_monitor_port <<< "$command_info" 2> /dev/null | strings > $dst_fn
    dos2unix $src_fn
    dos2unix $dst_fn

    result=""
    if [[ $ab == "on" ]]; then
        echo -e "${BCYAN}checking ab validity${NC}" >&2
        #if ! ps -p $ab_pid > /dev/null; then
        #    echo -e "${BRED}ab stopped early${NC}" >&2
        #    result+="Failed"
        #fi
        #echo -e "${BCYAN}stopping ab${NC}" >&2
        #sudo kill -SIGINT "$ab_pid" >&2
	#sudo kill -SIGINT $(pgrep ab) >&2
        #sleep 10s
	if [ ! -f "$ab_fn" ]; then
            echo -e "${BRED}ab output missing${NC}" >&2
            result+="Failed"
	fi 
    fi


    if [[ $ab == "on" ]]; then 
        #if curl -m 10 "http://$guest_ip/64kb" --output 64kb >&2 ; then
        if curl -m 10 "http://$guest_ip/" >&2 --output index.html ; then
            echo -e "${BGREEN}dst alive${NC}" >&2
        else
            echo -e "${BRED}dst dead${NC}" >&2
            result+="Failed"
        fi
    else 
	if ping -c 3 "$guest_ip" >&2 ; then
            echo -e "${BGREEN}dst alive${NC}" >&2
        else
            echo -e "${BRED}dst dead${NC}" >&2
            result+="Failed"
        fi
    fi

    result+=$(checkValidity $src_fn)
    result+=$(checkValidity $dst_fn)
    if [[ -n "$result" ]]; then
        echo -e "${BRED}migration failed${NC}" >&2
        (( consecutive_failure += 1 ))
        (( i -= 1 ))
    else
        data=$(collectData $src_fn)
        if [[ -z "$data" ]]; then
            echo -e "${BRED}migration failed${NC}" >&2
	    (( consecutive_failure += 1 ))
            (( i -= 1 ))
        else
            data=( $data )
            for (( j = 0; j < ${#FieldsToCollect[@]}; j++)); do
                field=${FieldsToCollect[$j]}
                DataSums[$field]=$(echo "${data[$j]} + ${DataSums[$field]}"|bc)
            done
            consecutive_failure=0
        fi
    fi

    echo -e "${BCYAN}cleaning up VMs${NC}" >&2
    ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$command_shutdown" 2> /dev/null > /dev/null
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_shutdown" 2> /dev/null > /dev/null
    echo -e "${BCYAN}wait for VMs to shutdown${NC}" >&2
    sleep 20s

done

for field in "${FieldsToCollect[@]}"; do
    avg=$(echo "scale=4; ${DataSums[$field]} / $rounds"|bc)
    echo -n "$avg "
done
echo ""
