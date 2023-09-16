#! /bin/bash


function err_msg() {
	BRED='\033[1;31m'
	NC='\033[0m'
	echo -e "${BRED}$1${NC}" >&2
}

function run_config() {
	./eval.sh $1
	if [[ $? -ne 0 ]]; then
		err_msg "$1 aborted!"
	fi
}

run_config example-config.sh
run_config idle-config.sh
