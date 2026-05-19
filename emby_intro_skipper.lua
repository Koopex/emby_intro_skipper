-- https://github.com/Koopex/emby_intro_skipper

local o = {-------------------------------===[[ 脚本配置 ]]===-------------------------------
    skip_key = 'PGDWN',  -- 跳过片头/片尾的按键, 默认是 PageDown
    from_mediainfo = true,  -- 播放本地视频时尝试从神医助手生成的 mediainfo.json 获取章节信息
    config_path = [[~~home/_cache/emby_intro_skipper.json]]
}          -------------------------------===[[ 配置结束 ]]===-------------------------------

local mp = require 'mp'
local utils = require 'mp.utils'
local osd = mp.create_osd_overlay('ass-events')

if o.config_path:match('^~~home') then
	o.config_path = mp.command_native({"expand-path", o.config_path})
end

-- ignore   : 关闭
-- key      : 按键跳过
-- direct   : 直接跳过
local mode = 'ignore'

local function readlog()
	local file = io.open(o.config_path, 'r')
	if file then
		local logs = utils.parse_json(file:read("*a"))
		mode = logs.mode or 'ignore'
		file:close()
	else
		io.open(o.config_path, "w"):write(utils.format_json({mode = 'ignore'})):close()
	end
end

local key_indices = {} -- 用于存储 {intro_start_index, intro_end_index, credits_start_index}

local function on_chapter_change(name, value)
    osd:remove()
    mp.remove_key_binding("skip_intro")
    mp.remove_key_binding("skip_credits")

    if mode == 'ignore' then return end

    -- 如果当前章节在片头范围内，直接跳到片头结束
    local function skip_intro()
        mp.set_property_native("chapter", key_indices.intro_end)
        mp.osd_message("已跳过片头")
    end
    if key_indices.intro_start
    and key_indices.intro_end
    and value >= key_indices.intro_start
    and value < key_indices.intro_end then
        if mode == 'key' then
            osd.data = "{\\an9}按 " .. o.skip_key .. " 跳过片头"
            osd:update()
            mp.add_forced_key_binding(o.skip_key, "skip_intro", function()
                skip_intro()
                mp.remove_key_binding("skip_intro")
            end)
            return
        elseif mode == 'direct' then
            skip_intro()
            return
        end
    end

    -- 如果当前章节在片尾范围内，直接跳到片尾结束
    local function skip_credits()
        mp. commandv('no-osd', 'add', 'chapter', '1')
        mp.osd_message("已跳过片尾")
    end

    if key_indices.credits_start
    and value == key_indices.credits_start then
        if mode == 'key' then
            osd.data = "{\\an9}按 " .. o.skip_key .. " 跳过片尾"
            osd:update()
            mp.add_forced_key_binding(o.skip_key, "skip_credits", function()
                skip_credits()
                mp.remove_key_binding("skip_credits")
            end)
            return
        elseif mode == 'direct' then
            skip_credits()
            return
        end
    end
end

-- 提取 Emby 章节标记（IntroStart, IntroEnd, CreditsStart）, 将时间标记注入为 mpv 章节
local function inject_chapters(emby_chapters)
    if not emby_chapters or #emby_chapters == 0 then return end

    local mpv_chapters = {}

    for i, ch in ipairs(emby_chapters) do
        -- 直接使用 Emby 提供的名字，若为空则根据 MarkerType 补一个
        local title = ch.Name
        
        if ch.MarkerType == "IntroStart" then
            title = "片头"
            key_indices.intro_start = i - 1 -- mpv 的章节索引从 0 开始，而 lua table 索引从 1 开始，所以这里减 1
        elseif ch.MarkerType == "IntroEnd" then
            title = "正片"
            key_indices.intro_end = i - 1
        elseif ch.MarkerType == "CreditsStart" then
            title = "片尾"
            key_indices.credits_start = i - 1
        end

        table.insert(mpv_chapters, {
            title = title,
            time = ch.StartPositionTicks / 10000000 -- 将 Ticks 转换为秒
        })
    end

    -- 注入所有章节
    mp.set_property_native("chapter-list", mpv_chapters)

    -- 把片头和片尾的 index 交给跳过片头的方法使用
    if next(key_indices) then
        mp.observe_property("chapter", "native", on_chapter_change)
    end
end

-- 从 Emby 服务器获取章节信息
local function fetch_chapters_from_emby(url)
    -- 提取参数
	local api_key = url:match("[?&]api_key=([^&]+)")
	local item_id = url:match("[?&]MediaSourceId=([^&]+)"):match("mediasource_(%d+)")
    local server_base = url:match("^(.-)/emby/")
    
    if not (item_id and api_key and server_base) then
        mp.msg.warn("参数提取失败")
        return
    end
    
    -- 构建并请求
    local chapters_url = string.format(
        "%s/emby/Items?Ids=%s&Fields=Chapters&api_key=%s",
        server_base, item_id, api_key
    )

    local args = {
        "curl",
        "-s",
        "--max-time", "5",  -- 5秒超时
        chapters_url
    }

    -- 异步执行 curl 请求
    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
    }, function(success, result)
        if not success or result.status ~= 0 then
            mp.msg.warn("请求失败: " .. (result.error or "未知错误"))
            return
        end

        -- 解析 JSON
        local chapters = utils.parse_json(result.stdout).Items[1].Chapters

        if chapters then
			-- 提取并注入章节到当前视频
			inject_chapters(chapters)
        end
    end)
end

-- 尝试从本地 MediaInfo.json 获取章节信息
local function fetch_chapters_from_mediainfo(path)
	local mediainfo_path = string.match(path, "(.+)%..+$") .. '-mediainfo.json'

	local file = io.open(mediainfo_path, 'r')
	if not file then return end

	local content = file:read('*a')
	file:close()

	-- 解析 MediaInfo JSON 并注入章节
	local mediainfo = utils.parse_json(content)
	if mediainfo and mediainfo[1].Chapters then
		inject_chapters(mediainfo[1].Chapters)
	end
end


local function on_file_loaded()
    readlog()

    local path = mp.get_property("path")

    if not path then
        mp.msg.warn("无法获取当前文件路径")
        return
    end

    if string.find(path, "/emby/videos/.+/original") then
		fetch_chapters_from_emby(path)
        return
	elseif o.from_mediainfo and not path:match("^(http|rtmp)") then
		fetch_chapters_from_mediainfo(path)
    end
end

local function on_file_end()
    -- 文件结束, 取消对章节变化的监听
    mp.unobserve_property(on_chapter_change)
    -- 清空章节索引
    key_indices = {}
end

local function toggle()
    readlog()

    if mode == 'ignore' then
        mode = 'key'
        mp.osd_message("已切换到“按键跳过”模式")
    elseif mode == 'key' then
        mode = 'direct'
        mp.osd_message("已切换到“直接跳过”模式")
    elseif mode == 'direct' then
        mode = 'ignore'
        mp.osd_message("片头跳过 已关闭")
    end

	io.open(o.config_path, "w"):write(utils.format_json({mode = mode})):close()
end

mp.commandv('script-message-to', 'uosc', 'set-button', 'emby_intro_skipper_mode', utils.format_json({
    icon = 'swipe_right',
    tooltip = "切换片头跳过模式",
    command = 'script-binding emby_intro_skipper/toggle'
}))
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", on_file_end)
mp.add_key_binding(nil, 'toggle', toggle)