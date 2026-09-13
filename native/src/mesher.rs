//! Chunk meshing with flood-fill lighting and greedy face merging. Called from Godot WorkerThreadPool
//! threads; it only reads its arguments.
//!
//! Output vertex format (shared with the GDScript fallback in engine/client/chunk_mesher.gd and the
//! shader in engine/client/voxel_material.gd):
//!   UV       texture coordinates in block units (repeat per block across merged quads)
//!   CUSTOM0  atlas rect of the tile (x, y, w, h)
//!   COLOR    r = sky light, g = block light (0..1), b = directional face shade, a = ambient occlusion
//!   UV2      x = flags: 1 sway (foliage), 2 liquid, 4 emissive

use godot::classes::mesh::ArrayType;
use godot::prelude::*;

use crate::{CHUNK_BYTES, LUT_SIZE, SIZE_Y, UNLOADED};

const RENDER_OPAQUE: u8 = 1;
const RENDER_TRANSLUCENT: u8 = 3;
const RENDER_MODEL: u8 = 4;
const RENDER_PLANT: u8 = 5;
const MAX_LIGHT: u8 = 15;
const LIQUID_TOP: f32 = 0.88;

/// The 3x3 chunk neighbourhood around the chunk being meshed.
const RX: usize = 48;
const RZ: usize = 48;
const RY: usize = SIZE_Y as usize;
const REGION: usize = RX * RZ * RY;
const OFFSET: usize = 16;

/// Crossed diagonal quads for plants, each listed once per side (the solid material culls back faces).
const PLANT_QUADS: [[[f32; 3]; 4]; 4] = [
    [[0., 1., 0.], [1., 1., 1.], [1., 0., 1.], [0., 0., 0.]],
    [[1., 1., 1.], [0., 1., 0.], [0., 0., 0.], [1., 0., 1.]],
    [[1., 1., 0.], [0., 1., 1.], [0., 0., 1.], [1., 0., 0.]],
    [[0., 1., 1.], [1., 1., 0.], [1., 0., 0.], [0., 0., 1.]],
];

// Corners per face, clockwise viewed from outside (Godot front faces). Order: +X, -X, +Y, -Y, +Z, -Z.
const CORNERS: [[[f32; 3]; 4]; 6] = [
    [[1., 1., 1.], [1., 1., 0.], [1., 0., 0.], [1., 0., 1.]],
    [[0., 1., 0.], [0., 1., 1.], [0., 0., 1.], [0., 0., 0.]],
    [[0., 1., 0.], [1., 1., 0.], [1., 1., 1.], [0., 1., 1.]],
    [[0., 0., 1.], [1., 0., 1.], [1., 0., 0.], [0., 0., 0.]],
    [[0., 1., 1.], [1., 1., 1.], [1., 0., 1.], [0., 0., 1.]],
    [[1., 1., 0.], [0., 1., 0.], [0., 0., 0.], [1., 0., 0.]],
];
const NORMALS: [[i32; 3]; 6] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
const SHADE: [f32; 6] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68];
/// Per face: (slice axis, u axis, v axis) as indices into [x, y, z].
const AXES: [(usize, usize, usize); 6] = [(0, 2, 1), (0, 2, 1), (1, 0, 2), (1, 0, 2), (2, 0, 1), (2, 0, 1)];

#[inline]
fn ridx(x: usize, y: usize, z: usize) -> usize {
    x + z * RX + y * RX * RZ
}

#[derive(Default)]
struct Surface {
    verts: Vec<Vector3>,
    normals: Vec<Vector3>,
    uvs: Vec<Vector2>,
    colors: Vec<Color>,
    uv2s: Vec<Vector2>,
    custom: Vec<f32>,
    indices: Vec<i32>,
}

