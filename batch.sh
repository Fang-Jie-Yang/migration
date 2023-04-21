#! /bin/bash

./eval.sh precopy 1000 1024 1 off off >> test_out
./eval.sh multifd2 1000 1024 2 on off >> test_out
./eval.sh multifd4 1000 1024 4 on off >> test_out
./eval.sh multifd8 1000 1024 8 on off >> test_out
./eval.sh postcopy 1000 1024 1 off on >> test_out
