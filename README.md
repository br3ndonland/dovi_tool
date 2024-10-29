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

Supported [environment variables](https://docs.docker.com/reference/cli/docker/container/run/#env):

- `DOVI_TRACK` (`0` or `>=1`, default `0`): Dolby Vision track in source video file, as reported by [`mkvinfo`](https://mkvtoolnix.download/doc/mkvinfo.html).
- `VIDEO_TRACK` (`0` or `>=1`, default `0`): HDR10 Base Layer (BL) video track in source video file, as reported by [`mkvinfo`](https://mkvtoolnix.download/doc/mkvinfo.html).
