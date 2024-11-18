**Usage for SSD-based indices**
===============================

To generate an SSD-friendly index, use the `apps/build_disk_index` program. 
----------------------------------------------------------------------------

The arguments are as follows:

1. **--data_type**: The type of dataset you wish to build an index on. float(32 bit), signed int8 and unsigned uint8 are supported. 
2. **--dist_fn**: Three distance functions are supported: cosine distance, minimum Euclidean distance (l2) and maximum inner product (mips).
3. **--data_file**: The input data over which to build an index, in .bin format. The first 4 bytes represent number of points as an integer. The next 4 bytes represent the dimension of data as an integer. The following `n*d*sizeof(T)` bytes contain the contents of the data one data point in time. `sizeof(T)` is 1 for byte indices, and 4 for float indices. This will be read by the program as int8_t for signed indices, uint8_t for unsigned indices or float for float indices.
4. **--index_path_prefix**: the index will span a few files, all beginning with the specified prefix path. For example, if you provide `~/index_test` as the prefix path, build  generates files such as `~/index_test_pq_pivots.bin, ~/index_test_pq_compressed.bin, ~/index_test_disk.index, ...`. There may be between 8 and 10 files generated with this prefix depending on how the index is constructed.
5. **-R (--max_degree)**  (default is 64): the degree of the graph index, typically between 60 and 150. Larger R will result in larger indices and longer indexing times, but better search quality. 
6. **-L (--Lbuild)**  (default is 100): the size of search list during index build. Typical values are between 75 to 200. Larger values will take more time to build but result in indices that provide higher recall for the same search complexity. Use a value for L value that is at least the value of R unless you need to build indices really quickly and can somewhat compromise on quality. 
7. **-B (--search_DRAM_budget)**: bound on the memory footprint of the index at search time in GB. Once built, the index will use up only the specified RAM limit, the rest will reside on disk. This will dictate how aggressively we compress the data vectors to store in memory. Larger will yield better performance at search time. For an n point index, to use b byte PQ compressed representation in memory, use `B = ((n * b) / 2^30  + (250000*(4*R + sizeof(T)*ndim)) / 2^30)`. The second term in the summation is to allow some buffer for caching about 250,000 nodes from the graph in memory while serving.  If you are not sure about this term, add 0.25GB to the first term. 
8. **-M (--build_DRAM_budget)**: Limit on the memory allowed for building the index in GB. If you specify a value less than what is required to build the index in one pass, the index is  built using a divide and conquer approach so that  sub-graphs will fit in the RAM budget. The sub-graphs are overlayed to build the overall index. This approach can be upto 1.5 times slower than building the index in one shot. Allocate as much memory as your RAM allows.
9. **-T (--num_threads)** (default is to get_omp_num_procs()): number of threads used by the index build process. Since the code is highly parallel, the  indexing time improves almost linearly with the number of threads (subject to the cores available on the machine and DRAM bandwidth).
10. **--PQ_disk_bytes**  (default is 0): Use 0 to store uncompressed data on SSD. This allows the index to asymptote to 100% recall. If your vectors are too large to store in SSD, this parameter provides the option to compress the vectors using PQ for storing on SSD. This will trade off recall. You would also want this to be greater than the number of bytes used for the PQ compressed data stored in-memory
11. **--build_PQ_bytes** (default is 0): Set to a positive value less than the dimensionality of the data to enable faster index build with PQ based distance comparisons. 
12. **--use_opq**: use the flag to use OPQ rather than PQ compression. OPQ is more space efficient for some high dimensional datasets, but also needs a bit more build time.

To search the SSD-index, use the `apps/search_disk_index` program. 
-------------------------------------------------------------------

The arguments are as follows:

