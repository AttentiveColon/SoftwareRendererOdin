package base

import la "core:math/linalg"
import "core:math"

Camera :: struct
{
    view_matrix, proj_matrix : M4,
    position, look_at, up : V3,
    fov, aspect, near, far : f32,
    yaw, pitch : f32,
}

Frustum :: [6][4]f32

create_camera :: proc(position, look_at : V3, fov, aspect, near, far : f32) -> Camera
{
    up := V3{0, 1, 0}
    view_matrix := la.matrix4_look_at(position, look_at, up)
    proj_matrix := la.matrix4_perspective(fov, aspect, near, far)

    forward := la.normalize(look_at - position)
    pitch := math.asin(forward.y)
    yaw := math.atan2(forward.z, forward.x)

    return {view_matrix, proj_matrix, position, look_at, up, fov, aspect, near, far, yaw, pitch}
}

move_camera :: proc(camera : ^Camera, move_delta : V3, mouse_delta : V2)
{
    mouse_sensitivity : f32 = 0.005

    camera.yaw += -mouse_delta.x * mouse_sensitivity
    camera.pitch += -mouse_delta.y * mouse_sensitivity
    camera.pitch = clamp(camera.pitch, -1.5, 1.5)

    forward : V3
    forward.x = math.cos(camera.yaw) * math.cos(camera.pitch)
    forward.y = math.sin(camera.pitch)
    forward.z = math.sin(camera.yaw) * math.cos(camera.pitch)
    forward = la.normalize(forward)

    right := la.normalize(la.cross(forward, camera.up))

    camera.position += right * move_delta.x
    camera.position += camera.up * move_delta.y 
    camera.position += forward * move_delta.z

    camera.look_at = camera.position + forward
    camera.view_matrix = la.matrix4_look_at(camera.position, camera.look_at, camera.up)

}

get_view_projection :: proc(camera : ^Camera) -> matrix[4,4]f32
{
    return camera.proj_matrix * camera.view_matrix
}

extract_frustum :: proc(view_proj : matrix[4,4]f32) -> (f: Frustum)
{
    r0 := [4]f32{view_proj[0, 0], view_proj[0, 1], view_proj[0, 2], view_proj[0, 3]}
    r1 := [4]f32{view_proj[1, 0], view_proj[1, 1], view_proj[1, 2], view_proj[1, 3]}
    r2 := [4]f32{view_proj[2, 0], view_proj[2, 1], view_proj[2, 2], view_proj[2, 3]}
    r3 := [4]f32{view_proj[3, 0], view_proj[3, 1], view_proj[3, 2], view_proj[3, 3]}

    raw := [6][4]f32{
        r3 + r0, // left
        r3 - r0, // right
        r3 + r1, // bottom
        r3 - r1, // top
        r2,     // near
        r3 - r2, // far
    }

    for p, i in raw
    {
        f[i] = p / la.length(p.xyz)
    }
    
    return f
}

is_in_frustum :: proc(f: ^Frustum, model : matrix[4,4]f32, center : [3]f32, radius : f32) -> bool
{
    world_pos := (model * [4]f32{center.x, center.y, center.z, 1.0}).xyz
	max_scale := math.sqrt(math.max(
		la.length2(model[0].xyz),
		math.max(la.length2(model[1].xyz), la.length2(model[2].xyz)),
	))
	r := radius * max_scale

	for p in f {
		if la.dot(p.xyz, world_pos) + p.w < -r {
			return false
		}
	}
	return true
}