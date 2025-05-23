#!/data/data/com.termux/files/usr/bin/bash

# === Configuration ===
# Default destination is now a shared storage path.
# Ensure you have run 'termux-setup-storage' once in Termux.
DEFAULT_DEST_FOLDER="$HOME/storage/downloads/MyYoutubeGrabs"

# Maximum length for the 'title' part of the filename.
# yt-dlp will truncate the title to this many characters.
MAX_FILENAME_TITLE_LENGTH=100

# === Helper Functions ===

# Function to ensure yt-dlp, ffmpeg, and termux-api are installed
ensure_dependencies() {
    local core_dependencies_met=true
    local termux_api_found=true

    if ! command -v yt-dlp &>/dev/null; then
        echo "INFO: yt-dlp not found."
        core_dependencies_met=false
    fi

    if ! command -v ffmpeg &>/dev/null; then
        echo "INFO: ffmpeg not found."
        core_dependencies_met=false
    fi

    if ! command -v termux-notification &>/dev/null; then
        echo "INFO: termux-notification (from termux-api) not found."
        termux_api_found=false
    fi

    if [ "$core_dependencies_met" = true ] && [ "$termux_api_found" = true ]; then
        # echo "DEBUG: All dependencies are already installed."
        return 0
    fi

    echo "Attempting to install missing packages..."
    if command -v pkg &>/dev/null; then
        local packages_to_install=()
        if [ "$core_dependencies_met" = false ]; then
            # yt-dlp needs python, ffmpeg is separate
            # Check if python is needed for pip for yt-dlp
            if ! command -v python &>/dev/null && ! command -v yt-dlp &>/dev/null; then
                 packages_to_install+=("python")
            fi
            if ! command -v ffmpeg &>/dev/null; then
                packages_to_install+=("ffmpeg")
            fi
        fi

        if [ "$termux_api_found" = false ]; then
            packages_to_install+=("termux-api")
        fi

        if [ ${#packages_to_install[@]} -gt 0 ]; then
             echo "INFO: Installing with pkg: ${packages_to_install[*]}"
             pkg install -y "${packages_to_install[@]}" || {
                echo "ERROR: Failed to install some packages with pkg. Please review messages above."
             }
        fi

        # Install/upgrade yt-dlp via pip if still not found or to ensure it's upgraded
        if ! command -v yt-dlp &>/dev/null || [ "$core_dependencies_met" = false ]; then # Force pip install if core_dependencies_met was false
            if pip install --upgrade yt-dlp; then
                echo "INFO: yt-dlp installed/upgraded successfully via pip."
            else
                echo "ERROR: Failed to install/upgrade yt-dlp via pip. Please try installing it manually."
                # yt-dlp is crucial, so we might want to exit if it fails
                # For now, we let the final check handle it.
            fi
        fi
    else
        echo "ERROR: Termux 'pkg' command not found. Cannot automatically install dependencies."
        echo "Please install Python, ffmpeg, termux-api, and yt-dlp (e.g., using pip) manually."
        exit 1 # Cannot proceed without pkg if dependencies are missing
    fi

    # Final check for core components
    if ! command -v yt-dlp &>/dev/null || ! command -v ffmpeg &>/dev/null; then
        echo "ERROR: Core dependencies (yt-dlp, ffmpeg) still missing after installation attempt. Exiting."
        exit 1
    fi
    # For termux-notification, a warning is sufficient if it's still missing
    if ! command -v termux-notification &>/dev/null; then
        echo "WARNING: termux-notification still not found. Android notifications will be skipped."
    fi
    echo "INFO: Dependency check completed."
}


# Function to prompt user for YouTube URL(s)
prompt_url() {
    read -r -p "Enter YouTube video or playlist URL(s) (space-separated): " video_url_line
    if [[ -z "$video_url_line" ]]; then
        echo "ERROR: No URL(s) entered. Exiting."
        exit 1
    fi
    read -r -a video_urls_to_process <<< "$video_url_line"
}


# Function to prompt user for quality and set format
prompt_quality_and_format() {
    echo "Choose the download option:"
    echo "  1. Best video + best audio (merged into MP4)"
    echo "  2. Best single file (MP4, highest quality Video+Audio pre-merged stream)"
    echo "  3. 1440p max video + best audio (merged into MP4)  <--- Approx 2K resolution"
    echo "  4. Best audio only (default container, typically M4A or Opus)"
    echo "  5. Best audio only (converted to MP3)"
    read -r -p "Enter option (1-5) [Press Enter for default: 3 (1440p/2K)]: " quality_choice

    if [[ -z "$quality_choice" ]]; then
        echo "INFO: No quality selected, using default option 3 (1440p/2K)."
        quality_choice="3"
    fi

    format_selection=""
    yt_dlp_extra_args=()

    case $quality_choice in
        1) format_selection="bv*+ba/b";;
        2) format_selection="best";;
        3) format_selection="bestvideo[height<=1440]+bestaudio/best[height<=1440]";;
        4) format_selection="bestaudio/ba";;
        5) format_selection="bestaudio/ba"; yt_dlp_extra_args=(--extract-audio --audio-format mp3 --audio-quality "0");;
        *) echo "ERROR: Invalid option selected ('$quality_choice'). Please choose a number from 1 to 5. Exiting."; exit 1;;
    esac
}

