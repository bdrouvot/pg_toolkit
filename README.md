`pg_toolkit` – Some scripts for postgresql
=============================================================

compare_disk_mem directory
--------------------------

Some scripts to compare pages in memory and on disk

* `page_header_info.sh`: to inspect page header from memory and from disk
* `heap_page_items_info.sh`: to inspect heap page items from memory and from disk
* `bt_metap_info.sh`: to inspect B-tree index's metapage from memory and from disk
* `bt_page_items_info.sh`: to inspect B-tree index's page items from memory and from disk
* `bt_page_stats_info.sh`: to get summary information about single pages of B-tree indexes from memory and from disk

Example:

    $ ./bt_page_stats_info.sh

    Usage: 

    -b: block to inspect
    -p: relation path on disk
    -bt: btree name
    -i: where to inspect (disk, memory, both)

    $ ./bt_page_stats_info.sh -b 15 -p /usr/local/pgsql12.0/data/base/13593/139931 -bt bdtidx -i both

    BLOCK   = 15
    PATH    = /usr/local/pgsql12.0/data/base/13593/139931
    BTREE   = bdtidx
    INSPECT = both
    
    from | blkno | type | live_items | dead_items | avg_item_size | free_size  | btpo_prev | btpo_next | btpo | btpo_flags
    -----+-------+------+------------+------------+---------------+------------+-----------+-----------+------+-----------
    dsk  | 15    | l    | 239        | 0          | 16            |  3368      | 0         | 111       | 0    | 1          
    mem  | 15    | l    | 239        | 0          | 16            |  3368      | 0         | 111       | 0    | 1          
    
    $ psql -c "insert into bdt select generate_series(1, 5000),generate_series(1,5000),'bdt'" 
    INSERT 0 5000
    
    $ ./bt_page_stats_info.sh -b 15 -p /usr/local/pgsql12.0/data/base/13593/139931 -bt bdtidx -i both
    
    BLOCK   = 15
    PATH    = /usr/local/pgsql12.0/data/base/13593/139931
    BTREE   = bdtidx
    INSPECT = both
    
    from | blkno | type | live_items | dead_items | avg_item_size | free_size  | btpo_prev | btpo_next | btpo | btpo_flags
    -----+-------+------+------------+------------+---------------+------------+-----------+-----------+------+-----------
    dsk  | 15    | l    | 239        | 0          | 16            |  3368      | 0         | 111       | 0    | 1          
    mem  | 15    | l    | 273        | 0          | 16            |  2688      | 0         | 111       | 0    | 1          
    
    $ psql -c "checkpoint"
    CHECKPOINT
    
    $ ./bt_page_stats_info.sh -b 15 -p /usr/local/pgsql12.0/data/base/13593/139931 -bt bdtidx -i both
    
    BLOCK   = 15
    PATH    = /usr/local/pgsql12.0/data/base/13593/139931
    BTREE   = bdtidx
    INSPECT = both
    
    from | blkno | type | live_items | dead_items | avg_item_size | free_size  | btpo_prev | btpo_next | btpo | btpo_flags
    -----+-------+------+------------+------------+---------------+------------+-----------+-----------+------+-----------
    dsk  | 15    | l    | 273        | 0          | 16            |  2688      | 0         | 111       | 0    | 1          
    mem  | 15    | l    | 273        | 0          | 16            |  2688      | 0         | 111       | 0    | 1          

from_files_only
--------------------------

Some scripts to get information from files only

* `get_multixid_members.sh`: to retrieve multixid members from pg_multixact/offsets and pg_multixact/members

Example:

     $ ./get_multixid_members.sh -help

     Usage:

     -m: mxid
     -d: DATA path

     $ ./get_multixid_members.sh -m 3406700053 -d /usr/local/pgsql11.6/data

     MXID   = 3406700053
     DATA   = /usr/local/pgsql11.6/data

     Members are:
     1191575939
     1191576073
     1191576075

     # Verification from postgres

     #SELECT * FROM pg_get_multixact_members('3406700053');

     xid     | mode
     ------------+-------
     1191575939 | keysh
     1191576073 | keysh
     1191576075 | keysh

* `get_xact_status.sh`: to retrieve xact status from the pg_xact directory  

Example:

     postgres=# select txid_current_snapshot();
      txid_current_snapshot
     -----------------------
      31795295:31795295:
     (1 row)
     
     postgres=# \! ./get_xact_status.sh -x 31795295 -d /usr/local/pgsql12.1-bench/data
     
     XID   = 31795295
     DATA  = /usr/local/pgsql12.1-bench/data
     
     xid 31795295 status is: UNKNOWN
     postgres=#
     postgres=# insert into bdt values (1);
     INSERT 0 1
     postgres=# checkpoint;
     CHECKPOINT
     postgres=# \! ./get_xact_status.sh -x 31795295 -d /usr/local/pgsql12.1-bench/data
     
     XID   = 31795295
     DATA  = /usr/local/pgsql12.1-bench/data
     
     Reading bits 7,8 in byte 2583 in page 10 of file 001E
     
     xid 31795295 status is: COMMITTED
     postgres=#
     postgres=# begin;
     BEGIN
     postgres=# insert into bdt values (1);
     INSERT 0 1
     postgres=# rollback;
     ROLLBACK
     postgres=# checkpoint;
     CHECKPOINT
     postgres=# \! ./get_xact_status.sh -x 31795296 -d /usr/local/pgsql12.1-bench/data
     
     XID   = 31795296
     DATA  = /usr/local/pgsql12.1-bench/data
     
     Reading bits 1,2 in byte 2584 in page 10 of file 001E
     
     xid 31795296 status is: ABORTED
