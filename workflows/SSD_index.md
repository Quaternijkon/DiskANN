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

**基于SSD的索引使用方法**
===============================

要生成一个适合SSD的索引，请使用`apps/build_disk_index`程序。
----------------------------------------------------------------------------

参数说明如下：

1. **--data_type**: 要构建索引的数据集类型。支持32位浮点数（float）、8位有符号整数（signed int8）和8位无符号整数（unsigned uint8）。 
2. **--dist_fn**: 支持三种距离函数：余弦距离（cosine distance）、最小欧几里得距离（l2）和最大内积（mips）。
3. **--data_file**: 输入的数据文件，以.bin格式存储。文件的前4个字节表示数据点的数量（整数），接下来的4个字节表示数据的维度（整数）。之后的`n*d*sizeof(T)`字节包含数据的内容，每次存储一个数据点。`sizeof(T)`对于字节索引为1，对于浮点数索引为4。程序将按签名索引（int8_t）、无符号索引（uint8_t）或浮点数索引（float）读取这些数据。
4. **--index_path_prefix**: 索引将跨多个文件生成，所有文件名前缀为指定的路径。例如，如果提供`~/index_test`作为前缀路径，生成的文件将类似于`~/index_test_pq_pivots.bin`、`~/index_test_pq_compressed.bin`、`~/index_test_disk.index`等。生成的文件数目通常在8到10个之间，具体取决于索引构建方式。
5. **-R (--max_degree)** （默认值为64）：图索引的度数，通常在60到150之间。较大的R值会导致更大的索引和更长的构建时间，但能提供更好的搜索质量。 
6. **-L (--Lbuild)** （默认值为100）：构建索引时的搜索列表大小。通常值在75到200之间。较大的L值会增加构建时间，但会提高索引的召回率。除非需要非常快速地构建索引并且可以在质量上做出一些妥协，否则L的值应至少为R的值。
7. **-B (--search_DRAM_budget)**: 搜索时索引的内存限制，单位为GB。索引构建后，将仅使用指定的内存限制，剩余部分存储在磁盘上。此参数决定了我们在内存中压缩数据向量的程度。较大的B值将提高搜索时的性能。对于n个数据点的索引，使用b字节的PQ压缩表示存储在内存中时，使用公式`B = ((n * b) / 2^30 + (250000*(4*R + sizeof(T)*ndim)) / 2^30)`来计算。公式中的第二项用于缓存大约250,000个图节点的缓冲区。如果不确定此项的大小，可以在第一项基础上加上0.25GB。
8. **-M (--build_DRAM_budget)**: 构建索引时允许使用的内存限制，单位为GB。如果指定的值小于构建索引所需的内存，则会使用分治法构建索引，将子图按内存限制合并。此方法可能比一次性构建索引慢1.5倍。应根据机器的RAM大小分配尽可能多的内存。
9. **-T (--num_threads)** （默认值为`get_omp_num_procs()`）：构建索引时使用的线程数。由于代码高度并行化，线程数增加会使索引构建时间几乎线性缩短（受机器核心数和内存带宽的限制）。
10. **--PQ_disk_bytes** （默认值为0）：使用0表示在SSD上存储未压缩的数据。这允许索引达到100%的召回率。如果数据向量太大无法存储在SSD中，则可以使用PQ压缩向量并存储在SSD上。这会牺牲一定的召回率。此参数值应大于在内存中存储PQ压缩数据所使用的字节数。
11. **--build_PQ_bytes** （默认值为0）：设置一个小于数据维度的正值，以启用基于PQ的距离比较进行更快速的索引构建。
12. **--use_opq**: 使用该标志启用OPQ压缩而非PQ压缩。OPQ对于某些高维数据集更节省空间，但也需要更多的构建时间。

要搜索SSD索引，请使用`apps/search_disk_index`程序。
-------------------------------------------------------------------

参数说明如下：

