
import Logging

# These use PascalCase to avoid clashing with source filenames.
const LOG_GROUP_PARSING = :Parsing
const LOG_GROUP_RECORDER = :Recorder
const LOG_GROUP_SERIALIZATION = :Serialization
const LOG_GROUP_SYSTEM = :System
const LOG_GROUP_SYSTEM_CHECKS = :SystemChecks
const LOG_GROUP_TIME_SERIES = :TimeSeries

# Try to keep this updated so that users can check the known groups in the REPL.
const LOG_GROUPS = (
    LOG_GROUP_PARSING,
    LOG_GROUP_RECORDER,
    LOG_GROUP_SERIALIZATION,
    LOG_GROUP_SYSTEM,
    LOG_GROUP_TIME_SERIES,
)
const SIIP_LOGGING_CONFIG_FILENAME =
    joinpath(dirname(pathof(InfrastructureSystems)), "utils", "logging_config.toml")

const LOG_LEVELS = Dict(
    "Debug" => Logging.Debug,
    "Info" => Logging.Info,
    "Warn" => Logging.Warn,
    "Error" => Logging.Error,
)

"""Contains information describing a log event."""
mutable struct LogEvent
    file::String
    line::Int
    id::Symbol
    message::String
    level::Logging.LogLevel
    count::Int
    suppressed::Int
end

function LogEvent(file, line, id, message, level)
    if isnothing(file)
        file = "None"
    end

    LogEvent(file, line, id, message, level, 1, 0)
end

struct LogEventTracker
    events::Dict{Logging.LogLevel, Dict{Symbol, LogEvent}}

    # Defining an inner constructor to prohibit creation of a default constructor that
    # takes a parameter of type Any. The outer constructor below causes an overwrite of
    # that method, which results in a warning message from Julia.
    LogEventTracker(events::Dict{Logging.LogLevel, Dict{Symbol, LogEvent}}) = new(events)
end
"""Returns a summary of log event counts by level."""
function report_log_summary(tracker::LogEventTracker)::String
    text = "\nLog message summary:\n"
    # Order by criticality.
    for level in sort!(collect(keys(tracker.events)), rev = true)
        num_events = length(tracker.events[level])
        text *= "\n$num_events $level events:\n"
        for event in
            sort!(collect(get_log_events(tracker, level)), by = x -> x.count, rev = true)
            text *= "  count=$(event.count) at $(event.file):$(event.line)\n"
            text *= "    example message=\"$(event.message)\"\n"
            if event.suppressed > 0
                text *= "    suppressed=$(event.suppressed)\n"
            end
        end
    end

    return text
end

"""Returns an iterable of log events for a level."""
function get_log_events(tracker::LogEventTracker, level::Logging.LogLevel)
    if !_is_level_valid(tracker, level)
        return []
    end

    return values(tracker.events[level])
end

"""Increments the count of a log event."""
function increment_count(tracker::LogEventTracker, event::LogEvent, suppressed::Bool)
    if _is_level_valid(tracker, event.level)
        if haskey(tracker.events[event.level], event.id)
            tracker.events[event.level][event.id].count += 1
            if suppressed
                tracker.events[event.level][event.id].suppressed += 1
            end
        else
            tracker.events[event.level][event.id] = event
        end
    end
end

function _is_level_valid(tracker::LogEventTracker, level::Logging.LogLevel)
    return level in keys(tracker.events)
end

struct LoggingConfiguration
    console::Bool
    console_stream::IO
    console_level::Base.LogLevel
    file::Bool
    filename::Union{Nothing, String}
    file_level::Base.LogLevel
    file_mode::String
    tracker::Union{Nothing, LogEventTracker}
    set_global::Bool
    group_levels::Dict{Symbol, Base.LogLevel}
end

function LoggingConfiguration(;
    console = true,
    console_stream = stderr,
    console_level = Logging.Error,
    file = true,
    filename = "log.txt",
    file_level = Logging.Info,
    file_mode = "w+",
    tracker = nothing,
    set_global = true,
    group_levels = Dict{Symbol, Base.LogLevel}(),
)
    return LoggingConfiguration(
        console,
        console_stream,
        console_level,
        file,
        filename,
        file_level,
        file_mode,
        tracker,
        set_global,
        group_levels,
    )
end

