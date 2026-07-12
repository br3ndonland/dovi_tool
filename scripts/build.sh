#!/usr/bin/env bash
set -euo pipefail

USAGE="
Usage: scripts/build.sh

Options:
  -h, --help  Show this help text.
"

require_env() {
	local missing=()
	local name

	for name in "$@"; do
		if [[ -z "${!name-}" ]]; then
			missing+=("${name}")
		fi
	done

	if ((${#missing[@]} > 0)); then
		echo "::error::Missing required environment variables:"
		printf '  %s\n' "${missing[@]}"
		exit 1
	fi
}

trim_whitespace() {
	local value="$1"

	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "${value}"
}

count_csv_values() {
	local csv="$1"
	local count=0
	local item
	local -a items

	IFS=, read -r -a items <<<"${csv}"
	for item in "${items[@]}"; do
		item="$(trim_whitespace "${item}")"
		if [[ -n "${item}" ]]; then
			((count += 1))
		fi
	done

	printf '%s' "${count}"
}

validate_annotation_levels() {
	local annotation_levels="$1"
	local platforms="$2"
	local level
	local level_type
	local platform_count
	local -a levels

	if [[ -z "${annotation_levels}" ]]; then
		return
	fi

	platform_count="$(count_csv_values "${platforms}")"
	if ((platform_count == 0)); then
		platform_count=1
	fi
	IFS=, read -r -a levels <<<"${annotation_levels}"
	for level in "${levels[@]}"; do
		level="$(trim_whitespace "${level}")"
		level_type="${level%%[*}"

		case "${level_type}" in
		manifest | index | manifest-descriptor | index-descriptor)
			;;
		*)
			echo "::error::Unsupported annotation level: ${level}"
			exit 1
			;;
		esac

		if ((platform_count == 1)) &&
			[[ "${level_type}" == "index" || "${level_type}" == "index-descriptor" ]]; then
			echo "::error::DOCKER_METADATA_ANNOTATIONS_LEVELS=${annotation_levels} targets ${level_type}," \
				"but PLATFORMS=${platforms} contains one platform."
			echo "::error::Use DOCKER_METADATA_ANNOTATIONS_LEVELS=manifest" \
				"for single-platform" \
				"builds, or add another platform."
			exit 1
		fi
	done
}

validate_load() {
	local load="$1"
	local platforms="$2"
	local platform_count

	case "${load}" in
	true | false)
		;;
	*)
		echo "::error::LOAD must be true or false."
		exit 1
		;;
	esac

	platform_count="$(count_csv_values "${platforms}")"
	if [[ "${load}" == "true" ]] && ((platform_count > 1)); then
		echo "::error::LOAD=true cannot be used with multiple platforms in this script."
		echo "::error::Buildx --load uses the Docker exporter, which does" \
			"not export manifest lists from this docker-container builder."
		echo "::error::Set PLATFORMS to one platform for a runnable local image," \
			"or set LOAD=false for a multi-platform cache-only build."
		exit 1
	fi
}

validate_gha_cache() {
	local gha_cache="$1"

	if [[ "${gha_cache}" != "true" ]]; then
		return
	fi

	if [[ -z "${ACTIONS_RUNTIME_TOKEN:-}" ]]; then
		echo "::error::GHA_CACHE=true requires ACTIONS_RUNTIME_TOKEN."
		echo "::error::Run ./.github/actions/github-runtime before" \
			"scripts/build.sh in GitHub Actions."
		exit 1
	fi

	if [[ -z "${ACTIONS_CACHE_URL:-}" && -z "${ACTIONS_RESULTS_URL:-}" ]]; then
		echo "::error::GHA_CACHE=true requires ACTIONS_CACHE_URL or" \
			"ACTIONS_RESULTS_URL."
		echo "::error::Run ./.github/actions/github-runtime before" \
			"scripts/build.sh in GitHub Actions."
		exit 1
	fi
}

