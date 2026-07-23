package renderer

import "../base"
import "core:slice"
import "core:math"
import "core:thread"
import "core:os"

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

    raster_verticies : [dynamic]base.RasterVertex,
    clip_buffer : [15]base.RasterVertex,
    polygon_buffer : [4]base.RasterVertex,

    global_light_position : base.V3,

    thread_pool : ^thread.Pool,
}

Render_Thread :: struct
{
    renderer : ^Renderer,
    index : i32,
}

render_task :: proc(task : thread.Task)
{
    // cast task.data to thread data type
    data := cast(^Render_Thread)task.data
    renderer := data.renderer
    index := data.index

    tile_x_min := (index % renderer.tile_x) * renderer.tile_size
    tile_x_max := tile_x_min + renderer.tile_size - 1
    tile_y_min := (index / renderer.tile_x) * renderer.tile_size
    tile_y_max := tile_y_min + renderer.tile_size - 1

    for j := 0; j < len(renderer.tile_bins[index]); j += 1
    {
        draw_triangle_tile(
            renderer.tile_bins[index][j], 
            tile_x_min, tile_x_max, 
            tile_y_min, tile_y_max
        )
    }
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
    raster_verticies : [dynamic]base.RasterVertex
    clip_buffer : [15]base.RasterVertex
    polygon_buffer : [4]base.RasterVertex

    global_light_position : base.V3 = {15,15,15}

    thread_pool := new(thread.Pool)
    thread.pool_init(thread_pool, context.allocator, os.get_processor_core_count())
    thread.pool_start(thread_pool)
    
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
        thread_pool,
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
    task_data := make([]Render_Thread, len(renderer.tile_bins), context.temp_allocator)
    for _, index in renderer.tile_bins
    {
        task_data[index] = Render_Thread{renderer, i32(index)}
        thread.pool_add_task(renderer.thread_pool, context.allocator, render_task, rawptr(&task_data[index]))
    }
    thread.pool_finish(renderer.thread_pool)
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
    delete(renderer.depthbuffer)
    delete(renderer.raster_verticies)
    delete(renderer.textures)
    for bin in renderer.tile_bins
    {
        delete(bin)
    }
    delete(renderer.tile_bins)
    thread.pool_finish(renderer.thread_pool)
    thread.pool_destroy(renderer.thread_pool)
    free(renderer.thread_pool)
}