impl Surface {
    /// `light`: per corner [sky, block, ao (0-3)].
    fn add_quad(&mut self, corners: [Vector3; 4], face: usize, tile: &[f32], light: [[u8; 3]; 4], flags: f32) {
        let n = self.verts.len() as i32;
        let normal = NORMALS[face];
        let w = (corners[1] - corners[0]).length();
        let h = (corners[3] - corners[0]).length();
        let uv = [Vector2::new(0.0, 0.0), Vector2::new(w, 0.0), Vector2::new(w, h), Vector2::new(0.0, h)];
        for k in 0..4 {
            self.verts.push(corners[k]);
            self.normals.push(Vector3::new(normal[0] as f32, normal[1] as f32, normal[2] as f32));
            let [sky, block, ao] = light[k];
            self.colors.push(Color::from_rgba(sky as f32 / 15.0, block as f32 / 15.0, SHADE[face], ao as f32 / 3.0));
            self.uvs.push(uv[k]);
            self.uv2s.push(Vector2::new(flags, 0.0));
            self.custom.extend_from_slice(tile);
        }
        // Split along the brighter diagonal so occlusion gradients don't look creased.
        let ao = |k: usize| light[k][2] as u32;
        if ao(0) + ao(2) < ao(1) + ao(3) {
            self.indices.extend_from_slice(&[n, n + 1, n + 3, n + 1, n + 2, n + 3]);
        } else {
            self.indices.extend_from_slice(&[n, n + 1, n + 2, n, n + 2, n + 3]);
        }
    }

    /// A plant: crossed quads through the cell at `p`, lit by the cell's own light, texture 0..1.
    fn add_plant(&mut self, p: [usize; 3], tile: &[f32], sky: u8, block: u8, flags: f32) {
        let uv = [Vector2::new(0.0, 0.0), Vector2::new(1.0, 0.0), Vector2::new(1.0, 1.0), Vector2::new(0.0, 1.0)];
        for quad in PLANT_QUADS.iter() {
            let n = self.verts.len() as i32;
            for k in 0..4 {
                let c = quad[k];
                self.verts.push(Vector3::new(p[0] as f32 + c[0], p[1] as f32 + c[1], p[2] as f32 + c[2]));
                self.normals.push(Vector3::UP);
                self.colors.push(Color::from_rgba(sky as f32 / 15.0, block as f32 / 15.0, 0.9, 1.0));
                self.uvs.push(uv[k]);
                self.uv2s.push(Vector2::new(flags, 0.0));
                self.custom.extend_from_slice(tile);
            }
            self.indices.extend_from_slice(&[n, n + 1, n + 2, n, n + 2, n + 3]);
        }
    }

    fn into_arrays(self) -> VarArray {
        let mut arrays = VarArray::new();
        if self.verts.is_empty() {
            return arrays;
        }
        arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
        arrays.set(ArrayType::VERTEX.ord() as usize, &PackedVector3Array::from(&self.verts[..]).to_variant());
        arrays.set(ArrayType::NORMAL.ord() as usize, &PackedVector3Array::from(&self.normals[..]).to_variant());
        arrays.set(ArrayType::TEX_UV.ord() as usize, &PackedVector2Array::from(&self.uvs[..]).to_variant());
        arrays.set(ArrayType::COLOR.ord() as usize, &PackedColorArray::from(&self.colors[..]).to_variant());
        arrays.set(ArrayType::TEX_UV2.ord() as usize, &PackedVector2Array::from(&self.uv2s[..]).to_variant());
        arrays.set(ArrayType::CUSTOM0.ord() as usize, &PackedFloat32Array::from(&self.custom[..]).to_variant());
        arrays.set(ArrayType::INDEX.ord() as usize, &PackedInt32Array::from(&self.indices[..]).to_variant());
        arrays
    }
}

struct Tables<'a> {
    opaque: &'a [u8],
    render: &'a [u8],
    cull_same: &'a [u8],
    liquid: &'a [u8],
    emission: &'a [u8],
    sway: &'a [u8],
    uvs: &'a [f32],
    ambient_occlusion: bool,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeMesher {}

