using Base.Test
using LCMCore
using Base.Dates: Second
import LCMCore: encode, decode

let
    lcm = LCM()
    close(lcm)
    close(lcm)
    close(lcm)
end

let
    lcm = LCM()

    did_check = false
    data = UInt8[1,2,3,4,5]
    channel = "CHANNEL_1"
    function check_data(c, d)
        did_check = true
        @test c == channel
        @test d == data
    end
    subscribe(lcm, channel, check_data)
    publish(lcm, channel, data)
    handle(lcm)
    @test did_check
end

let
    lcm = LCM()

    data = UInt8[1,2,3,4,5]
    channel = "CHANNEL_1"
    function check_data(c, d)
        did_check = true
        @test c == channel
        @test d == data
    end
    subscribe(lcm, channel, check_data)
    @async handle(lcm)
    publish(lcm, channel, data)
end

type MyMessage
    field1::Int32
    field2::Float64
end

function encode(msg::MyMessage)
    buf = IOBuffer()
    write(buf, hton(msg.field1))
    write(buf, hton(msg.field2))
    buf.data
end

function decode(data, msg::Type{MyMessage})
    buf = IOBuffer(data)
    MyMessage(ntoh(read(buf, Int32)), ntoh(read(buf, Float64)))
end

let
    lcm = LCM()
    msg = MyMessage(23, 1.234)
    did_check = false
    channel = "CHANNEL_2"
    function check_data(c, d)
        did_check = true
        @test d.field1 == msg.field1
        @test d.field2 == msg.field2
    end
    subscribe(lcm, channel, check_data, MyMessage)
    publish(lcm, channel, msg)
    handle(lcm, Second(1))
    @test did_check

    # Test handle() with a timeout when there's no message available
    did_check = false
    handle(lcm, Second(1))
    @test did_check == false
end
