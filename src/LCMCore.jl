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
       unsubscribe,
       handle,
       set_queue_capacity


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
unsafe_convert(::Type{Ptr{Void}}, sub::Subscription) = sub.csubscription

# Troubleshooting adapted from:
# https://github.com/RobotLocomotion/drake/blob/f72bb3f465f69f25459a7a65c57b45c795b5e31d/drake/matlab/util/setup_loopback_multicast.sh
# https://github.com/RobotLocomotion/drake/blob/f72bb3f465f69f25459a7a65c57b45c795b5e31d/drake/matlab/util/check_multicast_is_loopback.sh
function troubleshoot()
    lo = loopback_interface()
    if check_loopback_multicast(lo)
        check_multicast_routing(lo)
    end
    error("Failed to create LCM instance.")
end

loopback_interface() = chomp(readstring(pipeline(`ifconfig`, `grep -m 1 -i loopback`, `cut -d : -f1`)))

function loopback_multicast_setup_advice(lo::String)
    @static if is_apple()
        """Consider running:
        route add -net 224.0.0.0 -netmask 240.0.0.0 -interface $lo"""
    elseif is_linux()
        """Consider running:
        ifconfig $lo multicast
        route add -net 224.0.0.0 netmask 240.0.0.0 dev lo"""
    else
        "OS-specific instructions not available."
    end
end

function check_loopback_multicast(lo::String)
    pass = if parse(readstring(pipeline(`ifconfig $lo`, `grep -c -i multicast`))) != 0
        msg = """Loopback interface $lo is not set to multicast.
        The most probable cause for this is that you are not connected to the internet.
        $(loopback_multicast_setup_advice(lo))"""
        warn(msg)
        false
    else
        true
    end
    pass
end

function check_multicast_routing(lo::String)
    routing_correct = @static if is_apple()
        chomp(readstring(pipeline(`route get 224.0.0.0 -netmask 240.0.0.0`, `grep -m 1 -i interface`, `cut -f2 -d :`, `tr -d ' '`))) == lo
    elseif is_linux()
        chomp(readstring(pipeline(`ip route get 224.0.0.0`, `grep -m 1 -i dev`, `sed 's/.*dev\s*//g'`, `cut -d ' ' -f1`))) == lo
    else
        error()
    end
    pass = if !routing_correct
        msg = """
        Route to multicast channel does not run through the loopback interface.
        The most probable cause for this is that you are not connected to the internet.
        $(loopback_multicast_setup_advice(lo))
        """
        warn(msg)
        false
    else
        true
    end
    pass
end

type LCM
    pointer::Ptr{Void}
    provider::String
    filedescriptor::RawFD
    subscriptions::Vector{Subscription}

    LCM(provider="") = begin
        pointer = ccall((:lcm_create, liblcm), Ptr{Void}, (Ptr{UInt8},), provider)
        if pointer == C_NULL
            troubleshoot()
        end
        filedescriptor = RawFD(ccall((:lcm_get_fileno, liblcm), Cint, (Ptr{Void},), pointer))
        lcm = new(pointer, provider, filedescriptor, Subscription[])
        finalizer(lcm, close)
        lcm
    end
end
unsafe_convert(::Type{Ptr{Void}}, lcm::LCM) = lcm.pointer

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
    channel = unsafe_string(channelbytes)
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

function unsubscribe(lcm::LCM, subscription::Subscription)
    result = ccall((:lcm_unsubscribe, liblcm), Cint, (Ptr{Void}, Ptr{Void}), lcm, subscription)
    result == 0
end

function set_queue_capacity(sub::Subscription, capacity::Integer)
    @assert capacity >= 0
    status = ccall((:lcm_subscription_set_queue_capacity, liblcm), Cint, (Ptr{Void}, Cint), sub, capacity)
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
    timeout_ms = Dates.value(convert(Millisecond, timeout))
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
