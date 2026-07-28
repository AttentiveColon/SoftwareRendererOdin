package display

import "core:log"
import rl "vendor:raylib"

Display :: struct
{
    render_width, render_height : i32,
    screen_texture : rl.Texture2D,
    source_rect, dest_rect : rl.Rectangle,
    title : cstring,
    frame_target : i32,
}

create :: proc(
    window_width, window_height, render_width, render_height, frame_target : i32, 
    title : cstring,
    ) -> Display
{
    rl.InitWindow(window_width, window_height, title)
    rl.SetTargetFPS(frame_target)
    blank_image : rl.Image = rl.GenImageColor(render_width, render_height, rl.BLACK)
    screen_texture : rl.Texture2D = rl.LoadTextureFromImage(blank_image)
    rl.UnloadImage(blank_image)
    rl.SetTextureFilter(screen_texture, rl.TextureFilter.POINT)
    source_rect : rl.Rectangle = {0, 0, f32(render_width), f32(render_height)}
    dest_rect : rl.Rectangle = {0, 0, f32(window_width), f32(window_height)}
    display : Display = {
        render_width, 
        render_height, 
        screen_texture, 
        source_rect, 
        dest_rect, 
        title, 
        frame_target
    }
    return display
}

present :: proc(display : Display, framebuffer : []u32) -> bool
{
    if display.render_width * display.render_height != i32(len(framebuffer))
    {
        log.fatal("Render target mismatch")
        return false
    }

    rl.UpdateTexture(display.screen_texture, raw_data(framebuffer))
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLACK)

    rl.DrawTexturePro(display.screen_texture, display.source_rect, display.dest_rect, {0,0}, 0.0, rl.WHITE)
    rl.DrawFPS(10, 10)
    rl.EndDrawing()
    return rl.WindowShouldClose()
}

close :: proc(display : Display)
{
    rl.UnloadTexture(display.screen_texture)
    rl.CloseWindow()
}