#[godot_api]
impl NativeMesher {
    /// `chunks`: 9 PackedByteArrays (u16 ids) for the 3x3 neighbourhood, index (dx + 1) + (dz + 1) * 3,
    /// with an empty array for chunks that are not loaded. Lookup tables have LUT_SIZE entries.
    /// `face_uvs`: 4 floats per registered block per face, followed by 4 floats for the "missing" tile. Returns [solid_arrays, translucent_arrays, models] where either arrays may be empty and
    /// `models` is a PackedInt32Array of (block id, x, y, z, sky light, block light) per model block.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn build(
        chunks: VarArray,
        opaque: PackedByteArray,
        render: PackedByteArray,
        cull_same: PackedByteArray,
        liquid: PackedByteArray,
        emission: PackedByteArray,
        sway: PackedByteArray,
        face_uvs: PackedFloat32Array,
        lighting: bool,
        ambient_occlusion: bool,
    ) -> VarArray {
        let mut out = VarArray::new();
        let empty = || VarArray::new().to_variant();
        let tables = Tables {
            opaque: opaque.as_slice(),
            render: render.as_slice(),
            cull_same: cull_same.as_slice(),
            liquid: liquid.as_slice(),
            emission: emission.as_slice(),
            sway: sway.as_slice(),
            uvs: face_uvs.as_slice(),
            ambient_occlusion,
        };
        let byte_arrays: Vec<PackedByteArray> =
            (0..9).map(|i| chunks.get(i).and_then(|v| v.try_to::<PackedByteArray>().ok()).unwrap_or_default()).collect();
        if chunks.len() != 9
            || byte_arrays[4].len() != CHUNK_BYTES
            || [tables.opaque, tables.render, tables.cull_same, tables.liquid, tables.emission, tables.sway].iter().any(|t| t.len() < LUT_SIZE)
            || tables.uvs.len() < 4
        {
            out.push(&empty());
            out.push(&empty());
            out.push(&PackedInt32Array::new().to_variant());
            return out;
        }

        let region = fill_region(&byte_arrays);
        let (sky, block_light) = if lighting { compute_light(&region, &tables) } else { full_bright() };
        let (solid, translucent) = mesh_center(&region, &sky, &block_light, &tables);
        out.push(&solid.into_arrays().to_variant());
        out.push(&translucent.into_arrays().to_variant());
        out.push(&PackedInt32Array::from(&model_instances(&region, &sky, &block_light, &tables)[..]).to_variant());
        out
    }
}

/// Copies the 3x3 chunks into one 48 x 128 x 48 volume; missing chunks are filled with UNLOADED.
fn fill_region(chunks: &[PackedByteArray]) -> Vec<u16> {
    let mut region = vec![UNLOADED; REGION];
    for cz in 0..3 {
        for cx in 0..3 {
            let data = chunks[cx + cz * 3].as_slice();
            if data.len() != CHUNK_BYTES {
                continue;
            }
            for y in 0..RY {
                for z in 0..16usize {
                    let src = (z * 16 + y * 256) * 2;
                    let dst = ridx(cx * 16, y, cz * 16 + z);
                    for x in 0..16usize {
                        region[dst + x] = u16::from_le_bytes([data[src + x * 2], data[src + x * 2 + 1]]);
                    }
                }
            }
        }
    }
    region
}

/// Atlas rect for a block face; ids without an entry get the trailing "missing" tile.
fn tile(uvs: &[f32], id: u16, face: usize) -> &[f32] {
    let start = id as usize * 24 + face * 4;
    if start + 4 <= uvs.len() - 4 { &uvs[start..start + 4] } else { &uvs[uvs.len() - 4..] }
}

fn full_bright() -> (Vec<u8>, Vec<u8>) {
    (vec![MAX_LIGHT; REGION], vec![0; REGION])
}

