package asset

import "core:thread"
import "core:os"
import "core:log"
import "../base"
import "core:strconv"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import cgltf "vendor:cgltf"
import rl "vendor:raylib"
import "core:math"

// Bind to the global C namespace where Raylib has already exposed the STB symbols
foreign import libc "system:c"

@(default_calling_convention="c")
foreign libc {
    stbi_load_from_memory :: proc(buffer: ^u8, len: i32, x, y, channels_in_file: ^i32, desired_channels: i32) -> ^u8 ---
    stbi_load             :: proc(filename: cstring, x, y, channels_in_file: ^i32, desired_channels: i32) -> ^u8 ---
    stbi_image_free       :: proc(retval_from_stbi_load: rawptr) ---
}


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

// load_gltf :: proc(manager : ^Manager, filepath : string) -> ^base.Model
// {
//     options : cgltf.options = {}
//     data := new(cgltf.data)
//     result : cgltf.result
//     c_filepath := strings.clone_to_cstring(filepath, context.allocator)
//     data, result = cgltf.parse_file(options, c_filepath)
//     log.debug(result)
    
//     return {}
// }


load2 :: proc(manager : ^Manager, filepath_str : string, y_up : bool = true, ccw_winding : bool = false) -> ^base.Model {
    options := cgltf.options{}
    
    c_filepath := strings.clone_to_cstring(filepath_str, context.temp_allocator)
    data, result := cgltf.parse_file(options, c_filepath)
    if result != .success { return nil }
    defer cgltf.free(data)
    
    if cgltf.load_buffers(options, data, c_filepath) != .success { return nil }

    model := new(base.Model)
    
    total_primitives := 0
    for node in data.nodes 
    {
        if node.mesh != nil 
        {
            total_primitives += len(node.mesh.primitives)
        }
    }

    // allocate textures based on the number of IMAGES, not materials.
    num_textures := len(data.images)
    if num_textures == 0 { num_textures = 1 } // if no images found, set to 1 for a fallback

    model.meshes = make([]base.NewMesh, total_primitives, context.allocator)
    model.textures = make([]base.Texture, num_textures, context.allocator)
    model.tex_to_mesh_index = make([]int, total_primitives, context.allocator)

    // process images
    if len(data.images) == 0 
    {
        // if no images found, default to fallback white texture
        my_pixels := make([]base.V4, 1, context.allocator)
        my_pixels[0] = {1.0, 1.0, 1.0, 1.0}
        model.textures[0] = base.Texture{
            name = "default_white", width = 1, height = 1, pixels = my_pixels,
        }
    } 
    else 
    {
        for img, i in data.images 
        {
            width, height, channels : i32 = 1, 1, 4
            pixels_ptr : ^u8 = nil
            
            if img.buffer_view != nil 
            {
                offset := img.buffer_view.offset
                size := img.buffer_view.size
                buf_data := cast([^]u8)img.buffer_view.buffer.data
                pixels_ptr = stbi_load_from_memory(&buf_data[offset], i32(size), &width, &height, &channels, 4)
            } 
            else if img.uri != nil 
            {
                uri_str := string(img.uri)
                dir := filepath.dir(filepath_str)
                img_path, err := filepath.join({dir, uri_str}, context.temp_allocator)
                c_img_path := strings.clone_to_cstring(img_path, context.temp_allocator)
                pixels_ptr = stbi_load(c_img_path, &width, &height, &channels, 4)
            }
            
            if pixels_ptr != nil 
            {
                num_pixels := int(width * height)
                my_pixels := make([]base.V4, num_pixels, context.allocator)
                pixel_slice := slice.from_ptr(pixels_ptr, num_pixels * 4)
                
                for p := 0; p < num_pixels; p += 1 
                {
                    pidx := p * 4
                    my_pixels[p] = [4]f32{
                        f32(pixel_slice[pidx + 0]) / 255.0,
                        f32(pixel_slice[pidx + 1]) / 255.0,
                        f32(pixel_slice[pidx + 2]) / 255.0,
                        f32(pixel_slice[pidx + 3]) / 255.0,
                    }
                }
                
                model.textures[i] = base.Texture{
                    name = fmt.aprintf("%s_img%d", filepath_str, i),
                    width = width, height = height, pixels = my_pixels,
                }
                stbi_image_free(pixels_ptr)
            } 
            else 
            {
                my_pixels := make([]base.V4, 1, context.allocator)
                my_pixels[0] = {1.0, 0.0, 1.0, 1.0} // Magenta error fallback for failed decodes
                model.textures[i] = base.Texture{
                    name = fmt.aprintf("%s_img%d_failed", filepath_str, i),
                    width = 1, height = 1, pixels = my_pixels,
                }
            }
        }
    }

    // process nodes and texture indicies
    mesh_idx := 0
    for n in 0..<len(data.nodes) 
    {
        node := &data.nodes[n]
        if node.mesh == nil { continue }

        mat : [16]f32
        cgltf.node_transform_world(node, &mat[0])

        for prim in node.mesh.primitives 
        {
            
            // map the primitive to the correct IMAGE index, not material index
            img_idx := 0
            if prim.material != nil 
            {
                // navigate: primitive -> material -> texture -> image
                target_img: ^cgltf.image = nil
                
                // look for common places you'd find diffuse/albedo textures
                if prim.material.has_pbr_metallic_roughness 
                {
                    if prim.material.pbr_metallic_roughness.base_color_texture.texture != nil 
                    {
                        target_img = prim.material.pbr_metallic_roughness.base_color_texture.texture.image_
                    }
                } else if prim.material.has_pbr_specular_glossiness 
                {
                    if prim.material.pbr_specular_glossiness.diffuse_texture.texture != nil 
                    {
                        target_img = prim.material.pbr_specular_glossiness.diffuse_texture.texture.image_
                    }
                }
                
                // if we found a valid image pointer, calculate its index in the global data.images slice
                if target_img != nil && len(data.images) > 0 
                {
                    img_ptr_diff := uintptr(target_img) - uintptr(raw_data(data.images))
                    img_idx = int(img_ptr_diff / size_of(cgltf.image))
                }
            }
            model.tex_to_mesh_index[mesh_idx] = img_idx
            
            pos_acc, norm_acc, uv_acc: ^cgltf.accessor
            
            for attr in prim.attributes 
            {
                #partial switch attr.type 
                {
                    case .position: pos_acc = attr.data
                    case .normal:   norm_acc = attr.data
                    case .texcoord: if uv_acc == nil { uv_acc = attr.data }
                }
            }
            
            if pos_acc == nil 
            {
                mesh_idx += 1
                continue
            }
            
            idx_acc := prim.indices
            total_render_vertices := int(idx_acc != nil ? idx_acc.count : pos_acc.count)
            verticies := make([]base.Vertex, total_render_vertices, context.allocator)
            
            for j in 0..<total_render_vertices 
            {
                v_index := uint(j)
                if idx_acc != nil 
                {
                    v_index = cgltf.accessor_read_index(idx_acc, uint(j))
                }
                
                pos: [3]f32
                err := cgltf.accessor_read_float(pos_acc, v_index, &pos[0], 3)
                
                tx := pos[0] * mat[0] + pos[1] * mat[4] + pos[2] * mat[8]  + mat[12]
                ty := pos[0] * mat[1] + pos[1] * mat[5] + pos[2] * mat[9]  + mat[13]
                tz := pos[0] * mat[2] + pos[1] * mat[6] + pos[2] * mat[10] + mat[14]
                
                x, y, z := tx, ty, tz
                
                if y_up { y = -y }
                if ccw_winding { temp := x; x = z; z = temp }
                
                nx, ny, nz : f32
                if norm_acc != nil 
                {
                    norm: [3]f32
                    err := cgltf.accessor_read_float(norm_acc, v_index, &norm[0], 3)
                    
                    tnx := norm[0] * mat[0] + norm[1] * mat[4] + norm[2] * mat[8]
                    tny := norm[0] * mat[1] + norm[1] * mat[5] + norm[2] * mat[9]
                    tnz := norm[0] * mat[2] + norm[1] * mat[6] + norm[2] * mat[10]
                    
                    length := math.sqrt(tnx*tnx + tny*tny + tnz*tnz)
                    if length > 0.0001 
                    {
                        tnx /= length; tny /= length; tnz /= length
                    }
                    
                    nx, ny, nz = tnx, tny, tnz
                    
                    if y_up { ny = -ny }
                    if ccw_winding { temp := nx; nx = nz; nz = temp }
                }

                u, v : f32
                if uv_acc != nil 
                {
                    uv: [2]f32
                    err := cgltf.accessor_read_float(uv_acc, v_index, &uv[0], 2)
                    u, v = uv[0], uv[1]
                }
                
                verticies[j] = base.Vertex{
                    x = x, y = y, z = z,
                    nx = nx, ny = ny, nz = nz,
                    u = u, v = v,
                }
            }
            model.meshes[mesh_idx].verticies = verticies
            mesh_idx += 1
        }
    }
    return model
}

