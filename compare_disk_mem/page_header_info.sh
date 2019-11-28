#!/bin/bash

if [ "$1" = "--help" -o $# -eq 0 ] ; then
  echo ""
  echo "Usage: "
  echo ""
  echo "-b: block to inspect"
  echo "-p: relation path on disk"
  echo "-t: table name"
  echo "-i: where to inspect (disk, memory, both)"
  echo ""
  exit 0
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -b|--block)
    blk="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--path)
    relpath="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--table)
    tb="$2"
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
echo "BLOCK   = ${blk}"
echo "PATH    = ${relpath}"
echo "TABLE   = ${tb}"
echo "INSPECT = ${inspect}"
echo ""

echo " from    |    lsn            | checksum    | flags        | lower        | upper        | special      | prune_xid     "
echo "---------+-------------------+-------------+--------------+--------------+--------------+--------------+-----------"
if [ "$inspect" = "disk" -o "$inspect" = "both" ] ; then

filenumber=`expr $blk / 131072`
blktoread=0
if (( $filenumber >= 1 ))
then
relpath=${relpath}.${filenumber}
blktoread=`expr 131072 \\* $filenumber`
fi
blkmem=$blk
blk=`expr $blk - $blktoread`

dsk_lsn1=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x4 -N 4`
dsk_lsn1=`echo $dsk_lsn1 | tr '[:lower:]' '[:upper:]'`
dsk_lsn2=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x4 -j 4 -N 4`
dsk_lsn2=`echo $dsk_lsn2 | tr '[:lower:]' '[:upper:]'`
dsk_checksum=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 8 -N 2`
dsk_flags=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 10 -N 2`
dsk_lower=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 12 -N 2`
dsk_upper=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 14 -N 2`
dsk_special=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 16 -N 2`
dsk_pagesize=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 18 -N 2`
dsk_prune=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 20 -N 4`

printf "%-8s %1s %-16s %1s %-11s %1s %-12s %1s %-12s %1s %-12s %1s %-12s %1s %-10s \n" 'disk' '|' $dsk_lsn1/$dsk_lsn2 '|' $dsk_checksum '|' $dsk_flags '|' $dsk_lower '|' $dsk_upper '|' $dsk_special '|' $dsk_prune
fi

if [ "$inspect" = "mem" -o "$inspect" = "both" ] ; then
from_mem=`psql -tA -c "SELECT * FROM page_header(get_raw_page('$tb', $blkmem))"`

mem_lsn=`echo $from_mem | cut -f1 -d "|"`
mem_checksum=`echo $from_mem | cut -f2 -d "|"`
mem_flags=`echo $from_mem | cut -f3 -d "|"`
mem_lower=`echo $from_mem | cut -f4 -d "|"`
mem_upper=`echo $from_mem | cut -f5 -d "|"`
mem_special=`echo $from_mem | cut -f6 -d "|"`
mem_prune=`echo $from_mem | cut -f9 -d "|"`
printf "%-8s %1s %-17s %1s %-11s %1s %-12s %1s %-12s %1s %-12s %1s %-12s %1s %-10s \n" 'mem' '|' $mem_lsn '|' $mem_checksum '|' $mem_flags '|' $mem_lower '|' $mem_upper '|' $mem_special '|' $mem_prune
fi
