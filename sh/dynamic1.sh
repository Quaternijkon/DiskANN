type='float'
data='data/sift/sift_learn.fbin'
query='data/sift/sift_query.fbin'
index_prefix='data/sift/index'
result='data/sift/res'
deletes=25000
inserts=75000
deletes_after=50000
pts_per_checkpoint=10000
begin=0
thr=64
index=${index_prefix}.after-concurrent-delete-del${deletes}-${inserts}
gt_file=data/sift/gt100_learn-conc-${deletes}-${inserts}

 ~/DiskANN/build/apps/test_insert_deletes_consolidate  --data_type ${type} --dist_fn l2 --data_path ${data}  --index_path_prefix ${index_prefix} -R 64 -L 300 --alpha 1.2 -T ${thr} --points_to_skip 0 --max_points_to_insert ${inserts} --beginning_index_size ${begin} --points_per_checkpoint ${pts_per_checkpoint} --checkpoints_per_snapshot 0 --points_to_delete_from_beginning ${deletes} --start_deletes_after ${deletes_after} --do_concurrent true;

 ~/DiskANN/build/apps/utils/compute_groundtruth --data_type ${type} --dist_fn l2 --base_file ${index}.data  --query_file ${query}  --K 100 --gt_file ${gt_file} --tags_file  ${index}.tags

 ~/DiskANN/build/apps/search_memory_index  --data_type ${type} --dist_fn l2 --index_path_prefix ${index} --result_path ${result} --query_file ${query}  --gt_file ${gt_file}  -K 10 -L 20 40 60 80 100 -T ${thr} --dynamic true --tags 1