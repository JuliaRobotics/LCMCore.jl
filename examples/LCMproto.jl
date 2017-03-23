# This is LCMproto.jl
# https://github.com/Netflix/SimianArmy/wiki/Chaos-Monkey

addprocs(1)
@everywhere begin
using ProtoBuf
using LCMCore
using JSON

import LCMCore: encode, decode


type Nested
  more::Float64
end

abstract DoubleWammy{T}

type MyMessageType{T} <: DoubleWammy{T}  # a Julia composite type
 intval::Int                             # probably generated from protoc
 strval::ASCIIString
 len::Int64
 data::Vector{UInt8}
 # ndd::Nested
 dd::T
 MyMessageType() = new()
 MyMessageType(i,s,l,d,o) = new(i,s,l,d,o)
end
# Dict{ASCIIString,Vector{Float64}}


# MyMessageType(10, "hello world")

function encode{T}(msg::MyMessageType{T})
  iob = PipeBuffer()
  js = JSON.json(msg.dd)
  writeproto(iob, MyMessageType{ASCIIString}(msg.intval, msg.strval, msg.len, msg.data, js)  )
  enc = takebuf_array(iob)
  return enc
end

function decode{T <: Dict}(data::Vector{UInt8}, ::Type{MyMessageType{T}})
  iob = PipeBuffer(data)
  rmsg = readproto(iob, MyMessageType{ASCIIString}())  # read it back into another instance
  js = JSON.parse(rmsg.dd)
  MyMessageType{T}(rmsg.intval, rmsg.strval, rmsg.len, rmsg.data, js)
end


function typed_callback{T}(channel::AbstractString, msg::MyMessageType{T})
    @show channel
    @show typeof(msg)
end


typealias MDD Dict{ASCIIString,Vector{Float64}}
end

@everywhere function listento(MYCHAN)
  lc = LCM()
  subscribe(lc, MYCHAN, typed_callback, MyMessageType{MDD})

  flag = Bool[true]
  @async begin
  while flag[1]
      @time handle(lc)
  end
  end
end


r = @spawn listento("MY_CHANNEL")

lc = LCM()

for i in 1:1000
  dd = MDD("$i" => randn(100))
  mymsg = MyMessageType{MDD}(i,"hello world",1000000,Array(UInt8,1000000),dd)
  # nn = Nested(100.0-i, Dict{AbstractString,Vector{Float64}}("$i" => randn(10)))
  # mymsg = MyMessageType(i,"hello world",100,Array(UInt8,100),nn)
  @time publish(lc, "MY_CHANNEL", mymsg)
  sleep(0.0001)
end


flag[1] = false



# Some testing
i = 10
dd = MDD("$i" => randn(10))
# nn = Nested(100.0-i, dd)
mymsg = MyMessageType{MDD}(i,"hello world",100,Array(UInt8,100),dd)


enc = encode(mymsg)

md = decode(enc, MyMessageType{MDD})
