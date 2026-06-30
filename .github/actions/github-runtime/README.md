# GitHub runtime action

## Description

The Docker [GitHub Actions cache backend](https://docs.docker.com/build/cache/backends/gha/) (`type=gha`) uses cache runtime variables like `ACTIONS_CACHE_URL` and `ACTIONS_RUNTIME_TOKEN`. The GitHub Actions runner exposes these cache runtime variables to the [Node.js JavaScript runtime](https://github.com/actions/runner/blob/1ed4f70ee92b31d200d4d446958f47decd2d998f/src/Runner.Worker/Handlers/NodeScriptActionHandler.cs) but not to [shell `run:` steps](https://github.com/actions/runner/blob/1ed4f70ee92b31d200d4d446958f47decd2d998f/src/Runner.Worker/Handlers/ScriptHandler.cs).

This action reads the Node.js JavaScript runtime environment variables and exports them for later shell steps.
