#!/usr/bin/env sh

set -e

STOP_IF_FEL=${STOP_IF_FEL:=0}
DOVI_TRACK=${DOVI_TRACK:=0}
VIDEO_TRACK=${VIDEO_TRACK:=0}

# Sanity check
for command in dovi_tool jq mediainfo mkvmerge; do
	if ! command -v $command >/dev/null 2>&1; then
		printf "\n%s could not be found\n" $command
		exit 1
	fi
done

if [ -z "${1+x}" ] || [ -z "${2+x}" ]; then
	printf "\nUsage: %s <filename> <profile>\nValid profiles: dvhe.07\n" "$0"
	exit 1
fi

if [ ! -f "$1" ]; then
	printf "\n%s is not a file\n" "$1"
	exit 1
fi

# Helper function to print each command
print_and_run() {
	printf "\n------------------\n%s\n------------------\n" "$*" >&2
	"$@"
}

# Cleanup function to remove any leftover files
cleanup() {
	printf "\n\nCleaning up working files...\n"
	rm -f "${1%.*}"*".hevc" "${1%.*}.mkv."* "${1%.*}"*".rpu.bin"
}

# Get DV profile information using mediainfo
get_dvhe_profile() {
	printf "\n\nChecking for Dolby Vision %s profile...\n" "$2"
	DVHE_PROFILE=$(print_and_run mediainfo --Output=JSON "$1" | jq '.media.track[].HDR_Format_Profile' | grep "${2}" || true)
	if [ -n "${DVHE_PROFILE}" ]; then
		printf "\nDVHE %s profile found\n" "$2"
	else
		printf "\nDVHE %s profile not found\n" "$2"
		exit 0
	fi
}

extract_hevc() {
	printf "\n\nExtracting HEVC track from %s...\n" "$1"
	if [ "$DOVI_TRACK" -ne "$VIDEO_TRACK" ]; then
		if ! print_and_run mkvextract "$1" tracks "$DOVI_TRACK:${1%.*}.hevc" "$VIDEO_TRACK:${1%.*}.bl.hevc"; then
			printf "\nFailed to extract %s\n" "$1"
			cleanup "$1"
			exit 1
		fi
	else
		if ! print_and_run mkvextract "$1" tracks "$VIDEO_TRACK:${1%.*}.hevc"; then
			printf "\nFailed to extract %s\n" "$1"
			cleanup "$1"
			exit 1
		fi
	fi
}

convert_hevc() {
	printf "\n\nConverting %s...\n" "${1%.*}.hevc"
	if ! print_and_run dovi_tool --edit-config /config/dovi_tool.config.json convert --discard "${1%.*}.hevc" -o "${1%.*}.dv8.hevc"; then
		printf "\nFailed to convert %s\n" "$1"
		cleanup "$1"
		exit 1
	fi
}

extract_rpu() {
	printf "\n\nExtracting original RPU from %s...\n" "${1%.*}.hevc"
	if ! print_and_run dovi_tool extract-rpu "${1%.*}.hevc" -o "${1%.*}.dv7.rpu.bin"; then
		printf "\nFailed to extract RPU from %s\n" "${1%.*}.hevc"
		cleanup "$1"
		exit 1
	fi
	printf "\n\nExtracting converted RPU from %s...\n" "${1%.*}.dv8.hevc"
	if ! print_and_run dovi_tool extract-rpu "${1%.*}.dv8.hevc" -o "${1%.*}.rpu.bin"; then
		printf "\nFailed to extract RPU from %s\n" "${1%.*}.dv8.hevc"
		cleanup "$1"
		exit 1
	fi
}

plot_rpu() {
	printf "\n\nPlotting RPU info from %s...\n" "${1%.*}.dv7.rpu.bin"
	if ! print_and_run dovi_tool plot "${1%.*}.dv7.rpu.bin" -o "${1%.*}.dv7.l1_plot.png"; then
		printf "\nFailed to create plot from RPU\n"
		cleanup "$1"
		exit 1
	fi
	printf "\n\nPlotting RPU info from %s...\n" "${1%.*}.rpu.bin"
	if ! print_and_run dovi_tool plot "${1%.*}.rpu.bin" -o "${1%.*}.dv8.l1_plot.png"; then
		printf "\nFailed to create plot from RPU\n"
		cleanup "$1"
		exit 1
	fi
}

summarize_rpu() {
	for rpu in "${1%/*}/"*".rpu.bin"; do
		printf "\n\nSummarizing RPU info from %s...\n" "$rpu"
		if ! rpu_summary=$(print_and_run dovi_tool info -i "$rpu" --summary); then
			printf "\nFailed to summarize RPU info from %s\n" "$rpu"
			cleanup "$1"
			exit 1
		else
			printf "%s" "$rpu_summary\n"
			if printf "%s" "$rpu_summary" | grep "FEL" && [ "$STOP_IF_FEL" -eq 1 ]; then
				printf "\nFull Enhancement Layer (FEL) detected in %s.\nExiting.\n" "$rpu"
				cleanup "$1"
				exit 1
			fi
		fi
	done
}

demux_file() {
	printf "\n\nDemuxing %s...\n" "$1"
	extract_hevc "$1"
	convert_hevc "$1"
	extract_rpu "$1"
	plot_rpu "$1"
	summarize_rpu "$1"
}

remux_file() {
	if [ "$DOVI_TRACK" -ne "$VIDEO_TRACK" ]; then
		printf "\n\nInjecting RPU into BL...\n"
		if ! print_and_run dovi_tool inject-rpu -i "${1%.*}.bl.hevc" --rpu-in "${1%.*}.rpu.bin" -o "${1%.*}.dv8.hevc"; then
			printf "\nFailed to inject RPU into BL\n"
			cleanup "$1"
			exit 1
		else
			rm -f "${1%.*}.bl.hevc"
		fi
	fi
	printf "\n\nRemuxing %s...\n" "$1"
	if ! print_and_run mkvmerge -o "${1%.*}.mkv.tmp" -D "$1" "${1%.*}.dv8.hevc" --track-order 1:0; then
		printf "\nFailed to remux %s\n" "$1"
		cleanup "$1"
		exit 1
	fi
}

# Overwrite the original file with the remuxed file
overwrite_file() {
	# Create a symbolic link (symlink) to the temporary file
	if ! ln "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy"; then
		printf "\nFailed to copy %s to %s\n" "${1%.*}.mkv.tmp" "${1%.*}.mkv.copy"
		cleanup "$1"
		exit 1
	fi

	# Rename the symlink to the original filename, effectively overwriting the original file
	if ! mv "${1%.*}.mkv.copy" "$1"; then
		printf "\nFailed to overwrite %s\n" "$1"
		cleanup "$1"
		exit 1
	fi

	# Remove the temporary file
	if ! rm "${1%.*}.mkv.tmp"; then
		printf "\nFailed to remove %s\n" "${1%.*}.mkv.tmp"
		cleanup "$1"
		exit 1
	fi

	if [ -f "${1%.*}.mkv.tmp" ]; then
		printf "\nFailed to remove %s\n" "${1%.*}.mkv.tmp"
		cleanup "$1"
		exit 1
	fi
}

main() {
	get_dvhe_profile "$1" "$2"
	demux_file "$1"
	remux_file "$1"
	overwrite_file "$1"
	cleanup "$1"
}

main "$1" "$2"
