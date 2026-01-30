# mpv-custom

项目为 [mpv](https://mpv.io/) 播放器的个人配置文件，采用 [ModernZ](https://github.com/Samillion/ModernZ) 作为 OSC，脚本和设置参考自 [mpv-config](https://github.com/dyphire/mpv-config)，滤镜和着色器来源于 [mpv_PlayKit（原 mpv-lazy）](https://github.com/hooke007/mpv_PlayKit)。

![示意图](scheme.png)

## 使用方法

从 Release 中下载配置文件压缩包。安装 mpv 构建版后，将压缩包中的 portable_config 解压自播放器根目录。

## OSC

采用 [ModernZ](https://github.com/Samillion/ModernZ) 作为 OSC，汉化部分界面。播放音频文件时不自动隐藏，不保存播放进度。

## 设置及输入

播放器设置见 portable_config\mpv.conf。

右键菜单及快捷键见 portable_config\input.conf。

## 脚本

采用的脚本来自多个开源项目。

- [mpv-menu-plugin](https://github.com/tsl0922/mpv-menu-plugin)：为播放器添加右键菜单。
- [thumbfast](https://github.com/po5/thumbfast)：进度条略缩图预览。
- [evafast](https://github.com/po5/evafast)：提供长按快进功能。
- [input-event](https://github.com/natural-harmonia-gropius/input-event)：提供更加丰富的输入行为，如长按、双击等。
- [pause-indicator](https://github.com/CogentRedTester/mpv-scripts/blob/master/pause-indicator.lua)：再界面中央显示播放/暂停图标。
- [dynamic-crop](https://github.com/Ashyni/mpv-scripts/)：动态裁剪黑边。
- [recentmenu](https://github.com/natural-harmonia-gropius/recent-menu)：提供最近访问记录及其菜单项。
- [mpv-file-browser](https://github.com/CogentRedTester/mpv-file-browser)：提供 OSC 界面文件浏览功能。
- [clipshot](https://github.com/ObserverOfTime/mpv-scripts/blob/master/clipshot.lua)：将截图复制到剪贴板。
- [osd-bar](https://github.com/422658476/MPV-EASY-Player/blob/master/portable-data/scripts/osd-bar.lua)：窗口模式在底部始终显示进度条（非 OSC）。
- [sub-fastwhisper](https://github.com/dyphire/mpv-config/blob/master/script-opts/sub_fastwhisper.conf)：AI 识别/翻译字幕。来自 [mpv-config](https://github.com/dyphire/mpv-config)，须自行填写 Whisper 程序路径和大模型 API Key。
- select.lua：汉化版本的菜单。修改自 mpv 源代码内置脚本。
- [stats.lua](https://github.com/FinnRaze/mpv-stats-zh)：汉化版本的统计信息。修改以对增加内容进行汉化。

脚本 lua 文件位于 portable_config\scripts\，脚本设置位于 portable_config\script-opts\。

## 着色器

着色器文件位于 portable_config\shaders\，均来自 [mpv_PlayKit](https://github.com/hooke007/mpv_PlayKit)。

## VapourSynth 滤镜（自行安装）

须配合 [mpv_PlayKit](https://github.com/hooke007/mpv_PlayKit) 的 vsNV 补丁包使用（下载链接：<https://github.com/hooke007/mpv_PlayKit/releases>）。解压后滤镜文件将 portable_config\vs\ 中。

### 使用方法：

- 方案一：解压 vsNV 补丁包自播放器根目录，已内置 Python 运行环境和 VapourSynth 及其必要插件。
- 方案二：
  1. 自行安装 [Python](https://www.python.org) 和 [VapourSynth](https://github.com/vapoursynth/vapoursynth)。
  2. pip 安装 [k7sfunc](https://pypi.org/project/k7sfunc/) 。`pip install k7sfunc`
  3. 将 vsNV 补丁包里 vs-plugins 中的所有文件解压自 VapourSynth 安装目录下的 plugins 文件夹中。
