"""
    LCMType

Supertype of concrete Julia `struct`s that represent LCM message types.

Subtypes must be `mutable struct`s and may use the following field types:

* `Bool`
* numeric types: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`
* bytes (encoded in the same was as `Int8`): `UInt8`;
* `String`;
* another `LCMType`;
* `Vector` or a subtype of `StaticVector`, for which the element type must also be
one of the previously specified types or another `Vector` or `StaticVector`.

Any size fields must come **before** the `Vector` fields to which they correspond.

The following methods must be defined for a concrete subtype of `LCMType` (say `MyType`):

* `dimensions(x::MyType, ::Val{fieldsym})`
* `sizefields(::Type{MyType})`
* `fingerprint(::Type{MyType})`

Note that the `@lcmtypesetup` macro can be used to generate these methods automatically.

Also note that ideally, all of these methods would be generated from the LCM message type
definition, but that is currently not the case.
"""
abstract type LCMType end

"""
    dimensions(x::LCMType, ::Val{fieldsym})

Return a tuple of LCMDimensions describing the size of `getfield(x, fieldsym)`.
"""
function dimensions end

"""
    sizefields(x::Type{T}) where T<:LCMType

Returns a tuple of `Symbol`s corresponding to the fields of `T` that represent vector dimensions.
"""
function sizefields end

"""
    fingerprint(::Type{T}) where T<:LCMType

Return the fingerprint of LCM type `T` as an `SVector{8, UInt8}`.
"""
function fingerprint end

# Types that are encoded in network byte order, as dictated by the LCM type specification.
const NetworkByteOrderEncoded = Union{Int8, Int16, Int32, Int64, Float32, Float64, UInt8}

# Julia types that correspond to LCM primitive types
const LCMPrimitive = Union{Int8, Int16, Int32, Int64, Float32, Float64, String, Bool, UInt8}

# Default values for all of the possible field types of an LCM type:
defaultval(::Type{Bool}) = false
defaultval(::Type{T}) where {T<:NetworkByteOrderEncoded} = zero(T)
defaultval(::Type{String}) = ""
defaultval(::Type{T}) where {T<:Vector} = T()
defaultval(::Type{SV}) where {N, T, SV<:StaticVector{N, T}} = SV(ntuple(i -> defaultval(T), Val(N)))
defaultval(::Type{T}) where {T<:LCMType} = T()

# Generated default constructor for LCMType subtypes
@generated function (::Type{T})() where T<:LCMType
    constructor_arg_exprs = [:(defaultval(fieldtype(T, $i))) for i = 1 : fieldcount(T)]
    :(T($(constructor_arg_exprs...)))
end

# Field dimension information
@enum DimensionMode LCM_CONST LCM_VAR
struct LCMDimension{S <: Union{Symbol, Int}}
    size::S # either a field name, or the size of a statically-sized field
end
dimensionmode(::Type{LCMDimension{Symbol}}) = LCM_VAR
dimensionmode(::Type{LCMDimension{Int}}) = LCM_CONST

# Hash computation
# Port of https://github.com/ZeroCM/zcm/blob/e9c7bfc401ea15aa64291507da37d1163e5506c0/gen/ZCMGen.cpp#L73-L94
# NOTE: actual LCM implementation: https://github.com/lcm-proj/lcm/blob/992959adfbda78a13a858a514636e7929f27ed16/lcmgen/lcmgen.c#L114-L132
# uses an int64_t for v and thus relies on undefined behavior; see https://stackoverflow.com/a/4009922.
function sign_extended_right_shift(val::UInt64, nshift::UInt64)
    (val >> 63) == 0 ? val >> nshift :
        (val >> nshift) | ~((1 << (UInt64(64) - nshift)) - UInt64(1))
end

hashupdate(v::UInt64, c::Cchar) = ((v << 8) ⊻ sign_extended_right_shift(v, UInt64(55))) + c
hashupdate(v::UInt64, c::Char) = hashupdate(v, Cchar(c))
hashupdate(v::UInt64, n::Integer) = hashupdate(v, Cchar(n))

function hashupdate(v::UInt64, s::AbstractString)
    v = hashupdate(v, Cchar(length(s)))
    for char in s
        v = hashupdate(v, char)
    end
    v
end

hashupdate(v::UInt64, sym::Symbol) = hashupdate(v, string(sym))
hashupdate(v::UInt64, mode::DimensionMode) = hashupdate(v, Cchar(mode))
hashupdate(v::UInt64, dim::T) where {T<:LCMDimension} = (v = hashupdate(v, dimensionmode(T)); hashupdate(v, string(dim.size)))

