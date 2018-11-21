mutable struct image_metadata_t <: LCMType
    key::String
    n::Int32
    value::Vector{UInt8}
end

@lcmtypesetup(image_metadata_t,
    value => (n,)
)
