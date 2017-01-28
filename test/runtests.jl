using Netpbm, ColorTypes, FixedPointNumbers, IndirectArrays, ImageCore, FileIO
using Base.Test

@testset "IO" begin
    workdir = joinpath(tempdir(), "Images")
    isdir(workdir) && rm(workdir, recursive=true)
    mkdir(workdir)

    @testset "Gray pgm" begin
        af = rand(2, 3)
        for T in (N0f8, N4f12, N0f16,
                  Gray{N0f8}, Gray{N4f12}, Gray{N0f16})
            ac = convert(Array{T}, af)
            fn = File(format"PGMBinary", joinpath(workdir, "3by2.pgm"))
            Netpbm.save(fn, ac)
            b = Netpbm.load(fn)
            @test b == ac
        end
        a8 = convert(Array{N0f8}, af)
        for T in (Float32, Float64, Gray{Float32}, Gray{Float64})
            ac = convert(Array{T}, af)
            fn = File(format"PGMBinary", joinpath(workdir, "3by2.pgm"))
            Netpbm.save(fn, ac)
            b = Netpbm.load(fn)
            @test b == a8
        end
    end

    @testset "Color ppm" begin
        af = rand(RGB{Float64}, 2, 3)
        for T in (RGB{N0f8}, RGB{N4f12}, RGB{N0f16})
            ac = convert(Array{T}, af)
            fn = File(format"PPMBinary", joinpath(workdir, "3by2.ppm"))
            Netpbm.save(fn, ac)
            b = Netpbm.load(fn)
            @test b == ac
        end
        a8 = convert(Array{RGB{N0f8}}, af)
        for T in (RGB{Float32}, RGB{Float64}, HSV{Float64})
            ac = convert(Array{T}, af)
            fn = File(format"PPMBinary", joinpath(workdir, "3by2.ppm"))
            Netpbm.save(fn, ac)
            b = Netpbm.load(fn)
            @test b == a8
        end
    end

    @testset "Colormap" begin
        datafloat = reshape(linspace(0.5, 1.5, 6), 2, 3)
        dataint = round(UInt8, 254*(datafloat .- 0.5) .+ 1)  # ranges from 1 to 255
        # build our colormap
        b = RGB(0,0,1)
        w = RGB(1,1,1)
        r = RGB(1,0,0)
        cmaprgb = Array(RGB{N0f8}, 255)
        f = linspace(0,1,128)
        cmaprgb[1:128] = [(1-x)*b + x*w for x in f]
        cmaprgb[129:end] = [(1-x)*w + x*r for x in f[2:end]]
        img = IndirectArray(dataint, cmaprgb)
        fn = File(format"PPMBinary", joinpath(workdir,"cmap.ppm"))
        Netpbm.save(fn, img)
        imgr = Netpbm.load(fn)
        @test imgr == img
        cmaprgb = Array(RGB, 255) # poorly-typed cmap, Images issue #336
        @test !isleaftype(eltype(cmaprgb))
        cmaprgb[1:128] = RGB{N0f16}[(1-x)*b + x*w for x in f]
        cmaprgb[129:end] = RGB{N4f12}[(1-x)*w + x*r for x in f[2:end]]
        img = IndirectArray(dataint, cmaprgb)
        @test_throws ErrorException Netpbm.save(fn, img) # widens to unsupported type
        cmaprgb[129:end] = RGB{N0f8}[(1-x)*w + x*r for x in f[2:end]]
        img = IndirectArray(dataint, cmaprgb)
        Netpbm.save(fn, img)
        imgr = Netpbm.load(fn)
        @test imgr == img
    end

    # Images issue #256
    @testset "Clamping" begin
        A = rand(2,3)
        A[1,1] = -0.4
        fn = File(format"PGMBinary", joinpath(workdir, "2by3.pgm"))
        @test_throws InexactError Netpbm.save(fn, A)
        Netpbm.save(fn, A, mapf=clamp01nan)
        B = Netpbm.load(fn)
        A[1,1] = 0
        @test B == Gray{N0f8}.(A)
    end
end

nothing
