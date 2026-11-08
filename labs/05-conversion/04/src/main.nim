import std/[os, strutils]

proc getU16(data: string, pos: int): int =
  ord(data[pos]) or (ord(data[pos + 1]) shl 8)

proc getU32(data: string, pos: int): int =
  ord(data[pos]) or (ord(data[pos + 1]) shl 8) or
    (ord(data[pos + 2]) shl 16) or (ord(data[pos + 3]) shl 24)

proc convertBmp(data: string): string =
  if data.len < 54:
    raise newException(ValueError, "BMP header is too short")
  if data[0] != 'B' or data[1] != 'M':
    raise newException(ValueError, "Not a BMP file")

  let dibSize = getU32(data, 14)
  if dibSize < 40 or dibSize > data.len - 14:
    raise newException(ValueError, "Unsupported BMP header")

  let pixelOffset = getU32(data, 10)
  if pixelOffset < 14 + dibSize or pixelOffset > data.len:
    raise newException(ValueError, "Invalid pixel data offset")

  let width = getU32(data, 18)
  let rawHeight = getU32(data, 22)
  let signedHeight = if rawHeight >= 0x80000000:
    rawHeight - 0x100000000
  else:
    rawHeight

  if width <= 0 or width > 10000 or signedHeight == 0 or
     signedHeight < -10000 or signedHeight > 10000:
    raise newException(ValueError, "Invalid image dimensions")

  let height = abs(signedHeight)
  if width * height > 4000000:
    raise newException(ValueError, "Image is too large")
  if getU16(data, 26) != 1 or getU16(data, 28) != 24:
    raise newException(ValueError, "Only 24-bit BMP is supported")
  if getU32(data, 30) != 0:
    raise newException(ValueError, "Compressed BMP is not supported")

  let rowStride = ((width * 3 + 3) div 4) * 4
  if rowStride * height > data.len - pixelOffset:
    raise newException(ValueError, "Truncated BMP pixel data")

  result = "P2\n" & $width & " " & $height & "\n255\n"
  for y in 0..<height:
    let storedRow = if signedHeight > 0: height - 1 - y else: y
    for x in 0..<width:
      let p = pixelOffset + storedRow * rowStride + x * 3
      let blue = ord(data[p])
      let green = ord(data[p + 1])
      let red = ord(data[p + 2])
      let gray = (299 * red + 587 * green + 114 * blue + 500) div 1000
      if x > 0:
        result.add(' ')
      result.add($gray)
    result.add('\n')

proc fails(data: string): bool =
  try:
    discard convertBmp(data)
    return false
  except ValueError:
    return true

proc check(name: string, ok: bool, passed: var int, total: var int) =
  inc total
  if ok:
    inc passed
  echo name, ": ", (if ok: "PASS" else: "FAIL")

proc runTests() =
  let bmp = readFile("input.bmp")
  let expected = readFile("expected.pgm")
  var passed = 0
  var total = 0

  check("Sample BMP to PGM", convertBmp(bmp) == expected, passed, total)
  check("Correct grayscale values", expected.contains("76 150 29\n255 0 226\n179 105 128\n"), passed, total)

  var badSignature = bmp
  badSignature[0] = 'X'
  check("Invalid signature", fails(badSignature), passed, total)

  check("Truncated pixel data", fails(bmp[0 ..< bmp.len - 1]), passed, total)
  check("Truncated header", fails(bmp[0 ..< 20]), passed, total)

  var badDepth = bmp
  badDepth[28] = chr(32)
  check("Reject 32-bit BMP", fails(badDepth), passed, total)

  var compressed = bmp
  compressed[30] = chr(1)
  check("Reject compressed BMP", fails(compressed), passed, total)

  var zeroWidth = bmp
  for i in 18..21:
    zeroWidth[i] = chr(0)
  check("Reject zero width", fails(zeroWidth), passed, total)

  var zeroHeight = bmp
  for i in 22..25:
    zeroHeight[i] = chr(0)
  check("Reject zero height", fails(zeroHeight), passed, total)

  var badOffset = bmp
  badOffset[10] = chr(10)
  check("Reject invalid pixel offset", fails(badOffset), passed, total)

  var topDown = bmp
  topDown[22] = chr(253)
  topDown[23] = chr(255)
  topDown[24] = chr(255)
  topDown[25] = chr(255)
  for row in 0..<3:
    for col in 0..<12:
      topDown[54 + row * 12 + col] = bmp[54 + (2 - row) * 12 + col]
  check("Top-down BMP", convertBmp(topDown) == expected, passed, total)

  var changedPadding = bmp
  for row in 0..<3:
    for col in 9..<12:
      changedPadding[54 + row * 12 + col] = chr(255)
  check("Ignore row padding", convertBmp(changedPadding) == expected, passed, total)

  check("Ignore extra trailing bytes", convertBmp(bmp & "extra") == expected, passed, total)

  let testOutput = "test_output.pgm"
  writeFile(testOutput, convertBmp(bmp))
  check("Write and read output file", readFile(testOutput) == expected, passed, total)
  removeFile(testOutput)

  echo "Passed: ", passed, "/", total
  if passed != total:
    quit(1)

when isMainModule:
  if paramCount() == 1 and paramStr(1) == "--test":
    try:
      runTests()
    except CatchableError as e:
      stderr.writeLine("Test error: " & e.msg)
      quit(1)
  elif paramCount() <= 2:
    let inputPath = if paramCount() >= 1: paramStr(1) else: "input.bmp"
    let outputPath = if paramCount() == 2: paramStr(2) else: "output.pgm"
    try:
      let pgm = convertBmp(readFile(inputPath))
      writeFile(outputPath, pgm)
      echo "Input: ", inputPath
      echo "Output: ", outputPath
      echo "BMP converted to grayscale PGM successfully."
    except CatchableError as e:
      stderr.writeLine("Error: " & e.msg)
      quit(1)
  else:
    echo "Usage: main.exe [input.bmp] [output.pgm]"
    echo "       main.exe --test"
    quit(1)
