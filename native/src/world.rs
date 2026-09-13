//! Chunk storage mirrored from engine/shared/voxel_world.gd so physics can read blocks without
//! crossing into GDScript for every voxel.

use std::collections::HashMap;

use godot::prelude::*;

use crate::physics::{self, Body, Input, Rules};
use crate::{SIZE_Y, UNLOADED, VOLUME};

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeVoxelWorld {
    chunks: HashMap<(i32, i32), Box<[u8]>>,
    void_below: bool,
    solid: Lut,
    liquid: Lut,
}

/// 256-entry lookup table indexed by block id.
pub struct Lut(pub [u8; 256]);

impl Default for Lut {
    fn default() -> Self {
        let mut lut = [0u8; 256];
        lut[UNLOADED as usize] = 1;
        Lut(lut)
    }
}

impl NativeVoxelWorld {
    #[inline]
    pub fn block(&self, x: i32, y: i32, z: i32) -> u8 {
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
        if blocks.len() != VOLUME {
            return false;
        }
        self.chunks.insert((coord.x, coord.y), blocks.as_slice().into());
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
                chunk[((x & 15) + ((z & 15) << 4) + (y << 8)) as usize] = id as u8;
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
}

fn copy_lut(target: &mut Lut, source: &PackedByteArray) {
    let src = source.as_slice();
    for (i, value) in target.0.iter_mut().enumerate() {
        *value = src.get(i).copied().unwrap_or(0);
    }
}
