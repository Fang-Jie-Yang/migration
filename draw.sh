#! /bin/bash

DIR=$1
for (( i = 0; i < 10; i++ )); do
    python3 pretty-plot.py $DIR/ab$i $DIR/$i.png
done
