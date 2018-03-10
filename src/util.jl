# reversedimindices (for conversion from row-major to column-major and vice versa)
struct ReverseDimIndices{C<:CartesianIndices}
    revcartinds::C
    length::Int
    ReverseDimIndices(revcartinds::C) where {C<:CartesianIndices} = new{C}(revcartinds, length(revcartinds))
end
ReverseDimIndices(A::AbstractArray) = ReverseDimIndices(CartesianIndices(reverse(size(A))))

Base.start(inds::ReverseDimIndices{N}) where {N} = 1
function Base.next(inds::ReverseDimIndices{N}, state::Int) where N
    ind = CartesianIndex(reverse(inds.revcartinds[state].I))
    ind, state + 1
end
Base.done(inds::ReverseDimIndices, state::Int) = state > inds.length
Base.length(inds::ReverseDimIndices) = inds.length

reversedimindices(A::AbstractArray) = ReverseDimIndices(A)

# reversedims (for StaticArrays)
reversedims(A::StaticVector) = A
reversedims(A::StaticMatrix) = transpose(A)
# TODO: higher dimensions
