# clipper2
Clipper2 is a VLC extension to create portions (clips) of files. 
It provides facilities to jump backwards and forwards within a video by 1 frame, 1 second, 10 seconds or 1 minute. 
It includes a feature to create successive clips from a file (like fido_a, fido_b, fido_c, etc.).
It calls the external ffmpeg program to create the clips.

INSTALLATION:
Put the clipper2.lua file in the VLC subdir /lua/extensions, by default:
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