/// Sky light falls straight down until blocked, then both sky and block light spread with a falloff
/// of one per block through non-opaque cells. Unloaded chunks are treated as open sky.
fn compute_light(region: &[u16], t: &Tables) -> (Vec<u8>, Vec<u8>) {
    let blocks_light = |b: u16| b != UNLOADED && t.opaque[b as usize] == 1;
    let mut sky = vec![0u8; REGION];
    let mut block = vec![0u8; REGION];
    for z in 0..RZ {
        for x in 0..RX {
            for y in (0..RY).rev() {
                let i = ridx(x, y, z);
                if blocks_light(region[i]) {
                    break;
                }
                sky[i] = MAX_LIGHT;
            }
        }
    }

    let mut queue: Vec<u32> = Vec::with_capacity(4096);
    // Seed only the sky cells that border a dark, open cell sideways.
    for y in 0..RY {
        for z in 0..RZ {
            for x in 0..RX {
                let i = ridx(x, y, z);
                if sky[i] != MAX_LIGHT {
                    continue;
                }
                let dark_open = |j: usize| sky[j] == 0 && !blocks_light(region[j]);
                if (x > 0 && dark_open(i - 1)) || (x + 1 < RX && dark_open(i + 1))
                    || (z > 0 && dark_open(i - RX)) || (z + 1 < RZ && dark_open(i + RX))
                {
                    queue.push(i as u32);
                }
            }
        }
    }
    spread(&mut sky, &mut queue, region, &blocks_light);

    for (i, &b) in region.iter().enumerate() {
        if b != UNLOADED && t.emission[b as usize] > 0 {
            block[i] = t.emission[b as usize].min(MAX_LIGHT);
            queue.push(i as u32);
        }
    }
    spread(&mut block, &mut queue, region, &blocks_light);
    (sky, block)
}

fn spread(light: &mut [u8], queue: &mut Vec<u32>, region: &[u16], blocks_light: &dyn Fn(u16) -> bool) {
    let mut head = 0;
    let layer = RX * RZ;
    while head < queue.len() {
        let i = queue[head] as usize;
        head += 1;
        let level = light[i];
        if level <= 1 {
            continue;
        }
        let (x, z, y) = (i % RX, (i / RX) % RZ, i / layer);
        let visit = |j: usize, light: &mut [u8], queue: &mut Vec<u32>| {
            if light[j] < level - 1 && !blocks_light(region[j]) {
                light[j] = level - 1;
                queue.push(j as u32);
            }
        };
        if x > 0 { visit(i - 1, light, queue); }
        if x + 1 < RX { visit(i + 1, light, queue); }
        if z > 0 { visit(i - RX, light, queue); }
        if z + 1 < RZ { visit(i + RX, light, queue); }
        if y > 0 { visit(i - layer, light, queue); }
        if y + 1 < RY { visit(i + layer, light, queue); }
    }
    queue.clear();
}

