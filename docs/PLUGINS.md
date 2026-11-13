# 制作与使用漫匣插件

漫匣插件 API 1 使用 JSON 描述扩展。主题、阅读预设、静态 HTML 漫画源、导航布局与角色包可以自由组合，安装后即时生效；无需重新编译 APK。

## 使用插件

底栏进入「插件」浏览内置目录，选择插件后查看作者、版本、协议和扩展范围，再安装启用。「已安装」提供启停、插件设置和卸载。右上菜单可导入 JSON 或角色 ZIP 文件、粘贴 JSON，或添加 HTTPS 插件仓库；「生效与覆盖关系」显示每项贡献的来源和覆盖原因。

内置目录可离线使用；「添加 / 刷新在线仓库」会读取指定目录并逐包核对 SHA-256。刷新失败会保留当前目录。作者字段由插件提供；哈希用于校验内容一致性，不表示作者身份认证。

## API 2 脚本漫画源

API 2 可以用 JavaScript 编写漫画源。安装包是单个 JSON 文件，包含清单和脚本。复制 [示例目录](../plugins/examples/script-source/)，修改 `manifest.json` 和 `source.js` 后打包：

```sh
node tools/plugin-sdk.mjs pack-source ./my-source ./my-source.json
node tools/plugin-sdk.mjs validate ./my-source.json
```

清单使用 `apiVersion: 2`，只包含 `contributes.source`，其中 `id` 用于保存作品身份，更新时保持不变。`name` 是显示名称，`baseUrl` 是 HTTPS 基址。`requestHosts` 和 `imageHosts` 分别声明文本请求和图片域名，省略时使用基址域名。每类最多八个精确域名，`requestHosts` 包含基址域名。

`source.js` 是返回接口对象的 JavaScript 表达式。它提供以下同步函数，每次调用收到 `baseUrl` 和 `responses`，以及当前操作的字段：

| 函数 | 参数 | `result` 结构 |
| --- | --- | --- |
| `search` | `query` 搜索词 | 作品数组，每项含 `path`、`title`，可选 `cover`、`author`、`latest` |
| `discover` | 空字符串 `query` | 同搜索，可省略，此时调用 `search` |
| `detail` | `url` 作品地址 | 含 `chapters` 的对象，可选 `description`。章节含 `path`、`title`，可选 `group` |
| `pages` | `url` 章节地址 | 图片地址数组 |

首次调用时 `responses` 为空。需要请求时返回 `{request: '路径或 HTTPS 地址'}`，宿主将响应正文追加到 `responses`，在新的隔离环境中再次调用该函数。完成时返回 `{result: 数据}`。用 `responses.length` 区分步骤。作品与章节路径解析到基址同一来源，图片地址使用 `imageHosts`。

每项操作最多三次 GET。脚本上限 24 KiB，每次文本响应上限 256 KiB，整项操作最多 15 秒；隔离执行输入限制为 1 MiB，堆上限仍为 16 MiB。宿主拒绝重定向和指向局域网、回环或保留网络地址的请求，执行使用支持终止与内存上限的 Android WebView 隔离环境。应用保留 Android 7 安装支持，脚本源要求 Android 8 及以上且 WebView 提供相应能力。Web 版可继续使用 API 1。

内置目录提供「漫画柜」「看漫（公开章节）」和「小辣椒与萝卜头（中文）」三个可选源插件。安装时确认请求与图片域名，再选择默认发现源。漫画柜与看漫支持下滑自动分页；看漫只列出公开章节接口返回的免费内容。《小辣椒与萝卜头》是单部作品的官方中文来源，不能当作综合漫画站。原站验证、地区限制或服务故障会影响访问，不代表整个作品不存在。

可分页脚本在 `source` 中声明 `pagination: true`，`discover` 接收从 1 开始的 `page`，仍返回普通作品数组。宿主在下一页没有新作品时停止，网络错误保留目录并提供重试。非分页插件不受影响；`search` 也会收到 `page: 1`。试跑页可留空检查发现目录，或输入关键词检查搜索，随后验证最早一章的实际首图。

导入插件时先核对域名，再启用。在插件卡片点「试跑脚本源」，以一个关键词检查搜索结果、第一章目录与实际解码的首图。内置「小夏试读源」可用「漫匣试读」验证完整流程。点「设为默认发现源」即可从发现页浏览。更新后可回退上一个已安装版本。恢复备份的脚本源需在插件商城重新确认权限。

