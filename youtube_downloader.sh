#!/data/data/com.termux/files/usr/bin/bash

# === Configuration ===
# Default destination is now a shared storage path.
# Ensure you have run 'termux-setup-storage' once in Termux.
DEFAULT_DEST_FOLDER="$HOME/storage/downloads/MyYoutubeGrabs"

# Maximum length for the 'title' part of the filename.
# yt-dlp will truncate the title to this many characters.
MAX_FILENAME_TITLE_LENGTH=100

# === Helper Functions ===

# Function to ensure yt-dlp and ffmpeg are installed
ensure_dependencies() {
    local dependencies_met=true

    if ! command -v yt-dlp &>/dev/null; then
        echo "INFO: yt-dlp not found."
        dependencies_met=false
    fi

    if ! command -v ffmpeg &>/dev/null; then
        echo "INFO: ffmpeg not found."
        dependencies_met=false
    fi

    if [ "$dependencies_met" = true ]; then
        # echo "DEBUG: All dependencies (yt-dlp, ffmpeg) are already installed."
        return 0
    fi

    echo "Attempting to install missing packages (python, ffmpeg, yt-dlp)..."
    if command -v pkg &>/dev/null; then
        pkg install -y python ffmpeg || {
            echo "ERROR: Failed to install python or ffmpeg using 'pkg'. Please install them manually."
            exit 1
        }
        if pip install --upgrade yt-dlp; then
            echo "INFO: yt-dlp installed/upgraded successfully via pip."
        else
            echo "ERROR: Failed to install/upgrade yt-dlp via pip. Please try installing it manually."
            exit 1
        fi
    else
        echo "ERROR: Termux 'pkg' command not found. Cannot automatically install dependencies."
        echo "Please install Python, ffmpeg, and yt-dlp (e.g., using pip) manually."
        exit 1
    fi

    # Final check
    if ! command -v yt-dlp &>/dev/null || ! command -v ffmpeg &>/dev/null; then
        echo "ERROR: Dependencies still missing after installation attempt. Exiting."
        exit 1
    fi
    echo "INFO: Dependencies installed successfully."
}

# Function to prompt user for YouTube URL
prompt_url() {
    read -r -p "Enter YouTube video or playlist URL: " video_url
    if [[ -z "$video_url" ]]; then
        echo "ERROR: No URL entered. Exiting."
        exit 1
    fi
}

# Function to prompt user for quality and set format
prompt_quality_and_format() {
    echo "Choose the download option:"
    echo "  1. Best video + best audio (merged into MP4)"
    echo "  2. Best single file (MP4, highest quality Video+Audio pre-merged stream)"
    echo "  3. 1440p max video + best audio (merged into MP4)"
    echo "  4. Best audio only (default container, typically M4A or Opus)"
    echo "  5. Best audio only (converted to MP3)"
    read -r -p "Enter option (1-5): " quality_choice

    # Initialize format_selection and an array for any extra yt-dlp arguments
    format_selection=""
    yt_dlp_extra_args=()

    case $quality_choice in
        1) format_selection="bv*+ba/b";; # Best video, best audio, /b for best overall if specific combo fails
        2) format_selection="best";;     # Single best quality file
        3) format_selection="bestvideo[height<=1440]+bestaudio/best[height<=1440]";;
        4) format_selection="bestaudio/ba";; # 'ba' is an alias for 'bestaudio'
        5) format_selection="bestaudio/ba"; yt_dlp_extra_args=(--extract-audio --audio-format mp3 --audio-quality "0");; # VBR quality 0-9, 0 is best
        *) echo "ERROR: Invalid option selected. Exiting."; exit 1;;
    esac
}