isprimitive(::Type{<:LCMType}) = false
isprimitive(::Type{T}) where {T<:LCMPrimitive} = true
isprimitive(::Type{<:AbstractVector{T}}) where {T} = isprimitive(T)

lcmtypename(::Type{Int8}) = "int8_t"
lcmtypename(::Type{Int16}) = "int16_t"
lcmtypename(::Type{Int32}) = "int32_t"
lcmtypename(::Type{Int64}) = "int64_t"
lcmtypename(::Type{Float32}) = "float"
lcmtypename(::Type{Float64}) = "double"
lcmtypename(::Type{String}) = "string"
lcmtypename(::Type{Bool}) = "boolean"
lcmtypename(::Type{UInt8}) = "byte"
lcmtypename(::Type{<:AbstractVector{T}}) where {T} = lcmtypename(T)
lcmtypename(::Type{T}) where {T<:LCMType} = string(T)

# port of https://github.com/lcm-proj/lcm/blob/992959adfbda78a13a858a514636e7929f27ed16/lcmgen/lcmgen.c#L248-L282
function basehash(::Type{T}) where T<:LCMType
    v = UInt64(0x12345678)
    for field in fieldnames(T)
        v = hashupdate(v, field)
        F = fieldtype(T, field)
        if isprimitive(F)
            v = hashupdate(v, lcmtypename(F))
        end
        dims = dimensions(T, Val(field))
        v = hashupdate(v, length(dims))
        for dim in dims
            v = hashupdate(v, dim)
        end
    end
    v
end

computehash(::Type{T}, parents::Vector{DataType}) where {T<:LCMPrimitive} = zero(UInt64)
computehash(::Type{<:AbstractVector{T}}, parents::Vector{DataType}) where {T} = computehash(T, parents)
function computehash(::Type{T}, parents::Vector{DataType}) where T<:LCMType
    T in parents && return UInt64(0)
    hash = basehash(T)
    for field in fieldnames(T)
        F = fieldtype(T, field)
        hash += computehash(F, vcat(parents, T))
    end
    (hash << 1) + ((hash >> 63) & 1)
end

struct FingerprintException <: Exception
    T::Type
end

@noinline function Base.showerror(io::IO, e::FingerprintException)
    print(io, "LCM message fingerprint did not match type ", e.T, ". ")
    print(io, "This means that you are trying to decode the wrong message type, or a different version of the message type.")
end

function checkfingerprint(io::IO, ::Type{T}) where T<:LCMType
    decodefield(io, Int64) == fingerprint(T) || throw(FingerprintException(T))
end

# Resizing
@generated function Base.resize!(x::T) where T<:LCMType
    exprs = Expr[]
    for fieldname in fieldnames(T)
        F = fieldtype(T, fieldname)
        F <: AbstractVector && push!(exprs, :(LCMCore.resizevec!(x.$fieldname, x, LCMCore.dimensions(T, $(Val(fieldname)))...)))
    end
    quote
        $(exprs...)
        return nothing
    end
end

@inline resizevec!(vec::SVector, x::LCMType, dim::LCMDimension{Int}) = nothing
@inline resizevec!(vec::Vector, x::LCMType, dim::LCMDimension{Symbol}) = (_resizevec!(vec, getfield(x, dim.size)); nothing)
@inline function resizevec!(vec::AbstractVector, x::LCMType, dimhead::LCMDimension, dimtail::LCMDimension...)
    resizevec!(vec, x, dimhead)
    for vi in vec
        resizevec!(vi, x, dimtail...)
    end
end

@inline function _resizevec!(vec::Vector{T}, newsize::Integer) where T
    # Note: separated from resizevec! to introduce a function barrier and
    # achieve zero allocation despite the type-unstable `getfield` call.
    oldsize = length(vec)
    resize!(vec, newsize)
    for i in oldsize + 1 : newsize
        @inbounds vec[i] = defaultval(T)
    end
end

# checkvalid
"""
    checkvalid(x::LCMType)

Check that `x` is a valid LCM type. For example, check that array lengths are correct.
"""
@generated function checkvalid(x::T) where T<:LCMType
    exprs = Expr[]
    for fieldname in fieldnames(T)
        F = fieldtype(T, fieldname)
        F <: AbstractVector && push!(exprs, :(LCMCore.checkveclength(x.$fieldname, x, LCMCore.dimensions(T, $(Val(fieldname)))...)))
    end
    quote
        $(exprs...)
        return nothing
    end
end

