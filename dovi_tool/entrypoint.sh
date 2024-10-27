#!/usr/bin/env sh

set -eo

DOVI_TRACK=${DOVI_TRACK:=0}
VIDEO_TRACK=${VIDEO_TRACK:=0}

# Sanity check
for command in mediainfo dovi_tool mkvmerge jq; do
	if ! command -v $command >/dev/null 2>&1; then
		echo "$command could not be found"
		exit 1
	fi
done

if [ -z "${1+x}" ] || [ -z "${2+x}" ]; then
	echo "Usage: $0 <filename> <profile>"
	echo "Valid profiles: dvhe.07"
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "$1 is not a file"
	exit 1
fi

# Cleanup function to remove any leftover files
cleanup() {
	echo "Cleaning up working files..."
	rm -f "${1%.*}.hevc" "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy" "${1%.*}.bl.hevc" "${1%.*}.dv8.hevc" "${1%.*}.rpu.bin"
}

# Get DV profile information using mediainfo
get_dvhe_profile() {
	echo "Checking for Dolby Vision ${2} profile..."
	echo "------------------"
	echo "mediainfo --Output=JSON $1 | jq '.media.track[].HDR_Format_Profile' | grep ${2}"
	echo "------------------"
	DVHE_PROFILE=$(mediainfo --Output=JSON "$1" | jq '.media.track[].HDR_Format_Profile' | grep "${2}" || true)
	if [ -n "${DVHE_PROFILE}" ]; then
		echo "DVHE ${2} profile found"
	else
		echo "DVHE ${2} profile not found"
		exit 0
	fi
}

extract_mkv() {
	echo "Extracting $1..."
	echo "------------------"
	if [ "$DOVI_TRACK" -ne "$VIDEO_TRACK" ]; then
		echo "mkvextract $1 tracks $DOVI_TRACK:${1%.*}.hevc $VIDEO_TRACK:${1%.*}.bl.hevc"
		echo "------------------"
		if ! mkvextract "$1" tracks "$DOVI_TRACK:${1%.*}.hevc" "$VIDEO_TRACK:${1%.*}.bl.hevc"; then
			echo "Failed to extract $1"
			cleanup "$1"
			exit 1
		fi
	else
		echo "mkvextract $1 tracks $VIDEO_TRACK:${1%.*}.hevc"
		echo "------------------"
		if ! mkvextract "$1" tracks "$VIDEO_TRACK:${1%.*}.hevc"; then
			echo "Failed to extract $1"
			cleanup "$1"
			exit 1
		fi
	fi
}

convert_mkv() {
	echo "Converting $1..."
	echo "------------------"
	echo "dovi_tool --edit-config /config/dovi_tool.config.json convert --discard ${1%.*}.hevc -o ${1%.*}.dv8.hevc"
	echo "------------------"
	if ! dovi_tool --edit-config /config/dovi_tool.config.json convert --discard "${1%.*}.hevc" -o "${1%.*}.dv8.hevc"; then
		echo "Failed to convert $1"
		cleanup "$1"
		exit 1
	fi
}

extract_rpu() {
	echo "Extracting RPU from ${1%.*}.dv8.hevc..."
	echo "------------------"
	echo "dovi_tool extract-rpu ${1%.*}.dv8.hevc -o ${1%.*}.rpu.bin"
	echo "------------------"
	if ! dovi_tool extract-rpu "${1%.*}.dv8.hevc" -o "${1%.*}.rpu.bin"; then
		echo "Failed to extract RPU from ${1%.*}.dv8.hevc"
		cleanup "$1"
		exit 1
	fi
}

create_plot() {
	echo "Creating plot from RPU..."
	echo "------------------"
	echo "dovi_tool plot ${1%.*}.rpu.bin -o ${1%.*}.l1_plot.png"
	echo "------------------"
	if ! dovi_tool plot "${1%.*}.rpu.bin" -o "${1%.*}.l1_plot.png"; then
		echo "Failed to create plot from RPU"
		cleanup "$1"
		exit 1
	fi
}

demux_file() {
	echo "Demuxing $1..."
	extract_mkv "$1"
	convert_mkv "$1"
	extract_rpu "$1"
	create_plot "$1"
}

remux_file() {
	if [ "$DOVI_TRACK" -ne "$VIDEO_TRACK" ]; then
		echo "Injecting RPU into BL..."
		echo "------------------"
		echo "dovi_tool inject-rpu -i ${1%.*}.bl.hevc --rpu-in ${1%.*}.rpu.bin -o ${1%.*}.dv8.hevc"
		echo "------------------"
		if ! dovi_tool inject-rpu -i "${1%.*}.bl.hevc" --rpu-in "${1%.*}.rpu.bin" -o "${1%.*}.dv8.hevc"; then
			echo "Failed to inject RPU into BL"
			cleanup "$1"
			exit 1
		else
			rm -f "${1%.*}.bl.hevc"
		fi
	fi
	echo "Remuxing $1..."
	echo "------------------"
	echo "mkvmerge -o ${1%.*}.mkv.tmp -D $1 ${1%.*}.dv8.hevc --track-order 1:0"
	echo "------------------"
	if ! mkvmerge -o "${1%.*}.mkv.tmp" -D "$1" "${1%.*}.dv8.hevc" --track-order 1:0; then
		echo "Failed to remux $1"
		cleanup "$1"
		exit 1
	fi
}

# Overwrite the original file with the remuxed file
overwrite_file() {
	# Create a symbolic link (symlink) to the temporary file
	if ! ln "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy"; then
		echo "Failed to copy ${1%.*}.mkv.tmp to ${1%.*}.mkv.copy"
		cleanup "$1"
		exit 1
	fi

	# Rename the symlink to the original filename, effectively overwriting the original file
	if ! mv "${1%.*}.mkv.copy" "$1"; then
		echo "Failed to overwrite $1"
		cleanup "$1"
		exit 1
	fi

	# Remove the temporary file
	if ! rm "${1%.*}.mkv.tmp"; then
		echo "Failed to remove ${1%.*}.mkv.tmp"
		cleanup "$1"
		exit 1
	fi

	if [ -f "${1%.*}.mkv.tmp" ]; then
		echo "Failed to remove ${1%.*}.mkv.tmp"
		cleanup "$1"
		exit 1
	fi
}

main() {
	trap 'echo "Error: $0:$LINENO: Command \`$BASH_COMMAND\` on line $LINENO failed with exit code $?" >&2; cleanup $1' ERR
	get_dvhe_profile "$1" "$2"
	demux_file "$1"
	remux_file "$1"
	overwrite_file "$1"
	cleanup "$1"
}

main "$1" "$2"
