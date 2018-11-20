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
    fingerprint(::Type{T}) where T<:LCMType

Return the fingerprint of LCM type `T` as an Int64 (exactly 8 bytes).
"""
function fingerprint end

# Types that are encoded in network byte order, as dictated by the LCM type specification.
const NetworkByteOrderEncoded = Union{Int8, Int16, Int32, Int64, Float32, Float64, UInt8}

# Julia types that correspond to LCM primitive types
const LCMPrimitive = Union{Int8, Int16, Int32, Int64, Float32, Float64, String, Bool, UInt8}

# Default values for all of the possible field types of an LCM type:
defaultval(::Type{T}) where {T<:LCMType} = T()
defaultval(::Type{Bool}) = false
defaultval(::Type{T}) where {T<:NetworkByteOrderEncoded} = zero(T)
defaultval(::Type{String}) = ""
defaultval(::Type{Array{T, N}}) where {T, N} = Array{T, N}(undef, ntuple(i -> 0, Val(N))...)
defaultval(::Type{SA}) where {T, SA<:StaticArray{<:Any, T}} = _defaultval(SA, T, Length(SA))
_defaultval(::Type{SA}, ::Type{T}, ::Length{L}) where {SA, T, L} = SA(ntuple(i -> defaultval(T), Val(L)))

# Generated default constructor for LCMType subtypes
@generated function (::Type{T})() where T<:LCMType
    constructor_arg_exprs = [:(defaultval(fieldtype(T, $i))) for i = 1 : fieldcount(T)]
    :(T($(constructor_arg_exprs...)))
end

# Field dimension information
abstract type LCMDimension end

struct LCMDimensionVar{T} <: LCMDimension end
LCMDimensionVar(fieldname::Symbol) = LCMDimensionVar{fieldname}()
sizestring(::LCMDimensionVar{T}) where {T} = string(T)

struct LCMDimensionConst{T} <: LCMDimension end
LCMDimensionConst(constsize::Integer) = LCMDimensionConst{Int(constsize)}()
sizestring(::LCMDimensionConst{T}) where {T} = string(T)

@enum DimensionMode LCM_CONST LCM_VAR
dimensionmode(::Type{<:LCMDimensionVar}) = LCM_VAR
dimensionmode(::Type{<:LCMDimensionConst}) = LCM_CONST

makedim(fieldname::Symbol) = LCMDimensionVar(fieldname)
makedim(constsize::Int) = LCMDimensionConst(constsize)

@inline evaldims(x::LCMType) = ()
@inline function evaldims(x::LCMType, dimhead::LCMDimensionConst{constsize}, dimtail::LCMDimension...) where {constsize}
    (Int(constsize), evaldims(x, dimtail...)...)
end
@inline function evaldims(x::LCMType, dimhead::LCMDimensionVar{fieldname}, dimtail::LCMDimension...) where {fieldname}
    (Int(getfield(x, fieldname)), evaldims(x, dimtail...)...)
end

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
function hashupdate(v::UInt64, dim::T) where {T<:LCMDimension}
    v = hashupdate(v, dimensionmode(T))
    hashupdate(v, sizestring(dim))
end

isprimitive(::Type{<:LCMType}) = false
isprimitive(::Type{T}) where {T<:LCMPrimitive} = true
isprimitive(::Type{<:AbstractArray{T}}) where {T} = isprimitive(T)

lcmtypename(::Type{Int8}) = "int8_t"
lcmtypename(::Type{Int16}) = "int16_t"
lcmtypename(::Type{Int32}) = "int32_t"
lcmtypename(::Type{Int64}) = "int64_t"
lcmtypename(::Type{Float32}) = "float"
lcmtypename(::Type{Float64}) = "double"
lcmtypename(::Type{String}) = "string"
lcmtypename(::Type{Bool}) = "boolean"
lcmtypename(::Type{UInt8}) = "byte"
lcmtypename(::Type{<:AbstractArray{T}}) where {T} = lcmtypename(T)
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
computehash(::Type{<:AbstractArray{T}}, parents::Vector{DataType}) where {T} = computehash(T, parents)
function computehash(::Type{T}, parents::Vector{DataType}) where T<:LCMType
    T in parents && return zero(UInt64)
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
    fp = fingerprint(T)
    fpint = fp isa Int64 ? fp : ntoh(reinterpret(Int64, Vector(fp))[1]) # TODO: remove for next release; fingerprints are now Int64s
    decodefield(io, Int64) == fpint || throw(FingerprintException(T))
end

# Resizing
@generated function Base.resize!(x::T) where T<:LCMType
    exprs = Expr[]
    for fieldname in fieldnames(T)
        F = fieldtype(T, fieldname)
        if F <: Array
            push!(exprs, quote
                resizearrayfield!(x, $(Val(fieldname)), $F)
            end)
        end
    end
    quote
        $(exprs...)
        return nothing
    end
end

@generated function resizearrayfield!(x::T, ::Val{fieldname}, ::Type{Array{S, N}}) where {T<:LCMType, fieldname, S, N}
    quote
        Base.@_inline_meta
        newsize = evaldims(x, dimensions(T, $(Val(fieldname)))...)
        if newsize !== size(x.$fieldname)
            x.$fieldname = Array{S, N}(undef, newsize...)
            @inbounds for i in eachindex(x.$fieldname)
                x.$fieldname[i] = defaultval(S)
            end
        end
    end
end

# check_valid
"""
    check_valid(x::LCMType)

