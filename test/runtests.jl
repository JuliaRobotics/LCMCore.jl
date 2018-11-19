using Test
using LCMCore
using StaticArrays
using Dates: Second, Millisecond
using FileWatching: poll_fd
import LCMCore: encode, decode

include("mymessage.jl")

@testset "close multiple times" begin
    lcm = LCM()
    close(lcm)
    close(lcm)
    close(lcm)
end

@testset "isgood" begin
    lcm = LCM()
    @test isgood(lcm)
    close(lcm)
    @test !isgood(lcm)
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
        did_check = true
    end
    sub = subscribe(lcm, channel, check_data)
    @test set_queue_capacity(sub, 1)
    fd = filedescriptor(lcm)
    publish(lcm, channel, UInt8[1,2,3])
    publish(lcm, channel, UInt8[1,2,3,4])

    # Subscription capacity is 1, so the queue should only have 1 message
    # even though we published twice
    @test LCMCore.get_queue_size(sub) == 1

    # Handle the 1 message in queue and verify that the queue is now empty
    LCMCore.lcm_handle(lcm)
    @test did_check
    @test LCMCore.get_queue_size(sub) == 0

    # We published twice and handled once. Because the queue capacity is only
    # 1, there should not be another message available to read.
    event = poll_fd(fd, 1; readable=true)
    @show event
    @test !event.readable
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
    @test LCMCore.get_queue_size(sub) == 2
    LCMCore.lcm_handle(lcm)
    @test did_check

    # We published twice and handled once. The queue capacity is 2, so
    # there should be another message available to read.
    @test LCMCore.get_queue_size(sub) == 1
    event = poll_fd(fd, 1; readable=true)
    @test event.readable

    # Now we handle the second message in the queue
    did_check = false
    LCMCore.lcm_handle(lcm)
    @test did_check

    # Now we've exhausted the queue, so there should be no more messages
    # available to read
    @test LCMCore.get_queue_size(sub) == 0
    event = poll_fd(fd, 1; readable=true)
    @test !event.readable
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

@testset "UDP ports" begin
    lcm1 = LCM("udpm://239.255.76.67:7667")
    lcm2 = LCM("udpm://239.255.76.67:7668")

    channel = "FOO"
    did_callback1 = false
    function callback1(channel, data)
        @test data == UInt8[1, 2, 3]
        did_callback1 = true
    end
    did_callback2 = false
    function callback2(channel, data)
        @test data == UInt8[1, 2, 3, 4]
        did_callback2 = true
    end
    subscribe(lcm1, channel, callback1)
    subscribe(lcm2, channel, callback2)
    publish(lcm1, channel, UInt8[1,2,3])
    handle(lcm1, Millisecond(100))
    handle(lcm2, Millisecond(100))
    @test did_callback1
    @test !did_callback2

    did_callback1 = false
    did_callback2 = false
    publish(lcm2, channel, UInt8[1,2,3,4])
    handle(lcm1, Millisecond(100))
    handle(lcm2, Millisecond(100))
    @test !did_callback1
    @test did_callback2
end

@testset "lcm_handle allocations" begin
    data = UInt8[1,2,3,4,5]
    channel = "CHANNEL_1"

    # start listening
    sublcm = LCM()
    sub = subscribe(sublcm, channel, (c, d) -> nothing)
    set_queue_capacity(sub, 2)

    # publish two messages
    publcm = LCM()
    for _ = 1 : 2
        publish(publcm, channel, data)
    end

    # check that handling doesn't allocate
    LCMCore.lcm_handle(sublcm)
    allocs = @allocated LCMCore.lcm_handle(sublcm)
    @test allocs == 0
end

include("test_lcmtype.jl")
include("test_readlog.jl")
