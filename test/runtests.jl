using Base.Test
using LCMCore

@testset "construct and close" begin
    lcm = LCM()
    close(lcm)
end
