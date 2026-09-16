//! Port of engine/shared/player_physics.gd (players) and engine/shared/entity_physics.gd (entities).
//! Keep them in lockstep with the GDScript versions: the client predicts players with the same step
//! the server runs, so any divergence shows up as rubber-banding.

use godot::builtin::{Vector2, Vector3};

use crate::world::NativeVoxelWorld;

const DT: f32 = 1.0 / 60.0;
const HALF_WIDTH: f32 = 0.3;
const HEIGHT: f32 = 1.8;
const MAX_SUBSTEP: f32 = 0.45;
const SKIN: f32 = 0.001;
const EDGE: f32 = 0.0001;
const LIQUID_ACCEL: f32 = 20.0;
/// How far a walker is lifted onto a low block (a slab, the first step of a stairs) without jumping.
const STEP_HEIGHT: f32 = 0.55;

/// The boxes each block shape fills, in block space: the twin of BlockRegistry.SHAPE_BOXES.
const FULL_BOX: [[f32; 6]; 1] = [[0.0, 0.0, 0.0, 1.0, 1.0, 1.0]];
const SLAB_BOTTOM: [[f32; 6]; 1] = [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0]];
const SLAB_TOP: [[f32; 6]; 1] = [[0.0, 0.5, 0.0, 1.0, 1.0, 1.0]];
const STAIRS_NORTH: [[f32; 6]; 2] = [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.0, 0.5, 0.0, 1.0, 1.0, 0.5]];
const STAIRS_EAST: [[f32; 6]; 2] = [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.5, 0.5, 0.0, 1.0, 1.0, 1.0]];
const STAIRS_SOUTH: [[f32; 6]; 2] = [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.0, 0.5, 0.5, 1.0, 1.0, 1.0]];
const STAIRS_WEST: [[f32; 6]; 2] = [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.0, 0.5, 0.0, 0.5, 1.0, 1.0]];
const FENCE: [[f32; 6]; 1] = [[0.375, 0.0, 0.375, 0.625, 1.5, 0.625]];

/// The boxes for one shape id (BlockRegistry.Shape).
pub fn boxes_of(shape: u8) -> &'static [[f32; 6]] {
    match shape {
        1 => &SLAB_BOTTOM,
        2 => &SLAB_TOP,
        3 => &STAIRS_NORTH,
        4 => &STAIRS_EAST,
        5 => &STAIRS_SOUTH,
        6 => &STAIRS_WEST,
        7 => &FENCE,
        _ => &FULL_BOX,
    }
}
/// Crouching and flying, mirroring PlayerPhysics.
const SNEAK_SPEED: f32 = 0.3;
const FLY_SPEED: f32 = 10.0;
const FLY_SPRINT: f32 = 1.8;
const FLY_RISE: f32 = 8.0;

pub struct Body {
    pub position: Vector3,
    pub velocity: Vector3,
    pub on_ground: bool,
}

pub struct Input {
    pub move_input: Vector2,
    pub yaw: f32,
    pub jump: bool,
    pub sprint: bool,
    pub sneak: bool,
    pub flying: bool,
}

pub struct Rules {
    walk_speed: f32,
    sprint_speed: f32,
    gravity: f32,
    jump_velocity: f32,
    terminal_velocity: f32,
    ground_accel: f32,
    air_accel: f32,
    swim_speed: f32,
    sink_speed: f32,
}

impl Rules {
    /// Same order as PlayerPhysics.Rules.TUNABLES; missing values fall back to engine defaults.
    pub fn from_slice(v: &[f32]) -> Self {
        let at = |i: usize, default: f32| v.get(i).copied().unwrap_or(default);
        Rules {
            walk_speed: at(0, 4.3),
            sprint_speed: at(1, 5.6),
            gravity: at(2, 32.0),
            jump_velocity: at(3, 9.0),
            terminal_velocity: at(4, 60.0),
            ground_accel: at(5, 60.0),
            air_accel: at(6, 12.0),
            swim_speed: at(7, 3.0),
            sink_speed: at(8, 2.0),
        }
    }
}

/// A collision box: half width (x/z) and height, feet at the position.
#[derive(Clone, Copy)]
pub struct Size {
    pub half_width: f32,
    pub height: f32,
}

const PLAYER: Size = Size { half_width: HALF_WIDTH, height: HEIGHT };

/// Result flags of an entity step.
pub struct EntityStep {
    pub blocked: bool,
    pub in_liquid: bool,
}

