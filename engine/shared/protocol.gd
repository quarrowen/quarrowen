extends RefCounted
## Wire protocol constants and limits shared by client and server.

## Bump whenever RPC signatures or payload layouts change.
const VERSION := 17
## Human-readable release shown in version mismatch messages.
const GAME_NAME := "VoxelCraft"
const GAME_VERSION := "0.17.0"

const MAX_ASSET_SIZE := 16 * 1024 * 1024
const MAX_TOTAL_ASSET_SIZE := 256 * 1024 * 1024
const MAX_ASSETS := 4096
const ASSET_PIECE_SIZE := 60 * 1024
const ASSET_BYTES_PER_TICK := 512 * 1024
const MAX_TEXTURE_SIZE := 256
