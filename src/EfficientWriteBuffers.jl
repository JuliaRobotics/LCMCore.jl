module EfficientWriteBuffers

export EfficientWriteBuffer

struct EfficientWriteBuffer <: IO
    data::Vector{UInt8}
    position::Base.RefValue{Int}
end

EfficientWriteBuffer(data::Vector{UInt8}) = EfficientWriteBuffer(data, Ref(0))
EfficientWriteBuffer() = EfficientWriteBuffer(Vector{UInt8}())

@inline function ensureroom!(buf::EfficientWriteBuffer, n::Integer)
    resize!(buf.data, buf.position[] + n)
end

function Base.take!(buf::EfficientWriteBuffer)
    resize!(buf.data, buf.position[])
    buf.position[] = 0
    buf.data
end

@inline function Base.unsafe_write(buf::EfficientWriteBuffer, p::Ptr{UInt8}, n::UInt)
    ensureroom!(buf, n)
    unsafe_copyto!(pointer(buf.data, buf.position[] + 1), p, n)
    buf.position[] += n
    Int(n)
end

Base.@propagate_inbounds function Base.write(buf::EfficientWriteBuffer, x::UInt8)
    ensureroom!(buf, 1)
    position = buf.position[] += 1
    buf.data[position] = x
    1
end

Base.@propagate_inbounds Base.write(buf::EfficientWriteBuffer, x::Int8) = write(buf, reinterpret(UInt8, x))

@inline function Base.write(
            buf::EfficientWriteBuffer,
            x::Union{Int16,UInt16,Int32,UInt32,Int64,UInt64,Int128,UInt128}) # TODO: more?
    n = Core.sizeof(x)
    ensureroom!(buf, n)
    position = buf.position[]
    @inbounds for i = Base.OneTo(n) # LLVM unrolls this loop on Julia 0.6.4
        position += 1
        buf.data[position] = x % UInt8
        x = x >>> 8
    end
    buf.position[] = position
    n
end

@inline Base.write(buf::EfficientWriteBuffer, x::Union{Float16, Float32, Float64}) = write(buf, reinterpret(Unsigned, x))

Base.eof(buf::EfficientWriteBuffer) = true

end
