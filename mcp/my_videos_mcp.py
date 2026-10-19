#!/usr/bin/env python3
"""
My Videos MCP server: lets Claude Code drive the My Videos Mac app.

It talks to the app's local companion API (the one the iPhone app uses), so My Videos
must be running with Settings > Devices > "Use My Videos on iPhone and iPad" turned on.
The pairing token is read from the app's preferences, so there is nothing to configure.

Standard library only. Register it with:
    claude mcp add my-videos -- python3 "/path/to/mcp/my_videos_mcp.py"
"""

import json
import os
import plistlib
import sys
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "com.wholesalepayments.video-grabber"
PORT = int(os.environ.get("MYVIDEOS_PORT", "8765"))
BASE = f"http://127.0.0.1:{PORT}"
PROTOCOL_VERSION = "2025-06-18"

NOT_RUNNING = ("My Videos isn't reachable. Open the app and turn on Settings > Devices > "
               "\"Use My Videos on iPhone and iPad\" (that's the local connection this uses).")


# MARK: - App API

class AppError(Exception):
    pass


def token():
    path = os.path.expanduser(f"~/Library/Preferences/{BUNDLE_ID}.plist")
    try:
        with open(path, "rb") as f:
            value = plistlib.load(f).get("companionToken")
    except (OSError, plistlib.InvalidFileException):
        value = None
    if not value:
        raise AppError(NOT_RUNNING)
    return value


def call(method, path, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token()}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        try:
            message = json.loads(error.read()).get("error")
        except ValueError:
            message = None
        raise AppError(message or f"My Videos answered {error.code}.")
    except (urllib.error.URLError, ConnectionError, TimeoutError):
        raise AppError(NOT_RUNNING)
    return json.loads(raw) if raw else {}


# MARK: - Tools

def job_summary(job):
    line = f"[{job.get('phase')}] {job.get('title')} - {job.get('status')}"
    details = [f"id: {job.get('id')}"]
    if job.get("url"):
        details.append(f"link: {job['url']}")
    if job.get("phase") == "failed" and job.get("error"):
        details.append(f"yt-dlp: {job['error']}")
    for path in job.get("files") or []:
        details.append(f"file: {path}")
    return line + "\n  " + "\n  ".join(details)


def tool_app_status(_):
    status = call("GET", "/api/status")
    missing = status.get("missingTools") or []
    ready = "ready to download" if status.get("ready") else f"missing {', '.join(missing)}"
    return f"My Videos {status.get('version')} on {status.get('mac')}: {ready}."


def tool_preview_link(args):
    query = urllib.parse.urlencode({"url": args["url"]})
    info = call("GET", f"/api/preview?{query}", timeout=120)
    lines = [f"Title: {info.get('title')}"]
    for key, label in (("uploader", "Channel"), ("site", "Site")):
        if info.get(key):
            lines.append(f"{label}: {info[key]}")
    if info.get("duration"):
        minutes, seconds = divmod(int(info["duration"]), 60)
        lines.append(f"Length: {minutes}:{seconds:02d}")
    if info.get("isPlaylist"):
        lines.append(f"Playlist with {info.get('playlistCount') or 'several'} items")
    if info.get("existing"):
        lines.append("Already in the library.")
    return "\n".join(lines)


def tool_download(args):
    body = {"url": args["url"], "format": args.get("format", "video")}
    quality = {"best": "Best quality", "1080p": "1080p", "720p": "720p"}.get(args.get("quality", "best"))
    if quality:
        body["quality"] = quality
    if args.get("playlist"):
        body["playlist"] = True
        if args.get("playlist_limit"):
            body["playlistLimit"] = int(args["playlist_limit"])
    state = call("POST", "/api/download", body)
    jobs = state.get("jobs") or []
    queued = next((j for j in reversed(jobs) if j.get("url") == args["url"]), jobs[-1] if jobs else None)
    if not queued:
        return "Queued."
    return "Queued. Use download_status to follow it.\n" + job_summary(queued)


