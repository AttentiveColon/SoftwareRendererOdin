package renderer

Renderer :: struct
{
    render_width, render_height : i32,
    framebuffer : []u32,
}

create :: proc(render_width, render_height : i32) -> Renderer
{
    framebuffer := make([]u32, render_width * render_height)
    return {render_width, render_height, framebuffer}
}

get_framebuffer :: proc(renderer : Renderer) -> []u32
{
    return renderer.framebuffer
}

close :: proc(renderer : Renderer)
{
    delete(renderer.framebuffer)
}