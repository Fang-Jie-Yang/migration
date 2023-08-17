#! /bin/bash


# -------------------- Setting --------------------- #

## VM scripts
vm_src="qemu_scripts/blk.sh"
vm_dst="qemu_scripts/resume-blk.sh"

## Network Settings
src_ip="10.10.1.1"
dst_ip="10.10.1.2"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888

## Evaluation Settings
expected_max_totaltime="20s"
#ParamsToSet[0]="multifd-channels"
#CapsToSet[0]="multifd"

# ----------------- Setting Ends ------------------- #

command_migrate="migrate -d tcp:$dst_ip:$migration_port"
command_shutdown="quit"

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

# ****************** Script Starts Here ****************** #

(( argc = ${#ParamsToSet[@]} + ${#CapsToSet[@]} ))
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

echo -e "${BCYAN}setting migration parameters${NC}" >&2
for param in ${ParamsToSet[@]}; do
    cmd="migrate_set_parameter $param ${ParamSettings[$param]}"
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd"
    ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd"
done
echo -e "${BCYAN}setting migration capabilities${NC}" >&2
for cap in ${CapsToSet[@]}; do
    cmd="migrate_set_capability $cap ${CapsSettings[$cap]}"
    ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$cmd"
    ncat -w 5 -i 2 $dst_ip $dst_monitor_port <<< "$cmd"
done

echo -e "${BCYAN}starting the migration${NC}" >&2
ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "$command_migrate"
#FIXME: hard coded postcopy
#ncat -w 5 -i 2 $src_ip $src_monitor_port <<< "migrate_start_postcopy"
