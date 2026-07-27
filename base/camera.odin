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