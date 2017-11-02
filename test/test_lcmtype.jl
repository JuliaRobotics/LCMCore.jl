using LCMCore
using Base.Test
using StaticArrays
using BufferedStreams

include("lcmtypes/lcmtesttypes.jl")

function test_encode_decode(::Type{T}) where T<:LCMType
    for i = 1 : 100
        in = rand(T)
        bytes = encode(in)::Vector{UInt8}
        out = decode(bytes, T)
        @test in == out
    end
end

function test_decode!_allocations(::Type{T}) where T<:LCMType
    in = rand(T)
    bytes = encode(in)
    out = deepcopy(in)
    decodestream = BufferedInputStream(bytes)
    decode!(out, decodestream)
    decodestream = BufferedInputStream(bytes)
    allocs = @allocated decode!(out, decodestream)
    @test allocs == 0
end

@testset "LCMType" begin
    using lcmtesttypes
    srand(1)

    # Check base hashes (obtained from lcm-gen --debug; note that hash reported by lcm-gen is a **signed** integer (despite the 0x prefix))
    @test LCMCore.base_hash(lcm_test_type_1) == 0x6ac981fb91a46d8b
    @test LCMCore.base_hash(lcm_test_type_3) == 0x394ce5f0e401c325
    @test LCMCore.base_hash(lcm_test_type_2) == 0x5a53eae01a55d4cb

    # Check invertibility
    test_encode_decode(lcm_test_type_1)
    test_encode_decode(lcm_test_type_2)
    test_encode_decode(lcm_test_type_3)

    # Check that decoding types without `String`s doesn't allocate
    test_decode!_allocations(lcm_test_type_1)
    test_decode!_allocations(lcm_test_type_2)

    # Mismatch between length field and length of corresponding vector
    bad = rand(lcm_test_type_1)
    bad.blength += 1
    @test_throws AssertionError encode(bad)

    # Bad fingerprint
    in = rand(lcm_test_type_1)
    badbytes = encode(in)
    badbytes[1] += 0x01
    @test_throws LCMCore.FingerprintException decode(badbytes, lcm_test_type_1)

    # Test against byte blobs that were encoded using pylcm
    bytes = read(Pkg.dir("LCMCore", "test", "lcmtypes", "lcm_test_type_1_example_bytes"))
    @test hard_coded_example(lcm_test_type_1) == decode(bytes, lcm_test_type_1)
    bytes = read(Pkg.dir("LCMCore", "test", "lcmtypes", "lcm_test_type_2_example_bytes"))
    @test hard_coded_example(lcm_test_type_2) == decode(bytes, lcm_test_type_2)
    bytes = read(Pkg.dir("LCMCore", "test", "lcmtypes", "lcm_test_type_3_example_bytes"))
    @test hard_coded_example(lcm_test_type_3) == decode(bytes, lcm_test_type_3)
end
