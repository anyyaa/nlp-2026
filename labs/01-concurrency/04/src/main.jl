const Point = NTuple{2, Float64}

struct PairResult
    i::Int
    j::Int
    distance2::Float64
end

struct WorkerInfo
    id::Int
    rows::Int
    pairs_checked::Int
    thread_id::Int
end

struct SearchResult
    pair::Union{Nothing, PairResult}
    workers::Vector{WorkerInfo}
end

mutable struct TestState
    passed::Int
    total::Int
end

@inline function squared_distance(a::Point, b::Point)::Float64
    dx = a[1] - b[1]
    dy = a[2] - b[2]
    return dx * dx + dy * dy
end

function is_better(candidate::PairResult, current::PairResult)::Bool
    return candidate.distance2 < current.distance2 ||
           (candidate.distance2 == current.distance2 &&
            (candidate.i < current.i ||
             (candidate.i == current.i && candidate.j < current.j)))
end

function scan_worker(points::Vector{Point}, id::Int, worker_count::Int)
    n = length(points)
    best_distance2 = Inf
    best_i = 0
    best_j = 0
    rows = 0
    pairs_checked = 0

    for i in id:worker_count:(n - 1)
        rows += 1
        for j in (i + 1):n
            pairs_checked += 1
            d2 = squared_distance(points[i], points[j])
            if d2 < best_distance2 ||
               (d2 == best_distance2 &&
                (i < best_i || (i == best_i && j < best_j)))
                best_distance2 = d2
                best_i = i
                best_j = j
            end
        end
    end

    pair = best_i == 0 ? nothing : PairResult(best_i, best_j, best_distance2)
    return pair, WorkerInfo(id, rows, pairs_checked, Threads.threadid())
end

function closest_sequential(points::Vector{Point})
    length(points) < 2 && return nothing
    pair, _ = scan_worker(points, 1, 1)
    return pair
end

function closest_parallel(points::Vector{Point}, requested_workers::Int)::SearchResult
    requested_workers > 0 || throw(ArgumentError("Worker count must be positive"))

    n = length(points)
    n < 2 && return SearchResult(nothing, WorkerInfo[])

    worker_count = min(requested_workers, n - 1)
    tasks = Vector{Task}(undef, worker_count)

    for id in 1:worker_count
        tasks[id] = Threads.@spawn scan_worker(points, id, worker_count)
    end

    best = nothing
    infos = WorkerInfo[]

    for task in tasks
        candidate, info = fetch(task)
        push!(infos, info)
        if candidate !== nothing && (best === nothing || is_better(candidate, best))
            best = candidate
        end
    end

    return SearchResult(best, infos)
end

function same_pair(a, b)::Bool
    if a === nothing || b === nothing
        return a === b
    end
    return a.i == b.i && a.j == b.j && a.distance2 == b.distance2
end

function pair_is(pair, i::Int, j::Int, distance2::Real)::Bool
    return pair !== nothing && pair.i == i && pair.j == j &&
           pair.distance2 == distance2
end

function rejects_worker_count(points::Vector{Point}, workers::Int)::Bool
    try
        closest_parallel(points, workers)
    catch error
        return error isa ArgumentError
    end
    return false
end

function build_points(n::Int)::Vector{Point}
    return Point[
        (Float64(mod(i * 137, 10007)),
         Float64(mod(i * i * 47 + i * 271, 10009)))
        for i in 1:n
    ]
end

function check!(state::TestState, name::String, ok::Bool)
    state.total += 1
    if ok
        state.passed += 1
    end
    println(name, ": ", ok ? "PASS" : "FAIL")
end

