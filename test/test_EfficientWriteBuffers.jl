module EfficientWriteBuffersTest

using Test
using Random
using LCMCore: EfficientWriteBuffers.EfficientWriteBuffer

@testset "bitstype numbers" begin
    for T = [Int8,UInt8,Int16,UInt16,Int32,UInt32,Int64,UInt64,Int128,UInt128,Float16,Float32,Float64]
        buf = EfficientWriteBuffer()
        @test buf.position[] == 0
        for i = 1 : 2
            x = rand(T)
            @test write(buf, x)::Int == Core.sizeof(x)
            @test buf.position[] == Core.sizeof(x)
            allocs = @allocated(write(buf, x))
            if i > 1
                @test allocs == 0
            end
            bytes = take!(buf)
            readbuf = IOBuffer(bytes)
            for _ = 1 : 2
                xback = read(readbuf, T)
                @test xback == x
            end
        end
        @test eof(buf)
    end
end

@testset "strings" begin
    rng = MersenneTwister(1)
    buf = EfficientWriteBuffer()
    for i = 1 : 2
        take!(buf)
        str = randstring(rng, 8)
        allocs = @allocated write(buf, str)
        if i > 1
            @test allocs == 0
        end
    end

    buf = EfficientWriteBuffer()
    for i = 1 : 1000
        str = randstring(rng, 8)
        @test write(buf, str)::Int == sizeof(str)
        write(buf, str)
        strstr = String(take!(buf))
        @test strstr == str * str
    end
end

end
