# 自定义漫画源

默认动漫屋适配器读取公开 HTML 和内嵌图片列表。添加源使用静态 CSS 选择器，不执行远程脚本、不携带账号 Cookie，不绕过验证码或付费限制。

在设置中添加下列格式，替换成自己的真实站点和选择器：

```json
{
  "id": "my_comics",
  "name": "我的漫画源",
  "baseUrl": "https://example.com",
  "home": "/",
  "search": "/search?q={query}",
  "cards": ".comic",
  "title": ".title",
  "link": "a",
  "cover": "img",
  "coverAttribute": "data-src",
  "author": ".author",
  "latest": ".latest",
  "description": ".description",
  "chapters": ".chapters a",
  "pages": ".reader img",
  "pageAttribute": "src",
  "imageHosts": ["example.com", "cdn.example.com"],
  "reverseChapters": false
}
```

这是结构示例，example.com 不是漫画源。`cards` 选每张卡片的容器；title/link/cover/author/latest 在容器内查找。章节适配器输出按最新在前的顺序供详情界面处理；网页相反时设置 reverseChapters。pages 按阅读顺序选图片。

页面必须在 baseUrl 相同 origin，图片为明确列出的 HTTPS 域名。浏览器通过本机预览代理注册来源，原生端直连并按来源发送 Referer。只有实际抓取到结果才代表适配可用。登录、JavaScript 解密和特殊 API 需另外编写适配器，声明式配置不会假装支持。

保存后切换默认发现源，再用“检查当前源”依次验证首页、首本目录和首章图片列表。配置进入资料备份，不在其中放密码、Cookie 或 token。

## 目录不可用时

动漫屋手机入口只有外部搜索时，漫匣会再检查同作品的公开桌面目录。原站明确显示移除、迁移或访问验证时会保留实际提示；公开索引里仍有章节名称，不代表当前请求可以读取。

详情的“换源查找”使用其他已配置或已启用的书源，带入漫画名，也可以改用别名。确认搜索结果后打开对应版本，不自动替换原收藏或挪用原阅读页码，也不改变默认发现源。没有其他来源时可直接进入书源设置；网站需要特殊API或远程脚本时，当前声明式配置不适用。
