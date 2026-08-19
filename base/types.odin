package base

V4 :: [4]f32
V3 :: [3]f32
V2 :: [2]f32

M4 :: matrix[4,4]f32

Color :: V4

vertex_procedure :: proc(Vertex, f32)-> Vertex
fragment_procedure :: proc(FragmentIn, f32) -> FragmentOut

FragmentIn :: struct
{
    screen_pos : [2]i32,
    depth : f32,
    uv : V2,
    color : Color,
    tex : ^Texture
}

FragmentOut :: struct
{
    color : Color,
    depth : f32,
    discard : bool,
}

Face :: struct
{
    f0, f1, f2 : u32,
}

FragCoord :: struct
{
    z : f32,
    c : Color,
    uv: V2,
    normal: V3,
    inv_w : f32,
}

Point :: struct
{
    x, y : int,
    z : f32,
    color : Color,
    uv : V2,
    normal : V3,
}

ScreenCoord :: struct
{
    x, y : int,
}

edge_function :: proc(a, b, p : ScreenCoord) -> int
{
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
}

point_in_triangle :: proc(a, b, c, p: ScreenCoord) -> bool
{
    w0 : int = edge_function(a, b, p)
    w1 : int = edge_function(b, c, p)
    w2 : int = edge_function(c, a, p)

    if w0 >= 0 && w1 >= 0 && w2 >= 0 do return true
    return false
}

RasterTriangle :: struct
{
    s0, s1, s2 : ScreenCoord,
    f0, f1, f2 : FragCoord,
    texture_index : int,
    area : f32,
    frag_proc : fragment_procedure
}

Vertex :: struct
{
    x, y, z : f32,
    nx, ny, nz : f32,
    u, v : f32,
}

Material :: struct
{
    texture : Texture, 
}

FaceGroup :: struct
{
    last_face_index : int,
    material_name : string,
}

Mesh :: struct
{
    vertices : []Vertex,
    faces : []Face,
    materials : map[string]Material,
    face_groups : []FaceGroup,
}

NewMesh :: struct
{
    verticies : []Vertex,
}

Model :: struct
{
    meshes : []NewMesh,
    textures : []Texture,
    tex_to_mesh_index : []int,
    bounding_radius : f32,
}

destroy_mesh :: proc(mesh : ^Mesh)
{
    delete(mesh.vertices)
    delete(mesh.faces)
    delete(mesh.face_groups)

    for key, material in mesh.materials
    {
        delete(key)
        mat := material
        unload_texture(&mat.texture)
    }
    delete(mesh.materials)
}

RasterVertex :: struct
{
    position : V4,
    light_color : Color,
    normal : V3,
    uv : V2,
}

Options :: struct
{
    backface_culling : bool,
    affine_textures : bool,
    frame_target : int,
}