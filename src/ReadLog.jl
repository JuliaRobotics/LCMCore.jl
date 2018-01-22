# Read LCM log files directly

# export
#   LCMlog,
#   close,
#   readNextEvent,
#   handle,
#   subscribe

# also see JuliaLang's RawFD type, but little information found.
# www.c4learn/c-programming/c-file-structure-and-file-pointer
mutable struct FILE
  level::Cshort
  token::Cshort
  bsize::Cshort
  fd::Cuchar
  flags::Cuint  # (unsigned flags ;)
  hold::Cuchar
  buffer::Ptr{Cuchar}
  curp::Ptr{Cuchar}
  istemp::Cuint # (unsigned is temp)
end

mutable struct lcm_eventlog_t
  f::Ptr{FILE}
  eventcount::Clonglong
end
const _LCMlog = Ptr{lcm_eventlog_t}


struct lcm_eventlog_event_t
  eventnum::Clonglong
  timestamp::Clonglong
  channellen::Cint
  datalen::Cint
  channel::Ptr{Cuchar}
  data::Ptr{Cuchar}
end


function lcm_eventlog_create(file::S where S <: AbstractString)
  ccall(
    (:lcm_eventlog_create, LCMCore.liblcm),
    _LCMlog, #Ptr{lcm_eventlog_t},
    (Cstring, Cstring),
    file, "r"
  )
end


function lcm_eventlog_destroy(_log::Ptr{lcm_eventlog_t})
  ccall(
    (:lcm_eventlog_destroy, LCMCore.liblcm),
    Void,
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



mutable struct LCMlog
  _log::_LCMlog
  subscriptions::Dict{AbstractString, LCMCore.SubscriptionOptions}
  function LCMlog(filename::S) where {S <: AbstractString}
    try
      _log = lcm_eventlog_create(filename)
      return new(_log, Dict{AbstractString, LCMCore.SubscriptionOptions}())
    catch e
      warn(e)
      backtrace()
      throw("Cannot open the LCM log file at: $filename")
    end
    return new() # should never occur
  end
end



function close(lcmlog::LCMlog)
  try
    lcm_eventlog_destroy(lcmlog._log)
  catch e
    warn(e)
  end
end

isgood(_event::Ptr{lcm_eventlog_event_t}) = _event != C_NULL

function readNextEvent(lcmlog::LCMlog)::Union{Void, lcm_eventlog_event_t}
  _event = lcm_eventlog_read_next_event(lcmlog._log)
  if isgood(_event)
    return unsafe_load(_event)
  end
  nothing
end

function handle(lcmlog::LCMlog)::Bool
    # do memory copy and then check for subscribed channel -- This is not efficient, but easiest to do. TBD is `unsafe_wrap` to avoid memory copy of _event
    event = readNextEvent(lcmlog)
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

function subscribe(lcmlog::LCMlog, channel::S, callback::F, msgtype=Void) where {S <: AbstractString, F <: Function}
  opts = LCMCore.LCMCore.SubscriptionOptions(msgtype, callback)
  lcmlog.subscriptions[channel] = opts
  nothing
end