Check that the array sizes of `x` match their corresponding size fields.
"""
@generated function check_valid(x::T) where T<:LCMType
    exprs = Expr[]
    for fieldname in fieldnames(T)
        F = fieldtype(T, fieldname)
        if F <: Array
            push!(exprs, quote
                if size(x.$fieldname) != evaldims(x, LCMCore.dimensions(T, $(Val(fieldname)))...)
                    throw(DimensionMismatch())
                end
            end)
        end
    end
    quote
        $(exprs...)
        return nothing
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

decode_in_place(::Type{<:LCMType}) = true
@generated function decodefield!(x::T, io::IO) where T<:LCMType
    field_assignments = Vector{Expr}(undef, fieldcount(x))
    for (i, fieldname) in enumerate(fieldnames(x))
        F = fieldtype(x, fieldname)
        field_assignments[i] = quote
            $F <: Array && resizearrayfield!(x, $(Val(fieldname)), $F)
            if decode_in_place($F)
                decodefield!(x.$fieldname, io)
            else
                x.$fieldname = decodefield(io, $F)
            end
        end
    end
    return quote
        $(field_assignments...)
        return x
    end
end

decode_in_place(::Type{Bool}) = false
decodefield(io::IO, ::Type{Bool}) = read(io, UInt8) == 0x01

decode_in_place(::Type{<:NetworkByteOrderEncoded}) = false
decodefield(io::IO, ::Type{T}) where {T<:NetworkByteOrderEncoded} = ntoh(read(io, T))

decode_in_place(::Type{String}) = false
function decodefield(io::IO, ::Type{String})
    len = ntoh(read(io, UInt32))
    ret = String(read(io, len - 1))
    read(io, UInt8) # strip off null
    ret
end

decode_in_place(::Type{<:Array}) = true
function decodefield!(x::Array{T}, io::IO) where T
    if decode_in_place(T)
        @inbounds for i in reversedimindices(x)
            decodefield!(x[i], io)
        end
    else
        @inbounds for i in reversedimindices(x)
            x[i] = decodefield(io, T)
        end
    end
    x
end

decode_in_place(::Type{SA}) where {T, SA<:StaticArray{<:Any, T}} = decode_in_place(T)
function decodefield!(x::StaticArray{<:Any, T}, io::IO) where T
    decode_in_place(T) || error()
    @inbounds for i in reversedimindices(x)
        decodefield!(x[i], io)
    end
    x
end
@inline decodefield(io::IO, ::Type{SA}) where {SA<:StaticArray} = _decodefield(io, Size(SA), SA)
@generated function _decodefield(io::IO, ::Size{s}, ::Type{SA}) where {s, T, SA<:StaticArray{<:Any, T}}
    decode_in_place(T) && error()
    exprs = [:(decodefield(io, T)) for i = 1 : prod(s)]
    quote
        Base.@_inline_meta
        reversedims($SA(tuple($(exprs...))))
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
    encode_exprs = Vector{Expr}(undef, fieldcount(x))
    for (i, fieldname) in enumerate(fieldnames(x))
        encode_exprs[i] = :(encodefield(io, x.$fieldname))
    end
    quote
        check_valid(x)
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
function encodefield(io::IO, A::AbstractArray)
    for i in reversedimindices(A)
        encodefield(io, A[i])
    end
end

# Sugar
encode(data::AbstractVector{UInt8}, x::LCMType) = encode(FastWriteBuffer(data), x)
encode(x::LCMType) = (stream = FastWriteBuffer(); encode(stream, x); flush(stream); take!(stream))

decode!(x::LCMType, data::AbstractVector{UInt8}) = decode!(x, FastReadBuffer(data))
decode(data::AbstractVector{UInt8}, ::Type{T}) where {T<:LCMType} = decode!(T(), data)

# @lcmtypesetup macro and related functions
"""
    @lcmtypesetup(lcmtype, dimensioninfos...)