# Function to prompt for destination folder
prompt_destination() {
    read -r -p "Enter the destination folder (default: $DEFAULT_DEST_FOLDER): " dest_folder_input
    # If input is empty, use default; otherwise, use input
    dest_folder="${dest_folder_input:-$DEFAULT_DEST_FOLDER}"

    # Expand ~ (tilde) to $HOME directory if it's at the start of the path
    dest_folder="${dest_folder/#\~/$HOME}"

    # Create the destination folder if it doesn't exist
    if ! mkdir -p "$dest_folder"; then
        echo "ERROR: Could not create destination folder: $dest_folder"
        echo "Please check permissions and the validity of the path."
        exit 1
    fi
    # Convert to absolute path for consistent logging (optional, but good practice)
    dest_folder="$(cd "$dest_folder" && pwd)" # cd and pwd to resolve to canonical path
    echo "INFO: Files will be saved to: $dest_folder"
}


# === Main Script Execution ===

ensure_dependencies
prompt_url
prompt_quality_and_format # This sets $format_selection, $quality_choice, and $yt_dlp_extra_args
prompt_destination        # This sets $dest_folder

# Construct the output template for yt-dlp.
# This version uses a simpler playlist index format that results in "NA_" for single videos.
# It was chosen because it bypassed the previous '%\x00(' errors in your environment.
output_template="$dest_folder/%(playlist_index)s_%(title).${MAX_FILENAME_TITLE_LENGTH}s.%(ext)s"

# ---
# Note on a more advanced template (optional, try if the simple one is too basic):
# If you want to try the more advanced template again for cleaner filenames
# (e.g., "01 - Title.mp4" for playlists, "Title.mp4" for single videos)
# ensure you type it VERY carefully to avoid hidden characters:
# output_template="$dest_folder/%(playlist_index?%(playlist_index)02d - :)s%(title).${MAX_FILENAME_TITLE_LENGTH}s.%(ext)s"
# ---

# Base yt-dlp command array
yt_dlp_base_cmd=(
    yt-dlp
    -f "$format_selection"
    --ignore-errors             # Continue downloading other videos in a playlist if one fails
    --no-warnings               # Suppress yt-dlp warnings like "Ignoring subtitle chapters"
    # --progress                # Uncomment for a progress bar (can be verbose)
    # -q                        # Uncomment for quiet mode (less output)
    -o "$output_template"
    # --ppa "ffmpeg: -loglevel warning" # Reduce ffmpeg's verbosity during merges/conversions
)

# Add video-specific options if the choice is NOT audio-only (options 4 or 5)
if [[ "$quality_choice" -ne 4 && "$quality_choice" -ne 5 ]]; then
    yt_dlp_base_cmd+=(
        --embed-subs            # Embed subtitles into the video container (if supported)
        --sub-langs "en.*,en"   # Download English subtitles (all variants like en-US, en-GB)
        --write-subs            # Also write subtitles to a separate file (as backup/alternative)
        --merge-output-format "mp4" # If merging formats (e.g., video+audio), output as MP4
    )
fi

# Add any extra arguments determined by quality selection (e.g., for MP3 conversion)
if [ ${#yt_dlp_extra_args[@]} -gt 0 ]; then
    yt_dlp_base_cmd+=("${yt_dlp_extra_args[@]}")
fi

# Add the URL to the command
yt_dlp_base_cmd+=("$video_url")

# Announce action
echo "--------------------------------------------------"
echo "Starting download process..."
echo "  URL: $video_url"
echo "  Quality option: $quality_choice"
echo "  Format string: $format_selection ${yt_dlp_extra_args[*]}" # Show extra args if any
echo "  Saving to: $dest_folder"
# For debugging, you can print the full command:
# echo "  Full command: ${yt_dlp_base_cmd[*]}"
echo "--------------------------------------------------"

# Execute the yt-dlp command
if "${yt_dlp_base_cmd[@]}"; then
    echo "" # Newline for cleaner separation after yt-dlp output
    echo "✅ Download process completed."
    echo "   Files should be located in: $dest_folder"
else
    echo "" # Newline for cleaner separation
    echo "❌ yt-dlp command failed with exit code $?."
    echo "   There might have been errors during the download."
    echo "   Please check the output above for details."
    echo "   Partially downloaded files, if any, might be in: $dest_folder"
    echo "   (or your current directory if the -o path specification failed early)."
fi

exit 0

