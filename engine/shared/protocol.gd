extends RefCounted
## Wire protocol constants and limits shared by client and server.

## Bump whenever RPC signatures or payload layouts change - and whenever the client and server must
## agree on something the wire does not carry, such as the block shape table: an older client that does
## not know a shape walks into a different world from the one the server is simulating, and the player
## sees it as rubber-banding rather than as a version problem.
const VERSION := 52
## Human-readable release shown in version mismatch messages.
const GAME_NAME := "Quarrowen"
const GAME_VERSION := "0.42.0"
## The mod API's semantic version: mods declare what they work with in mod.json ("engine": "^1.0").
## Bump the minor version when the API gains things, the major when something mods use changes.
const MOD_API_VERSION := "1.0.0"

const MAX_ASSET_SIZE := 16 * 1024 * 1024
const MAX_TOTAL_ASSET_SIZE := 256 * 1024 * 1024
const MAX_ASSETS := 4096
const ASSET_PIECE_SIZE := 60 * 1024
const ASSET_BYTES_PER_TICK := 512 * 1024
const MAX_TEXTURE_SIZE := 256
