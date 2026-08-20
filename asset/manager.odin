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
import stbi "vendor:stb/image"
import "core:math"

Manager :: struct
{

}



create :: proc() -> Manager
{
    return {}
}


load2 :: proc(manager : ^Manager, filepath_str : string, y_up : bool = true, ccw_winding : bool = false) -> ^base.Model {
    options := cgltf.options{}
    c_filepath := strings.clone_to_cstring(filepath_str, context.temp_allocator)
    data, result := cgltf.parse_file(options, c_filepath)
    if result != .success { return nil }
    defer cgltf.free(data)
    
    if cgltf.load_buffers(options, data, c_filepath) != .success { return nil }
    
    model := new(base.Model)
    
    total_primitives := 0
    for &node in data.nodes 
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
                pixels_ptr = stbi.load_from_memory(&buf_data[offset], i32(size), &width, &height, &channels, 4)
            } 
            else if img.uri != nil 
            {
                uri_str := string(img.uri)
                dir := filepath.dir(filepath_str)
                img_path, err := filepath.join({dir, uri_str}, context.temp_allocator)
                c_img_path := strings.clone_to_cstring(img_path, context.temp_allocator)
                pixels_ptr = stbi.load(c_img_path, &width, &height, &channels, 4)
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
                stbi.image_free(pixels_ptr)
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

    // track extents of x, y, z values
    min_bounds := [3]f32{math.F32_MAX, math.F32_MAX, math.F32_MAX}
    max_bounds := [3]f32{-math.F32_MAX, -math.F32_MAX, -math.F32_MAX}

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

                // update min and max extents
                min_bounds.x = math.min(min_bounds.x, x)
                min_bounds.y = math.min(min_bounds.y, y)
                min_bounds.z = math.min(min_bounds.z, z)

                max_bounds.x = math.max(max_bounds.x, x)
                max_bounds.y = math.max(max_bounds.y, y)
                max_bounds.z = math.max(max_bounds.z, z)
                
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
    
    // calculate midpoint and minimum enclosing sphere
    model.bounding_center = (min_bounds + max_bounds) * 0.5
    extent := max_bounds - model.bounding_center
    model.bounding_radius = math.sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z)

    return model
}

close :: proc(manager : ^Manager)
{
}