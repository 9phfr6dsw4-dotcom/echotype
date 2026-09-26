#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
APP_KEY="${APP_KEY:?APP_KEY is required}"
HELPER="$ROOT/.github/scripts/render-readme-media.swift"
ARTIFACT_DIR="$RUNNER_TEMP/readme-media"
EXTRACT_DIR="$RUNNER_TEMP/release-app"
mkdir -p "$ARTIFACT_DIR" "$EXTRACT_DIR" "$ROOT/docs/images"

case "$APP_KEY" in
  clipboard-shelf)
    RELEASE_REPO='9phfr6dsw4-dotcom/clipboard-shelf'
    APP_BUNDLE='Clipboard Shelf.app'; WINDOW_OWNER='ClipboardShelf'; APP_NAME='Clipboard Shelf'
    TAGLINE='A quiet macOS menu-bar clipboard history with search, pins, and a pause switch.'
    MENU_APP=1
    ;;
  quick-drop-zone)
    RELEASE_REPO='9phfr6dsw4-dotcom/quick-drop-zone'
    APP_BUNDLE='Quick Drop Zone.app'; WINDOW_OWNER='QuickDropZone'; APP_NAME='Quick Drop Zone'
    TAGLINE='A careful, local-first file organizer in the macOS menu bar.'
    MENU_APP=1
    ;;
  echotype)
    RELEASE_REPO='9phfr6dsw4-dotcom/echotype'
    APP_BUNDLE='EchoType.app'; WINDOW_OWNER='EchoType'; APP_NAME='EchoType'
    TAGLINE='Private, on-device dictation for macOS with Apple Speech, Parakeet v3, and Whisper.'
    MENU_APP=0
    ;;
  captiongrab)
    RELEASE_REPO='9phfr6dsw4-dotcom/captiongrab'
    APP_BUNDLE='CaptionGrab.app'; WINDOW_OWNER='CaptionGrab'; APP_NAME='CaptionGrab'
    TAGLINE='Get English YouTube captions and save them as Markdown or Word.'
    MENU_APP=0
    ;;
  *) printf 'Unknown APP_KEY: %s\n' "$APP_KEY" >&2; exit 2 ;;
esac

case "$APP_KEY" in
  clipboard-shelf) SLUG='clipboard-shelf' ;;
  quick-drop-zone) SLUG='quick-drop-zone' ;;
  echotype) SLUG='echotype' ;;
  captiongrab) SLUG='captiongrab' ;;
esac

printf '%s\n' '=== Display configuration ==='
system_profiler SPDisplaysDataType 2>&1 | tee "$ARTIFACT_DIR/display-info.txt"
printf '%s\n' '=== Preparing a clean synthetic-demo desktop ==='
swift "$HELPER" wallpaper "$RUNNER_TEMP/readme-wallpaper.png"
osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$RUNNER_TEMP/readme-wallpaper.png\"" || printf '%s\n' 'Wallpaper AppleScript was unavailable.'
defaults write com.apple.finder CreateDesktop false || true
killall Finder >/dev/null 2>&1 || true
osascript -e 'tell application "Finder" to close every window' >/dev/null 2>&1 || true
osascript -e 'tell application "Terminal" to close every window' >/dev/null 2>&1 || true

printf 'Downloading latest published release from %s.\n' "$RELEASE_REPO"
mkdir -p "$RUNNER_TEMP/release-download"
gh release download --repo "$RELEASE_REPO" --pattern '*.zip' --dir "$RUNNER_TEMP/release-download"
ZIP_PATH="$(python3 - "$RUNNER_TEMP/release-download" <<'PY'
from pathlib import Path
import sys
files = sorted(Path(sys.argv[1]).glob('*.zip'))
if len(files) != 1:
    raise SystemExit(f'Expected one ZIP asset from the latest release; found {len(files)}')
print(files[0])
PY
)"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
APP="$EXTRACT_DIR/$APP_BUNDLE"
test -d "$APP"
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
ICON="$ROOT/docs/images/$SLUG-icon.png"
test -s "$ICON"

set_appearance() {
  local dark="$1"
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark" || printf 'Could not switch appearance to dark=%s; retaining the runner theme.\n' "$dark"
  sleep 2
}

show_menu_popover() {
  osascript - "$WINDOW_OWNER" <<'APPLESCRIPT' || return 1
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
      delay 1
      try
        click menu bar item 1 of menu bar 2
      on error
        click menu bar item 1 of menu bar 1
      end try
    end tell
  end tell
end run
APPLESCRIPT
}

window_info() {
  swift "$HELPER" window "$WINDOW_OWNER"
}

