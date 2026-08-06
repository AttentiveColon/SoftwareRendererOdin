package asset

import rl "vendor:raylib"
import "core:thread"
import "core:os"
import "core:strings"
import "core:log"
import "../base"
import "core:strconv"
import "core:slice"
import "core:fmt"

Manager :: struct
{
    thread_pool : ^thread.Pool,
    pool_size : int,
}

Load_Thread :: struct
{
    manager : ^Manager,
    filepath : string,
    mesh : ^base.Mesh,
}

create :: proc() -> Manager
{
    thread_pool := new(thread.Pool)
    pool_size := os.get_processor_core_count()
    thread.pool_init(thread_pool, context.allocator, pool_size)
    thread.pool_start(thread_pool)
    return Manager{thread_pool, pool_size}
}

load_task :: proc(task : thread.Task)
{
    data := cast(^Load_Thread)task.data
    manager := data.manager
    filepath := data.filepath



    //assign to mesh at end
}

load :: proc(manager : ^Manager, filepath : string) -> ^base.Model
{
    // worry about threading after getting model loading working
    //task_data := new(Load_Thread)
    //task_data.manager = manager
    //task_data.filepath = filepath
    rl_model := rl.LoadModel(strings.clone_to_cstring(filepath, context.temp_allocator))
    defer rl.UnloadModel(rl_model)
    
    model := new(base.Model)

    model.meshes = make([]base.NewMesh, rl_model.meshCount, context.allocator)
    model.textures = make([]base.Texture, rl_model.materialCount, context.allocator)
    model.tex_to_mesh_index = make([]int, rl_model.meshCount, context.allocator)

    for i in 0..<rl_model.materialCount
    {
        rl_mat := rl_model.materials[i]
        rl_tex := rl_mat.maps[rl.MaterialMapIndex.ALBEDO].texture
        rl_img := rl.LoadImageFromTexture(rl_tex)
        rl_data_ptr := rl.LoadImageColors(rl_img)
        num_pixels := int(rl_img.width * rl_img.height)
        rl_data_slice := slice.from_ptr(rl_data_ptr, num_pixels)
        my_pixels := make([]base.V4, num_pixels, context.allocator)
        for p, pidx in rl_data_slice
        {
            // Cast each u8 channel to f32 and normalize
            my_pixels[pidx] = [4]f32{
                f32(p.r) / 255.0,
                f32(p.g) / 255.0,
                f32(p.b) / 255.0,
                f32(p.a) / 255.0,
            }
        }
        model.textures[i] = base.Texture{
            name = fmt.aprintf("%s_%d", filepath, rl_tex.id),
            width = rl_tex.width,
            height = rl_tex.height,
            pixels = my_pixels
        }
        rl.UnloadImageColors(rl_data_ptr)
        rl.UnloadImage(rl_img)
    }
    for i in 0..<rl_model.meshCount
    {
        model.tex_to_mesh_index[i] = int((cast([^]i32)rl_model.meshMaterial)[i])

        current_mesh := rl_model.meshes[i]

        // total verticies is triangle count * 3
        total_render_vertices := current_mesh.triangleCount * 3
        verticies := make([]base.Vertex, total_render_vertices, context.allocator)

        indices := slice.from_ptr(current_mesh.indices, int(total_render_vertices))

        for j in 0..<total_render_vertices
        {
            // fall back to sequential indexing if model isn't indexed
            v_index := int(j)
            if indices != nil {
                v_index = int(indices[j])
            }

            // calculate offsets based on index
            v_idx := v_index * 3
            uv_idx := v_index * 2

            // TODO: add checking and fallbacks if normals or texcoords dont exist

            verticies[j] = base.Vertex{
                x = current_mesh.vertices[v_idx + 0],
                y = current_mesh.vertices[v_idx + 1],
                z = current_mesh.vertices[v_idx + 2],
                nx = current_mesh.normals[v_idx + 0],
                ny = current_mesh.normals[v_idx + 1],
                nz = current_mesh.normals[v_idx + 2],
                u = current_mesh.texcoords[uv_idx + 0],
                v = current_mesh.texcoords[uv_idx + 1],
            }
        }
        model.meshes[i].verticies = verticies
    }

    return model
}

print_model_statistics :: proc(model : ^rl.Model)
{
    log.debug(
        "Mesh Count: ", 
        model.meshCount, 
        " Material Count: ", 
        model.materialCount,
    )
}

close :: proc(manager : ^Manager)
{
    thread.pool_finish(manager.thread_pool)
    thread.pool_destroy(manager.thread_pool)
    free(manager.thread_pool)
}