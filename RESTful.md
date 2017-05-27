# 当我们在讨论RESTful时，我们在讨论什么

[TOC]

RESTful是目前流行的API接口形式，无论哪个搜索引擎都会告诉你，RESTful是什么，长什么样子，但在工程实践方面，涉及的资料较少。本文是实际项目中提炼的经验总结，从实践层面告诉你RESTful应该怎么做，会涉及哪些问题。作者参与的项目和阅读的资料有限，观点不免狭隘，还请各位多多包涵，若能引起大家讨论，也是好事。本文讨论的RESTful，均是指RESTful HTTP。

为了便于论述，本文全篇使用一个类微博功能背景：用户可以与其他用户成为好友，成为好友后可以看到好友的动态数据流; 可以对好友的动态点赞; 可以自己发表动态; 可以去其他用户的个人主页查看其发表的所有动态。


## RESTful是什么
通俗点说，RESTful是按"资源/资源id"组织url，用HTTP方法定义资源操作的一种接口形式。如本文讨论的类微博功能，后台提供的部分RESTful接口如下：

* 查询好友动态
```
    GET /tweets
```

* 查询某个动态的详情
```
    GET /tweets/{tweetid}
```

* 发表一个动态
```
    POST /tweets
    {
        "text"："RESTful大法好"
    }
```

* 删除我的动态
```
    DELETE /tweets/{tweetid}
```

* 查询某个人的动态
```
    GET /users/{userid}/tweets
```

* 点赞
```
    POST /tweets/{tweetid}/thumb
```

如果你的接口在请求部分做到了上述的接口形式，那你的接口已经达到了Martin Fowler在文章[《steps toward the glory of REST》](https://martinfowler.com/articles/richardsonMaturityModel.html)中定义的level 2。然而最高level是level 3，level 3比level 2多了hypermedia信息，hypermedia是指接口的返回中携带了资源下一步操作的接口信息，如查询好友动态列表接口，返回的每个动态对象中都有属性指定查详情和点赞使用什么接口，并且返回了查询下一页动态应该使用什么接口：
```
    GET /tweets
    
    {
        "tweets"[{
            "user": { "name": "tom", "uid": "abc" },
            "text": "RESTful大法好",
            "links": [{ "rel": "detail", "method": "GET", "uri": "/tweets/123456"}]
        }, {
            "user": { "name": "lily", "uid": "xyz" },
            "text": "hypermedia大法好",
            "links": [{"rel": "detail", "method": "GET", "uri": "/tweets/456789"},
                {"rel": "thumb", "method": "POST", "uri": "/tweets/456789/thumb"}]
        }],
        "links": [{"rel": "next", "method": "GET", "uri": "/tweets?ctime=1495008478"}]
    }
```

hypermedia信息可以是接口层面的，也可以是每个数据对象层面的。一般做法是把所有hypermedia放在一个`links`数组中，数组每个元素有`rel`和`uri`属性，`rel`指定操作类型，`uri`指定接口。有了hypermedia，你的RESTful接口可以形成接口协议地图，如本文讨论的类微博功能的部分协议地图如下：
```
    +--下一页--+     +-----> 点赞
    |          |     |
    |          V     |
    +-------查看好友动态 --> 查看动态详情 -> 删除动态
                               ^
                               |
            发表动态 ----------+
```
画出协议地图后你会发现，协议地图还原了需求，再现了业务场景。相信你把协议地图拿给产品经理看，她们会说：“嗯，是这样的”。如果你手上的协议地图太复杂了，你也可以拿给产品经理看，然后说：“你看，你这个业务定得太复杂了，上面各种交叉，我都画不下了” :)。
然而协议地图是使用hypermedia结果，不是原因，我认为使用hypermedia的主要原因或优势是：

