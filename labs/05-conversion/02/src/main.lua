
local morse = {
    A = ".-", B = "-...", C = "-.-.", D = "-..", E = ".", F = "..-.",
    G = "--.", H = "....", I = "..", J = ".---", K = "-.-", L = ".-..",
    M = "--", N = "-.", O = "---", P = ".--.", Q = "--.-", R = ".-.",
    S = "...", T = "-", U = "..-", V = "...-", W = ".--", X = "-..-",
    Y = "-.--", Z = "--..",
    ["0"] = "-----", ["1"] = ".----", ["2"] = "..---",
    ["3"] = "...--", ["4"] = "....-", ["5"] = ".....",
    ["6"] = "-....", ["7"] = "--...", ["8"] = "---..",
    ["9"] = "----.",
    ["."] = ".-.-.-", [","] = "--..--", ["?"] = "..--..",
    ["!"] = "-.-.--", ["-"] = "-....-", ["/"] = "-..-.",
    ["("] = "-.--.", [")"] = "-.--.-"
}

local letters = {}

for char, code in pairs(morse) do
    letters[code] = char
end

local function encode(text)
    local result = {}

    for i = 1, #text do
        local char = text:sub(i, i):upper()

        if char == " " then
            if #result > 0 and result[#result] ~= "/" then
                result[#result + 1] = "/"
            end
        else
            local code = morse[char]

            if not code then
                return nil, "Unsupported character at position " .. i
            end

            result[#result + 1] = code
        end
    end

    if result[#result] == "/" then
        table.remove(result)
    end

    return table.concat(result, " ")
end

local function decode(text)
    local result = {}

    for token in text:gmatch("%S+") do
        if token == "/" then
            if #result > 0 and result[#result] ~= " " then
                result[#result + 1] = " "
            end
        else
            local char = letters[token]

            if not char then
                return nil, "Unknown Morse code: " .. token
            end

            result[#result + 1] = char
        end
    end

    if result[#result] == " " then
        table.remove(result)
    end

    return table.concat(result)
end

local function run_tests()
    local tests = {
        {"SOS", "... --- ..."},
        {"HELLO WORLD", ".... . .-.. .-.. --- / .-- --- .-. .-.. -.."},
        {"2026", "..--- ----- ..--- -...."},
        {"A, B", ".- --..-- / -..."}
    }

    for i, test in ipairs(tests) do
        local encoded = encode(test[1])
        local decoded = decode(test[2])
        local passed = encoded == test[2] and decoded == test[1]

        print("Test " .. i .. ": " .. (passed and "PASS" or "FAIL"))
    end

    print("Invalid character: " ..
        (encode("HELLO#") == nil and "PASS" or "FAIL"))

    print("Invalid Morse: " ..
        (decode("... --- ..--..--") == nil and "PASS" or "FAIL"))
end

while true do
    print("\n1 - Text to Morse")
    print("2 - Morse to text")
    print("3 - Run tests")
    print("0 - Exit")
    io.write("Choose: ")

    local choice = io.read("*l")

    if choice == nil or choice == "0" then
        break
    elseif choice == "1" then
        io.write("Enter text: ")
        local text = io.read("*l")

        if text then
            local result, err = encode(text)
            print(result or err)
        end
    elseif choice == "2" then
        io.write("Enter Morse code: ")
        local text = io.read("*l")

        if text then
            local result, err = decode(text)
            print(result or err)
        end
    elseif choice == "3" then
        run_tests()
    else
        print("Unknown option")
    end
end
