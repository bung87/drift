import std/strutils

type PathOp* = object
  cmd*: char
  values*: seq[float64]

proc with[K, V](T: typedesc[array], values: openArray[(K, V)]): T =
  for (i, x) in values:
    result[i] = x

const CmdSize = with(
  array[char, int],
  {
    'A': 7, 'C': 6, 'H': 1, 'L': 2, 'M': 2, 'Q': 4, 'S': 4, 'T': 2, 'V': 1,
    'a': 7, 'c': 6, 'h': 1, 'l': 2, 'm': 2, 'q': 4, 's': 4, 't': 2, 'v': 1,
  },
)

iterator groups*(op: PathOp): tuple[group: seq[float64], idx: int] =
  let size = CmdSize[op.cmd]
  var idx = 0
  for i in countup(0, op.values.len-size, size):
    yield (op.values[i..<i+size], idx)
    idx += 1

iterator ops*(data: string): PathOp =
  var
    cmd = '\0'
    chunk = ""
    chunkHasPeriod = false
    values: seq[float64]
  for c in data:
    if c >= 'A' and c <= 'z':
      if chunk.len > 0:
        values.add(chunk.parseFloat())
      if values.len > 0:
        yield PathOp(cmd: cmd, values: values)
        values = @[]
      cmd = c
      chunk = ""
      values = @[]
      chunkHasPeriod = false
    elif c == '-':
      if chunk.len > 0:
        # A hyphen should only come at the beginning of a number. If the dash comes after the beginning,
        # that means it's the beginning of a new number.
        values.add(chunk.parseFloat())
        chunk = ""
        chunkHasPeriod = false
      chunk &= c
    elif c == '.':
      if chunkHasPeriod:
        values.add(chunk.parseFloat())
        chunk = "0"
      else:
        chunkHasPeriod = true
      chunk &= '.'
    elif c >= '0' and c <= '9':
      chunk &= c
    elif c == ',' or c == ' ':
      if chunk.len > 0:
        values.add(chunk.parseFloat())
        chunk = ""
        chunkHasPeriod = false
  
  # Yield final operation if there are remaining values
  if chunk.len > 0:
    values.add(chunk.parseFloat())
  if values.len > 0:
    yield PathOp(cmd: cmd, values: values)
