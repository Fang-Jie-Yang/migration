#! /bin/bash

Fields=()
while :
do
    case "$1" in
        -f | --field)
        Fields+=("$2")
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
file_path="$1"

for field in "${Fields[@]}"; do
    val=$(cat "$file_path" | grep "$field:" | grep -o '[0-9.]\+')
    if [[ -z "$val" ]]; then
        echo -e "${BRED}no $field value${NC}" >&2
        exit 1
    else
        echo "$val"
    fi
done