/// One entity step (EntityPhysics.step): gravity, liquid drag, airborne drag, collision.
pub fn step_entity(s: &mut Body, size: Size, world: &NativeVoxelWorld, dt: f32, gravity: f32, drag: f32) -> EntityStep {
    if collides(s.position, size, world) {
        s.position.y += 0.25;
        s.velocity = Vector3::ZERO;
        s.on_ground = false;
        return EntityStep { blocked: false, in_liquid: false };
    }
    let in_liquid = world.is_liquid(
        s.position.x.floor() as i32,
        (s.position.y + (size.height * 0.5).min(0.4)).floor() as i32,
        s.position.z.floor() as i32,
    );
    if in_liquid {
        s.velocity.y = move_toward(s.velocity.y, -1.5, 12.0 * dt);
        let damp = (1.0 - 3.0 * dt).max(0.0);
        s.velocity.x *= damp;
        s.velocity.z *= damp;
    } else {
        s.velocity.y = (s.velocity.y - gravity * dt).max(-60.0);
        if drag > 0.0 && !s.on_ground {
            let damp = (1.0 - drag * dt).max(0.0);
            s.velocity.x *= damp;
            s.velocity.z *= damp;
        }
    }
    let motion = s.velocity * dt;
    let largest = motion.x.abs().max(motion.y.abs()).max(motion.z.abs());
    let steps = ((largest / MAX_SUBSTEP).ceil() as i32).max(1);
    let mut part = motion / steps as f32;
    s.on_ground = false;
    let mut blocked = false;
    for _ in 0..steps {
        if move_axis(s, 1, part.y, size, world) {
            if part.y < 0.0 {
                s.on_ground = true;
            }
            s.velocity.y = 0.0;
            part.y = 0.0;
        }
        if move_axis(s, 0, part.x, size, world) {
            s.velocity.x = 0.0;
            part.x = 0.0;
            blocked = true;
        }
        if move_axis(s, 2, part.z, size, world) {
            s.velocity.z = 0.0;
            part.z = 0.0;
            blocked = true;
        }
    }
    EntityStep { blocked, in_liquid }
}

pub fn step(s: &mut Body, input: &Input, world: &NativeVoxelWorld, rules: &Rules) {
    if collides(s.position, PLAYER, world) {
        // Stuck inside a block (terrain changed around us): push upward until free.
        s.position.y += 0.25;
        s.velocity = Vector3::ZERO;
        s.on_ground = false;
        return;
    }

    let mut mv = input.move_input;
    if mv.x * mv.x + mv.y * mv.y > 1.0 {
        mv = normalized2(mv);
    }
    let (sin_yaw, cos_yaw) = (libm::sinf(input.yaw), libm::cosf(input.yaw));
    let wish_x = cos_yaw * mv.x - sin_yaw * mv.y;
    let wish_z = -sin_yaw * mv.x - cos_yaw * mv.y;
    let in_liquid = world.is_liquid(
        s.position.x.floor() as i32,
        (s.position.y + 0.4).floor() as i32,
        s.position.z.floor() as i32,
    );

    let mut speed = if input.sprint && mv.y > 0.0 { rules.sprint_speed } else { rules.walk_speed };
    if input.flying {
        speed = FLY_SPEED * if input.sprint { FLY_SPRINT } else { 1.0 };
    } else if input.sneak && s.on_ground {
        speed *= SNEAK_SPEED;
    }
    if in_liquid && !input.flying {
        speed *= 0.5;
    }
    let accel = if s.on_ground || in_liquid || input.flying { rules.ground_accel } else { rules.air_accel };
    let horizontal = move_toward2(
        Vector2::new(s.velocity.x, s.velocity.z),
        Vector2::new(wish_x * speed, wish_z * speed),
        accel * DT,
    );
    s.velocity.x = horizontal.x;
    s.velocity.z = horizontal.y;

    if input.flying {
        let rise = if input.jump { FLY_RISE } else { 0.0 } - if input.sneak { FLY_RISE } else { 0.0 };
        s.velocity.y = move_toward(s.velocity.y, rise, rules.ground_accel * DT);
    } else if in_liquid {
        let target = if input.jump { rules.swim_speed } else { -rules.sink_speed };
        s.velocity.y = move_toward(s.velocity.y, target, LIQUID_ACCEL * DT);
    } else {
        if input.jump && s.on_ground {
            s.velocity.y = rules.jump_velocity;
        }
        s.velocity.y = (s.velocity.y - rules.gravity * DT).max(-rules.terminal_velocity);
    }

    let motion = s.velocity * DT;
    let largest = motion.x.abs().max(motion.y.abs()).max(motion.z.abs());
    let steps = ((largest / MAX_SUBSTEP).ceil() as i32).max(1);
    let mut part = motion / steps as f32;
    // Crouching on solid ground: a sideways step that would leave nothing underfoot is refused.
    let edge_guard = input.sneak && s.on_ground && !input.flying && !in_liquid;
    let was_grounded = s.on_ground;
    s.on_ground = false;
    for _ in 0..steps {
        if move_axis(s, 1, part.y, PLAYER, world) {
            if part.y < 0.0 {
                s.on_ground = true;
            }
            s.velocity.y = 0.0;
            part.y = 0.0;
        }
        let mut before = s.position;
        let mut blocked_x = move_axis(s, 0, part.x, PLAYER, world);
        if !blocked_x && edge_guard && !supported(s.position, world) {
            s.position = before;
            s.velocity.x = 0.0;
            part.x = 0.0;
        }
        before = s.position;
        let mut blocked_z = move_axis(s, 2, part.z, PLAYER, world);
        if !blocked_z && edge_guard && !supported(s.position, world) {
            s.position = before;
            s.velocity.z = 0.0;
            part.z = 0.0;
        }
        // Walking into something low (a slab, the first step of a stairs) lifts the player onto it and lets
        // the same step carry on, so stairs are climbed by walking rather than jumping.
        if (blocked_x || blocked_z) && (was_grounded || s.on_ground) && !input.flying && !input.sneak {
            let wish = Vector3::new(
                if blocked_x { part.x } else { 0.0 },
                0.0,
                if blocked_z { part.z } else { 0.0 },
            );
            if let Some(top) = step_target(s.position, PLAYER, wish, world) {
                if top - s.position.y <= STEP_HEIGHT {
                    s.position.y = top + SKIN;
                    s.velocity.y = s.velocity.y.max(0.0);
                    s.on_ground = true;
                    if blocked_x {
                        blocked_x = move_axis(s, 0, part.x, PLAYER, world);
                    }
                    if blocked_z {
                        blocked_z = move_axis(s, 2, part.z, PLAYER, world);
                    }
                }
            }
        }
        if blocked_x {
            s.velocity.x = 0.0;
            part.x = 0.0;
        }
        if blocked_z {
            s.velocity.z = 0.0;
            part.z = 0.0;
        }
    }
}