capture_app_window() {
  local output="$1"
  local info id x y width height scale
  info="$(window_info)"
  IFS='|' read -r id x y width height scale <<< "$info"
  printf 'Window %s bounds: id=%s x=%s y=%s width=%s height=%s backing-scale=%s\n' "$WINDOW_OWNER" "$id" "$x" "$y" "$width" "$height" "$scale"
  screencapture -x -l "$id" "$output"
  test -s "$output"
}

capture_menu_region() {
  local output="$1"
  local info id x y width height scale left region_width region_height
  info="$(window_info)"
  IFS='|' read -r id x y width height scale <<< "$info"
  left=$(( x > 64 ? x - 64 : 0 ))
  region_width=$(( width + 128 ))
  region_height=$(( y + height + 36 ))
  printf 'Menu popover %s bounds: id=%s x=%s y=%s width=%s height=%s backing-scale=%s\n' "$WINDOW_OWNER" "$id" "$x" "$y" "$width" "$height" "$scale"
  printf 'Capturing menu-bar icon plus popover region %s,0,%s,%s\n' "$left" "$region_width" "$region_height"
  screencapture -x -R "$left,0,$region_width,$region_height" "$output"
  test -s "$output"
}

capture_video_region() {
  local rect="$1"
  local x y width height scale
  IFS=',' read -r x y width height scale <<< "$rect"
  local raw="$RUNNER_TEMP/readme-capture.mov"
  local mp4="$ARTIFACT_DIR/$SLUG-hero.mp4"
  local gif="$ROOT/docs/images/$SLUG-hero.gif"
  local capture_log="$ARTIFACT_DIR/video-capture.log"
  rm -f "$raw" "$mp4" "$gif"

  printf '%s\n' 'Trying screencapture video with the requested region.'
  screencapture -v -V 8 -R "$x,$y,$width,$height" -x "$raw" >"$capture_log" 2>&1 &
  local capture_pid=$!
  sleep 1
  animate_app || printf '%s\n' 'UI animation returned an accessibility error.'
  wait "$capture_pid" || printf '%s\n' 'screencapture video mode failed; trying the next documented method.'

  if [[ ! -s "$raw" ]]; then
    if ! command -v ffmpeg >/dev/null 2>&1; then brew install ffmpeg; fi
    ffmpeg -f avfoundation -list_devices true -i '' >"$ARTIFACT_DIR/avfoundation-devices.txt" 2>&1 || true
    local screen_index="${AVFOUNDATION_SCREEN_INDEX:-0}"
    printf 'Trying AVFoundation screen device %s.\n' "$screen_index"
    ffmpeg -y -f avfoundation -framerate 30 -i "$screen_index:none" -t 8 -an "$raw" >>"$capture_log" 2>&1 &
    capture_pid=$!
    sleep 1
    animate_app || printf '%s\n' 'UI animation returned an accessibility error.'
    wait "$capture_pid" || printf '%s\n' 'AVFoundation capture failed; trying a still-frame burst.'
  fi

  if [[ ! -s "$raw" ]]; then
    if ! command -v ffmpeg >/dev/null 2>&1; then brew install ffmpeg; fi
    local frames="$RUNNER_TEMP/readme-frames"
    mkdir -p "$frames"
    for frame in {1..96}; do
      printf -v frame_name '%s/frame_%04d.png' "$frames" "$frame"
      screencapture -x -R "$x,$y,$width,$height" "$frame_name" >/dev/null 2>&1 || true
      sleep 0.02
    done &
    local frame_pid=$!
    animate_app || printf '%s\n' 'UI animation returned an accessibility error.'
    wait "$frame_pid"
    if compgen -G "$frames/frame_*.png" >/dev/null; then
      ffmpeg -y -framerate 12 -i "$frames/frame_%04d.png" -c:v libx264 -pix_fmt yuv420p "$raw" >>"$capture_log" 2>&1 || true
    fi
  fi

  if [[ ! -s "$raw" ]]; then
    printf '%s\n' 'No supported video-capture method succeeded.' | tee "$ARTIFACT_DIR/video-status.txt"
    return 0
  fi

  if ! command -v ffmpeg >/dev/null 2>&1; then brew install ffmpeg; fi
  local raw_size expected_width expected_height raw_dimensions raw_width raw_height crop_filter
  raw_dimensions="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$raw" 2>/dev/null || true)"
  raw_width="${raw_dimensions%x*}"
  raw_height="${raw_dimensions#*x}"
  expected_width=$(( width * scale ))
  expected_height=$(( height * scale ))
  crop_filter='null'
  if [[ "$raw_width" =~ ^[0-9]+$ && "$raw_height" =~ ^[0-9]+$ ]] && (( raw_width > expected_width || raw_height > expected_height )); then
    local crop_x=$(( x * scale )) crop_y=$(( y * scale ))
    if (( crop_x + expected_width <= raw_width && crop_y + expected_height <= raw_height )); then
      crop_filter="crop=$expected_width:$expected_height:$crop_x:$crop_y"
    fi
  fi
  printf 'Raw video size=%sx%s; target=%sx%s; filter=%s\n' "$raw_width" "$raw_height" "$expected_width" "$expected_height" "$crop_filter" | tee "$ARTIFACT_DIR/video-dimensions.txt"
  ffmpeg -y -i "$raw" -vf "$crop_filter,fps=30,tpad=stop_mode=clone:stop_duration=1" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$mp4" >>"$capture_log" 2>&1
  ffmpeg -y -i "$mp4" -vf 'fps=14,scale=800:-1:flags=lanczos,palettegen=stats_mode=diff' "$RUNNER_TEMP/palette.png" >>"$capture_log" 2>&1
  ffmpeg -y -i "$mp4" -i "$RUNNER_TEMP/palette.png" -lavfi 'fps=14,scale=800:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4' -loop 0 "$gif" >>"$capture_log" 2>&1
  local gif_bytes
  gif_bytes="$(stat -f '%z' "$gif")"
  if (( gif_bytes > 6291456 )); then
    if ! command -v gifsicle >/dev/null 2>&1; then brew install gifsicle; fi
    gifsicle -O3 --lossy=40 "$gif" -o "$RUNNER_TEMP/optimized.gif"
    mv "$RUNNER_TEMP/optimized.gif" "$gif"
  fi
  cp "$gif" "$ARTIFACT_DIR/$SLUG-hero.gif"
  printf 'Video capture and GIF complete; GIF bytes=%s\n' "$(stat -f '%z' "$gif")" | tee "$ARTIFACT_DIR/video-status.txt"
}

