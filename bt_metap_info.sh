#!/bin/bash

if [ "$1" = "--help" ] ; then
  echo ""
  echo "Usage: "
  echo ""
  echo "-p : relation path on disk"
  echo "-bt: btree name"
  echo "-i : where to inspect (disk, memory, both)"
  echo ""
  exit 0
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -p|--path)
    relpath="$2"
    shift # past argument
    shift # past value
    ;;
    -bt|--btree)
    bt="$2"
    shift # past argument
    shift # past value
    ;;
    -i|--inspect)
    inspect="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" 

echo ""
echo "PATH       = ${relpath}"
echo "BTREE      = ${bt}"
echo "INSPECT    = ${inspect}"
echo ""

echo "from | magic    | version | root | level | fastroot | fastlevel | oldest_xact | last_cleanup_num_tuples"
echo "-----+----------+---------+------+-------+----------+-----------+-------------+------------------------"

if [ "$inspect" = "disk" -o "$inspect" = "both" ] ; then
blk=0
skipbytes=$(( 24 + 0 ))
dsk_magic=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 4 ))
dsk_version=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 8 ))
dsk_root=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 12 ))
dsk_level=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 16 ))
dsk_fastroot=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 20 ))
dsk_fastlevel=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 24 ))
dsk_oldest_xact=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $skipbytes -N 4`
skipbytes=$(( 24 + 28 ))
dsk_last_cleanup_num_tuples=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t f4 -j $skipbytes -N 4`

BTREE_NOVAC_VERSION=3

if [ "$dsk_version" -ge "$BTREE_NOVAC_VERSION" ]
then
dsk_oldest_xact=0
dsk_last_cleanup_num_tuples=-1
fi

printf "%-4s %1s %-8s %1s %-7s %1s %-4s %1s %-5s %1s %-8s %1s %-9s %1s %-11s %1s %-2s \n" 'disk' '|' $dsk_magic '|' $dsk_version '|' $dsk_root '|' $dsk_level '|' $dsk_fastroot '|' $dsk_fastlevel '|' $dsk_oldest_xact '|' $dsk_last_cleanup_num_tuples 
  lp=$(( $lp + 1 ))
fi

if [ "$inspect" = "mem" -o "$inspect" = "both" ] ; then
from_mem=`psql -tA -c "SELECT * FROM bt_metap('$bt')"`

mem_magic=`echo $from_mem | cut -f1 -d "|"`
mem_version=`echo $from_mem | cut -f2 -d "|"`
mem_root=`echo $from_mem | cut -f3 -d "|"`
mem_level=`echo $from_mem | cut -f4 -d "|"`
mem_fastroot=`echo $from_mem | cut -f5 -d "|"`
mem_fastlevel=`echo $from_mem | cut -f6 -d "|"`
mem_oldest_xact=`echo $from_mem | cut -f7 -d "|"`
mem_last_cleanup_num_tuples=`echo $from_mem | cut -f8 -d "|"`
printf "%-4s %1s %-8s %1s %-7s %1s %-4s %1s %-5s %1s %-8s %1s %-9s %1s %-11s %1s %-2s \n" 'mem' '|' $mem_magic '|' $mem_version '|' $mem_root '|' $mem_level '|' $mem_fastroot '|' $mem_fastlevel '|' $mem_oldest_xact '|' $mem_last_cleanup_num_tuples 
fi
