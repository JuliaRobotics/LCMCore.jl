__precompile__()

module LCMCore

depsjl = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if !isfile(depsjl)
    error("LCMCore not properly installed. Please run\nPkg.build(\"LCMCore\")")
else
    include(depsjl)
end

import Base: unsafe_convert, close
using Base.Dates: Period, Millisecond
export LCM,
       publish,
       close,
       filedescriptor,
       encode,
       decode,
       subscribe,
       handle,
       set_queue_capacity!


# These are the methods that custom LCM types need to overload.
# The expected signatures are:
# encode(::MyMessageType)::Vector{UInt8}
# decode(::Vector{UInt8}, ::Type{MyMessageType})::MyMessageType
function encode end
function decode end

type SubscriptionOptions{T, F}
    msgtype::Type{T}
    handler::F
end

immutable Subscription{T <: SubscriptionOptions}
    options::T
    csubscription::Ptr{Void}
end

type LCM
    pointer::Ptr{Void}
    filedescriptor::RawFD
    subscriptions::Vector{Subscription}

    LCM() = begin
        pointer = ccall((:lcm_create, liblcm), Ptr{Void}, (Ptr{UInt8},), "")
        filedescriptor = RawFD(ccall((:lcm_get_fileno, liblcm), Cint, (Ptr{Void},), pointer))
        lc = new(pointer, filedescriptor, Subscription[])
        finalizer(lc, close)
        lc
    end
end
unsafe_convert(::Type{Ptr{Void}}, lc::LCM) = lc.pointer

function close(lcm::LCM)
    if lcm.pointer != C_NULL
        ccall((:lcm_destroy, liblcm), Void, (Ptr{Void},), lcm)
        lcm.pointer = C_NULL
    end
end

function LCM(func::Function)
    lcm = LCM()
    try
        func(lcm)
    finally
        close(lcm)
    end
end

function publish{T}(lcm::LCM, channel::AbstractString, msg::T)
    data = encode(msg)
    publish(lcm, convert(String, channel), data)
end

function publish(lcm::LCM, channel::AbstractString, data::Vector{UInt8})
    status = ccall((:lcm_publish, liblcm), Cint, (Ptr{Void}, Ptr{UInt8}, Ptr{UInt8}, Cuint), lcm, channel, data, length(data))
    return status == 0
end

filedescriptor(lcm::LCM) = lcm.filedescriptor

immutable RecvBuf
    data::Ptr{UInt8}
    data_size::UInt32
    recv_utime::Int64
    lcm::Ptr{Void}
end

function onresponse{T, F}(rbuf::RecvBuf, channelbytes::Ptr{UInt8}, opts::SubscriptionOptions{T, F})
    channel = unsafe_wrap(String, channelbytes)
    msgdata = unsafe_wrap(Vector{UInt8}, rbuf.data, rbuf.data_size)
    if isa(T, Type{Void})
        opts.handler(channel, msgdata)
    else
        msg = decode(msgdata, opts.msgtype)
        opts.handler(channel, msg)
    end
    return nothing::Void
end

function subscribe{T <: SubscriptionOptions}(lcm::LCM, channel::String, options::T)
    csubscription = ccall((:lcm_subscribe, liblcm), Ptr{Void},
        (Ptr{Void}, Ptr{UInt8}, Ptr{Void}, Ptr{Void}),
        lcm,
        channel,
        cfunction(onresponse, Void, (Ref{RecvBuf}, Ptr{UInt8}, Ref{T})),
        Ref(options))
    sub = Subscription(options, csubscription)
    push!(lcm.subscriptions, sub)
    sub
end

function subscribe(lcm::LCM, channel::String, handler, msgtype=Void)
    subscribe(lcm, channel, SubscriptionOptions(msgtype, handler))
end

function set_queue_capacity!(sub::Subscription, capacity::Integer)
    @assert capacity >= 0
    status = ccall((:lcm_subscription_set_queue_capacity, liblcm), Cint, (Ptr{Void}, Cint), sub.csubscription, capacity)
    return status == 0
end

lcm_handle(lcm::LCM) = ccall((:lcm_handle, liblcm), Cint, (Ptr{Void},), lcm)

function handle(lcm::LCM)
    fd = filedescriptor(lcm)
    while true
        event = poll_fd(fd, 10; readable=true)
        if event.readable
            lcm_handle(lcm)
            return true
        end
    end
end

function handle(lcm::LCM, timeout::Period)
    timeout_ms = convert(Int, convert(Millisecond, timeout))
    fd = filedescriptor(lcm)
    event = poll_fd(fd, timeout_ms / 1000; readable=true)
    if event.readable
        lcm_handle(lcm)
        return true
    else
        return false
    end
end


end
