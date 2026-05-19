# emby_intro_skipper
这是一个 mpv 脚本, 用来获取 emby 刮削的片头片尾信息, 并自动跳过片头片尾 

## 为什么用它  
用 hills lite 或 [embyToLocalPlayer](https://github.com/kjtsune/embyToLocalPlayer) 等调用第三方 mpv 时, 只有第一集能同步 emby 的片头信息, 后续只能手动跳过片头

## 主要功能
### 获取片头片尾信息
- 通过 emby 服务端获取, 向 emby 服务端请求视频流的同时请求章节信息
- 通过神医助手生成的 `mediainfo.json`, 目前只支持 json 文件与视频在同一目录
### 跳过片头片尾
有两种模式:
- **自动跳过**: 播放到片头位置直接跳过
- **按键跳过**: 播放片头时根据提示按键跳过
## 使用方法
1. 保存 `emby_intro_skipper.lua` 到 mpv 配置目录的 `scripts` 文件夹
2. 设置快捷键或 [uosc](https://github.com/tomasklaen/uosc) 按钮切换跳过模式, 默认不跳过
   - 快捷键: `#    script-binding emby_intro_skipper/toggle    #! 切换 片头跳过模式`
   - uosc 按钮: 编辑 `uosc.conf` 中的 `controls`, 在合适的位置添加 `button:emby_intro_skipper_mode`
3. (可选) 编辑 `emby_intro_skipper.lua` 开头的配置部分  
   自定义跳过快捷键, 开启读取神医助手生成的 `mediainfo.json` 功能
