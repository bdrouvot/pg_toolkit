SELECT 
-- See htup_details.h
       t_ctid AS ctid,
       t_xmin AS xmin,
       t_xmax AS xmax,
       t_infomask, 
       (t_infomask & 16)::boolean AS xmax_kshr_lock,
       (t_infomask & 64)::boolean AS xmax_excl_lock,
       (t_infomask & 128)::boolean AS xmax_lock_only,
       (t_infomask & 1024)::boolean AS xmax_committed,
       (t_infomask & 2048)::boolean AS xmax_invalid,
       (t_infomask & 4096)::boolean AS xmax_multixact,
       (t_infomask & 1)::boolean AS has_null,
       (t_infomask & 2)::boolean AS has_varwidth,
       (t_infomask & 4)::boolean AS has_external,
       (t_infomask & 8)::boolean AS has_oid,
       (t_infomask & 32)::boolean AS combo_cid,
       (t_infomask & 256)::boolean AS xmin_commited,
       (t_infomask & 512)::boolean AS xmin_invalid,
       (t_infomask::bit(16) & x'0300' = x'0300'::bit(16))::boolean AS xmin_frozen,
       (t_infomask & 8192)::boolean AS updated,
       (t_infomask & 16384)::boolean AS moved_off,
       (t_infomask & 32768)::boolean AS moved_in,
       ((((((t_infomask & ~16) & ~64) & ~128) & ~1024) & ~2048) & ~4096) | 2048 as infomask_with_xmax_invalid,
       t_infomask2, 
       (t_infomask2 & 8192)::boolean AS keys_updated,
       (t_infomask2 & 16384)::boolean AS hot_updated,
       (t_infomask2 & 32768)::boolean AS only_tuple
FROM heap_page_items(get_raw_page('parent', 0)) ;

select  lp,t_ctid, 
	CASE WHEN t_infomask::bit(16) & x'0300' = x'0300'::bit(16) THEN 'HEAP_XMIN_FROZEN|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'8000' = x'8000'::bit(16) THEN 'MOVED_IN|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'4000' = x'4000'::bit(16) THEN 'MOVED_OFF|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'2000' = x'2000'::bit(16) THEN 'UPDATED|'
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'1000' = x'1000'::bit(16) THEN 'XMAX_IS_MULTI|'
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0800' = x'0800'::bit(16) THEN 'XMAX_INVALID|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0400' = x'0400'::bit(16) THEN 'XMAX_COMMITTED|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0200' = x'0200'::bit(16) THEN 'XMIN_INVALID|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0080' = x'0080'::bit(16) THEN 'XMAX_LOCK_ONLY|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0040' = x'0040'::bit(16) THEN 'EXCL_LOCK|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0020' = x'0020'::bit(16) THEN 'COMBOCID|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0010' = x'0010'::bit(16) THEN 'XMAX_KEYSHR_LOCK|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0008' = x'0008'::bit(16) THEN 'HASOID|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0004' = x'0004'::bit(16) THEN 'HASEXTERNAL|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0002' = x'0002'::bit(16) THEN 'HASVARWIDTH|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0001' = x'0001'::bit(16) THEN 'HASNULL|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask::bit(16) & x'0100' = x'0100'::bit(16) THEN 'XMIN_COMMITTED|' 
	ELSE '|'
	END as t_infomask_info,
	CASE WHEN t_infomask2::bit(16) & x'2000' = x'2000'::bit(16) THEN 'HEAP_KEYS_UPDATED|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask2::bit(16) & x'4000' = x'4000'::bit(16) THEN 'HEAP_HOT_UPDATED|' 
	ELSE '|'
	END
	|| CASE WHEN t_infomask2::bit(16) & x'8000' = x'8000'::bit(16) THEN 'HEAP_ONLY_TUPLE|' 
	ELSE '|'
	END as t_infomask2_info
FROM heap_page_items(get_raw_page('parent', 0));
