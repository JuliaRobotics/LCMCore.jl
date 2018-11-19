using LCMCore
using Test
using Random
using StaticArrays
using FastIOBuffers: FastReadBuffer, FastWriteBuffer, setdata!

include(joinpath(@__DIR__, "lcmtypes", "lcmtesttypes.jl"))

function test_encode_decode(::Type{T}) where T<:LCMType
    for i = 1 : 100
        in = rand(T)
        bytes = encode(in)::Vector{UInt8}
        out = decode(bytes, T)
        @test in == out
    end
end

function test_in_place_decode_noalloc(::Type{T}) where T<:LCMType
    in = rand(T)
    bytes = encode(in)
    out = deepcopy(in)
    decodestream = FastReadBuffer()
    setdata!(decodestream, bytes)
    decode!(out, decodestream)
    allocs = @allocated begin
        setdata!(decodestream, bytes)
        decode!(out, decodestream)
    end
    @test allocs == 0
end

function test_in_place_encode_noalloc(::Type{T}) where T<:LCMType
    in = rand(T)
    encodestream = FastWriteBuffer()
    encode(encodestream, in)
    take!(encodestream)
    allocs = @allocated encode(encodestream, in)
    @test allocs == 0
end

@testset "LCMType" begin
    using .lcmtesttypes
    Random.seed!(1)

    # Check base hashes (obtained from lcm-gen --debug; note that hash reported by lcm-gen is a **signed** integer (despite the 0x prefix))
    @test LCMCore.basehash(lcm_test_type_1) == 0x6ac981fb91a46d8b
    @test LCMCore.basehash(lcm_test_type_3) == 0x394ce5f0e401c325
    @test LCMCore.basehash(lcm_test_type_2) == 0x5a53eae01a55d4cb

    # Check invertibility
    test_encode_decode(lcm_test_type_1)
    test_encode_decode(lcm_test_type_2)
    test_encode_decode(lcm_test_type_3)
    test_encode_decode(polynomial_t)
    test_encode_decode(polynomial_matrix_t)

    # Check that decoding types without `String`s doesn't allocate
    test_in_place_decode_noalloc(lcm_test_type_1)
    test_in_place_decode_noalloc(lcm_test_type_2)
    test_in_place_decode_noalloc(polynomial_t)
    test_in_place_decode_noalloc(polynomial_matrix_t)

    # Check that encoding types doesn't allocate
    test_in_place_encode_noalloc(lcm_test_type_1)
    test_in_place_encode_noalloc(lcm_test_type_2)
    test_in_place_encode_noalloc(lcm_test_type_3)
    test_in_place_encode_noalloc(polynomial_t)
    test_in_place_encode_noalloc(polynomial_matrix_t)

    # Mismatch between length field and length of corresponding vector
    bad = rand(lcm_test_type_1)
    bad.blength += 1
    @test_throws DimensionMismatch encode(bad)

    # Bad fingerprint
    in = rand(lcm_test_type_1)
    badbytes = encode(in)
    badbytes[1] += 0x01
    @test_throws LCMCore.FingerprintException decode(badbytes, lcm_test_type_1)

    # Test against byte blobs that were encoded using pylcm
    for lcmt in [lcm_test_type_1, lcm_test_type_2, lcm_test_type_3, polynomial_t, polynomial_matrix_t]
        bytes = read(joinpath(@__DIR__, "lcmtypes", string(lcmt.name.name) * "_example_bytes"))
        @test hard_coded_example(lcmt) == decode(bytes, lcmt)
    end

    # resize!
    lcmt2 = lcm_test_type_2()
    lcmt2.dlength = 5
    lcmt2.f_inner_length = 2
    resize!(lcmt2)
    @test length(lcmt2.d) == 5
    @test size(lcmt2.f) == (3, 2)
    d = lcmt2.d
    f = lcmt2.f
    resize!(lcmt2)
    @test d === lcmt2.d
    @test f === lcmt2.f
end

@testset "LCMType: handle" begin
    channel = "CHANNEL_1"
    msg = rand(lcm_test_type_1)

    # start listening
    sublcm = LCM()
    check_msg = let expected = msg
        (channel, msg) -> @test(msg == expected)
    end
    sub = subscribe(sublcm, channel, check_msg, lcm_test_type_1)
    set_queue_capacity(sub, 2)

    # publish two messages
    publcm = LCM()
    for _ = 1 : 2
        publish(publcm, channel, msg)
    end

    # handle
    LCMCore.lcm_handle(sublcm)
end
