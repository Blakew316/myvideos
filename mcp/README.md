# My Videos for Claude Code

An MCP server that lets Claude Code control the My Videos app: download links, follow
progress (with yt-dlp's exact error when something fails), search the library, and
manage followed channels.

It uses the app's local companion connection, so My Videos must be running with
**Settings › Devices › Use My Videos on iPhone and iPad** turned on. The pairing token is
read from the app's preferences; there's nothing else to set up. Python 3 standard
library only.

```sh
claude mcp add --scope user my-videos -- python3 "/path/to/video grabber/mcp/my_videos_mcp.py"
```

Tools: `app_status`, `preview_link`, `download`, `download_status`, `manage_download`,
`clear_finished`, `search_library`, `remove_from_library`, `list_channels`,
`follow_channel`, `check_channel`, `unfollow_channel`.

Set `MYVIDEOS_PORT` if the app's companion server isn't on port 8765.