/// Solid ground just under the player's box (the crouch edge guard).
fn supported(position: Vector3, world: &NativeVoxelWorld) -> bool {
    collides(position - Vector3::new(0.0, 0.08, 0.0), PLAYER, world)
}

fn axis(v: Vector3, i: usize) -> f32 {
    match i {
        0 => v.x,
        1 => v.y,
        _ => v.z,
    }
}

fn set_axis(v: &mut Vector3, i: usize, value: f32) {
    match i {
        0 => v.x = value,
        1 => v.y = value,
        _ => v.z = value,
    }
}

/// Moves along one axis; on collision snaps flush against the blocking voxel.
/// Moves the box along one axis as far as the blocks (whole cells, slabs, stairs, fences) allow.
/// The twin of BlockShapes.sweep; returns true when something stopped it short.
fn move_axis(s: &mut Body, i: usize, delta: f32, size: Size, world: &NativeVoxelWorld) -> bool {
    if delta == 0.0 {
        return false;
    }
    let (travelled, hit) = sweep(s.position, size, i, delta, world);
    let moved = axis(s.position, i) + travelled;
    set_axis(&mut s.position, i, moved);
    hit
}

fn extent(p: Vector3, size: Size, i: usize) -> (f32, f32) {
    let lo = axis(p, i) - if i == 1 { 0.0 } else { size.half_width };
    (lo, lo + if i == 1 { size.height } else { size.half_width * 2.0 })
}

fn sweep(position: Vector3, size: Size, i: usize, delta: f32, world: &NativeVoxelWorld) -> (f32, bool) {
    let mut target = position;
    set_axis(&mut target, i, axis(position, i) + delta);
    let low = Vector3::new(position.x.min(target.x), position.y.min(target.y), position.z.min(target.z));
    let high = Vector3::new(position.x.max(target.x), position.y.max(target.y), position.z.max(target.z));
    let x0 = (low.x - size.half_width).floor() as i32;
    let x1 = (high.x + size.half_width - EDGE).floor() as i32;
    let y0 = low.y.floor() as i32 - 1; // a fence in the cell below still blocks
    let y1 = (high.y + size.height - EDGE).floor() as i32;
    let z0 = (low.z - size.half_width).floor() as i32;
    let z1 = (high.z + size.half_width - EDGE).floor() as i32;
    let mut limit = delta;
    let mut hit = false;
    for y in y0..=y1 {
        for z in z0..=z1 {
            for x in x0..=x1 {
                for b in world.shape_at(x, y, z) {
                    let box_min = Vector3::new(x as f32 + b[0], y as f32 + b[1], z as f32 + b[2]);
                    let box_max = Vector3::new(x as f32 + b[3], y as f32 + b[4], z as f32 + b[5]);
                    if !crosses(position, size, i, box_min, box_max) {
                        continue;
                    }
                    let (lo, hi) = extent(position, size, i);
                    let allowed = if delta > 0.0 && axis(box_min, i) >= hi - EDGE {
                        (axis(box_min, i) - hi - SKIN).max(0.0)
                    } else if delta < 0.0 && axis(box_max, i) <= lo + EDGE {
                        (axis(box_max, i) - lo + SKIN).min(0.0)
                    } else {
                        continue; // beside the move, or already overlapping
                    };
                    if allowed.abs() < limit.abs() {
                        limit = allowed;
                        hit = true;
                    }
                }
            }
        }
    }
    (limit, hit)
}

