# 漫匣图标

`xiaxia-source.png` 是小夏眨眼、比 V 的透明原图，`icon.png` 是品牌展示图。

安装 Pillow 后运行 `python tools/generate-icons.py` 生成 Android 各密度桌面图标、前景素材和 Web/PWA 图标。脚本仅缩放、安排透明留白，不重画角色，也不添加背景。

Android 使用透明 PNG 桌面图标，避免透明自适应底层被桌面渲染成黑色。附带的前景素材按 108dp 图层中的 66dp 安全圆适配，PWA maskable 图标将角色保留在中央安全圆内。桌面最终的图标外形由系统控制；保留源图的 Alpha 通道，不把透明区域填成黑色或白色。
