# 当我们在讨论RESTful时，我们在讨论什么

RESTful是目前流行的API接口形式，无论哪个搜索引擎都会告诉你，RESTful是什么，长什么样子，但在工程实践方面，涉及的资料较少。本文是实际项目中提炼的经验总结，从实践层面告诉你RESTful应该怎么做，会涉及哪些问题。作者参与的项目和阅读的资料有限，观点不免狭隘，还请各位多多包涵，若能引起大家讨论，也是好事。本文讨论的RESTful，均是指RESTful HTTP。

为了便于论述，本文全篇使用一个类微博功能背景：用户可以关注其他用户，关注后可以看到关注人的动态数据流; 可以对关注人的动态点赞; 可以发表自己动态; 可以去其他用户的个人主页查看其发表的所有动态。

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

### RESTful接口级别
如果你的接口在请求部分做到了上述的接口形式，那你的接口已经达到了Martin Fowler在文章[《steps toward the glory of REST》](https://martinfowler.com/articles/richardsonMaturityModel.html)中定义的level 2。最高level是level 3，level 3比level 2多了hybermedia信息，hybermedia是指接口的返回中携带了资源下一步操作的接口信息，如查询好友动态列表接口，返回的每个动态对象中都有属性指定查详情使用什么接口，并且返回了查询下一页动态应该使用什么接口：
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
        "uri": "/tweets?ctime=1495008478"
    }]
}
```

hybermedia信息可以是接口层面的，也可以是每个数据对象层面的。一般做法是把所有hybermedia放在一个links数组中，数组每个元素有rel和uri属性，rel指定操作类型，uri指定接口。有了hybermedia，你的RESTful接口可以形成接口协议地图，如本文讨论的类微博功能的部分协议地图如下：
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

1. 前端只需要理解协议地图的根节点和ref。
    * 相比理解所有的接口，有了hybermedia后，前端只用理解少量接口和ref，而有些ref是通用的，如所有列表接口的下一页ref都是`next`，因此ref是比接口数量少的，可以减少前端理解接口的成本。
    * ref还可以帮助前端完成一些展示上的逻辑，如列表查询，如果没有找到`next`的ref，则列表的最下方可以做没有更多数据的展示；如果没有找到点赞的ref，则说明已经点过赞了，点赞按钮需展示成已点赞的样式。

2. 后台的控制能力前所未有的强。
    * 示例1，



### RESTful接口规范












接口形式
规范
工程目录
架构



