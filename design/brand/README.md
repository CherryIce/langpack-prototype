# 译包 LangPack · 双语卡片

图标以两张错位叠放的语言卡片表达「收集文案、跨语言转换、打包交付」。笔画均为矢量路径，没有字体依赖。左后是薄荷绿的「文」，右前是暖白的「A」；森林绿底保持小尺寸识别度。

| 用途 | 颜色 |
| --- | --- |
| 品牌主色 / 图标底 | `#197E64` |
| 文字墨色 | `#243E34` |
| 页面与启动背景 | `#F5F8F4` |
| 辅助薄荷 | `#CDE9D9` |

`app-icon.svg` 是完整的 1024×1024 母版，`mark.svg` 是同一组透明卡片。iOS 使用不含透明像素、没有预裁圆角的方形 PNG；Android legacy、Web、Windows 保留透明圆角；macOS 额外保留光学留白。Android adaptive 前景与 monochrome 资源均缩入系统安全区。

Flutter 使用 `assets/brand/app-icon.png` 与 `assets/brand/mark.png`。Web 使用 `assets/brand/*.svg`。SVG 不依赖外部字体、图片或网络。

## 启动

- iOS：暖白底，96 pt 图标居中，1× / 2× / 3×资源。
- Android 11及以下：暖白底，96 dp 图标居中。
- Android 12及以上：使用系统启动页主题，同色背景与专用矢量图标；系统决定显示时长。
- 启动页没有进度数字、授权请求或营销内容。

## 重新生成图标

运行环境需要 Node.js 与 `sharp`。已有该依赖时运行：

```sh
node scripts/generate-brand-assets.cjs
```

依赖位于独立位置时，可用 `NODE_PATH=/path/to/node_modules node scripts/generate-brand-assets.cjs`。脚本读取本目录 SVG，输出 iOS / Android / macOS / Windows / Web 图标与 iOS / Android 启动 PNG。Android vector、adaptive XML 和启动主题单独随源码维护。

本次只生成并静态核对资源；原生平台的实际启动截图应由对应平台运行验证提供。

## 设计总览

打开 `index.html` 可查看图标、启动页与三步引导，手机可横向滑动。引导使用 `previews/flutter-intro-01.jpg` 至 `03.jpg` 的实际应用 Web 截图，点击可查看原图。启动页以相同配色和比例呈现 `splash.html` 的品牌居中布局。

`overview.png` 是 1800×1210 的静态总览，便于保存与分享。可在安装 `sharp` 的环境中运行 `node design/brand/generate-overview.cjs` 重新生成；它只进行矢量渲染与图片合成，不依赖浏览器或网络。
