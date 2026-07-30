---
hide_table_of_contents: true
---

<head>
    <meta name="apple-itunes-app" content="app-id=6469834197"/>
</head>

## 关于 Roam

:::warning

这是 Roam 应用的支持页面，不是 Roly。最近我发现 Roly 应用抄袭了我的源代码和应用商店页面，甚至把本页面作为他们的支持页面进行了链接。这是欺诈且不正确的行为。

:::

:::tip[请我喝杯咖啡]

Roam 完全免费，无广告，无付费等级。如果对你有用，可以[随意打赏](/coffee)。

:::

Roam 提供你需要的一切，拒绝冗余功能

-   支持 Mac、iPhone、iPad、Apple Watch、Vision Pro 以及 Apple TV！
-   与平台深度集成：在 Mac 上支持键盘快捷键，在 iOS 上通过硬件音量键控制电视音量
-   使用快捷指令和小组件，无需打开 App 就能遥控电视！
-   支持耳机模式（即“私人聆听”），在 Mac、iPad、iPhone、VisionOS 和 Apple TV 上都能把电视音频通过你的设备播放
-   打开 App 即可自动发现本地网络中的设备
-   采用苹果原生 SwiftUI 设计系统，界面直观
-   体积小巧，所有设备安装包均小于 8 MB，启动速度不到半秒！
-   开源项目（https://github.com/msdrigg/roam）

## 功能介绍

-   遥控器
    -   Roam 提供标准的 Roku 遥控按钮，包括方向键、选择、返回、主页、播放/暂停，以及支持的电视控制项。
    -   音量控制在 Roku Stick 设备上可能不可用，因为该类设备仅通过 HDMI 连接，无法通过 Roam 的网络指令控制音量。
-   键盘输入
    -   在 macOS 上没有键盘按钮，当 Roam 窗口激活时，Mac 键盘会自动控制电视。
    -   在 iOS 和 iPadOS 上，遥控器顶部有键盘按钮。
    -   watchOS 目前暂不支持键盘输入功能。
    -   部分 Roku 应用会忽略来自远程应用的键盘输入。例如 Prime Video 就不支持通过键盘输入，因为 Roku 应用本身不接受此种输入。
-   键盘快捷键
    -   Roam 将实体键盘上的按键映射为遥控操作（方向键、OK/选择、返回、主页、音量、静音、播放/暂停等），这与屏幕上的文本输入是分开的。
    -   你可以在 **设置 -> 键盘快捷键** 中自定义这些快捷方式（Mac、iPhone、iPad 和 Vision Pro 上可用，watchOS 不支持）。
    -   点击对应行可更改快捷键，右键（Mac）或滑动（iPhone/iPad）可重置，也可使用“重置全部”/“清除全部”。默认快捷键使用 Command (⌘) 作为修饰键。
-   粘贴链接直接播放（macOS）
    -   在 Mac 上复制视频网站链接、点击 Roam 窗口，按 **⌘V**，Roam 会自动在你的 Roku 打开对应的 APP 并播放内容。
    -   支持服务：YouTube、Amazon Prime Video、Netflix、Disney+、Hulu、Max、Paramount+、Peacock、Tubi、Sling 以及 The Roku Channel。
    -   若电视端文本框激活，按 ⌘V 会将剪贴板文本输入该字段，而不是打开视频链接。
-   耳机模式/私人聆听
    -   在支持的 Roku 设备上，可将电视音频通过你的设备进行播放，实现私人聆听。
    -   Mac、iPad、iPhone、VisionOS 及 Apple TV 上均支持该功能，但不是所有 Roku 电视都支持。

## 常见问题

-   如果 Roam 没能自动发现我的电视怎么办？
    -   [详见此处](/manually-add-tv)
-   Roam 在 Apple Watch 上无法正常使用，怎么办？
    -   请前往 **设置 -> 系统 -> 高级系统设置 -> 移动应用控制**，确保设置为 **Permissive（允许）**
