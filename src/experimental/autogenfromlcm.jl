# functions to auto generate julia ccall interfaces to user defined .lcm types

import Base: convert

abstract type LCMTypeCWrapper end
abstract type LCMTypeJL end

# unidirectional convert function for use with encode function
function convert(CT::Type{<:LCMTypeCWrapper}, msg::T where T <: LCMTypeJL)
  cmsg = CT()
  for el in fieldnames(msg)
    val = getfield(msg, el)
    if isa(val, Array) || isa(val, String)
      setfield!(cmsg, el, pointer(getfield(msg, el)))
    elseif isa(val, Tuple)
      setfield!(cmsg, el, val)
    else
      setfield!(cmsg, el, val)
    end
    # @show el, getfield(cmsg, el)
  end
  return cmsg
end

const LCM2JLTYPES = Dict{Symbol, Symbol}(
  :byte => :UInt8,
  :uint8_t => :UInt8,
  :int8_t => :Int8,
  :int16_t => :Int16,
  :uint16_t => :UInt16,
  :int32_t => :Int32,
  :uint32_t => :UInt32,
  :int64_t => :Int64,
  :uint64_t => :UInt64,
  :string => :String,
  :double => :Float64,
  :float => :Float32,
  :boolean => :Bool,
)


function addvariablearray!(arrlendict, newmember)
  vardef = newmember[2]
  if contains(vardef, "[") && contains(vardef, "]")
    varelems = split(vardef, '[')
    varname = varelems[1]
    arrlen = split(varelems[2],']')[1]
    arrlenrgx = match(r"^[1-9][0-9]*", arrlen)
    if arrlenrgx == nothing
      arrlendict[Symbol(varname)] = Symbol(arrlen)
    end
  end
  nothing
end


# build msg struct from lcm definition

function interpretLCMDefinition(lcmtypefilepath)
  fid = open(lcmtypefilepath, "r")

  package = nothing
  structname = nothing
  structmembers = Vector{Tuple{Symbol, String}}()
  arrlendict = Dict{Symbol, Symbol}()

  insidedef = false
  for ln in readlines(fid)
    if contains(ln, "package")
      packagen = split(ln, "package ")[end]
      package = packagen[end] == ';' ? Symbol(packagen[1:(end-1)]) : Symbol(packagen)
    elseif contains(ln, "struct")
      structn = split(ln, "struct ")[end]
      structname = structn[end] == ';' ? Symbol(structn[1:(end-1)]) : Symbol(structn)
    elseif contains(ln, "{")
      insidedef = true
    elseif contains(ln, "}")
      insidedef = false
    elseif insidedef && contains(ln, ";")
      mems = split(strip(ln), ";")[1]
      memss = split(mems, ' ')
      idx = -1
      while idx != 0
        idx = findfirst(memss, "")
        idx > 0 ? deleteat!(memss, idx) : nothing
      end
      newmember = (Symbol(memss[1]), memss[2])
      push!(structmembers ,newmember)
      # check if variable length array
      addvariablearray!(arrlendict, newmember)
    else
      # not necessarily an error
    end
  end
  close(fid)

  return package, structname, structmembers, arrlendict
end


# build new julia and c compatible types

# LCM to julia type equivalence

function createLCMTypePath(lcmtypefilepath, package, structname, lcm2jldir)
  # create the auto generated file in a standard destination
  # temppath = lcmtypefilepath[1:findlast(lcmtypefilepath, '/')]
  # lcm2jldir = joinpath(destination,string(package))
  if !isdir(lcm2jldir)
    mkdir(lcm2jldir)
  end
  joinpath(lcm2jldir, "$(structname).jl")
end

function getLCMStructName(structname; language=:jl)
  structtypet = lowercase(string(structname))
  structtypename = language == :jl ? uppercase(structtypet[1]) : structtypet[1]
  structtypename*structtypet[2:end]
end

