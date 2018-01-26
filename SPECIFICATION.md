# RESTful接口规范

## 前缀&文档
http://campusx.qq.com/api/{version}

## 头部
| key | value | description |
| --- | --- | --- |
| x-user | 475698713 | 平台用户id(目前就是指第三方平台openid) |
| x-client| platform=android/ios/h5,version=20401,device=fsd3157,channel=10003,model=meizu | 客户端平台,版本,device,android渠道号,机型 | 
| x-3rd-qq | appid=1000067 | QQ第三方平台信息 | 
| x-3rd-weixin | appid=1000067 | 微信第三方平台信息 | 
| Authorization | Bearer access_token | 登录态, Bearer表示后面是第三方平台的access token | 
| x-qcloud-im | appid=1000067  | 腾讯云IM的appid | 
| Accept-Encoding | deflate, gzip | 指定数据压缩 | 
| x-ts | 1464340571789 | 本地时间的毫秒数 | 

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
| POST/PUT/PATCH | 400 Bad Request           | 数据解析失败 |
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
| POST/PUT/PATCH | 201 CREATED               | 创建成功 |
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


## 特定场景
### 1. 分页查询

参数名 | 说明
---|---
start | 查询起始位置
num | 查询数量(一页记录数)
total | 返回记录总数
lat | 纬度
lng | 经度

## hybermedia
hybermedia为接口和资源的附属信息, 用于引导前端进行下一步操作.
所有hybermedia统一放在links数组里面.
每个hybermedia有以下几个属性, rel: 描述, uri: 该link对应的请求地址, method: 请求方法. 例如:

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
