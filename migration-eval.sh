#! /bin/bash

## TODO: Edit the parameters here
src_ip="128.110.216.98"
dst_ip="128.110.216.58"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888
src_migration_attr[0]="migrate_set_capability compress on"
src_migration_attr[1]="migrate_set_parameter compress-threads 64"
src_migration_attr[2]="migrate_set_parameter compress-level 9"
dst_migration_attr[0]="migrate_set_capability compress on"
dst_migration_attr[1]="migrate_set_parameter decompress-threads 16"
dst_migration_attr[2]="migrate_set_parameter compress-level 9"
rounds=10
output_dir="./eval-data/eval-compress-64-16-lv9"

command_migrate="migrate -d tcp:$dst_ip:$migration_port"
command_info="info migrate"
command_shutdown="quit"

BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

sum_totaltime=0
sum_downtime=0
totaltime=0
downtime=0
fail=0

mkdir $output_dir

for ((i = 0; i < $rounds; i++)); do

	echo -e "${BCYAN}opening VM on src${NC}"
	ssh $username@$src_ip << EOF
	cd /mydata/some-tutorials/files/blk
	sudo nohup ./blk.sh
EOF

	echo -e "${BCYAN}opening VM on dst${NC}"
	ssh $username@$dst_ip << EOF
	cd /mydata/some-tutorials/files/blk
	sudo nohup ./resume-blk.sh
EOF

	echo -e "${BCYAN}setting migration attributes on src${NC}"
	for attr in "${src_migration_attr[@]}"; do
		nc -N $src_ip $src_monitor_port <<< "$attr"
	done
	echo ""

	echo -e "${BCYAN}setting migration attributes on dst${NC}"
	for attr in "${dst_migration_attr[@]}"; do
		nc -N $dst_ip $dst_monitor_port <<< "$attr"
	done
	echo ""

	echo -e "${BCYAN}starting the migration${NC}"
	nc -N $src_ip $src_monitor_port <<< "$command_migrate"
	echo ""

	echo -e "${BCYAN}wait for the migration to complete${NC}"
	sleep 30s
		
	echo -e "${BCYAN}fetching migration results${NC}"
	nc -N $src_ip $src_monitor_port <<< "$command_info" | \
	tail -n +3 | head -n -1 > "$output_dir/$i.txt"
	totaltime=$(cat "$output_dir/$i.txt" | awk '$1 == "total" && $2 == "time:" {print $3}')
	downtime=$(cat "$output_dir/$i.txt" | awk '$1 == "downtime:" {print $2}')
	if [[ -z "$totaltime" ]]; then
		echo -e "${BRED}migration failed${NC}"
		(( i -= 1 ))
		(( fail += 1 ))
	elif [[ -z "$downtime" ]]; then
		echo -e "${BRED}migration failed${NC}"
		(( i -= 1 ))
		(( fail += 1 ))
	else
		echo "totaltime = $totaltime"
		echo "downtime = $downtime"
		(( sum_totaltime += totaltime ))
		(( sum_downtime += downtime ))
	fi
	echo -e "${BCYAN}cleaning up VMs${NC}"
	nc -N $src_ip $src_monitor_port <<< "$command_shutdown"
	nc -N $dst_ip $dst_monitor_port <<< "$command_shutdown"
	echo -e "${BCYAN}wait for VMs to shutdown${NC}"
	sleep 30s
done

(( sum_totaltime /= rounds ))
(( sum_downtime /= rounds ))
echo "avg totaltime: $sum_totaltime"
echo "avg downtime: $sum_downtime"
echo "fail: $fail"