// load :: proc(manager : ^Manager, filepath : string, y_up : bool = true, ccw_winding : bool = true) -> ^base.Model
// {
//     // worry about threading after getting model loading working
//     //task_data := new(Load_Thread)
//     //task_data.manager = manager
//     //task_data.filepath = filepath
//     rl_model := rl.LoadModel(strings.clone_to_cstring(filepath, context.temp_allocator))
//     defer rl.UnloadModel(rl_model)
    
//     model := new(base.Model)

//     model.meshes = make([]base.NewMesh, rl_model.meshCount, context.allocator)
//     model.textures = make([]base.Texture, rl_model.materialCount, context.allocator)
//     model.tex_to_mesh_index = make([]int, rl_model.meshCount, context.allocator)

//     for i in 0..<rl_model.materialCount
//     {
//         rl_mat := rl_model.materials[i]
//         rl_tex := rl_mat.maps[rl.MaterialMapIndex.ALBEDO].texture
//         rl_img := rl.LoadImageFromTexture(rl_tex)
//         rl_data_ptr := rl.LoadImageColors(rl_img)
//         num_pixels := int(rl_img.width * rl_img.height)
//         rl_data_slice := slice.from_ptr(rl_data_ptr, num_pixels)
//         my_pixels := make([]base.V4, num_pixels, context.allocator)
//         for p, pidx in rl_data_slice
//         {
//             // Cast each u8 channel to f32 and normalize
//             my_pixels[pidx] = [4]f32{
//                 f32(p.r) / 255.0,
//                 f32(p.g) / 255.0,
//                 f32(p.b) / 255.0,
//                 f32(p.a) / 255.0,
//             }
//         }
//         model.textures[i] = base.Texture{
//             name = fmt.aprintf("%s_%d", filepath, rl_tex.id),
//             width = rl_tex.width,
//             height = rl_tex.height,
//             pixels = my_pixels
//         }
//         rl.UnloadImageColors(rl_data_ptr)
//         rl.UnloadImage(rl_img)
//     }
//     for i in 0..<rl_model.meshCount
//     {
//         model.tex_to_mesh_index[i] = int((cast([^]i32)rl_model.meshMaterial)[i])

