# testing ccall of LCM log file handling

## Not repeating the definitions from earlier in the runtests.jl file
# using Base: Test
# using LCMCore
#
# import LCMCore: encode, decode
#
# mutable struct MyMessage
#     field1::Int32
#     field2::Float64
# end
#
# function encode(msg::MyMessage)
#     buf = IOBuffer()
#     write(buf, hton(msg.field1))
#     write(buf, hton(msg.field2))
#     buf.data
# end
#
# function decode(data, msg::Type{MyMessage})
#     buf = IOBuffer(data)
#     MyMessage(ntoh(read(buf, Int32)), ntoh(read(buf, Float64)))
# end

compare(a::MyMessage, b::MyMessage; tol::Float64=1e-14) = a.field1 == b.field1 && abs(a.field2 - b.field2) < tol

function handledata(channel, msgdata, groundtruth)
  msg = decode(msgdata, MyMessage)
  @test compare(groundtruth, msg)
  nothing
end

function handletype(channel, msg, groundtruth)
  @test compare(groundtruth, msg)
  nothing
end

function handlefile(lcl; N=1)
  for i in 1:N
    handle(lcl) ? nothing : break
  end
  nothing
end

function foroverrun()
  # record a temporary log file
  lcmlogdir = joinpath(dirname(@__FILE__),"testdata","testlog.lcm")

  # recreate the messages locally for comparison with those in the test log file
  msg1 = MyMessage(23, 1.234)
  msg2 = MyMessage(24, 2.345)

  lc = LCMLog(lcmlogdir)
  subscribe(lc, "CHANNEL_1", (c, d) -> handledata(c, d, msg1) )
  subscribe(lc, "CHANNEL_2", (c, m) -> handletype(c, m, msg2), MyMessage)
  # Consume the log file
  handlefile(lc, N=100)
  @test true
  close(lc)
  nothing
end

function whilestyle()
  # record a temporary log file
  lcmlogdir = joinpath(dirname(@__FILE__),"testdata","testlog.lcm")

  # recreate the messages locally for comparison with those in the test log file
  msg1 = MyMessage(23, 1.234)
  msg2 = MyMessage(24, 2.345)

  lc = LCMLog(lcmlogdir)
  subscribe(lc, "CHANNEL_1", (c, d) -> handledata(c, d, msg1) )
  subscribe(lc, "CHANNEL_2", (c, m) -> handletype(c, m, msg2), MyMessage)
  # Consume the log file
  while handle(lc); end
  @test true
  close(lc)
  nothing
end

@testset "reading LCM log directly" begin
  foroverrun()
  whilestyle()
  @test_throws ArgumentError LCMLog("doesnt.exs")
end

# Test for issue #56
using LCMCore, CaesarLCMTypes
using JSON
@testset "Encode/decode issue #56" begin
    function handleData(channel, msg::image_metadata_t, msgs)
        @show msg
        push!(msgs, msg)
    end

    msgs = []
    lcmlogdir = joinpath(dirname(@__FILE__),"testdata","image_metadata_log.lcm")
    lc = LCMLog(lcmlogdir)
    LCMCore.subscribe(lc, "CHANNEL_1", (c, d) -> handleData(c, d, msgs), image_metadata_t)

    # Run while there is data
    while handle(lc)
    end
    close(lc)
    # If this works then the encode/decode issue is resolved
    @test length(msgs) > 0
end

## Code used to create the image_metadata_log.lcm LCM log file used in this test
# using CaesarLCMTypes
# lc = LCM()
# msg1 = image_metadata_t("KEY1", 0, [])
# # run `lcm-logger testlog.lcm`
# LCMCore.publish(lc, "CHANNEL_1", msg1)
# LCMCore.publish(lc, "CHANNEL_1", msg1)
# # terminate lcm-logger
# LCMCore.close(lc)
