# README

## Description

This repo builds a Docker container image that can be used to run [dovi_tool](https://github.com/quietvoid/dovi_tool).

## Usage

```sh
docker pull ghcr.io/br3ndonland/dovi_tool
docker run --rm -it -v /path/to/media/dir:/opt/media ghcr.io/br3ndonland/dovi_tool '<filename>' dvhe.07
```

The Docker container will run the [`entrypoint.sh`](./dovi_tool/entrypoint.sh) script. The script will convert the [Dolby Vision profile](https://professionalsupport.dolby.com/s/article/What-is-Dolby-Vision-Profile?language=en_US) in the source media file from 7 to 8 for broader device compatibility.

**The original file will be overwritten after the conversion process is complete.**

Although the converted file will be the same size or smaller than the source file, the conversion process will temporarily require additional hard disk space. **It is recommended to have free hard disk space equal to 4x the size of the source file.** This allows space for the original `.mkv`, the extracted `.hevc`, the converted `.dv8.hevc`, and the remuxed `.mkv.tmp`.

Supported [environment variables](https://docs.docker.com/reference/cli/docker/container/run/#env):

- `CONVERT_FEL` (`0` or `1`, default `1`): whether or not to proceed with conversion if a [Full Enhancement Layer](#dolby-vision-enhancement-layers) (FEL) is detected. If `CONVERT_FEL=0` and a FEL is detected, the `entrypoint.sh` script will exit prior to converting the source file.
- `DOVI_TRACK` (`0` or `>=1`, default `0`): Dolby Vision track in source video file, as reported by [`mkvinfo`](https://mkvtoolnix.download/doc/mkvinfo.html).
- `VIDEO_TRACK` (`0` or `>=1`, default `0`): HDR10 Base Layer (BL) video track in source video file, as reported by [`mkvinfo`](https://mkvtoolnix.download/doc/mkvinfo.html).

## Notes

### Dolby Vision Enhancement Layers

The `entrypoint.sh` script used in the `dovi_tool` Docker image converts Dolby Vision Profile 7 (`dvhe.07.06`) to Profile 8 (`dvhe.08.06`). In addition to the HDR10 Base Layer (BL), Profile 7 includes an "Enhancement Layer" (EL) and "Reference Picture Unit" (RPU) information.

The Profile 7 EL comes in two variants:

1. "Minimal Enhancement Layer" (MEL). On MEL sources, the EL is empty (included only for compatibility purposes) and the RPU has all of the Dolby Vision data.
2. "Full Enhancement Layer" (FEL). On FEL sources, the EL has additional color information, as well as luma and chroma mappings, increasing color bit depth to 12 bit.

Profile 8 only includes BL+RPU and does not include the EL. Converting a MEL from Profile 7 to Profile 8 is effectively a lossless conversion (because the RPU contains all Dolby Vision data), but converting a FEL from Profile 7 to Profile 8 is a lossy conversion because the additional color data must be discarded.

It is therefore helpful to know if a Profile 7 source is MEL or FEL. MediaInfo does not provide this information because it might require parsing the RPU, which is something MediaInfo does not do by default ([MediaArea/MediaInfo#721](https://github.com/MediaArea/MediaInfo/issues/721)).

To identify the EL type, the `entrypoint.sh` script extracts not only the converted RPU, but also the original Profile 7 RPU from the un-converted HEVC file. The script then summarizes all `.rpu.bin` files in the same directory as the source MKV file and outputs [L1 plots](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Content-Creation-Best-Practices-Guide?language=en_US) that include the enhancement layer variant (MEL/FEL), [Content Metadata](#dolby-vision-content-metadata) version (CMv2.9/CMv4.0), and shot-by-shot brightness levels for each RPU.

If the environment variable `CONVERT_FEL` is set to `0`, the script will exit if it detects a FEL.

### Dolby Vision Content Metadata

Dolby Vision includes "[Content Metadata](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Metadata-Levels?language=en_US)" (CM) specifying the algorithm to use when displaying content. CMv4.0 is backwards-compatible with the previous CMv2.9, but in the past, some devices and applications have had limited support for CMv4.0.

The conversion process performed by the `entrypoint.sh` script will preserve CMv4.0 metadata.

## Development

- Docker container images are built with [GitHub Actions](https://docs.github.com/en/actions) using workflows in [`.github/workflows`](./.github/workflows/ci.yml).
- Shell scripts are checked with [ShellCheck](https://github.com/koalaman/shellcheck) and formatted with [`shfmt`](https://github.com/mvdan/sh).
- Web code (JSON, Markdown, YAML, etc.) is formatted with [Prettier](https://prettier.io/).
- [VSCode settings](https://code.visualstudio.com/docs/getstarted/settings) and [recommended extensions](https://code.visualstudio.com/docs/editor/extension-marketplace#_workspace-recommended-extensions) are included in the `.vscode` directory.
