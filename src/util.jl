# reversedimindices (for conversion from row-major to column-major and vice versa)
struct ReverseDimIndices{C<:CartesianIndices}
    revcartinds::C
    length::Int
    ReverseDimIndices(revcartinds::C) where {C<:CartesianIndices} = new{C}(revcartinds, length(revcartinds))
end
ReverseDimIndices(A::AbstractArray) = ReverseDimIndices(CartesianIndices(reverse(size(A))))

function Base.iterate(inds::ReverseDimIndices{N}, state::Int=1) where {N}
    if state > inds.length
        return nothing
    end
    ind = CartesianIndex(reverse(inds.revcartinds[state].I))
    return ind, state + 1
end

Base.length(inds::ReverseDimIndices) = inds.length

reversedimindices(A::AbstractArray) = ReverseDimIndices(A)

# reversedims (for StaticArrays)
reversedims(A::StaticVector) = A
reversedims(A::StaticMatrix) = transpose(A)
# TODO: higher dimensions
