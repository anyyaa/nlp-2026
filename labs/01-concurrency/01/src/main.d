
import std.stdio : writeln;
import core.thread : Thread;
import std.uni : isAlpha, toLower;
import std.utf : toUTF8;
import std.algorithm.sorting : sort;

alias Counts = size_t[string];

struct WorkerInfo {
    size_t number;
    size_t from;
    size_t to;
    size_t wordsProcessed;
    size_t uniqueWords;
    ulong osThreadId;
}

struct Analysis {
    Counts counts;
    WorkerInfo[] workers;
}

string[] splitWords(string text) {
    string[] words;
    dchar[] current;
    auto lowerText = toLower(text);

    foreach (dchar ch; lowerText) {
        if (isAlpha(ch) || (ch >= '0' && ch <= '9')) {
            current ~= ch;
        } else if (current.length > 0) {
            words ~= toUTF8(current);
            current.length = 0;
        }
    }

    if (current.length > 0) {
        words ~= toUTF8(current);
    }

    return words;
}

Counts countRange(string[] words, size_t from, size_t to) {
    Counts result;
    foreach (word; words[from .. to]) {
        if (auto existing = word in result) {
            ++(*existing);
        } else {
            result[word] = 1;
        }
    }
    return result;
}

class WordWorker : Thread {
    private string[] words;
    private size_t from;
    private size_t to;
    private size_t number;
    Counts localCounts;
    WorkerInfo info;

    this(string[] words, size_t from, size_t to, size_t number) {
        super(&run);
        this.words = words;
        this.from = from;
        this.to = to;
        this.number = number;
    }

    private void run() {
        localCounts = countRange(words, from, to);
        info = WorkerInfo(number, from, to, to - from,
                          localCounts.length, Thread.getThis().id);
    }
}

Analysis countParallel(string text, size_t requestedWorkers) {
    if (requestedWorkers == 0) {
        throw new Exception("Worker count must be positive");
    }

    auto words = splitWords(text);
    Analysis result;
    if (words.length == 0) {
        return result;
    }

    size_t workersCount = requestedWorkers < words.length
        ? requestedWorkers : words.length;
    WordWorker[] threads;
    result.workers = new WorkerInfo[workersCount];

    foreach (i; 0 .. workersCount) {
        size_t from = words.length * i / workersCount;
        size_t to = words.length * (i + 1) / workersCount;
        threads ~= new WordWorker(words, from, to, i + 1);
    }

    foreach (thread; threads) {
        thread.start();
    }
    foreach (thread; threads) {
        thread.join();
    }

    foreach (i, thread; threads) {
        result.workers[i] = thread.info;
        foreach (word, frequency; thread.localCounts) {
            if (auto existing = word in result.counts) {
                *existing += frequency;
            } else {
                result.counts[word] = frequency;
            }
        }
    }

    return result;
}

bool sameCounts(Counts left, Counts right) {
    if (left.length != right.length) {
        return false;
    }
    foreach (word, frequency; left) {
        auto other = word in right;
        if (other is null || *other != frequency) {
            return false;
        }
    }
    return true;
}

void runTests() {
    size_t passed = 0;
    size_t total = 0;

    void check(string name, bool ok) {
        ++total;
        if (ok) ++passed;
        writeln(name, ": ", ok ? "PASS" : "FAIL");
    }

    auto a = countParallel("Cat cat DOG!", 2);
    check("Case insensitive", a.counts.get("cat", 0) == 2 && a.counts.get("dog", 0) == 1);
    check("Two workers", a.workers.length == 2);
    check("Empty text", countParallel("", 4).counts.length == 0);
    check("Only punctuation", countParallel("!?,.;", 3).counts.length == 0);
    check("One word", countParallel("hello", 2).counts.get("hello", 0) == 1);
    check("Numbers", countParallel("2026 2026 7", 3).counts.get("2026", 0) == 2);
    check("Hyphen is separator", countParallel("one-two", 2).counts.get("one", 0) == 1 && countParallel("one-two", 2).counts.get("two", 0) == 1);
    check("Underscore is separator", countParallel("red_blue", 2).counts.get("red", 0) == 1);
    check("Cyrillic text", countParallel("кот кот пёс", 3).counts.get("кот", 0) == 2);
    check("Unicode case folding", countParallel("КОТ кот", 2).counts.get("кот", 0) == 2);
    check("Single worker", countParallel("a b b", 1).counts.get("b", 0) == 2);
    check("Too many workers", countParallel("a b", 100).workers.length == 2);
    check("No lost words", countParallel("a a b c c c", 4).counts.get("c", 0) == 3);

    auto many = "one two one three two one four three two five";
    auto seqResult = countParallel(many, 1);
    auto parallelResult = countParallel(many, 4);
    check("Parallel equals sequential", sameCounts(seqResult.counts, parallelResult.counts));

    size_t processed = 0;
    foreach (worker; parallelResult.workers) {
        processed += worker.wordsProcessed;
    }
    check("All ranges processed", processed == splitWords(many).length);

    writeln();
    writeln("Passed: ", passed, "/", total);
    if (passed != total) {
        throw new Exception("Some tests failed");
    }
}

void main() {
    string text = "Data data DATA! Parallel threads count words. " ~
                  "Threads work in parallel. Кот кот КОТ.";
    size_t workers = 4;

    writeln("=== Parallel Word Frequency ===");
    writeln("Input: ", text);
    auto result = countParallel(text, workers);

    foreach (worker; result.workers) {
        writeln("worker-", worker.number, ": words=", worker.wordsProcessed,
                ", unique=", worker.uniqueWords,
                ", indexes=", worker.from, "..", worker.to - 1,
                ", OS thread id=", worker.osThreadId);
    }

    string[] keys;
    foreach (word, _; result.counts) {
        keys ~= word;
    }
    sort(keys);

    writeln("Word frequencies:");
    size_t total = 0;
    foreach (word; keys) {
        writeln(word, ": ", result.counts[word]);
        total += result.counts[word];
    }
    writeln("Total words: ", total);
    writeln("Unique words: ", keys.length);
    writeln();
    runTests();
}