prepare_clipboard_demo() {
  swift "$HELPER" seed-clipboard
}

prepare_quick_drop_demo() {
  mkdir -p "$HOME/Downloads"
  printf 'Sample project brief for a fictional Atlas workspace.\n' > "$HOME/Downloads/Atlas-project-brief.pdf"
  printf 'Review notes for the fictional Atlas workspace.\n' > "$HOME/Downloads/Atlas-review-notes.md"
  printf 'Timeline data for the fictional Atlas workspace.\n' > "$HOME/Downloads/Atlas-timeline.xlsx"
  printf 'Draft copy for the fictional Atlas workspace.\n' > "$HOME/Downloads/Atlas-copy-draft.docx"
  printf 'Sample team agenda.\n' > "$HOME/Downloads/Team-agenda-2026-08.docx"
  printf 'Receipt sample.\n' > "$HOME/Downloads/invoice-2026-08.pdf"
  printf 'Archive sample.\n' > "$HOME/Downloads/holiday-photos.zip"
  printf 'Image sample.\n' > "$HOME/Downloads/Screenshot 2026-09-20 at 10.14.03.png"
  cp "$RUNNER_TEMP/readme-wallpaper.png" "$HOME/Downloads/Screenshot 2026-09-20 at 10.14.03.png"
  printf 'Meeting notes sample.\n' > "$HOME/Downloads/meeting-notes.md"
  printf 'Design draft sample.\n' > "$HOME/Downloads/brand-board.sketch"
  printf 'Installer sample.\n' > "$HOME/Downloads/Sample Studio.dmg"
  printf 'Temporary export sample.\n' > "$HOME/Downloads/export-final-2.csv"
  sudo mkdir -p '/Applications/Sample Studio.app/Contents'
  printf 'Synthetic demo app marker.\n' | sudo tee '/Applications/Sample Studio.app/Contents/Info.plist' >/dev/null
}

animate_app() {
  case "$APP_KEY" in
    clipboard-shelf)
      show_menu_popover || return 1
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "ClipboardShelf"
    delay 1
    try
      set value of text field 1 of window 1 to "build"
      delay 1
      set value of text field 1 of window 1 to ""
      delay 1
      click button "Pin clipboard item" of row 1 of table 1 of scroll area 1 of window 1
      delay 1
      click row 2 of table 1 of scroll area 1 of window 1
    on error errText
      log errText
    end try
  end tell
end tell
APPLESCRIPT
      ;;
    quick-drop-zone)
      show_menu_popover || return 1
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "QuickDropZone"
    delay 1
    try
      click button "Clean up…" of window 1
    on error
      click button "Clean up..." of window 1
    end try
    delay 2
    try
      click checkbox 1 of window 1
    end try
    delay 1
    try
      click button "Approve & Move" of window 1
      delay 1
      click button "Move Selected Files" of sheet 1 of window 1
    end try
    delay 2
    try
      click button "Back" of window 1
    end try
    delay 1
  end tell