/// Whether the box overlaps a block's box on the two axes it is not moving along.
fn crosses(position: Vector3, size: Size, i: usize, box_min: Vector3, box_max: Vector3) -> bool {
    for other in 0..3 {
        if other == i {
            continue;
        }
        let (lo, hi) = extent(position, size, other);
        if hi - EDGE <= axis(box_min, other) || lo + EDGE >= axis(box_max, other) {
            return false;
        }
    }
    true
}

/// Where a step up would put the feet (the highest surface just ahead within reach), or None.
fn step_target(position: Vector3, size: Size, direction: Vector3, world: &NativeVoxelWorld) -> Option<f32> {
    let flat = Vector3::new(direction.x, 0.0, direction.z);
    let length = libm::sqrtf(flat.x * flat.x + flat.z * flat.z);
    if length <= 0.0 {
        return None;
    }
    let ahead = position + flat * ((size.half_width + 0.15) / length);
    let mut best = f32::NEG_INFINITY;
    for x in (ahead.x - size.half_width).floor() as i32..=(ahead.x + size.half_width - EDGE).floor() as i32 {
        for z in (ahead.z - size.half_width).floor() as i32..=(ahead.z + size.half_width - EDGE).floor() as i32 {
            for y in position.y.floor() as i32..=(position.y + STEP_HEIGHT).floor() as i32 {
                for b in world.shape_at(x, y, z) {
                    let top = y as f32 + b[4];
                    if top > position.y + EDGE && top <= position.y + STEP_HEIGHT {
                        best = best.max(top);
                    }
                }
            }
        }
    }
    if best == f32::NEG_INFINITY {
        return None;
    }
    let landing = Vector3::new(ahead.x, best + SKIN, ahead.z);
    if collides(landing, size, world) {
        None
    } else {
        Some(best)
    }
}

fn collides(p: Vector3, size: Size, world: &NativeVoxelWorld) -> bool {
    let x0 = (p.x - size.half_width).floor() as i32;
    let x1 = (p.x + size.half_width - EDGE).floor() as i32;
    let y0 = p.y.floor() as i32 - 1; // shapes can stand taller than their cell (a fence)
    let y1 = (p.y + size.height - EDGE).floor() as i32;
    let z0 = (p.z - size.half_width).floor() as i32;
    let z1 = (p.z + size.half_width - EDGE).floor() as i32;
    for y in y0..=y1 {
        for z in z0..=z1 {
            for x in x0..=x1 {
                for b in world.shape_at(x, y, z) {
                    if p.x - size.half_width + EDGE < x as f32 + b[3]
                        && p.x + size.half_width - EDGE > x as f32 + b[0]
                        && p.y + EDGE < y as f32 + b[4]
                        && p.y + size.height - EDGE > y as f32 + b[1]
                        && p.z - size.half_width + EDGE < z as f32 + b[5]
                        && p.z + size.half_width - EDGE > z as f32 + b[2]
                    {
                        return true;
                    }
                }
            }
        }
    }
    false
}

fn normalized2(v: Vector2) -> Vector2 {
    let len = libm::sqrtf(v.x * v.x + v.y * v.y);
    if len == 0.0 {
        v
    } else {
        Vector2::new(v.x / len, v.y / len)
    }
}

/// Matches Godot's Vector2.move_toward.
fn move_toward2(from: Vector2, to: Vector2, delta: f32) -> Vector2 {
    let d = Vector2::new(to.x - from.x, to.y - from.y);
    let len = libm::sqrtf(d.x * d.x + d.y * d.y);
    if len <= delta || len < 0.00001 {
        to
    } else {
        Vector2::new(from.x + d.x / len * delta, from.y + d.y / len * delta)
    }
}

/// Matches Godot's move_toward for scalars.
fn move_toward(from: f32, to: f32, delta: f32) -> f32 {
    if (to - from).abs() <= delta {
        to
    } else {
        from + (to - from).signum() * delta
    }
}
