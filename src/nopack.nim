from os import 
  fileExists, `/`, copyDir,
  existsOrCreateDir, dirExists
from strutils import parseInt, split, endsWith

{.compile: "nopack.c".}
{.push header: "nopack.h".}

type
  ImageChunk {.importc: "image_chunk_t".} = object
    bytes: cuint
    w, h, fit: cshort
    channels: cshort
    # Allocated Chunk
    pad0: cuint
    buffer: UncheckedArray[byte]
  PImageChunk = ptr ImageChunk

{.push importc.}

proc nopack_load_svg(filename: cstring, fit: cint, isRGBA: cint): PImageChunk
proc nopack_load_bitmap(filename: cstring, fit: cint, isRGBA: cint): PImageChunk
proc nopack_load_dealloc(chunk: PImageChunk)

{.pop.} # importc
{.pop.} # header

# ----------------
# File I/O Helpers
# ----------------

{.push raises: [IOError].}

proc listfile(filename: string): File =
  if not open(result, filename, fmRead):
    raise newException(IOError, filename & " not found")

proc packfile(filename: string): File =
  if not open(result, filename, fmWrite):
    raise newException(IOError, filename & " not writtable")

{.pop.}

# -----------------
# Icon Chunk Writer
# -----------------

{.push raises: [IOError].}

proc header(file: File, isRGBA: bool) =
  const
    NOGUIRgbSignature = 0x4247524955474f4e'u64 # "NOGUIRGB"
    NOGUIAlphaSignature = 0x4955474f4e'u64 # "NOGUI   "
    UInt64Size = sizeof(uint64)
  # Write Header to File
  var signature: uint64
  signature = if isRGBA:
    NOGUIRgbSignature
  else: NOGUIAlphaSignature
  if writeBuffer(file, addr signature, sizeof UInt64Size) != UInt64Size:
    raise newException(IOError, "illformed signature")

proc rasterize(filename: string, fit: cshort, isRGBA: bool): PImageChunk =
  # Check if File Exists
  if not fileExists(filename):
    raise newException(IOError, "not found")
  # Check Filename type
  result = if filename.endsWith(".svg"):
    nopack_load_svg(filename, fit, cint isRGBA)
  else: nopack_load_bitmap(filename, fit, cint isRGBA)
  # Check if file was loaded
  if isNil(result):
    raise newException(IOError, filename & " is invalid")

proc write(file: File, chunk: PImageChunk) =
  let bytes = sizeof(ImageChunk) + int(chunk.bytes)
  # Copy Chunk to File
  if writeBuffer(file, chunk, bytes) != bytes:
    raise newException(IOError, "writing is illformed")

proc info(line: string): tuple[file: string, fit: cshort] =
  let s = split(line, " : ")
  const pack = "pack" / "icons"
  result.file = pack / s[0]
  # Extract Size
  try: 
    result.fit = cshort parseInt s[1]
  except ValueError:
    raise newException(IOError, result.file & " invalid fit size")

proc pack(isRGBA = false) =
  # Prepare Icons File
  let 
    list = listfile("pack" / "icons.list")
    pack = packfile("data" / "icons.dat")
  # Write Pack Signature
  header(pack, isRGBA)
  # Write Each File
  for line in lines(list):
    let 
      info = info(line)
      chunk = rasterize(info.file, info.fit, isRGBA)
    echo "[PACKED] " & line
    # Write Chunk to File
    write(pack, chunk)
    nopack_load_dealloc(chunk)

{.pop.} # raises

# -------------------
# Folder Copy Writter
# -------------------

{.push raises: [IOError].}

proc folder(line: string): tuple[src, dst: string, extern: bool] =
  let 
    s = split(line, " : ")
    s1 = split(s[0], "-:-")
  # Check if Path is Valid
  if s.len != 2 and s1.len != 2:
    raise newException(IOError, line & " invalid path")
  # Check Source Path Existence
  if not s1[0].dirExists:
    raise newException(IOError, s1[0] & " don't exists")
  # Extract Paths
  result.src = s1[0]
  result.dst = s1[1]
  # Extract Extern
  try:
    result.extern = parseInt(s[1]) > 0
  except ValueError:
    raise newException(IOError, result.src & " invalid path mode")

{.pop.}

proc copy() {.raises: [OSError, IOError].} =
  # Prepare Folder List
  let list = listfile("pack" / "paths.list")
  # Copy Paths to Data
  for line in lines(list):
    var f = line.folder()
    if not f.extern:
      f.src = "data" / f.src
    # Copy Folder to Destination
    copyDir(f.src, f.dst)

# ---------
# Main Proc
# ---------

proc main() =
  echo "nogui data packer 0.2"
  echo "mrgaturus 2023"
  try: 
    pack() # Pack Icons
    copy() # Copy Folder
  except IOError as error:
    echo "[ERROR] ", error.msg
    quit(65535)
  except OSError as error:
    echo "[OS ERROR]", error.msg
    quit(32767)

when isMainModule:
  main()
