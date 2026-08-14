package display

import "core:log"
import "core:time"
import "core:fmt"
import sdl2 "vendor:sdl2"

Display :: struct
{
    window : ^sdl2.Window,
    window_surface : ^sdl2.Surface,
    renderer : ^sdl2.Renderer,
    texture : ^sdl2.Texture,
    render_width, render_height : i32,
    window_width, window_height : i32,
    frame_target : i32, 
    title : cstring,
    hardware_render : bool,
}

create :: proc(
    window_width,
    window_height,
    render_width,
    render_height,
    frame_target : i32,
    title : cstring,
    hardware_render : bool,
) -> Display
{
    if sdl2.Init(sdl2.INIT_VIDEO) != 0
    {
        log.fatalf("Failed to initialize SDL: %s", sdl2.GetError())
        return {}
    }

    window := sdl2.CreateWindow(
        title,
        sdl2.WINDOWPOS_UNDEFINED,
        sdl2.WINDOWPOS_UNDEFINED,
        window_width,
        window_height,
        {.SHOWN},
    )

    if window == nil
    {
        log.fatalf("Failed to create window: %s", sdl2.GetError())
        sdl2.Quit()
        return {}
    }

    window_surface : ^sdl2.Surface
    renderer : ^sdl2.Renderer
    texture : ^sdl2.Texture

    if hardware_render
    {
        renderer = sdl2.CreateRenderer(window, -1, {.ACCELERATED})
        if renderer == nil
        {
            log.fatalf("Failed to create renderer: %s", sdl2.GetError())
            sdl2.DestroyWindow(window)
            sdl2.Quit()
            return {}
        }

        texture = sdl2.CreateTexture(
            renderer,
            sdl2.PixelFormatEnum.RGBA32,
            .STREAMING,
            render_width,
            render_height,
        )
        if texture == nil
        {
            log.fatalf("Failed to create texture: %s", sdl2.GetError())
            sdl2.DestroyRenderer(renderer)
            sdl2.DestroyWindow(window)
            sdl2.Quit()
            return {}
        }
    }
    else
    {
        window_surface := sdl2.GetWindowSurface(window)
        if window_surface == nil
        {
            log.fatalf("Failed to get window surface: %s", sdl2.GetError())
            sdl2.DestroyWindow(window)
            sdl2.Quit()
            return {}
        }
    }

    

    return Display{
        window = window,
        window_surface = window_surface,
        renderer = renderer,
        texture = texture,
        render_width = render_width,
        render_height = render_height,
        window_width = window_width,
        window_height = window_height,
        frame_target = frame_target,
        title = title,
        hardware_render = hardware_render
    }
}

present :: proc(display : Display, framebuffer : []u32) -> bool
{
    @static last_time : f64
    @static fps_timer : f64
    @static frame_count : f64
    if last_time == 0.0
    {
        last_time = f64(sdl2.GetPerformanceCounter()) / f64(sdl2.GetPerformanceFrequency())
        fps_timer = last_time
    }

    if display.render_width * display.render_height != i32(len(framebuffer))
    {
        log.fatal("Render target mismatch!")
        return false
    }

    if display.hardware_render // take hardware accelerated path
    {
        pitch := display.render_width * 4
        sdl2.UpdateTexture(display.texture, nil, raw_data(framebuffer), pitch)
        sdl2.RenderClear(display.renderer)
        sdl2.RenderCopy(display.renderer, display.texture, nil, nil)
        sdl2.RenderPresent(display.renderer)
    }
    else // take software accelerated path
    {

        // convert framebuffer into surface
        src_surface := sdl2.CreateRGBSurfaceWithFormatFrom(
            raw_data(framebuffer),
            display.render_width,
            display.render_height,
            32,
            display.render_width * 4,
            u32(sdl2.PixelFormatEnum.RGBA32),
        )
        
        if src_surface == nil
        {
            log.fatalf("Failed to create surface from framebuffer: %s", sdl2.GetError())
            return false
        }
        defer sdl2.FreeSurface(src_surface)
        
        // blit the framebuffer surface to window surface
        dest_rect := sdl2.Rect{0, 0, display.window_width, display.window_height}
        sdl2.BlitScaled(src_surface, nil, display.window_surface, &dest_rect)
        
        // push surface to screen
        sdl2.UpdateWindowSurface(display.window)
    }

    // sdl requires polling in main thread
    should_close := false
    event : sdl2.Event
    for sdl2.PollEvent(&event)
    {
        #partial switch event.type
        {
            case .QUIT:
                should_close = true
        }
    }

    // frame pacing
    current_time := f64(sdl2.GetPerformanceCounter()) / f64(sdl2.GetPerformanceFrequency())
    if display.frame_target > 0
    {
        target_time := 1.0 / f64(display.frame_target)

        for current_time - last_time < target_time
        {
            time.sleep(time.Millisecond)
            current_time = f64(sdl2.GetPerformanceCounter()) / f64(sdl2.GetPerformanceFrequency())
        }
        last_time = current_time
    }
    else
    {
        last_time = f64(sdl2.GetPerformanceCounter()) / f64(sdl2.GetPerformanceFrequency())
    }

    // fps tracking and window title update
    frame_count += 1
    if current_time - fps_timer >= 0.5
    {
        fps := f64(frame_count) / (current_time - fps_timer)
        title_str := fmt.ctprintf("%s -> FPS: %.0f", display.title, fps)
        sdl2.SetWindowTitle(display.window, title_str)

        frame_count = 0
        fps_timer = current_time
    }

    return should_close
}

close :: proc(display : Display)
{
    if display.hardware_render
    {
        sdl2.DestroyTexture(display.texture)
        sdl2.DestroyRenderer(display.renderer)
    }
    sdl2.DestroyWindow(display.window)
    sdl2.Quit()
}