
abstract type Scale <: AbstractAffine end

struct ScaleFixed{T<:Number} <: Scale
    size::Tuple{T, T}
end
struct ScaleRatio <: Scale
    ratios
end
ScaleRatio(fy::Number, fx::Number) = ScaleRatio((fy, fx))
ScaleRatio(f::Number) = ScaleRatio((f, f))

ScaleFixed(h::Int, w::Int) = ScaleFixed((h, w))

function getaffine(tfm::ScaleFixed, bounds, randstate, T = Float32)
    ratios = tfm.size ./ boundssize(bounds)
    return getaffine(ScaleRatio(ratios), bounds, randstate, T)
end

function getaffine(tfm::ScaleRatio, bounds, randstate, T = Float32)
    fy, fx = tfm.ratios
    return LinearMap(SMatrix{2, 2, T}([fy 0; 0 fx]))
end


"""
    ScaleKeepAspect(minlengths) <: Scale <: AbstractAffine
    ScaleKeepAspect(minlength)

Affine transformation that scales the shortest side of `item`
to `minlengths`, keeping the original aspect ratio.
"""
struct ScaleKeepAspect <: Scale
    minlengths::Tuple{Int, Int}
end

ScaleKeepAspect(minlength::Int) = ScaleKeepAspect((minlength, minlength))

function getaffine(tfm::ScaleKeepAspect, bounds, randstate, T = Float32)
    l1, l2 = tfm.minlengths
    ratio = maximum((l1, l2) ./ boundssize(bounds))
    getaffine(ScaleRatio((ratio, ratio)), bounds, randstate, T)
end