function LoggingConfiguration(config_filename)
    config = open(config_filename, "r") do io
        TOML.parse(io)
    end

    console_stream_str = get(config, "console_stream", "stderr")
    if console_stream_str == "stderr"
        config["console_stream"] = stderr
    elseif console_stream_str == "stdout"
        config["console_stream"] = stdout
    else
        error("unsupport console_stream value: {console_stream_str")
    end

    config["console_level"] = get_logging_level(get(config, "console_level", "Info"))
    config["file_level"] = get_logging_level(get(config, "file_level", "Info"))
    config["group_levels"] =
        Dict(Symbol(k) => get_logging_level(v) for (k, v) in config["group_levels"])
    config["tracker"] = nothing
    return LoggingConfiguration(; Dict(Symbol(k) => v for (k, v) in config)...)
end

function make_logging_config_file(filename = "logging_config.toml"; force = false)
    cp(SIIP_LOGGING_CONFIG_FILENAME, filename, force = force)
    println("Created $filename")
end

"""
Tracks counts of all log events by level.

# Examples
```Julia
LogEventTracker()
LogEventTracker((Logging.Info, Logging.Warn, Logging.Error))
```
"""
function LogEventTracker(levels = (Logging.Info, Logging.Warn, Logging.Error))
    return LogEventTracker(Dict(l => Dict{Symbol, LogEvent}() for l in levels))
end

"""
Creates console and file loggers per caller specification and returns a MultiLogger.

**Note:** If logging to a file users must call Base.close() on the returned MultiLogger to
ensure that all events get flushed.

# Arguments
- `console::Bool=true`: create console logger
- `console_stream::IOStream=stderr`: stream for console logger
- `console_level::Logging.LogLevel=Logging.Error`: level for console messages
- `file::Bool=true`: create file logger
- `filename::Union{Nothing, String}=log.txt`: log file
- `file_level::Logging.LogLevel=Logging.Info`: level for file messages
- `file_mode::String=w+`: mode used when opening log file
- `tracker::Union{LogEventTracker, Nothing}=LogEventTracker()`: optionally track log events
- `set_global::Bool=true`: set the created logger as the global logger

# Example
```Julia
logger = configure_logging(filename="mylog.txt")
```
"""
function configure_logging(;
    console = true,
    console_stream = stderr,
    console_level = Logging.Error,
    file = true,
    filename = "log.txt",
    file_level = Logging.Info,
    file_mode = "w+",
    tracker = LogEventTracker(),
    set_global = true,
)
    config = LoggingConfiguration(
        console = console,
        console_stream = console_stream,
        console_level = console_level,
        file = file,
        filename = filename,
        file_level = file_level,
        file_mode = file_mode,
        tracker = tracker,
        set_global = set_global,
    )
    return configure_logging(config)
end

function configure_logging(config_filename::AbstractString)
    return configure_logging(LoggingConfiguration(config_filename))
end

function configure_logging(config::LoggingConfiguration)
    if !config.console && !config.file
        error("At least one of console or file must be true")
    end

    loggers = Vector{Logging.AbstractLogger}()
    if config.console
        console_logger = Logging.ConsoleLogger(config.console_stream, config.console_level)
        push!(loggers, console_logger)
    end

    if config.file
        io = open(config.filename, config.file_mode)
        file_logger = FileLogger(io, config.file_level)
        push!(loggers, file_logger)
    end

    logger = MultiLogger(loggers, config.tracker, Dict{Symbol, Base.LogLevel}())
    if config.set_global
        Logging.global_logger(logger)
    end

    return logger
end

"""
Specializes the behavior of SimpleLogger by adding timestamps and process and thread IDs.
"""
struct FileLogger <: Logging.AbstractLogger
    logger::Logging.SimpleLogger
end

function FileLogger(stream::IO, level::Base.CoreLogging.LogLevel)
    return FileLogger(Logging.SimpleLogger(stream, level))
end

function Logging.handle_message(
    file_logger::FileLogger,
    level,
    message,
    _module,
    group,
    id,
    file,
    line;
    maxlog = nothing,
    kwargs...,
)
    Logging.handle_message(
        file_logger.logger,
        level,
        "$(Dates.now()) [$(getpid()):$(Base.Threads.threadid())]: $message",
        _module,
        group,
        id,
        file,
        line;
        maxlog = maxlog,
        kwargs...,
    )
end

function Logging.shouldlog(logger::FileLogger, level, _module, group, id)
    return Logging.shouldlog(logger.logger, level, _module, group, id)
end

Logging.min_enabled_level(logger::FileLogger) = Logging.min_enabled_level(logger.logger)
Logging.catch_exceptions(logger::FileLogger) = false
Base.flush(logger::FileLogger) = flush(logger.logger.stream)
Base.close(logger::FileLogger) = close(logger.logger.stream)

