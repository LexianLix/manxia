# 制作与使用漫匣插件

漫匣插件 API 1 使用 JSON 描述扩展。主题、阅读预设、静态 HTML 漫画源、导航布局与角色包可以自由组合，安装后即时生效；无需重新编译 APK。

## 使用插件

底栏进入「插件」浏览内置目录，选择插件后查看作者、版本、协议和扩展范围，再安装启用。「已安装」提供启停、插件设置和卸载。右上菜单可导入 JSON 或角色 ZIP 文件、粘贴 JSON，或添加 HTTPS 插件仓库；「生效与覆盖关系」显示每项贡献的来源和覆盖原因。

内置目录可离线使用；「添加 / 刷新在线仓库」会读取指定目录并逐包核对 SHA-256。刷新失败会保留当前目录。作者字段由插件提供；哈希用于校验内容一致性，不表示作者身份认证。

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

完整模板见 [`plugins/examples/source-template.json`](../plugins/examples/source-template.json)。替换真实站点地址、允许的图片域名及 CSS 选择器后导入，再到「设置 → 默认发现源」选择它。`source.id` 不能是 `dm5` 或 `local`，也不能与手动添加或其他已安装插件的源重复。

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