//         current_mesh := rl_model.meshes[i]

//         // total verticies is triangle count * 3
//         total_render_vertices := current_mesh.triangleCount * 3
//         verticies := make([]base.Vertex, total_render_vertices, context.allocator)

//         indices := slice.from_ptr(current_mesh.indices, int(total_render_vertices))
        
//         for j in 0..<total_render_vertices
//         {
//             // fall back to sequential indexing if model isn't indexed
//             v_index := int(j)
//             if indices != nil {
//                 v_index = int(indices[j])
//             }
            
//             // calculate offsets based on index
//             v_idx := v_index * 3
//             uv_idx := v_index * 2
            
//             // TODO: add checking and fallbacks if normals or texcoords dont exist
            
            
//             x, y, z : f32
//             x = current_mesh.vertices[v_idx + 0]
//             y = current_mesh.vertices[v_idx + 1]
//             if y_up
//             {
//                 y = -current_mesh.vertices[v_idx + 1]
//             }
//             z = current_mesh.vertices[v_idx + 2]
//             if ccw_winding
//             {
//                 temp := x
//                 x = z
//                 z = temp
//             }
            
//             nx, ny, nz : f32
//             if current_mesh.normals != nil
//             {
//                 nx = current_mesh.normals[v_idx + 0]
//                 ny = current_mesh.normals[v_idx + 1]
//                 nz = current_mesh.normals[v_idx + 2]
//             }

//             u, v : f32
//             if current_mesh.texcoords != nil
//             {
//                 u = current_mesh.texcoords[uv_idx + 0]
//                 v = current_mesh.texcoords[uv_idx + 1]
//             }
            
//             verticies[j] = base.Vertex{
//                 x = x,
//                 y = y,
//                 z = z,
//                 nx = nx,
//                 ny = ny,
//                 nz = nz,
//                 u = u,
//                 v = v,
//             }
//         }
//         model.meshes[i].verticies = verticies
//     }
//     return model
// }

// print_model_statistics :: proc(model : ^rl.Model)
// {
//     log.debug(
//         "Mesh Count: ", 
//         model.meshCount, 
//         " Material Count: ", 
//         model.materialCount,
//     )
// }

close :: proc(manager : ^Manager)
{
    thread.pool_finish(manager.thread_pool)
    thread.pool_destroy(manager.thread_pool)
    free(manager.thread_pool)
}