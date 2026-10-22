# 制作与使用漫匣插件

漫匣插件 API 1 使用 JSON 描述扩展。主题、阅读预设、静态 HTML 漫画源和导航布局可以自由组合，安装后即时生效；无需重新编译 APK。

## 使用插件

底栏进入「插件」浏览内置目录，选择插件后查看作者、版本、协议和扩展范围，再安装启用。「已安装」提供启停、插件设置和卸载。右上菜单可导入 JSON 文件、粘贴 JSON，或添加 HTTPS 插件仓库。

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
| `source` | 静态源配置，见下面模板 | 发现、搜索、详情、目录和图片解析 |
| `navigation` | 3–6 个不重复入口编号，必须包含 0 和 3 | 手机底部入口及顺序 |

导航编号固定：`0` 书架、`1` 发现、`2` 足迹、`3` 设置、`4` 下载、`5` 插件。用户手动选择的布局优先于插件布局，可在设置中恢复插件 / 默认布局。

阅读偏好的优先级为：应用基础偏好 → 全局阅读默认值 → 启用的阅读插件 → 逐本设置。同类主题 / 阅读预设启用一个时，会停用其他同类插件；不同类别可以组合。停用后恢复原来的基础偏好，不覆盖书籍和逐本设置。卸载移除该插件及其配置，个人书库保留。

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

构建命令生成在线 `plugins/index.json` 和内置 `assets/plugins/catalog.json`。索引中每项包含 `id`、`version`、包的 HTTPS `url` 和原始文件字节的 `sha256`。JSON 统一 LF 换行，避免跨系统改变哈希。

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