function printLCMType(fid, package, structname, structmembers; language=:c, lcm2jltypes=LCM2JLTYPES )
  structtype = getLCMStructName(structname; language=language)
  if language == :c
    println(fid, "mutable struct $(structtype) <: LCMTypeCWrapper")
  else
    println(fid, "mutable struct $(structtype) <: LCMTypeJL")
  end

  arrlen = 0
  hasarrays = Dict{Symbol, Symbol}()
  for el in structmembers
    if !contains(el[2], "[")
      datatype = string(lcm2jltypes[el[1]])
      datatype = language==:c && datatype=="String" ? "Ptr{UInt8}" : datatype
      println(fid, "  $(el[2])::$(datatype)")
    elseif contains(el[2], "const ")
      error("printLCMType cannot convert const types yet.")
    elseif contains(el[2], "[") && contains(el[2], "]")
      varelems = split(el[2], '[')
      varname = varelems[1]
      arrlen = split(varelems[2],']')[1]
      arrlenrgx = match(r"^[1-9][0-9]*", arrlen)
      if arrlenrgx != nothing
        arrlen = parse(Int, arrlenrgx.match)
        println(fid, "  $(varname)::NTuple{$(arrlen),$(lcm2jltypes[el[1]])}")
      else
        arrtype = language == :c ? "Ptr{$(lcm2jltypes[el[1]])}" : "Array{$(lcm2jltypes[el[1]]),1}"
        println(fid, "  $(varname)::$(arrtype)")
      end
    else
      error("lcm-gen-jl not sure how to convert $(package).$(structname), elements $(el)")
    end
  end

  # close out struct definition
  println(fid, "  $(structtype)() = new()")
  println(fid, "end")
  nothing
end



function printLCMDecodeFunction(fid, package, structname, structmembers, arrlendict, libraryname; lcm2jltypes=LCM2JLTYPES)

  jlstructname = getLCMStructName(structname, language=:jl)
  cstructname = getLCMStructName(structname, language=:c)

  println(fid, "function decode(data::Vector{UInt8}, ::Type{$(jlstructname)})::$(jlstructname)")
  # should be taken from LCMCore.RecvBuf.datalen directly -- important for nested types
  println(fid, "  len = length(data)")
  println(fid, "  ptr = pointer(data)")
  println(fid, "  msgt = $(cstructname)()")
  println(fid, "  ")
  println(fid, "  msgptr = pointer_from_objref(msgt)")
  println(fid, "  retval = ccall(")
  println(fid, "    (:$(package)_$(cstructname)_decode, :$(libraryname)),")
  println(fid, "    Int32,")
  println(fid, "    (Ptr{Void}, Int32, Int32, Ptr{example_t}),")
  println(fid, "    ptr, 0, len, msgptr")
  println(fid, "  )")
  println(fid, "  ")
  println(fid, "  msgr = unsafe_pointer_to_objref(msgptr)")
  println(fid, "  ")
  println(fid, "  msg = $(jlstructname)()")
  println(fid, "  ")

  # insert automated c to jl struct memory pointing here

  for el in structmembers
     if !contains(el[2], "[")
       if el[1] == :string
         println(fid, "  msg.$(el[2]) = unsafe_string(msgr.$(el[2]))")
       else
         println(fid, "  msg.$(el[2]) = msgr.$(el[2])")
       end
     elseif contains(el[2], "const ")
       error("printLCMDecodeFunction cannot convert const types yet.")
     elseif contains(el[2], "[") && contains(el[2], "]")
       varelems = split(el[2], '[')
       varname = varelems[1]
       arrlen = split(varelems[2],']')[1]
       arrlenrgx = match(r"^[1-9][0-9]*", arrlen)
       if arrlenrgx != nothing
         println(fid, "  msg.$(varname) = msgr.$(varname)")
       else
         println(fid, "  msg.$(varname) = unsafe_wrap(Array{$(lcm2jltypes[el[1]]),1}, msgr.$(varname), msgr.$(arrlendict[Symbol(varname)])) ")
       end
     else
       error("lcm-gen-jl not sure how to equate $(package).$(structname), elements $(el) for decode function.")
     end
  end

  println(fid, "  ")
  println(fid, "  return msg")
  println(fid, "end")

  nothing
end


function printLCMEncodeFunction(fid, package, structname, structmembers, libraryname; lcm2jltypes=LCM2JLTYPES)

  jlstructname = getLCMStructName(structname, language=:jl)
  cstructname = getLCMStructName(structname, language=:c)

  println(fid, "")
  println(fid, "function encode(msg::$(jlstructname))::Vector{UInt8}")
  println(fid, "  cmsg = convert($(cstructname), msg)")
  println(fid, "  cmsgptr = pointer_from_objref(cmsg)")
  println(fid, "  datasize = ccall(")
  println(fid, "    (:$(package)_$(cstructname)_encoded_size, :$(libraryname)),")
  println(fid, "    Int32,")
  println(fid, "    (Ptr{example_t},),")
  println(fid, "    cmsgptr")
  println(fid, "  )")
  println(fid, "  data = zeros(UInt8, datasize)")
  println(fid, "  dataptr = pointer(data)")
  println(fid, "  ccall(")
  println(fid, "    (:$(package)_$(cstructname)_encode, :$(libraryname)),")
  println(fid, "    Int32,")
  println(fid, "    (Ptr{UInt8}, Int32, Int32, Ptr{example_t}),")
  println(fid, "    dataptr, 0, datasize, cmsgptr")
  println(fid, "  )")
  println(fid, "  ")
  println(fid, "  return data")
  println(fid, "end")
  nothing
