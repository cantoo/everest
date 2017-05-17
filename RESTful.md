# 当我们在讨论RESTful时，我们在讨论什么

[TOC]

RESTful是目前流行的API接口形式，无论哪个搜索引擎都会告诉你，RESTful是什么，长什么样子，但在工程实践方面，涉及的资料较少。本文是实际项目中提炼的经验总结，从实践层面告诉你RESTful应该怎么做，会涉及哪些问题。作者参与的项目和阅读的资料有限，观点不免狭隘，还请各位多多包涵，若能引起大家讨论，也是好事。本文讨论的RESTful，均是指RESTful HTTP。

为了便于论述，本文全篇使用一个类微博功能背景：用户可以关注其他用户，关注后可以看到关注人的动态数据流; 可以对关注人的动态点赞; 可以自己发表动态; 可以去其他用户的个人主页查看其发表的所有动态。

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
PUT /tweets/{tweetid}/thumb
```

### RESTful接口级别
如果你的接口在请求部分做到了上述的接口形式，那你的接口已经达到了Martin Fowler在文章[《steps toward the glory of REST》](https://martinfowler.com/articles/richardsonMaturityModel.html)中定义的level 2。最高level是level 3，level 3比level 2多了hybermedia信息，hybermedia是指接口的返回中携带了资源下一步操作的接口信息，如查询好友动态列表接口，返回的每个动态对象中都有属性指定查详情和点赞使用什么接口，并且返回了查询下一页动态应该使用什么接口：
```
GET /tweets

{
    "tweets"[{
        "text": "RESTful大法好",
        "links": [{
            "ref": "detail",
            "method": "GET",
            "uri": "/tweets/123456"
        }]
    }, {
        "text": "hybermedia大法好",
        "links": [{
            "ref": "detail",
            "method": "GET",
            "uri": "/tweets/456789"
        },{
            "ref": "thumb",
            "method": "PUT",
            "uri": "/tweets/456789/thumb"
        }]
    }],
    "links": [{
        "ref": "next",
        "method": "GET",
        "uri": "/tweets?ctime=1495008478"
    }]
}
```

hybermedia信息可以是接口层面的，也可以是每个数据对象层面的。一般做法是把所有hybermedia放在一个`links`数组中，数组每个元素有`rel`和`uri`属性，`rel`指定操作类型，`uri`指定接口。有了hybermedia，你的RESTful接口可以形成接口协议地图，如本文讨论的类微博功能的部分协议地图如下：
```
    +--下一页--+     +-----> 点赞
    |          |     |
    |          V     |
    +-------查看好友动态 --> 查看动态详情 -> 删除动态
                               ^
                               |
            发表动态 ----------+
```
画出协议地图后你会发现，协议地图还原了需求，再现了业务场景。相信你把协议地图拿给产品经理看，她们会说：“嗯，是这样的”。如果你手上的协议地图太复杂了，你也可以拿给产品经理看，然后说：“你看，你这个业务定得太复杂了，上面各种交叉，我都画不下了:)”。
然而协议地图是使用hybermedia结果，不是原因，我认为使用hybermedia的主要原因或优势是：

1. 前端只需要理解协议地图的根节点和`ref`。
    * 相比理解所有的接口，有了hybermedia后，前端只用理解少量接口和`ref`，而有些`ref`是通用的，如所有列表接口的下一页`ref`都是`next`，因此ref是比接口数量少的，可以减少前端理解接口的成本。
    * `ref`还可以帮助前端完成一些展示上的逻辑，如列表查询，如果没有找到`next`，则列表的最下方可以做没有更多数据的展示；如果没有找到`thumb`，则说明已经点过赞了，点赞按钮需展示成已点赞的样式。

2. 后台对排序，接口升级等方面的控制能力前所未有的强。
    * 示例1：好友动态列表，是按时间线排序的，由于RESTful是无状态的，所以一般查下页数据的时间需要前端把最后一个动态的时间带上来。有了hybermedia后，首先前端不用再写找到最后一个动态，取发表时间属性，再拼到请求里面的逻辑，直接发送`next`指定的请求即可；另外，如果产品经理想在动态流里面加入广告和推荐，那动态列表就包含了2条数据流了，这2条数据流各有各的排序方式，这种情况下，后台直接在`next`中加入广告和推荐数据流的排序参数即可。整个过程对前端透明，前端代码不用做任何改动，不需要发布新版本。
    * 示例2：比方说产品经理定义了一些点赞的连锁反应，如加入关注的动态列表，该动态有新评论时可以收到通知。但你发现改现有的点赞逻辑代码比较戳，已经无从下手，所以你决定新写一个点赞接口`thumb2`，通常情况下你需要跟前端同事说：“这次你们发版本把点赞接口换成`thumb2`吧”，但有了hybermedia后，你可以直接将列表接口返回的`thumb`替换为新的`thumb2`接口。这个过程同样对前端透明。

强烈建议使用hybermedia，定义REST的作者Roy Thomas Fielding也撰文表示[REST APIs must be hypertext-driven](http://roy.gbiv.com/untangled/2008/rest-apis-must-be-hypertext-driven)。

### RESTful接口规范





## 工程目录



## 架构