1. **--data_type**: The type of dataset you wish to build an index on. float(32 bit), signed int8 and unsigned uint8 are supported. Use the same data type as in arg (1) above used in building the index.
2.  **--dist_fn**: There are two distance functions supported: minimum Euclidean distance (l2) and maximum inner product (mips). Use the same distance as in arg (2) above used in building the index.
3. **--index_path_prefix**: same as the prefix used in building the index (see arg 4 above).
4. **--num_nodes_to_cache** (default is 0): While serving the index, the entire graph is stored on SSD. For faster search performance, you can cache a few frequently accessed nodes in memory. 
5. **-T (--num_threads)** (default is to get_omp_num_procs()): The number of threads used for searching. Threads run in parallel and one thread handles one query at a time. More threads will result in higher aggregate query throughput, but will also use more IOs/second across the system, which may lead to higher per-query latency. So find the balance depending on the maximum number of IOPs supported by the SSD.
6. **-W (--beamwidth)** (default is 2): The beamwidth to be used for search. This is the maximum number of IO requests each query will issue per iteration of search code. Larger beamwidth will result in fewer IO round-trips per query, but might result in slightly higher total number of IO requests to SSD per query. For the highest query throughput with a fixed SSD IOps rating, use `W=1`. For best latency, use `W=4,8` or higher complexity search. Specifying 0 will optimize the beamwidth depending on the number of threads performing search, but will involve some tuning overhead. 
7. **--query_file**: The queries to be searched on in same binary file format as the data file in arg (2) above. The query file must be the same type as argument (1).
8. **--gt_file**: The ground truth file for the queries in arg (7) and data file used in index construction.  The binary file must start with *n*, the number of queries (4 bytes), followed by *d*, the number of ground truth elements per query (4 bytes), followed by `n*d` entries per query representing the d closest IDs per query in integer format,  followed by `n*d` entries representing the corresponding distances (float). Total file size is `8 + 4*n*d + 4*n*d` bytes. The groundtruth file, if not available, can be calculated using the program `apps/utils/compute_groundtruth`. Use "null" if you do not have this file and if you do not want to compute recall.
9. **K**: search for *K* neighbors and measure *K*-recall@*K*, meaning the intersection between the retrieved top-*K* nearest neighbors and ground truth *K* nearest neighbors.
10. **result_output_prefix**: Search results will be stored in files with specified prefix, in bin format.
11. **-L (--search_list)**: A list of search_list sizes to perform search with. Larger parameters will result in slower latencies, but higher accuracies. Must be at least the value of *K* in arg (9).


Example with BIGANN:
--------------------

