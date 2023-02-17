#! /bin/bash

if [[ $# -ne 1 ]]; then
	echo "usage: ./migration-eval.sh max-bandwidth"
	exit
fi
max_bandwidth="$1"
(( max_bandwidth_Bps = max_bandwidth * 1024 * 1024))

## TODO: Edit the parameters here
src_ip="128.110.217.22"
dst_ip="128.110.217.16"
username="fjyang"
src_monitor_port="1234"
dst_monitor_port="1235"
migration_port=8888
rounds=10
output_dir_root="./eval-data-multifd"
result_prefix="res"
expected_max_totaltime="30s"

MultiFD[0]="off"
MultiFD[1]="on"
MultiFD[2]="on"
MultiFD_channels[0]="1"
MultiFD_channels[1]="2"
MultiFD_channels[2]="4"

command_migrate="migrate -d tcp:$dst_ip:$migration_port"
command_info="info migrate
info migrate_parameters
info migrate_capabilities"
command_shutdown="quit"
mutual_migration_attr[0]="migrate_set_parameter max-bandwidth $max_bandwidth"
mutual_migration_attr[1]="migrate_set_parameter downtime-limit 3000"
result_path="$result_prefix-limit-$max_bandwidth.txt"

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

mkdir $output_dir_root
mkdir "$output_dir_root/bandwitdh-$max_bandwidth"

echo "max bandwidth: $max_bandwidth" > $result_path

for ((t = 0; t < 3; t++)); do

    # set up output directory
	output_dir="$output_dir_root/bandwitdh-$max_bandwidth/"
	output_dir+="multifd-${MultiFD[$t]}-channels-${MultiFD_channels[$t]}"
	mkdir "$output_dir"

	sum_totaltime=0
	sum_downtime=0
	sum_setup=0
    sum_transferred_ram=0
    sum_throughput=0
    sum_multifd_bytes=0
    sum_pages_per_second=0

	totaltime=0
	downtime=0
	setup=0
    transferred_ram=0
    throughput=0
    multifd_bytes=0
    pages_per_second=0

	fail=0

	src_migration_attr[0]="migrate_set_capability multifd ${MultiFD[$t]}"
	src_migration_attr[1]="migrate_set_parameter  multifd-channels ${MultiFD_channels[$t]}"
	dst_migration_attr[0]="migrate_set_capability multifd ${MultiFD[$t]}"
	dst_migration_attr[1]="migrate_set_parameter  multifd-channels ${MultiFD_channels[$t]}"

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
			ncat --send-only $dst_ip $dst_monitor_port <<< "$attr"
		done

		echo -e "${BCYAN}starting the migration${NC}"
		ncat --send-only $src_ip $src_monitor_port <<< "$command_migrate"

		echo -e "${BCYAN}wait for the migration to complete${NC}"
		sleep "$expected_max_totaltime"


		echo -e "${BCYAN}fetching migration results${NC}"
		ncat $src_ip $src_monitor_port <<< "$command_info" | strings > "$output_dir/src_$i.txt"
		ncat $dst_ip $dst_monitor_port <<< "$command_info" | strings > "$output_dir/dst_$i.txt"

        failed="False"
		dos2unix "$output_dir/src_$i.txt"
		dos2unix "$output_dir/dst_$i.txt"


        src_multifd=$(cat "$output_dir/src_$i.txt" | awk '$1 == "multifd:"  {print $2}')
        if [[ "$src_multifd" != "${MultiFD[$t]}" ]]; then
            echo -e "${BRED}src_multifd: $src_multifd${NC}"
            failed="True"
        fi
        dst_multifd=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "multifd:"  {print $2}')
        if [[ "$dst_multifd" != "${MultiFD[$t]}" ]]; then
            echo -e "${BRED}dst_multifd: $dst_multifd${NC}"
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
        src_downtime_limit=$(cat "$output_dir/src_$i.txt" | awk '$1 == "downtime-limit:"  {print $2}')
        if [[ "$src_downtime_limit" != "3000" ]]; then
            echo -e "${BRED}src_downtime_limit: $src_downtime_limit${NC}"
            failed="True"
        fi
        dst_downtime_limit=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "downtime-limit:"  {print $2}')
        if [[ "$dst_downtime_limit" != "3000" ]]; then
            echo -e "${BRED}dst_downtime_limit: $dst_downtime_limit${NC}"
            failed="True"
        fi
        multifd_channels=$(cat "$output_dir/src_$i.txt" | awk '$1 == "multifd-channels:"  {print $2}')
        if [[ "$multifd_channels" != "${MultiFD_channels[$t]}" ]]; then
            echo -e "${BRED}src_multifd_channels: $multifd_channels${NC}"
            failed="True"
        fi
        multifd_channels=$(cat "$output_dir/dst_$i.txt" | awk '$1 == "multifd-channels:"  {print $2}')
        if [[ "$multifd_channels" != "${MultiFD_channels[$t]}" ]]; then
            echo -e "${BRED}dst_multifd_channels: $multifd_channels${NC}"
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
		setup=$(cat "$output_dir/src_$i.txt" | awk '$1 == "setup:" {print $2}')
        if [[ -z "$setup" ]]; then
            echo -e "${BRED}setup${NC}"
            failed="True"
        fi
		transferred_ram=$(cat "$output_dir/src_$i.txt" | awk '$1 == "transferred" {print $3}')
        if [[ -z "$transferred_ram" ]]; then
            echo -e "${BRED}transferred_ram${NC}"
            failed="True"
        fi
		throughput=$(cat "$output_dir/src_$i.txt" | awk '$1 == "throughput:" {print $2}')
        if [[ -z "$throughput" ]]; then
            echo -e "${BRED}throughput${NC}"
            failed="True"
        fi
		multifd_bytes=$(cat "$output_dir/src_$i.txt" | awk '$1 == "multifd" {print $3}')
        if [[ -z "$multifd_bytes" ]]; then
            echo -e "${BRED}multifd_bytes${NC}"
            failed="True"
        fi
		pages_per_second=$(cat "$output_dir/src_$i.txt" | awk '$1 == "pages-per-second:" {print $2}')
        if [[ -z "$pages_per_second" ]]; then
            echo -e "${BRED}pages_per_second${NC}"
            failed="True"
        fi

		if [[ "$failed" == "True" ]]; then
			echo -e "${BRED}migration failed${NC}"
			(( i -= 1 ))
			(( fail += 1 ))
        else
			echo -e "${BGREEN}totaltime = $totaltime${NC}"
			echo -e "${BGREEN}downtime = $downtime${NC}"
			echo -e "${BGREEN}setup = $setup${NC}"
			echo -e "${BGREEN}transferred_ram = $transferred_ram${NC}"
			echo -e "${BGREEN}throughput = $throughput${NC}"
			echo -e "${BGREEN}multifd_bytes = $multifd_bytes${NC}"
			echo -e "${BGREEN}pages_per_second = $pages_per_second${NC}"
			(( sum_totaltime += totaltime ))
			(( sum_downtime += downtime ))
			(( sum_setup += setup ))
			(( sum_transferred_ram += transferred_ram ))
			(( sum_multifd_bytes += multifd_bytes ))
			(( sum_pages_per_second += pages_per_second ))
			sum_throughput=$(echo "$throughput + $sum_throughput"|bc)
		fi

		echo -e "${BCYAN}cleaning up VMs${NC}"
		ncat --send-only $src_ip $src_monitor_port <<< "$command_shutdown"
		ncat --send-only $dst_ip $dst_monitor_port <<< "$command_shutdown"
		echo -e "${BCYAN}wait for VMs to shutdown${NC}"
		sleep 10s
	done

	(( sum_totaltime /= rounds ))
	(( sum_downtime /= rounds ))
	(( sum_setup /= rounds ))
    (( sum_transferred_ram /= rounds ))
    (( sum_multifd_bytes /= rounds ))
    (( sum_pages_per_second /= rounds ))
	sum_throughput=$(echo "scale=4; $sum_throughput / $rounds"|bc)
	echo "$sum_downtime $sum_totaltime $sum_setup $sum_throughput $sum_transferred_ram $sum_multifd_bytes $sum_pages_per_second $fail" >> $result_path
	echo -e "${BCYAN}t=$t, done${NC}"
done
