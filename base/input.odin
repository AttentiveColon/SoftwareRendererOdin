package base

import sdl2 "vendor:sdl2"

process_input :: proc(speed : f32) -> (direction: V3, mouse_delta: V2)
{
    keys := sdl2.GetKeyboardState(nil)

    forward : bool = keys[sdl2.SCANCODE_W] != 0
    backward : bool = keys[sdl2.SCANCODE_S] != 0
    left : bool = keys[sdl2.SCANCODE_A] != 0
    right : bool = keys[sdl2.SCANCODE_D] != 0

    if forward {direction.z += 1}
    if backward {direction.z -= 1}
    if left {direction.x -= 1}
    if right {direction.x += 1}
    
    direction.x *= speed
    direction.y *= speed
    direction.z *= speed
    
    dx, dy : i32
    sdl2.GetRelativeMouseState(&dx, &dy)
    
    mouse_delta.x = -f32(dx)
    mouse_delta.y = -f32(dy)
    
    if keys[sdl2.SCANCODE_LSHIFT] == 0
    {
        mouse_delta.x = 0
        mouse_delta.y = 0
    }

    return direction, mouse_delta
}