@inline checkveclength(vec::SVector, x::LCMType, dim::LCMDimension{Int}) = nothing
@inline checkveclength(vec::Vector, x::LCMType, dim::LCMDimension{Symbol}) = (length(vec) == getfield(x, dim.size) || throw(DimensionMismatch()))
@inline function checkveclength(vec::AbstractVector, x::LCMType, dimhead::LCMDimension, dimtail::LCMDimension...)
    checkveclength(vec, x, dimhead)
    for vi in vec
        checkveclength(vi, x, dimtail...)
    end
end

# Decoding
function decode!(x::LCMType, io::IO)
    checkfingerprint(io, typeof(x))
    decodefield!(x, io)
end

"""
    decode_in_place(T)

Specify whether type `T` should be decoded in place, i.e. whether to use a
`decodefield!` method instead of a `decodefield` method.
"""
function decode_in_place end

Base.@pure decode_in_place(::Type{<:LCMType}) = true
@generated function decodefield!(x::T, io::IO) where T<:LCMType
    field_assignments = Vector{Expr}(fieldcount(x))
    for (i, fieldname) in enumerate(fieldnames(x))
        F = fieldtype(x, fieldname)
        field_assignments[i] = quote
            if decode_in_place($F)
                decodefield!(x.$fieldname, io)
            else
                x.$fieldname = decodefield(io, $F)
            end
            # $(QuoteNode(fieldname)) ∈ sizefields(T) && resize!(x) # allocates!
            any($(QuoteNode(fieldname)) .== sizefields(T)) && resize!(x)
        end
    end
    return quote
        $(field_assignments...)
        return x
    end
end

Base.@pure decode_in_place(::Type{Bool}) = false
decodefield(io::IO, ::Type{Bool}) = read(io, UInt8) == 0x01

Base.@pure decode_in_place(::Type{<:NetworkByteOrderEncoded}) = false
decodefield(io::IO, ::Type{T}) where {T<:NetworkByteOrderEncoded} = ntoh(read(io, T))

Base.@pure decode_in_place(::Type{String}) = false
function decodefield(io::IO, ::Type{String})
    len = ntoh(read(io, UInt32))
    ret = String(read(io, len - 1))
    read(io, UInt8) # strip off null
    ret
end

Base.@pure decode_in_place(::Type{<:Vector}) = true
function decodefield!(x::Vector{T}, io::IO) where T
    @inbounds for i in eachindex(x)
        if decode_in_place(T)
            isassigned(x, i) || (x[i] = defaultval(T))
            decodefield!(x[i], io)
        else
            x[i] = decodefield(io, T)
        end
    end
    x
end

Base.@pure decode_in_place(::Type{SV}) where {SV<:StaticVector} = decode_in_place(eltype(SV))
function decodefield!(x::StaticVector, io::IO)
    decode_in_place(eltype(x)) || error()
    @inbounds for i in eachindex(x)
        decodefield!(x[i], io)
    end
    x
end
@generated function decodefield(io::IO, ::Type{SV}) where {N, T, SV<:StaticVector{N, T}}
    constructor_arg_exprs = [:(decodefield(io, T)) for i = 1 : N]
    return quote
        decode_in_place(T) && error()
        SV(tuple($(constructor_arg_exprs...)))
    end
end

# Encoding
"""
    encode(io::IO, x::LCMType)

Write an LCM byte representation of `x` to `io`.
"""
function encode(io::IO, x::LCMType)
    encodefield(io, fingerprint(typeof(x)))
    encodefield(io, x)
end

@generated function encodefield(io::IO, x::LCMType)
    encode_exprs = Vector{Expr}(fieldcount(x))
    for (i, fieldname) in enumerate(fieldnames(x))
        encode_exprs[i] = :(encodefield(io, x.$fieldname))
    end
    quote
        checkvalid(x)
        $(encode_exprs...)
        io
    end
end

encodefield(io::IO, x::Bool) = write(io, ifelse(x, 0x01, 0x00))
encodefield(io::IO, x::NetworkByteOrderEncoded) = write(io, hton(x))
function encodefield(io::IO, x::String)
    write(io, hton(UInt32(length(x) + 1)))
    write(io, x)
    write(io, UInt8(0))
end
function encodefield(io::IO, A::AbstractVector)
    for x in A
        encodefield(io, x)
    end
end

# Sugar
encode(data::Vector{UInt8}, x::LCMType) = encode(IOBuffer(data, false, true), x)
encode(x::LCMType) = (stream = IOBuffer(false, true); encode(stream, x); flush(stream); take!(stream))

