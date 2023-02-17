#! /bin/bash

if [[ $# -ne 2 ]]; then
	echo "usage: ./migration-eval.sh compress-level max-bandwidth"
	exit
fi
compress_level="$1"
max_bandwidth="$2"
(( max_bandwidth_Bps = max_bandwidth * 1024 * 1024))
downtime_limit="3000"
wait_thread="on"

## TODO: Edit the parameters here
src_ip="128.110.216.43"
dst_ip="128.110.216.52"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888
rounds=10
output_dir_root="./eval-sw-no-crypt-idle-8mb-data"
result_prefix="res-sw-no-crypt-busy-idle-8mb-8thread"
expected_max_downtime="90s"

Compress[0]="off"
Compress[1]="on"
Compress[2]="on"
Compress[3]="on"
Compress[4]="on"
Compress_threads[0]="8"
Compress_threads[1]="8"
Compress_threads[2]="8"
Compress_threads[3]="8"
Compress_threads[4]="8"
Decompress_threads[0]="1"
Decompress_threads[1]="1"
Decompress_threads[2]="2"
Decompress_threads[3]="4"
Decompress_threads[4]="8"

command_migrate="migrate -d tcp:$dst_ip:$migration_port"
command_info="info migrate
info migrate_parameters
info migrate_capabilities"
command_shutdown="quit"
mutual_migration_attr[0]="migrate_set_parameter compress-level $compress_level"
mutual_migration_attr[1]="migrate_set_parameter max-bandwidth $max_bandwidth"
mutual_migration_attr[2]="migrate_set_parameter downtime-limit $downtime_limit"
mutual_migration_attr[3]="migrate_set_parameter compress-wait-thread $wait_thread"
result_path="$result_prefix-$compress_level-$max_bandwidth.txt"

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

mkdir $output_dir_root
mkdir "$output_dir_root/bandwitdh-$max_bandwidth-level-$compress_level"

echo "max bandwidth: $max_bandwidth" > $result_path
echo "compress level: $compress_level" >> $result_path

for ((t = 0; t < 2; t++)); do

    # set up output directory
	output_dir="$output_dir_root/bandwitdh-$max_bandwidth-level-$compress_level/"
	output_dir+="compress-${Compress[$t]}-${Compress_threads[$t]}-${Decompress_threads[$t]}"
	mkdir "$output_dir"

	sum_totaltime=0
	sum_downtime=0
	sum_rate=0
	totaltime=0
	downtime=0
	fail=0

	src_migration_attr[0]="migrate_set_capability compress ${Compress[$t]}"
	src_migration_attr[1]="migrate_set_parameter compress-threads ${Compress_threads[$t]}"
	dst_migration_attr[0]="migrate_set_capability compress ${Compress[$t]}"
	dst_migration_attr[1]="migrate_set_parameter decompress-threads ${Decompress_threads[$t]}"

	for ((i = 0; i < $rounds; i++)); do

		echo -e "${BCYAN}opening VM on src${NC}"
		log=$( { ssh $username@$src_ip << EOF
		cd /mydata/some-tutorials/files/blk
		nohup sudo ./blk.sh --fs /proj/ntucsie-PG0/kevin/cloud-hack.img
EOF
		} 2>&1 )

		echo -e "${BCYAN}opening VM on dst${NC}"
		log+=$( { ssh $username@$dst_ip << EOF
		cd /mydata/some-tutorials/files/blk
		nohup sudo ./resume-blk.sh --fs /proj/ntucsie-PG0/kevin/cloud-hack.img
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
        fi

		err=$(echo "$log" | grep "qemu-system-aarch64: -drive if=none,file=/proj/ntucsie-PG0/fjyang/cloud-hack.img,id=vda,cache=none,format=raw: Could not open '/proj/ntucsie-PG0/fjyang/cloud-hack.img': No such file or directory")
		if [[ -n "$err" ]]; then
			echo -e "${BRED}NFS broken, remounting${NC}"		
			ssh $username@$src_ip << EOF
			sudo mount ops.utah.cloudlab.us:/proj/ntucsie-PG0 /proj/ntucsie-PG0
EOF
			ssh $username@$dst_ip << EOF
			sudo mount ops.utah.cloudlab.us:/proj/ntucsie-PG0 /proj/ntucsie-PG0
EOF
			(( i -= 1 ))
			continue
        fi

        echo -e "${BCYAN}waiting for VMs${NC}"		
        sleep 10s


		echo -e "${BCYAN}setting migration attributes on src${NC}"
		for attr in "${src_migration_attr[@]}"; do
			ncat -w 5s --send-only $src_ip $src_monitor_port <<< "$attr"
		done
		for attr in "${mutual_migration_attr[@]}"; do
			ncat -w 5s --send-only $src_ip $src_monitor_port <<< "$attr"
		done

		echo -e "${BCYAN}setting migration attributes on dst${NC}"
		for attr in "${dst_migration_attr[@]}"; do
			ncat -w 5s --send-only $dst_ip $dst_monitor_port <<< "$attr"
		done
		for attr in "${mutual_migration_attr[@]}"; do
			ncat -w 5s --send-only $dst_ip $dst_monitor_port <<< "$attr"
		done

		echo -e "${BCYAN}starting the migration${NC}"
		ncat -w 5s --send-only $src_ip $src_monitor_port <<< "$command_migrate"

		echo -e "${BCYAN}wait for the migration to complete${NC}"
		sleep "$expected_max_downtime"


		echo -e "${BCYAN}fetching migration results${NC}"
		ncat --wait 5s $src_ip $src_monitor_port <<< "$command_info" | strings > "$output_dir/src_$i.txt"
		ncat --wait 5s $dst_ip $dst_monitor_port <<< "$command_info" | strings > "$output_dir/dst_$i.txt"

        failed="False"
		dos2unix "$output_dir/src_$i.txt"
		dos2unix "$output_dir/dst_$i.txt"

        src_compress_level=$(cat "$output_dir/src_$i.txt" | awk '$1 == "compress-level:"  {print $2}')
        if [[ "$src_compress_level" != "$compress_level" ]]; then
            echo -e "${BRED}src_compress_level: $src_compress_level${NC}"
            failed="True"
        fi
        src_compress=$(cat "$output_dir/src_$i.txt" | awk '$1 == "compress:"  {print $2}')
        if [[ "$src_compress" != "${Compress[$t]}" ]]; then
            echo -e "${BRED}src_compress: $src_compress${NC}"
            failed="True"
        fi
        src_limit=$(cat "$output_dir/src_$i.txt" | awk '$1 == "downtime-limit:"  {print $2}')
        if [[ "$src_limit" != "$downtime_limit" ]]; then
            echo -e "${BRED}src_limit: $src_limit${NC}"
            failed="True"
        fi
        src_wait_thread=$(cat "$output_dir/src_$i.txt" | awk '$1 == "compress-wait-thread:"  {print $2}')
        if [[ "$src_wait_thread" != "$wait_thread" ]]; then
            echo -e "${BRED}src_wait_thread: $src_wait_thread${NC}"
            failed="True"
        fi
        
        dst_compress_level=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "compress-level:"  {print $2}')
        if [[ "$dst_compress_level" != "$compress_level" ]]; then
            echo -e "${BRED}dst_compress_level: $dst_compress_level${NC}"
            failed="True"
        fi
        dst_compress=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "compress:"  {print $2}')
        if [[ "$dst_compress" != "${Compress[$t]}" ]]; then
            echo -e "${BRED}dst_compress: $dst_compress${NC}"
            failed="True"
        fi
        dst_limit=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "downtime-limit:"  {print $2}')
        if [[ "$dst_limit" != "$downtime_limit" ]]; then
            echo -e "${BRED}dst_limit: $dst_limit${NC}"
            failed="True"
        fi
        dst_wait_thread=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "compress-wait-thread:"  {print $2}')
        if [[ "$dst_wait_thread" != "$wait_thread" ]]; then
            echo -e "${BRED}dst_wait_thread: $dst_wait_thread${NC}"
            failed="True"
        fi

        src_bandwidth=$(cat "$output_dir/src_$i.txt" | awk '$1 == "max-bandwidth:"  {print $2}')
        if [[ "$src_bandwidth" != "$max_bandwidth_Bps" ]]; then
            echo -e "${BRED}src_bandwidth: $src_bandwidth${NC}"
            failed="True"
        fi

        dst_bandwidth=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "max-bandwidth:"  {print $2}')
        if [[ "$dst_bandwidth" != "$max_bandwidth_Bps" ]]; then
            echo -e "${BRED}dst_bandwidth: $dst_bandwidth${NC}"
            failed="True"
        fi
        compress_threads=$(cat "$output_dir/src_$i.txt" | awk '$1 == "compress-threads:"  {print $2}')
        if [[ "$compress_threads" != "${Compress_threads[$t]}" ]]; then
            echo -e "${BRED}compress_threads: $compress_threads${NC}"
            failed="True"
        fi
        decompress_threads=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "decompress-threads:"  {print $2}')
        if [[ "$decompress_threads" != "${Decompress_threads[$t]}" ]]; then
            echo -e "${BRED}decompress_threads: $decompress_threads${NC}"
            failed="True"
        fi

		totaltime=$(cat "$output_dir/src_$i.txt" | awk '$1 == "total" && $2 == "time:" {print $3}')
        if [[ -z "$totaltime" ]]; then
            echo -e "${BRED}totaltime${NC}"
            failed="True"
        fi
		downtime=$(cat "$output_dir/src_$i.txt" | awk '$1 == "downtime:" {print $2}')
        if [[ -z "$downtime" ]]; then
            echo -e "${BRED}downtime${NC}"
            failed="True"
        fi
		compress_rate=$(cat "$output_dir/src_$i.txt" | awk '$1 == "compression" && $2 == "rate:" {print $3}')
        if [[ -n "$compress_rate" ]]; then
            if [[ "$compress_rate" == "0.00" ]]; then
                echo -e "${BRED}compression rate${NC}"
                failed="True"
            fi
        fi


		if [[ "$failed" == "True" ]]; then
			echo -e "${BRED}migration failed${NC}"
			(( i -= 1 ))
			(( fail += 1 ))
        else
			echo -e "${BGREEN}totaltime = $totaltime${NC}"
			echo -e "${BGREEN}downtime = $downtime${NC}"
			(( sum_totaltime += totaltime ))
			(( sum_downtime += downtime ))
			if [[ "${Compress[$t]}" == "on" ]]; then 
				echo -e "${BGREEN}compress rate = $compress_rate${NC}"
				sum_rate=$(echo "$compress_rate + $sum_rate"|bc)
			fi
		fi

		echo -e "${BCYAN}cleaning up VMs${NC}"
		ncat -w 5s --send-only $src_ip $src_monitor_port <<< "$command_shutdown"
		ncat -w 5s --send-only $dst_ip $dst_monitor_port <<< "$command_shutdown"
		echo -e "${BCYAN}wait for VMs to shutdown${NC}"
		sleep 30s
	done

	(( sum_totaltime /= rounds ))
	(( sum_downtime /= rounds ))
	sum_rate=$(echo "scale=4; $sum_rate / $rounds"|bc)
	echo "$sum_downtime $sum_totaltime $sum_rate $fail" >> $result_path
	echo -e "${BGREEN}t=$t, done${NC}"
done
