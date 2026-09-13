//! Native hot paths for the VoxelCraft engine. Everything here has a GDScript twin that is used when
//! the extension is not loaded, so the native code must stay behaviourally identical to it.

use godot::prelude::*;

mod js;
mod mesher;
mod pathfind;
mod physics;
mod process;
mod snapshot;
mod world;

struct VoxelcraftNative;

#[gdextension]
unsafe impl ExtensionLibrary for VoxelcraftNative {}

/// Chunk dimensions shared with engine/shared/chunk.gd.
pub const SIZE_X: i32 = 16;
pub const SIZE_Y: i32 = 128;
pub const SIZE_Z: i32 = 16;
pub const VOLUME: usize = (SIZE_X * SIZE_Y * SIZE_Z) as usize;
/// Chunk payloads store one little-endian u16 block id per cell.
pub const CHUNK_BYTES: usize = VOLUME * 2;
/// Lookup tables are indexed directly by block id.
pub const LUT_SIZE: usize = 65536;

/// Block id reported for positions in chunks that are not loaded (solid and opaque).
pub const UNLOADED: u16 = 0xFFFF;
