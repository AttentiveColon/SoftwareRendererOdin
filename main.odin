package main

import "core:fmt"
import "display"
import "renderer"
import "base"

Display :: display.Display
Renderer :: renderer.Renderer

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
    return {1, 1, 640, 512, 640, 512, 0, "title"}
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
    defer renderer.close(r)

    //Texture test code
    tex := base.load_texture("assets/EMD48.png")
    for c, index in tex.pixels
    {
        r.framebuffer[index] = base.to_uint32_color(tex.pixels[index])
    }

    base.load_obj("assets/leon.obj")


    for 
    {
        if display.present(d, renderer.get_framebuffer(r)) {break}
    }
}

main :: proc()
{
    program : Program = create_program()
    run(program)
}