def tool_download_status(_):
    state = call("GET", "/api/state")
    jobs = state.get("jobs") or []
    if not jobs:
        return "No downloads in the queue."
    header = f"{state.get('pending', 0)} in progress, {state.get('paused', 0)} paused."
    return header + "\n\n" + "\n\n".join(job_summary(j) for j in reversed(jobs))


def tool_manage_download(args):
    call("POST", f"/api/jobs/{args['id']}/{args['action']}")
    return f"Done: {args['action']}."


def tool_clear_finished(_):
    call("POST", "/api/queue/clear")
    return "Cleared finished and failed downloads from the queue."


def tool_search_library(args):
    items = call("GET", "/api/history").get("items") or []
    query = (args.get("query") or "").lower()
    kind = args.get("kind", "all")
    matches = []
    for item in items:
        if kind == "video" and item.get("isAudio"):
            continue
        if kind == "audio" and not item.get("isAudio"):
            continue
        text = f"{item.get('title', '')} {item.get('uploader', '')}".lower()
        if query and query not in text:
            continue
        matches.append(item)
    limit = int(args.get("limit", 25))
    if not matches:
        return "Nothing in the library matches." if items else "The library is empty."
    lines = []
    for item in matches[:limit]:
        size = f"{item['bytes'] / 1_000_000:.1f} MB" if item.get("bytes") else "size unknown"
        where = item.get("path") or "file missing on this Mac"
        lines.append(f"{item.get('title')} - {item.get('uploader') or 'unknown channel'} "
                     f"({'audio' if item.get('isAudio') else 'video'}, {size}, added {item.get('date', '')[:10]})\n"
                     f"  id: {item.get('id')}\n  file: {where}\n  source: {item.get('source')}")
    more = f"\n\n...and {len(matches) - limit} more." if len(matches) > limit else ""
    return f"{len(matches)} match(es):\n\n" + "\n\n".join(lines) + more


def tool_remove_from_library(args):
    call("DELETE", f"/api/history/{args['id']}")
    return "Removed from the library. The file itself was left on disk."


def tool_list_channels(_):
    data = call("GET", "/api/subscriptions")
    items = data.get("items") or []
    if not items:
        return "Not following any channels."
    lines = []
    for sub in items:
        state = "on" if sub.get("enabled", True) else "paused"
        lines.append(f"{sub.get('title')} ({state})\n  id: {sub.get('id')}\n  link: {sub.get('url')}")
    return "\n\n".join(lines)


def tool_follow_channel(args):
    body = {"url": args["url"], "format": "audio" if args.get("format") == "audio" else "Best quality",
            "latest": int(args.get("download_latest", 0))}
    call("POST", "/api/subscriptions", body, timeout=120)
    return "Following. New uploads will download automatically."


def tool_check_channel(args):
    call("POST", f"/api/subscriptions/{args['id']}/check", {}, timeout=180)
    return "Checked for new uploads. Use download_status to see anything that started."


def tool_unfollow_channel(args):
    call("DELETE", f"/api/subscriptions/{args['id']}")
    return "Unfollowed. Downloads already saved were kept."


def schema(properties=None, required=None):
    return {"type": "object", "properties": properties or {}, "required": required or []}


URL = {"type": "string", "description": "Web address of the video, playlist, song or channel."}
ID = {"type": "string", "description": "The id shown by download_status, search_library or list_channels."}