decode!(x::LCMType, data::Vector{UInt8}) = decode!(x, BufferedInputStream(data))
decode(data::Vector{UInt8}, ::Type{T}) where {T<:LCMType} = decode!(T(), data)

# @lcmtypesetup macro and related functions
function make_fixed_dimensions_method(::Type{T}, ::Type{<:SVector{N, <:Any}}, field::Symbol, axisnum::Int) where {T<:LCMType, N}
    let lcmdim = LCMCore.LCMDimension(N)
        LCMCore.dimensions(::Type{T}, ::Val{field}, ::Val{axisnum}) = lcmdim
    end
end

function make_fixed_dimensions_methods(::Type{T}, ::Type{F}, field::Symbol, axisnum::Int) where {T<:LCMType, V, F<:AbstractVector{V}}
    F <: SVector && make_fixed_dimensions_method(T, F, field, axisnum)
    V <: AbstractVector && return make_fixed_dimensions_methods(T, V, field, axisnum + 1)
    axisnum
end

function make_dimensions_methods(::Type{T}) where T<:LCMType
    for field in fieldnames(T)
        F = fieldtype(T, field)
        numaxes = F <: AbstractVector ? make_fixed_dimensions_methods(T, F, field, 1) : 0
        fieldval = Val(field)
        # Need to use invokelatest here, as the methods just created in `make_fixed_dimensions_methods`
        # would otherwise be too new to be visible here.
        let dimtuple = ntuple(i -> Base.invokelatest(LCMCore.dimensions, T, fieldval, Val(i)), numaxes)
            LCMCore.dimensions(::Type{T}, ::Val{field}) = dimtuple
        end
    end
end

"""
    @lcmtypesetup(lcmtype, dimensioninfos...)

Generate the following methods for a concrete LCMType subtype (say `MyType`):

* `dimensions(x::MyType, ::Val{fieldsym})`, for all fields
* `sizefields(::Type{MyType})`
* `fingerprint(::Type{MyType})`

The `lcmtype` argument should be the name of a concrete LCMType subtype.
The `dimensioninfos` arguments can be used to define which fields determine
the length of which variable-length vector fields. Each `dimensioninfos` element
should have the form

```julia
(vecfieldname, depth) => sizefieldname
```

where `vecfieldname` is the name of a (possibly nested) `AbstractVector` field and
`sizefieldname` is the name of the field containing the size. `depth` determines the
'nesting depth' for which the size is specified.

# Examples
```julia
mutable struct MyType <: LCMType
    alength::Int32
    c_inner_length::Int32
    a::Vector{Float64}
    b::SVector{3, Float32}
    c::SVector{3, Vector{Int64}}
end

@lcmtypesetup(MyType,
    (a, 1) => alength,
    (c, 2) => c_inner_length
)
```
"""
macro lcmtypesetup(lcmt, dimensioninfos...)
    # LCMCore.dimensions methods for variable dimensions
    sizefields = Set(Symbol[])
    vardimmethods = map(dimensioninfos) do dimensioninfo
        @assert dimensioninfo.head == :call
        @assert dimensioninfo.args[1] == :(=>)
        @assert dimensioninfo.args[2].head == :tuple
        @assert length(dimensioninfo.args[2].args) == 2
        vecfieldname, depth = dimensioninfo.args[2].args
        sizefieldname = dimensioninfo.args[3]::Symbol
        push!(sizefields, sizefieldname)
        quote
            let lcmdim = LCMCore.LCMDimension($(QuoteNode(sizefieldname)))
                LCMCore.dimensions(::Type{$lcmt}, ::Val{$(QuoteNode(vecfieldname))}, ::Val{$depth}) = lcmdim
            end
        end
    end

    # LCMCore.dimensions methods for constant dimensions, and a method that returns a tuple of LCMDimensions for each field
    dimmethods = :(LCMCore.make_dimensions_methods($lcmt))

    # LCMCore.sizefields method
    sizefieldsmethod = quote
        let sizefieldtup = tuple($(map(QuoteNode, collect(sizefields))...))
            LCMCore.sizefields(::Type{$lcmt}) = sizefieldtup
        end
    end

    # LCMCore.fingerprint method
    fingerprint = quote
        let hash = reinterpret(Int64, LCMCore.computehash($lcmt, DataType[]))
            LCMCore.fingerprint(::Type{$lcmt}) = hash
        end
    end

    esc(quote
        $(vardimmethods...)
        $dimmethods
        $sizefieldsmethod
        $fingerprint
    end)
end
