#!/bin/bash

# Same as SELECT * FROM bt_page_items('pg_toast.pg_toast_174243_index', 1);
# but display the data as chunk_id and chunk_seq
# ./toast_index_info.sh -b 1 -p /usr/local/pgsql12.0/data/base/174236/174248
# 
#from | ofs | t_ctid              | len | nu | va | chunk_id          | chunk_seq
#-----+-----+---------------------+-----+----+----+-------------------|-------------------
#disk | 1   | ( 0        , 1    ) | 16  | f  | f  | 174249            | 0
#disk | 2   | ( 0        , 2    ) | 16  | f  | f  | 174249            | 1
#disk | 3   | ( 0        , 3    ) | 16  | f  | f  | 174249            | 2
#disk | 4   | ( 0        , 4    ) | 16  | f  | f  | 174249            | 3
#disk | 5   | ( 1        , 1    ) | 16  | f  | f  | 174249            | 4
#disk | 6   | ( 1        , 2    ) | 16  | f  | f  | 174249            | 5
#disk | 7   | ( 1        , 3    ) | 16  | f  | f  | 174250            | 0
#disk | 8   | ( 1        , 4    ) | 16  | f  | f  | 174250            | 1

# means 174250 , seq 0 is located at block 1 and lp 4 in the toast relation

# to get the path of the index:

#select
#pg_relation_filepath(c.reltoastrelid) as toast_table_path,
#pg_relation_filepath(i.indexrelid) as toast_index_path
#from pg_class c
#left outer join pg_index i on c.reltoastrelid=i.indrelid
#where c.relname = 'messages';

if [ "$1" = "--help" -o $# -eq 0 ] ; then
  echo ""
  echo "Usage: "
  echo ""
  echo "-b: block to inspect"
  echo "-p: relation path on disk"
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
echo ""

echo "from | ofs | t_ctid              | len | nu | va | chunk_id          | chunk_seq         " 
echo "-----+-----+---------------------+-----+----+----+-------------------|-------------------"

filenumber=`expr $blk / 131072`
blktoread=0
if (( $filenumber >= 1 ))
then
relpath=$relpath.$filenumber
blktoread=`expr 131072 \\* $filenumber`
fi
blkmem=$blk
blk=`expr $blk - $blktoread`

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
  dsk_ctid_block_number=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x2 -j $toread -N 4 | sed 's/ //g'`
  dsk_ctid_block_number=`echo $dsk_ctid_block_number | tr '[:lower:]' '[:upper:]'`
  dsk_ctid_block_number=`echo "ibase=16;$dsk_ctid_block_number"|bc`
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
  toread_seq=$(( 4 + $toread ))
  n_toread=$(( $dsk_item_len - 8 ))
  #dsk_t_data=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t x4 -j $toread -N $n_toread`
  dsk_t_chunkid=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $toread -N 4`
  dsk_t_chunkseq=`dd status=none bs=8192 count=1 if=$relpath skip=$blk | od -A n -t u4 -j $toread_seq -N 4`
  printf "%-4s %1s %-3s %1s %1s %-8s %1s %-4s %1s %1s %-3s %1s %-2s %1s %-2s %1s %-17s %1s %-17s\n" 'disk' '|' $ent '|' '(' $dsk_ctid_block_number ',' $dsk_ctid_tuple_id ')' '|' $dsk_item_len '|' $item_has_null '|' $item_has_var '|' $dsk_t_chunkid '|' $dsk_t_chunkseq
  ent=$(( $ent + 1 ))
done