1. **前端只需要理解协议地图的根节点和`rel`**。
    * 相比理解所有的接口，**有了hypermedia后，前端只用理解少量接口和`rel`**，而有些`rel`是通用的，如所有列表接口的下一页`rel`都是`next`，因此rel是比接口数量少的，可以减少前端理解接口的成本。
    * **`rel`还可以帮助前端完成一些展示上的逻辑**，如列表查询，如果没有找到`next`，则列表的最下方可以做没有更多数据的展示；如果没有找到`thumb`，则说明已经点过赞了，点赞按钮需展示成已点赞的样式。

2. **后台对排序，接口参数调用，接口替换等方面的控制能力前所未有的强**。
    * 示例1：好友动态列表，是按时间线排序的，由于RESTful是无状态的，所以一般查下页数据的时间需要前端把最后一个动态的时间带上来。**有了hypermedia后，首先前端不用再写找到最后一个动态，取发表时间属性，再拼到请求里面的逻辑，直接发送`next`指定的请求即可**；另外，如果产品经理想在动态流里面加入推荐的动态，那动态列表就包含了2条数据流了，这2条数据流各有各的排序方式，这种情况下，**后台直接在`next`中加入推荐数据流的排序参数即可。整个过程对前端透明，前端代码不用做任何改动，不需要发布新版本**。
    * 示例2：比方说产品经理定义了一些点赞的连锁反应，如加入关注的动态列表，该动态有新评论时可以收到通知。但你发现改现有的点赞逻辑代码比较困难，所以你决定新写一个点赞接口`thumb2`，通常情况下你需要跟前端同事说：“这次你们发版本把点赞接口换成`thumb2`吧”，**但有了hypermedia后，你可以直接将列表接口返回的`thumb`替换为新的`thumb2`接口。这个过程同样对前端透明**。

