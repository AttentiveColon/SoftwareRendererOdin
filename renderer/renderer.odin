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
            renderer,
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

draw_triangle_tile :: proc(renderer : ^Renderer, tri : base.RasterTriangle, tile_x_min, tile_x_max, tile_y_min, tile_y_max : i32)
{
    tex := renderer.textures[tri.texture_index]
    area := tri.area
    render_width : int = int(renderer.render_width)
    render_height : int = int(renderer.render_height)

    // triangle bounds
    x_min := math.min(math.min(tri.s0.x, tri.s1.x), tri.s2.x)
    x_max := math.max(math.max(tri.s0.x, tri.s1.x), tri.s2.x)
    y_min := math.min(math.min(tri.s0.y, tri.s1.y), tri.s2.y)
    y_max := math.max(math.max(tri.s0.y, tri.s1.y), tri.s2.y)

    // clamp bounds to avoid index out of bounds crash
    x_min = math.max(0, x_min)
    x_max = math.min(int(render_width) - 1, x_max)
    y_min = math.max(0, y_min)
    y_max = math.min(int(render_height) - 1, y_max)
    x_min = math.max(int(tile_x_min), x_min)
    x_max = math.min(int(tile_x_max), x_max)
    y_min = math.max(int(tile_y_min), y_min)
    y_max = math.min(int(tile_y_max), y_max)

    // barycentric coordinates stepwise value
    alpha_step_x := f32(tri.s1.y - tri.s2.y) / area
    alpha_step_y:=  f32(tri.s2.x - tri.s1.x) / area
    beta_step_x :=  f32(tri.s2.y - tri.s0.y) / area
    beta_step_y :=  f32(tri.s0.x - tri.s2.x) / area
    gamma_step_x := f32(tri.s0.y - tri.s1.y) / area
    gamma_step_y := f32(tri.s1.x - tri.s0.x) / area

    // get starting coordinate at top left of bounding box
    start_p := base.ScreenCoord{x_min, y_min}
    start_alpha := total_area(start_p, tri.s1, tri.s2)    
    start_beta := total_area(start_p, tri.s2, tri.s0)
    start_gamma := total_area(start_p, tri.s0, tri.s1)

    row_alpha, row_beta, row_gamma : f32 = start_alpha, start_beta, start_gamma

    z0, z1, z2 : f32 = tri.f0.z, tri.f1.z, tri.f2.z
    c0, c1, c2 : base.Color = tri.f0.c, tri.f1.c, tri.f2.c
    u0, u1, u2 : f32 = tri.f0.uv.x, tri.f1.uv.x, tri.f2.uv.x
    v0, v1, v2 : f32 = tri.f0.uv.y, tri.f1.uv.y, tri.f2.uv.y

    epsilon : f32 = -0.0001
    for y := y_min; y <= y_max; y+=1
    {
        alpha, beta, gamma : f32 = row_alpha, row_beta, row_gamma
        row_offset : int = y * render_width
        for x := x_min; x <= x_max; x+=1
        {
            if alpha >= epsilon && beta >= epsilon && gamma >= epsilon
            {
                pixel_depth : f32 = (z0 * alpha) + (z1 * beta) + (z2 * gamma)
                buffer_index : int = row_offset + x

                if pixel_depth < renderer.depthbuffer[buffer_index]
                {
                    renderer.depthbuffer[buffer_index] = pixel_depth
                    light_color : base.Color = (c0 * alpha) + (c1 * beta) + (c2 * gamma)

                    // interpolate uvs and sample
                    uvx : f32 = (u0 * alpha) + (u1 * beta) + (u0 * gamma)
                    uvy : f32 = (v0 * alpha) + (v1 * beta) + (v2 * gamma)
                    sample : base.Color = base.sample_texture(tex, uvx, uvy)

                    // combine and write to buffer
                    final_color : base.Color = sample * light_color
                    renderer.framebuffer[buffer_index] = base.to_uint32_color(final_color)
                }
            }
            // step one pixel to the right
            alpha += alpha_step_x
            beta += beta_step_x
            gamma += gamma_step_x
        }
        // step one pixel row down
        row_alpha += alpha_step_y
        row_beta += beta_step_y
        row_gamma += gamma_step_y
    }
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