1. **--data_type**: 要构建索引的数据集类型。支持32位浮点数（float）、8位有符号整数（signed int8）和8位无符号整数（unsigned uint8）。必须与构建索引时的参数（1）相同。
2. **--dist_fn**: 支持两种距离函数：最小欧几里得距离（l2）和最大内积（mips）。必须与构建索引时的参数（2）相同。
3. **--index_path_prefix**: 与构建索引时使用的前缀相同（参见参数4）。
4. **--num_nodes_to_cache** （默认值为0）：在搜索时，整个图存储在SSD上。为了提高搜索性能，您可以将一些经常访问的节点缓存到内存中。
5. **-T (--num_threads)** （默认值为`get_omp_num_procs()`）：搜索时使用的线程数。线程并行运行，每个线程处理一个查询。增加线程数可以提高查询吞吐量，但也会增加系统的IO操作次数，从而可能导致更高的每查询延迟。根据SSD的最大IOPS选择合适的线程数。
6. **-W (--beamwidth)** （默认值为2）：搜索时使用的宽度。这是每次搜索迭代中，每个查询最多发出的IO请求数。较大的宽度将减少每个查询的IO往返次数，但可能导致每查询的总IO请求数略有增加。为了在固定的SSD IOPS下实现最高的查询吞吐量，使用`W=1`。为了获得最佳的延迟，使用`W=4,8`或更复杂的搜索。指定0时，宽度将根据执行搜索的线程数自动优化，但可能会涉及一定的调优开销。
7. **--query_file**: 查询文件，格式与参数（2）中的数据文件相同。查询文件的类型必须与构建索引时的参数（1）相同。
8. **--gt_file**: 查询文件的 ground truth 文件，格式与构建索引时的数据文件相同。二进制文件应以`n`（查询数量，4字节）开始，接着是`d`（每个查询的ground truth元素数，4字节），然后是`n*d`个整数（表示每个查询的d个最近邻的ID），之后是`n*d`个浮点数（表示对应的距离）。总文件大小为`8 + 4*n*d + 4*n*d`字节。如果没有ground truth文件，可以使用`apps/utils/compute_groundtruth`程序计算。如果没有该文件，也不想计算召回率，可以使用"null"。
9. **K**: 搜索*K*个邻居并测量*K*-召回率（K-recall@K），即检索到的前*K*个邻居与ground truth中*K*个最近邻的交集。
10. **result_output_prefix**: 搜索结果将存储在以指定前缀命名的文件中，文件格式为二进制。
11. **-L (--search_list)**: 要使用的多个搜索列表大小。较大的参数将导致更慢的延迟，但更高的准确率。该值必须至少为参数（9）中K的值。

**BIGANN示例：**
--------------------

该示例演示了在128维SIFT描述符上，使用上面命令操作100K大小的[BIGANN数据集](http://corpus-texmex.irisa.fr/)。

下载基准和查询集并转换为二进制格式：
```bash
mkdir -p DiskANN/build/data && cd DiskANN/build/data
wget ftp://ftp.irisa.fr/local/texmex/corpus/sift.tar.gz
tar -xf sift.tar.gz
cd ..
./apps/utils/fvecs_to_bin float data/sift/sift_learn.fvecs data/sift/sift_learn.fbin
./apps/utils/fvecs_to_bin float data/sift/sift_query.fvecs data/sift/sift_query.fbin
```

现在构建索引并进行搜索，使用暴力计算的ground truth测量召回率：
```bash
./apps/utils/compute_groundtruth  --data_type float --dist_fn l2 --base_file data/sift/sift_learn.fbin --query_file  data/sift/sift_query.fbin --gt_file data/sift/sift_query_learn_gt100 --K 100
# 使用0.003GB搜索

内存预算，针对100K向量进行32字节的PQ压缩
./apps/build_disk_index --data_type float --dist_fn l2 --data_path data/sift/sift_learn.fbin --index_path_prefix data/sift/disk_index_sift_learn_R32_L50_A1.2 -R 32 -L50 -B 0.003 -M 1
 ./apps/search_disk_index  --data_type float --dist_fn l2 --index_path_prefix data/sift/disk_index_sift_learn_R32_L50_A1.2 --query_file data/sift/sift_query.fbin  --gt_file data/sift/sift_query_learn_gt100 -K 10 -L 10 20 30 40 50 100 --result_path data/sift/res --num_nodes_to_cache 10000
 ```

搜索在使用远程SSD的机器上可能会较慢。输出结果列出了每个`L`参数设置下的查询吞吐量、平均延迟和99.9%延迟（单位为微秒），以及每个查询的平均4KB磁盘IO次数。

```
    L   Beamwidth             QPS    平均延迟（微秒）    99.9%延迟（微秒）    平均IO次数      CPU时间（秒）    Recall@10
======================================================================================================================
    10           2        27723.95         2271.92         4700.00            8.81           40.47           81.79
    20           2        15369.23         4121.04         7576.00           15.93           61.60           96.42
    30           2        10335.75         6147.14        11424.00           23.30           74.96           98.78
    40           2         7684.18         8278.83        14714.00           30.78           94.27           99.40
    50           2         6421.66         9913.28        16550.00           38.35          116.86           99.63
   100           2         3337.98        19107.81        29292.00           76.59          226.88           99.91
```