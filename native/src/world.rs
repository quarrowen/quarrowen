//! Chunk storage mirrored from engine/shared/voxel_world.gd so physics can read blocks without
//! crossing into GDScript for every voxel.

use std::collections::HashMap;

use godot::prelude::*;

use crate::physics::{self, Body, Input, Rules};
use crate::{CHUNK_BYTES, LUT_SIZE, SIZE_Y, UNLOADED, VOLUME};

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeVoxelWorld {
    chunks: HashMap<(i32, i32), Box<[u16]>>,
    void_below: bool,
    solid: Lut,
    liquid: Lut,
}

/// Lookup table indexed by block id (LUT_SIZE entries).
pub struct Lut(pub Box<[u8]>);

impl Default for Lut {
    fn default() -> Self {
        let mut lut = vec![0u8; LUT_SIZE].into_boxed_slice();
        lut[UNLOADED as usize] = 1;
        Lut(lut)
    }
}

impl NativeVoxelWorld {
    #[inline]
    pub fn block(&self, x: i32, y: i32, z: i32) -> u16 {
        if y < 0 {
            return if self.void_below { 0 } else { UNLOADED };
        }
        if y >= SIZE_Y {
            return 0;
        }
        match self.chunks.get(&(x >> 4, z >> 4)) {
            Some(chunk) => chunk[((x & 15) + ((z & 15) << 4) + (y << 8)) as usize],
            None => UNLOADED,
        }
    }

    #[inline]
    pub fn is_solid(&self, x: i32, y: i32, z: i32) -> bool {
        self.solid.0[self.block(x, y, z) as usize] == 1
    }

    #[inline]
    pub fn is_liquid(&self, x: i32, y: i32, z: i32) -> bool {
        self.liquid.0[self.block(x, y, z) as usize] == 1
    }
}

#[godot_api]
impl NativeVoxelWorld {
    /// Stores a copy of the chunk's blocks. Returns false if the data has the wrong size.
    #[func]
    fn set_chunk(&mut self, coord: Vector2i, blocks: PackedByteArray) -> bool {
        if blocks.len() != CHUNK_BYTES {
            return false;
        }
        self.chunks.insert((coord.x, coord.y), decode_ids(blocks.as_slice()));
        true
    }

    #[func]
    fn remove_chunk(&mut self, coord: Vector2i) {
        self.chunks.remove(&(coord.x, coord.y));
    }

    #[func]
    fn clear(&mut self) {
        self.chunks.clear();
    }

    #[func]
    fn get_block(&self, x: i32, y: i32, z: i32) -> i32 {
        self.block(x, y, z) as i32
    }

    #[func]
    fn set_block(&mut self, x: i32, y: i32, z: i32, id: i32) -> bool {
        if !(0..SIZE_Y).contains(&y) {
            return false;
        }
        match self.chunks.get_mut(&(x >> 4, z >> 4)) {
            Some(chunk) => {
                chunk[((x & 15) + ((z & 15) << 4) + (y << 8)) as usize] = id as u16;
                true
            }
            None => false,
        }
    }

    #[func]
    fn set_lookup_tables(&mut self, solid: PackedByteArray, liquid: PackedByteArray) {
        copy_lut(&mut self.solid, &solid);
        copy_lut(&mut self.liquid, &liquid);
        self.solid.0[UNLOADED as usize] = 1;
    }

    #[func]
    fn set_void_below(&mut self, enabled: bool) {
        self.void_below = enabled;
    }

    /// One fixed physics step. `flags`: 1 = jump, 2 = sprint. `rules` layout matches
    /// PlayerPhysics.Rules.TUNABLES. Returns [px, py, pz, vx, vy, vz, on_ground].
    #[func]
    fn step_player(
        &self,
        position: Vector3,
        velocity: Vector3,
        on_ground: bool,
        move_input: Vector2,
        yaw: f32,
        flags: i32,
        rules: PackedFloat32Array,
    ) -> PackedFloat32Array {
        let mut body = Body { position, velocity, on_ground };
        let input = Input { move_input, yaw, jump: flags & 1 != 0, sprint: flags & 2 != 0 };
        physics::step(&mut body, &input, self, &Rules::from_slice(rules.as_slice()));
        PackedFloat32Array::from(&[
            body.position.x,
            body.position.y,
            body.position.z,
            body.velocity.x,
            body.velocity.y,
            body.velocity.z,
            if body.on_ground { 1.0 } else { 0.0 },
        ][..])
    }

    /// Steps many entity bodies at once (EntityPhysics.step). Input: 11 floats per body
    /// [px, py, pz, vx, vy, vz, half_width, height, gravity, drag, on_ground]. Output: 7 floats per
    /// body [px, py, pz, vx, vy, vz, flags] with flags 1 = on ground, 2 = blocked sideways, 4 = in liquid.
    #[func]
    fn step_entities(&self, bodies: PackedFloat32Array, dt: f32) -> PackedFloat32Array {
        let input = bodies.as_slice();
        let count = input.len() / ENTITY_IN;
        let mut out = Vec::with_capacity(count * ENTITY_OUT);
        for chunk in input.chunks_exact(ENTITY_IN) {
            let mut body = Body {
                position: Vector3::new(chunk[0], chunk[1], chunk[2]),
                velocity: Vector3::new(chunk[3], chunk[4], chunk[5]),
                on_ground: chunk[10] > 0.5,
            };
            let size = physics::Size { half_width: chunk[6], height: chunk[7] };
            let result = physics::step_entity(&mut body, size, self, dt, chunk[8], chunk[9]);
            let flags = (body.on_ground as i32) | ((result.blocked as i32) << 1) | ((result.in_liquid as i32) << 2);
            out.extend_from_slice(&[
                body.position.x,
                body.position.y,
                body.position.z,
                body.velocity.x,
                body.velocity.y,
                body.velocity.z,
                flags as f32,
            ]);
        }
        PackedFloat32Array::from(&out[..])
    }
}

const ENTITY_IN: usize = 11;
const ENTITY_OUT: usize = 7;

/// Little-endian u16 ids from a chunk payload.
pub fn decode_ids(bytes: &[u8]) -> Box<[u16]> {
    let mut ids = vec![0u16; VOLUME].into_boxed_slice();
    for (i, pair) in bytes.chunks_exact(2).take(VOLUME).enumerate() {
        ids[i] = u16::from_le_bytes([pair[0], pair[1]]);
    }
    ids
}

fn copy_lut(target: &mut Lut, source: &PackedByteArray) {
    let src = source.as_slice();
    for (i, value) in target.0.iter_mut().enumerate() {
        *value = src.get(i).copied().unwrap_or(0);
    }
}
