package main

import "display"
import "renderer"
import "base"
import "core:math/linalg"
import "core:log"
import "core:prof/spall"
import "core:sync"



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
        0,                     // frame target (0 for uncapped)
        "title"                 // window title
    }
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
    )
    defer display.close(d)
    
    r : Renderer = renderer.create(program.render_width, program.render_height, &spall_ctx, &spall_buffer)
    defer renderer.close(&r)

    mesh := base.load_obj("assets/leon.obj")
    defer base.destroy_mesh(&mesh)


    camera := base.create_camera(
        {20,-20,20}, {0,0,0}, 3.14*0.5, 
        f32(program.render_width)/f32(program.render_height),
        0.001, 1000.0
    )

    trs_matrix : matrix[4,4]f32 = linalg.matrix4_scale_f32({0.5, 0.5, 0.5})
    mvp_matrix : matrix[4,4]f32 = camera.proj_matrix * camera.view_matrix * trs_matrix
    renderer.update_light_position(&r, {100, -15, 0})
    model_matricies := make([dynamic]matrix[4,4]f32)

    //frame : f32 = 0.0
    for 
    {   
        free_all(context.temp_allocator)
        clear(&model_matricies)
        renderer.clear_buffer(&r, {1.0, 1.0, 1.0, 1.0})
        renderer.begin_draw(&r)

        direction, delta := base.process_input(0.1)
        base.move_camera(&camera, direction, delta)

        view_proj := base.get_view_projection(&camera)

        {
            for i in 0..<10
            {
                for j in 0..<10
                {
                    translation := base.translate({f32(i * 15), 0, -f32(j * 15)}, trs_matrix)
                    //append(&model_matricies, translation)
                    {
                        //spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, "raster_single")
                        renderer.draw_mesh(&r, &mesh, translation, view_proj)
                    }
                }
            }
        }

        {
            renderer.end_draw(&r)
        }
        if display.present(d, renderer.get_framebuffer(&r)) {break}
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