package renderer

import "../base"
import "core:slice"
import "core:math"
import "core:thread"
import "core:os"
import "core:math/linalg"
import "core:fmt"

backface_culling : bool : true

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
    clip_buffer : [dynamic ; 15]base.RasterVertex,
    polygon_buffer : [dynamic ; 4]base.RasterVertex,

    global_light_position : base.V3,

    thread_pool : ^thread.Pool,
}

Render_Thread :: struct
{
    renderer : ^Renderer,
    index : i32,
}

get_or_add_texture :: proc(textures : ^[dynamic]base.Texture, new_texture : base.Texture) -> int
{
    for tex, i in textures
    {
        if tex.name == new_texture.name
        {
            return i
        }
    }
    //fmt.println("AHHHH")
    //fmt.println(new_texture.pixels)
    index := len(textures)
    append(textures, new_texture)
    return index
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
    clip_buffer : [dynamic ; 15]base.RasterVertex
    polygon_buffer : [dynamic ; 4]base.RasterVertex

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
    //fmt.println(renderer.textures[tri.texture_index])
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
    start_alpha := total_area(start_p, tri.s1, tri.s2) / area    
    start_beta := total_area(start_p, tri.s2, tri.s0) / area
    start_gamma := total_area(start_p, tri.s0, tri.s1) / area

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
                    uvx : f32 = (u0 * alpha) + (u1 * beta) + (u2 * gamma)
                    uvy : f32 = (v0 * alpha) + (v1 * beta) + (v2 * gamma)
                    //fmt.println(tex.name, tex.height)
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

cull_slice_triangle :: proc(renderer : ^Renderer, rv0, rv1, rv2 : base.RasterVertex)
{
    clear(&renderer.clip_buffer)
    clear(&renderer.polygon_buffer)

    clip_edge :: proc(renderer : ^Renderer, current, next : base.RasterVertex)
    {
        current_dist := current.position.z
        next_dist := next.position.z

        current_inside : bool = current_dist >= 0.0
        next_inside : bool = next_dist >= 0.0

        if current_inside && next_inside
        {
            append(&renderer.polygon_buffer, next)
        }
        else if current_inside && !next_inside
        {
            append(&renderer.polygon_buffer, lerp_vertex(current, next, current_dist, next_dist))
        }
        else if !current_inside && next_inside
        {
            append(&renderer.polygon_buffer, lerp_vertex(current, next, current_dist, next_dist))
            append(&renderer.polygon_buffer, next)
        }
    }

    clip_edge(renderer, rv0, rv1)
    clip_edge(renderer, rv1, rv2)
    clip_edge(renderer, rv2, rv0)

    // triangulate output
    if len(renderer.polygon_buffer) == 3
    {
        append(&renderer.clip_buffer, renderer.polygon_buffer[0])
        append(&renderer.clip_buffer, renderer.polygon_buffer[1])
        append(&renderer.clip_buffer, renderer.polygon_buffer[2])
    }
    else if len(renderer.polygon_buffer) == 4
    {
        append(&renderer.clip_buffer, renderer.polygon_buffer[0])
        append(&renderer.clip_buffer, renderer.polygon_buffer[1])
        append(&renderer.clip_buffer, renderer.polygon_buffer[2])

        append(&renderer.clip_buffer, renderer.polygon_buffer[0])
        append(&renderer.clip_buffer, renderer.polygon_buffer[2])
        append(&renderer.clip_buffer, renderer.polygon_buffer[3])
    }
}

draw_mesh :: proc(renderer : ^Renderer, mesh : base.Mesh, mvp, model_matrix : matrix[4,4]f32)
{
    current_face_index : int = 0
    half_width, half_height : f32 = f32(renderer.render_width / 2), f32(renderer.render_height / 2)

    // preallocate if mesh array is larger than current raster vertex dynamic array
    if len(mesh.vertices) > len(renderer.raster_verticies)
    {
        reserve(&renderer.raster_verticies, len(mesh.vertices))
        resize(&renderer.raster_verticies, len(mesh.vertices))
    }

    calculate_light :: proc(renderer : ^Renderer, v : base.Vertex, model_matrix : matrix[4,4]f32) -> base.Color
    {
        obj_normal : base.V3 = {v.nx, v.ny, v.nz}
        v4_normal : base.V4 = {obj_normal.x, obj_normal.y, obj_normal.z, 0.0}
        world_normal : base.V4 = linalg.normalize(linalg.mul(model_matrix, v4_normal))
        world_position : base.V3 = (model_matrix * base.V4{v.x, v.y, v.z, 1.0}).xyz
        light_direction : base.V3 = renderer.global_light_position - world_position

        diffuse : f32 = math.max(linalg.dot(light_direction, world_normal.xyz), 0.0)
        ambient : f32 = 0.2
        total_light : f32 = math.min(diffuse + ambient, 1.0)

        return base.Color{total_light, total_light, total_light, 1.0}
    }

    // precalculate vertices to avoid recalculating shared verticies
    for vertex, idx in mesh.vertices
    {
        raster_vertex : base.RasterVertex = {
            position = mvp * base.V4{vertex.x, vertex.y, vertex.z, 1.0},
            light_color = calculate_light(renderer, vertex, model_matrix),
            normal = {vertex.nx, vertex.ny, vertex.nz},
            uv = {vertex.u, vertex.v},
        }
        renderer.raster_verticies[idx] = raster_vertex // this might break
        
        // if the above breaks, clear array and then call this append below 
        //append(&renderer.raster_verticies, raster_vertex)
    }

    for group in mesh.face_groups
    {
        // check for texture and add it if it doesn't exist yet
        mat, ok := mesh.materials[group.material_name]
        if !ok
        {
            fmt.panicf("No material, everyone panic")
        }
        group_texture : base.Texture = mesh.materials[group.material_name].texture
        texture_index := get_or_add_texture(&renderer.textures, group_texture)

        // collect and distribute triangles to associated tile bins
        for ; current_face_index <= group.last_face_index; current_face_index+=1
        {
            face : base.Face = mesh.faces[current_face_index]

            rv0 : base.RasterVertex = renderer.raster_verticies[face.f0]
            rv1 : base.RasterVertex = renderer.raster_verticies[face.f1]
            rv2 : base.RasterVertex = renderer.raster_verticies[face.f2]        
                
            cull_slice_triangle(renderer, rv0, rv1, rv2)

            for i := 0; i < len(renderer.clip_buffer); i+=3
            {
                out0 : base.RasterVertex = renderer.clip_buffer[i]
                out1 : base.RasterVertex = renderer.clip_buffer[i + 1]
                out2 : base.RasterVertex = renderer.clip_buffer[i + 2]

                // perspective division
                out0.position /= out0.position.w
                out1.position /= out1.position.w
                out2.position /= out2.position.w

                // create 2d geometry coordinates
                s0 : base.ScreenCoord = {int((out0.position.x + 1) * half_width), int((out0.position.y + 1) * half_height)}
                s1 : base.ScreenCoord = {int((out1.position.x + 1) * half_width), int((out1.position.y + 1) * half_height)}
                s2 : base.ScreenCoord = {int((out2.position.x + 1) * half_width), int((out2.position.y + 1) * half_height)}

                // calculate area and skip backfacing triangles
                area : f32 = total_area(s0, s1, s2)
                if backface_culling && area > 0 {continue}

                f0 : base.FragCoord = {out0.position.z, out0.light_color, out0.uv, out0.normal}
                f1 : base.FragCoord = {out1.position.z, out1.light_color, out1.uv, out1.normal}
                f2 : base.FragCoord = {out2.position.z, out2.light_color, out2.uv, out2.normal}

                // create final triangle for binning
                tri : base.RasterTriangle = {s0, s1, s2, f0, f1, f2, texture_index, area}

                // get triangle bounds and clamp to screen width and height
                x_min := math.max(math.min(math.min(s0.x, s1.x), s2.x), 0)
                x_max := math.min(math.max(math.max(s0.x, s1.x), s2.x), int(renderer.render_width - 1))
                y_min := math.max(math.min(math.min(s0.y, s1.y), s2.y), 0)
                y_max := math.min(math.max(math.max(s0.y, s1.y), s2.y), int(renderer.render_height - 1))

                // find which bins each triangle crosses (shift by X where 2^X == tile_size)
                // default tile size is 32, so x is 5 or 2^5 which == 32
                start_x := x_min >> 5
                start_y := y_min >> 5
                end_x := x_max >> 5
                end_y := y_max >> 5
                
                // iterate all possible bins of each triangle and place triangles
                for y := start_y; y <= end_y; y += 1
                {
                    for x := start_x; x <= end_x; x += 1
                    {
                        append(&renderer.tile_bins[y * int(renderer.tile_x) + x], tri)
                    }
                }
            }
        }
    }
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

get_framebuffer :: proc(renderer : ^Renderer) -> []u32
{
    return renderer.framebuffer
}

close :: proc(renderer : ^Renderer)
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