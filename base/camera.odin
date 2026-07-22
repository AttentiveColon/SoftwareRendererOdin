package base

import la "core:math/linalg"

Camera :: struct
{
    view_matrix, proj_matrix : M4,
    position, look_at, up : V3,
    fov, aspect, near, far : f32,
}

create_camera :: proc(position, look_at : V3, fov, aspect, near, far : f32) -> Camera
{
    up := V3{0, 1, 0}
    look_at := la.normalize(look_at - position)
    view_matrix := la.matrix4_look_at(position, la.normalize(look_at - position), up)
    proj_matrix := la.matrix4_perspective(fov, aspect, near, far)
    return {view_matrix, proj_matrix, position, look_at, up, fov, aspect, near, far}
}

move_camera :: proc(camera : ^Camera, move_delta : V3, mouse_delta : V2)
{
    pointing_vector : V3 = la.normalize(camera.look_at - camera.position)
    right_vector : V3 = la.normalize(la.cross(camera.up, pointing_vector))
    up_vector : V3 = la.normalize((camera.position + camera.up) - camera.position)

    camera.position += right_vector * move_delta.x
    camera.position += up_vector * move_delta.y
    camera.position += pointing_vector * move_delta.z

    camera.look_at += right_vector * move_delta.x
    camera.look_at += up_vector * move_delta.y
    camera.look_at += pointing_vector * move_delta.z

    yaw_pitch_matrix : M4 = la.matrix4_from_yaw_pitch_roll(-mouse_delta.x, -mouse_delta.y, 0)
    forward : V3 = camera.look_at - camera.position
    forward_v4 : V4 = {forward.x, forward.y, forward.z, 1.0}
    forward_v3 : V3 = (yaw_pitch_matrix * forward_v4).xyz  
    camera.look_at = camera.position + forward_v3
    camera.view_matrix = la.matrix4_look_at(camera.position, camera.look_at, camera.up)
}