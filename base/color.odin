package base

import "core:math"

blend_color :: proc(color : Color, scalar : f32) -> Color
{
    return color * scalar
}

to_uint32_color :: proc(color : Color) -> u32
{
    scaled : [4]f32 = {
        math.clamp(color.x, 0, 1) * 255.0, 
        math.clamp(color.y, 0, 1) * 255.0, 
        math.clamp(color.z, 0, 1) * 255.0, 
        math.clamp(color.w, 0, 1) * 255.0
    }

    return u32(scaled.x) | u32(scaled.y) << 8 | u32(scaled.z) << 16 | u32(scaled.w) << 24
}

to_color_from_uint32 :: proc(value : u32) -> Color
{
    return {
        f32(value & 0xFF) / 255.0,
        f32((value >> 8) & 0xFF) / 255.0,
        f32((value >> 16) & 0xFF) / 255.0,
        f32((value >> 24) & 0xFF) / 255.0,
    }
}
