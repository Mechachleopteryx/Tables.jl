Base.@pure function nondatavaluenamedtuple(::Type{NT}) where {NT <: NamedTuple{names}} where {names}
    TT = Tuple{Any[ DataValueInterfaces.nondatavaluetype(fieldtype(NT, i)) for i = 1:fieldcount(NT) ]...}
    return NamedTuple{names, TT}
end

Base.@pure function datavaluenamedtuple(::Tables.Schema{names, types}) where {names, types}
    TT = Tuple{Any[ DataValueInterfaces.datavaluetype(fieldtype(types, i)) for i = 1:fieldcount(types) ]...}
    return NamedTuple{names, TT}
end

# IteratorWrapper takes an input Row iterators, it will unwrap any DataValue elements as plain Union{T, Missing}
struct IteratorWrapper{S}
    x::S
end

nondatavaluerows(x) = IteratorWrapper(IteratorInterfaceExtensions.getiterator(x))
Tables.istable(::Type{<:IteratorWrapper}) = true
Tables.rowaccess(::Type{<:IteratorWrapper}) = true
Tables.rows(x::IteratorWrapper) = x

function Tables.schema(dv::IteratorWrapper)
    eT = eltype(dv.x)
    (!(eT <: NamedTuple) || eT === Union{}) && return schema(dv.x)
    return Tables.Schema(nondatavaluenamedtuple(eT))
end

Base.IteratorEltype(::Type{IteratorWrapper{S}}) where {S} = Base.IteratorEltype(S)
Base.eltype(rows::IteratorWrapper) = IteratorRow{eltype(rows.x)}
Base.IteratorSize(::Type{IteratorWrapper{S}}) where {S} = Base.IteratorSize(S)
Base.length(rows::IteratorWrapper) = length(rows.x)
Base.size(rows::IteratorWrapper) = size(rows.x)

@noinline invalidtable(::T, ::S) where {T, S} = throw(ArgumentError("'$T' iterates '$S' values, which don't satisfy the Tables.jl Row-iterator interface"))

@inline function Base.iterate(rows::IteratorWrapper)
    x = iterate(rows.x)
    x === nothing && return nothing
    row, st = x
    propertynames(row) === () && invalidtable(rows.x, row)
    return IteratorRow(row), st
end

@inline function Base.iterate(rows::IteratorWrapper, st)
    x = iterate(rows.x, st)
    x === nothing && return nothing
    row, st = x
    return IteratorRow(row), st
end

struct IteratorRow{T}
    row::T
end

@inline function Base.getproperty(d::IteratorRow, ::Type{T}, col::Int, nm::Symbol) where {T}
    x = getproperty(getfield(d, 1), T, col, nm)
    return convert(DataValueInterfaces.nondatavaluetype(typeof(x)), x)
end
@inline function Base.getproperty(d::IteratorRow, nm::Symbol)
    x = getproperty(getfield(d, 1), nm)
    return convert(DataValueInterfaces.nondatavaluetype(typeof(x)), x)
end
Base.propertynames(d::IteratorRow) = propertynames(getfield(d, 1))

# DataValueRowIterator wraps a Row iterator and will wrap `Union{T, Missing}` typed fields in DataValues
struct DataValueRowIterator{NT, S}
    x::S
end

function datavaluerows(x)
    r = Tables.rows(x)
    s = Tables.schema(r)
    s === nothing && error("Schemaless sources cannot be passed to datavaluerows.")
    return DataValueRowIterator{datavaluenamedtuple(s), typeof(r)}(r)
end

Base.eltype(rows::DataValueRowIterator{NT, S}) where {NT, S} = NT
Base.IteratorSize(::Type{DataValueRowIterator{NT, S}}) where {NT, S} = Base.IteratorSize(S)
Base.length(rows::DataValueRowIterator) = length(rows.x)
Base.size(rows::DataValueRowIterator) = size(rows.x)

# struct DataValueRow{NT, T}
#     x::T
# end
# DataValueRow{NT}(x::T) where {NT, T} = DataValueRow{NT, T}(x)

# @inline function Base.iterate(rows::DataValueRowIterator{NT}) where {NT}
#     x = iterate(rows.x)
#     x === nothing && return nothing
#     row, st = x
#     return DataValueRow{NT}(row), st
# end

# @inline function Base.iterate(rows::DataValueRowIterator{NT}, st) where {NT}
#     x = iterate(rows.x, st)
#     x === nothing && return nothing
#     row, st = x
#     return DataValueRow{NT}(row), st
# end

# @inline function Base.getproperty(d::DataValueRow{NT}, nm::Symbol) where {NT}
#     x = getproperty(getfield(d, 1), nm)
#     return convert(fieldtype(NT, nm), x)
# end
# Base.propertynames(d::DataValueRow) = propertynames(getfield(d, 1))

@inline function Base.iterate(rows::DataValueRowIterator{NT, S}, st=()) where {NT <: NamedTuple{names}, S} where {names}
    if @generated
        vals = Tuple(:(convert($(fieldtype(NT, i)), getproperty(row, $(DataValueInterfaces.nondatavaluetype(fieldtype(NT, i))), $i, $(Meta.QuoteNode(names[i]))))) for i = 1:fieldcount(NT))
        q = quote
            Base.@_inline_meta
            x = iterate(rows.x, st...)
            x === nothing && return nothing
            row, st = x
            return $NT(($(vals...),)), (st,)
        end
        # @show q
        return q
    else
        x = iterate(rows.x, st...)
        x === nothing && return nothing
        row, st = x
        return NT(Tuple(convert(fieldtype(NT, i), getproperty(row, DataValueInterfaces.nondatavaluetype(fieldtype(NT, i)), i, names[i])) for i = 1:fieldcount(NT))), (st,)
    end
end
