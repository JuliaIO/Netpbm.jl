# Netpbm

[![Build Status](https://travis-ci.org/JuliaIO/Netpbm.jl.svg?branch=master)](https://travis-ci.org/JuliaIO/Netpbm.jl)

This package implements the
[FileIO](https://github.com/JuliaIO/FileIO.jl) interface for loading
and saving binary
[Netpbm](https://en.wikipedia.org/wiki/Netpbm_format) images.  Other
packages, such as
[ImageMagick](https://github.com/JuliaIO/ImageMagick.jl), also support
such formats. One advantage of this package is that it does not have
any binary (e.g., external library) dependencies---it is implemented
in pure Julia.
