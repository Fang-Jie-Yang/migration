#! /bin/bash

out="result.txt"

src="1cpu-256M-idle.sh"
dst="1cpu-256M-idle-resume.sh"
ab="off"
dt="1000"
bm="10240"
pbm="10737418240"
#./eval.sh $src $dst $ab 1-1-1 $dt $bm 1 $pbm off off off >> $out
#./eval.sh $src $dst $ab 1-1-2 $dt $bm 1 $pbm off off on  >> $out
#./eval.sh $src $dst $ab 1-1-3 $dt $bm 2 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-1-4 $dt $bm 4 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-1-5 $dt $bm 8 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-1-6 $dt $bm 1 $pbm off on  off >> $out


src="1cpu-256M-ab.sh"
dst="1cpu-256M-ab-resume.sh"
ab="on"
dt="3000"
bm="10240"
pbm="10737418240"
#./eval.sh $src $dst $ab 1-2-1 $dt $bm 1 $pbm off off off >> $out
#./eval.sh $src $dst $ab 1-2-2 $dt $bm 1 $pbm off off on  >> $out
#./eval.sh $src $dst $ab 1-2-3 $dt $bm 2 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-2-4 $dt $bm 4 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-2-5 $dt $bm 8 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-2-6 $dt $bm 1 $pbm off on  off >> $out

src="4cpu-256M-idle.sh"
dst="4cpu-256M-idle-resume.sh"
ab="off"
dt="1000"
bm="10240"
pbm="10737418240"
#./eval.sh $src $dst $ab 1-3-1 $dt $bm 1 $pbm off off off >> $out
#./eval.sh $src $dst $ab 1-3-2 $dt $bm 1 $pbm off off on  >> $out
#./eval.sh $src $dst $ab 1-3-3 $dt $bm 2 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-3-4 $dt $bm 4 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-3-5 $dt $bm 8 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-3-6 $dt $bm 1 $pbm off on  off >> $out
#

src="4cpu-256M-ab.sh"
dst="4cpu-256M-ab-resume.sh"
ab="on"
dt="3000"
bm="10240"
pbm="10737418240"
#./eval.sh $src $dst $ab 1-4-1 $dt $bm 1 $pbm off off off >> $out
#./eval.sh $src $dst $ab 1-4-2 $dt $bm 1 $pbm off off on  >> $out
#./eval.sh $src $dst $ab 1-4-3 $dt $bm 2 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-4-4 $dt $bm 4 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-4-5 $dt $bm 8 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-4-6 $dt $bm 1 $pbm off on  off >> $out


src="4cpu-1024M-idle.sh"
dst="4cpu-1024M-idle-resume.sh"
ab="off"
dt="3000"
bm="10240"
pbm="10737418240"
#./eval.sh $src $dst $ab 1-5-1 $dt $bm 1 $pbm off off off >> $out
#./eval.sh $src $dst $ab 1-5-2 $dt $bm 1 $pbm off off on  >> $out
#./eval.sh $src $dst $ab 1-5-3 $dt $bm 2 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-5-4 $dt $bm 4 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-5-5 $dt $bm 8 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-5-6 $dt $bm 1 $pbm off on  off >> $out


src="4cpu-1024M-ab.sh"
dst="4cpu-1024M-ab-resume.sh"
ab="on"
dt="5000"
bm="10240"
pbm="10737418240"
#./eval.sh $src $dst $ab 1-6-1 $dt $bm 1 $pbm off off off >> $out
#./eval.sh $src $dst $ab 1-6-2 $dt $bm 1 $pbm off off on  >> $out
#./eval.sh $src $dst $ab 1-6-3 $dt $bm 2 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-6-4 $dt $bm 4 $pbm on  off off >> $out
#./eval.sh $src $dst $ab 1-6-5 $dt $bm 8 $pbm on  off off >> $out
./eval.sh $src $dst $ab 1-6-6 $dt $bm 1 $pbm off on  off >> $out