end tell
APPLESCRIPT
      ;;
    captiongrab)
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "CaptionGrab"
    delay 1
    try
      click button "Get transcript" of window 1
    end try
    delay 6
    try
      click menu button 1 of window 1
    end try
    delay 1
  end tell
end tell
APPLESCRIPT
      ;;
    echotype)
      printf '%s\n' 'Live dictation is not attempted: the hosted runner has no microphone; owner local recording remains required.' | tee "$ARTIFACT_DIR/echotype-live-dictation-status.txt"
      ;;
  esac
}

case "$APP_KEY" in
  clipboard-shelf)
    prepare_clipboard_demo
    open "$APP"
    sleep 5
    set_appearance false
    show_menu_popover || printf '%s\n' 'Clipboard Shelf menu bar popover could not be opened with System Events.'
    capture_menu_region "$ROOT/docs/images/clipboard-shelf-light.png"
    show_menu_popover || true
    set_appearance true
    show_menu_popover || true
    capture_menu_region "$ROOT/docs/images/clipboard-shelf-dark.png"
    show_menu_popover || true
    set_appearance false
    show_menu_popover || true
    info="$(window_info)"; IFS='|' read -r id x y width height scale <<< "$info"
    rect="$(( x > 64 ? x - 64 : 0 )),0,$(( width + 128 )),$(( y + height + 36 )),$scale"
    show_menu_popover || true
    capture_video_region "$rect"
    ;;
  quick-drop-zone)
    prepare_quick_drop_demo
    open "$APP"
    sleep 5
    set_appearance false
    show_menu_popover || printf '%s\n' 'Quick Drop Zone menu bar popover could not be opened with System Events.'
    capture_menu_region "$ROOT/docs/images/quick-drop-zone-light.png"
    show_menu_popover || true
    set_appearance true
    show_menu_popover || true
    capture_menu_region "$ROOT/docs/images/quick-drop-zone-dark.png"
    show_menu_popover || true
    set_appearance false
    show_menu_popover || true
    info="$(window_info)"; IFS='|' read -r id x y width height scale <<< "$info"
    rect="$(( x > 64 ? x - 64 : 0 )),0,$(( width + 128 )),$(( y + height + 36 )),$scale"
    show_menu_popover || true
    capture_video_region "$rect"
    ;;
  echotype)
    swift "$HELPER" seed-echotype
    defaults write com.echotype.app EchoType.hasSeenLaunchAtLoginOption -bool true
    open "$APP"
    sleep 10
    osascript -e 'tell application "System Events" to tell process "EchoType" to set size of window 1 to {1100, 950}' || true
    set_appearance false
    capture_app_window "$ROOT/docs/images/echotype-light.png"
    osascript <<'APPLESCRIPT' || printf '%s\n' 'Could not switch to Speech Models using System Events.'
tell application "System Events"
  tell process "EchoType"
    try
      click radio button "Speech Models" of tab group 1 of window 1
    on error
      click button "Speech Models" of window 1
    end try
  end tell
end tell
APPLESCRIPT
    sleep 3
    capture_app_window "$ROOT/docs/images/echotype-model-library-light.png" || true
    set_appearance true
    osascript -e 'tell application "System Events" to tell process "EchoType" to click radio button "Home" of tab group 1 of window 1' || true
    sleep 2
    capture_app_window "$ROOT/docs/images/echotype-dark.png"
    set_appearance false
    ;;
  captiongrab)
    open "$APP"
    sleep 6
    osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "CaptionGrab"
    set frontmost to true
    try
      set size of window 1 to {1120, 900}
      set position of window 1 to {60, 45}
      set value of text field 1 of window 1 to "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
      click button "Get transcript" of window 1
    end try
  end tell
end tell
APPLESCRIPT
    sleep 18
    set_appearance false
    capture_app_window "$ROOT/docs/images/captiongrab-light.png"
    set_appearance true
    capture_app_window "$ROOT/docs/images/captiongrab-dark.png"
    set_appearance false
    info="$(window_info)"; IFS='|' read -r id x y width height scale <<< "$info"
    rect="$x,$y,$width,$height,$scale"
    capture_video_region "$rect"
    ;;
esac

STILL="$ROOT/docs/images/$SLUG-light.png"
if [[ -s "$STILL" ]]; then
  swift "$HELPER" social "$ROOT/docs/images/social-preview.png" "$ICON" "$APP_NAME" "$TAGLINE" "$STILL"
  cp "$ROOT/docs/images/social-preview.png" "$ARTIFACT_DIR/social-preview.png"
fi
for image in "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif" "$ROOT/docs/images/social-preview.png"; do
  [[ ! -e "$image" ]] || cp "$image" "$ARTIFACT_DIR/"
done
printf 'Capture candidates are in docs/images and artifacts in %s\n' "$ARTIFACT_DIR"
