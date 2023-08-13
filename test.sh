#! /bin/bash 

bb=""
bb=$( {ssh -q $(whoami)@10.10.1.1 << EOF
	flsajd
    sudo /srv/vm/net.sh
EOF
2>&1 | head -n -1)
echo $bb
