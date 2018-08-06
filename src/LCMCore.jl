module LCMCore

using StaticArrays
using BufferedStreams

using Dates
using FileWatching: poll_fd
import Base: unsafe_convert, close

depsjl = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if !isfile(depsjl)
    error("LCMCore not properly installed. Please run\nPkg.build(\"LCMCore\")")
else
    include(depsjl)
end

export LCM,
       LCMType,
       publish,
       close,
       filedescriptor,
       encode,
       decode,
       decode!,
       subscribe,
       unsubscribe,
       handle,
       set_queue_capacity,
       isgood,
       LCMLog,
       @lcmtypesetup

include("EfficientWriteBuffers.jl")
using .EfficientWriteBuffers: EfficientWriteBuffer

include("util.jl")
include("core.jl")
include("lcmtype.jl")
include("readlog.jl")

end
