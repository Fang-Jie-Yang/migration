#! /bin/bash

./eval.sh precopy 1000 1024 1 0 off off off >> test_out
./eval.sh compress 1000 1024 1 0 off off on >> test_out
./eval.sh multifd2 1000 1024 2 0 on off off >> test_out
./eval.sh multifd4 1000 1024 4 0 on off off >> test_out
./eval.sh multifd8 1000 1024 8 0 on off off >> test_out
./eval.sh postcopy 1000 1024 1 10737418240 off on off >> test_out
