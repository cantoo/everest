# RESTful接口规范

## 域名
[业务/产品].主域名
如：product1.domain.com

## 头部
| key | value | description |
| --- | --- | --- |
| Authorization | token | 登录态 | 
| Accept-Encoding | deflate, gzip | 指定数据压缩 | 
| x-ts | 1464340571789 | 本地时间的毫秒数 | 
| x-request-id | ab5f8a9e | 8位requestid | 
| x-version | 100 | api版本号 |

[OAuth 2.0 Authorization Header](http://stackoverflow.com/questions/11068892/oauth-2-0-authorization-header)

## 数据格式
**所有请求走https**

* 请求:
	* GET/DELELTE: 参数位于uri中
	* POST/PUT/PATCH: json body
* 回应:
	* ALL: json body

## 返回码
| method         | status code               | |
| -------------: | :-------------------------| :--|
|       POST/PUT | 400 Bad Request           | 数据解析失败 |
|            ALL | 401 Unauthorized          | 登录态过期 |
|            ALL | 403 Forbidden             | 资源未授权 |
|            ALL | 404 NOT FOUND             | 不支持的接口或查询资源时不存在 | 
|            ALL | 405 Method Not Allowed    | 接口未授权 |
|            ALL | 410 GONE                  | 资源已经被删除 | 
|            ALL | 422 Unprocessable Entity  | 参数非法 | 
|            ALL | 423 Locked | 当前用户已经被禁用 |
|            ALL | 429 Too Many Requests     | 超过频率限制 | 
|            ALL | 500 INTERNAL SERVER ERROR | 服务器内部错误 | 
|            GET | 200 OK                    | 成功(POST新建资源成功应返回201) |
|       POST/PUT | 201 CREATED               | 创建成功 |
|         DELETE | 204 NO CONTENT            | 删除数据成功 | 
| 	         GET | 304 Not Changed 		     | 可使用客户端缓存 |

**除200, 201, 204以外的所有状态码, 在需要提示用户或422的情况下, response body会返回错误信息, 格式如下:**
```json
{"error": "您没有权限删除该评论", "errcode": 3811}
```

## 缓存
*  第一次请求资源, 返回200 & Last-Modified
*  第二次请求资源, 发送If-Modified-Since头
	*  若资源未发生变化, 返回304
	*  若资源有变化, 返回200 & Last-Modified

## 频率限制
暂不考虑

## 通用接口参数

参数名 | 请求/回应 | 说明
---|---
start | 请求 | 查询起始位置
num   | 请求 | 查询数量(一页记录数)
total | 回应 | 返回记录总数
list  | 回应 | 资源列表
links | 回应 | hypermedia列表

## hypermedia
hypermedia为接口和资源的附属信息, 用于引导前端进行下一步操作.
所有hypermedia统一放在links数组里面.
每个hypermedia有以下几个属性, rel: 描述, uri: 该link对应的请求地址, method: 请求方法. 例如:

```
查询好友动态
GET /tweets

返回:
{
    "tweets": [
        {
            "links":[
                {"rel": "thumb", "method": "PUT", "uri": "/tweets/TW123456?thumb"},
                {"rel": "detail", "method": "GET", "uri": "/tweets/TW123456"},
            ]
        }
    ],
    "links": [
        {"rel": "next", "method": "GET", "uri": "/tweets?ctime=987654"}
    ]
}
```

### rel规范

|name|desc|when|
|---|---|---|
|detail|详情|查列表, 新增|
|delete|删除|查详情|
|modify|修改|查详情|
|previous|上一页|查列表|
|next|下一页|查列表|

其余不在rel规范里面的, 需要在接口说明里注明.

---
[RESTful资源合集](https://github.com/aisuhua/restful-api-design-references)
