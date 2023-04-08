function enable_disk_caching!(ram_percentage_limit::Int=30)
    !(0 < ram_percentage_limit <= 100 ) && error("Ram limit values must be in (1, 100> range")
    processes = procs()

    process_info = [ id =>
        remotecall(id) do
            return (;
                total_memory=Sys.total_physical_memory(),
                hostname=gethostname(),
            )
        end
        for id in processes
    ]

    machines = Dict()
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

    r = [
        remotecall(id) do
            Main.eval(:(using Dagger))
            Dagger.MemPool.setup_global_device!(
                Dagger.MemPool.DiskCacheConfig(;
                    toggle=true,
                    membound=mem_limits[id]
                )
            )
            true
        end
        for id in processes
    ]

    return try
        all(fetch.(r))
    catch _
        @error("Error when setting up disk caching on all workers")
        false
    end
end
