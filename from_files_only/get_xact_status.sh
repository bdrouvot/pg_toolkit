#!/bin/bash

if [ "$1" = "--help" ] || [ $# -ne 4 ] ; then
  echo ""
  echo "Usage: "
  echo ""
  echo "-x: xid"
  echo "-d: DATA path"
  echo ""
  echo "example: $0 -x 31795287 -d /usr/local/pgsql11.6/data/"
  exit 0
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -x|--xid)
    xid="$2"
    shift # past argument
    shift # past value
    ;;
    -d|--data)
    pgdata="$2"
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
echo "XID   = ${xid}"
echo "DATA  = ${pgdata}"
echo ""

#See clog.c:
#CLOG_BITS_PER_XACT      2
#CLOG_XACTS_PER_BYTE 4
#CLOG_XACTS_PER_PAGE 32768
#CLOG_XACT_BITMASK 3
#CLOG_LSNS_PER_PAGE 1024
#sizeof(TransactionId) is 4

PGCLOG="${pgdata}/pg_xact/"


#define TransactionIdToPage(xid)    ((xid) / (TransactionId) CLOG_XACTS_PER_PAGE)
pagenumber=`expr ${xid} / 32768`
pageinfile=`expr ${pagenumber} % 32`

hexfic=`expr ${pagenumber} / 32`
hexfic=`echo "ibase=10;obase=16;${hexfic}" | bc`
hexfic=`printf "%04x" "0x${hexfic}" | tr '[:lower:]' '[:upper:]'`

#define TransactionIdToPgIndex(xid) ((xid) % (TransactionId) CLOG_XACTS_PER_PAGE)
offsetid=`expr ${xid} % 32768`

#define TransactionIdToByte(xid)    (TransactionIdToPgIndex(xid) / CLOG_XACTS_PER_BYTE)
xidtobyte=`expr ${offsetid} / 4`

#define TransactionIdToBIndex(xid)  ((xid) % (TransactionId) CLOG_XACTS_PER_BYTE)
xidtobindex=`expr ${xid} % 4`

BYREAD=`dd status=none bs=8192 count=1 if=${PGCLOG}${hexfic} skip=$pageinfile | od -A n -t x1 -j $xidtobyte -N 1| sed 's/^ *//'`
BYREAD=`echo $BYREAD | tr '[:lower:]' '[:upper:]'`
ALLBITS=`echo "ibase=16;obase=2;${BYREAD}" | bc`
NBBITS=`echo -n "$ALLBITS" | wc -c`

# get the right 2 bits
HEAD=`expr ${xidtobindex} + 1`
HEAD=`expr ${HEAD} \* 2`
HEADMIN1=`expr ${HEAD} - 1`

# if we want a bit position greater than we want to
# aka xid not written in pg_xact yet
if (( $HEADMIN1 > $NBBITS))
then
echo "xid $xid status is: UNKNOWN"
exit
fi

# Read the 2 bits of interest
CSTATUS=`echo "$ALLBITS" | rev | head -c $HEAD | tail -c 2 | rev`
echo "Reading bits $HEADMIN1,$HEAD in byte $xidtobyte in page $pageinfile of file ${hexfic}"

#define TRANSACTION_STATUS_IN_PROGRESS      0x00
#define TRANSACTION_STATUS_COMMITTED        0x01
#define TRANSACTION_STATUS_ABORTED          0x02
#define TRANSACTION_STATUS_SUB_COMMITTED    0x03

echo ""
case $CSTATUS in
  0|00)
    echo "xid $xid status is: IN PROGRESS"
    ;;
  1|01)
    echo "xid $xid status is: COMMITTED"
    ;;
  10)
    echo "xid $xid status is: ABORTED"
    ;;
  11)
    echo "xid $xid status is: SUB COMMITED"
    ;;
  *)
    echo "xid $xid status is: UNKNOWN"
    ;;
esac