Generate the following methods for a concrete LCMType subtype (say `MyType`):

* `dimensions(x::MyType, ::Val{fieldsym})`, for all fields
* `fingerprint(::Type{MyType})`

The `lcmtype` argument should be the name of a concrete LCMType subtype.
The `dimensioninfos` arguments can be used to define which fields determine
the size of which variable-size array fields. Each `dimensioninfos` element
should have the form

```julia
arrayfieldname => (size1, size2, ...)
```

where `arrayfieldname` is the name of an `Array` field and `size1`, `size2`
etc. are the dimensions of the `Array`, where both integers and field names
that come *before* `arrayfieldname` in the type definition may be used.

# Examples
```julia
mutable struct MyType <: LCMType
    alength::Int32
    c_inner_length::Int32
    a::Vector{Float64}
    b::SVector{3, Float32}
    c::Matrix{Int64}
end

@lcmtypesetup(MyType,
    a => (alength, ),
    c => (3, c_inner_length)
)
```
"""
macro lcmtypesetup(lcmt, dimensioninfos...)
    # LCMCore.dimensions methods for variable dimensions
    vardimmethods = map(dimensioninfos) do dimensioninfo
        @assert dimensioninfo.head == :call
        @assert dimensioninfo.args[1] == :(=>)
        vecfieldname = dimensioninfo.args[2]::Symbol
        @assert dimensioninfo.args[3].head == :tuple
        dims = dimensioninfo.args[3].args
        quote
            let dimtuple = tuple($(LCMCore.makedim.(dims)...))
                LCMCore.dimensions(::Type{$(esc(lcmt))}, ::Val{$(QuoteNode(vecfieldname))}) = dimtuple
            end
        end
    end

    # LCMCore.dimensions methods for constant dimensions
    makeconstdimmethods = quote
        let T = $(esc(lcmt))
            for field in fieldnames(T)
                F = fieldtype(T, field)
                if F <: Array
                    # skip
                elseif F <: StaticArray
                    let dimtuple = LCMCore.makedim.(size(F))
                        LCMCore.dimensions(::Type{T}, ::Val{field}) = dimtuple
                    end
                else
                    LCMCore.dimensions(::Type{T}, ::Val{field}) = ()
                end
            end
        end
    end

    # LCMCore.fingerprint method
    fingerprint = quote
        let hash = reinterpret(Int64, LCMCore.computehash($(esc(lcmt)), DataType[]))
            LCMCore.fingerprint(::Type{$(esc(lcmt))}) = hash
        end
    end

    quote
        $(vardimmethods...)
        $makeconstdimmethods
        $fingerprint
    end
end
