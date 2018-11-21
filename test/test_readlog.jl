function compare(a::MyMessage, b::MyMessage; tol::Float64=1e-14)
    a.field1 == b.field1 && isapprox(a.field2, b.field2, atol=tol)
end

function handle_file(lcmlog::LCMLog; N=1)
    for i in 1 : N
        handle(lcmlog) || break
    end
    nothing
end

function make_test_lcmlog()
    # record a temporary log file
    lcmlogdir = joinpath(@__DIR__, "testdata", "testlog.lcm")

    # recreate the messages locally for comparison with those in the test log file
    msg1 = MyMessage(23, 1.234)
    msg2 = MyMessage(24, 2.345)

    lcmlog = LCMLog(lcmlogdir)
    subscribe(lcmlog, "CHANNEL_1", (channel, data) -> @test(compare(decode(data, MyMessage), msg1)))
    subscribe(lcmlog, "CHANNEL_2", (channel, msg) -> @test(compare(msg, msg2)), MyMessage)
    lcmlog
end

@testset "LCM log overrun" begin
    lcmlog = make_test_lcmlog()
    handle_file(lcmlog, N=100)
    close(lcmlog)
end

@testset "Read until end" begin
    lcmlog = make_test_lcmlog()
    while handle(lcmlog); end
    close(lcmlog)
end

# Test for issue #56
include(joinpath(dirname(@__FILE__), "lcmtypes", "image_metadata_t.jl"))
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
    # Assert - should be 2 messages
    @test length(msgs) == 2
end

## Code used to create the testlog.lcm LCM log file used in this test
# lcm = LCM()
# msg1 = MyMessage(23, 1.234)
# msg2 = MyMessage(24, 2.345)
# # run `lcm-logger testlog.lcm`
# publish(lcm, "CHANNEL_1", msg1)
# publish(lcm, "CHANNEL_2", msg2)
# # terminate lcm-logger
# close(lcm)
