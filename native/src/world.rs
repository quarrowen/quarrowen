//! Chunk storage mirrored from engine/shared/voxel_world.gd so physics can read blocks without
//! crossing into GDScript for every voxel.

use std::collections::HashMap;

use godot::prelude::*;

use crate::pathfind;
use crate::physics::{self, Body, Input, Rules};
use crate::{CHUNK_BYTES, LUT_SIZE, SIZE_Y, UNLOADED, VOLUME};

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeVoxelWorld {
    chunks: HashMap<(i32, i32), Box<[u16]>>,
    void_below: bool,
    solid: Lut,
    liquid: Lut,
    /// Which shape each block fills its cell with (BlockRegistry.Shape); 0 = the whole cell.
    shape: Lut,
    /// Blocks that stop line of sight (opaque blocks) and blocks mobs must never path through.
    sight: Lut,
    hazard: Lut,
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

    /// The boxes a block fills (see physics::SHAPE_BOXES); empty when nothing is there.
    #[inline]
    pub fn shape_at(&self, x: i32, y: i32, z: i32) -> &'static [[f32; 6]] {
        let block = self.block(x, y, z) as usize;
        if self.solid.0[block] != 1 {
            return &[];
        }
        crate::physics::boxes_of(self.shape.0[block])
    }

    #[inline]
    pub fn is_liquid(&self, x: i32, y: i32, z: i32) -> bool {
        self.liquid.0[self.block(x, y, z) as usize] == 1
    }

    #[inline]
    pub fn solid_at(&self, block: u16) -> bool {
        self.solid.0[block as usize] == 1
    }

    #[inline]
    pub fn liquid_at(&self, block: u16) -> bool {
        self.liquid.0[block as usize] == 1
    }

    #[inline]
    pub fn hazard_at(&self, block: u16) -> bool {
        self.hazard.0[block as usize] == 1
    }

    #[inline]
    pub fn sight_blocked_at(&self, block: u16) -> bool {
        self.sight.0[block as usize] == 1
    }
}

fn agent_from(values: &PackedInt32Array) -> pathfind::Agent {
    let v = values.as_slice();
    let at = |i: usize, default: i32| v.get(i).copied().unwrap_or(default);
    pathfind::Agent {
        width: at(0, 1).clamp(1, 8),
        height: at(1, 2).clamp(1, 16),
        step_up: at(2, 1).clamp(0, 8),
        max_drop: at(3, 3).clamp(0, 32),
        can_swim: at(4, 0) != 0,
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

    /// Blocks that do not fill their cell (slabs, stairs, fences): BlockRegistry.shape_lut.
    #[func]
    fn set_shape_table(&mut self, shapes: PackedByteArray) {
        copy_lut(&mut self.shape, &shapes);
        self.shape.0[UNLOADED as usize] = 0;  // unloaded blocks fill their whole cell
    }

    /// `sight`: 1 for blocks that stop line of sight; `hazard`: 1 for blocks mobs avoid.
    #[func]
    fn set_ai_tables(&mut self, sight: PackedByteArray, hazard: PackedByteArray) {
        copy_lut(&mut self.sight, &sight);
        copy_lut(&mut self.hazard, &hazard);
        self.sight.0[UNLOADED as usize] = 1;
        self.hazard.0[UNLOADED as usize] = 0;
    }

    /// A* for a mob. `agent`: [width, height, step_up, max_drop, can_swim] in blocks. Returns
    /// [(status, node count, expanded), node...] where nodes are footprint minimum corners from start
    /// to end; status 0 = no path, 1 = reached, 2 = partial (closest reachable node).
    #[func]
    fn find_path(&self, start: Vector3i, goal: Vector3i, radius: f32, agent: PackedInt32Array, max_nodes: i32) -> PackedVector3Array {
        let a = agent_from(&agent);
        let (status, nodes) = self.astar((start.x, start.y, start.z), (goal.x, goal.y, goal.z), radius, &a, max_nodes.clamp(1, 20000) as usize);
        let mut out = Vec::with_capacity(nodes.len() + 1);
        out.push(Vector3::new(status, nodes.len() as f32, 0.0));
        out.extend(nodes.iter().map(|n| Vector3::new(n.0 as f32, n.1 as f32, n.2 as f32)));
        PackedVector3Array::from(&out[..])
    }

    #[func]
    fn walkable_line(&self, from: Vector3i, to: Vector3i, agent: PackedInt32Array) -> bool {
        self.walk_line((from.x, from.y, from.z), (to.x, to.y, to.z), &agent_from(&agent))
    }

    #[func]
    fn standable(&self, node: Vector3i, agent: PackedInt32Array) -> bool {
        self.can_stand(node.x, node.y, node.z, &agent_from(&agent))
    }

    #[func]
    fn line_of_sight(&self, from: Vector3, to: Vector3) -> bool {
        self.sight_line([from.x, from.y, from.z], [to.x, to.y, to.z])
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
        let input = Input {
            move_input,
            yaw,
            jump: flags & 1 != 0,
            sprint: flags & 2 != 0,
            sneak: flags & 4 != 0,
            flying: flags & 8 != 0,
        };
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
