using Netpbm, Images, ColorTypes, FixedPointNumbers, FileIO
using FactCheck

facts("IO") do
    workdir = joinpath(tempdir(), "Images")
    isdir(workdir) && rm(workdir, recursive=true)
    mkdir(workdir)

    context("Gray pgm") do
        a = rand(2,3)
        aa = convert(Array{Ufixed8}, a)
        fn = File(format"PGMBinary", joinpath(workdir, "3by2.pgm"))
        save(fn, a)
        b = load(fn)
        @fact convert(Array, b) --> aa
        save(fn, aa)
        b = load(fn)
        @fact convert(Array, b) --> aa
        aaimg = Images.grayim(aa')
        b = load(fn)
        @fact b --> aaimg
        aa = convert(Array{Ufixed16}, a)
        save(fn, aa)
        b = load(fn)
        @fact convert(Array, b) --> aa
    end

    context("Color ppm") do
        fn = File(format"PPMBinary", joinpath(workdir, "3by2.ppm"))
        img = Images.colorim(rand(3,3,2))
        img24 = convert(Images.Image{RGB24}, img)
        save(fn, img24)
        b = load(fn)
        imgrgb8 = convert(Images.Image{RGB{Ufixed8}}, img)
        @fact Images.data(imgrgb8) --> Images.data(b)

        bb = load(fn)
        @fact data(bb) --> data(imgrgb8)
    end

    context("Colormap usage") do
        datafloat = reshape(linspace(0.5, 1.5, 6), 2, 3)
        dataint = round(UInt8, 254*(datafloat .- 0.5) .+ 1)  # ranges from 1 to 255
        # build our colormap
        b = RGB(0,0,1)
        w = RGB(1,1,1)
        r = RGB(1,0,0)
        cmaprgb = Array(RGB{U8}, 255)
        f = linspace(0,1,128)
        cmaprgb[1:128] = [(1-x)*b + x*w for x in f]
        cmaprgb[129:end] = [(1-x)*w + x*r for x in f[2:end]]
        img = Images.ImageCmap(dataint, cmaprgb)
        save(File(format"PPMBinary", joinpath(workdir,"cmap.ppm")), img)
        cmaprgb = Array(RGB, 255) # poorly-typed cmap, issue #336
        cmaprgb[1:128] = [(1-x)*b + x*w for x in f]
        cmaprgb[129:end] = [(1-x)*w + x*r for x in f[2:end]]
        img = Images.ImageCmap(dataint, cmaprgb)
        save(File(format"PPMBinary", joinpath(workdir, "cmap.ppm")), img)
    end

    context("Clamping (Images issue #256)") do
        A = grayim(rand(2,3))
        A[1,1] = -0.4
        fn = File(format"PGMBinary", joinpath(workdir, "2by3.pgm"))
        @fact_throws InexactError save(fn, A)
        save(fn, A, mapi=mapinfo(Clamp, A))
        B = load(fn)
        A[1,1] = 0
        @fact B --> map(Gray{Ufixed8}, A)
    end
end
FactCheck.exitstatus()
