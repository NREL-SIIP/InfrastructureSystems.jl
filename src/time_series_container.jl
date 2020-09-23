struct TimeSeriesKey
    time_series_type::Type{<:TimeSeriesMetadata}
    label::String
end

const TimeSeriesByType = Dict{TimeSeriesKey, TimeSeriesMetadata}

"""
Time series container for a component.
"""
mutable struct TimeSeriesContainer
    data::TimeSeriesByType
    time_series_storage::Union{Nothing, TimeSeriesStorage}
end

function TimeSeriesContainer()
    return TimeSeriesContainer(TimeSeriesByType(), nothing)
end

Base.length(container::TimeSeriesContainer) = length(container.data)
Base.isempty(container::TimeSeriesContainer) = isempty(container.data)

function set_time_series_storage!(
    container::TimeSeriesContainer,
    storage::Union{Nothing, TimeSeriesStorage},
)
    if !isnothing(container.time_series_storage) && !isnothing(storage)
        throw(ArgumentError(
            "The time_series_storage reference is already set. Is this component being " *
            "added to multiple systems?",
        ))
    end

    container.time_series_storage = storage
end

function add_time_series!(
    container::TimeSeriesContainer,
    time_series::T;
    skip_if_present = false,
) where {T <: TimeSeriesMetadata}
    key = TimeSeriesKey(T, get_label(time_series))
    if haskey(container.data, key)
        if skip_if_present
            @warn "time_series $key is already present, skipping overwrite"
        else
            throw(ArgumentError("time_series $key is already stored"))
        end
    else
        container.data[key] = time_series
    end
end

function remove_time_series!(
    ::Type{T},
    container::TimeSeriesContainer,
    label::AbstractString,
) where {T <: TimeSeriesMetadata}
    key = TimeSeriesKey(T, label)
    if !haskey(container.data, key)
        throw(ArgumentError("time_series $key is not stored"))
    end

    pop!(container.data, key)
end

function clear_time_series!(container::TimeSeriesContainer)
    empty!(container.data)
end

function get_time_series(
    ::Type{T},
    container::TimeSeriesContainer,
    label::AbstractString,
) where {T <: TimeSeriesMetadata}
    key = TimeSeriesKey(T, label)
    if !haskey(container.data, key)
        throw(ArgumentError("time_series $key is not stored"))
    end

    return container.data[key]
end

function get_time_series_initial_times(ts_metadata::TimeSeriesMetadata)
    initial_time_stamp = get_initial_time_stamp(ts_metadata)
    interval = get_interval(ts_metadata)
    count = get_count(ts_metadata)
    return collect(range(initial_time_stamp; length = count, step = interval))
end

function get_time_series_initial_times(container::TimeSeriesContainer)
    ts_metadata = first(values(container.data))
    return get_time_series_initial_times(ts_metadata)
end

function get_time_series_initial_times(
    ::Type{T},
    container::TimeSeriesContainer,
) where {T <: TimeSeriesMetadata}
    for (key, ts_metadata) in keys(container.data)
        if key.time_series_type <: T
            return get_time_series_initial_times(ts_metadata)
        end
    end
    return Vector{Dates.DateTime}()
end

function get_time_series_initial_times(
    ::Type{T},
    container::TimeSeriesContainer,
    label::AbstractString,
) where {T <: TimeSeriesMetadata}
    ts_metadata = get(container.data, TimeSeriesKey(T, label), nothing)
    if ts_metadata === nothing
        return Vector{Dates.DateTime}()
    else
        return get_time_series_initial_times(ts_metadata)
    end
end

function get_time_series_initial_times!(
    initial_times::Set{Dates.DateTime},
    container::TimeSeriesContainer,
)
    for ts_medatadata in values(container.data)
        push!(initial_times, get_time_series_initial_times(ts_medatadata)...)
    end
end

function get_time_series_labels(
    ::Type{T},
    container::TimeSeriesContainer,
) where {T <: TimeSeriesMetadata}
    labels = Set{String}()
    for key in keys(container.data)
        if key.time_series_type <: T
            push!(labels, key.label)
        end
    end

    return Vector{String}(collect(labels))
end

function serialize(container::TimeSeriesContainer)
    # Store a flat array of time series. Deserialization can unwind it.
    return serialize_struct.(values(container.data))
end

function deserialize(::Type{TimeSeriesContainer}, data::Vector)
    container = TimeSeriesContainer()
    for ts_dict in data
        type = get_type_from_serialization_metadata(get_serialization_metadata(ts_dict))
        time_series = deserialize(type, ts_dict)
        add_time_series!(container, time_series)
    end

    return container
end