"""
Opens a file logger using Logging.SimpleLogger.

# Example
```Julia
open_file_logger("log.txt", Logging.Info) do logger
    global_logger(logger)
    @info "hello world"
end
```
"""
function open_file_logger(
    func::Function,
    filename::String,
    level = Logging.Info,
    mode = "w+",
)
    stream = open(filename, mode)
    try
        logger = FileLogger(stream, level)
        func(logger)
    finally
        close(stream)
    end
end

"""
Redirects log events to multiple loggers. The primary use case is to allow logging to
both a file and the console. Secondarily, it can track the counts of all log messages.

# Example
```Julia
MultiLogger([ConsoleLogger(stderr), SimpleLogger(stream)], LogEventTracker())
```
"""
mutable struct MultiLogger <: Logging.AbstractLogger
    loggers::Array{Logging.AbstractLogger}
    tracker::Union{LogEventTracker, Nothing}
    group_levels::Dict{Symbol, Base.LogLevel}
end

"""
Creates a MultiLogger with no event tracking.

# Example
```Julia
MultiLogger([ConsoleLogger(stderr), SimpleLogger(stream)])
```
"""
function MultiLogger(loggers::Array{T}) where {T <: Logging.AbstractLogger}
    return MultiLogger(loggers, nothing, Dict{Symbol, Base.LogLevel}())
end

function MultiLogger(
    loggers::Array{T},
    tracker::LogEventTracker,
) where {T <: Logging.AbstractLogger}
    return MultiLogger(loggers, tracker, Dict{Symbol, Base.LogLevel}())
end

function Logging.shouldlog(logger::MultiLogger, level, _module, group, id)
    return get(logger.group_levels, group, level) <= level
end

function Logging.min_enabled_level(logger::MultiLogger)
    return minimum([Logging.min_enabled_level(x) for x in logger.loggers])
end

Logging.catch_exceptions(logger::MultiLogger) = false

function Logging.handle_message(
    logger::MultiLogger,
    level,
    message,
    _module,
    group,
    id,
    file,
    line;
    maxlog = nothing,
    kwargs...,
)
    suppressed = false
    for _logger in logger.loggers
        if level >= Logging.min_enabled_level(_logger)
            if Logging.shouldlog(_logger, level, _module, group, id)
                Logging.handle_message(
                    _logger,
                    level,
                    message,
                    _module,
                    group,
                    id,
                    file,
                    line;
                    maxlog = maxlog,
                    kwargs...,
                )
            else
                suppressed = true
            end
        end
    end

    if !isnothing(logger.tracker)
        id = isa(id, Symbol) ? id : :empty
        event = LogEvent(file, line, id, string(message), level)
        increment_count(logger.tracker, event, suppressed)
    end

    return
end

"""
Empty the minimum log levels stored for each group.
"""
function empty_group_levels!(logger::MultiLogger)
    empty!(logger.group_levels)
    return
end

"""
Set the minimum log level for a group.

The `group` field of a log message defaults to its file's base name (no extension) as a
symbol. It can be customized by setting `_group = :a_group_name`.

The minimum log level stored for a console or file logger supercede this setting.
"""
function set_group_level!(logger::MultiLogger, group::Symbol, level::Base.LogLevel)
    logger.group_levels[group] = level
    return
end

"""
Set the minimum log levels for multiple groups. Refer to [`set_group_level`](@ref) for more
information.
"""
function set_group_levels!(logger::MultiLogger, group_levels::Dict{Symbol, Base.LogLevel})
    merge!(logger.group_levels, group_levels)
    return
end

"""
Return the minimum logging level for a group or nothing if `group` is not stored.
"""
get_group_level(logger::MultiLogger, group::Symbol) =
    get(logger.group_levels, group, nothing)

"""
Return the minimum logging levels for groups that have been stored.
"""
get_group_levels(logger::MultiLogger) = deepcopy(logger.group_levels)

"""Returns a summary of log event counts by level."""
function report_log_summary(logger::MultiLogger)
    if isnothing(logger.tracker)
        error("log event tracking is not enabled")
    end

    return report_log_summary(logger.tracker)
end

"""Flush any file streams."""
function Base.flush(logger::MultiLogger)
    _handle_log_func(logger, Base.flush)
end

"""Ensures that any file streams are flushed and closed."""
function Base.close(logger::MultiLogger)
    _handle_log_func(logger, Base.close)
end

function get_logging_level(level::String)
    if !haskey(LOG_LEVELS, level)
        error("Invalid log level $level: Supported levels: $(values(LOG_LEVELS))")
    end

    return LOG_LEVELS[level]
end

function _handle_log_func(logger::MultiLogger, func::Function)
    for _logger in logger.loggers
        if isa(_logger, Logging.SimpleLogger)
            func(_logger.stream)
        elseif isa(_logger, FileLogger)
            func(_logger)
        end
    end
end
