# This is LCMproto.jl
# https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey

addprocs(1)

@everywhere begin
using LCMCore
using ProtoBuf
using JSON

import LCMCore: encode, decode


typealias MDD Dict{ASCIIString,Vector{UInt8}}

type Nested
  more::Float64
  data::Vector{UInt8}
  Nested() = new()
  Nested(a,b) = new(a,b)
end

type MyMessageType{T}  # a Julia composite type
 intval::Int                             # probably generated from protoc
 strval::ASCIIString
 len::Int64
 data::Vector{Float64}
 ndd::Nested
 dd::T
 MyMessageType() = new()
 MyMessageType{T}(i,s,l,d,nd,o::T) = new(i,s,l,d,nd,o)
end

function encode{T}(msg::MyMessageType{T})
  iob = PipeBuffer()
  js = JSON.json(msg.dd)
  writeproto(iob, MyMessageType{ASCIIString}(msg.intval, msg.strval, msg.len, msg.data, msg.ndd, js)  )
  enc = takebuf_array(iob)
  return enc
end

function decode{T}(data::Vector{UInt8}, ::Type{MyMessageType{T}})
  iob = PipeBuffer(data)
  rmsg = readproto(iob, MyMessageType{ASCIIString}())  # read it back into another instance
  js = JSON.parse(rmsg.dd)
  MyMessageType{T}(rmsg.intval, rmsg.strval, rmsg.len, rmsg.data, rmsg.ndd, js)
end


function typed_callback{T}(channel::AbstractString, msg::MyMessageType{T})
  @show channel
  @show typeof(msg)
  nothing
end


function listento(MYCHAN, flag::Vector{Bool})
  lc = LCM()
  subscribe(lc, MYCHAN, typed_callback, MyMessageType{MDD})

  while flag[1]
    @time handle(lc)
  end
end

end #@everywhere



function testencdec()
  i = 10
  dd = MDD("$i" => Array(UInt8,100))
  nn = Nested(100.0-i, Array(UInt8,1000000))
  mymsg = MyMessageType{MDD}(i,"hello world",10,randn(100),nn,dd)
  enc = encode(mymsg)
  md = decode(enc, MyMessageType{MDD})
  norm(mymsg.data-md.data) < 1e-10
end


testencdec()



function publishmanymsgs(channel::AbstractString; iter::Int=100)
  lc = LCM()

  for i in 1:iter
    dd = MDD("$i" => Array(UInt8,10))
    nn = Nested(100.0-i, Array(UInt8,1000000))
    mymsg = MyMessageType{MDD}(i,"hello world",7,randn(100),nn,dd)
    @time publish(lc, channel, mymsg)
    sleep(0.0001)
  end
  nothing
end


channel = "MY_CHANNEL"


# Run listener on separate process
loopflag = Bool[true]
r = @spawn listento(channel, loopflag) # or @async for co-routine using loopflag

# sender
publishmanymsgs(channel, iter=999)

# to stop while loop
loopflag[1] = false
publishmanymsgs(channel, iter=1)















#