validate_bool() {
	local name="$1"
	local value="$2"

	case "${value,,}" in
	1 | true)
		printf '%s' "true"
		;;
	0 | false)
		printf '%s' "false"
		;;
	*)
		echo "::error::${name} must be true, false, 1, or 0." >&2
		exit 1
		;;
	esac
}

write_summary_list() {
	local title="$1"
	shift
	local item

	printf '<details><summary>%s</summary>\n\n' "${title}"
	printf '```text\n'
	if (($# > 0)); then
		for item in "$@"; do
			printf '%s\n' "${item}"
		done
	else
		printf 'none\n'
	fi
	printf '```\n\n'
	printf '</details>\n\n'
}

write_build_summary() {
	local metadata_file="$1"
	local iidfile="$2"
	local dockerfile_summary

	if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
		return
	fi

	if [[ -n "${dockerfile}" ]]; then
		dockerfile_summary="${dockerfile}"
	else
		dockerfile_summary="Docker default"
	fi

	{
		printf '## Docker container image build\n\n'
		printf '| Input | Value |\n'
		printf '| --- | --- |\n'
		printf "| Image | \`%s\` |\n" "${IMAGE_NAME}"
		printf "| Context | \`%s\` |\n" "${build_context}"
		printf "| Dockerfile | \`%s\` |\n" "${dockerfile_summary}"
		printf "| Platforms | \`%s\` |\n" "${platforms}"
		printf "| Annotation levels | \`%s\` |\n" "${annotation_levels:-none}"
		printf "| Provenance | \`%s\` |\n" "${provenance}"
		printf "| Push | \`%s\` |\n" "${should_push}"
		printf "| GHA cache | \`%s\` |\n" "${gha_cache}"

		write_summary_list "Tags" "${tags[@]}"
		write_summary_list "Labels" "${labels[@]}"
		write_summary_list "Annotations" "${annotations[@]}"

		if [[ -s "${iidfile}" ]]; then
			printf '<details><summary>Image ID</summary>\n\n'
			printf '```text\n'
			cat "${iidfile}"
			printf '\n```\n\n'
			printf '</details>\n\n'
		fi

		if [[ -s "${metadata_file}" ]]; then
			printf '<details><summary>Buildx metadata</summary>\n\n'
			printf '```json\n'
			cat "${metadata_file}"
			printf '\n```\n\n'
			printf '</details>\n'
		fi
	} >>"${GITHUB_STEP_SUMMARY}"
}

while (($# > 0)); do
	case "$1" in
	-h | --help)
		echo "$USAGE"
		exit 0
		;;
	*)
		echo "::error::Unknown argument: $1"
		echo "$USAGE"
		exit 1
		;;
	esac
done

if [[ -z "${RUNNER_TEMP:-}" ]]; then
	RUNNER_TEMP="${TMPDIR:-/tmp}"
	export RUNNER_TEMP
fi

if [[ -z "${GITHUB_SHA:-}" ]]; then
	GITHUB_SHA="$(git rev-parse HEAD)"
	export GITHUB_SHA
fi

require_env \
	GITHUB_REF_TYPE \
	GITHUB_REF_NAME \
	GITHUB_RUN_ID \
	GITHUB_RUN_ATTEMPT \
	GITHUB_SERVER_URL \
	GITHUB_REPOSITORY \
	IMAGE_NAME \
	OCI_DESCRIPTION \
	OCI_LICENSES \
	OCI_URL

OCI_SOURCE="${OCI_SOURCE:-${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}}"
OCI_TITLE="${OCI_TITLE:-${GITHUB_REPOSITORY##*/}}"

should_push=false
if [[ "${GITHUB_REF_TYPE}" == "tag" || "${GITHUB_REF_NAME}" == "main" ]]; then
	should_push=true
fi

if [[ -n "${BUILD_ARGS:-}" ]]; then
	read -r -a build_args_inputs <<<"${BUILD_ARGS}"
else
	build_args_inputs=()
fi
build_context="${BUILD_CONTEXT-.}"
dockerfile="${DOCKERFILE-}"
platforms="${PLATFORMS-}"
annotation_levels="${DOCKER_METADATA_ANNOTATIONS_LEVELS-manifest}"
short_sha_length="${DOCKER_METADATA_SHORT_SHA_LENGTH-7}"
if [[ -z "${short_sha_length}" ]]; then
	short_sha_length=7
fi
if [[ ! "${short_sha_length}" =~ ^[0-9]+$ ]] ||
	((10#${short_sha_length} <= 0)); then
	echo "::error::DOCKER_METADATA_SHORT_SHA_LENGTH must be a positive integer." >&2
	exit 1
fi
short_sha_length="$((10#${short_sha_length}))"
if ((short_sha_length > ${#GITHUB_SHA})); then
	echo "::error::DOCKER_METADATA_SHORT_SHA_LENGTH must be less than or" \
		"equal to the full GITHUB_SHA length (${#GITHUB_SHA})." >&2
	exit 1
fi
load="${LOAD-false}"
if [[ -z "${load}" ]]; then
	load=false
fi
load="$(validate_bool LOAD "${load}")"
provenance="${PROVENANCE-true}"
if [[ -z "${provenance}" ]]; then
	provenance=false
fi
provenance="$(validate_bool PROVENANCE "${provenance}")"
gha_cache="${GHA_CACHE-}"
if [[ -z "${gha_cache}" ]]; then
	if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
		gha_cache=true
	else
		gha_cache=false
	fi
fi
gha_cache="$(validate_bool GHA_CACHE "${gha_cache}")"
tag_latest="${TAG_LATEST-}"
if [[ -z "${tag_latest}" ]]; then
	tag_latest="${should_push}"
fi
tag_latest="$(validate_bool TAG_LATEST "${tag_latest}")"
builder="builder-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
metadata_file="${RUNNER_TEMP}/build-metadata.json"
iidfile="${RUNNER_TEMP}/build-iidfile.txt"

if [[ -z "${build_context}" ]]; then
	echo "::error::BUILD_CONTEXT must not be empty."
	exit 1
fi

validate_annotation_levels "${annotation_levels}" "${platforms}"
validate_load "${load}" "${platforms}"
validate_gha_cache "${gha_cache}"

if [[ "${load}" == "true" && "${provenance}" == "true" ]]; then
	echo "::notice::Skipping provenance attestations because LOAD=true uses the" \
		"Docker exporter and the local Docker image store does not support" \
		"loading attestations."
	provenance=false
fi

cleanup() {
	docker buildx rm "${builder}" || true
	if [[ "${should_push}" == "true" ]]; then
		docker logout ghcr.io || true
	fi
}
trap cleanup EXIT

sanitize_tag() {
	local tag="${1//\//-}"
	tag="${tag//[^A-Za-z0-9_.-]/-}"
	if [[ ! "${tag}" =~ ^[A-Za-z0-9_] ]]; then
		tag="_${tag}"
	fi
	printf '%s' "${tag:0:128}"
}

short_sha="${GITHUB_SHA::short_sha_length}"
version="sha-${short_sha}"
created="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"

tags=("${IMAGE_NAME}:${version}")
if [[ "${GITHUB_REF_TYPE}" == "branch" ]] &&
	[[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
	tags+=("${IMAGE_NAME}:$(sanitize_tag "${GITHUB_REF_NAME}")")
fi
if [[ "${tag_latest}" == "true" ]]; then
	tags+=("${IMAGE_NAME}:latest")
fi

labels=(
	"org.opencontainers.image.created=${created}"
	"org.opencontainers.image.description=${OCI_DESCRIPTION}"
	"org.opencontainers.image.licenses=${OCI_LICENSES}"
	"org.opencontainers.image.revision=${GITHUB_SHA}"
	"org.opencontainers.image.source=${OCI_SOURCE}"
	"org.opencontainers.image.title=${OCI_TITLE}"
	"org.opencontainers.image.url=${OCI_URL}"
	"org.opencontainers.image.version=${version}"
)

annotations=()
if [[ -n "${annotation_levels}" ]]; then
	IFS=, read -r -a annotation_level_items <<<"${annotation_levels}"
	for annotation_level in "${annotation_level_items[@]}"; do
		annotation_level="$(trim_whitespace "${annotation_level}")"
		for label in "${labels[@]}"; do
			annotations+=("${annotation_level}:${label}")
		done
	done
fi

echo "::group::Docker build metadata inputs"
printf 'build_context=%s\n' "${build_context}"
if [[ -n "${dockerfile}" ]]; then
	printf 'dockerfile=%s\n' "${dockerfile}"
else
	printf 'dockerfile=%s\n' "Docker default"
fi
printf 'platforms=%s\n' "${platforms}"
printf 'build_args:\n'
printf '%s\n' "${build_args_inputs[@]}"
printf 'docker_metadata_annotations_levels=%s\n' "${annotation_levels:-none}"
printf 'docker_metadata_short_sha_length=%s\n' "${short_sha_length}"
printf 'load=%s\n' "${load}"
printf 'provenance=%s\n' "${provenance}"
printf 'gha_cache=%s\n' "${gha_cache}"
printf 'tag_latest=%s\n' "${tag_latest}"
printf 'version=%s\n' "${version}"
printf 'push=%s\n' "${should_push}"
printf 'tags:\n'
printf '%s\n' "${tags[@]}"
printf 'labels:\n'
printf '%s\n' "${labels[@]}"
printf 'annotations:\n'
printf '%s\n' "${annotations[@]}"
echo "::endgroup::"

echo "::group::Docker Buildx builder"
docker buildx version
docker buildx create \
	--name "${builder}" \
	--driver docker-container \
	--use
docker buildx inspect --bootstrap --builder "${builder}"
echo "::endgroup::"

build_args=(
	docker buildx build
	--builder "${builder}"
	--metadata-file "${metadata_file}"
	--iidfile "${iidfile}"
)

if [[ -n "${platforms}" ]]; then
	build_args+=(--platform "${platforms}")
fi
for build_arg in "${build_args_inputs[@]}"; do
	build_args+=(--build-arg "${build_arg}")
done

if [[ "${provenance}" == "true" ]]; then
	provenance_builder_id="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
	provenance_builder_id+="/actions/runs/${GITHUB_RUN_ID}"
	provenance_builder_id+="/attempts/${GITHUB_RUN_ATTEMPT}"
	build_args+=(
		--attest
		"type=provenance,mode=max,builder-id=${provenance_builder_id}"
	)
else
	build_args+=(--provenance=false)
fi
if [[ -n "${dockerfile}" ]]; then
	build_args+=(--file "${dockerfile}")
fi
if [[ "${gha_cache}" == "true" ]]; then
	build_args+=(
		--cache-from "type=gha"
		--cache-to "type=gha,mode=max"
	)
fi
for annotation in "${annotations[@]}"; do
	build_args+=(--annotation "${annotation}")
done
for label in "${labels[@]}"; do
	build_args+=(--label "${label}")
done
for tag in "${tags[@]}"; do
	build_args+=(--tag "${tag}")
done
if [[ "${load}" == "true" ]]; then
	build_args+=(--load)
fi
if [[ "${should_push}" == "true" ]]; then
	build_args+=(--push)
fi
build_args+=("${build_context}")

echo "::group::Docker buildx build command"
printf '%q ' "${build_args[@]}"
printf '\n'
echo "::endgroup::"

"${build_args[@]}"

if [[ -s "${metadata_file}" ]]; then
	echo "::group::Docker build metadata"
	cat "${metadata_file}"
	echo "::endgroup::"
fi

write_build_summary "${metadata_file}" "${iidfile}"
