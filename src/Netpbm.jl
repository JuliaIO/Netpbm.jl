__precompile__()

module Netpbm

using FileIO, FixedPointNumbers, Colors, ColorVectorSpace, ImageCore
typealias AbstractGray{T} Color{T, 1}

# Note: there is no endian standard, but netpbm is big-endian
const is_little_endian = ENDIAN_BOM == 0x04030201
const ufixedtype = Dict(10=>UFixed10, 12=>UFixed12, 14=>UFixed14, 16=>UFixed16)

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
    # permuteddimsview(dat, (2,1))
    Base.PermutedDimsArrays.PermutedDimsArray(A, (2,1))
end

function load(s::Stream{format"PGMBinary"})
    io = stream(s)
    w, h = parse_netpbm_size(io)
    maxval = parse_netpbm_maxval(io)
    if maxval <= 255
        dat8 = Array{UInt8}(h, w)
        readio!(io, dat8)
        return reinterpret(Gray{U8}, dat8)
    elseif maxval <= typemax(UInt16)
        datraw = Array(UInt16, h, w)
        readio!(io, datraw)
        # Determine the appropriate UFixed type
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
        dat8 = Array{UInt8}(3, h, w)
        readio!(io, dat8)
        return reinterpret(RGB{U8}, dat8)
    elseif maxval <= typemax(UInt16)
        datraw = Array(UInt16, 3, h, w)
        readio!(io, datraw)
        # Determine the appropriate UFixed type
        T = ufixedtype[ceil(Int, log2(maxval)/2)<<1]
        return reinterpret(RGB{T}, datraw)
    else
        error("Image file may be corrupt. Are there really more than 16 bits in this image?")
    end
end

@noinline function readio!{T}(io, dat::AbstractMatrix{T})
    h, w = size(dat)
    for i = 1:h, j = 1:w  # io is stored in row-major format
        dat[i,j] = default_swap(read(io, T))
    end
    dat
end

@noinline function readio!{T}(io, dat::AbstractArray{T,3})
    size(dat, 1) == 3 || throw(DimensionMismatch("must be of size 3 in first dimension, got $(size(dat, 1))"))
    h, w = size(dat, 2), size(dat, 3)
    for i = 1:h, j = 1:w, k = 1:3  # io is stored row-major, color-first
        dat[k,i,j] = default_swap(read(io, T))
    end
    dat
end

function save(filename::File{format"PGMBinary"}, img; mapi=identity )
    open(filename, "w") do s
        io = stream(s)
        write(io, "P5\n")
        write(io, "# pgm file written by Julia\n")
        save(s, img, mapi=mapi)
    end
end

function save(filename::File{format"PPMBinary"}, img; mapi=identity)
    open(filename, "w") do s
        io = stream(s)
        write(io, "P6\n")
        write(io, "# ppm file written by Julia\n")
        save(s, img, mapi=mapi)
    end
end

save(s::Stream, img::AbstractMatrix; mapi=identity) = save(s, img, mapi)

@noinline function save{T<:Union{Gray,Number}}(s::Stream{format"PGMBinary"}, img::AbstractMatrix{T}, mapi)
    h, w = size(img)
    Tout, mx = pnmmax(img)
    if sizeof(Tout) > 2
        error("element type $Tout (from $T) not supported")
    end
    write(s, "$w $h\n$mx\n")
    for i = 1:h, j = 1:w  # s is stored in row-major format
        write(s, default_swap(round(Tout, mx*gray(mapi(img[i,j])))))
    end
    nothing
end

@noinline function save{T<:Color}(s::Stream{format"PPMBinary"}, img::AbstractMatrix{T}, mapi)
    h, w = size(img)
    Tout, mx = pnmmax(img)
    if sizeof(Tout) > 2
        error("element type $Tout (from $T) not supported")
    end
    write(s, "$w $h\n$mx\n")
    for i = 1:h, j = 1:w  # io is stored row-major, color-first
        c = RGB(mapi(img[i,j]))
        write(s, default_swap(round(Tout, mx*red(c))))
        write(s, default_swap(round(Tout, mx*green(c))))
        write(s, default_swap(round(Tout, mx*blue(c))))
    end
    nothing
end

function parse_netpbm_size(stream::IO)
    szline = strip(readline(stream))
    while isempty(szline) || szline[1] == '#'
        szline = strip(readline(stream))
    end
    parseints(szline, 2)
end

function parse_netpbm_maxval(stream::IO)
    skipchars(stream, isspace, linecomment='#')
    maxvalline = strip(readline(stream))
    parse(Int, maxvalline)
end

function parseints(line, n)
    ret = Array(Int, n)
    pos = 1
    for i = 1:n
        pos2 = search(line, ' ', pos)
        if pos2 == 0
            pos2 = length(line)+1
        end
        ret[i] = parse(Int, line[pos:pos2-1])
        pos = pos2+1
        if pos > length(line) && i < n
            error("Line terminated without finding all ", n, " integers")
        end
    end
    tuple(ret...)

end

function pnmmax{T}(img::AbstractArray{T})
    if isleaftype(T)
        return pnmmax(eltype(T))
    end
    # Determine the concrete type that can hold all the elements
    S = typeof(first(img))
    for val in img
        S = promote_type(S, typeof(val))
    end
    pnmmax(eltype(S))
end

pnmmax{T<:AbstractFloat}(::Type{T}) = UInt8, 255
function pnmmax{U<:UFixed}(::Type{U})
    FixedPointNumbers.rawtype(U), reinterpret(one(U))
end
pnmmax{T<:Unsigned}(::Type{T}) = T, typemax(T)

mybswap(i::Integer)  = bswap(i)
mybswap(i::UFixed)   = bswap(i)
mybswap(c::Colorant) = mapc(bswap, c)
mybswap(c::RGB24) = c

const default_swap = is_little_endian ? mybswap : identity

end # module