# Function to prompt for destination folder
prompt_destination() {
    read -r -p "Enter the destination folder (default: $DEFAULT_DEST_FOLDER): " dest_folder_input
    dest_folder="${dest_folder_input:-$DEFAULT_DEST_FOLDER}"
    dest_folder="${dest_folder/#\~/$HOME}"

    if ! mkdir -p "$dest_folder"; then
        echo "ERROR: Could not create destination folder: $dest_folder"
        exit 1
    fi
    dest_folder="$(cd "$dest_folder" && pwd)"
    echo "INFO: Files will be saved to: $dest_folder"
}


# === Main Script Execution ===

ensure_dependencies
prompt_url
prompt_quality_and_format
prompt_destination

if [ ${#video_urls_to_process[@]} -eq 0 ]; then
    echo "ERROR: No valid URLs were provided to process. Exiting."
    exit 1
fi

successful_downloads=0
failed_downloads=0

for current_video_url in "${video_urls_to_process[@]}"; do
    echo "--------------------------------------------------"
    echo "Processing URL: $current_video_url"
    echo "--------------------------------------------------"

    # Construct the output template for cleaner filenames.
    # TYPE THIS LINE CAREFULLY to avoid hidden characters.
    output_template="$dest_folder/%(playlist_index?%(playlist_index)02d - :)s%(title).${MAX_FILENAME_TITLE_LENGTH}s.%(ext)s"

    # Base yt-dlp command array
    yt_dlp_base_cmd=(
        yt-dlp
        -f "$format_selection"
        --ignore-errors       # Continue on individual download errors in a batch
        --no-warnings         # Suppress yt-dlp's own warnings (e.g., about subtitles)
        --no-overwrites       # Skip download if file already exists
        --embed-metadata      # Embed available metadata (good for tagging)
        -o "$output_template"
        # --ppa "ffmpeg: -loglevel error" # Optional: make ffmpeg less verbose if needed
    )

    # Add video-specific options OR audio-specific options
    if [[ "$quality_choice" -ne 4 && "$quality_choice" -ne 5 ]]; then
        # This is a VIDEO download (options 1, 2, or 3)
        yt_dlp_base_cmd+=(
            --embed-subs
            --sub-langs "en.*,en"
            --write-subs
            --merge-output-format "mp4"
        )
    else
        # This is an AUDIO download (options 4 or 5)
        yt_dlp_base_cmd+=(
            --embed-thumbnail # Embed video thumbnail as album art
        )
    fi

    # Add any extra arguments determined by quality selection (e.g., for MP3 conversion for option 5)
    if [ ${#yt_dlp_extra_args[@]} -gt 0 ]; then
        yt_dlp_base_cmd+=("${yt_dlp_extra_args[@]}")
    fi

    # Add the CURRENT URL from the loop to the command
    yt_dlp_base_cmd+=("$current_video_url")

    # Announce action for the current URL
    echo "Starting download process for: $current_video_url"
    echo "  Quality option: $quality_choice"
    echo "  Format string: $format_selection ${yt_dlp_extra_args[*]}"
    echo "  Saving to: $dest_folder"
    # For debugging: echo "  Full command: ${yt_dlp_base_cmd[*]}"

    # Execute the yt-dlp command for the current URL
    if "${yt_dlp_base_cmd[@]}"; then
        echo "" # Newline for cleaner separation
        echo "✅ Download process completed for: $current_video_url"
        ((successful_downloads++))
    else
        echo "" # Newline for cleaner separation
        echo "❌ yt-dlp command failed for: $current_video_url (exit code $?)."
        echo "   There might have been errors during its download."
        ((failed_downloads++))
    fi
done

echo "--------------------------------------------------"
echo "All specified URLs have been processed."
echo "Successful downloads: $successful_downloads"
echo "Failed downloads: $failed_downloads"
echo "Files should be located in: $dest_folder"

if command -v termux-notification &>/dev/null; then
    total_processed=${#video_urls_to_process[@]}
    notification_title="YT-DL Script Finished"
    notification_content="Processed $total_processed URL(s). Success: $successful_downloads, Failed: $failed_downloads. Files in $dest_folder"

    termux-notification \
        --title "$notification_title" \
        --content "$notification_content" \
        --id "ytdl-script-status" \
        --priority high \
        --sound # Makes a sound
    echo "INFO: Sent notification via Termux."
else
    echo "INFO: termux-notification command not found. Skipping Android notification."
    echo "      You can try installing it with: pkg install termux-api"
fi

exit 0
