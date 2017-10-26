using LCMCore
using Base.Test
using StaticArrays
using BufferedStreams

module LCMTestTypes

export LCMTestType1, LCMTestType2, LCMTestType3
export hard_coded_example

using LCMCore, StaticArrays

mutable struct LCMTestType1 <: LCMType
    a::Int16
    blength::Int32
    b::Vector{Int64}
    c::SVector{3, Int32}
end

function Base.:(==)(x::LCMTestType1, y::LCMTestType1)
    x.a == y.a || return false
    x.blength == y.blength || return false
    x.b == y.b || return false
    x.c == y.c || return false
    true
end

function Base.rand(::Type{LCMTestType1})
    blength = rand(Int32(0) : Int32(10))
    LCMTestType1(rand(Int16), blength, rand(Int64, blength), rand(SVector{3, Int32}))
end

function hard_coded_example(::Type{LCMTestType1})
    ret = LCMTestType1()
    ret.a = 1
    ret.blength = 4
    ret.b = [4, 5, -6, 7]
    ret.c = [10, -1, 5]
    ret
end

LCMCore.fingerprint(::Type{LCMTestType1}) = SVector(0xd5, 0x93, 0x03, 0xf7, 0x23, 0x48, 0xdb, 0x16)
LCMCore.size_fields(::Type{LCMTestType1}) = (:blength,)
LCMCore.check_valid(x::LCMTestType1) = @assert length(x.b) == x.blength
Base.resize!(x::LCMTestType1) = resize!(x.b, x.blength)

mutable struct LCMTestType2 <: LCMType
    dlength::Int32
    f_inner_length::Int32
    a::Bool
    b::UInt8
    c::LCMTestType1
    d::Vector{LCMTestType1}
    e::SVector{3, LCMTestType1}
    f::SVector{3, Vector{Int64}}
end

function Base.:(==)(x::LCMTestType2, y::LCMTestType2)
    x.dlength == y.dlength || return false
    x.f_inner_length == y.f_inner_length || return false
    x.a == y.a || return false
    x.b == y.b || return false
    x.c == y.c || return false
    x.d == y.d || return false
    x.e == y.e || return false
    x.f == y.f || return false
    true
end

function Base.rand(::Type{LCMTestType2})
    dlength = rand(Int32(0) : Int32(10))
    f_inner_length = rand(Int32(0) : Int32(10))
    a = rand(Bool)
    b = rand(UInt8)
    c = rand(LCMTestType1)
    d = [rand(LCMTestType1) for i = 1 : dlength]
    e = SVector{3}([rand(LCMTestType1) for i = 1 : 3])
    f = SVector{3}([rand(Int64, f_inner_length) for i = 1 : 3])
    LCMTestType2(dlength, f_inner_length, a, b, c, d, e, f)
end

function hard_coded_example(::Type{LCMTestType2})
    ret = LCMTestType2()
    ret.dlength = 2
    ret.f_inner_length = 2
    ret.a = false
    ret.b = 6
    ret.c = hard_coded_example(LCMTestType1)
    ret.d = [hard_coded_example(LCMTestType1), hard_coded_example(LCMTestType1)]
    ret.d[1].a = 2
    ret.e = [hard_coded_example(LCMTestType1), hard_coded_example(LCMTestType1), hard_coded_example(LCMTestType1)]
    ret.e[3].c = [5, 3, 8]
    ret.f = [[1, 2], [3, 4], [5, 7]]
    ret
end

LCMCore.fingerprint(::Type{LCMTestType2}) = SVector(0xb6, 0x19, 0xed, 0x8b, 0x08, 0x60, 0xcc, 0x1b)
LCMCore.size_fields(::Type{LCMTestType2}) = (:dlength, :f_inner_length)
function LCMCore.check_valid(x::LCMTestType2)
    @assert length(x.d) == x.dlength
    for element in x.f
        @assert length(element) == x.f_inner_length
    end
end
function Base.resize!(x::LCMTestType2)
    resize!(x.d, x.dlength)
    for element in x.f
        resize!(element, x.f_inner_length)
    end
end

mutable struct LCMTestType3 <: LCMType
    a::String
    blength::Int32
    b::Vector{String}
    c::SVector{2, String}
    d::Float64
end

function Base.:(==)(x::LCMTestType3, y::LCMTestType3)
    x.a == y.a || return false
    x.blength == y.blength || return false
    x.b == y.b || return false
    x.c == y.c || return false
    x.d == y.d || return false
    true
end

function Base.rand(::Type{LCMTestType3})
    a = randstring()
    blength = rand(Int32(0) : Int32(10))
    b = [randstring() for i = 1 : blength]
    c = SVector{2}([randstring() for i = 1 : 2])
    d = rand()
    LCMTestType3(a, blength, b, c, d)
end

function hard_coded_example(::Type{LCMTestType3})
    ret = LCMTestType3()
    ret.a = "abcd"
    ret.blength = 3
    ret.b = ["x*4f", "4^G32", "4"]
    ret.c = ["xyz", "wxy"]
    ret.d = 2.5
    ret
end

LCMCore.fingerprint(::Type{LCMTestType3}) = SVector(0x72, 0x99, 0xcb, 0xe1, 0xc8, 0x03, 0x86, 0x4a)
LCMCore.size_fields(::Type{LCMTestType3}) = (:blength,)
LCMCore.check_valid(x::LCMTestType3) = @assert length(x.b) == x.blength
Base.resize!(x::LCMTestType3) = resize!(x.b, x.blength)

end # module

function test_encode_decode(::Type{T}) where T<:LCMType
    for i = 1 : 100
        in = rand(T)
        bytes = encode(in)::Vector{UInt8}
        out = decode(bytes, T)
        @test in == out
    end
end

function test_decode!_allocations(::Type{T}) where T<:LCMType
    in = rand(T)
    bytes = encode(in)
    out = deepcopy(in)
    decodestream = BufferedInputStream(bytes)
    decode!(out, decodestream)
    decodestream = BufferedInputStream(bytes)
    allocs = @allocated decode!(out, decodestream)
    @test allocs == 0
end

@testset "LCMType" begin
    using LCMTestTypes
    srand(1)

    # Check invertibility
    test_encode_decode(LCMTestType1)
    test_encode_decode(LCMTestType2)
    test_encode_decode(LCMTestType3)

    # Check that decoding types without `String`s doesn't allocate
    test_decode!_allocations(LCMTestType1)
    test_decode!_allocations(LCMTestType2)

    # Mismatch between length field and length of corresponding vector
    bad = rand(LCMTestType1)
    bad.blength += 1
    @test_throws AssertionError encode(bad)

    # Bad fingerprint
    in = rand(LCMTestType1)
    badbytes = encode(in)
    badbytes[1] += 0x01
    @test_throws LCMCore.FingerprintException decode(badbytes, LCMTestType1)

    # Test against byte blobs that were encoded using pylcm
    bytes = read(Pkg.dir("LCMCore", "test", "lcmtypes", "lcm_test_type_1_example_bytes"))
    @test hard_coded_example(LCMTestType1) == decode(bytes, LCMTestType1)
    bytes = read(Pkg.dir("LCMCore", "test", "lcmtypes", "lcm_test_type_2_example_bytes")) # encoded using pylcm
    @test hard_coded_example(LCMTestType2) == decode(bytes, LCMTestType2)
    bytes = read(Pkg.dir("LCMCore", "test", "lcmtypes", "lcm_test_type_3_example_bytes")) # encoded using pylcm
    @test hard_coded_example(LCMTestType3) == decode(bytes, LCMTestType3)
end
