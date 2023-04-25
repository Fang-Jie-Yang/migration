#!/bin/bash

CMDLINE="earlycon=pl011,0x09000000"
NET="-net none"
MEM="256"
BLK=""
DEBUG=""
TRACE=""
KERNEL="/mydata/some-tutorials/files/Image.sekvm"
RESUME="tcp"
PORT="8888"
CONSOLE="1235"
FILE="/tmp/snap"
FS="/proj/ntucsie-PG0/fjyang/cloud-hack-ab.img"
QEMU="/mydata/qemu"

while :
do
    case "$1" in
        --nat)
            NET="-netdev user,id=net0"
            NET="$NET -device virtio-net-pci,netdev=net0"
            shift 1
            ;;
        --bridge)
            ifconfig | grep -q br0
            err=$?

            if [[ $err == 0 ]]; then
                echo "Using bridged networking"
                NET="-netdev tap,id=net1,helper=$QEMU/qemu-bridge-helper,vhost=on"
                NET="$NET -device virtio-net-pci,netdev=net1,mac=de:ad:be:ef:f6:5f"
            else
                echo "br0 not found"
                exit 1
            fi
            shift 1
            ;;
        -k | --kernel)
            KERNEL="$2"
            shift 2
            ;;
        -q | --qemu)
            QEMU="$2"
            shift 2
            ;;
        -d | --debug )
            DEBUG="gdb --tui --args"
            shift 1
            ;;
        -t | --trace )
            TRACE="-trace events=$2,file=dst.bin"
            shift 2
            ;;
        -c | --console )
            CONSOLE="$2"
            shift 2
            ;;
        -p | --port )
            PORT="$2"
            shift 2
            ;;
        -f | --file )
            FILE="$2"
            shift 2
            ;;
        -i | --image )
            IMAGE="$2"
            shift 2
            ;;
        -m | --mem )
            MEM="$2"
            shift 2
            ;;
        -r | --resume )
            if [ "$2" = "dead" ]
            then
                RESUME="exec"
            elif [ "$2" = "live" ]
            then
                RESUME="tcp"
            else
                echo "WTF"
                exit 1
            fi
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -* | --* )
            echo "WTF"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $RESUME == *"tcp"* ]]
then
    RESUME="tcp:0:$PORT"
elif [[ $RESUME == *"exec"* ]]
then
    RESUME="exec:gzip -c -d $FILE"
fi

$DEBUG \
$QEMU/aarch64-softmmu/qemu-system-aarch64 \
    -enable-kvm -M virt -cpu host -m $MEM \
    -kernel $KERNEL \
    $NET \
    -drive if=none,file=$FS,id=vda,cache=none,format=raw \
    -device virtio-blk-pci,drive=vda \
    -append "console=ttyAMA0 root=/dev/vda rw $CMDLINE" \
    -monitor telnet:10.10.1.2:$CONSOLE,server,nowait \
    -display none\
    -daemonize \
    -incoming "$RESUME" \
    $TRACE \
