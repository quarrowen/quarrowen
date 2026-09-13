//! Builds per-player state snapshots (see GameServer._build_snapshot for the layout) using a uniform
//! grid so each player only examines nearby cells instead of every other player.

use std::collections::HashMap;

use godot::prelude::*;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeSnapshots {}

#[godot_api]
impl NativeSnapshots {
    /// Parallel arrays describe every player. Players within `radius` are included; those beyond
    /// `near_radius` only when `full_rate` is true (the server alternates it to halve far updates).
    /// Returns one PackedByteArray per player, in input order.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn build(
        peer_ids: PackedInt32Array,
        seqs: PackedInt32Array,
        positions: PackedVector3Array,
        velocities: PackedVector3Array,
        yaws: PackedFloat32Array,
        pitches: PackedFloat32Array,
        grounded: PackedByteArray,
        radius: f32,
        near_radius: f32,
        full_rate: bool,
    ) -> VarArray {
        let n = peer_ids.len();
        let mut out = VarArray::new();
        let (ids, seqs, pos, vel, yaws, pitches, grounded) = (
            peer_ids.as_slice(),
            seqs.as_slice(),
            positions.as_slice(),
            velocities.as_slice(),
            yaws.as_slice(),
            pitches.as_slice(),
            grounded.as_slice(),
        );
        if [seqs.len(), pos.len(), vel.len(), yaws.len(), pitches.len(), grounded.len()].iter().any(|&l| l != n) || radius <= 0.0 {
            return out;
        }

        let cell_of = |p: Vector3| ((p.x / radius).floor() as i32, (p.z / radius).floor() as i32);
        let mut grid: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
        for (i, p) in pos.iter().enumerate() {
            grid.entry(cell_of(*p)).or_default().push(i);
        }

        let (radius_sq, near_sq) = (radius * radius, near_radius * near_radius);
        let mut buf: Vec<u8> = Vec::with_capacity(256);
        for i in 0..n {
            buf.clear();
            buf.extend_from_slice(&seqs[i].to_le_bytes());
            for v in [pos[i].x, pos[i].y, pos[i].z, vel[i].x, vel[i].y, vel[i].z] {
                buf.extend_from_slice(&v.to_le_bytes());
            }
            buf.push(u8::from(grounded[i] != 0));
            let count_at = buf.len();
            buf.extend_from_slice(&0u16.to_le_bytes());
            let mut count: u16 = 0;
            let (cx, cz) = cell_of(pos[i]);
            for dx in -1..=1 {
                for dz in -1..=1 {
                    let Some(members) = grid.get(&(cx + dx, cz + dz)) else { continue };
                    for &j in members {
                        if j == i || count == u16::MAX {
                            continue;
                        }
                        let d = pos[j] - pos[i];
                        let dist_sq = d.x * d.x + d.y * d.y + d.z * d.z;
                        if dist_sq > radius_sq || (dist_sq > near_sq && !full_rate) {
                            continue;
                        }
                        buf.extend_from_slice(&ids[j].to_le_bytes());
                        for v in [pos[j].x, pos[j].y, pos[j].z] {
                            buf.extend_from_slice(&v.to_le_bytes());
                        }
                        let tau = std::f32::consts::TAU;
                        let half_pi = std::f32::consts::FRAC_PI_2;
                        let yaw = (yaws[j].rem_euclid(tau) / tau * 65535.0) as u16;
                        let pitch = (pitches[j].clamp(-half_pi, half_pi) / half_pi * 32767.0) as i16;
                        buf.extend_from_slice(&yaw.to_le_bytes());
                        buf.extend_from_slice(&pitch.to_le_bytes());
                        count += 1;
                    }
                }
            }
            buf[count_at..count_at + 2].copy_from_slice(&count.to_le_bytes());
            out.push(&PackedByteArray::from(&buf[..]).to_variant());
        }
        out
    }
}
