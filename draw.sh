#!/bin/bash

rounds=9
dt_sum=0
idx=6
output_dir="graph/$idx"
#output_dir="."
input_dir="stress/$idx"
mkdir $output_dir
for (( i = 0; i < $rounds; i++ )); do
	dt=$(echo "$output_dir/ab_$i.png" | python3 ~/some-tutorials/files/migration/plot.py $input_dir/ab_$i.txt | awk '{print $2}')
	echo "$dt" >&2
	dt_sum=$(echo $dt + $dt_sum|bc)
done
echo -n $(echo "scale=4; $dt_sum / $rounds"|bc)
