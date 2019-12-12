"""
    redirect_stdout_to_log(func::Function)

Redirect all data written to stdout by a function to log events.
"""
function redirect_stdout_to_log(func::Function)
    orig_stdout = Base.stdout
    (read_pipe, write_pipe) = redirect_stdout()
    redirector = StdoutRedirector(read_pipe, write_pipe, true)

    task = Threads.@spawn _redirect(redirector)
    while !istaskstarted(task)
        sleep(0.1)
    end

    try
        func()
    finally
        redirect_stdout(orig_stdout)
        redirector.enabled = false
        print(redirector.write_pipe, "\n")
        close(redirector.read_pipe)
        close(redirector.write_pipe)
        wait(task)
    end
end

mutable struct StdoutRedirector
    read_pipe::Base.PipeEndpoint
    write_pipe::Base.PipeEndpoint
    enabled::Bool
end

function _redirect(redirector::StdoutRedirector)
    while redirector.enabled
        line = readline(redirector.read_pipe)
        _log_line(line)
    end

    # There may still be data in the pipe.
    if !eof(redirector.read_pipe)
        for line in eachline(redirector.read_pipe)
            _log_line(line)
        end
    end
end

function _log_line(data)
    line = strip(data)
    if !isempty(line)
        @info line
    end
end
