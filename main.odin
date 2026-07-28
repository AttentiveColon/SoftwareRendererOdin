package main

import "display"
import "renderer"
import "base"
import "core:math/linalg"
import "core:log"

Display :: display.Display
Renderer :: renderer.Renderer

testing : bool : true

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
        60,                     // frame target (0 for uncapped)
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
    
    r : Renderer = renderer.create(program.render_width, program.render_height)
    defer renderer.close(&r)

    mesh := base.load_obj("assets/leon.obj")


    camera := base.create_camera(
        {20,-20,20}, {0,0,0}, 3.14*0.5, 
        f32(program.render_width)/f32(program.render_height),
        0.001, 1000.0
    )

    trs_matrix : matrix[4,4]f32 = linalg.matrix4_scale_f32({0.51, 0.51, 0.51})
    mvp_matrix : matrix[4,4]f32 = camera.proj_matrix * camera.view_matrix * trs_matrix
    renderer.update_light_position(&r, {100, -15, 0})

    frame : f32 = 0.0
    for 
    {   
        free_all(context.temp_allocator)
        renderer.clear_buffer(&r, {1.0, 1.0, 1.0, 1.0})
        renderer.begin_draw(&r)

        direction, delta := base.process_input(0.1)
        base.move_camera(&camera, direction, delta)
        mvp_matrix = camera.proj_matrix * camera.view_matrix * trs_matrix

        renderer.draw_mesh(&r, mesh, mvp_matrix, trs_matrix)


        renderer.end_draw(&r)
        if display.present(d, renderer.get_framebuffer(&r)) {break}
    }
}

main :: proc()
{
    context.logger = log.create_console_logger()
    program : Program = create_program()
    run(program)
}