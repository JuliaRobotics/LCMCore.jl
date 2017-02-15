using Base.Test
using LCMCore
using Base.Dates: Second
import LCMCore: encode, decode

@testset "close multiple times" begin
    lcm = LCM()
    close(lcm)
    close(lcm)
    close(lcm)
end

@testset "publish raw data" begin
    LCM() do lcm
        publish(lcm, "CHANNEL_0", UInt8[1,2,3,4])
    end
end


@testset "publish and subscribe" begin
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

@testset "async publish and subscribe" begin
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

@testset "encode and decode" begin
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

@testset "queue capacity 1" begin
    lcm = LCM()

    did_check = false
    channel = "CHANNEL_1"
    function check_data(c, d)
        @show d
        did_check = true
    end
    sub = subscribe(lcm, channel, check_data)
    @test set_queue_capacity(sub, 1)
    fd = filedescriptor(lcm)
    publish(lcm, channel, UInt8[1,2,3])
    publish(lcm, channel, UInt8[1,2,3,4])
    LCMCore.lcm_handle(lcm)
    @test did_check

    event = poll_fd(fd, 1; readable=true)
    # We published twice and handled once. Because the queue capacity is only
    # 1, there should not be another message available to read.
    # However, queue size is actually off by one in LCM:
    # https://github.com/lcm-proj/lcm/issues/167
    # so this test won't pass.
    # @test !event.readable
end

@testset "queue capacity 2" begin
    lcm = LCM()

    did_check = false
    channel = "CHANNEL_1"
    function check_data(c, d)
        did_check = true
    end
    sub = subscribe(lcm, channel, check_data)
    set_queue_capacity(sub, 2)
    fd = filedescriptor(lcm)
    publish(lcm, channel, UInt8[1,2,3,4,5])
    publish(lcm, channel, UInt8[1,2,3,4,5])
    LCMCore.lcm_handle(lcm)
    @test did_check

    # We published twice and handled once. The queue capacity is 2, so
    # there should be another message available to read.
    # This will pass despite https://github.com/lcm-proj/lcm/issues/167
    # because that bug causes the queue size to actually be 3 instead of 2.
    # In either case, fd will be readable. 
    event = poll_fd(fd, 1; readable=true)
    @test event.readable
end

@testset "unsubscribe" begin
    lcm = LCM()

    channel = "FOO"
    did_callback1 = false
    function callback1(channel, data)
        did_callback1 = true
    end
    did_callback2 = false
    function callback2(channel, data)
        did_callback2 = true
    end
    sub1 = subscribe(lcm, channel, callback1)
    unsubscribe(lcm, sub1)
    sub2 = subscribe(lcm, channel, callback2)
    publish(lcm, channel, UInt8[1,2,3])
    handle(lcm)

    @test !did_callback1
    @test did_callback2
end
