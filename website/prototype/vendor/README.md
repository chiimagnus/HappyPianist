# 本地原型依赖

Three.js 固定为 **0.180.0**，只供这个浏览器设计原型，不改变 Xcode/App 依赖。原始文件未经修改；其原有许可证与头部保留于 `LICENSE` 和源码。

来源：

- `https://unpkg.com/three@0.180.0/build/three.module.js`
- `https://unpkg.com/three@0.180.0/build/three.core.js`
- `https://unpkg.com/three@0.180.0/examples/jsm/controls/OrbitControls.js`
- `https://unpkg.com/three@0.180.0/examples/jsm/renderers/CSS3DRenderer.js`
- `https://unpkg.com/three@0.180.0/LICENSE`

SHA-256：

```text
c8211c69345d2e9949dc7a8ac969380497aa0600a5a8ac6a459c8cd02dd9cb8a  three.module.js
eb077d2417f61d3e6d9264c317cabc4ea35769ed6b0ab533067292a550784c20  three.core.js
b97879c748170baadeb3fb84cea1ffdf4674e283dc06042f34e2acb95a76042c  OrbitControls.js
ff7e2468e6e2e153d8914fd8c0e2dcf162d40bb985d5541daece3b795f9e365c  CSS3DRenderer.js
bfe119ea4fd413f5f7ca3fcd63adb0c4a073ed39daa2fe7d3e6b769e21272601  LICENSE
```

HTML import map 指向本目录；OrbitControls 与 CSS3DRenderer 通过同一 `three` 映射消费模块，没有运行时外网资源或另一套 engine。加载方式依据 [Three.js 官方安装文档](https://threejs.org/manual/pages/installation.html)，没有为原型引入构建框架。CSS3DObject 使用对象层级变换，不使用面向镜头的 CSS3DSprite。
