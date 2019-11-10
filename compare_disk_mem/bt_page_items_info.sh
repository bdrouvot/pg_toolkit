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

echo "from | ofs | t_ctid              | len | nu | va | data                                                                   " 
echo "-----+-----+---------------------+-----+----+----+------------------------------------------------------------------------"

if [ "$inspect" = "disk" -o "$inspect" = "both" ] ; then
dsk_lower=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t d -j 12 -N 2`
nbentries=`expr $dsk_lower - 24`
nbentries=`expr $nbentries / 4`
ent=1
while [ $ent -le $nbentries ]
do
  skipbytes=$(( 4 * $ent - 4 ))
  skipbytes=$(( 24 + $skipbytes ))
  dsk_item_off=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $skipbytes -N 2 | sed 's/^ *//'`
  dsk_item_off=`echo $((0x$dsk_item_off & ~$((1<<15))))`
  skipbytes=$(( 2 + $skipbytes ))
  dsk_item_len=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $skipbytes -N 2 | sed 's/^ *//'`
  dsk_item_len=`echo $((0x$dsk_item_len >> 1))`
  toread=$(( 0 + $dsk_item_off ))
  dsk_ctid_block_number=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x4 -j $toread -N 4`
  toread=$(( 4 + $dsk_item_off ))
  dsk_ctid_tuple_id=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
  toread=$(( 6 + $dsk_item_off ))
  dsk_t_info=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u2 -j $toread -N 2`
  dsk_t_info_b=`echo "obase=2;$dsk_t_info" | bc | rev`
# typedef struct IndexTupleData
#  {
#   ItemPointerData t_tid;      /* reference TID to heap tuple */
#   /* ---------------
#    * t_info is laid out in the following fashion:
#    *
#    * 15th (high) bit: has nulls
#    * 14th bit: has var-width attributes
#    * 13th bit: unused
#    * 12-0 bit: size of tuple
#    * ---------------
#    */
#    unsigned short t_info;      /* various info about tuple */
#  } IndexTupleData; 
  has_var=`echo $dsk_t_info_b | cut -c15` #0 to 15 so need to ad one here
  if [ ! -z "$has_var" ] && (( $has_var == 1 ))
  then
  item_has_var="t"
  else
  item_has_var="f"
  fi

  has_null=`echo $dsk_t_info_b | cut -c16` #0 to 15 so need to ad one here
  if [ ! -z "$has_null" ] && (( $has_null == 1 ))
  then
  item_has_null="t"
  else
  item_has_null="f"
  fi
  
  toread=$(( 8 + $dsk_item_off ))
  n_toread=$(( $dsk_item_len - 8 ))
  dsk_t_data=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x1 -j $toread -N $n_toread`
  printf "%-4s %1s %-3s %1s %1s %-8s %1s %-4s %1s %1s %-3s %1s %-2s %1s %-2s %1s %-60s \n" 'disk' '|' $ent '|' '(' $dsk_ctid_block_number ',' $dsk_ctid_tuple_id ')' '|' $dsk_item_len '|' $item_has_null '|' $item_has_var '|' "$dsk_t_data"
  ent=$(( $ent + 1 ))
done
fi

if [ "$inspect" = "mem" -o "$inspect" = "both" ] ; then
from_mem=`psql -tA -c "SELECT * FROM bt_page_items('$bt', $blk)"`

IFS=$'\n'
for item in `echo "$from_mem"`
do
mem_offset=`echo $item | cut -f1 -d "|"`
mem_ctid=`echo $item | cut -f2 -d "|"`
mem_length=`echo $item | cut -f3 -d "|"`
mem_has_null=`echo $item | cut -f4 -d "|"`
mem_has_var=`echo $item | cut -f5 -d "|"`
mem_item_data=`echo $item | cut -f6 -d "|"`
printf "%-4s %1s %-3s %1s %-19s %1s %-3s %1s %-2s %1s %-2s %1s %-60s \n" 'mem' '|' $mem_offset '|' $mem_ctid '|' $mem_length '|' $mem_has_null '|' $mem_has_var '| ' $mem_item_data
done
fi
