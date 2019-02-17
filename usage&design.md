# URL count mapreduce 使用说明 & 详设

## 使用说明

1. **GOPATH=~\URL_counter_mapreduce**
2. 中间结果输出  
    在 `src/main/main.go` 和 `src/mapreduce/common.go` 中修改 `debugEnabled` 的值。
    - 若为 true 则输出 debug 的打印信息，否则不输出。
3. 运行src/main/main.sh 其输出即为正序的top100的URL
   - 参数解释  
        |参数|解释|
        |:---|:---|
        |master|当前运行的为master节点|
        |distributed|运行的为分布式模式（可替换为 sequential）|
        |(sequential)|运行单线程模式（只有一个worker）**debug/测试使用**|
        |data*.txt|输入的文件|

    `sort -n -k2 mrtmp.wcseq | tail -100` 用于对reducer输出的文件进行排序，并输出最后100条
    余下的部分用于清除中间文件
4. 单元测试（在`src/mapreduce` 目录下）  
    均在 `src/mapreduce/test_test.go` 下实现
   1. 测试基础的map/reduce功能  
        `go test -run Sequential`
   2. 测试多线程下的worker协同通信情况
        `go test -run TestParallel`

## 详设

main/main.go

- mapF
    将文件中的每个 URL 分离出来并处理成键值对
  - 参数
    - filename(string)：传入文件名
    - contents(string)：传入文件内容，每个文件内容以字符串形式进行处理
  - 返回值
    - []mapreduce.KeyValue：返回 KeyValue 类型的切片
        即 mapF 处理每个 URL 为对应的键值对 `{word, ""}`
- reduceF
    统计每个key值出现的次数并以 string 类型返回
  - 参数
    - key(string)：每个键值对的 word
    - values([]string)：每个键值对中的value经过合并产生的切片
  - 返回值
    - (string)：统计values切片的元素个数并转换为string类型返回

mapreduce/common.go

- reduceName
    在 map 阶段完成时调用，返回处理的中间文件的文件名
  - 参数
    - jobName(string)：当前的任务名
    - mapTask(int)：完成的 map 任务编号
    - reduceTask(int)：目标 reducer 的编号
  - 返回值
    - (string)：产生的文件名
- mergeName
    在 reduce 阶段完成时调用，返回生成的 reduce 结果的文件名
  - 参数
    - jobName(string)：当前的任务名
    - reduceTask(int)：完成的 reduce 任务编号
  - 返回值
    - (string)：产生的文件名

mapreduce/common_map.go

- doMap
    处理 map 阶段任务，通过 mapF 得到对应的键值对并分类写入对应中间文件
  - 参数
    - jobName(string)：当前任务名
    - mapTask(int)：当前 map 任务的编号
    - inFile(string)：传入的文件名（单一文件）
    - nReduce(int)：将进行 reduce 任务的机器数量
    - mapF(func)：参数和返回值同 main/main.go/mapF
  - 无返回值
- ihash
    针对每个 key 生成其 hash 并以 int 类型返回
  - 参数
    - s(string)：key
  - 返回值
    - (int)：当前 key 的 hash

mapreduce/common_reduce.go

- doReduce
    处理 reduce 阶段任务，合并相同 key 值的项并进行计数，写入结果文件
  - 参数
    - jobTask(string)：当前任务名
    - reduceTask(int)：当前 reduce 任务编号
    - outFile(string)：输出文件名/路径
    - nMap(int)：map 任务的总数
    - reduceF(func)：参数和返回值同 main/main.go/reduceF
  - 无返回值

mapreduce/common_rpc.go

- call
    包装 `rpc.Dail()` 并进行异常处理
  - 参数
    - srv(string)：发出 rpc 请求的 worker 的 rpc 地址
    - rpcname(string)：处理此 rpc 请求的主机地址
    - args(interface{})：通过 rpc 进行传输的报文格式
    - reply(interface{})：同 args
  - 返回值
    - (bool)：是否成功进行通信（是否找到主机/通信中是否有错误）

mapreduce/master.go

- newMaster
    master 节点的初始化
  - 参数
    - master(string)：master 节点的 rpc 地址
  - 返回值
    - mr(*Master)：初始化成功的 Master 对象
- Sequential
    控制顺序运行整个 mapreduce 任务（当一个任务完成了再分配下一个）
  - 参数
    - jobName(string)：当前任务名
    - files([]string)：所有传入的文件名
    - nreduce(int)：进行 reduce 任务的机器数量
    - mapF(func)：参数和返回值同 main/main.go/mapF
    - reduceF(func)：参数和返回值同 main/main.go/reduceF
  - 返回值
    - mr(*Master)：完成流程的 Master 对象
- forwardRegistrations
    通过一个 channel ch 转发当前存在的且新注册的节点的 rpc 的地址
    schedule() 通过读取 ch 了解当前 worker 的工作情况
  - 参数
    - ch(chan string)：传递 worker 的 rpc 地址通道
  - 无返回值
- Distributed
    控制分布式情况下的部分任务（schedule 和 forwardRegistrations）
  - 参数
    - jobName(string)
    - files([]string)
    - nreduce(int)
    - master(string)
  - 返回值
    - mr(*Master)：完成流程的 Master 对象
- GoDistributed
    控制分布式状态下的 mapreduce 任务
  - 参数
    - jobName(string)
    - files([]string)
    - nReduce(int)
    - master(string)
    - mapF(func)：参数和返回值同 main/main.go/mapF
    - reduceF(func)：参数和返回值同 main/main.go/reduceF
  - 返回值
    - mr(*Master)：完成流程的 Master 对象
- run
    实际控制 worker 执行 mapreduce 任务
    首先将输入的文件分配到每个 mapper 上，再分配 reduce 任务，最终进行文件合并
  - 参数
    - jobName(string)：当前任务名
    - files([]string)：输入的所有文件
    - nreduce(int)：执行 reduce 任务的机器数量
    - schedule(func)：参数和返回值同 mapreduce/schedule.go/schedule
    - finish(func)
        使用匿名函数，控制使所有 worker 下线并注销主机的 rpc 服务
      - 无参数和返回值
  - 无返回值
- Wait
    使主线程等待至所有任务结束
  - 无参数和返回值
- killWorkers
    使注册在主机的 worker 下线并返回当前 worker 完成任务的数量
  - 无参数
  - 返回值
    - ([]int)：其中的每个元素代表对应 worker 完成任务的数量

mapreduce/master_rpc.go