#!/bin/bash

Fields=()
declare -A Values
while :
do
    case "$1" in
        -f | --field)
            Fields+=("$2")
            Values["$2"]=0
            shift 2
            ;;
        --help | -* | --*)
            echo "Usage: $(basename $0)"
            echo "       [(-f|--field) field_name] * N"
            echo "       file_path"
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

cnt=0
while :
do
    file_name="$1"
    if [[ -n "$file_name" ]]; then
        for field in "${Fields[@]}"; do
            val=$(./read.sh --field "$field" "$file_name")
            Values["$field"]=$(echo "$val" + ${Values["$field"]}|bc)
        done
        (( cnt += 1 ))
        shift
    else
        break
    fi
done

for field in "${Fields[@]}"; do
    avg=$(echo "scale=4; ${Values[$field]} / $cnt"|bc)
    echo -n "$avg "
done
echo ""
