isdefined(Base, :__precompile__) && __precompile__()

module Netpbm

using Images, FileIO, ColorTypes, FixedPointNumbers, Compat
typealias AbstractGray{T} Color{T, 1}

import FileIO: load, save

const is_little_endian = ENDIAN_BOM == 0x04030201
const ufixedtype = @compat Dict(10=>Ufixed10, 12=>Ufixed12, 14=>Ufixed14, 16=>Ufixed16)

function load(f::@compat(Union{File{format"PBMBinary"},File{format"PGMBinary"},File{format"PPMBinary"}}))
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
    Image(dat, @compat Dict("spatialorder" => ["x", "y"], "pixelspacing" => [1,1]))
end

function load(s::Stream{format"PGMBinary"})
    io = stream(s)
    w, h = parse_netpbm_size(io)
    maxval = parse_netpbm_maxval(io)
    local dat
    if maxval <= 255
        dat = reinterpret(Gray{Ufixed8}, read(io, Ufixed8, w, h), (w, h))
    elseif maxval <= typemax(UInt16)
        datraw = Array(UInt16, w, h)
        if !is_little_endian
            for indx = 1:w*h
                datraw[indx] = read(io, UInt16)
            end
        else
            for indx = 1:w*h
                datraw[indx] = bswap(read(io, UInt16))
            end
        end
        # Determine the appropriate Ufixed type
        T = ufixedtype[ceil(Int, log2(maxval)/2)<<1]
        dat = reinterpret(Gray{T}, datraw, (w, h))
    else
        error("Image file may be corrupt. Are there really more than 16 bits in this image?")
    end
    T = eltype(dat)
    Image(dat, @compat Dict("colorspace" => "Gray", "spatialorder" => ["x", "y"], "pixelspacing" => [1,1]))
end

function load(s::Stream{format"PPMBinary"})
    io = stream(s)
    w, h = parse_netpbm_size(io)
    maxval = parse_netpbm_maxval(io)
    local dat
    if maxval <= 255
        datraw = read(io, Ufixed8, 3, w, h)
        dat = reinterpret(RGB{Ufixed8}, datraw, (w, h))
    elseif maxval <= typemax(UInt16)
        # read first as UInt16 so the loop is type-stable, then convert to Ufixed
        datraw = Array(UInt16, 3, w, h)
        # there is no endian standard, but netpbm is big-endian
        if !is_little_endian
            for indx = 1:3*w*h
                datraw[indx] = read(io, UInt16)
            end
        else
            for indx = 1:3*w*h
                datraw[indx] = bswap(read(io, UInt16))
            end
        end
        # Determine the appropriate Ufixed type
        T = ufixedtype[ceil(Int, log2(maxval)/2)<<1]
        dat = reinterpret(RGB{T}, datraw, (w, h))
    else
        error("Image file may be corrupt. Are there really more than 16 bits in this image?")
    end
    T = eltype(dat)
    Image(dat, @compat Dict("spatialorder" => ["x", "y"], "pixelspacing" => [1,1]))
end

function save(filename::File{format"PGMBinary"}, img; kwargs...)
    open(filename, "w") do s
        io = stream(s)
        write(io, "P5\n")
        write(io, "# pgm file written by Julia\n")
        save(s, img; kwargs...)
    end
end

function save(filename::File{format"PPMBinary"}, img; kwargs...)
    open(filename, "w") do s
        io = stream(s)
        write(io, "P6\n")
        write(io, "# ppm file written by Julia\n")
        save(s, img; kwargs...)
    end
end

pnmmax{T<:AbstractFloat}(::Type{T}) = 255
pnmmax{T<:Ufixed}(::Type{T}) = reinterpret(FixedPointNumbers.rawtype(T), one(T))
pnmmax{T<:Unsigned}(::Type{T}) = typemax(T)

function save{T<:Gray}(s::Stream{format"PGMBinary"}, img::AbstractArray{T}; mapi = mapinfo(img))
    w, h = widthheight(img)
    TE = eltype(T)
    mx = pnmmax(TE)
    write(s, "$w $h\n$mx\n")
    p = permutation_horizontal(img)
    writepermuted(s, img, mapi, p)
end

function save{T<:Number}(s::Stream{format"PGMBinary"}, img::AbstractArray{T}; mapi = mapinfo(img))
    io = stream(s)
    w, h = widthheight(img)
    cs = colorspace(img)
    cs == "Gray" || error("colorspace $cs not supported")
    mx = pnmmax(T)
    write(io, "$w $h\n$mx\n")
    p = permutation_horizontal(img)
    writepermuted(io, img, mapi, p)
end