/// Visible faces of the center chunk, merged into the largest rectangles sharing tile and light.
fn mesh_center(region: &[u16], sky: &[u8], block_light: &[u8], t: &Tables) -> (Surface, Surface) {
    let mut solid = Surface::default();
    let mut translucent = Surface::default();

    let mut top = RY as i32 - 1;
    'find_top: while top >= 0 {
        for z in 0..16 {
            for x in 0..16 {
                if region[ridx(OFFSET + x, top as usize, OFFSET + z)] != 0 {
                    break 'find_top;
                }
            }
        }
        top -= 1;
    }
    if top < 0 {
        return (solid, translucent);
    }
    let height = top as usize + 1;
    let dims = [16usize, height, 16usize];

    for face in 0..6 {
        let (s_axis, u_axis, v_axis) = AXES[face];
        let (s_len, u_len, v_len) = (dims[s_axis], dims[u_axis], dims[v_axis]);
        let normal = NORMALS[face];
        let mut mask = vec![0u64; u_len * v_len];
        for s in 0..s_len {
            for v in 0..v_len {
                for u in 0..u_len {
                    let mut p = [0usize; 3];
                    p[s_axis] = s;
                    p[u_axis] = u;
                    p[v_axis] = v;
                    let i = ridx(OFFSET + p[0], p[1], OFFSET + p[2]);
                    let id = region[i];
                    let mode = t.render[id as usize];
                    mask[u + v * u_len] = 0;
                    if mode == 0 || mode == RENDER_MODEL || mode == RENDER_PLANT {
                        continue;
                    }
                    let ny = p[1] as i32 + normal[1];
                    let n_id = if ny >= RY as i32 {
                        0u16
                    } else if ny < 0 {
                        UNLOADED
                    } else {
                        region[ridx(
                            (OFFSET as i32 + p[0] as i32 + normal[0]) as usize,
                            ny as usize,
                            (OFFSET as i32 + p[2] as i32 + normal[2]) as usize,
                        )]
                    };
                    if t.opaque[n_id as usize] == 1 {
                        continue;
                    }
                    if mode != RENDER_OPAQUE && t.cull_same[id as usize] == 1 && n_id == id {
                        continue;
                    }
                    let is_liquid = t.liquid[id as usize] == 1;
                    let above = if p[1] + 1 < RY { region[ridx(OFFSET + p[0], p[1] + 1, OFFSET + p[2])] } else { 0 };
                    let lower = mode != RENDER_OPAQUE && is_liquid && above != id;
                    let tile = tile(t.uvs, id, face);
                    // Liquids stay flat-lit; everything else gets per-corner smooth light and occlusion.
                    let corners = corner_light(region, sky, block_light, t, p, face, !is_liquid && t.ambient_occlusion);
                    if lower && face != 2 {
                        // Lowered liquid sides don't tile vertically; emit them individually.
                        let target = if mode == RENDER_TRANSLUCENT { &mut translucent } else { &mut solid };
                        target.add_quad(quad_sized(face, p, [1, 1, 1], lower), face, tile, corners, face_flags(t, id));
                        continue;
                    }
                    let mut packed = 0u64;
                    for (k, c) in corners.iter().enumerate() {
                        packed |= ((c[0] as u64) | (c[1] as u64) << 4 | (c[2] as u64) << 8) << (k * 10);
                    }
                    let translucent_bit = u64::from(mode == RENDER_TRANSLUCENT);
                    mask[u + v * u_len] = 1 | (id as u64) << 1 | u64::from(lower) << 17 | translucent_bit << 18 | packed << 19;
                }
            }
            greedy(&mut mask, u_len, v_len, |u, v, w, h, key| {
                let mut p = [0usize; 3];
                p[s_axis] = s;
                p[u_axis] = u;
                p[v_axis] = v;
                let mut size = [1usize; 3];
                size[u_axis] = w;
                size[v_axis] = h;
                let id = ((key >> 1) & 0xffff) as u16;
                let lower = (key >> 17) & 1 == 1;
                let mut corners = [[0u8; 3]; 4];
                for (k, c) in corners.iter_mut().enumerate() {
                    let bits = key >> (19 + k * 10);
                    *c = [(bits & 0xf) as u8, ((bits >> 4) & 0xf) as u8, ((bits >> 8) & 0x3) as u8];
                }
                let target = if (key >> 18) & 1 == 1 { &mut translucent } else { &mut solid };
                target.add_quad(quad_sized(face, p, size, lower), face, tile(t.uvs, id, face), corners, face_flags(t, id));
            });
        }
    }
    for y in 0..height {
        for z in 0..16 {
            for x in 0..16 {
                let i = ridx(OFFSET + x, y, OFFSET + z);
                let id = region[i];
                if t.render[id as usize] == RENDER_PLANT {
                    solid.add_plant([x, y, z], tile(t.uvs, id, 0), sky[i], block_light[i], face_flags(t, id));
                }
            }
        }
    }
    (solid, translucent)
}

fn face_flags(t: &Tables, id: u16) -> f32 {
    let i = id as usize;
    (u32::from(t.sway[i] != 0) | u32::from(t.liquid[i] != 0) << 1 | u32::from(t.emission[i] != 0) << 2) as f32
}

