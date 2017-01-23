module LCMCore

import Base: unsafe_convert, read, write, close
using Base.Dates: Period, Millisecond
export LCM,
       publish,
       filedescriptor,
       encode,
       decode,
       subscribe,
       handle


function encode end
function decode end


const liblcm = "$(ENV["HOME"])/.julia/v0.5/PyLCM/deps/usr/lib/liblcm.dylib"

type LCM
    pointer::Ptr{Void}
    filedescriptor::RawFD

    LCM() = begin
        pointer = ccall((:lcm_create, liblcm), Ptr{Void}, (Ptr{UInt8},), "")
        filedescriptor = RawFD(ccall((:lcm_get_fileno, liblcm), Cint, (Ptr{Void},), pointer))
        lc = new(pointer, filedescriptor)
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

function publish(lcm::LCM, channel::String, data::Vector{UInt8})
    ccall((:lcm_publish, liblcm), Cint, (Ptr{Void}, Ptr{UInt8}, Ptr{UInt8}, Cuint), channel, data, length(data))
end

filedescriptor(lcm::LCM) = lcm.filedescriptor

immutable RecvBuf
    data::Ptr{UInt8}
    data_size::UInt32
    recv_utime::Int64
    lcm::Ptr{Void}
end

type SubscriptionInfo{T, F}
    msgtype::Type{T}
    handler::F
end

function onresponse(rbuf::RecvBuf, channelbytes::Ptr{UInt8}, info::SubscriptionInfo)
    channel = unsafe_wrap(String, channelbytes)
    msgdata = unsafe_wrap(Vector{UInt8}, rbuf.data, rbuf.data_size)
    @show info
    msg = decode(IOBuffer(msgdata), info.msgtype)
    info.handler(channel, msg)
    return nothing::Void
end

function subscribe{T}(lcm::LCM, channel::String, handler::Function, msgtype::Type{T})
    info = SubscriptionInfo(msgtype, handler)
    ccall((:lcm_subscribe, liblcm), Ptr{Void},
    (Ptr{Void}, Ptr{UInt8}, Ptr{Void}, Ptr{Void}),
    lcm,
    channel,
    cfunction(onresponse, Void, (Ref{RecvBuf}, Ptr{UInt8}, Ref{typeof(info)})),
    Ref(info))
end

chandle(lcm::LCM) = ccall((:lcm_handle, liblcm), Cint, (Ptr{Void},), lcm)

function handle(lcm::LCM)
    fd = filedescriptor(lcm)
    while true
        event = poll_fd(fd, 10; readable=true)
        if event.readable
            chandle(lcm)
            return true
        end
    end
end

function handle(lcm::LCM, timeout::Period)
    timeout_ms = convert(Int, convert(Millisecond, timeout))
    fd = filedescriptor(lcm)
    event = poll_fd(fd, timeout_ms / 1000; readable=true)
    if event.readable
        chandle(lcm)
        return true
    else
        return false
    end
end

end
