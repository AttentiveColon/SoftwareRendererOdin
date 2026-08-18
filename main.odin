package main

import "display"
import "renderer"
import "base"
import "asset"
import "core:math/linalg"
import "core:log"
import "core:prof/spall"
import "core:sync"
import "core:math"


Display :: display.Display
Renderer :: renderer.Renderer

testing : bool : true

spall_ctx : spall.Context
@(thread_local) spall_buffer : spall.Buffer

Program :: struct
{
    render_scale, window_scale, 
    render_width, render_height, 
    window_width, window_height, 
    frame_target : i32,
    title : cstring,
}

create_program :: proc() -> Program
{
    render_scale : i32 = 1
    window_scale : i32 = 3
    return {
        render_scale,           // render scale
        window_scale,           // window scale
        320 * render_scale,     // render width                 
        220 * render_scale,     // render height                
        320 * window_scale,     // window width
        240 * window_scale,     // window height
        30,                      // frame target (0 for uncapped)
        "Odin Software Renderer"// window title
    }
}

// TEST: vertex stage
wobbly :: proc(v : base.Vertex, time : f32) -> base.Vertex
{
    vertex := v
    vertex.x += math.sin(time * 0.0005 * vertex.y) * 0.250
    return vertex
}

// TEST: fragment stage
skybox :: proc(in_frag : base.FragmentIn, tick : f32) -> base.FragmentOut
{
    sample := base.sample_texture(in_frag.tex, in_frag.uv.x, in_frag.uv.y)
    red_tint : base.Color = {math.clamp(math.sin(tick * 0.001) * 1.0, 0.5, 1.0), math.clamp(math.cos(tick * 0.005) * 0.5, 0.5, 1.0), 0.5, 1.0}
    depth : f32 = 1.0
    return {sample * red_tint, depth, false}
}

run :: proc(program : Program)
{
    d : Display = display.create(
        program.window_width, 
        program.window_height, 
        program.render_width, 
        program.render_height, 
        program.frame_target,
        program.title,
        true,
    )
    defer display.close(d)

    asset_manager : asset.Manager = asset.create()
    defer asset.close(&asset_manager)

    //model := asset.load2(&asset_manager, "assets/Sponza/gltf/Sponza.gltf")
    //model := asset.load2(&asset_manager, "assets/Untitled.glb", ccw_winding=false)
    //model := asset.load2(&asset_manager, "assets/ABeautifulGame.glb", ccw_winding=false)
    model := asset.load2(&asset_manager, "assets/leon.glb")
    model2 := asset.load2(&asset_manager, "assets/test_skybox.glb")
    //model := asset.load2(&asset_manager, "assets/VirtualCity.glb")
       
    r : Renderer = renderer.create(program.render_width, program.render_height, &spall_ctx, &spall_buffer)
    defer renderer.close(&r)

    camera := base.create_camera(
        {20,-20,20}, {0,0,0}, 3.14*0.3335, 
        f32(program.render_width)/f32(program.render_height),
        1.0, 600.0
    )

    trs_matrix : matrix[4,4]f32 = linalg.matrix4_scale_f32({1.5, 1.5, 1.5})
    mvp_matrix : matrix[4,4]f32 = camera.proj_matrix * camera.view_matrix * trs_matrix
    renderer.update_light_position(&r, {100, -15, 0})
    model_matricies := make([dynamic]matrix[4,4]f32)

    //frame : f32 = 0.0
    for 
    {   
        free_all(context.temp_allocator)
        clear(&model_matricies)
        renderer.clear_buffer(&r, {1.0, 0.0, 1.0, 1.0})
        renderer.begin_draw(&r)

        direction, delta := base.process_input(5.5)
        base.move_camera(&camera, direction, delta)

        view_proj := base.get_view_projection(&camera)


        translation := base.translate({0, 0, 0}, trs_matrix)
        for i in 0..<150
        {
            for j in 0..<5
            {
                translation = base.translate({f32(j * 150), 0, -f32(i * 150)}, trs_matrix)
                renderer.draw_model(&r, model, translation, view_proj)

            }

        }
        translation = base.translate(camera.position, trs_matrix)
        // renderer.set_fragment_pipeline(&r, skybox)
        // renderer.set_vertex_pipeline(&r, wobbly)
        // renderer.draw_model(&r, model2, translation, view_proj)
        // renderer.reset_fragment_pipeline(&r)
        // renderer.reset_vertex_pipeline(&r)

        

        renderer.end_draw(&r)
        post_process_framebuffer := renderer.apply_fog(renderer.get_framebuffer(&r), renderer.get_depthbuffer(&r), base.Color{0.3, 0.3, 0.3, 1.0})
        if display.present(d, post_process_framebuffer) {break}
        //if display.present(d, renderer.get_depthbuffer_as_framebuffer(&r)) {break}
    }
}

main :: proc()
{
    spall_ctx = spall.context_create("renderer_trace.spall")
    defer spall.context_destroy(&spall_ctx)
    buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
    defer delete(buffer_backing)
    spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
    defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

    program : Program = create_program()
    run(program)
}