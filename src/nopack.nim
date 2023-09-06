from os import 
  fileExists, `/`, copyDir,
  removeDir, createDir, dirExists
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

# -----------------
# Reporting Helpers
# -----------------

proc error(filename, msg: string) {.raises: [IOError].} =
  raise newException(IOError, filename & " " & msg)

proc msgInfo(reason, msg: string) =
  echo "\e[1;34m[", reason, "]\e[00m ", msg

proc msgError(reason, msg: string) =
  echo "\e[1;31m[", reason, "]\e[00m ", msg

# ----------------
# File I/O Helpers
# ----------------

proc listfile(filename: string): File =
  if not open(result, filename, fmRead):
    error(filename, " not found")

proc packfile(filename: string): File =
  if not open(result, filename, fmWrite):
    error(filename, " not writtable")

# -----------------
# Icon Chunk Writer
# -----------------

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
    error("icons.dat", "illformed signature")

proc rasterize(filename: string, fit: cshort, isRGBA: bool): PImageChunk =
  # Check if File Exists
  if not fileExists(filename):
    error(filename, "not found")
  # Check Filename type
  result = if filename.endsWith(".svg"):
    nopack_load_svg(filename, fit, cint isRGBA)
  else: nopack_load_bitmap(filename, fit, cint isRGBA)
  # Check if file was loaded
  if isNil(result):
    error(filename, "is invalid")

proc write(file: File, chunk: PImageChunk) =
  let bytes = sizeof(ImageChunk) + int(chunk.bytes)
  # Copy Chunk to File
  if writeBuffer(file, chunk, bytes) != bytes:
    error("icons.dat", "writing is illformed")

proc info(line: string): tuple[file: string, fit: cshort] =
  let s = split(line, " : ")
  const pack = "pack" / "icons"
  result.file = pack / s[0]
  # Extract Size
  try: 
    result.fit = cshort parseInt s[1]
  except ValueError:
    error(result.file, "invalid fit size")

proc pack(isRGBA = false) {.raises: [IOError].} =
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
    # Debug Information
    msgInfo("PACK", line)
    # Write Chunk to File
    write(pack, chunk)
    nopack_load_dealloc(chunk)

# -------------------
# Folder Copy Writter
# -------------------

proc folder(line: string): tuple[src, dst: string, extern: bool] =
  let 
    s = split(line, " : ")
    s1 = split(s[0], "-:-")
  # Check if Path is Valid
  if s.len != 2 and s1.len != 2:
    error(line, "invalid path")
  # Extract Paths
  result.src = s1[0]
  result.dst = s1[1]
  # Extract Extern
  try:
    result.extern = parseInt(s[1]) > 0
  except ValueError:
    error(result.src, "invalid path mode")

proc copy() {.raises: [OSError, IOError].} =
  # Prepare Folder List
  let list = listfile("pack" / "paths.list")
  # Copy Paths to Data
  for line in lines(list):
    var f = line.folder()
    if not f.extern:
      f.src = "pack" / f.src
    # Check Source Path Existence
    if not dirExists(f.src):
      error(f.src, "not found")
    # Debug Information
    let sym = if f.extern: " >> " else: " -> "
    msgInfo("COPY", f.src & sym & "data" / f.dst)
    # Copy Folder to Destination
    f.dst = "data" / f.dst
    copyDir(f.src, f.dst)

# ---------
# Main Proc
# ---------

proc main() =
  echo "nogui data packer 0.2"
  echo "mrgaturus 2023 \n"
  try:
    # Clear Data Folder
    echo "Creating data folder..."
    removeDir("data")
    createDir("data")
    # Pack Icons and Copy Paths
    echo "Packing icons.dat..."; pack()
    echo "\nCopying paths..."; copy()
  except IOError as error:
    msgError("IO ERROR", error.msg)
    removeDir("data")
    quit(65535)
  except OSError as error:
    msgError("OS ERROR", error.msg)
    removeDir("data")
    quit(32767)

when isMainModule:
  main()
