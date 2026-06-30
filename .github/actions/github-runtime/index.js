const fs = require("node:fs")

const envFile = process.env.GITHUB_ENV
if (!envFile) {
  throw new Error("GITHUB_ENV is not set")
}

const names = [
  "ACTIONS_CACHE_SERVICE_V2",
  "ACTIONS_CACHE_URL",
  "ACTIONS_RESULTS_URL",
  "ACTIONS_RUNTIME_TOKEN",
  "ACTIONS_RUNTIME_URL",
]

for (const name of names) {
  const value = process.env[name]
  if (!value) {
    continue
  }

  if (name.endsWith("_TOKEN")) {
    process.stdout.write(`::add-mask::${value}\n`)
  }

  fs.appendFileSync(envFile, `${name}=${value}\n`)
  process.stdout.write(`Exported ${name}\n`)
}
