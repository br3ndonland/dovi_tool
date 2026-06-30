# README

## Description

This repo builds a Docker container image that can be used to run [dovi_tool](https://github.com/quietvoid/dovi_tool).

## Usage

### General usage

```sh
docker run --rm -it -v /path/to/media:/opt/media ghcr.io/br3ndonland/dovi_tool '<filename>' dvhe.07
```

The Docker container will run the [`entrypoint.sh`](./dovi_tool/entrypoint.sh) script. The script will convert the [Dolby Vision profile](https://professionalsupport.dolby.com/s/article/What-is-Dolby-Vision-Profile?language=en_US) in the source media file from 7 to 8 for broader device compatibility.

**The original file will be overwritten after the conversion process is complete.**

Although the converted file will be the same size or smaller than the source file, the conversion process will temporarily require additional hard disk space. **It is recommended to have free hard disk space equal to 4x the size of the source file.** This allows space for the original `.mkv`, the extracted `.hevc`, the converted `.dv8.hevc`, and the remuxed `.mkv.tmp`.

### Interactive usage

To keep the container running for interactive usage of [`dovi_tool`](https://github.com/quietvoid/dovi_tool), [`hdr10plus_tool`](https://github.com/quietvoid/hdr10plus_tool), [`mediainfo`](https://github.com/mediaarea/mediainfo), and [MKVToolNix](https://codeberg.org/mbunkus/mkvtoolnix) (`mkvinfo`, `mkvmerge`, `mkvpropedit`), simply change the `--entrypoint`. [Alpine Linux uses BusyBox Ash as the default shell](https://wiki.alpinelinux.org/wiki/BusyBox).

```sh
docker run --rm -it -v /path/to/media:/opt/media --entrypoint ash ghcr.io/br3ndonland/dovi_tool
```

### Environment variables

Supported [environment variables](https://docs.docker.com/reference/cli/docker/container/run/#env):

- `STOP_IF_FEL` (`0` or `1`, default `0`): whether or not to proceed with conversion if a [Full Enhancement Layer](#dolby-vision-enhancement-layers) (FEL) is detected. If `STOP_IF_FEL=1` and a FEL is detected, the `entrypoint.sh` script will exit prior to overwriting the source file.
- `DOVI_TRACK` (`0` or `>=1`, default `0`): Dolby Vision track in source video file, as reported by [`mkvinfo`](https://mkvtoolnix.download/doc/mkvinfo.html).
- `VIDEO_TRACK` (`0` or `>=1`, default `0`): HDR10 Base Layer (BL) video track in source video file, as reported by [`mkvinfo`](https://mkvtoolnix.download/doc/mkvinfo.html).

### Platforms

[Multi-platform builds](https://docs.docker.com/build/building/multi-platform/) are provided for the `linux/amd64` and `linux/arm64` platforms. If running on a different platform, use the [`--platform` option](https://docs.docker.com/reference/cli/docker/container/run/) to emulate a supported platform.

### Users

Docker containers run as the `root` user by default. However, it is [considered a best practice](https://docs.docker.com/build/building/best-practices/#user) to run as a non-root user when possible. The `dovi_tool` container image provides a non-root user `apps` (UID `568`) and group `apps` (GID `568`) for this purpose.

For the `docker run` CLI, add the [`-u`, `--user` option](https://docs.docker.com/reference/cli/docker/container/run/) (`-u apps`) to run as the non-root user.

```sh
docker run --rm -it -u apps -v /path/to/media:/opt/media --entrypoint ash ghcr.io/br3ndonland/dovi_tool
```

For Docker Compose, add the [`user` key](https://docs.docker.com/reference/compose-file/services/#user) to the appropriate service (`user: apps`) to run as the non-root user.

```yaml
# compose.yaml
name: dovi_tool
services:
  dovi_tool:
    image: ghcr.io/br3ndonland/dovi_tool
    container_name: ${COMPOSE_PROJECT_NAME}
    pull_policy: always
    restart: "no"
    user: apps
    stdin_open: true
    tty: true
    entrypoint: ash
    environment:
      - STOP_IF_FEL=1
      - TZ=
    volumes:
      - /path/to/media:/opt/media
```

## Notes

### Dolby Vision Enhancement Layers

The `entrypoint.sh` script used in the `dovi_tool` Docker image converts Dolby Vision Profile 7 (`dvhe.07.06`) to Profile 8 (`dvhe.08.06`). In addition to the HDR10 Base Layer (BL), Profile 7 includes an "Enhancement Layer" (EL) and "Reference Picture Unit" (RPU) information.

The Profile 7 EL comes in two variants:

1. "Minimal Enhancement Layer" (MEL). On MEL sources, the EL is empty (included only for compatibility purposes) and the RPU has all of the Dolby Vision data.
2. "Full Enhancement Layer" (FEL). On FEL sources, the EL has additional color information, as well as luma and chroma mappings, increasing color bit depth to 12 bit.

Profile 8 only includes BL+RPU and does not include the EL. Converting a MEL from Profile 7 to Profile 8 is effectively a lossless conversion (because the RPU contains all Dolby Vision data), but converting a FEL from Profile 7 to Profile 8 is a lossy conversion because the additional color data must be discarded.

It is therefore helpful to know if a Profile 7 source is MEL or FEL. MediaInfo does not provide this information because it might require parsing the RPU, which is something MediaInfo does not do by default ([MediaArea/MediaInfo#721](https://github.com/MediaArea/MediaInfo/issues/721)).

To identify the EL type, the `entrypoint.sh` script extracts not only the converted RPU, but also the original Profile 7 RPU from the un-converted HEVC file. The script then summarizes the `.rpu.bin` file and outputs [L1 plots](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Content-Creation-Best-Practices-Guide?language=en_US) that include the enhancement layer variant (MEL/FEL), [Content Metadata](#dolby-vision-content-metadata) version (CMv2.9/CMv4.0), and shot-by-shot brightness levels for each RPU.

If the environment variable `STOP_IF_FEL` is set to `1`, the script will exit if it detects a FEL.

### Dolby Vision Content Metadata

Dolby Vision includes "[Content Metadata](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Metadata-Levels?language=en_US)" (CM) specifying the algorithm to use when displaying content. CMv4.0 is backwards-compatible with the previous CMv2.9, but in the past, some devices and applications have had limited support for CMv4.0.

The conversion process performed by the `entrypoint.sh` script will preserve CMv4.0 metadata.

### HDR10+

[`hdr10plus_tool`](https://github.com/quietvoid/hdr10plus_tool) is included in this project because it can be useful for converting HDR10+ metadata to Dolby Vision metadata.

A [`dovi_tool` generator config](https://github.com/quietvoid/dovi_tool/blob/main/docs/generator.md) is required in order to convert HDR10+ metadata. The Docker container image includes a default generator config that is suitable for general-purpose HDR10+ conversion. The default may not be adequate in all circumstances and further customization may be needed for best results.

An example HDR10+ conversion workflow might look like this:

```sh
input_filename=file.mkv
mkvextract "$input_filename" tracks 0:"${input_filename/.mkv/.hdr10plus.hevc}"
hdr10plus_tool extract "${input_filename/.mkv/.hdr10plus.hevc}" -o "${input_filename/.mkv/.hdr10plus.json}"
hdr10plus_tool plot "${input_filename/.mkv/.hdr10plus.json}" -o "${input_filename/.mkv/.hdr10plus_plot.png}"
dovi_tool generate -j /config/dovi_tool_generator_config.json --hdr10plus-json "${input_filename/.mkv/.hdr10plus.json}" -o "${input_filename/.mkv/.rpu.bin}"
dovi_tool plot "${input_filename/.mkv/.rpu.bin}" -o "${input_filename/.mkv/.dv8.l1_plot.png}"
dovi_tool inject-rpu -i "${input_filename/.mkv/.hdr10plus.hevc}" --rpu-in "${input_filename/.mkv/.rpu.bin}" -o "${input_filename/.mkv/.dv8.hevc}"
mkvmerge -o "${input_filename/.mkv/.dv8.mkv}" --no-video "$input_filename" "${input_filename/.mkv/.dv8.hevc}" --track-order 1:0
```

## Development

### Summary

- Docker container images are built with [GitHub Actions](https://docs.github.com/en/actions) using workflows in [`.github/workflows`](./.github/workflows/ci.yml). The GitHub Actions container build runs [`scripts/build.sh`](./scripts/build.sh).
- [mise-en-place](https://mise.jdx.dev/) is a tool manager. The [`mise.toml` configuration file](https://mise.jdx.dev/configuration.html) is used to install tools needed for the project.
- Shell scripts are checked with [ShellCheck](https://github.com/koalaman/shellcheck) and formatted with [`shfmt`](https://github.com/mvdan/sh).
- Web code (JSON, Markdown, YAML, etc.) is formatted with [Prettier](https://prettier.io/).
- [VSCode settings](https://code.visualstudio.com/docs/getstarted/settings) and [recommended extensions](https://code.visualstudio.com/docs/editor/extension-marketplace#_workspace-recommended-extensions) are included in the `.vscode` directory.

### Local container image builds

The [`build.sh`](scripts/build.sh) script can be used to build Docker container images locally. The [`.env.local`](.env.local) file includes required environment variables for local builds.

```sh
(source .env.local && ./scripts/build.sh)
```

The version-controlled `.env.local` file uses shell `export` assignments so it can be sourced before running the build script.

If `PLATFORMS` is unset or empty, the script omits `--platform` and Buildx builds for the builder's default platform. Multi-platform builds require Docker Buildx and platform emulation for whichever target is not native to the host. The default local command above uses the values in `.env.local` to build a runnable single-platform image.

To build a runnable local image, set `LOAD` to `true`, set `PLATFORMS` to one platform, and use manifest-only annotations.

```sh
export DOCKER_METADATA_ANNOTATIONS_LEVELS="manifest"
export LOAD="true"
export PLATFORMS="linux/amd64"
export TAG_LATEST="true"
```

Optional environment variables include:

- `BUILD_CONTEXT`: Should be set to `./dovi_tool` to match the layout of this repo. If not set, Docker uses the default `.` (repo root).
- `DOCKERFILE`: Should be set to `./dovi_tool/Dockerfile` to match the layout of this repo. If not set, Docker uses the default `Dockerfile` in the build context.
- `DOCKER_METADATA_ANNOTATIONS_LEVELS`: Comma-separated list of Docker Buildx annotation levels, such as `index`, `manifest`, `manifest-descriptor`, and `index-descriptor`. Docker [documents](https://docs.docker.com/build/metadata/annotations/#specify-annotation-level) that "the build must produce the component that you specify, or else the build will fail." For multi-platform builds, `DOCKER_METADATA_ANNOTATIONS_LEVELS="index,manifest"` are commonly used so that annotations are added to both the index and each platform manifest. For single-platform builds, use `DOCKER_METADATA_ANNOTATIONS_LEVELS="manifest"` and do not include `index` or `index-descriptor`. Set to an empty value to skip annotations.
- `DOCKER_METADATA_SHORT_SHA_LENGTH`: Number of characters to use for short SHA tags like `sha-860c190` (default `7`). The value must not exceed the full `GITHUB_SHA` length.
- `PLATFORMS`: Comma-separated target platforms. If unset or empty, the script omits `--platform` and Buildx uses the builder's default platform. The GitHub Actions workflow sets this to `linux/amd64,linux/arm64` for multi-platform builds.
- `LOAD`: To build a runnable local image, set to `true` or `1` to use [Buildx `--load`](https://docs.docker.com/reference/cli/docker/buildx/build/#load) and load the build result into the local Docker image store. Set to `false`, `0`, or leave unset to leave the result in the BuildKit cache, such as for multi-platform cache-only validation builds. The script rejects `LOAD="true"` with multiple platforms because `--load` uses the Docker exporter, and the Docker exporter does not export manifest lists from the temporary `docker-container` builder. Loading multi-platform images locally requires a different Docker setup with an image store that supports multi-platform images, such as the [containerd image store](https://docs.docker.com/desktop/features/containerd/).
- `OCI_SOURCE`: OCI image source URL. Defaults to `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}`.
- `OCI_TITLE`: OCI image title. Defaults to the repository name.
- `TAG_LATEST`: Set to `true` or `1` to tag the image with `${IMAGE_NAME}:latest`. Set to `false` or `0` to skip the `latest` tag. The default matches the push condition, so `latest` is added for `main` and tag builds in CI. Local builds can set `TAG_LATEST="true"` without enabling `--push`.
- If `GITHUB_SHA` or `RUNNER_TEMP` are not set, the script populates them from `git rev-parse HEAD` and `${TMPDIR:-/tmp}`.

### GitHub Actions container image builds

- The build script writes a lightweight GitHub Actions job summary when `GITHUB_STEP_SUMMARY` is available. The summary includes resolved build inputs, generated tags, labels, annotations, and Buildx metadata. It does not create a [`.dockerbuild` build record](https://docs.docker.com/reference/cli/docker/buildx/history/import/).
- `PROVENANCE`: Set to `false` or `0` to skip [BuildKit provenance attestations](https://docs.docker.com/build/metadata/attestations/slsa-provenance/). The script defaults to `true` for cache-only and push builds. If `LOAD="true"`, the script automatically skips provenance because, as stated in the Docker [docs](https://docs.docker.com/build/ci/github-actions/attestations/#max-level-provenance), images with attestations must be pushed to a registry instead of loaded to the local runner image store.
- `GHA_CACHE`: Set to `true` or `1` to use the Docker Buildx GitHub Actions cache backend with `--cache-from "type=gha"` and `--cache-to "type=gha,mode=max"`. Set to `false` or `0` to disable it. The default is `true` on GitHub Actions and `false` elsewhere. When enabled, the script requires `ACTIONS_RUNTIME_TOKEN` and either `ACTIONS_CACHE_URL` or `ACTIONS_RESULTS_URL`, so CI fails instead of silently skipping cache setup. The GitHub Actions workflow uses the local [GitHub runtime action](.github/actions/github-runtime) before running `scripts/build.sh`.