强烈建议使用hypermedia，定义REST的作者Roy Thomas Fielding也撰文表示[REST APIs must be hypertext-driven](http://roy.gbiv.com/untangled/2008/rest-apis-must-be-hypertext-driven)。

## 工程目录
在PC web时代，我们组织目录的方式和url相关，如个人中心的url是`home/index.php`。这种做法的好处是，看到url就可以很快的反应出代码在哪里。同样，RESTful的工程目录结构也最好使用跟url相关的目录结构，不同的是RESTful的工程目录结构要跳过url中的资源id部分，而且文件名最好跟HTTP方法相关，如：

* 纵深结构，按多级资源组织文件

|接口|url|文件目录|
|-----|-----|-----|
|查询好友动态|`GET /tweets`|`/your/root/tweets/get.cgi`|
|查询某人的动态|`GET /users/{uid}/tweets`|`/your/root/users/tweets/get.cgi`|

* 扁平结构，所有文件放在一级资源下

|接口|url|文件目录|
|-----|-----|-----|
|查询好友动态|`GET /tweets`|`/your/root/tweets/get_tweets.cgi`|
|查询某人的动态|`GET /users/{uid}/tweets`|`/your/root/users/get_users_tweets.cgi`|

纵深结构比扁平结构目录层次更清晰，避免了一个目录下有大量的文件；扁平结构比纵深结构调试起来更方便，重名文件少，文件名本身的语义更清晰。


## RESTful接口规范
网上的RESTful规范有很多，比较靠谱的有：

* [Best Practices for Designing a Pragmatic RESTful API](http://www.vinaysahni.com/best-practices-for-a-pragmatic-restful-api)
* [Principles of good RESTful API Design](https://codeplanet.io/principles-good-restful-api-design/)

比较规范的示例有：

* [Coinbase](https://developers.coinbase.com/api/v2)
* [Enchant REST API](http://dev.enchant.com/api/v1)

Github上牛人整理的RESTful资料合集:

* [restful-api-design-references](https://github.com/aisuhua/restful-api-design-references)

RESTful规范像代码规范一样，若要分出个好坏来，那非得打起来不可，所以只要整个项目风格统一，所有人都遵守就可以了。

从我们项目实践的经验和教训看，我们有如下的建议：

1. **API版本信息放在url的域名部分**。
    首先排除放在头部，放在头部不直观。那放在url里面有两种形式：`apiv1.domain.com`，`domain.com/api/v1`，或这两种形式的变种，后者的问题是对hypermedia有影响，是后台在返回每个hypermedia前面都加上`/api/v1`，还是前端请求时加上，为了避免这些麻烦，还是将版本信息放在url的域名部分。

2. **不要吝啬建立新的资源，尽量使用phony resource来明确语义**。
    如前面提到的点赞接口：`POST /tweets/{tweetid}/thumb`，thumb就不是一个逻辑上的资源实体，是一个phony resource。使用thumb这样一个phony resource后，使得接口非常好理解，点赞就是在某个动态下新增一个点赞数据。如果不使用phony resource，则点赞接口可能是：`PUT /tweets/{tweetid}?thumb`，这样点赞代码不得不和其他涉及动态数据修改的代码揉在一起。
    另外一个例子，如果有一个新的需求是查询身边的热门动态，可以定义另外一个phony resource：`GET /nearby_tweets`，在扁平的目录结构下这个接口的文件名是：`get_nearby_tweets.cgi`，文件名和接口同样语义明确。

3. **不必强制要求GET不带body, PUT不带参数**。
    在后面讨论架构时，会发现有这样的情况，需要把一个服务查得的大量数据交给另外一个服务处理，这时如果把这些数据全放到url里面，则会导致url超长。
    PUT方法用于修改数据，现实中会有这样的情况：有的接口只改数据的某些字段，有的接口改数据的另外一些字段。这时不得不用参数来区分。

4. **不要让前端传参数来实现条件过滤，字段过滤和排序**。
    外国友人的文章里提到，条件过滤、字段过滤、排序都可以放到请求参数里面。然而，RESTful讲究的是后台的控制力，将这些事情交给前端等于倒退。这些细节都应该后台处理，或者隐藏在hypermedia中，前端只专注于数据展示。


## 架构
RESTful的核心思想是将数据划分为一个个资源，这和微服务架构的思想是一致的。Chris Richardson的7篇介绍微服务系列雄文[《Microservices: From Design to Deployment》](https://www.nginx.com/blog/introduction-to-microservices/)中就推荐使用RESTful作为接口形式。本文讨论的需求背景，后台的微服务架构为：
```
    +--------+        +-------------+
    |        |<------>|    users    |
    |        |        +-------------+
    |        |                       
    |        |                       
    |   API  |        +-------------+
    |        |<------>|    rela     |
    | Gateway|        +-------------+
    |        |                       
    |        |                       
    |        |        +-------------+
    |        |<------>|    tweets   |
    +--------+        +-------------+
```
这里我们定义了3个微服务，`user`服务负责维护用户的个人信息；`rela`负责维护关系链数据；`tweet`负责维护动态数据。Chris Richardson在文章[Building Microservices: Using an API Gateway](https://www.nginx.com/blog/building-microservices-using-an-api-gateway/)中描述的`API Gateway`的职责是：

* 为前端提供统一入口，路由请求
* 协议转换
* 数据整合

上面列出的职责中最重要的是数据整合。数据整合的意思是`API Gateway`应该整合后端多个服务的数据一并返回给前端，以减少客户端调用次数，如查询好友动态接口，不仅要返回动态的数据，还需要返回动态发表人的数据，这两块数据分别由`users`服务和`tweets`服务维护。

### 进程间通讯
微服务讲究各服务的独立性，但有一些场景确实是需要其他服务的数据，如：

1. 查询好友动态时，`tweets`服务如何知道用户的好友列表？
2. 如果产品经理要求在任何展示用户头像的地方，展示用户收到的点赞总数，这样把点赞总数统计放到`users`服务是比较合理的。那在用户的动态收到新的点赞时，如何通知`users`服务更新点赞总数?

首先要肯定的是微服务之间不要直接互相调用，否则你的服务将变成一张蜘蛛网。Chris Richardson在文章[Building Microservices: Inter-Process Communication in a Microservices Architecture](https://www.nginx.com/blog/building-microservices-inter-process-communication/)里建议微服务之间使用消息队列来通讯，这种做法比较重。建议的方式是全部由`API Gateway`来协调。

如查询好友动态，由`API Gateway`先向`rela`服务查询好友，然后把全部好友告诉`tweets`服务（此时就不能要求GET方法不带body），`tweets`服务返回全部好友的动态数据。再如更新点赞数，`API Gateway`在调用`tweets`服务点赞成功后，再调用`users`服务更新点赞数。也就是说，`API Gateway`除了负责数据的整合输出，还负责多个服务间的数据协调。

然而全部由`API Gateway`来协调，引出的另外一个问题：多个服务间的数据一致性如何保证？这个问题可以从下面3个方面考虑：

1. 是不是不一致也没有关系?
2. 使用修复机制，如调用`users`服务更新点赞数时，每次都是全量设置，而不是增量设置，这样一来就算数据暂时不一致，也可以由用户后续的操作修复。
3. 要求强一致的场景，应该将数据放到同一个服务里管理。


### 微服务和目录结构
同一个数据模型下，微服务的划分和RESTful中资源的划分是一致的，但需要注意的是**服务的划分和目录结构没有强制的对应关系**，如`tweets`服务不只有`tweets`目录，查询某个人的动态接口`GET /users/{uid}/tweets`的代码就放在`users`目录下。
另外还有一个微服务管理多个资源的情况，如可以把所有的UGC放到`ugc`服务里面管理，`ugc`服务不仅管理`tweets`数据，还管理`comments`等数据。


### 单体 & 微服务
Chris Richardson在文章[《Introduction to Microservices》](https://www.nginx.com/blog/introduction-to-microservices/)中提到几项微服务相对单体架构的缺点：

1. 相比单体架构内部的函数调用，微服务的RPC调用更复杂。
2. 微服务架构包含大量的微服务，部署没有单体架构方便。

针对上面的问题，我们项目的做法是：

1. **逻辑上保持微服务结构，物理上所有微服务运行在一个进程**，随着业务量的上升再逐步的剥离一些微服务为单独的进程。
2. **将远程的微服务本地化，使上层的业务代码不关心服务是在本地还是远程**，这样保证在剥离微服务的过程中，业务代码不用做任何改动。

我们使用OpenResty开源框架，具体的实现细节是：
```
    http {
        upstream micro_svr {
            server 127.0.0.1:8081;
        }

        server {
            listen 8080; 

            location /main {
                content_by_lua_block {
                    local res = ngx.location.capture("/sub")
                    ngx.say(res.body)
                }
            }

            location /sub {
                internal;
                proxy_pass http://micro_svr;
                break;
            }
        }

        server {
            listen 8081;

            location /sub {
                echo "hello RESTful";
            }
        }
    }
```

即有个监听8081端口的微服务，这个服务可以用internal location + proxy pass + upstream来映射到`API Gateway`内部，无论该微服务是否在一个逻辑进程内，业务代码处都是使用subrequest来调用这个服务。如果随着业务的发展，需要将8081微服务剥离了，只用改upstream里面server的IP配置即可。

暂时将微服务和`API Gateway`放到一个物理进程内，可以让我们在业务初期免于考虑`API Gateway`到微服务的容灾和负载均衡，同时你的服务也可以做到镜像部署，良好的容器亲和性，业务逻辑服务器之间不用关心彼此的存在，没有网络调用。


### 监控
RESTful监控和普通Web服务的监控并无二致。我们项目使用ELK来搜集nginx的access log，并基于log实现业务监控。除了日志查询、异常监控，ELK还有丰富的数据展示能力。推荐大家使用。


## 结语
终上所述，我们在讨论RESTful时，不只是在讨论一个接口形式，而是在讨论如何使接口语义更清楚，后台的控制力更强，工程目录结构更清晰，架构更优化等等问题。当我们把这些问题都搞清楚时，会发现RESTful带给我们超过其本意的好处。



