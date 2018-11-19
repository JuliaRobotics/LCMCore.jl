# Read LCM log files directly

mutable struct lcm_eventlog_t
    f::Ptr{Cvoid}
    eventcount::Int64 #Clonglong
end

struct lcm_eventlog_event_t
    eventnum::Int64 #Clonglong
    timestamp::Int64 #Clonglong
    channellen::Int32 #Cint
    datalen::Int32 #Cint
    channel::Ptr{Cuchar}
    data::Ptr{Cuchar}
end

function lcm_eventlog_create(file::S where S <: AbstractString)
    ccall(
    (:lcm_eventlog_create, LCMCore.liblcm),
    Ptr{lcm_eventlog_t},
    (Cstring, Cstring),
    file, "r"
    )
end

function lcm_eventlog_destroy(_log::Ptr{lcm_eventlog_t})
    ccall(
    (:lcm_eventlog_destroy, LCMCore.liblcm),
    Cvoid,
    (Ptr{lcm_eventlog_t}, ),
    _log
    )
end

function lcm_eventlog_read_next_event(_log::Ptr{lcm_eventlog_t})
    ccall(
    (:lcm_eventlog_read_next_event, LCMCore.liblcm),
    Ptr{lcm_eventlog_event_t},
    (Ptr{lcm_eventlog_t},),
    _log
    )
end

#
# Doesn't work yet
# event = unsafe_wrap(lcm_eventlog_event_t, _event, dim??)

mutable struct LCMLog
    _log::Ptr{lcm_eventlog_t}
    subscriptions::Dict{AbstractString, LCMCore.SubscriptionOptions}
    function LCMLog(filename::S) where {S <: AbstractString}
        _log = lcm_eventlog_create(filename)
        if !isgood(_log)
            throw(ArgumentError("Cannot open the LCM log file at: $filename"))
        end
        return new(_log, Dict{AbstractString, LCMCore.SubscriptionOptions}())
    end
end

function close(lcmlog::LCMLog)
    if isgood(lcmlog)
        lcm_eventlog_destroy(lcmlog._log)
    end
end

isgood(_log::Ptr{lcm_eventlog_t}) = _log != C_NULL
isgood(lcmlog::LCMLog) = isgood(lcmlog._log)
isgood(_event::Ptr{lcm_eventlog_event_t}) = _event != C_NULL

function read_next_event(lcmlog::LCMLog)::Union{Nothing, lcm_eventlog_event_t}
    _event = lcm_eventlog_read_next_event(lcmlog._log)
    if isgood(_event)
        return unsafe_load(_event)
    end
    nothing
end

function handle(lcmlog::LCMLog)::Bool
    # do memory copy and then check for subscribed channel -- This is not efficient, but easiest to do. TBD is `unsafe_wrap` to avoid memory copy of _event
    event = read_next_event(lcmlog)
    if event != nothing
        # need a convert from lcm_eventlog_event_t to (RecvBuf, channelbytes, chnlen)
        rb = LCMCore.RecvBuf(event.data, UInt32(event.datalen), event.timestamp, 0)
        # need a LCMCore.SubscriptionOptions{T}
        chn = unsafe_string(event.channel, event.channellen)
        if haskey(lcmlog.subscriptions, chn)
            opts = lcmlog.subscriptions[chn]
            # use onresponse similar to regular live LCM traffic
            LCMCore.onresponse(rb, event.channel, opts)
        end
        return true
    end
    return false
end

function subscribe(lcmlog::LCMLog, channel::S, callback::F, msgtype=Nothing) where {S <: AbstractString, F}
    opts = SubscriptionOptions(msgtype, callback, channel)
    lcmlog.subscriptions[channel] = opts
    nothing
end
