module lcmtesttypes

export lcm_test_type_1, lcm_test_type_2, lcm_test_type_3, polynomial_t, polynomial_matrix_t
export hard_coded_example

using LCMCore, StaticArrays
using Random: randstring

mutable struct lcm_test_type_1 <: LCMType
    a::Int16
    blength::Int32
    b::Vector{Int64}
    c::SVector{3, Int32}
end

@lcmtypesetup(lcm_test_type_1,
    b => (blength, )
)

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

mutable struct lcm_test_type_2 <: LCMType
    dlength::Int32
    f_inner_length::Int32
    a::Bool
    b::UInt8
    c::lcm_test_type_1
    d::Vector{lcm_test_type_1}
    e::SVector{3, lcm_test_type_1}
    f::Matrix{Int64}
end

@lcmtypesetup(lcm_test_type_2,
    d => (dlength, ),
    f => (3, f_inner_length)
)

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
    f = rand(Int64, 3, f_inner_length)
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
    ret.f = [1 2; 3 4; 5 7]
    ret
end

mutable struct lcm_test_type_3 <: LCMType
    a::String
    blength::Int32
    b::Vector{String}
    c::SVector{2, String}
    d::Float64
end

@lcmtypesetup(lcm_test_type_3,
    b => (blength, )
)

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

mutable struct polynomial_t <: LCMType
    timestamp::Int64
    num_coefficients::Int32
    coefficients::Vector{Float64}
end

@lcmtypesetup(polynomial_t,
    coefficients => (num_coefficients, )
)

function Base.:(==)(x::polynomial_t, y::polynomial_t)
    x.timestamp == y.timestamp || return false
    x.num_coefficients == y.num_coefficients || return false
    x.coefficients == y.coefficients || return false
    true
end

function Base.rand(::Type{polynomial_t})
    timestamp = rand(Int64)
    num_coefficients = rand(Int32(0) : Int32(10))
    coefficients = rand(num_coefficients)
    polynomial_t(timestamp, num_coefficients, coefficients)
end

function hard_coded_example(::Type{polynomial_t})
    polynomial_t(1234, 4, [5.0, 0.0, 1.0, 3.0])
end


mutable struct polynomial_matrix_t <: LCMType
    timestamp::Int64
    rows::Int32
    cols::Int32
    polynomials::Matrix{polynomial_t}
end

@lcmtypesetup(polynomial_matrix_t,
    polynomials => (rows, cols)
)

function Base.:(==)(x::polynomial_matrix_t, y::polynomial_matrix_t)
    x.timestamp == y.timestamp || return false
    x.rows == y.rows || return false
    x.cols == y.cols || return false
    x.polynomials == y.polynomials || return false
    true
end

function Base.rand(::Type{polynomial_matrix_t})
    timestamp = rand(Int64)
    rows = rand(Int32(0) : Int32(10))
    cols = rand(Int32(0) : Int32(10))
    polynomials = [rand(polynomial_t) for row = 1 : rows, col = 1 : cols]
    polynomial_matrix_t(timestamp, rows, cols, polynomials)
end

function hard_coded_example(::Type{polynomial_matrix_t})
    polynomials = Matrix{polynomial_t}(undef, 2, 1)
    polynomials[1] = polynomial_t(1234, 4, [5.0, 0.0, 1.0, 3.0])
    polynomials[2] = polynomial_t(1234, 4, [10.0, 0.0, 2.0, 6.0])
    polynomial_matrix_t(1234, 2, 1, polynomials)
end

end # module
