# test lcmgenjl functions

@testset "lcmgenjl auto-generated code test" begin

lcmtypefilepath = joinpath(dirname(@__FILE__), "lcmtypes", "example_t.lcm")
lcm2jlfile, = lcmgenjl(lcmtypefilepath)
include(lcm2jlfile)

# test message encoding and decoding
msg = Example_t()

msg.timestamp = 0
msg.position = (1,2,3)
msg.orientation = (1,0,0,0)
msg.ranges = Int16.(collect(0:14))
msg.num_ranges = length(msg.ranges)
msg.name = "example string"
msg.enabled = true


data = encode(msg)
msgr = decode(data, Example_t)

@test msg.timestamp == msgr.timestamp
@test msg.position == msgr.position
@test msg.orientation == msgr.orientation
@test msg.ranges == msgr.ranges
@test msg.num_ranges == msgr.num_ranges
@test msg.name == msgr.name
@test msg.enabled == msgr.enabled

end





#
# function callback(channel, msgdata)
#   # @show msgdata
#   @time msg = decode(msgdata, Example_t)
#   nothing
# end
#
# lcm = LCM()
# subsc = subscribe(lcm, "EXAMPLE", callback)
#
# println("waiting...")
# handle(lcm)
#
# unsubscribe(lcm, subsc)
#
#
#
#
# function typed_callback(channel::String, msg::Example_t)
#   @show msg
#   nothing
# end
#
# lcm = LCM()
# subsc = subscribe(lcm, "EXAMPLE", typed_callback, Example_t)
#
# println("waiting...")
# handle(lcm)
#
# unsubscribe(lcm, subsc)
#


#