API 2 的官方仓库为 `plugins/v2/index.json`。旧版仍使用各自的 API 1 目录。

想独立维护插件时，可以复制 [书源仓库模板](../plugins/examples/source-repository/)。工作流使用 `publish-source` 校验清单、打包插件、生成带 SHA-256 的索引，并在主分支部署到 GitHub Pages。

## 最小主题插件

保存为 `yourname.my-room.json`，在插件页导入：

```json
{
  "apiVersion": 1,
  "id": "yourname.my-room",
  "name": "我的阅读室",
  "version": "1.0.0",
  "author": "Your Name",
  "license": "MIT",
  "description": "纸色背景和可以调整的强调色。",
  "settings": [
    {"key": "accent", "label": "强调色", "type": "color", "default": "#725747"}
  ],
  "contributes": {
    "theme": {
      "seed": {"setting": "accent"},
      "lightSurface": "#F8F2E8",
      "darkSurface": "#211B17"
    }
  }
}
```

`id` 采用 `author.name`，版本为 `x.y.z`。`name`、`author`、`license` 必填；manifest 上限 128 KB。设置支持 `boolean`、`number`、`choice`、`color`；贡献中使用 `{"setting":"key"}` 引用设置。数值需定义 `min` / `max`，选择项需定义 `choices`。配置会校验并保存到本机。

## 扩展接口

| `contributes` 字段 | 支持的参数 | 生效位置 |
| --- | --- | --- |
| `theme` | `seed`、`lightSurface`、`darkSurface`，颜色为 `#RRGGBB` | 应用主题、按钮、导航和页面底色 |
| `reader` | `mode`: `page/strip`；`rtl`、`doublePage`、`tapZones`: 布尔；`background`: `ink/paper/sepia`；`turn`: `slide/paper`；`warmth`: 0–0.8 | 下次打开阅读器的默认偏好 |
| `character` | `states` 中的 `idle`、`blink`、`happy`、`puzzled` 静态 PNG | 书架、空状态与操作反馈；阅读正文隐藏 |
| `source` | 静态源配置，见下面模板 | 发现、搜索、详情、目录和图片解析 |
| `navigation` | 3–6 个不重复入口编号，必须包含 0 和 3 | 手机底部入口及顺序 |

导航编号固定：`0` 书架、`1` 发现、`2` 足迹、`3` 设置、`4` 下载、`5` 插件。用户手动选择的布局优先于插件布局，可在设置中恢复插件 / 默认布局。

阅读偏好的优先级为：基础设置 → 启用的阅读插件 → 个人默认阅读方案 → 逐本设置。同类主题 / 阅读预设 / 角色包启用一个时，会停用其他同类插件；不同类别可以组合。停用后恢复原来的基础偏好，不覆盖书籍和逐本设置。卸载移除该插件及其配置，个人书库保留。

主题需为浅色、深色模式分别选择合适底色，避免文字与背景缺乏对比。

## 漫画源插件

完整模板见 [`plugins/examples/source-template.json`](../plugins/examples/source-template.json)。替换真实站点地址、允许的图片域名及 CSS 选择器后导入，再到「设置 → 默认发现源」选择它。`source.id` 不能是内置保留值 `dm5`、`mangabz`、`dongman` 或 `local`，也不能与手动添加或其他已安装插件的源重复。

解析参数与 [漫画源说明](SOURCES.md) 一致。支持静态 HTML 页面；API 1 不执行站点 JavaScript，不支持第三方脚本运行、任意原生调用或替换阅读器渲染内核。需要新宿主能力时应扩展接口版本，不能在 manifest 中夹带代码来绕过接口。

## 校验和分享

Node.js 22+ 环境下：

```sh
node tools/plugin-sdk.mjs validate yourname.my-room.json
```

校验器检查清单、设置和贡献参数；宿主还会检查 CSS 选择器。编辑器可关联 [`plugins/manifest.schema.json`](../plugins/manifest.schema.json) 获得结构提示。

本仓库的插件源码位于 `plugins/packages/`。增加或修改包后运行：

