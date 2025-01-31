# ### [`ToEltype`](@ref)

"""
    ToEltype(T)

Converts any `AbstractArrayItem` to an `AbstractArrayItem{N, T}`.

Supports `apply!`.

## Examples

{cell=ToEltype}
```julia
using DataAugmentation

tfm = ToEltype(Float32)
item = ArrayItem(rand(Int, 10))
apply(tfm, item)
```
"""
struct ToEltype{T} <: Transform end
ToEltype(T::Type) = ToEltype{T}()

apply(::ToEltype{T}, item::AbstractArrayItem{N, <:T}; randstate = nothing) where {N, T} = item
function apply(::ToEltype{T1}, item::AbstractArrayItem{N, T2}; randstate = nothing) where {N, T1, T2}
    newdata = map(x -> convert(T1, x), itemdata(item))
    item = setdata(item, newdata)
    return item
end

function apply!(buf, ::ToEltype, item::AbstractArrayItem; randstate = nothing)
    ## copy! does type conversion under the hood
    copy!(itemdata(buf), itemdata(item))
    return buf
end

# ### [`Normalize`](@ref)

"""
    Normalize(means, stds)

Normalizes the last dimension of an `AbstractArrayItem{N}`.

Supports `apply!`.

## Examples

Preprocessing a 3D image with 3 color channels.

{cell=Normalize}
```julia
using DataAugmentation, Images
image = Image(rand(RGB, 20, 20, 20))
tfms = ImageToTensor() |> Normalize((0.1, -0.2, -0.1), (1,1,1.))
apply(tfms, image)
```

"""
struct Normalize{N} <: Transform
    means::SVector{N}
    stds::SVector{N}
end

function Normalize(means, stds)
    length(means) == length(stds) || error("`means` and `stds` must have same length")
    N = length(means)
    return Normalize{N}(SVector{N}(means), SVector{N}(stds))
end

function apply(tfm::Normalize, item::ArrayItem{N, T}; randstate = nothing) where {N, T}
    return ArrayItem(normalize(itemdata(item), tfm.means, tfm.stds))
end

function apply!(
        buf,
        tfm::Normalize,
        item::ArrayItem;
        randstate = nothing)
    copy!(itemdata(buf), itemdata(item))
    normalize!(itemdata(buf), tfm.means, tfm.stds)
    return buf
end


function normalize!(
        a::AbstractArray{T, N},
        means::SVector{M},
        stds::SVector{M}) where {N, T, M}
    means = reshape(convert.(T, means), (1 for _ = 2:N)..., M)
    stds = reshape(convert.(T, stds), (1 for _ = 2:N)..., M)
    a .-= means
    a ./= stds
    return a
end

normalize(a, means, stds) = normalize!(copy(a), means, stds)

function denormalize!(
        a::AbstractArray{T, N},
        means::SVector{M},
        stds::SVector{M}) where {N, T, M}
    means = reshape(convert.(T, means), (1 for _ = 2:N)..., M)
    stds = reshape(convert.(T, stds), (1 for _ = 2:N)..., M)
    a .*= stds
    a .+= means
    return a
end

denormalize(a, means, stds) = denormalize!(copy(a), means, stds)


# ### [`NormalizeIntensity`]

"""
    NormalizeIntensity()

Normalizes the pixels of an array based on calculated mean and std.
"""

struct NormalizeIntensity <: Transform end

function apply(tfm::NormalizeIntensity, item::ArrayItem; randstate = nothing)
    array = itemdata(item)
    slices = ones(Bool, size(array))
    means = mean(array[slices])
    stds = std(array[slices])
    array[slices] = (array[slices] .- means) / stds
    return ArrayItem(array)
end

# ### [`ImageToTensor`]

"""
    ImageToTensor()

Expands an `Image{N, T}` of size `sz` to an `ArrayItem{N+1}` with
size `(sz..., ch)` where `ch` is the number of color channels of `T`.

Supports `apply!`.

## Examples

{cell=ImageToTensor}
```julia
using DataAugmentation, Images

image = Image(rand(RGB, 50, 50))
tfm = ImageToTensor()
apply(tfm, image)
```

"""
struct ImageToTensor{T} <: Transform end

ImageToTensor(T::Type{<:Number} = Float32) = ImageToTensor{T}()


function apply(::ImageToTensor{T}, image::Image; randstate = nothing) where T
    return ArrayItem(imagetotensor(itemdata(image), T))
end


function apply!(buf, ::ImageToTensor, image::Image; randstate = nothing)
    imagetotensor!(buf.data, image.data)
    return buf
end

function imagetotensor(image::AbstractArray{C, N}, T = Float32) where {C<:Color, N}
    T.(PermutedDimsArray(_channelview(image), ((i for i in 2:N+1)..., 1)))
end

#=
function imagetotensor(image::AbstractArray{C, N}, T = Float32) where {TC, C<:Color{TC, 1}, N}
    return T.(_channelview(image))
end
=#


# TODO: relax color type constraint, implement for other colors
# single-channel colors need a `channelview` that also expands the array
function imagetotensor!(buf, image::AbstractArray{<:Color, N}) where N
    permutedims!(
        buf,
        _channelview(image),
        (2:N+1..., 1))
end

function tensortoimage(a::AbstractArray)
    nchannels = size(a)[end]
    if nchannels == 3
        return tensortoimage(RGB, a)
    elseif nchannels == 1
        return tensortoimage(Gray, a)
    else
        error("Found image tensor with $nchannels color channels. Pass in color type
                explicitly.")
    end
end

function tensortoimage(C::Type{<:Color}, a::AbstractArray{T, N}) where {T, N}
    perm = (N, 1:N-1...)
    return _colorview(C, PermutedDimsArray(a, perm))
end


function _channelview(img)
    chview = channelview(img)
    # for single-channel colors, expand the color dimension anyway
    if size(img) == size(chview)
        chview = reshape(chview, 1, size(chview)...)
    end
    return chview
end

function _colorview(C::Type{<:Color}, img)
    if size(img, 1) == 1
        img = reshape(img, size(img)[2:end])
    end
    return colorview(C, img)
end

# OneHot encoding

"""
    OneHot([T = Float32])

One-hot encodes a `MaskMulti` with `n` classes and size `sz` into
an array item of size `(sz..., n)` with element type `T`. Supports [`apply!`](@ref).

```julia
item = MaskMulti(rand(1:4, 100, 100), 1:4)
apply(OneHot(), item)
```
"""
struct OneHot{T} <: Transform end
OneHot() = OneHot{Float32}()

function apply(tfm::OneHot{T}, item::MaskMulti; randstate = nothing) where T
    mask = parent(itemdata(item))
    a = zeros(T, size(mask)..., length(item.classes))
    for I in CartesianIndices(mask)
        a[I, mask[I]] = one(T)
    end

    return ArrayItem(a)
end


function apply!(buf, tfm::OneHot{T}, item::MaskMulti; randstate = nothing) where T
    mask = parent(itemdata(item))
    a = itemdata(buf)
    fill!(a, zero(T))

    for I in CartesianIndices(mask)
        a[I, mask[I]] = one(T)
    end

    return buf
end


function onehot(T, x::Int, n::Int)
    v = fill(zero(T), n)
    v[x] = one(T)
    return v
end
onehot(x, n) = onehot(Float32, x, n)
