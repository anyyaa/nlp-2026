
import Data.List (sort)

mergeIntervals :: [(Int, Int)] -> [(Int, Int)]
mergeIntervals [] = []
mergeIntervals intervals =
    reverse (foldl merge [] (sort intervals))
  where
    merge [] interval = [interval]
    merge ((l1, r1):rest) (l2, r2)
        | l2 <= r1 = (l1, max r1 r2) : rest
        | otherwise = (l2, r2) : (l1, r1) : rest

test :: String -> [(Int, Int)] -> IO ()
test name intervals = do
    putStrLn ("--- " ++ name ++ " ---")
    putStrLn ("Input: " ++ show intervals)
    putStrLn ("Result: " ++ show (mergeIntervals intervals))
    putStrLn ""

main :: IO ()
main = do
    test "Overlapping intervals"
        [(1, 3), (2, 6), (8, 10), (15, 18)]

    test "Nested intervals"
        [(1, 10), (2, 3), (4, 8)]

    test "Touching intervals"
        [(1, 3), (3, 5), (5, 7)]

    test "Non-overlapping intervals"
        [(1, 2), (4, 5), (7, 9)]

    test "Unsorted intervals"
        [(8, 10), (1, 4), (3, 6), (10, 12)]

    test "Empty list"
        []
