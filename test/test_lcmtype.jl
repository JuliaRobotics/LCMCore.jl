using LCMCore
using Base.Test
using StaticArrays
using BufferedStreams

module LCMTestTypes

export LCMTestType1, LCMTestType2, LCMTestType3

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

LCMCore.fingerprint(::Type{LCMTestType1}) = SVector(0x36, 0x62, 0xf8, 0xc2, 0x35, 0x8e, 0x35, 0x12) # note: not the correct LCM fingerprint!
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

LCMCore.fingerprint(::Type{LCMTestType2}) = SVector(0x26, 0x62, 0xf8, 0xc2, 0x35, 0x8f, 0x35, 0x02) # note: not the correct LCM fingerprint!
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

LCMCore.fingerprint(::Type{LCMTestType3}) = SVector(0x26, 0x62, 0xff, 0xc2, 0x31, 0x8f, 0x32, 0x02) # note: not the correct LCM fingerprint!
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

    test_encode_decode(LCMTestType1)
    test_decode!_allocations(LCMTestType1)

    test_encode_decode(LCMTestType2)
    test_decode!_allocations(LCMTestType2)

    test_encode_decode(LCMTestType3)

    # Mismatch between length field and length of corresponding vector
    bad = rand(LCMTestType1)
    bad.blength += 1
    @test_throws AssertionError encode(bad)

    # Bad fingerprint
    in = rand(LCMTestType1)
    badbytes = encode(in)
    badbytes[1] += 0x01
    @test_throws LCMCore.FingerprintException decode(badbytes, LCMTestType1)
end
