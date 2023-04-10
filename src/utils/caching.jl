function enable_disk_caching!(
    ram_percentage_limit::Int=30, processes::Vector{Int}=procs(), disk_limit_gb::Int=16
)
    !(0 < ram_percentage_limit <= 100) &&
        error("Ram limit values must be in (1, 100> range")

    process_info = [
        id => remotecall(id) do
            return (; total_memory=Sys.total_physical_memory(), hostname=gethostname())
        end for id in processes
    ]

    machines = Dict{Int,Any}()
    for (id, info) in process_info
        key = fetch(info)
        machines[key] = push!(get(machines, key, Int[]), id)
    end

    mem_limits = Dict{Int,Int}()
    for (info, ids) in machines
        for id in ids
            mem_limits[id] = info.total_memory * ram_percentage_limit / 100 ÷ length(ids)
        end
    end

    return enable_disk_caching!(mem_limits, processes, disk_limit_gb)
end

function enable_disk_caching!(
    mem_limits::Dict{Int,Int}, processes::Vector{Int}=procs(), disk_limit_gb::Int=16
)
    results = [
        remotecall(id) do
            !isdefined(Main, :Dagger) && Main.eval(:(using Dagger))
            Dagger.MemPool.setup_global_device!(
                Dagger.MemPool.DiskCacheConfig(;
                    toggle=true, membound=mem_limits[id], diskbound=disk_limit_gb * 2^30
                ),
            )
            nothing
        end for id in processes
    ]
    any_error = false
    for (i, id) in enumerate(processes)
        r = fetch(results[i])
        any_error |= r !== nothing
        if r !== nothing
            @error("Error setting up disk caching on process id = $id", ex = r)
        end
    end

    return if any_error
        @error("Disk cache setup failed")
        false
    else
        @info("Disk cache setup successful")
        true
    end
end

function inspect_global_devices(processes::Vector{Int}=procs())
    results = [
        remotecall(id) do
            !isdefined(Main, :Dagger) && Main.eval(:(using Dagger))
            id => Dagger.MemPool.GLOBAL_DEVICE[]
        end for id in processes
    ]
    return fetch.(results)
end
