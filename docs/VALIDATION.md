# 验收记录 · 2026-10-20 · 0.2 开发版

## 0.2.2 性能复核

提交 f1de1b0：静态分析无问题，33 项 Flutter 测试通过；新增绘制底图缓存、32 像素取色缓存、返回书架保留场景，以及高级设置按需加载的回归检查。本地 Web release 构建成功，浏览器无控制台错误。

固定场景的浏览器主线程帧工作 P95 从 17.299 ms 降至 12.204 ms；首次设置页仍有一次 59.560 ms 长帧。已访问页面后重复操作的 P95 为 10.780 ms，最大 26.107 ms，通过本机检查。完整条件与保留的失败结果见 [性能说明](PERFORMANCE.md)。这些不是 Android/GPU FPS 结论。

本轮 [Actions 运行](https://github.com/LexianLix/manxia/actions/runs/39435016723) 全部通过：静态分析、33 项 Flutter 测试、6 项网关测试、Web 与 Profile/AOT Android 构建。安装包已下载至本机 artifacts/android-0.2.2/app-profile.apk，大小 95589904 字节，已逐文件摘要确认与构建 ZIP 中的 APK 一致；包含 arm64-v8a、armeabi-v7a、x86_64 的 libapp.so，不含 Debug 的 kernel_blob.bin。SHA-256 为 aa9ac0dd5b68660334e9cf9325c92c455e8c10a94d59ba6658676a3a6ab51e8c。真机帧率、触感与具体设备表现仍需实机确认。

实际比较 APK Signing Block 中的证书，新测试包与本机保存的 0.2.1 调试包签名不同。换装前需先导出完整书库并妥善保存；本轮没有执行卸载或删除用户书库。迁移步骤见发布指南。

## 0.2.1 玻璃与动效复核

代码提交 df08122：静态分析无问题，30 项 Flutter 测试通过；新增底栏拖动释放/取消、减少动画/安全区、开书详情初始化次数的检查。Web release 已重新编译。

390 × 844 的真实浏览器中检查了悬浮毛玻璃底栏，封面内容在底栏后方可见并被模糊；实际拖动导航由发现页返回书架、点书打开详情并返回，控制台无错误。使用浏览器逐帧录制了导航切换和直接点书开封面，两段分别保存在本机 artifacts/frosted-navigation-motion.gif 与 book-opening-motion.gif。这些是实际运行记录，不是设计稿。

本轮 [df08122 Actions](https://github.com/LexianLix/manxia/actions/runs/39429969493) 全部通过：30 项 Flutter 测试、6 项网关测试、静态分析、Web 和 Android 调试 APK。0.2.1 安装包已下载至 artifacts/android-0.2.1/app-debug.apk，并确认与构建 ZIP 中的 APK 完全一致；大小 177123843 字节，SHA-256 为 d26955b3bacba5bf152b9c7a73ccf323004b98e9e0abc43890d6681301d0c2ff。夜间模式底栏已在浏览器检查并恢复原来的浅色设置。原生动效与折射的真机边界仍见下文。

## 当前本地结果

- Flutter 3.47.7 / Dart 3.13.5，静态分析无问题。
- 26 项 Flutter 测试通过：来源解析/解码、分类组合链接、日期推荐、备份合并与删除标记、完整图片备份校验、ZIP 自然排序/CBZ 导出、下载失败续传、乱序下载后的离线目录顺序、WebDAV ETag 与二进制书库传输、长图内位置恢复、裁白边、分页记录、双页末尾导航及从右页恢复、390/754/1440 布局及英文 150% 字号。
- 6 项 Node 网关测试通过：限制/拒绝/去重缓存、声明式来源注册、分类分页参数、WebDAV 二进制流传输及条件写入。
- Web release 编译成功，PDF.js 已本地打包；独立离线 app shell 生成。曾发现默认 Flutter worker 与自定义 worker 互相替换引发重载，现改用单一 worker，浏览器切页恢复稳定。
- 签名脚本在本机生成 RSA-3072/SHA256withRSA 密钥，确认 .private/manxia-release.jks 与 android/key.properties 被忽略。没有将其提交或上传到 GitHub。

## 真实动漫屋样本

最近一次 tool/probe.dart：80 本首页、26 类、分类第一页 10 本/下一页 10 本、三种排序及三种状态、搜索 22 项、《冰之城壁》119 个目录条目、第 1 话 15 张图片。首图 HTTP 200 / image/jpeg / 133848 字节。

这只证明当前样本。站点曾阶段性超时；缓存目录会标明日期，不把快照显示当作在线刷新成功。

## 浏览器

- 实际渲染立体书架、每日推荐、四榜与题材/状态筛选；手机 390 × 844 与桌面 1280 × 720 均已查看。
- 通过真实文件选择器导入自制三页 CBZ，显示页码 1/3，翻到 2/3 并实际显示第二、三页。
- 导入自制两页 PDF，PDF.js 在本地转图成功并显示 1/2 及页面文字。
- 仅对 QA 页模拟断网，刷新后应用仍启动、导入书架/封面/阅读记录恢复，继续阅读实际显示本地 PDF；测试后恢复网络。
- 双页的中缝过宽问题已在视觉检查中发现并修正为靠中线排布。
- 截图保存在 artifacts/mobile-discovery-0.2.png、pdf-import-reader.png、offline-reload-reader.png 等本机文件，不提交漫画图片。

## Android 与真实服务

最终代码提交 b51bacd 已通过 GitHub Actions 的静态分析、26 项 Flutter 测试、6 项网关测试、Web 和 Android 调试 APK 构建：[完整运行记录](https://github.com/LexianLix/manxia/actions/runs/39387721366)。调试包已下载至本机 artifacts/android-0.2/app-debug.apk，并逐字节确认与该次构建的 ZIP 内 APK 一致；同目录 build-info.json 记录提交、运行编号、大小及 SHA-256。

尚无连接的 Android 真机；折射后端、传感器、音量键、触感、常亮、旋转、实际性能、签名覆盖升级均未验收。WebDAV 尚无实际服务账号，已通过模拟协议与图片字节往返测试，不能据此宣称兼容具体网盘。

品牌补充：Android 普通/自适应图标与 Web 图标统一为深绿“匣”字标，源自项目内 OFL 字体；生成脚本位于 tools/generate-icons.py。

纸页检查：浏览器中开启纸页弯曲后，实际从 2/3 翻至 3/3，下一页正确禁用，控制台无渲染错误。

离线目录检查：保存原站完整章节顺序；用户先下载旧章、再下载新章，重启后仍按原站顺序展示。书库 ZIP 同时携带目录，未来不支持的资料版本在写入图片前拒绝。

双页最终检查：在桌面宽度恢复到第三页时，实际显示相邻的第二、三页，页码为 2–3 / 3，下一页禁用，控制台无渲染错误；截图为 artifacts/double-page-reader-0.2.png。
