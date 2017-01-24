using BinDeps

@BinDeps.setup

function cflags_validator(pkg_name)
    return (name, handle) -> begin
        try
            run(`pkg-config --cflags $(pkg_name)`)
            return true
        catch ErrorException
            return false
        end
    end
end

@static if is_linux()
    deps = [
        python = library_dependency("python", aliases=["libpython2.7.so", "libpython3.2.so", "libpython3.3.so", "libpython3.4.so", "libpython3.5.so", "libpython3.6.so", "libpython3.7.so"], validate=cflags_validator("python"))
        glib = library_dependency("glib", aliases=["libglib-2.0-0", "libglib-2.0", "libglib-2.0.so.0"], depends=[python], validate=cflags_validator("glib-2.0"))
        lcm = library_dependency("lcm", aliases=["liblcm", "liblcm.1"], depends=[glib])

        provides(AptGet, Dict("python-dev" => python, "libglib2.0-dev" => glib))
    ]
else
    deps = [
        glib = library_dependency("glib", aliases = ["libglib-2.0-0", "libglib-2.0", "libglib-2.0.so.0"])
        lcm = library_dependency("lcm", aliases=["liblcm", "liblcm.1"], depends=[glib])
    ]
end

prefix = joinpath(BinDeps.depsdir(lcm), "usr")

lcm_cmake_arguments = String[]
@static if is_apple()
    if Pkg.installed("Homebrew") === nothing
        error("Homebrew package not installed, please run Pkg.add(\"Homebrew\")")
    end
    using Homebrew
    provides(Homebrew.HB, "glib", glib, os=:Darwin)
    push!(lcm_cmake_arguments,
        "-DCMAKE_LIBRARY_PATH=$(joinpath(Pkg.dir("Homebrew"), "deps", "usr", "lib"))")
    push!(lcm_cmake_arguments,
        "-DCMAKE_INCLUDE_PATH=$(joinpath(Pkg.dir("Homebrew"), "deps", "usr", "include"))")

end

provides(Yum,
    Dict("glib" => glib))

lcm_sha = "9e53469cd0713ca8fbf37a968f6fd314f5f11584"
lcm_folder = "lcm-$(lcm_sha)"

provides(Sources,
    URI("https://github.com/lcm-proj/lcm/archive/$(lcm_sha).zip"),
    lcm,
    unpacked_dir=lcm_folder)

lcm_builddir = joinpath(BinDeps.depsdir(lcm), "builds", "lcm")
lcm_srcdir = joinpath(BinDeps.depsdir(lcm), "src", lcm_folder)
lcm_cmake_command = `cmake -DCMAKE_INSTALL_PREFIX=$(prefix)`
for arg in lcm_cmake_arguments
    lcm_cmake_command = `$lcm_cmake_command $arg`
end
lcm_cmake_command = `$lcm_cmake_command $lcm_srcdir`

provides(BuildProcess,
    (@build_steps begin
        GetSources(lcm)
        CreateDirectory(lcm_builddir)
        @build_steps begin
            ChangeDirectory(lcm_builddir)
            lcm_cmake_command
            `cmake --build . --target install`
        end
    end),
    lcm,
    onload="""
const lcm_prefix = "$prefix"
""")

@BinDeps.install Dict(:lcm => :liblcm)