This example demonstrates the use of the commands above on a 100K slice of the [BIGANN dataset](http://corpus-texmex.irisa.fr/) with 128 dimensional SIFT descriptors applied to images. 

Download the base and query set and convert the data to binary format
```bash
mkdir -p DiskANN/build/data && cd DiskANN/build/data
wget ftp://ftp.irisa.fr/local/texmex/corpus/sift.tar.gz
tar -xf sift.tar.gz
cd ..
./apps/utils/fvecs_to_bin float data/sift/sift_learn.fvecs data/sift/sift_learn.fbin
./apps/utils/fvecs_to_bin float data/sift/sift_query.fvecs data/sift/sift_query.fbin
```

Now build and search the index and measure the recall using ground truth computed using brutefoce. 
```bash
./apps/utils/compute_groundtruth  --data_type float --dist_fn l2 --base_file data/sift/sift_learn.fbin --query_file  data/sift/sift_query.fbin --gt_file data/sift/sift_query_learn_gt100 --K 100
# Using 0.003GB search memory budget for 100K vectors implies 32 byte PQ compression
./apps/build_disk_index --data_type float --dist_fn l2 --data_path data/sift/sift_learn.fbin --index_path_prefix data/sift/disk_index_sift_learn_R32_L50_A1.2 -R 32 -L50 -B 0.003 -M 1
 ./apps/search_disk_index  --data_type float --dist_fn l2 --index_path_prefix data/sift/disk_index_sift_learn_R32_L50_A1.2 --query_file data/sift/sift_query.fbin  --gt_file data/sift/sift_query_learn_gt100 -K 10 -L 10 20 30 40 50 100 --result_path data/sift/res --num_nodes_to_cache 10000
 ```

The search might be slower on machine with remote SSDs. The output lists the query throughput, the mean and 99.9pc latency in microseconds and mean number of 4KB IOs to disk for each `L` parameter provided. 

```
    L   Beamwidth             QPS    Mean Latency    99.9 Latency        Mean IOs         CPU (s)       Recall@10
======================================================================================================================
    10           2        27723.95         2271.92         4700.00            8.81           40.47           81.79
    20           2        15369.23         4121.04         7576.00           15.93           61.60           96.42
    30           2        10335.75         6147.14        11424.00           23.30           74.96           98.78
    40           2         7684.18         8278.83        14714.00           30.78           94.27           99.40
    50           2         6421.66         9913.28        16550.00           38.35          116.86           99.63
   100           2         3337.98        19107.81        29292.00           76.59          226.88           99.91
```

**用于基于SSD的索引的用法**
================================

**生成SSD友好的索引**  
使用`apps/build_disk_index`程序。  
--------------------------------------------------

参数说明如下：

1. **--data_type**：构建索引的数据集类型。支持32位浮点数(float)、有符号int8和无符号uint8。
2. **--dist_fn**：支持三种距离函数：余弦距离(cosine distance)、最小欧几里得距离(l2)和最大内积(mips)。
3. **--data_file**：用于构建索引的输入数据，格式为.bin。前4个字节表示点数(整数)，接下来的4个字节表示数据维度(整数)。后续为`n*d*sizeof(T)`字节数据，每次表示一个数据点，其中`sizeof(T)`为有符号或无符号字节索引时为1，浮点索引时为4。
4. **--index_path_prefix**：索引会生成几个文件，所有文件的前缀路径都相同。例如，提供路径前缀`~/index_test`，会生成文件如`~/index_test_pq_pivots.bin`，`~/index_test_pq_compressed.bin`，`~/index_test_disk.index`等，具体数量取决于索引构建方式。
5. **-R (--max_degree)**（默认值为64）：图索引的度数，通常在60到150之间。R值越大，索引越大，构建时间越长，但搜索质量越高。
6. **-L (--Lbuild)**（默认值为100）：索引构建时的搜索列表大小。典型值为75到200。值越大，构建时间越长，但索引的召回率也会提高。L值通常至少应等于R值。
7. **-B (--search_DRAM_budget)**：索引搜索时的内存限制，单位为GB。索引构建后，仅使用指定的内存，剩余部分存储在磁盘上。内存越大，搜索性能越好。
8. **-M (--build_DRAM_budget)**：构建索引时的内存限制，单位为GB。如果指定值小于所需内存，索引将分段构建，并合并生成整体索引。分段构建的速度可能是一次性构建的1.5倍。
9. **-T (--num_threads)**（默认值为`get_omp_num_procs()`）：构建索引时使用的线程数。线程数越多，构建时间几乎呈线性下降（受限于机器的核心数量和内存带宽）。
10. **--PQ_disk_bytes**（默认值为0）：设置为0以在SSD上存储未压缩数据。设置此值以使用PQ压缩存储在SSD上的向量数据，从而在召回率上进行权衡。
11. **--build_PQ_bytes**（默认值为0）：设置为小于数据维度的正值，以启用基于PQ的距离比较，从而加速索引构建。
12. **--use_opq**：使用此标志启用OPQ压缩，而非PQ压缩。OPQ在某些高维数据集上更节省空间，但需要更多的构建时间。

**搜索SSD索引**  
使用`apps/search_disk_index`程序。  
-------------------------------------------------

参数说明如下：

1. **--data_type**：构建索引时所使用的数据集类型（float、int8、uint8）。
2. **--dist_fn**：支持两种距离函数：最小欧几里得距离(l2)和最大内积(mips)。需与构建索引时的距离函数保持一致。
3. **--index_path_prefix**：与构建索引时的前缀路径相同。
4. **--num_nodes_to_cache**（默认值为0）：索引的整个图存储在SSD上。为了更快的搜索性能，可以在内存中缓存一些频繁访问的节点。
5. **-T (--num_threads)**（默认值为`get_omp_num_procs()`）：搜索时的线程数。线程以并行方式运行，每个线程一次处理一个查询。
6. **-W (--beamwidth)**（默认值为2）：搜索时的beamwidth，即每个查询在每次迭代中发出的最大IO请求数。较大的beamwidth会减少查询的IO轮询次数，但可能会增加每次查询的IO总请求数。
7. **--query_file**：用于搜索的查询文件，与构建索引时的数据类型相同。
8. **--gt_file**：查询的ground truth文件，包含查询的最近邻点及其距离。如果没有该文件，可使用`apps/utils/compute_groundtruth`程序计算。
9. **K**：搜索的最近邻个数，计算`K`的召回率，即检索的前`K`最近邻与ground truth的前`K`最近邻的交集。
10. **result_output_prefix**：搜索结果将以指定的前缀存储为bin格式文件。
11. **-L (--search_list)**：搜索时的搜索列表大小。值越大，延迟越高，但准确率越高。至少需要等于参数`K`的值。

**BIGANN示例：**  
--------------------------------
以下示例演示了在100K大小的BIGANN数据集切片上，使用128维SIFT描述符的索引构建和搜索。

下载数据并转换为二进制格式：
```bash
mkdir -p DiskANN/build/data && cd DiskANN/build/data
wget ftp://ftp.irisa.fr/local/texmex/corpus/sift.tar.gz
tar -xf sift.tar.gz
cd ..
./apps/utils/fvecs_to_bin float data/sift/sift_learn.fvecs data/sift/sift_learn.fbin
./apps/utils/fvecs_to_bin float data/sift/sift_query.fvecs data/sift/sift_query.fbin
```

构建索引并使用bruteforce计算召回率：
```bash
./apps/utils/compute_groundtruth --data_type float --dist_fn l2 --base_file data/sift/sift_learn.fbin --query_file data/sift/sift_query.fbin --gt_file data/sift/sift_query_learn_gt100 --K 100
./apps/build_disk_index --data_type float --dist_fn l2 --data_path data/sift/sift_learn.fbin --index_path_prefix data/sift/disk_index_sift_learn_R32_L50_A1.2 -R 32 -L50 -B 0.003 -M 1
./apps/search_disk_index --data_type float --dist_fn l2 --index_path_prefix data/sift/disk_index_sift_learn_R32_L50_A1.2 --query_file data/sift/sift_query.fbin --gt_file data/sift/sift_query_learn_gt100 -K 10 -L 10 20 30 40 50 100 --result_path data/sift/res --num_nodes_to_cache 10000
```

搜索在远程SSD的机器上可能较慢，输出将列出查询吞吐量、平均和99.9%的延迟、每查询的平均4KB IO数以及召回率。