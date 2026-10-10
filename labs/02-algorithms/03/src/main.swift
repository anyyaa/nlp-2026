
func longestIncreasingSubsequence(_ numbers: [Int]) -> [Int] {
    let n = numbers.count

    if n == 0 {
        return []
    }

    var dp = Array(repeating: 1, count: n)
    var previous = Array(repeating: -1, count: n)
    var bestEnd = 0

    for i in 0..<n {
        for j in 0..<i {
            if numbers[j] < numbers[i] && dp[j] + 1 > dp[i] {
                dp[i] = dp[j] + 1
                previous[i] = j
            }
        }

        if dp[i] > dp[bestEnd] {
            bestEnd = i
        }
    }

    var result: [Int] = []
    var index = bestEnd

    while index != -1 {
        result.append(numbers[index])
        index = previous[index]
    }

    return Array(result.reversed())
}

func test(_ name: String, _ numbers: [Int]) {
    let result = longestIncreasingSubsequence(numbers)

    print("--- \(name) ---")
    print("Input: \(numbers)")
    print("Length: \(result.count)")
    print("Sequence: \(result)")
    print()
}

test("Normal sequence", [10, 9, 2, 5, 3, 7, 101, 18])
test("Repeated numbers", [2, 2, 2, 2])
test("Decreasing sequence", [5, 4, 3, 2, 1])
test("Empty sequence", [])
test("Increasing sequence", [1, 2, 3, 4, 5])
