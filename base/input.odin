package base

import rl "vendor:raylib"
import "core:log"

process_input :: proc(speed : f32) -> (direction: V3, mouse_delta: V2)
{
    forward : bool = rl.IsKeyDown(rl.KeyboardKey.W)
    backward : bool = rl.IsKeyDown(rl.KeyboardKey.S)
    left : bool = rl.IsKeyDown(rl.KeyboardKey.A)
    right : bool = rl.IsKeyDown(rl.KeyboardKey.D)

    
    if forward {direction.z += 1}
    if backward {direction.z -= 1}
    if left {direction.x -= 1}
    if right {direction.x += 1}
    
    direction.x *= speed
    direction.y *= speed
    direction.z *= speed
    
    mouse_delta = rl.GetMouseDelta()
    mouse_delta.y = -mouse_delta.y
    mouse_delta.x = -mouse_delta.x
    
    if !rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT)
    {
        mouse_delta.x = 0
        mouse_delta.y = 0
    }

    return direction, mouse_delta
}