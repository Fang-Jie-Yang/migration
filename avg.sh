#! /bin/bash

sum=0
rounds=10

for ((i = 0; i < $rounds; i++)); do
	temp=$(cat "$i.txt" | awk '$1 == "compression" && $2 == "rate:" {print $3}')
    sum=$(echo "$temp + $sum"|bc)
done

sum=$(echo "scale=4; $sum / $rounds"|bc)
echo "avg: $sum"
