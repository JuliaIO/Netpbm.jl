module Netpbm

using FileIO, FixedPointNumbers, ColorTypes, ColorVectorSpace, ImageCore
using ColorTypes: AbstractGray

# Note: there is no endian standard, but netpbm is big-endian
const is_little_endian = ENDIAN_BOM == 0x04030201
const ufixedtype = Dict(10=>N6f10, 12=>N4f12, 14=>N2f14, 16=>N0f16)

function load(f::Union{File{format"PBMBinary"},File{format"PGMBinary"},File{format"PPMBinary"}})
    open(f) do s
        skipmagic(s)
        load(s)
    end
end

function load(s::Stream{format"PBMBinary"})
    io = stream(s)
    w, h = parse_netpbm_size(io)
    dat = BitArray(w, h)
    nbytes_per_row = ceil(Int, w/8)
    for irow = 1:h, j = 1:nbytes_per_row
        tmp = read(io, UInt8)
        offset = (j-1)*8
        for k = 1:min(8, w-offset)
            dat[offset+k, irow] = (tmp>>>(8-k))&0x01
        end
    end
    permuteddimsview(dat, (2,1))
end

function load(s::Stream{format"PGMBinary"})
    io = stream(s)
    w, h = parse_netpbm_size(io)
    maxval = parse_netpbm_maxval(io)
    if maxval <= 255
        dat8 = Array{UInt8}(undef, h, w)
        readio!(io, dat8)
        return reinterpret(Gray{N0f8}, dat8)
    elseif maxval <= typemax(UInt16)
        datraw = Array{UInt16}(undef, h, w)
        readio!(io, datraw)
        # Determine the appropriate Normed type
        T = ufixedtype[ceil(Int, log2(maxval)/2)<<1]
        return reinterpret(Gray{T}, datraw)
    else
        error("Image file may be corrupt. Are there really more than 16 bits in this image?")
    end
end

function load(s::Stream{format"PPMBinary"})
    io = stream(s)
    w, h = parse_netpbm_size(io)
    maxval = parse_netpbm_maxval(io)
    local dat
    if maxval <= 255
        dat8 = Array{UInt8}(undef, 3, h, w)
        readio!(io, dat8)
        return reshape(reinterpret(RGB{N0f8}, dat8), (h, w))
    elseif maxval <= typemax(UInt16)
        datraw = Array{UInt16}(undef, 3, h, w)
        readio!(io, datraw)
        # Determine the appropriate Normed type
        T = ufixedtype[ceil(Int, log2(maxval)/2)<<1]
        return reshape(reinterpret(RGB{T}, datraw), (h, w))
    else
        error("Image file may be corrupt. Are there really more than 16 bits in this image?")
    end
end

@noinline function readio!(io, dat::AbstractMatrix{T}) where {T}
    h, w = size(dat)
    for i = 1:h, j = 1:w  # io is stored in row-major format
        dat[i,j] = default_swap(read(io, T))
    end
    dat
end

@noinline function readio!(io, dat::AbstractArray{T,3}) where {T}
    size(dat, 1) == 3 || throw(DimensionMismatch("must be of size 3 in first dimension, got $(size(dat, 1))"))
    h, w = size(dat, 2), size(dat, 3)
    for i = 1:h, j = 1:w, k = 1:3  # io is stored row-major, color-first
        dat[k,i,j] = default_swap(read(io, T))
    end
    dat
end

function save(filename::File{format"PGMBinary"}, img; mapf=identity, mapi=nothing)
    mapf = kwrename(:mapf, mapf, :mapi, mapi, :save)
    open(filename, "w") do s
        io = stream(s)
        write(io, "P5\n")
        write(io, "# pgm file written by Julia\n")
        save(s, img, mapf=mapf)
    end
end

function save(filename::File{format"PPMBinary"}, img; mapf=identity, mapi=nothing)
    mapf = kwrename(:mapf, mapf, :mapi, mapi, :save)
    open(filename, "w") do s
        io = stream(s)
        write(io, "P6\n")
        write(io, "# ppm file written by Julia\n")
        save(s, img, mapf=mapf)
    end
end

function save(s::Stream, img::AbstractMatrix; mapf=identity, mapi=nothing)
    mapf = kwrename(:mapf, mapf, :mapi, mapi, :save)
    save(s, img, mapf)
end

@noinline function save(s::Stream{format"PGMBinary"}, img::AbstractMatrix{T}, mapf) where {T<:Union{Gray,Number}}
    h, w = size(img)
    Tout, mx = pnmmax(img)
    if sizeof(Tout) > 2
        error("element type $Tout (from $T) not supported")
    end
    write(s, "$w $h\n$mx\n")
    for i = 1:h, j = 1:w  # s is stored in row-major format
        write(s, default_swap(round(Tout, mx*gray(mapf(img[i,j])))))
    end
    nothing
end

@noinline function save(s::Stream{format"PPMBinary"}, img::AbstractMatrix{T}, mapf) where {T<:Color}
    h, w = size(img)
    Tout, mx = pnmmax(img)
    if sizeof(Tout) > 2
        error("element type $Tout (from $T) not supported")
    end
    write(s, "$w $h\n$mx\n")
    for i = 1:h, j = 1:w  # io is stored row-major, color-first
        c = RGB(mapf(img[i,j]))
        write(s, default_swap(round(Tout, mx*red(c))))
        write(s, default_swap(round(Tout, mx*green(c))))
        write(s, default_swap(round(Tout, mx*blue(c))))
    end
    nothing
end

function parse_netpbm_size(stream::IO)
    (parsenextint(stream), parsenextint(stream))
end

function parse_netpbm_maxval(stream::IO)
    parsenextint(stream)
end

function parsenextint(stream::IO)
    # ikirill: ugly, but I can't figure out a better way
    skipchars(isspace, stream, linecomment='#')
    from = position(stream)
    mark(stream)
    skipchars(isdigit, stream)
    to = position(stream)
    reset(stream)
    parse(Int, String(read(stream, to-from+1)))
end

function pnmmax(img::AbstractArray{T}) where {T}
    if isconcretetype(T)
        return pnmmax(eltype(T))
    end
    # Determine the concrete type that can hold all the elements
    S = typeof(first(img))
    for val in img
        S = promote_type(S, typeof(val))
    end
    pnmmax(eltype(S))
end

pnmmax(::Type{T}) where {T<:AbstractFloat} = UInt8, 255
function pnmmax(::Type{U}) where {U<:Normed}
    FixedPointNumbers.rawtype(U), reinterpret(one(U))
end
pnmmax(::Type{T}) where {T<:Unsigned} = T, typemax(T)

mybswap(i::Integer)  = bswap(i)
mybswap(i::Normed)   = bswap(i)
mybswap(c::Colorant) = mapc(bswap, c)
mybswap(c::RGB24) = c

const default_swap = is_little_endian ? mybswap : identity

function kwrename(newname, newval, oldname, oldval, caller::Symbol)
    if oldval !== nothing
        Base.depwarn("keyword $oldname has been renamed $newname", caller)
        return oldval
    end
    newval
end

end # module
