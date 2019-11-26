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

echo "from | lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid              | t_infomask2 | t_infomask | t_hoff"
echo "-----+----+--------+----------+--------+--------+--------+----------+---------------------+-------------+------------+--------"

if [ "$inspect" = "disk" -o "$inspect" = "both" ] ; then
filenumber=`expr $blk / 131072`
blktoread=0
if (( $filenumber >= 1 ))
then
relpath=$relpath.$filenumber
blktoread=`expr 131072 \\* $filenumber`
fi
blkmem=$blk
blk=`expr $blk - $blktoread`
#echo "Reading block $blk in file $relpath....."

dsk_lower=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 12 -N 2`
nbtuples=`expr $dsk_lower - 24`
nbtuples=`expr $nbtuples / 4`
lp=1
while [ $lp -le $nbtuples ]
do
  skipbytes=$(( 4 * $lp - 4 ))
  skipbytes=$(( 24 + $skipbytes ))
  dsk_lp_off=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $skipbytes -N 2 | sed 's/^ *//'`
  dsk_lp_off=`echo $((0x$dsk_lp_off & ~$((1<<15))))`
  dsk_lp_flags=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x4 -j $skipbytes -N 4 | sed 's/^ *//'`
  dsk_lp_flags=`echo $dsk_lp_flags | tr '[:lower:]' '[:upper:]'`
  skipbytes=$(( 2 + $skipbytes ))
  dsk_lp_len=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $skipbytes -N 2 | sed 's/^ *//'`
  dsk_lp_len=`echo $((0x$dsk_lp_len >> 1))`
  dsk_lp_flags="$((2#`echo "ibase=16;obase=2;${dsk_lp_flags}" | bc | rev | cut -c16,17 | rev`))"
  dsk_xmin=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d4 -j $dsk_lp_off -N 4`
  toread=$(( 4 + $dsk_lp_off ))
  dsk_xmax=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d4 -j $toread -N 4`
  toread=$(( 8 + $dsk_lp_off ))
  dsk_t_field3=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $toread -N 4`
  toread=$(( 12 + $dsk_lp_off ))
  dsk_ctid_block_number=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $toread -N 4 | sed 's/ //g'`
  dsk_ctid_block_number=`echo $dsk_ctid_block_number | tr '[:lower:]' '[:upper:]'`
  dsk_ctid_block_number=`echo "ibase=16;$dsk_ctid_block_number"|bc`
  toread=$(( 16 + $dsk_lp_off ))
  dsk_ctid_tuple_id=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
  toread=$(( 18 + $dsk_lp_off ))
  dsk_t_infomask2=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
  toread=$(( 20 + $dsk_lp_off ))
  dsk_t_infomask=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
  toread=$(( 22 + $dsk_lp_off ))
  dsk_t_hoff=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u1 -j $toread -N 1`


  printf "%-4s %1s %-2s %1s %-6s %1s %-8s %1s %-6s %1s %-6s %1s %-6s %1s %-8s %1s %1s %-8s %1s %-4s %1s %1s %-11s %1s %-10s %1s %-6s \n" 'disk' '|' $lp '|' $dsk_lp_off '|' $dsk_lp_flags '|' $dsk_lp_len '|' $dsk_xmin '|' $dsk_xmax '|' $dsk_t_field3 '|' '(' $dsk_ctid_block_number ',' $dsk_ctid_tuple_id ')' '|' $dsk_t_infomask2 '|' $dsk_t_infomask '|' $dsk_t_hoff 
  lp=$(( $lp + 1 ))
done
fi

if [ "$inspect" = "mem" -o "$inspect" = "both" ] ; then
from_mem=`psql -tA -c "SELECT * FROM heap_page_items(get_raw_page('$tb', $blkmem))"`

for lp in `echo "$from_mem"`
do
#echo $lp
mem_lp=`echo $lp | cut -f1 -d "|"`
mem_lp_off=`echo $lp | cut -f2 -d "|"`
mem_lp_flags=`echo $lp | cut -f3 -d "|"`
mem_lp_len=`echo $lp | cut -f4 -d "|"`
mem_t_xmin=`echo $lp | cut -f5 -d "|"`
mem_t_max=`echo $lp | cut -f6 -d "|"`
mem_t_field3=`echo $lp | cut -f7 -d "|"`
mem_t_ctid=`echo $lp | cut -f8 -d "|"`
mem_t_infomask2=`echo $lp | cut -f9 -d "|"`
mem_t_infomask=`echo $lp | cut -f10 -d "|"`
mem_t_hoff=`echo $lp | cut -f11 -d "|"`
mem_t_bits=`echo $lp | cut -f12 -d "|"`
mem_t_oid=`echo $lp | cut -f13 -d "|"`
printf "%-4s %1s %-2s %1s %-6s %1s %-8s %1s %-6s %1s %-6s %1s %-6s %1s %-8s %1s %-19s %1s %-11s %1s %-10s %1s %-6s \n" 'mem' '|' $mem_lp '|' $mem_lp_off '|' $mem_lp_flags '|' $mem_lp_len '|' $mem_t_xmin '|' $mem_t_max '|' $mem_t_field3 '|' $mem_t_ctid '|' $mem_t_infomask2 '|' $mem_t_infomask '|' $mem_t_hoff 
done
fi
