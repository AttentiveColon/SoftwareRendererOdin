package base

import rl "vendor:raylib"
import "core:log"
import "core:math"
import "core:strings"

Texture :: struct
{
    name : string,
    width, height : i32,
    pixels : []V4
}

load_texture :: proc(filepath : string) -> Texture
{
    filepath_cstring := strings.clone_to_cstring(filepath, context.temp_allocator)
    image := rl.LoadImage(filepath_cstring)
    defer rl.UnloadImage(image)
    if image.data != nil
    {
        rl.ImageFormat(&image, rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
    }
    else { log.panic("Failed to load image data!") }
    total_pixels := image.width * image.height
    img_ptr := cast([^][4]f32) image.data
    raylib_slice := img_ptr[:total_pixels]
    odin_slice := make([][4]f32, total_pixels)
    copy(odin_slice,  raylib_slice)
    return {strings.clone(filepath), image.width, image.height, odin_slice}
}

unload_texture :: proc(texture : ^Texture)
{
    delete(texture.pixels)
    delete(texture.name)
}

sample_texture :: proc(texture : Texture, u, v : f32, clamp_edges : bool = false) -> Color
{
    u := u
    v := v
    if clamp_edges
    {
        u = clamp(u, 0.0, 1.0)
        v = clamp(v, 0.0, 1.0)
    } else
    {
        u = u - math.floor(u)
        v = v - math.floor(v)
    }

    tex_x := i32(u * f32(texture.width - 1))
    tex_y := i32(v * f32(texture.height - 1))

    index : i32 = tex_y * texture.width + tex_x

    return texture.pixels[index]
}