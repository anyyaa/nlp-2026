
data class WorkerResult(
    val from: Int,
    val to: Int,
    val primes: List<Int>,
    val threadName: String
)

fun isPrime(number: Int): Boolean {
    if (number < 2) return false
    if (number == 2) return true
    if (number % 2 == 0) return false

    var divisor = 3
    while (divisor <= number / divisor) {
        if (number % divisor == 0) return false
        divisor += 2
    }
    return true
}

fun findPrimesParallel(limit: Int, workerCount: Int): Pair<List<Int>, List<WorkerResult>> {
    require(limit >= 0) { "Limit must not be negative" }
    require(workerCount > 0) { "Worker count must be positive" }

    if (limit < 2) return Pair(emptyList(), emptyList())

    val numbersCount = limit - 1
    val workersCount = minOf(workerCount, numbersCount)
    val baseSize = numbersCount / workersCount
    val extraNumbers = numbersCount % workersCount

    val results = arrayOfNulls<WorkerResult>(workersCount)
    val threads = mutableListOf<Thread>()

    for (index in 0 until workersCount) {
        val from = 2 + index * baseSize + minOf(index, extraNumbers)
        val size = baseSize + if (index < extraNumbers) 1 else 0
        val to = from + size - 1

        val thread = Thread({
            val primes = mutableListOf<Int>()
            for (number in from..to) {
                if (isPrime(number)) primes.add(number)
            }
            results[index] = WorkerResult(
                from, to, primes, Thread.currentThread().name
            )
        }, "worker-${index + 1}")

        threads.add(thread)
    }

    threads.forEach { it.start() }
    threads.forEach { it.join() }

    val details = results.filterNotNull()
    val primes = details.flatMap { it.primes }
    return Pair(primes, details)
}

fun check(name: String, passed: Boolean): Boolean {
    println("$name: ${if (passed) "PASS" else "FAIL"}")
    return passed
}

fun runTests() {
    var passed = 0
    var total = 0

    fun test(name: String, condition: Boolean) {
        total++
        if (check(name, condition)) passed++
    }

    test("2 is prime", isPrime(2))
    test("1 is not prime", !isPrime(1))
    test("Even composite", !isPrime(100))
    test("Odd composite", !isPrime(49))
    test("97 is prime", isPrime(97))
    test("Small range", findPrimesParallel(10, 3).first == listOf(2, 3, 5, 7))
    test("25 primes up to 100", findPrimesParallel(100, 4).first.size == 25)
    test("Limit zero", findPrimesParallel(0, 4).first.isEmpty())
    test("Limit one", findPrimesParallel(1, 4).first.isEmpty())
    test("More threads than numbers", findPrimesParallel(5, 20).first == listOf(2, 3, 5))
    test("Exactly four workers when possible", findPrimesParallel(6, 4).second.size == 4)
    test("One thread", findPrimesParallel(30, 1).first == listOf(2, 3, 5, 7, 11, 13, 17, 19, 23, 29))
    test("Parallel equals sequential", findPrimesParallel(1000, 4).first == (2..1000).filter(::isPrime))

    val result = findPrimesParallel(100, 4).second
    test("Ranges cover all numbers", result.flatMap { (it.from..it.to).toList() } == (2..100).toList())
    test("Four distinct workers", result.map { it.threadName }.distinct().size == 4)

    println("Passed: $passed/$total")
    if (passed != total) throw IllegalStateException("Some tests failed")
}

fun main() {
    val limit = 100
    val workerCount = 4

    println("=== Parallel Prime Numbers ===")
    val (primes, workers) = findPrimesParallel(limit, workerCount)

    for (worker in workers) {
        println("${worker.threadName}: ${worker.from}..${worker.to}, primes=${worker.primes.size}")
    }

    println("Primes: ${primes.joinToString(", ")}")
    println("Total primes: ${primes.size}")
    println()

    runTests()
}
