# YouTube Downloader Script

A Bash script to download YouTube videos or playlists using `yt-dlp` on Termux or other Unix-like systems.

## Features
- Downloads videos in various formats (best video+audio, 1440p, audio-only, MP3).
- Saves files to a configurable folder (default: `~/storage/downloads/MyYoutubeGrabs`).
- Embeds subtitles for video downloads.
- Handles playlists and single videos.

## Prerequisites
- **Termux** (or another Unix-like environment).
- Install dependencies:
  ```bash
  pkg install python ffmpeg
  pip install yt-dlp
