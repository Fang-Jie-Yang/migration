#! /bin/bash


src_ip="10.10.1.1"
src_port="1234"
dst_ip="10.10.1.2"
dst_port="1235"
migarte_port="8888"
declare -A ParamSettings
declare -A CapSettings
BCYAN='\033[1;36m'
NC='\033[0m'

while :
do
    case "$1" in
        --src)
            src_ip="$2"
            shift 2
            ;;
        --src-port)
            src_port="$2"
            shift 2
            ;;
        --dst)
            dst_ip="$2"
            shift 2
            ;;
        --dst-port)
            dst_port="$2"
            shift 2
            ;;
        --migrate-port)
            migrate_port="$2"
            shift 2
            ;;
        --cap)
            CapSettings["$2"]="$3"
            shift 3
            ;;
        --param)
            ParamSettings["$2"]="$3"
            shift 3
            ;;
        --help | -* | --*)
            echo "Usage: $(basename $0)"
            echo "       [--src src_ip] [--src-port src_port]"
            echo "       [--dst dst_ip] [--dst-port dst_port]"
            echo "       [--migrate-port migrate_port]"
            echo "       [--cap capability_name value] * N"
            echo "       [--param parameter_name value] * N"
            exit 1
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

command_migrate="migrate -d tcp:$dst_ip:$migrate_port"
command_shutdown="quit"

echo -e "${BCYAN}setting migration parameters${NC}" >&2
for param in ${!ParamSettings[@]}; do
    cmd="migrate_set_parameter $param ${ParamSettings[$param]}"
    ncat -w 2 -i 2 $src_ip $src_port <<< "$cmd"
    ncat -w 2 -i 2 $dst_ip $dst_port <<< "$cmd"
    echo "$cmd"
done
echo -e "${BCYAN}setting migration capabilities${NC}" >&2
for cap in ${!CapSettings[@]}; do
    cmd="migrate_set_capability $cap ${CapSettings[$cap]}"
    ncat -w 2 -i 2 $src_ip $src_port <<< "$cmd"
    ncat -w 2 -i 2 $dst_ip $dst_port <<< "$cmd"
    echo "$cmd"
done

echo -e "${BCYAN}starting the migration${NC}" >&2
ncat -w 2 -i 2 $src_ip $src_port <<< "$command_migrate"