function save{T<:Color}(s::Stream{format"PPMBinary"}, img::AbstractArray{T}; mapi = mapinfo(img))
    w, h = widthheight(img)
    TE = eltype(eltype(mapi))
    mx = pnmmax(TE)
    write(s, "$w $h\n$mx\n")
    p = permutation_horizontal(img)
    writepermuted(s, img, mapi, p; gray2color = T <: AbstractGray)
end

function save{T}(s::Stream{format"PPMBinary"}, img::AbstractArray{T}; mapi = mapinfo(img))
    io = stream(s)
    w, h = widthheight(img)
    cs = colorspace(img)
    in(cs, ("RGB", "Gray")) || error("colorspace $cs not supported")
    mx = pnmmax(T)
    write(io, "$w $h\n$mx\n")
    p = permutation_horizontal(img)
    writepermuted(io, img, mapi, p; gray2color = cs == "Gray")
end

# Permute to a color, horizontal, vertical, ... storage order (with time always last)
function permutation_horizontal(img)
    cd = colordim(img)
    td = timedim(img)
    p = spatialpermutation(["x", "y"], img)
    if cd != 0
        p[p .>= cd] += 1
        insert!(p, 1, cd)
    end
    if td != 0
        push!(p, td)
    end
    p
end

permutedims_horizontal(img) = permutedims(img, permutation_horizontal(img))

# Write values in permuted order
let method_cache = Dict()
global writepermuted
# Delete the following once img[i,j] returns the Color for an ImageCmap
writepermuted(stream, img::ImageCmap, mapi::MapInfo, perm; gray2color::Bool = false) =
    writepermuted(stream, convert(Image, img), mapi, perm; gray2color=gray2color)

function writepermuted(stream, img, mapi::MapInfo, perm; gray2color::Bool = false)
    cd = colordim(img)
    key = (perm, cd, gray2color)
    if !haskey(method_cache, key)
        swapfunc = is_little_endian ? :mybswap : :identity
        loopsyms = [symbol(string("i_",d)) for d = 1:ndims(img)]
        body = gray2color ? quote
                g = $swapfunc(map(mapi, img[$(loopsyms...)]))
                write(stream, g)
                write(stream, g)
                write(stream, g)
            end : quote
                write(stream, $swapfunc(map(mapi, img[$(loopsyms...)])))
            end
        loopargs = [:($(loopsyms[d]) = 1:size(img, $d)) for d = 1:ndims(img)]
        loopexpr = Expr(:for, Expr(:block, loopargs[perm[end:-1:1]]...), body)
        f = @eval begin
            local _writefunc_
            function _writefunc_(stream, img, mapi)
                $loopexpr
            end
        end
    else
        f = method_cache[key]
    end
    f(stream, img, mapi)
    nothing
end
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

function Base.write{T<:Ufixed}(io::IO, c::AbstractRGB{T})
    write(io, reinterpret(red(c)))
    write(io, reinterpret(green(c)))
    write(io, reinterpret(blue(c)))
end

function Base.write(io::IO, c::RGB24)
    write(io, red(c))
    write(io, green(c))
    write(io, blue(c))
end

Base.write(io::IO, c::Gray) = write(io, reinterpret(gray(c)))
Base.write(io::IO, c::Ufixed) = write(io, reinterpret(c))

mybswap(i::Integer) = bswap(i)
mybswap(i::Ufixed) = bswap(reinterpret(i))
mybswap(c::RGB24) = c
mybswap{T<:Ufixed}(c::AbstractRGB{T}) = RGB{T}(T(bswap(reinterpret(red(c))),0),
                                               T(bswap(reinterpret(green(c))),0),
                                               T(bswap(reinterpret(blue(c))),0))

# Netpbm mapinfo client. Converts to RGB and uses Ufixed.
mapinfo{T<:Unsigned}(img::AbstractArray{T}) = MapNone{T}()
mapinfo{T<:Ufixed}(img::AbstractArray{T}) = MapNone{T}()
mapinfo{T<:AbstractFloat}(img::AbstractArray{T}) = MapNone{Ufixed8}()
for ACV in (Color, AbstractRGB)
    for CV in subtypes(ACV)
        (length(CV.parameters) == 1 && !(CV.abstract)) || continue
        CVnew = CV<:AbstractGray ? Gray : RGB
        @eval mapinfo{T<:Ufixed}(img::AbstractArray{$CV{T}}) = MapNone{$CVnew{T}}()
        @eval mapinfo{CV<:$CV}(img::AbstractArray{CV}) = MapNone{$CVnew{Ufixed8}}()
    end
end
mapinfo(img::AbstractArray{RGB24}) = MapNone{RGB{Ufixed8}}()

end # module
