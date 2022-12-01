#! /bin/bash

if [[ $# -ne 2 ]]; then
	echo "usage: ./migration-eval.sh compress-level max-bandwidth"
	exit
fi
compress_level="$1"
max_bandwidth="$2"

## TODO: Edit the parameters here
src_ip="128.110.216.73"
dst_ip="128.110.216.57"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888
rounds=10
output_dir_root="./eval-data"
result_prefix="res"

compress[0]="off"
compress[1]="on"
compress[2]="on"
compress[3]="on"
compress[4]="on"
compress[5]="on"
compress[6]="on"
compress[7]="on"
compress[8]="on"
compress_threads[0]="8"
compress_threads[1]="8"
compress_threads[2]="8"
compress_threads[3]="16"
compress_threads[4]="16"
compress_threads[5]="32"
compress_threads[6]="32"
compress_threads[7]="64"
compress_threads[8]="64"
decompress_threads[0]="1"
decompress_threads[1]="1"
decompress_threads[2]="2"
decompress_threads[3]="1"
decompress_threads[4]="4"
decompress_threads[5]="1"
decompress_threads[6]="8"
decompress_threads[7]="1"
decompress_threads[8]="16"

command_migrate="migrate -d tcp:$dst_ip:$migration_port"
command_info="info migrate"
command_shutdown="quit"
mutual_migration_attr[0]="migrate_set_parameter compress-level $compress_level"
mutual_migration_attr[1]="migrate_set_parameter max-bandwidth $max_bandwidth"
result_path="$result_prefix-$compress_level-$max_bandwidth.txt"

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

mkdir $output_dir_root
mkdir "$output_dir_root/bandwitdh-$max_bandwidth-level-$compress_level"

echo "max bandwidth: $max_bandwidth" > $result_path
echo "compress level: $compress_level" >> $result_path

for ((t = 0; t < 9; t++)); do

    # set up output directory
	output_dir="$output_dir_root/bandwitdh-$max_bandwidth-level-$compress_level/"
	output_dir+="compress-${compress[$t]}-${compress_threads[$t]}-${decompress_threads[$t]}"
	mkdir "$output_dir"

	sum_totaltime=0
	sum_downtime=0
	sum_rate=0
	totaltime=0
	downtime=0
	fail=0

	src_migration_attr[0]="migrate_set_capability compress ${compress[$t]}"
	src_migration_attr[1]="migrate_set_parameter compress-threads ${compress_threads[$t]}"
	dst_migration_attr[0]="migrate_set_capability compress ${compress[$t]}"
	dst_migration_attr[1]="migrate_set_parameter decompress-threads ${decompress_threads[$t]}"

	for ((i = 0; i < $rounds; i++)); do

		echo -e "${BCYAN}opening VM on src${NC}"
		log=$( { ssh $username@$src_ip << EOF
		cd /mydata/some-tutorials/files/blk
		sudo nohup ./blk.sh
EOF
		} 2>&1 )
		
		echo -e "${BCYAN}opening VM on dst${NC}"
		log+=$( { ssh $username@$dst_ip << EOF
		cd /mydata/some-tutorials/files/blk
		sudo nohup ./resume-blk.sh
EOF
		} 2>&1 )

		err=$(echo "$log" | grep "qemu-system-aarch64: Failed to retrieve host CPU features")
		if [[ -n "$err" ]]; then
			echo -e "${BRED}qemu broken, rebooting${NC}"		
			ssh $username@$src_ip << EOF
			sudo reboot
EOF
			ssh $username@$dst_ip << EOF
			sudo reboot
EOF
			echo -e "${BCYAN}waiting for reboot${NC}"		
			sleep 8m
			(( i -= 1 ))
			continue
        else
			echo -e "${BCYAN}waiting for VMs${NC}"		
            sleep 10s
        fi


		echo -e "${BCYAN}setting migration attributes on src${NC}"
		for attr in "${src_migration_attr[@]}"; do
			ncat --send-only $src_ip $src_monitor_port <<< "$attr"
		done
		for attr in "${mutual_migration_attr[@]}"; do
			ncat --send-only $src_ip $src_monitor_port <<< "$attr"
		done

		echo -e "${BCYAN}setting migration attributes on dst${NC}"
		for attr in "${dst_migration_attr[@]}"; do
			ncat --send-only $dst_ip $dst_monitor_port <<< "$attr"
		done
		for attr in "${mutual_migration_attr[@]}"; do
			ncat --send-only $src_ip $src_monitor_port <<< "$attr"
		done

		echo -e "${BCYAN}starting the migration${NC}"
		ncat --send-only $src_ip $src_monitor_port <<< "$command_migrate"
		echo ""

		echo -e "${BCYAN}wait for the migration to complete${NC}"
		sleep "$expected_max_downtime"
			

		echo -e "${BCYAN}checking migration attrs${NC}"
        # TODO


		echo -e "${BCYAN}fetching migration results${NC}"
		ncat $src_ip $src_monitor_port <<< "$command_info" | \
		tail -n +3 | head -n -1 > "$output_dir/$i.txt"
		dos2unix "$output_dir/$i.txt"
		totaltime=$(cat "$output_dir/$i.txt" | awk '$1 == "total" && $2 == "time:" {print $3}')
		downtime=$(cat "$output_dir/$i.txt" | awk '$1 == "downtime:" {print $2}')
		compress_rate=$(cat "$output_dir/$i.txt" | awk '$1 == "compression" && $2 == "rate:" {print $3}')
		if [[ -z "$totaltime" ]]; then
			echo -e "${BRED}migration failed${NC}"
			(( i -= 1 ))
			(( fail += 1 ))
		elif [[ -z "$downtime" ]]; then
			echo -e "${BRED}migration failed${NC}"
			(( i -= 1 ))
			(( fail += 1 ))
		else
			echo -e "${BGREEN}totaltime = $totaltime${NC}"
			echo -e "${BGREEN}downtime = $downtime${NC}"
			(( sum_totaltime += totaltime ))
			(( sum_downtime += downtime ))
			if [[ "${compress[$t]}" == "on" ]]; then 
				echo -e "${BGREEN}compress rate = $compress_rate${NC}"
				sum_rate=$(echo "$compress_rate + $sum_rate"|bc)
			fi
		fi
		echo -e "${BCYAN}cleaning up VMs${NC}"
		ncat --send-only $src_ip $src_monitor_port <<< "$command_shutdown"
		ncat --send-only $dst_ip $dst_monitor_port <<< "$command_shutdown"
		echo -e "${BCYAN}wait for VMs to shutdown${NC}"
		sleep 30s
	done

	(( sum_totaltime /= rounds ))
	(( sum_downtime /= rounds ))
	sum_rate=$(echo "scale=4; $sum_rate / $rounds"|bc)
	echo "$sum_downtime $sum_totaltime $sum_rate $fail" >> $result_path
	echo -e "${BCYAN}t=$t, done${NC}"
done
