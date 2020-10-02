"""
Construct Deterministic from a SortedDict of Arrays.

# Arguments
- `name::AbstractString`: user-defined name
- `input_data::AbstractDict{Dates.DateTime, Vector{Float64}}`: time series data.
- `resolution::Dates.Period`: The resolution of the forecast in Dates.Period`
- `normalization_factor::NormalizationFactor = 1.0`: optional normalization factor to apply
  to each data entry
- `scaling_factor_multiplier::Union{Nothing, Function} = nothing`: If the data are scaling
  factors then this function will be called on the component and applied to the data when
  [`get_time_series_array`](@ref) is called.
"""
function Deterministic(
    name::AbstractString,
    input_data::AbstractDict{Dates.DateTime, Vector{Float64}};
    resolution::Dates.Period,
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    if !isa(input_data, SortedDict)
        input_data = SortedDict(input_data...)
    end
    data = handle_normalization_factor(input_data, normalization_factor)
    initial_timestamp = first(keys(data))
    horizon = length(first(values(data)))
    return Deterministic(
        name,
        initial_timestamp,
        horizon,
        resolution,
        data,
        scaling_factor_multiplier,
    )
end

"""
Construct Deterministic from a Dict of TimeArrays.

# Arguments
- `name::AbstractString`: user-defined name
- `input_data::AbstractDict{Dates.DateTime, TimeSeries.TimeArray}`: time series data.
- `normalization_factor::NormalizationFactor = 1.0`: optional normalization factor to apply
  to each data entry
- `scaling_factor_multiplier::Union{Nothing, Function} = nothing`: If the data are scaling
  factors then this function will be called on the component and applied to the data when
  [`get_time_series_array`](@ref) is called.
- `timestamp = :timestamp`: If the values are DataFrames is passed then this must be the column name that
  contains timestamps.
"""
function Deterministic(
    name::AbstractString,
    input_data::AbstractDict{Dates.DateTime, <:TimeSeries.TimeArray};
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    data = SortedDict{Dates.DateTime, Vector{Float64}}()
    resolution =
        TimeSeries.timestamp(first(values(input_data)))[2] -
        TimeSeries.timestamp(first(values(input_data)))[1]
    for (k, v) in input_data
        if length(size(v)) > 1
            throw(ArgumentError("TimeArray with timestamp $k has more than one column)"))
        end
        data[k] = TimeSeries.values(v)
    end

    return Deterministic(
        name,
        data;
        resolution = resolution,
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

"""
Construct Deterministic from a Dict of collections of data.

# Arguments
- `name::AbstractString`: user-defined name
- `input_data::AbstractDict{Dates.DateTime, TimeSeries.TimeArray}`: time series data. The values in the dictionary should be able to be converted to Float64
- `resolution::Dates.Period`: The resolution of the forecast in Dates.Period`
- `normalization_factor::NormalizationFactor = 1.0`: optional normalization factor to apply
  to each data entry
- `scaling_factor_multiplier::Union{Nothing, Function} = nothing`: If the data are scaling
  factors then this function will be called on the component and applied to the data when
  [`get_time_series_array`](@ref) is called.
"""
function Deterministic(
    name::AbstractString,
    input_data::AbstractDict{Dates.DateTime, <:Any};
    resolution::Dates.Period,
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    data = SortedDict{Dates.DateTime, Vector{Float64}}()
    for (k, v) in input_data
        try
            data[k] = Float64[i for i in v]
        catch e
            @error("The forecast data provided $(second(eltype(input_data))) can't be converted to Vector{Float64}")
            rethrow()
        end
    end
    @assert !isempty(data)

    return Deterministic(
        name,
        data;
        resolution = resolution,
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

"""
Construct Deterministic from RawTimeSeries.
"""
function Deterministic(
    name::AbstractString,
    series_data::RawTimeSeries;
    resolution::Dates.Period,
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    return Deterministic(
        name,
        series_data.data;
        resolution = resolution,
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

"""
Construct Deterministic from a CSV file. The first column must be a timestamp in DateTime format and the columns the values in the forecast window.

# Arguments
- `name::AbstractString`: user-defined name
- `filename::AbstractString`: name of CSV file containing data
- `component::InfrastructureSystemsComponent`: component associated with the data
- `normalization_factor::NormalizationFactor = 1.0`: optional normalization factor to apply
  to each data entry
- `scaling_factor_multiplier::Union{Nothing, Function} = nothing`: If the data are scaling
  factors then this function will be called on the component and applied to the data when
  [`get_time_series_array`](@ref) is called.
"""
function Deterministic(
    name::AbstractString,
    filename::AbstractString,
    component::InfrastructureSystemsComponent;
    resolution::Dates.Period,
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    component_name = get_name(component)
    raw_data = read_time_series(Deterministic, filename, component_name)
    return Deterministic(
        name,
        raw_data;
        resolution = resolution,
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

function Deterministic(
    ts_metadata::DeterministicMetadata,
    data::SortedDict{Dates.DateTime, Array},
)
    return Deterministic(
        name = get_name(ts_metadata),
        initial_timestamp = first(keys(data)),
        resolution = get_resolution(ts_metadata),
        horizon = length(first(values(data))),
        data = data,
        scaling_factor_multiplier = get_scaling_factor_multiplier(ts_metadata),
        internal = InfrastructureSystemsInternal(get_time_series_uuid(ts_metadata)),
    )
end

function Deterministic(info::TimeSeriesParsedInfo)
    return Deterministic(
        info.name,
        info.data;
        resolution = info.resolution,
        normalization_factor = info.normalization_factor,
        scaling_factor_multiplier = info.scaling_factor_multiplier,
    )
end

function DeterministicMetadata(ts::Deterministic)
    return DeterministicMetadata(
        get_name(ts),
        get_resolution(ts),
        get_initial_timestamp(ts),
        get_interval(ts),
        get_count(ts),
        get_uuid(ts),
        get_horizon(ts),
        get_scaling_factor_multiplier(ts),
    )
end

"""
Return the forecast window corresponsing to initial_time.
"""
function get_window(forecast::Deterministic, initial_time::Dates.DateTime)
    return TimeSeries.TimeArray(
        make_timestamps(forecast, initial_time),
        forecast.data[initial_time],
    )
end

"""
Return the forecast window corresponsing to interval index.
"""
function get_window(forecast::Deterministic, index::Int)
    return get_window(forecast, index_to_initial_time(forecast, index))
end

"""
Iterate over all forecast windows.
"""
function iterate_windows(forecast::Deterministic)
    return (get_window(forecast, it) for it in keys(forecast.data))
end

function get_array_for_hdf(forecast::Deterministic)
    return hcat(values(forecast.data)...)
end

"""
Creates a new Deterministic from an existing instance and a subset of data.
"""
function Deterministic(forecast::Deterministic, data::SortedDict{Dates.DateTime, Vector})
    vals = []
    for (fname, ftype) in zip(fieldnames(Deterministic), fieldtypes(Deterministic))
        if ftype <: SortedDict{Dates.DateTime, Vector}
            val = data
        elseif ftype <: InfrastructureSystemsInternal
            # Need to create a new UUID.
            val = InfrastructureSystemsInternal()
        else
            val = getfield(forecast, fname)
        end

        push!(vals, val)
    end

    return Deterministic(vals...)
end
