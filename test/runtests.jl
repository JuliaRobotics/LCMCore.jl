using Base.Test
using LCMCore

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
