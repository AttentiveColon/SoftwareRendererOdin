package base

import "core:math"
import "core:math/linalg"


translate :: proc(offset : V3, trs : matrix[4,4]f32) -> matrix[4,4]f32
{
    offset_matrix := linalg.matrix4_translate(offset)
    instance_model := offset_matrix * trs
    return instance_model
}