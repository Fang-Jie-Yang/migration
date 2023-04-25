#!/bin/bash

CMDLINE="earlycon=pl011,0x09000000"
NET="-net none"
MEM="1024"
BLK=""
DEBUG=""
TRACE=""
KERNEL="/mydata/some-tutorials/files/Image.sekvm"
CONSOLE="1234"
FILE="/tmp/snap"
FS="/proj/ntucsie-PG0/fjyang/cloud-hack.img"
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
            TRACE="-trace events=$2,file=src.bin"
            shift 2
            ;;
        -c | --console )
            CONSOLE="$2"
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

$DEBUG \
$QEMU/aarch64-softmmu/qemu-system-aarch64 \
    -enable-kvm -M virt -cpu host -m $MEM \
    -smp 4 \
    -kernel $KERNEL \
    $NET \
    -drive if=none,file=$FS,id=vda,cache=none,format=raw \
    -device virtio-blk-pci,drive=vda \
    -append "console=ttyAMA0 root=/dev/vda rw $CMDLINE" \
    -monitor telnet:10.10.1.1:$CONSOLE,server,nowait \
    -display none\
    -daemonize \
    $TRACE \