/// Per corner of a face: [sky, block, ao]. Light is averaged over the open cells around the corner in
/// front of the face ("smooth lighting"); ao counts the solid cells there (0 = most occluded, 3 = open).
fn corner_light(region: &[u16], sky: &[u8], block_light: &[u8], t: &Tables, p: [usize; 3], face: usize, smooth: bool) -> [[u8; 3]; 4] {
    let normal = NORMALS[face];
    let (_, u_axis, v_axis) = AXES[face];
    let front = [OFFSET as i32 + p[0] as i32 + normal[0], p[1] as i32 + normal[1], OFFSET as i32 + p[2] as i32 + normal[2]];
    // (occludes, sky, block) for a region cell.
    let sample = |c: [i32; 3]| -> (bool, u8, u8) {
        if c[1] >= RY as i32 {
            return (false, MAX_LIGHT, 0);
        }
        if c[1] < 0 || c[0] < 0 || c[2] < 0 || c[0] >= RX as i32 || c[2] >= RZ as i32 {
            return (false, 0, 0);
        }
        let j = ridx(c[0] as usize, c[1] as usize, c[2] as usize);
        let b = region[j];
        (b != UNLOADED && t.opaque[b as usize] == 1, sky[j], block_light[j])
    };
    let (_, front_sky, front_block) = sample(front);
    if !smooth {
        return [[front_sky, front_block, 3]; 4];
    }
    let mut out = [[0u8; 3]; 4];
    for (k, corner) in CORNERS[face].iter().enumerate() {
        let mut du = [0i32; 3];
        let mut dv = [0i32; 3];
        du[u_axis] = if corner[u_axis] > 0.5 { 1 } else { -1 };
        dv[v_axis] = if corner[v_axis] > 0.5 { 1 } else { -1 };
        let add = |a: [i32; 3], b: [i32; 3]| [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
        let s1 = sample(add(front, du));
        let s2 = sample(add(front, dv));
        let sc = sample(add(add(front, du), dv));
        let ao = if s1.0 && s2.0 { 0 } else { 3 - u8::from(s1.0) - u8::from(s2.0) - u8::from(sc.0) };
        let (mut sky_sum, mut block_sum, mut count) = (front_sky as u32, front_block as u32, 1u32);
        for (occludes, s, b) in [s1, s2] {
            if !occludes {
                sky_sum += s as u32;
                block_sum += b as u32;
                count += 1;
            }
        }
        if !sc.0 && !(s1.0 && s2.0) {
            sky_sum += sc.1 as u32;
            block_sum += sc.2 as u32;
            count += 1;
        }
        out[k] = [((sky_sum + count / 2) / count) as u8, ((block_sum + count / 2) / count) as u8, ao];
    }
    out
}

fn greedy(mask: &mut [u64], u_len: usize, v_len: usize, mut emit: impl FnMut(usize, usize, usize, usize, u64)) {
    for v in 0..v_len {
        let mut u = 0;
        while u < u_len {
            let key = mask[u + v * u_len];
            if key == 0 {
                u += 1;
                continue;
            }
            let mut w = 1;
            while u + w < u_len && mask[u + w + v * u_len] == key {
                w += 1;
            }
            let mut h = 1;
            'grow: while v + h < v_len {
                for du in 0..w {
                    if mask[u + du + (v + h) * u_len] != key {
                        break 'grow;
                    }
                }
                h += 1;
            }
            for dv in 0..h {
                for du in 0..w {
                    mask[u + du + (v + dv) * u_len] = 0;
                }
            }
            emit(u, v, w, h, key);
            u += w;
        }
    }
}

fn model_instances(region: &[u16], sky: &[u8], block_light: &[u8], t: &Tables) -> Vec<i32> {
    let mut out = Vec::new();
    for y in 0..RY {
        for z in 0..16 {
            for x in 0..16 {
                let i = ridx(OFFSET + x, y, OFFSET + z);
                let id = region[i];
                if t.render[id as usize] == RENDER_MODEL {
                    out.extend_from_slice(&[id as i32, x as i32, y as i32, z as i32, sky[i] as i32, block_light[i] as i32]);
                }
            }
        }
    }
    out
}

/// Corners of a face covering `size` blocks starting at block `p` (chunk-local).
fn quad_sized(face: usize, p: [usize; 3], size: [usize; 3], lower: bool) -> [Vector3; 4] {
    let mut out = [Vector3::ZERO; 4];
    for (k, c) in CORNERS[face].iter().enumerate() {
        let mut v = [0f32; 3];
        for a in 0..3 {
            v[a] = p[a] as f32 + c[a] * size[a] as f32;
        }
        if lower && c[1] > 0.5 {
            v[1] = p[1] as f32 + (size[1] as f32 - 1.0) + LIQUID_TOP;
        }
        out[k] = Vector3::new(v[0], v[1], v[2]);
    }
    out
}
