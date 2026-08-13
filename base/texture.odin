package base

import stbi "vendor:stb/image"
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

    width, height, channels : i32
    // force 4 channel RGBA
    img_data := stbi.loadf(filepath_cstring, &width, &height, &channels, 4)

    if img_data == nil
    {
        log.panic("failed to load image data!")
    }
    defer stbi.image_free(img_data)

    total_pixels := width * height
    img_ptr := cast([^]V4)img_data
    stbi_slice := img_ptr[:total_pixels]

    odin_slice := make([]V4, total_pixels)
    copy(odin_slice, stbi_slice)

    return {strings.clone(filepath), width, height, odin_slice}
}

unload_texture :: proc(texture : ^Texture)
{
    delete(texture.pixels)
    delete(texture.name)
}

sample_texture :: proc(texture : ^Texture, u, v : f32, clamp_edges : bool = false) -> Color
{
    if len(texture.pixels) == 0 {
        // if empty return fallback color
        return {1.0, 0.0, 0.0, 1.0}
    }
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