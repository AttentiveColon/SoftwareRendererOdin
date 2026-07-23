package renderer

import "../base"
import "core:slice"
import "core:math"

Renderer :: struct
{
    render_width, render_height : i32,
    framebuffer : []u32,
    depthbuffer : []f32,

    tile_size : i32,
    tile_x : i32,
    tile_y : i32,

    tile_bins : [][dynamic]base.RasterTriangle,
    textures : [dynamic]base.Texture,

    raster_verticies : [20000]base.RasterVertex,
    clip_buffer : [15]base.RasterVertex,
    polygon_buffer : [4]base.RasterVertex,

    global_light_position : base.V3,
}

create :: proc(render_width, render_height : i32) -> Renderer
{
    framebuffer := make([]u32, render_width * render_height)
    depthbuffer := make([]f32, render_width * render_height)

    tile_size : i32 = 32
    tile_x : i32 = render_width / tile_size
    tile_y : i32 = render_height / tile_size
    tile_bins := make([][dynamic]base.RasterTriangle, tile_x * tile_y)
    textures : [dynamic]base.Texture
    raster_verticies : [20000]base.RasterVertex
    clip_buffer : [15]base.RasterVertex
    polygon_buffer : [4]base.RasterVertex

    global_light_position : base.V3 = {15,15,15}

    return {
        render_width, 
        render_height, 
        framebuffer, 
        depthbuffer,
        tile_size,
        tile_x,
        tile_y,
        tile_bins,
        textures,
        raster_verticies,
        clip_buffer,
        polygon_buffer,
        global_light_position,
    }
}

total_area :: proc(a, b, c : base.ScreenCoord) -> f32
{
    return f32((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
}

draw_triangle_tile :: proc(tri : base.RasterTriangle, tile_x_min, tile_x_max, tile_y_min, tile_y_max : i32)
{

}

get_point_from_position :: proc(renderer: Renderer, x, y, z : f32, c : base.Color, normal : base.V3, uv : base.V2) -> base.Point
{
    pixel_x : int = int((x + 1.0) * 0.5 * f32(renderer.render_width))
    pixel_y : int = int((y + 1.0) * 0.5 * f32(renderer.render_height))
    return base.Point{pixel_x, pixel_y, z, c, uv, normal}
}

lerp_vertex :: proc(v_in, v_out : base.RasterVertex, d_in, d_out : f32) -> base.RasterVertex
{
    t : f32 = d_in / (d_in - d_out)
    position := math.lerp(v_in.position, v_out.position, t)
    uv := math.lerp(v_in.uv, v_out.uv, t)
    light_color := math.lerp(v_in.light_color, v_out.light_color, t)

    // TODO: check if there needs to be a lerp of the normal here as well
    return {
        position, light_color, {}, uv
    }
}

cull_slice_triangle :: proc(rv0, rv1, rv2 : base.RasterVertex, clip_buffer : ^[dynamic]base.RasterVertex)
{

}

draw_mesh :: proc(mesh : base.Mesh, mvp, model_matrix : matrix[4,4]f32)
{

}

begin_draw :: proc(renderer : ^Renderer)
{
    for &tile in renderer.tile_bins
    {
        clear(&tile)
    }
    clear_depth_buffer(renderer)
}

end_draw :: proc(renderer : ^Renderer)
{

}

update_light_position :: proc(renderer : ^Renderer, position : base.V3)
{
    renderer.global_light_position = position
}

clear_buffer :: proc(renderer : ^Renderer, color : base.Color)
{
    slice.fill(renderer.framebuffer, base.to_uint32_color(color))
}

clear_depth_buffer :: proc(renderer : ^Renderer)
{
    slice.fill(renderer.depthbuffer, 1.0)
}

get_framebuffer :: proc(renderer : Renderer) -> []u32
{
    return renderer.framebuffer
}

close :: proc(renderer : Renderer)
{
    delete(renderer.framebuffer)
}