```sh
node tools/plugin-sdk.mjs build
node --test tools/plugin-sdk.test.mjs
flutter test test/plugin_test.dart
```

构建命令生成新版在线 `plugins/v1.1/index.json` 和内置 `assets/plugins/catalog.json`，同时保留不包含角色包的旧版 `plugins/index.json`，供较早宿主使用。索引中每项包含 `id`、`version`、包的 HTTPS `url` 和原始文件字节的 `sha256`。JSON 统一 LF 换行，避免跨系统改变哈希。

自己的仓库也可使用相同格式，上传 manifest 文件后填写其地址和哈希。索引格式：

```json
{
  "schemaVersion": 1,
  "plugins": [
    {
      "id": "yourname.my-room",
      "version": "1.0.0",
      "url": "https://your-domain.example/plugins/yourname.my-room.json",
      "sha256": "此处替换为 manifest 文件的 64 位小写 SHA-256"
    }
  ]
}
```

当前目录上限 20 个包。升级时保持 `id`，提高版本号并更新哈希；不支持覆盖降级。主题与阅读设置保存在资料备份内，恢复资料时会一并还原；Web 版清理站点数据会清除本地插件状态。

## 宿主生命周期

宿主实现位于 `lib/data/plugin.dart`、`plugin_registry.dart`：安装前验证清单与兼容版本，启用时计算贡献快照，配置后重新校验并更新，停用 / 卸载时撤销贡献。非法或损坏的插件恢复数据不会阻止应用启动。接口版本不兼容会拒绝安装，保留已有书库。


## 角色包

「设置 → 外观与动效 → 小夏与阅读伙伴」提供官方小夏的可选安装、显示开关、大小、眨眼开关和提醒频率。不会自动安装角色。角色关闭后恢复原有空状态图标；正文没有悬浮角色。角色动作由宿主管理，离开界面、进入后台或系统减少动效时停止。

角色 ZIP 根目录包含 `manifest.json` 和最多四张 PNG。图片不超过 512×512、单张 256 KB，不接受 APNG；ZIP 不超过 2 MB。角色图片按 SHA-256 存储，安装前全部校验解码，损坏的替换包不会停用当前角色。最多安装十个角色包，同时启用一个；卸载清理未被其他已安装角色引用的图片。

最小清单：

```json
{
  "apiVersion": 1,
  "id": "yourname.companion",
  "name": "我的伙伴",
  "version": "1.0.0",
  "author": "Your Name",
  "license": "MIT",
  "contributes": {
    "character": {
      "states": {
        "idle": {"file": "idle.png", "sha256": "替换为图片的64位SHA256"}
      }
    }
  }
}
```

`idle` 必填；`blink`、`happy`、`puzzled` 缺省时使用 `idle`。文件名使用小写英文、数字、下划线或连字符，不含路径。准备透明背景、大小和角色落点一致的图片，避免切换表情时跳位。此接口只接收静态图片，不运行脚本、模型或下载代码。

把清单和图片放进同一目录后打包：

```sh
node tools/plugin-sdk.mjs pack-character ./my-companion ./my-companion.zip
```

命令会在输出 ZIP 的清单内计算并写入 SHA-256；不会覆盖已有输出，也不会改写原清单。导入 ZIP 后即可启用。官方示例见 `plugins/packages/xiaxia.json` 和同目录 ZIP。

角色图片单独导出：角色设置中选择「导出角色 ZIP」。书库 JSON 备份只保留插件清单与配置，不包含自制角色图片；恢复后重新导入原 ZIP。缺失素材只显示书本占位，不影响启动和书库。

可选 `locales` 字段支持 `en`、`zh_TW` 下的 `name` 与 `description`。作者自行提供译文，宿主不会改写用户输入的插件名、作品名或阅读方案名。

## 个人阅读方案与设置来源

在阅读设置里保存当前布局、背景、亮度、暖色、翻页与点击习惯，并可选择只用于当前漫画或设为默认。预览在实际页面显示，取消不写入设置，应用后可撤销；设备亮屏、音量键和智能离线队列不随视觉方案切换。

插件页右上角的「生效与覆盖关系」按字段显示提供者，说明背景取色、个人导航或默认阅读方案造成的覆盖，并列出因启用同类插件而停用的条目。漫画源插件安装后只是可选来源，仍需在漫画源设置中选择。
