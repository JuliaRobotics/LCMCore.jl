append!(empty!(LOAD_PATH), Base.DEFAULT_LOAD_PATH)
using Pkg

Pkg.activate(@__DIR__)
Pkg.instantiate()

using BinDeps
using CMakeWrapper

@BinDeps.setup

function cflags_validator(pkg_names...)
    return (name, handle) -> begin
        for pkg_name in pkg_names
            try
                run(`pkg-config --cflags $(pkg_name)`)
                return true
            catch ErrorException
            end
        end
        false
    end
end

# Explicitly disallow global LCM installations
validate_lcm(name, handle) = occursin(dirname(@__FILE__), name)

@static if Sys.islinux()
    glib = library_dependency("glib", aliases=["libglib-2.0-0", "libglib-2.0", "libglib-2.0.so.0"], validate=cflags_validator("glib-2.0"))
    lcm = library_dependency("lcm", aliases=["liblcm", "liblcm.1"], depends=[glib],
                             validate=validate_lcm)

    provides(AptGet, Dict("libglib2.0-dev" => glib))
else
    glib = library_dependency("glib", aliases = ["libglib-2.0-0", "libglib-2.0", "libglib-2.0.so.0"])
    lcm = library_dependency("lcm", aliases=["liblcm", "liblcm.1"], depends=[glib],
                             validate=validate_lcm)
end

prefix = joinpath(BinDeps.depsdir(lcm), "usr")

lcm_cmake_arguments = [
    "-DCMAKE_BUILD_TYPE=Release",
    "-DLCM_ENABLE_TESTS:BOOL=OFF",
    "-DLCM_ENABLE_EXAMPLES:BOOL=OFF",
    "-DLCM_ENABLE_JAVA:BOOL=OFF",
    "-DLCM_ENABLE_LUA:BOOL=OFF"
]

@static if Sys.isapple()
    using Homebrew
    provides(Homebrew.HB, "glib", glib, os=:Darwin)
    push!(lcm_cmake_arguments,
        "-DCMAKE_LIBRARY_PATH=$(joinpath(dirname(pathof(Homebrew)), "..", "deps", "usr", "lib"))",
        "-DCMAKE_INCLUDE_PATH=$(joinpath(dirname(pathof(Homebrew)), "..", "deps", "usr", "include"))")
end

provides(Yum,
    Dict("glib" => glib))

lcm_sha = "0e6472188332bf5683d1ccdd29ba6855ac3cd593"
lcm_folder = "lcm-$(lcm_sha)"

provides(Sources,
    URI("https://github.com/lcm-proj/lcm/archive/$(lcm_sha).zip"),
    lcm,
    unpacked_dir=lcm_folder)

provides(BuildProcess, CMakeProcess(cmake_args=lcm_cmake_arguments),
         lcm,
         onload="""
const lcm_prefix = "$prefix"
""")

@BinDeps.install Dict(:lcm => :liblcm)
