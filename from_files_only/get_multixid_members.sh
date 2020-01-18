#!/bin/bash

if [ "$1" = "--help" ] || [ $# -ne 4 ] ; then
  echo ""
  echo "Usage: "
  echo ""
  echo "-m: mxid"
  echo "-d: DATA path"
  echo ""
  echo "example: ./get_multixid_members.sh -m 2 -d /usr/local/pgsql11.6/data/"
  exit 0
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -m|--mxid)
    mxid="$2"
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
echo "MXID   = ${mxid}"
echo "DATA   = ${pgdata}"
echo ""

#See multixact.c:
#MULTIXACT_OFFSETS_PER_PAGE is 2048
#SLRU_PAGES_PER_SEGMENT is 32
#MULTIXACT_MEMBERS_PER_MEMBERGROUP is 4
#MULTIXACT_MEMBERGROUP_SIZE is 20
#MULTIXACT_MEMBERGROUPS_PER_PAGE is 409
#MULTIXACT_MEMBERS_PER_PAGE is 1636
#MAX_MEMBERS_IN_LAST_MEMBERS_PAGE is 1036
#sizeof(TransactionId) is 4

OFFLOC="${pgdata}/pg_multixact/offsets/"
MEMBLOC="${pgdata}/pg_multixact/members/"

#define MultiXactIdToOffsetPage(xid) \ ((xid) / (MultiXactOffset) MULTIXACT_OFFSETS_PER_PAGE)
pagenumber=`expr ${mxid} / 2048`
pageinfile=`expr ${pagenumber} % 32`

#define MultiXactIdToOffsetSegment(xid) (MultiXactIdToOffsetPage(xid) / SLRU_PAGES_PER_SEGMENT)
hexfic=`expr ${pagenumber} / 32`
hexfic=`echo "ibase=10;obase=16;${hexfic}" | bc`
hexfic=`printf "%04x" "0x${hexfic}" | tr '[:lower:]' '[:upper:]'`

#define MultiXactIdToOffsetEntry(xid) \ ((xid) % (MultiXactOffset) MULTIXACT_OFFSETS_PER_PAGE)
offsetid=`expr ${mxid} % 2048`

# Same computation with next mxid
nextmxid=`expr ${mxid} + 1`
nextpagenumber=`expr ${nextmxid} / 2048`
nextpageinfile=`expr ${nextpagenumber} % 32`
nexthexfic=`expr ${nextpagenumber} / 32`
nexthexfic=`echo "ibase=10;obase=16;${nexthexfic}" | bc`
nexthexfic=`printf "%04x" "0x${nexthexfic}" | tr '[:lower:]' '[:upper:]'`
nextoffsetid=`expr ${nextmxid} % 2048`

#echo "Looking for offset $offsetid in page $pagenumber"
#echo "Page $pagenumber is page $pageinfile in file ${OFFLOC}${hexfic}"
#echo ""

# read with dd
skipread=`expr ${offsetid} \* 4`
next_skipread=`expr ${nextoffsetid} \* 4`

offset_members=`dd status=none bs=8192 count=1 if=${OFFLOC}${hexfic} skip=$pageinfile | od -A n -t u4 -j $skipread -N 4 | sed 's/^ *//'`
next_offset_members=`dd status=none bs=8192 count=1 if=${OFFLOC}${nexthexfic} skip=$nextpageinfile | od -A n -t u4 -j $next_skipread -N 4 | sed 's/^ *//'`
#echo "Offset value is: ${offset_members}"
#echo "NextOffset value is: ${next_offset_members}"

[ ${offset_members} -eq 0 ] && echo "No members to look for, exiting...." && exit 0

# Now look at the members
echo ""
echo "Members are:"
off=${offset_members}

if [ ! ${next_offset_members} -eq 0 ]
then

  while [ $off -lt $next_offset_members ]
  do
  #define MXOffsetToMemberPage(xid) ((xid) / (TransactionId) MULTIXACT_MEMBERS_PER_PAGE)
  memberpage=`expr ${off} / 1636`
  memberpageinfile=`expr ${memberpage} % 32`

  #define MXOffsetToMemberSegment(xid) (MXOffsetToMemberPage(xid) / SLRU_PAGES_PER_SEGMENT)
  membersegment=`expr ${memberpage} / 32`
  membersegment=`echo "ibase=10;obase=16;${membersegment}" | bc`
  membersegment=`printf "%04x" "0x${membersegment}" | tr '[:lower:]' '[:upper:]'`

  #define MXOffsetToFlagsOffset(xid) \ ((((xid) / (TransactionId) MULTIXACT_MEMBERS_PER_MEMBERGROUP) % (TransactionId) MULTIXACT_MEMBERGROUPS_PER_PAGE) * (TransactionId) MULTIXACT_MEMBERGROUP_SIZE)
  flagtooffset=`echo "$(( (${off} / 4 ) % 409 * 20 ))"`

  #define MXOffsetToMemberOffset(xid) \ (MXOffsetToFlagsOffset(xid) + MULTIXACT_FLAGBYTES_PER_GROUP + ((xid) % MULTIXACT_MEMBERS_PER_MEMBERGROUP) * sizeof(TransactionId))
  memberoffset=`echo "$(( ${flagtooffset} + 4 + ( ${off} % 4) * 4 ))"`

  #echo "Reading offset $memberoffset in page $memberpageinfile in file ${MEMBLOC}${membersegment}"
  dd status=none bs=8192 count=1 if=${MEMBLOC}${membersegment} skip=$memberpageinfile | od -A n -t u4 -j $memberoffset -N 4 | sed 's/^ *//'
  off=$(( $off + 1 ))
  done

else
  nextone=true
  while $nextone
  do
  #define MXOffsetToMemberPage(xid) ((xid) / (TransactionId) MULTIXACT_MEMBERS_PER_PAGE)
  memberpage=`expr ${off} / 1636`
  memberpageinfile=`expr ${memberpage} % 32`

  #define MXOffsetToMemberSegment(xid) (MXOffsetToMemberPage(xid) / SLRU_PAGES_PER_SEGMENT)
  membersegment=`expr ${memberpage} / 32`
  membersegment=`echo "ibase=10;obase=16;${membersegment}" | bc`
  membersegment=`printf "%04x" "0x${membersegment}" | tr '[:lower:]' '[:upper:]'`

  #define MXOffsetToFlagsOffset(xid) \ ((((xid) / (TransactionId) MULTIXACT_MEMBERS_PER_MEMBERGROUP) % (TransactionId) MULTIXACT_MEMBERGROUPS_PER_PAGE) * (TransactionId) MULTIXACT_MEMBERGROUP_SIZE)
  flagtooffset=`echo "$(( (${off} / 4 ) % 409 * 20 ))"`

  #define MXOffsetToMemberOffset(xid) \ (MXOffsetToFlagsOffset(xid) + MULTIXACT_FLAGBYTES_PER_GROUP + ((xid) % MULTIXACT_MEMBERS_PER_MEMBERGROUP) * sizeof(TransactionId))
  memberoffset=`echo "$(( ${flagtooffset} + 4 + ( ${off} % 4) * 4 ))"`

  #echo "Reading offset $memberoffset in page $memberpageinfile in file ${MEMBLOC}${membersegment}"
  THISMEMB=`dd status=none bs=8192 count=1 if=${MEMBLOC}${membersegment} skip=$memberpageinfile | od -A n -t u4 -j $memberoffset -N 4 | sed 's/^ *//'`
  if [ $THISMEMB -ne 0 ]
    then
    echo "${THISMEMB}"
    off=$(( $off + 1 ))
  else
    nextone=false
  fi 
  done

fi
