#!/bin/bash

if [ "$1" = "--help" ] ; then
  echo ""
  echo "Usage: "
  echo ""
  echo "-b: block to inspect"
  echo "-p: relation path on disk"
  echo "-bt: btree name"
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
echo "BLOCK   = ${blk}"
echo "PATH    = ${relpath}"
echo "BTREE   = ${bt}"
echo "INSPECT = ${inspect}"
echo ""

BTP_LEAF=0x1
BTP_ROOT=0x2
BTP_DELETED=0x4
BTP_META=0x8
BTP_HALF_DEAD=0x10
BTP_SPLIT_END=0x20
BTP_HAS_GARBAGE=0x40
BTP_INCOMPLETE_SPLIT=0x80 

search_type () {

btpo_flags_param=0x$1

P_ISDELETED=`echo $(( $btpo_flags_param & $BTP_DELETED ))`
P_IGNORE=`echo $(( $btpo_flags_param & ($BTP_DELETED|$BTP_HALF_DEAD) ))`
P_ISLEAF=`echo $(( $btpo_flags_param & $BTP_LEAF ))`
P_ISROOT=`echo $(( $btpo_flags_param & $BTP_ROOT ))`

if (( $P_ISDELETED != 0 ))
then
   page_type="d"
elif (( $P_IGNORE != 0 ))
then
   page_type="e"
elif (( $P_ISLEAF != 0 ))
then
   page_type="l"
elif (( $P_ISROOT != 0 ))
then
   page_type="r"
else
   page_type="i"
fi

echo "$page_type"
}

echo "from | blkno | type | live_items | dead_items | avg_item_size | free_size  | btpo_prev | btpo_next | btpo | btpo_flags"
echo "-----+-------+------+------------+------------+---------------+------------+-----------+-----------+------+-----------"

if [ "$inspect" = "disk" -o "$inspect" = "both" ] ; then
dsk_lower=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 12 -N 2`
dsk_upper=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 14 -N 2`
# where is opaque?
dsk_special=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 16 -N 2`
# go read opaque
toread=$(( 0 + $dsk_special ))
dsk_btpo_prev=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $toread -N 4`
toread=$(( 4 + $dsk_special ))
dsk_btpo_next=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $toread -N 4`
toread=$(( 8 + $dsk_special ))
dsk_btpo=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $toread -N 4`
toread=$(( 12 + $dsk_special ))
dsk_btpo_flags=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
dsk_btpo_flags_hexa=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $toread -N 2`
toread=$(( 14 + $dsk_special ))
dsk_BTCycleId=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
dsk_p_type=$(search_type $dsk_btpo_flags_hexa)
dsk_free_size=$(( $dsk_upper - $dsk_lower ))
dsk_free_size=$(( $dsk_free_size - 4 ))

if [ "$dsk_p_type" = "d" ] ; then
dsk_live_items=0
dsk_dead_items=0
dsk_dead_items=0
dsk_free_size=0
dsk_btpo_prev=-1
dsk_btpo_next=-1
dsk_btpo_flags=0

else

# how many entries?
nbentries=`expr $dsk_lower - 24`
nbentries=`expr $nbentries / 4`
ent=1
dsk_items_size=0
dsk_live_items=0
dsk_dead_items=0
LP_DEAD=3
while [ $ent -le $nbentries ]
do
  skipbytes=$(( 4 * $ent - 4 ))
  skipbytes=$(( 24 + $skipbytes ))
  dsk_item_off=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $skipbytes -N 2 | sed 's/^ *//'`
  dsk_item_off=`echo $((0x$dsk_item_off & ~$((1<<15))))`
  dsk_lp_flags=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x4 -j $skipbytes -N 4 | sed 's/^ *//'`
  dsk_lp_flags=`echo $dsk_lp_flags | tr '[:lower:]' '[:upper:]'`
  # bits 16 and 17
  dsk_lp_flags="$((2#`echo "ibase=16;obase=2;${dsk_lp_flags}" | bc | rev | cut -c16,17 | rev`))"
  if (( $dsk_lp_flags != $LP_DEAD )) 
  then
  dsk_live_items=$(( $dsk_live_items + 1 ))
  else
  dsk_dead_items=$(( $dsk_dead_items + 1 ))
  fi
  skipbytes=$(( 2 + $skipbytes ))
  dsk_item_len=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $skipbytes -N 2 | sed 's/^ *//'`
  dsk_item_len=`echo $((0x$dsk_item_len >> 1))`
  dsk_items_size=$(( $dsk_items_size + $dsk_item_len ))
  ent=$(( $ent + 1 ))
done
fi

dsk_total_items=$(( $dsk_live_items + $dsk_dead_items ))
if (( $dsk_total_items != 0 )) 
then
dsk_avg_item_size=$(( $dsk_items_size / $dsk_total_items ))
else
dsk_avg_item_size=0
fi
fi

printf "%-4s %1s %-5s %1s %-4s %1s %-10s %1s %-10s %1s %-13s %1s %-9s %1s %-9s %1s %-9s %1s %-4s %1s %-10s \n" 'dsk' '|' $blk '|' $dsk_p_type '|' $dsk_live_items '|' $dsk_dead_items '|' $dsk_avg_item_size '| ' "$dsk_free_size" '|' $dsk_btpo_prev '|' $dsk_btpo_next '|' $dsk_btpo '|' $dsk_btpo_flags


if [ "$inspect" = "mem" -o "$inspect" = "both" ] ; then
from_mem=`psql -tA -c "SELECT * FROM bt_page_stats('$bt', $blk)"`

for item in `echo "$from_mem"`
do
mem_blk=`echo $item | cut -f1 -d "|"`
mem_p_type=`echo $item | cut -f2 -d "|"`
mem_live_items=`echo $item | cut -f3 -d "|"`
mem_dead_items=`echo $item | cut -f4 -d "|"`
mem_avg_item_size=`echo $item | cut -f5 -d "|"`
mem_free_size=`echo $item | cut -f7 -d "|"`
mem_btpo_prev=`echo $item | cut -f8 -d "|"`
mem_btpo_next=`echo $item | cut -f9 -d "|"`
mem_btpo=`echo $item | cut -f10 -d "|"`
mem_btpo_flags=`echo $item | cut -f11 -d "|"`

printf "%-4s %1s %-5s %1s %-4s %1s %-10s %1s %-10s %1s %-13s %1s %-9s %1s %-9s %1s %-9s %1s %-4s %1s %-10s \n" 'mem' '|' $mem_blk '|' $mem_p_type '|' $mem_live_items '|' $mem_dead_items '|' $mem_avg_item_size '| ' "$mem_free_size" '|' $mem_btpo_prev '|' $mem_btpo_next '|' $mem_btpo '|' $mem_btpo_flags
done
fi
