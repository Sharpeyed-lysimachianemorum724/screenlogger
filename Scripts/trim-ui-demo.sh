#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
input=${1:-"$project_dir/build/demo/screenlogger-product-tour-full-display-raw.mov"}
output=${2:-"$project_dir/build/demo/screenlogger-product-tour-trimmed.mp4"}
icon=${3:-"$project_dir/docs/images/screenlogger-icon.png"}

ffmpeg_bin=$(command -v ffmpeg || true)
ffprobe_bin=$(command -v ffprobe || true)

if [ -z "$ffmpeg_bin" ] || [ -z "$ffprobe_bin" ]; then
    echo "error: ffmpeg and ffprobe are required" >&2
    exit 1
fi

for required_file in "$input" "$icon"; do
    if [ ! -f "$required_file" ]; then
        echo "error: file not found: $required_file" >&2
        exit 1
    fi
done

input_width=$($ffprobe_bin -v error -select_streams v:0 \
    -show_entries stream=width -of csv=p=0 "$input")
input_height=$($ffprobe_bin -v error -select_streams v:0 \
    -show_entries stream=height -of csv=p=0 "$input")

if [ "$input_width" != "3456" ] || [ "$input_height" != "2234" ]; then
    echo "error: expected a 3456x2234 full-display recording, got ${input_width}x${input_height}" >&2
    exit 1
fi

output_dir=$(dirname -- "$output")
/bin/mkdir -p "$output_dir"
temporary_output=$(mktemp "$output_dir/.screenlogger-demo.XXXXXX")
trap 'rm -f "$temporary_output"' EXIT HUP INT TERM

# Preserve the pace and composition of the original take. The only editorial
# changes are a short logo title, removal of setup time and the macOS menu bar,
# and a clean ending on the assistant chooser.
$ffmpeg_bin -hide_banner -loglevel warning -y \
    -i "$input" \
    -loop 1 -framerate 60 -i "$icon" \
    -filter_complex "\
[0:v]crop=iw:ih-72:0:72,split=2[cropped-intro][cropped-main];\
[cropped-intro]trim=start=0.5:end=1.9,setpts=PTS-STARTPTS,fps=60,format=yuv420p[introbg];\
[1:v]scale=320:320:flags=lanczos,format=rgba,\
fade=t=in:st=0:d=0.20:alpha=1,fade=t=out:st=1.05:d=0.25:alpha=1[logo];\
[introbg][logo]overlay=(W-w)/2:(H-h)/2:shortest=1,format=yuv420p[intro];\
[cropped-main]trim=start=3.5:end=47.7,setpts=PTS-STARTPTS,fps=60,format=yuv420p[main];\
[intro][main]xfade=transition=fade:duration=0.25:offset=1.15,\
fade=t=out:st=45.0:d=0.30,format=yuv420p[outv]" \
    -map "[outv]" -an -c:v libx264 -preset slow -crf 17 -profile:v high \
    -movflags +faststart -f mp4 "$temporary_output"

/bin/mv -f "$temporary_output" "$output"
trap - EXIT HUP INT TERM

$ffprobe_bin -v error -show_entries format=duration,size,bit_rate \
    -show_entries stream=codec_name,width,height,r_frame_rate \
    -of default=noprint_wrappers=1 "$output"