function run_tests()
    state = TestState(0, 0)

    empty = Point[]
    single = Point[(2.0, 3.0)]
    two = Point[(0.0, 0.0), (3.0, 4.0)]
    horizontal = Point[(0.0, 0.0), (2.0, 0.0), (5.0, 0.0)]
    vertical = Point[(0.0, 0.0), (0.0, 5.0), (0.0, 6.0)]
    negative = Point[(-5.0, -5.0), (-4.0, -5.0), (10.0, 10.0)]
    duplicates = Point[(2.0, 2.0), (9.0, 9.0), (2.0, 2.0), (2.0, 2.0)]
    square = Point[(0.0, 0.0), (2.0, 0.0), (0.0, 2.0), (2.0, 2.0)]
    example = Point[
        (0.0, 0.0), (5.0, 5.0), (1.0, 1.0), (1.0, 2.0),
        (8.0, 8.0), (0.0, 1.0), (3.0, 4.0), (6.0, 5.0)
    ]

    check!(state, "Empty sequential", closest_sequential(empty) === nothing)
    check!(state, "Empty parallel", closest_parallel(empty, 4).pair === nothing)
    check!(state, "Single point sequential", closest_sequential(single) === nothing)
    check!(state, "Single point parallel", closest_parallel(single, 4).pair === nothing)
    check!(state, "Two point indices", pair_is(closest_sequential(two), 1, 2, 25.0))
    check!(state, "Euclidean distance", sqrt(closest_sequential(two).distance2) == 5.0)
    check!(state, "Horizontal points", pair_is(closest_sequential(horizontal), 1, 2, 4.0))
    check!(state, "Vertical points", pair_is(closest_sequential(vertical), 2, 3, 1.0))
    check!(state, "Negative coordinates", pair_is(closest_sequential(negative), 1, 2, 1.0))
    check!(state, "Duplicate points", pair_is(closest_parallel(duplicates, 4).pair, 1, 3, 0.0))
    check!(state, "Lexicographic tie", pair_is(closest_parallel(square, 3).pair, 1, 2, 4.0))

    expected = closest_sequential(example)
    check!(state, "One worker", same_pair(closest_parallel(example, 1).pair, expected))
    check!(state, "Two workers", same_pair(closest_parallel(example, 2).pair, expected))
    check!(state, "Three workers", same_pair(closest_parallel(example, 3).pair, expected))
    check!(state, "Four workers", same_pair(closest_parallel(example, 4).pair, expected))

    result = closest_parallel(example, 4)
    check!(state, "Workers capped to rows", length(closest_parallel(two, 50).workers) == 1)
    check!(state, "All pairs checked", sum(w.pairs_checked for w in result.workers) == 28)
    check!(state, "All rows assigned", sum(w.rows for w in result.workers) == length(example) - 1)
    check!(state, "Deterministic result", same_pair(result.pair, closest_parallel(example, 4).pair))
    check!(state, "Zero workers rejected", rejects_worker_count(example, 0))
    check!(state, "Negative workers rejected", rejects_worker_count(example, -3))

    generated = build_points(300)
    check!(state, "Generated data agrees", same_pair(closest_sequential(generated), closest_parallel(generated, 4).pair))

    println("Passed: ", state.passed, "/", state.total)
    state.passed == state.total || error("Some tests failed")
end

function measure(points::Vector{Point}, workers::Int; repeats::Int = 3)
    closest_parallel(points, workers)

    best_time = Inf
    result = nothing
    for _ in 1:repeats
        start = time_ns()
        result = closest_parallel(points, workers)
        elapsed = (time_ns() - start) / 1e9
        best_time = min(best_time, elapsed)
    end
    return best_time, result
end

function main()
    points = Point[
        (0.0, 0.0), (5.0, 5.0), (1.0, 1.0), (1.0, 2.0),
        (8.0, 8.0), (0.0, 1.0), (3.0, 4.0), (6.0, 5.0)
    ]
    workers = 4

    println("=== Parallel Closest Pair (Julia) ===")
    println("Available Julia threads: ", Threads.nthreads())
    println("Points: ", length(points))

    result = closest_parallel(points, workers)
    for worker in result.workers
        println("worker-", worker.id, ": rows=", worker.rows,
                ", pairs=", worker.pairs_checked,
                ", thread_id=", worker.thread_id)
    end

    if result.pair !== nothing
        pair = result.pair
        println("Closest pair: (", pair.i, ", ", pair.j, ")")
        println("Point ", pair.i, ": ", points[pair.i])
        println("Point ", pair.j, ": ", points[pair.j])
        println("Squared distance: ", pair.distance2)
        println("Distance: ", sqrt(pair.distance2))
    end

    println("\n=== Tests ===")
    run_tests()

    n = Threads.nthreads() > 1 ? 4000 : 1600
    benchmark_points = build_points(n)
    println("\n=== Benchmark (", n, " points, best of 3 runs) ===")

    sequential_time, sequential_result = measure(benchmark_points, 1)
    parallel_time, parallel_result = measure(benchmark_points, 4)
    println("One worker:  ", round(sequential_time, digits=4), " s")
    println("Four workers: ", round(parallel_time, digits=4), " s")
    println("Speedup: ", round(sequential_time / parallel_time, digits=2), "x")
    println("Results equal: ", same_pair(sequential_result.pair, parallel_result.pair))
    println("Benchmark thread IDs: ", sort(unique(w.thread_id for w in parallel_result.workers)))

    if Threads.nthreads() == 1
        println("NOTE: The Julia runtime has only one thread.")
        println("Four tasks do not mean four parallel CPU threads here.")
        println("For real comparison run: julia --threads=4 main.jl")
    end
end

main()
