# testing ccall of LCM log file handling

using LCMCore
importall LCMCore

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


mutable struct lcm_eventlog_event_t
  eventnum::Clonglong
  timestamp::Clonglong
  channellen::Cint
  datalen::Cint
  channel::Ptr{Cuchar}
  data::Ptr{Cuchar}
end


# LCMCore.liblcm

# channel = "TEST"
#
# lcm = LCM()
#
# data= rand(UInt8, 10)
#
# ccall((:lcm_publish, LCMCore.liblcm), Cint, (Ptr{Void}, Ptr{UInt8}, Ptr{UInt8}, Cuint), lcm, channel, data, length(data))

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
    _event = ccall(
      (:lcm_eventlog_read_next_event, LCMCore.liblcm),
      Ptr{lcm_eventlog_event_t},
      (Ptr{lcm_eventlog_t},),
      _log
    )
    unsafe_load(_event)
end


# function fetchRecvBuf(event::)
#
# end





# typeof(log)

# for i in 1:1000
#
# end


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


function handle(lcmlog::LCMlog)::Void
    event = lcm_eventlog_read_next_event(lcmlog._log)
    # need a convert from lcm_eventlog_event_t to (RecvBuf, channelbytes, chnlen)
    rb = LCMCore.RecvBuf(event.data, UInt32(event.datalen), event.timestamp, 0)
    # need a LCMCore.SubscriptionOptions{T}
    chn = unsafe_string(event.channel, event.channellen)
    if haskey(lcmlog.subscriptions, chn)
      opts = lcmlog.subscriptions[chn]
      # use onresponse similar to regular live LCM traffic
      LCMCore.onresponse(rb, event.channel, opts)
    end
    nothing
end


function subscribe(lcmlog::LCMlog, channel::S, callback::Function) where {S <: AbstractString}
  opts = LCMCore.LCMCore.SubscriptionOptions(Void, handletest)
  lcmlog.subscriptions[channel] = opts
end


function handletest(chn, msgdata)
  @show "got $chn"
end


# _log = lcm_eventlog_create("/home/dehann/data/Robot-20170918-211035-simulator.lcm")
log = LCMlog("/home/dehann/data/Robot-20170918-211035-simulator.lcm")


subscribe(log, "IMU_SIMULATOR", handletest)


# to run handle
for i in 1:1000
  handle(log)
end

event




close(log)









#
