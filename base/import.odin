package base

import os "core:os"
import str "core:strings"
import "core:strconv"
import "core:log"


load_obj :: proc(obj_filepath : string) -> OldMesh
{
    current_material := ""
    start_face_index := 0

    verticies : [dynamic]V3 = make([dynamic]V3, context.temp_allocator)
    uvs : [dynamic]V2 = make([dynamic]V2, context.temp_allocator)
    normals : [dynamic]V3 = make([dynamic]V3, context.temp_allocator)

    faces : [dynamic]Face
    materials : map[string]Material = make(map[string]Material)
    face_groups : [dynamic]FaceGroup
    final_verticies : [dynamic]Vertex
    
    data, ok := os.read_entire_file_from_path(obj_filepath, context.temp_allocator)
    if ok != os.ERROR_NONE
    {
        log.panic("Failed to load file!")
    }

    lines := string(data)

    for line in str.split_lines_iterator(&lines)
    {
        parts := str.fields(line, context.temp_allocator)

        if len(parts) == 0 || str.starts_with(parts[0], "#") {continue}

        prefix : string = parts[0]

        switch prefix
        {
            case "mtllib":
                base_filepath, s := os.get_absolute_path(obj_filepath, context.temp_allocator)
                if s != os.ERROR_NONE
                {
                    log.panic("Failed to resolve absolute file path!")
                }
                base_directory := os.dir(base_filepath)
                mtl_file_path := str.concatenate({base_directory, "/", parts[1]}, context.temp_allocator)
                materials = load_materials(mtl_file_path)
            case "usemtl":
                if len(faces) > start_face_index
                {
                    append(&face_groups, FaceGroup{len(faces) - 1, current_material})
                    start_face_index = len(faces)
                }
                current_material = str.clone(parts[1])
            case "v":
                v1, s1 := strconv.parse_f32(parts[1])
                v2, s2 := strconv.parse_f32(parts[2])
                v3, s3 := strconv.parse_f32(parts[3])
                if !s1 || !s2 || !s3 
                {
                    log.panic("Failed to parse f32 Vertex")
                }
                append(&verticies, V3{v1, -v2, v3})
            case "vt":
                u, s1 := strconv.parse_f32(parts[1])
                v, s2 := strconv.parse_f32(parts[2])
                if !s1 || !s2
                {
                    log.panic("Failed to parse f32 UV")
                }
                v = 1.0 - v
                append(&uvs, V2{u, v})
            case "vn":
                n1 , s1 := strconv.parse_f32(parts[1])
                n2 , s2 := strconv.parse_f32(parts[2])
                n3 , s3 := strconv.parse_f32(parts[3])
                if !s1 || !s2 || !s3
                {
                    log.panic("Failed to parse f32 Normal")
                }
                append(&normals, V3{n1, n2, n3})
            case "f":
                index0 := process_vertex(parts[1],uvs[:], verticies[:], normals[:], &final_verticies)
                index1 := process_vertex(parts[2],uvs[:], verticies[:], normals[:], &final_verticies)
                index2 := process_vertex(parts[3],uvs[:], verticies[:], normals[:], &final_verticies)
                append(&faces, Face{index0, index1, index2})
        }
    }
    if len(faces) > start_face_index
    {
        append(&face_groups, FaceGroup{len(faces) - 1, current_material})
    }
    
    return OldMesh{final_verticies[:], faces[:], materials, face_groups[:]}
}

load_materials :: proc(mtl_filepath : string) -> map[string]Material
{
    materials : map[string]Material = make(map[string]Material)
    data, ok := os.read_entire_file_from_path(mtl_filepath, context.temp_allocator)
    if ok != os.ERROR_NONE
    {
        log.panic("Failed reading material file: ", mtl_filepath)
    }

    lines := string(data)
    base_directory := os.dir(mtl_filepath)
    current_material_name : string
    
    for line in str.split_lines_iterator(&lines)
    {
        trimmed := str.trim(line, " \r\t\n")
        //trimmed = str.trim(trimmed, "\t")
        if trimmed == "" || str.starts_with(trimmed, "#") {continue}

        parts : []string = str.split(trimmed, " ", context.temp_allocator)
        prefix : string = parts[0]
        
        switch prefix
        {
            case "newmtl":
                current_material_name = str.clone(parts[1])
                materials[current_material_name] = Material{}
            case "map_Kd":
                if current_material_name != ""
                {
                    texture_filename : string = parts[1]
                    full_texture_filepath : string = str.concatenate({base_directory, "/", texture_filename}, context.temp_allocator)
                    texture : Texture = load_texture(full_texture_filepath)
                    material : Material = {texture}
                    materials[current_material_name] = material
                }
        }
    }
    return materials
}

process_vertex :: proc(
    face_data : string, 
    raw_uvs : []V2, 
    raw_verts, raw_norms : []V3, 
    final_vertices : ^[dynamic]Vertex) -> u32
    {
        indicies := str.split(face_data, "/", context.temp_allocator)
        // get position(-1 since OBJ is 1 indexed)
        v_index, ok := strconv.parse_int(indicies[0])
        if !ok
        {
            log.panic("Failed parsing obj indice data!")
        }
        v_index = v_index - 1
        pos : V3 = raw_verts[v_index]
        
        // get uv, check for len incase model has no textures
        uv : V2 = V2{0,0}
        if len(indicies) > 1 && len(indicies[1]) != 0
        {
            t_index, ok2 := strconv.parse_int(indicies[1])
            if !ok2
            {
                log.panic("Failed parsing obj indice data!")
            }
            t_index = t_index - 1
            uv = raw_uvs[t_index]
        }

        norm : V3 = V3{0,0,0}
        if len(indicies) > 2 && len(indicies[2]) != 0
        {
            n_index, ok2 := strconv.parse_int(indicies[2])
            if !ok2
            {
                log.panic("Failed parsing obj indice data!")
            }
            n_index = n_index - 1
            norm = raw_norms[n_index]
        }

        vertex : Vertex = {pos.x, pos.y, pos.z, norm.x, norm.y, norm.z, uv.x, uv.y}
        append(final_vertices, vertex)
        return u32(len(final_vertices) - 1)
    }