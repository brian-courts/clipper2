--@diagnostic disable: lowercase-global 
-- above for Visual Studio Code editing
-- clipper2.lua -- VLC extension
--[[

Clipper2 is a VLC extension to create portions (clips) of files. 
It provides facilities to jump backwards and forwards within a video by 1 frame, 1 second, 10 seconds or 1 minute. 
It includes a feature to create successive clips from a file (like fido_a, fido_b, fido_c, etc.).
It calls the external ffmpeg program to create the clips.

INSTALLATION:
Put the file in the VLC subdir /lua/extensions, by default:
* Windows (all users): %ProgramFiles%\VideoLAN\VLC\lua\extensions\
* Windows (current user): %APPDATA%\VLC\lua\extensions\
* Linux (all users): /usr/share/vlc/lua/extensions/
* Linux (current user): ~/.local/share/vlc/lua/extensions/
* Mac OS X (all users): /Applications/VLC.app/Contents/MacOS/share/lua/extensions/
(create directories if they don't exist)
If VLC is not running, this extension will be available next time it starts.
If VLC is running, restart it, or in the VLC "Tools | Plugins and Extensions" item,
select the "Active Extensions" tab, then click the "Reload Extensions" box.

USAGE:
	Go to the "View" menu and select "Clipper2".
	Select a file to play.
	Select Start and Stop times for the desired clip.
	Click the "Save clip" box to save the clip.
	Click the "Help" button for detailed instructions.

TESTED SUCCESSFULLY ON:
	VLC 3.0.16 on Windows 10
	VLC 3.0.9.2 on Xubuntu 20.04.3

LICENSE:
	GNU General Public License version 2
--]]
--[[
	The calls to inform() send text to the Messages window. See comments in that function for usage.
	Most of the calls to that function have been converted to comments, so they take no action,
	Those calls are retained for possible future use when debugging.
]]
--[[

	regular expression to find lines starting with tab + inform( 
	works in Visual Studio Code, if the Regular Expression token (.*) is selected in the Find box

	\t(?<!-- *)inform\(
		(?<!-- *) makes sure there is no -- comment indicator, with or without spaces
	replace those found bits with "-- inform(" (no quotes) to comment out the inform() calls
]]
-- globals:
clipper_items = {}
source_item = nil
curr_id = -1
no_time = "--:--"
frame_rate = nil
duration = 0
osd_channel = nil
error_duration = 2000000 -- 2000000 microseconds = 2 seconds

time_factor = 1 -- 1 if before version 3 (times in seconds), 0.000001 if version 3 (times in microseconds)

time_steps = { -- values to increment/decrement show time (and position in video)
	{"1 second", 1},
	 -- actual time step for frames will be calculated from media's FramesPerSecond
	{"1 frame", 0.03333},
	{"10 seconds", 10},
	{"1 minute", 60}
}

add_number_pos = 1
add_start_stop_pos = 2
add_nothing_pos = 3

active=false

item_path = ""
file_item = false -- is the current item a file? true or false
file_path = nil
file_name = nil
file_ext = nil

function descriptor()
	return {
		title = "Clipper2 0.9";
		version = "0.9";
		author = "Brian Courts";
		url = 'to be determined';
		shortdesc = "Clipper2 0.9: Create clips of files.";
		description = "Clipper2 is a VLC extension (extension script \"clipper2.lua\") to create portions (clips) of files.";
		capabilities = {"input-listener"}
	}
end

function activate()

	-- this function called when extension is activated

	dir_sep = package.config:sub(1,1) or '/'
	-- inform("activate() dir_sep = " .. dir_sep)

	create_dialog()
	show_status("", "")
	--inform("activate() dialog created.")

	-- vlc.playlist.current() gives playlist item's id + ID_OFFSET
	-- We need to determine the value of ID_OFFSET to adjust (or not) the
	-- value returned by vlc.playlist.current().
	-- In early version of VLC the ID_OFFSET was 1
	-- In those early versions, Lua extensions could access vlc.misc
	-- In later versions, ID_OFFSET is 0, and extensions cannot access vlc.misc
	-- I don't know whether the correlation is perfect, but it works on
	-- 2.08 (ID_OFFSET = 1) and 3.0 (ID_OFFSET = 0)

	if vlc.misc then
		ID_OFFSET = 1
	else
		ID_OFFSET = 0
	end
	--inform("activate() ID_OFFSET = ".. ID_OFFSET)

	-- osd_channel = vlc.osd

	input_active("add")

	-- inform("calling vlc.osd.message('ACTIVATED')")
	-- vlc.osd.message("ACTIVATED")
	
	-- inform("calling vlc.osd.message('ACTIVATED', nil, 'center', 20000000)")
	-- -- 20000000 microseconds = 20 seconds
	-- vlc.osd.message("ACTIVATED", nil, "center", 20000000)
	
	--inform("activate() input activated.")

end

function deactivate()
	input_active("del")
end

function close()
	vlc.deactivate()
end

function input_changed()
	input_active("toggle")
end

function meta_changed()
end

function input_active(action)  -- action=add/del/toggle

	-- WOULD BE NICE TO CHECK IF SHOWING A PORTION OF THE PRECEDING ITEM,
	-- THEN JUST GOING TO NEW START POSITION. BUT NEW ITEM HAS ALREADY
	-- STARTED PLAYING, SO WE SEE START OF EVERY SEGMENT
	--inform("input_active action = " .. action)
	if (action=="toggle" and active==false) then action="add"
	elseif (action=="toggle" and active==true) then action="del" end

	local input = vlc.object.input()
	if input and active==false and action=="add" then
		active=true
		show_init()
	elseif input and active==true and action=="del" then
		active=false
	end
end

-- returns frame rate in frames per second
function get_frame_rate(input_item) 

	local info = input_item:info()
	local frame_rate
	for k, v in pairs(info) do
		for k2, v2 in pairs(v) do
			--inform(tostring(k2) .. " = " .. tostring(v2))
			if (k2 == "Frame rate") then
				frame_rate = tonumber(v2)
				return frame_rate
			end
		end
	end
	frame_rate = nil
	return frame_rate
end

function inform(message)
	-- This function displays information in the VLC Messages window.
	-- That window can be shown or hidden by selecting "Messages" in the "Tools" menu,
	-- or by typing Ctrl-m
	-- You can enter "Clipper" (without quotes) in the Filter box of the Messages window to see only messages containing Clipper.
	vlc.msg.info("Clipper: " .. message)
end

function show_init()
	-- this function called when the current item is changed

	--inform("show_init")
	curr_id = current_id()
	if (curr_id < 0) then
		return
	end

	source_item = get_clipper_item(curr_id)
	-- some items in the playlist may have start and
	-- stop times, so show those times
	get_file_location(source_item.path)
	local start_t = source_item.start
	local curr_item = vlc.playlist.get(curr_id)
	local input_item = vlc.input.item()
	duration = input_item:duration() -- gets duration in seconds
	-- if file format does not return duration, it is set to a negative value
	if (duration < 0) then
		duration = -1
	end
	--inform("duration = " .. duration)

	get_frame_rate(input_item)
	item_name_fld:set_text(source_item.name or curr_item.name)
	start_time_lbl:set_text(string_from_seconds(start_t))
	stop_time_lbl:set_text(string_from_seconds(source_item.stop))
	set_time(start_t or 0)
end

function show_time()
	local show_t = 0
	local show_str = show_time_fld:get_text()
	--inform("show_time() show_str = " .. show_str)
	if (not show_str) or (show_str == no_time) or (show_str == "") then
		show_t = current_time()
	else
		show_t  = seconds_from_string(show_str)
		--inform("show_time() show_t from string = " .. show_t)
		if (not show_t) then
			local time_err = "'"..show_str.."' not valid time"
			show_time_fld:set_text(time_err)
			error(time_err)
			return
		end
		--inform("show_time() duration = " .. duration)
		-- duration < 0 indicates file did not have duration information
		if (show_t < 0) then 
				-- negative show_t means go back from end of the clip
			if (duration > 0) then
					show_t = duration + show_t
				if (show_t < 0) then
					-- don't go too far back
					show_t = 0
				end
			else 
				--inform("Clipper2 cannot go back from end. File did not provide duration information.")
			end
		elseif ((show_t > duration) and (duration > 0)) then
			show_t = duration
		end
	end
	--inform("show_time() show_t = " .. show_t)
	show_time_fld:set_text(string_from_seconds(show_t))
	return show_t
end

function set_time_show()

	-- local curr_id = current_id()
	if (curr_id < 0) then
		return
	end

	local show_t = show_time()
	--inform("set_time_show() show_t = " .. show_t)
	set_time(show_t)
end

function get_time_step()
	local step_num, step_dat, time_step, step_name
	step_num = time_step_drop:get_value()

	step_dat = time_steps[step_num]

	step_name = step_dat[1]
	if frame_rate and (step_name == "1 frame") then
		if (frame_rate > 100) then
			-- assume this is a bogus or unknown frame rate
			-- try a workable frame rate
			time_step = 1 / 24
		else
			time_step = 1/ frame_rate
		end
	else
		time_step = step_dat[2]
	end

	return time_step
end

	--[[
	We decrement or increment the time here relative to the current media time.
	Some time passes while the time is set and the image shown, so the
	time shifts will not be exactly the time specified.
	For 1-frame shifts the video is paused to allow the user to see the small
	jumps, and the jumps are relative to the time in the "Show" text entry box,
	which is set by the preceding jump. By this means, the 1-frame jumps should
	be exactly 1 frame.
	]]

function show_dec()
	show_jump("dec")
end

function show_inc()
	show_jump("inc")
end

function show_jump(which)
	-- local curr_id = current_id()
	if (curr_id < 0) then
		return
	end
	local show_t

	local step = get_time_step()
	if (step < 1) then
		if (vlc.playlist.status() == 'playing') then
			-- first call of series with step < 1 (1-frame jump)
			-- pause the video so the user can see the small jumps
			pause_playlist()
			show_t = set_show_curr()
		else
			show_t = show_time()
		end
	else
		show_t = set_show_curr()
	end

	if (which == "dec") then
		show_t = show_t - step
		if (show_t < 0) then
			show_t = 0
		end
	elseif (which == "inc") then
		show_t = show_t + step
		if (duration > 0) and (show_t > duration) then
			show_t = duration
		end
	else
		-- invalid call
		return
	end

	set_time(show_t)
end

function set_time(when)
	--inform("set_time() when = " .. when)
	if (not when) or (when == no_time) then
		return
	end

	local input=vlc.object.input()
	if not input then
		return
	end

	if (type(when) == "string") then
		when = seconds_from_string(when)
	elseif (type(when) ~= "number") then
		when = 0
	end

	-- local curr_id = current_id()

	if (when < 0) then
		when = 0
	else
		if ((when > duration) and (duration > 0)) then
			when = duration
		end
	end

	show_time_fld:set_text(string_from_seconds(when))
	if (when < 100000) then
		when = when * 1000000
	end

	--inform("set_time() setting time to = " .. when)
	vlc.var.set(input, "time", when)
end

-- function set_item_name()

-- 	local curr_id = current_id()
-- 	if (curr_id < 0) then
-- 		return
-- 	end

-- 	source_item = get_clipper_item(curr_id)
-- 	source_item.name = item_name_fld:get_text()
-- 	-- regen_playlist(curr_id, "set_name")
-- end

function create_dialog()

	-- setting the row for each set of widgets allows one to more easily
	-- add and rearrange widgets

	local row = 0
	dlg = vlc.dialog("Clipper2")

	--inform("create_dialog() row = " .. row)
	row = row + 1
	-- item_name_btn = dlg:add_button("Item Name =", set_item_name,1,row,1,1)
	item_name_lbl = dlg:add_label("Item Name =",1,row,1,1)
	item_name_fld = dlg:add_text_input("", 2,row,2,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	show_btn = dlg:add_button("Show", set_time_show, 1,row,1,1)
	show_time_fld = dlg:add_text_input(no_time, 2,row,1,1)
	show_cur_btn = dlg:add_button("Show = Curr.", set_show_curr, 3,row,1,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	time_step_drop = dlg:add_dropdown(1,row,1,1)
	for i, step in pairs(time_steps) do
		time_step_drop:add_value(step[1], i)
	end
	show_dec_btn = dlg:add_button("<<", show_dec, 2,row,1,1)
	show_inc_btn = dlg:add_button(">>", show_inc, 3,row,1,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	start_lbl = dlg:add_label("Start", 1,row,1,1)
	start_time_lbl = dlg:add_label(no_time, 2,row,1,1)
	pause_play_btn = dlg:add_button("Pause / Play", pause_or_play, 3,row,1,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	start_curr_btn = dlg:add_button("Start = Curr.", set_start_curr, 1,row,1,1)
	start_show_btn = dlg:add_button("Start = Show", set_start_show, 2,row,1,1)
	start_begin_btn = dlg:add_button("Start = Begin", set_start_begin, 3,row,1,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	stop_lbl = dlg:add_label("Stop", 1,row,1,1)
	stop_time_lbl = dlg:add_label(no_time, 2,row,1,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	stop_curr_btn = dlg:add_button("Stop = Curr.", set_stop_curr, 1,row,1,1)
	stop_Show_btn = dlg:add_button("Stop = Show", set_stop_show, 2,row,1,1)
	stop_end_btn = dlg:add_button("Stop = End", set_stop_end, 3,row,1,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	clip_dir_lbl = dlg:add_label("Clip directory", 1,row,1,1)
	clip_dir_fld = dlg:add_text_input(vlc.config.homedir(), 2,row,2,1)

	--inform("create_dialog() row = " .. row)
	row = row + 1
	clip_name_lbl = dlg:add_label("Clip name", 1,row,1,1)
	clip_name_fld = dlg:add_text_input("myclip", 2,row,1,1)
	clip_btn = dlg:add_button("Save clip", save_clip, 3,row,1,1)

	--inform("create_dialog() row = " .. row)
	-- below will add row to show user the command used to save the clip
	-- row = row + 1
	-- output_lbl = dlg:add_label("Output", 1,row,1,1)
	-- output_fld = dlg:add_text_input("", 2,row,2,1)

	-- row = row + 1
	-- playlist_dir_lbl = dlg:add_label("Playlist directory", 1,row,1,1)
	-- playlist_dir_fld = dlg:add_text_input(vlc.config.homedir(), 2,row,2,1)

	-- row = row + 1
	-- playlist_name_lbl = dlg:add_label("Playlist name", 1,row,1,1)
	-- playlist_name_fld = dlg:add_text_input("mylist", 2,row,1,1)
	-- playlist_ext_lbl = dlg:add_label(".m3u", 3,row,1,1)

	-- row = row + 1
	-- load_playlist_btn = dlg:add_button("Load Playlist", load_playlist,1,row,1,1)
	-- save_abs_btn = dlg:add_button("Save Absolute", save_playlist_abs,2,row,1,1)
	-- save_abs_btn = dlg:add_button("Save Relative", save_playlist_rel,3,row,1,1)

	-- inform("create_dialog() row = " .. row)
	row = row + 1
	help_row = row
	add_clip_check_box = dlg:add_check_box("Add clip to Playlist", true,1,row,1,1)
	auto_advance_check_box = dlg:add_check_box("Auto Advance", true,2,row,1,1)
	help_col = 3
	help_btn = dlg:add_button("HELP", click_HELP,help_col,row,1,1)

	dlg:update()
end

function pause_or_play()
	local input = vlc.object.input()
	if (not input) then
		return
	else
		local status = vlc.playlist.status()
		if (status == 'stopped') or (status == 'paused') then
			play_playlist()
		else
			pause_playlist()
		end
	end
end

function pause_playlist()
	vlc.playlist.pause()
end

function play_playlist()
	vlc.playlist.play()
end

function get_rel_path(rel_to, this_path, dir_sep)
	local match_pat = rel_to .. dir_sep .. "(.+)"
	local rel_path = string.match(this_path, match_pat)
	return rel_path
end

function last_added_id()

	-- get the id of the just-added playlist item
	local id, just_added
	local play_list = vlc.playlist.get("normal", false)
	local items = play_list.children

	-- maximum id of playlist's children will be the one just added
	-- position in playlist may change, but the id will not
	just_added = -1
	for key, val in pairs(items) do
		id = val.id
		if id > just_added then
			just_added = id
		end
	end
	return just_added
end

function get_clipper_item(id)
	--inform("get_clipper_item() looking for id = " .. id)
	source_item = clipper_items[id]
	if (not source_item) then
		-- this item was not added to the playlist by clipper, so clipper has no data on it.
		-- we'll add a new item, and populate it with name and path.
		local item
		source_item = {}
		item = vlc.playlist.get(id)
		source_item.path = item.path
		source_item.name = item.name
		clipper_items[id] = source_item
		--inform("get_clipper_item() adding source_item = " .. id .. ", " .. source_item.path .. ", " .. source_item.name)
	else
		--inform("get_clipper_item() found source_item = " .. id .. ", " .. source_item.path .. ", " .. source_item.name)
	end

	return source_item
end

-- function add_playlist_item(source_item)

-- 	local play_list
-- 	local playlist_item = {}

-- 	playlist_item.path = source_item.path
-- 	if source_item.name then
-- 		playlist_item.name = source_item.name
-- 	end

-- 	if source_item.start then
-- 		playlist_item.options = {"start-time="..source_item.start}
-- 	end

-- 	if source_item.stop then
-- 		if (not playlist_item.options) then
-- 			playlist_item.options = {}
-- 		end
-- 		table.insert(playlist_item.options, "stop-time="..source_item.stop)
-- 	end

-- 	-- add the item to the playlist
-- 	-- need to do vlc.playlist.enqueue or vlc.playlist.add() to get item into vlc's playlist
-- 	vlc.playlist.enqueue( {playlist_item} )
-- 	--vlc.playlist.add( {playlist_item} )

-- -- NOTE: after item added to playlist, it
-- -- does not have an accessible options field for start time and stop time
-- -- so we need to save that information elsewhere

-- 	just_added = last_added_id()

-- 	clipper_items[just_added] = source_item
-- 	return just_added

-- end

function get_file_location(source_path) 
	-- check for and remove file:/// part of path
	local found
-- inform("get_file_location for cl_path = " .. source_path)
	item_path, found = string.gsub(source_path, '^file:///', '')
	--inform("get_file_location: found = " .. found)

	if (found > 0) then 
		-- this is a 'file:///' item
		file_item = true
		--inform("substituting %20 by space")
		item_path = string.gsub(item_path, '%%20', ' ')
		if (dir_sep ~= "/") then
			--inform("substituting / by dir_sep") 
			item_path = string.gsub(item_path, '/', dir_sep)
		end

		--inform("item_path = " .. item_path)
		file_path, file_name, file_ext = split_filename(item_path)
		--inform("get_file_location: path, name, ext = " .. file_path .. ", " .. file_name .. ", " .. file_ext)
		--inform("get_file_location: setting clip_dir_fld text")
		clip_dir_fld:set_text(file_path)
		--inform("get_file_location: setting clip_name_fld text")
		clip_name_fld:set_text(file_name .. "_")
		--inform("get_file_location: setting clip_name_lbl text")
		clip_name_lbl:set_text("Clip name (" .. file_ext .. ")")
		--inform("get_file_location: returning true")
		return true
	else
		return false
	end
end

function save_clip()
-- inform("saving clip")

-- inform("current_id = "..curr_id)

	clear_status()

	if (curr_id < 0) or (not source_item) then
		show_error("CLIP SOURCE ERROR", "No active item.")
		return
	end

-- inform("item_path = " .. item_path)

-- inform("source_item.start, stop = "..tostring(source_item.start)..", "..tostring(source_item.stop))

	local start_time = source_item.start
	local stop_time = source_item.stop
	
	if (not start_time) and (not stop_time) then
		show_error("CLIP LIMITS ERROR", "Must set Start and/or Stop.")
		return
	else 
		if (stop_time and start_time) then
			-- if (stop_time > 0) and (stop_time <= start_time) then
			if (stop_time <= start_time) then
				show_error("INVALID START OR STOP", "Proposed Start time ("..string_from_seconds(start_time)..") not before Stop time ("..string_from_seconds(stop_time) .. ").")
				return
			end
		end
	end

	local path, rel_path
	local name
	local start_parm = ""
	local stop_parm = ""

	-- -ss parameter may improve initial portion of clip
	if start_time then 
		start_parm = " -ss " .. tostring(start_time)
	end
-- inform("start_parm = " .. start_parm)

	if stop_time then
		stop_parm =  " -to ".. tostring(stop_time)
	end	
-- inform("stop_parm = " .. stop_parm)

	local clip_dir = clip_dir_fld:get_text()
	-- make sure last char is dir_sep
	local dir_len = string.len(clip_dir)
	local last_char = string.sub(clip_dir, dir_len, dir_len)
	if last_char ~= dir_sep then
		clip_dir = clip_dir .. dir_sep
	end
	local quoted_clip_dir = '"' .. clip_dir .. '"'
-- inform("quoted_clip_dir = " .. quoted_clip_dir)

	local clip_name = clip_name_fld:get_text()

	local clip_path = clip_dir .. clip_name .. "." .. file_ext
-- inform("clip_path = " .. clip_path)
	local quoted_clip_path = '"' .. clip_path .. '"'
-- inform("quoted_clip_path = " .. quoted_clip_path)

	local quoted_item_path = '"' .. item_path .. '"'
-- inform("quoted_item_path = " .. quoted_item_path)

-- inform("check if directory exists")
	local files_in_dir, err_msg, err_num = vlc.io.readdir(clip_dir)
-- inform("files_in_dir = " .. tostring(files_in_dir) .. " " .. tostring(err_msg) .. " " .. tostring(err_num))
	if (not files_in_dir) then
		show_error("DIRECTORY NOT FOUND", quoted_clip_dir .. " is not a directory.")
		return
	end

	if (file_exists(clip_path)) then
		show_error("NO OVERWRITE", " This program will not overwrite the existing file:<br><br>" .. quoted_clip_path)
		return
	end

	local base, number, lc_letter, is_auto_advance

	if (auto_advance_check_box:get_checked()) then
		is_auto_advance = false
		-- check if clip_name matches one of the auto advance patterns, 
		-- (for example: base_3, or base_t)

		_,  _, base, number = string.find(clip_name, "(.+_)(%d+)$")
		if (number) then
			is_auto_advance = true
			-- inform("auto number " .. tostring(number))
		else
			_,  _, base, lc_letter = string.find(clip_name, "(.+_)(%l)$")
			if (lc_letter) then
				is_auto_advance = true
				-- inform("auto lowercase " .. tostring(lc_letter))
			end
		end
		if (not is_auto_advance) then
			show_error("INVALID AUTO ADVANCE", 
			" Clip name (" .. clip_name .. 
			") does not end with underscore + letter or number (_b, _3, etc.)." ..
			" If you do not wish to use the Auto Advance option, uncheck the Auto Advance box.")
			return
		end
	end


	-- -n parameter tells ffmpeg to not overwrite existing file
	-- -loglevel parameter of 'quiet' tells ffmpeg to minimize output in the command prompt window that appears when ffmpeg is executed
	-- -i parameter tell ffmpeg that the input file is specified next (in start_parm) 
	local clip_cmd = "ffmpeg -n -loglevel quiet -i " ..
		quoted_item_path ..
		start_parm ..
		stop_parm ..
		" -c copy " .. quoted_clip_path
-- inform("clip_cmd = " .. clip_cmd)

-- inform("executing " .. clip_cmd)
	show_status("Saving clip", "Executing " .. clip_cmd)
	local result = os.execute(clip_cmd)
-- inform("os.excute() result = " .. tostring(result))
	if result == 0 then 
		local item = {}
	-- inform("item = " .. tostring(item))
		if (dir_sep ~= "/") then
			--inform("substituting / by dir_sep") 
			item_path = string.gsub(item_path, '/', dir_sep)
		end
		local local_path = "file:///" .. clip_path
	-- inform("local_path = " .. local_path)
		item.path = local_path
		item.name = clip_name

		if add_clip_check_box:get_checked() then
			-- we don't "add" in VLC sense because vlc.playlist.add would cause VLC to start playing the item
			-- inform("enqueueing item with path " .. item.path)
			vlc.playlist.enqueue({item})
		end

		if (is_auto_advance) then
			local second_line = "<br><br>Set start and stop times for next clip, or select another item to continue clipping."
			if (stop_time) then 
				-- inform("Doing auto advance.")
				set_start(stop_time)
				set_time(stop_time)
				-- leave stop_time at current value. Let user modify.

				if (number) then
					-- inform(" old number: " .. string.format("%d", number) .. ", new number: " .. string.format("%d", number + 1))
					clip_name_fld:set_text(base .. string.format("%d", number + 1))
				else
					if (lc_letter) then
						if lc_letter == "z" then
							second_line = "<br><br>Last letter (z) used. <br><br>To continue Auto advance, use a different base name, or use numbers."
						else
							clip_name_fld:set_text(base .. ('abcdefghijklmnopqrstuvwxyz'):match(lc_letter..'(.)'))
						end
					end
				end
				-- inform("Auto advanced to end of saved clip.")
				-- inform("second_line = ".. second_line)
				show_status("Saved clip", "as " .. clip_path .. 
				"<br><br>Auto advanced to end of saved clip." ..
				second_line
				)
			else 
				-- inform(" Auto advanced to end of item.")
				show_status("Saved clip", "as " .. clip_path ..
				"<br><br>Auto advanced to end of item." .. 
				"<br><br>Select another item to continue clipping.")
			end
		else 
			show_status("Saved clip", "as " .. clip_path)
		end
	else
		show_error("Error saving clip", "Status = " .. result)
	end
end

function current_id()
	local curr = vlc.playlist.current()
	--inform("current_id() curr = " .. curr)
	if (curr < 0) then
		return curr
	end
	local id = curr - ID_OFFSET
	--inform("current_id() id = " .. id)
	return id
end

function set_show_curr()
	local curr_t = current_time()
	if (curr_t == no_time) then
		return
	else
		--inform("set_show_curr() curr_t = " .. curr_t)
		show_time_fld:set_text(string_from_seconds(curr_t))
	end
	return curr_t
end

function set_start_show()
	set_start(show_time())
end

function set_start_curr()
	set_start("curr")
end

function set_start_begin()
	local when = nil
	--inform("set_start_begin() (when = )" .. tostring(when))
	set_start(nil)
end

function set_start(when)

	clear_status()
	--inform("set_start() when = " .. tostring(when))
	if (when == 0) then
		when = nil
	end

	-- local curr_id
	--inform("set_start() curr_id = " .. curr_id)
	if (curr_id < 0) then
		return
	end

	local input = vlc.object.input()
	if (not input) then
		start_time_lbl:set_text(no_time)
		return
	end

	local start_time = parse_time(when)
	if (start_time == no_time) then
		-- inform("set_start() no_time, returning")
		return
	end

	--inform("set_start() source_item = " .. tostring(source_item.path))

	local stop_time = source_item.stop
-- inform("set_start() start_time = "..tostring(start_time)..", stop_time = "..tostring(stop_time))
	source_item.start = start_time
	start_time_lbl:set_text(string_from_seconds(start_time))
end

--[[
OSD IS WORKING IN VLC 3.0.16 on Windows 10
Could use the functions below to display information
---
osd.icon( type, [id] ): Display an icon on the given OSD channel. Uses the
  default channel if none is given. Icon types are: "pause", "play",
  "speaker" and "mute".
osd.message( string, [id], [position], [duration] ): Display the text message on
  the given OSD channel. Position types are: "center", "left", "right", "top",
  "bottom", "top-left", "top-right", "bottom-left" or "bottom-right". The
  duration is set in microseconds.
osd.slider( position, type, [id] ): Display slider. Position is an integer
  from 0 to 100. Type can be "horizontal" or "vertical".
osd.channel_register(): Register a new OSD channel. Returns the channel id.
osd.channel_clear( id ): Clear OSD channel.
]]

function show_error(error, description)
	local error_text=
	[[<style type="text/css">
	body {background-color:white;}
	#header{background-color:#f59ca8;}
	</style>
	<body>
	<div id=header><b>]] .. error  .. "</b>	</div> <hr />" .. description
	-- inform("show_error " .. tostring(status_html))
	-- inform"adding widget")
	status_html = dlg:add_html(error_text,1,help_row + 1,3,1)
	-- inform"updating dialog")
	dlg:update()
end

function show_status(status, description)
	-- inform"show_status " .. tostring(status) .. "  " .. tostring(description))
	if status_html then
		-- inform"deleting status widget")
		dlg:del_widget(status_html)
	end
	local status_text=
	[[<style type="text/css">
	body {background-color:white;}
	#header{background-color:white;}
	</style>
	<body>
	<div id=header><b>]] .. status .. "</b>	</div> <hr />" .. description
	-- inform"adding widget")
	status_html = dlg:add_html(status_text,1,help_row + 1,3,1)
	-- inform"updating dialog")
	dlg:update()
end

function clear_status() 
	-- inform"clear_status()")
	show_status(" ", " ")
end

-- function clear_output() 
-- 	output_lbl:set_text("")
-- 	output_fld:set_text("")
-- end

function set_stop_show()
	set_stop(show_time())
end

function set_stop_curr()
	set_stop("curr")
end

function set_stop_end()
	set_stop(nil)
end

function set_stop(when)
	--inform("set_stop() when = " .. tostring(when))
	clear_status()
	local input = vlc.object.input()
	if not input then
		return
	end

	-- local curr_id = current_id()
	--inform("set_stop() curr_id = " .. curr_id)
	if (curr_id < 0) then
		return
	end

	local stop_time = parse_time(when)
	if (stop_time == no_time) then
		--inform("set_stop() no_time, returning")
		return
	end

	local start_time = source_item.start
	-- inform("set_stop() start_time = "..tostring(start_time)..", stop_time = "..tostring(stop_time))
	source_item.stop = stop_time
	stop_time_lbl:set_text(string_from_seconds(stop_time))

end

function click_HELP()
	local help_text=
	[[
	<style type="text/css">
	body {background-color:white;}
	.hello{font-family:"Arial black";font-size:48px;color:red;background-color:lime}
	#header{background-color:#B7FCB7;}
	.highlight{background-color:#FFFF7F;}
	.marker_green{background-color:#B7FCB7;}
	.input{background-color:lightblue;}
	.button{background-color:#E8E8E8;}
	.tip{background-color:#FFBFDA;}
	#footer{background-color:#D6ECF2;}
	</style>

	<body>
	<div id=header><b>Clipper2</b> is a VLC Extension that allows you to create 
	clips (portions) of video files</b>
	</div>
	<hr>

	<div><center><b><a class=highlight>&nbsp;Instructions&nbsp;</a></b></center><div>
	<b>In brief:</b>

	<ul>
	<li>Select a video in the playlist.</li>
	<li>Set start and/or stop time(s) for the clip you want.</li>
	<li>Save the clip.</li>
	<li>Repeat the above two steps for each clip you wish to make from the selected video.</li>
	<li>Save the playlist for future enjoyment or to share.
	<div class=tip><b>Note:</b> It is wise to save the playlist of clips as you
	develop it, and not wait until the playlist is complete.
	VLC has on occasion become unresponsive when using this
	extension.</div>
	</li>
	<br/>
	</ul>
	<hr><br/>

	<b>Details:</b>

	<ul>
	<li><a class=highlight>To load files</a> use VLC's
		<b>Open File...</b>,
	<b>Open Directory...</b> and similar menu items.
	You can also drag and drop files onto the playlist.</li>
	</li><br/>

	<li><a class=highlight>To set start and stop times</a> for a clip from an item, start playing it
	(or pause if you wish) then use a
	<b class=button>Start = </b> or <b class=button>Stop = </b> button to set them at:
	<ul>
	<li><b class=button>Curr.</b> - the current time in the file.</li>
	<li><b class=button>Show</b> - the time in the <b class=button>Show</b> text entry box </li>
	<li><b class=button>Begin</b> or <b class=button>End</b> - the beginning or end of the file</li>
	</ul><br/>
	It is sometimes convenient, while the file is playing, to press the <b class=button>Start = Curr.</b> button 
	when it gets to the beginning of the clip you want, let it continue to play, and press the 
	<b class=button>Stop = Curr.</b> button when it gets to where you want the clip to end.<br/><br/>

	If the <b>Start</b> or <b>Stop</b> time is not set (shown as '<b>--:--</b>'), playback will start at the beginning
	or or stop at the end of the file.
	</li><br/>
	<li><a class=highlight>To go to a <b>specific time</b></a>, enter that time in the
	<b class=button>Show</b> text entry box, 
	then press the <b class=button>Start = Show</b> or 
	<b class=button>Stop = Show</b> button.
	<br/><br/>

	Several time formats are available: 
	<br/> <br/>

	1h23m45s, 1:23:45, 1+23+45 and 5025 each mean
		"1 hour, 23 minutes and 45 seconds" from the beginning of the file.
	<br/><br/>

	Likewise, 1m23.45s,  1:23.45, 1+23.45 and 83.45 each mean "1 minute and 23.45 seconds"
	from the beginning.
	<br/><br/>

	<a class=highlight>If a time is entered which is past the end of the item</a>, the time in the
	<b class=button>Show</b> box will be set to the item's end. 
	<br/><br/>   

	<a class=highlight>A <b>negative</b> value (like <b>-1m17s</b>) will set the time
		to that amount BACK</a> from the END of the file. 
	After typing a negative value and pressing Enter, the time shown in the <b class=button>Show</b> box will be updated 
	to show the time from the beginning of the video. 
	<br/><br/>

	<a class=highlight>If a negative time is entered which is before the beginning of 
	the item</a>, the time in the
	<b class=button>Show</b> box will be set to the beginning (0.00). 
	<br/><br/>
	<li><a class=highlight>To jump forward or backward</a> 
	(relative to the current time) press the 
	<b class=button>&gt;&gt;</b> or
	<b class=button>&lt;&lt;</b> button. 
	The time to jump is selected in the dropdown box to the left of those buttons.
	<br/><br/>

	If the jump time selected is 1 frame and the video is not paused, 
	it will be paused.
	</li><br/>
	<li><a class=highlight>The <b class=button>Clip directory</b> box holds 
	the name of the directory</a> where the next clip will be stored.
	That directory is initially set to an item's directory 
	when that item is selected. You may enter the name of any
	existing directory.
	</li><br/>
	<li><a class=highlight>The <b class=button>Clip name</b> box holds 
	the name of the next clip to be saved</a>.
	The name is initially set to the selected item's base name plus underscore 
	when that item is selected. 
	For example, if the item's name is 'Fishing.mp4', the initial clip name will be
	'Fishing_'. You may then add '1' and save clip 'Fishing_1.mp4', add 'LakeLouise' to 
	save clip 'Fishing_LakeLouise.mp4', etc.
	You may enter any valid name.
	<br/>

	<a class=highlight>Clips are saved in the same format, and using the same 
	extension, as the source item.</a> 
	That is, clips from 'Fishing.mp4' will be saved as '.mp4' files. Clips from 'Travel.ogg'
	will be saved as '.ogg' files.  
	</li><br/>
	<li><a class=highlight> Press the <b class=button>Save clip</b> button to save the clip</a>
	with specified <b>Start</b> and <b>Stop</b> times in the file specified in the
	<b class=button>Clip directory</b> and <b class=button>Clip name</b> text boxes.<br/>
	</li><br/>
	<li><a class=highlight> If the <b class=button>Add clip to Playlist</b> box  is checked</a>,
	each clip that is saved will be added to the playlist.
	</li><br/>
	<li><a class=highlight>After a clip is saved, if the <b class=button>Auto Advance</b> box is checked</a>
	<ul> 
	<li>and the clip name ends in _[number] or _[lowercase letter] (like hometown_3 or fido_b)</li>
	<li>and the clip's Stop time is not the end of the item</li>
	</ul>
	the blanks for the next clip will be filled as follows: 
	<ul>
	<li>The <b class=button>Start</b> time and <b class=button>Stop</b> time will be set to the <b>Stop</b>
	time of the saved clip.</li>
	<li>The <b class=button>Clip name</b> will be set to the next name in the sequence. 
	For example, hometown_4 will be after hometown_3, and fido_d will be after fido_c.</li>
	</ul><br/>
	The position within the file will be set to the <b>Stop</b>
	time of the saved clip. If the video was playing when the clip was saved, 
	playing will start at the <b>Stop</b> time of the saved clip.
	<br/><br/>
	Auto Advance is especially convenient when selecting several consecutive (or nearly consecutive) 
	clips from one item.
	<br/> 
	<div><a class=highlight><b>NOTE:</b> In Windows operating systems, file names are not case-sensitive.</a>
	Therefore, the system will see fido_b and fido_B and FIDO_B as all being the same name, and will not
	allow you to save both fido_b and fido_B, etc.
	</div>
	</li><br/>

	<li><a class=highlight>To set the name of the item
	as it appears in the playlist</a> and on the VLC title bar, set the "Title" 
	value in the media file. That value can be changed by selecting "Media
	Information" in VLC's "Tools" menu.
	</li>
	</ul> 

	<div id=footer>
	<b>VLC Lua scripting:</b> <a href="http://forum.videolan.org/viewtopic.php?f=29&t=98644#p330318">Getting started?</a><br />
	Please, visit us and bring some new ideas.<br />
	Learn how to write your own scripts and share them with us.<br />
	Help to build a happy VLC community :o)
	</div>
			]]
	help_html = dlg:add_html(help_text,1,help_row + 1,3,1)
	helpx_btn = dlg:add_button("HELP (x)", click_HELPx,help_col,help_row,1,1)
	dlg:update()
end

function click_HELPx()
	dlg:del_widget(help_html)
	dlg:del_widget(helpx_btn)
	help_html=nil
	helpx_btn=nil
	dlg:update()
end

------------------------ TIME FUNCTIONS --------------------------

function current_time()
	-- returns current time in the media (point to which it has been played)

	local curr_t
	local input = vlc.object.input()
	if (not input) or (vlc.playlist.status() == 'stopped') then
		curr_t = nil
	else
		curr_t = vlc.var.get(input, "time")
	end
	if (curr_t > 100000) then
		curr_t = curr_t * 0.000001
	end
	--inform("current_time() curr_t = " .. curr_t)
	return curr_t
end

function parse_time(when)

	--inform("parse_time() when = " .. tostring(when))
	local time = no_time

	if (when == nil) or (when == no_time) then
		time = nil
	elseif (when == "curr") then
		time = current_time()
	elseif (type(when) == "string") then
		time = seconds_from_string(when)
		if (time == nil) then
			error("Invalid time string " .. when)
		end
	elseif (type(when) == "number") then
		time = when
	else
		error("Cannot parse time from " .. type(when) .. " " .. tostring(when))
	end
	return time
end

function hms_from_string(str)

	if not str then
		return nil, nil, nil
	end

	-- strip leading and trailing spaces
	str = string.match(str, "^%s*([^%s]*)%s*$")
	if not str then
		return nil, nil, nil
	end

	local pattern0 = "^(%d+%.?%d*)$"
	local pattern1a = "^(%d+):(%d+%.?%d*)$"
	local pattern1 = "^(%d+):(%d+):(%d+%.?%d*)$"
	local pattern2 = "^(%d+)[Hh](%d+)[Mm](%d+%.?%d*)[Ss]$"
	local pattern2a = "^(%d+)[Hh](%d+%.?%d*)[Mm]$"
	local pattern2b = "^(%d+)[Mm](%d+%.?%d*)[Ss]$"
	local pattern3a = "^(%d+)%+(%d+%.?%d*)$"
	local pattern3 = "^(%d+)%+(%d+)%+(%d+%.?%d*)$"
	local h, m, s

	s = string.match(str, pattern0)
	if s then
		return 0, 0, tonumber(s)
	end

	m, s = string.match(str, pattern1a)
	if m and s then
		return 0, tonumber(m), tonumber(s)
	end

	h, m, s = string.match(str, pattern1)
	if h and m and s then
		return tonumber(h), tonumber(m), tonumber(s)
	end

	h, m = string.match(str, pattern2a)
	if h and m then
		return tonumber(h), tonumber(m), 0
	end

	m, s = string.match(str, pattern2b)
	if m and s then
		return 0, tonumber(m), tonumber(s)
	end

	h, m, s = string.match(str, pattern2)
	if h and m and s then
		return tonumber(h), tonumber(m), tonumber(s)
	end

	m, s = string.match(str, pattern3a)
	if m and s then
		return 0, tonumber(m), tonumber(s)
	end

	h, m, s = string.match(str, pattern3)
	if h and m and s then
		return tonumber(h), tonumber(m), tonumber(s)
	end

	return nil, nil, nil
end

function seconds_from_string(str)

	local is_neg = false
	local h, m, s, sec

	if (not str) then
		return nil
	end

	if (str == ".") then
		return current_time()
	end

	if string.sub(str, 1, 1) == "-" then
		is_neg = true
		str = string.sub(str, 2, string.len(str))
	end

	h, m, s = hms_from_string(str)
	if (not s) then
		return nil
	else
		sec = (3600 * h) + (60 * m) + s
	end

	if (is_neg) then
		sec = -sec
	end

	return sec
end

function string_from_seconds(seconds)

	local str
	local h
	local hm_str = ""
	local m
	local s
	local s_str
	local sign = ""

	seconds = tonumber(seconds)

	if (not seconds) then
		return no_time
	end

	if (seconds < 0) then
		sign = "-"
		seconds = -seconds
	end

	h = math.floor(seconds / 3600)
	m = math.floor((seconds % 3600) / 60)
	s = seconds % 60

	s_str = string.format("%05.2f", s)
	--inform("string_from_seconds("..seconds..") = " .. s_str)

	if (h == 0) then
		if (m > 0) then
			hm_str = string.format("%d:", m)
		else
			-- we have only seconds
			s_str = string.format("%.2f", s)
			--inform("string_from_seconds("..seconds..") = " .. s_str)
		end
	else
		hm_str = string.format("%d:%02d:", h, m)
	end

	-- -- remove trailing zeroes and possible trailing decimal point
	-- if s_str:sub(-3) == ".00" then
	-- 	s_str = s_str:sub(1, s_str:len() - 3)
	-- elseif s_str:sub(-1) == "0" then
	-- 	s_str = s_str:sub(1, s_str:len() - 1)
	-- end

	return sign .. hm_str .. s_str
end

--[[
adapted from https://fhug.org.uk/kb/code-snippet/split-a-filename-into-path-file-and-extension/	

Sample of use:
	path,file,extension = SplitFilename(fhGetPluginDataFileName())
	print(path,file,extension)

split_filename("C:\users\documents\myfile.txt") will return 3 values as follows:
	C:\users\documents\
	myfile.txt
	txt
	
If it is required to omit the extension from the returned filename portion then adjust the final return statement by moving the filename capture closing ) earlier before the %. separator:

return strFilename:match("^(.-)([^\\/]-)%.([^\\/%.]-)%.?$")	
]]
function split_filename(strFilename)
	--inform("splitting filename " .. strFilename)
	-- Returns the Path, Filename, and Extension as 3 values
	local path, name, extension

	-- to get name with extension (for example from "C:\users\documents\myfile.txt") "C:\users\documents\", "myfile.txt", "txt"
	-- path, name, extension = strFilename:match("(.-)([^\\/]-([^\\/%.]+))$")

	-- to get name without extension (from "C:\users\documents\myfile.txt" => "C:\users\documents\", "myfile", "txt"
	path, name, extension = strFilename:match("^(.-)([^\\/]-)%.([^\\/%.]-)%.?$")	
	--inform("split_filename: path, name, extension =  " .. path .. ", " .. name .. ", " .. extension)
	return path, name, extension
end

function file_exists(path)
	--inform("starting file_exists()")
	local f, err_msg, err_num = vlc.io.open(path, 'r')
	--inform("f = " .. tostring(f) .. " " .. tostring(err_msg) .. " " .. tostring(err_num))
	if f then 
		f:close()
		return true
	else 
		return false
	end
end

function dir_exists(path)
	--inform("starting dir_exists()")
	local files_in_dir, err_msg, err_num = vlc.io.readdir(path)
	--inform("files_in_dir = " .. tostring(files_in_dir) .. " " .. tostring(err_msg) .. " " .. tostring(err_num))
	-- based on example from https://verghost.com/vlc-lua-docs/m/io/ 
	if files_in_dir then
		for i,f in pairs(files_in_dir) do
			--inform("File #" .. i .. " in directory is: " .. f)
		end
		return true
	else
		return false
	end
end
