module lcmtesttypes

export lcm_test_type_1, lcm_test_type_2, lcm_test_type_3
export hard_coded_example

using LCMCore, StaticArrays

mutable struct lcm_test_type_1 <: LCMType
    a::Int16
    blength::Int32
    b::Vector{Int64}
    c::SVector{3, Int32}
end

function LCMCore.dimensions(::Type{lcm_test_type_1}, field::Symbol)
    if field == :b
        [LCMDimension(LCMCore.LCM_VAR, :blength)]
    elseif field == :c
        [LCMDimension(LCMCore.LCM_CONST, 3)]
    else
        LCMDimension[]
    end
end

function Base.:(==)(x::lcm_test_type_1, y::lcm_test_type_1)
    x.a == y.a || return false
    x.blength == y.blength || return false
    x.b == y.b || return false
    x.c == y.c || return false
    true
end

function Base.rand(::Type{lcm_test_type_1})
    blength = rand(Int32(0) : Int32(10))
    lcm_test_type_1(rand(Int16), blength, rand(Int64, blength), rand(SVector{3, Int32}))
end

function hard_coded_example(::Type{lcm_test_type_1})
    ret = lcm_test_type_1()
    ret.a = 1
    ret.blength = 4
    ret.b = [4, 5, -6, 7]
    ret.c = [10, -1, 5]
    ret
end

# TODO: remove:
LCMCore.fingerprint(::Type{lcm_test_type_1}) = SVector(0xd5, 0x93, 0x03, 0xf7, 0x23, 0x48, 0xdb, 0x16)
LCMCore.size_fields(::Type{lcm_test_type_1}) = (:blength,)
LCMCore.check_valid(x::lcm_test_type_1) = @assert length(x.b) == x.blength
Base.resize!(x::lcm_test_type_1) = resize!(x.b, x.blength)

mutable struct lcm_test_type_2 <: LCMType
    dlength::Int32
    f_inner_length::Int32
    a::Bool
    b::UInt8
    c::lcm_test_type_1
    d::Vector{lcm_test_type_1}
    e::SVector{3, lcm_test_type_1}
    f::SVector{3, Vector{Int64}}
end

function LCMCore.dimensions(::Type{lcm_test_type_2}, field::Symbol)
    if field == :d
        [LCMDimension(LCMCore.LCM_VAR, :dlength)]
    elseif field == :e
        [LCMDimension(LCMCore.LCM_CONST, 3)]
    elseif field == :f
        [LCMDimension(LCMCore.LCM_CONST, 3), LCMDimension(LCMCore.LCM_VAR, :f_inner_length)]
    else
        LCMDimension[]
    end
end


function Base.:(==)(x::lcm_test_type_2, y::lcm_test_type_2)
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

function Base.rand(::Type{lcm_test_type_2})
    dlength = rand(Int32(0) : Int32(10))
    f_inner_length = rand(Int32(0) : Int32(10))
    a = rand(Bool)
    b = rand(UInt8)
    c = rand(lcm_test_type_1)
    d = [rand(lcm_test_type_1) for i = 1 : dlength]
    e = SVector{3}([rand(lcm_test_type_1) for i = 1 : 3])
    f = SVector{3}([rand(Int64, f_inner_length) for i = 1 : 3])
    lcm_test_type_2(dlength, f_inner_length, a, b, c, d, e, f)
end

function hard_coded_example(::Type{lcm_test_type_2})
    ret = lcm_test_type_2()
    ret.dlength = 2
    ret.f_inner_length = 2
    ret.a = false
    ret.b = 6
    ret.c = hard_coded_example(lcm_test_type_1)
    ret.d = [hard_coded_example(lcm_test_type_1), hard_coded_example(lcm_test_type_1)]
    ret.d[1].a = 2
    ret.e = [hard_coded_example(lcm_test_type_1), hard_coded_example(lcm_test_type_1), hard_coded_example(lcm_test_type_1)]
    ret.e[3].c = [5, 3, 8]
    ret.f = [[1, 2], [3, 4], [5, 7]]
    ret
end

# TODO: remove
LCMCore.fingerprint(::Type{lcm_test_type_2}) = SVector(0xb6, 0x19, 0xed, 0x8b, 0x08, 0x60, 0xcc, 0x1b)
LCMCore.size_fields(::Type{lcm_test_type_2}) = (:dlength, :f_inner_length)
function LCMCore.check_valid(x::lcm_test_type_2)
    @assert length(x.d) == x.dlength
    for element in x.f
        @assert length(element) == x.f_inner_length
    end
end
function Base.resize!(x::lcm_test_type_2)
    resize!(x.d, x.dlength)
    for element in x.f
        resize!(element, x.f_inner_length)
    end
end

mutable struct lcm_test_type_3 <: LCMType
    a::String
    blength::Int32
    b::Vector{String}
    c::SVector{2, String}
    d::Float64
end

function LCMCore.dimensions(::Type{lcm_test_type_3}, field::Symbol)
    if field == :b
        [LCMDimension(LCMCore.LCM_VAR, :blength)]
    elseif field == :c
        [LCMDimension(LCMCore.LCM_CONST, 2)]
    else
        LCMDimension[]
    end
end

function Base.:(==)(x::lcm_test_type_3, y::lcm_test_type_3)
    x.a == y.a || return false
    x.blength == y.blength || return false
    x.b == y.b || return false
    x.c == y.c || return false
    x.d == y.d || return false
    true
end

function Base.rand(::Type{lcm_test_type_3})
    a = randstring()
    blength = rand(Int32(0) : Int32(10))
    b = [randstring() for i = 1 : blength]
    c = SVector{2}([randstring() for i = 1 : 2])
    d = rand()
    lcm_test_type_3(a, blength, b, c, d)
end

function hard_coded_example(::Type{lcm_test_type_3})
    ret = lcm_test_type_3()
    ret.a = "abcd"
    ret.blength = 3
    ret.b = ["x*4f", "4^G32", "4"]
    ret.c = ["xyz", "wxy"]
    ret.d = 2.5
    ret
end

# TODO: remove:
LCMCore.fingerprint(::Type{lcm_test_type_3}) = SVector(0x72, 0x99, 0xcb, 0xe1, 0xc8, 0x03, 0x86, 0x4a)
LCMCore.size_fields(::Type{lcm_test_type_3}) = (:blength,)
LCMCore.check_valid(x::lcm_test_type_3) = @assert length(x.b) == x.blength
Base.resize!(x::lcm_test_type_3) = resize!(x.b, x.blength)

end # module