end



function generateLCMjl(lcmtypefilepath, package, structname, structmembers, arrlendict, destination)
  # package, structname, structmembers, arrlendict = interpretLCMDefinition(lcmtypefilepath)
  lcm2jlfile = createLCMTypePath(lcmtypefilepath, package, structname, destination)

  lcm2jlfid = open(lcm2jlfile, "w")

  println(lcm2jlfid, "# autogenerated file for make LCM types available in Julia.")
  println(lcm2jlfid, "import LCMCore: decode, encode")
  println(lcm2jlfid, "")

  printLCMType(lcm2jlfid, package, structname, structmembers, language=:jl, lcm2jltypes=LCM2JLTYPES )
  printLCMType(lcm2jlfid, package, structname, structmembers, language=:c, lcm2jltypes=LCM2JLTYPES )

  println(lcm2jlfid, "")
  println(lcm2jlfid, "push!(Libdl.DL_LOAD_PATH, \"$(destination)\")")
  println(lcm2jlfid, "")

  printLCMDecodeFunction(lcm2jlfid, package, structname, structmembers, arrlendict, :libexlcm, lcm2jltypes=LCM2JLTYPES)
  printLCMEncodeFunction(lcm2jlfid, package, structname, structmembers, :libexlcm; lcm2jltypes=LCM2JLTYPES)

  close(lcm2jlfid)

  return lcm2jlfile
end

function findlcmgen()
  lcmcoredir = Pkg.dir("LCMCore")
  lcmdir = joinpath(lcmcoredir, "deps", "builds", "lcm", "lcmgen", "lcm-gen")
end

function genLcmtypeSpecificCmake(package; destination=nothing)
  libraryname = string("lib", package)
  projsrcdir = destination != nothing ? destination : joinpath(Pkg.dir("LCMCore"),"deps","builds", package)
  cmakefile = joinpath(projsrcdir, "CMakeLists.txt")
  fid = open(cmakefile, "w")

  println(fid, "cmake_minimum_required(VERSION 3.0)")
  println(fid, "")
  println(fid, "project($(package))")
  println(fid, "include_directories($(projsrcdir))")
  println(fid, "file(GLOB SRC_FILES $(projsrcdir)/$(package)_*.c)")
  println(fid, "add_library($(package) SHARED")
  println(fid, "  \${SRC_FILES}")
  println(fid, ")")
  println(fid, "")
  println(fid, "set_property(TARGET $(package) PROPERTY POSITION_INDEPENDENT_CODE ON)")
  println(fid, "add_definitions(-shared)")

  close(fid)
  return libraryname, cmakefile
end

function lcmGenRunCmakeCompile(destination)
  # TODO -- CMakeWrapper.jl or BinDeps might be getter suited for operations performed in this function
  run(`cmake -B$(destination) -H$(destination)`)
  run(`make -C $(destination) clean all`)
end
## CMakeWrapper.jl
# CMakeBuild(srcdir=source_dir,  # where the CMakeLists.txt resides in your source
#            builddir=build_dir,  # where the cmake build outputs should go
#            prefix=install_prefix,  # desired install prefix
#            libtarget=[library_name],  # name of the library being built
#            installed_libpath=[path_to_intalled_library],  # expected installed library path
#            cmake_args=[],  # additional cmake arguments
#            targetname="install")  # build target to run (default: "install")


function lcmgenjl(lcmtypefilepath::S where S <: AbstractString; destination=nothing)
  # parse the .lcm file definition
  package, structname, structmembers, arrlendict = interpretLCMDefinition(lcmtypefilepath)

  # create the generated code folder
  destination = destination != nothing ? destination : joinpath(Pkg.dir("LCMCore"),"deps","builds", string(package))
  if !isdir(destination)
    mkdir(destination)
  end

  # generate the required c code
  lcm_gen = findlcmgen()
  run(`$(lcm_gen) -c --c-cpath $(destination) --c-hpath $(destination) $(lcmtypefilepath)`)

  # generate the required cmake file
  genLcmtypeSpecificCmake(package; destination=destination)

  # compile the required .so for the newly generated lcm c code
  lcmGenRunCmakeCompile(destination)

  # generate the required julia code
  lcmgenjlfile = generateLCMjl(lcmtypefilepath, package, structname, structmembers, arrlendict, destination)
  return lcmgenjlfile, destination
end







#