TOOLS = {
    "app_status": (tool_app_status, "Check that My Videos is running and ready to download.", schema()),
    "preview_link": (tool_preview_link, "Look up a link's title, channel and length without downloading it.",
                     schema({"url": URL}, ["url"])),
    "download": (tool_download, "Download a video, song or playlist with My Videos.", schema({
        "url": URL,
        "format": {"type": "string", "enum": ["video", "audio"], "default": "video"},
        "quality": {"type": "string", "enum": ["best", "1080p", "720p"], "default": "best",
                    "description": "Video quality (ignored for audio)."},
        "playlist": {"type": "boolean", "default": False, "description": "Download the whole playlist."},
        "playlist_limit": {"type": "integer", "description": "Only the first N playlist items."},
    }, ["url"])),
    "download_status": (tool_download_status, "List downloads in the queue with progress, saved files, "
                        "and yt-dlp's exact error for any that failed.", schema()),
    "manage_download": (tool_manage_download, "Pause, resume, cancel, retry or remove a download.", schema({
        "id": ID,
        "action": {"type": "string", "enum": ["pause", "resume", "cancel", "retry", "remove"]},
    }, ["id", "action"])),
    "clear_finished": (tool_clear_finished, "Clear finished and failed downloads from the queue.", schema()),
    "search_library": (tool_search_library, "Search downloaded videos and songs by title or channel.", schema({
        "query": {"type": "string", "description": "Text to find in titles or channel names. Empty lists everything."},
        "kind": {"type": "string", "enum": ["all", "video", "audio"], "default": "all"},
        "limit": {"type": "integer", "default": 25},
    })),
    "remove_from_library": (tool_remove_from_library, "Remove an item from the library (keeps the file).",
                            schema({"id": ID}, ["id"])),
    "list_channels": (tool_list_channels, "List followed channels and playlists.", schema()),
    "follow_channel": (tool_follow_channel, "Follow a channel or playlist so new uploads download automatically.",
                       schema({
                           "url": URL,
                           "format": {"type": "string", "enum": ["video", "audio"], "default": "video"},
                           "download_latest": {"type": "integer", "default": 0,
                                               "description": "Also download this many of the latest uploads now."},
                       }, ["url"])),
    "check_channel": (tool_check_channel, "Check a followed channel for new uploads now.", schema({"id": ID}, ["id"])),
    "unfollow_channel": (tool_unfollow_channel, "Stop following a channel (keeps its downloads).",
                         schema({"id": ID}, ["id"])),
}


# MARK: - MCP over stdio (JSON-RPC 2.0, one message per line)

def reply(message_id, result=None, error=None):
    message = {"jsonrpc": "2.0", "id": message_id}
    if error is not None:
        message["error"] = error
    else:
        message["result"] = result
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def handle(message):
    method = message.get("method")
    message_id = message.get("id")
    params = message.get("params") or {}
    if method == "initialize":
        reply(message_id, {
            "protocolVersion": params.get("protocolVersion", PROTOCOL_VERSION),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "my-videos", "version": "1.0"},
            "instructions": "Controls the My Videos Mac app: download links, follow progress and errors, "
                            "search the library, and manage followed channels.",
        })
    elif method == "tools/list":
        reply(message_id, {"tools": [
            {"name": name, "description": description, "inputSchema": input_schema}
            for name, (_, description, input_schema) in TOOLS.items()
        ]})
    elif method == "tools/call":
        name = params.get("name")
        if name not in TOOLS:
            reply(message_id, error={"code": -32602, "message": f"Unknown tool: {name}"})
            return
        try:
            text, is_error = TOOLS[name][0](params.get("arguments") or {}), False
        except AppError as error:
            text, is_error = str(error), True
        except (KeyError, ValueError) as error:
            text, is_error = f"Missing or invalid argument: {error}", True
        reply(message_id, {"content": [{"type": "text", "text": text}], "isError": is_error})
    elif method == "ping":
        reply(message_id, {})
    elif message_id is not None:
        reply(message_id, error={"code": -32601, "message": f"Method not found: {method}"})
    # Notifications (no id), such as notifications/initialized, need no answer.


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            reply(None, error={"code": -32700, "message": "Parse error"})
            continue
        handle(message)


if __name__ == "__main__":
    main()