-   为什么耳机模式（即私人聆听）无法在我的电视上使用？
    -   目前部分电视无法使用耳机模式。如果你用 Roam 不可用，但官方 Roku App 正常，请将你的 Roku 型号及相关信息发送邮件至 [roam-support@msd3.io](mailto:roam-support@msd3.io)。你的反馈将帮助我排查和修复此问题。
-   如果我遇到其他问题或有建议如何反馈？
    -   如为 BUG，请优先通过应用内提交反馈
        -   进入 Roam 应用，打开设置页面
        -   点击“发送反馈”。会自动生成诊断报告，可以直接发给 roam support（roam-support@msd3.io）
        -   若应用频繁崩溃，请确保你的“分析数据”在 设置 -> 隐私与安全 -> 分析与改进中已开启
            -   打开“共享 iPhone 和 Watch 分析”并勾选“与应用开发者共享”，这样应用崩溃时 Apple 会把报告发给我
    -   如为新功能建议，可通过邮件（roam-support@msd3.io）、在 Roam 应用（设置 -> 与开发者聊天）直接联系，或加入 [Roam Discord](https://discord.gg/FqaTNRccbG) 社区。
-   为什么 iPad 上有时方向键无法使用？
    -   这是因 iPadOS 会优先接管方向键，用于页面导航功能，导致我们无法检测到按键
    -   解决方法：可在 设置 -> 辅助功能 -> 键盘 关闭“完整键盘访问”；或进入 设置 -> 辅助功能 -> 键盘 -> 完整键盘访问 -> 命令 -> 基本，将“上移”、“下移”、“左移”、“右移”禁用
    -   你也可以在 Roam 的 **设置 -> 键盘快捷键** 中重新分配方向键快捷方式。保持 Command (⌘) 作为快捷键修饰符，可避免“完整键盘访问”拦截方向键。
-   为什么我在键盘上输入内容没有显示到电视上？
    -   有些 Roku 应用会直接忽略硬件键盘输入。你可以通过官方 Roku App 试试键盘输入功能，以判断是 Roam 问题还是该 App 的限制
    -   在 macOS 上没有键盘按钮，只要 Roam 窗口处于焦点，Mac 键盘就能自动输入到电视。在 iOS 和 iPadOS 上请使用遥控器顶部的键盘按钮。watchOS 目前不支持键盘输入。
    -   已知无法使用的 App 如：
        -   Prime Video
-   为什么 Roam 能在我的 iPhone 和 Mac 上用，但 Apple Watch 不能？
    -   WatchOS 应用通过电视的 ECP API 连接电视，部分 Roku 设备需要手动启用该 API。请前往 **设置 -> 系统 -> 高级系统设置 -> 移动应用控制**，确认“网络访问”已设为“Permissive”
-   为什么我无法用 Apple Watch 开机电视？
    -   Apple Watch 不能使用标准唤醒接口开机，除非你的 Roku 电视开启了 **Fast TV Start** 功能。开启方法如下：
        -   按下 Roku 电视遥控器上的 **Home**（主页）按钮
        -   上下移动并选择 **设置**
        -   选择 **系统**，然后进入 **电源**
        -   选择 **快速开机（Fast TV Start）**
        -   高亮选择 **启用快速开机**，然后按遥控器的 **OK** 按钮勾选

## 其他资源

如有疑问或遇到问题，请通过邮箱联系我：[roam-support@msd3.io](mailto:roam-support@msd3.io)。你也可以在 Roam 应用中（设置 -> 与开发者聊天）直接联系我，或加入 [Roam Discord](https://discord.gg/FqaTNRccbG) 社区交流。

-   [隐私政策](/privacy)
-   [GitHub 主代码仓库](https://github.com/msdrigg/roam)
-   [Roam Discord 交流群](https://discord.gg/FqaTNRccbG)
-   [App Store 下载](https://apps.apple.com/us/app/roam/6469834197)
-   [产品路线图](/upcoming-work)
-   [更新日志](/changes)
-   [Roku 兼容设备列表](/tested-tvs)
-   [请我喝杯咖啡](/coffee)
