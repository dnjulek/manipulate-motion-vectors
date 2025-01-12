# Manipulate Motion Vectors

A vapoursynth plugin to do potentially useful things with motion vectors that have already been generated.

## Overview

Motion vectors are useful for a variety of video processing tasks, and there is a long history of tooling related generating and using them. This historical tooling has generally coupled creating the motion vectors and consuming them into one plugin, MVTools. But it is the author's opinion that the decoupled tooling with a standard interface is reasonable and desirable. There is not quite a standard interface among the various versions and ports of MVTools so for now this plugin specifically targets the conventions used by [dubhater/vapoursynth-mvtools](https://github.com/dubhater/vapoursynth-mvtools) (see the [assumed conventions](#assumed-conventions) section for details).

## Functions

### ScaleVect

>[!WARNING]
>Arbitrary scaling of motion vectors is possible and conceptually reasonable and is thus allowed by this plugin. However subsequent operations which use the motion vectors may not support all of the scaled properties. For example scaling 8x8 blocks by 5x results in 40x40 blocks which aren't something MAnalyse supports generating.

Scales `image_size`, `block_size`, `overlap`, `padding`, and the individual `motion_vector`s contained in `MAnalyse` output by arbitrary and independent `x` and `y` factors. This is mostly useful to use motion vectors generated on a downscaled clip to perform operations on the full size clip (e.g. calculating motion vectors at 1080p and applying them at 4K).

#### Usage
```py
mvmanip.ScaleVect(vnode clip[, int scaleX=1, int scaleY=scaleX])
```
#### Parameters
- clip:\
A clip generated by `mvtools.MAnalyse()` or which otherwise follows its conventions.
- scaleX:\
The scale factor to use horizontally.\
This is limited to an 8 bit value, but practical scale factors are likely single digit.\
Default value is `1` (no scaling).
- scaleY:\
The scale factor to use vertically.\
This is limited to an 8 bit value, but practical scale factors are likely single digit.\
Default value is the same as `scaleX`.

#### Examples
```py
# Use vectors from 1080p clip to denoise 4K clip
SCALE = 2
clip = vs.core.std.BlankClip(3840, 2160)
small_clip = clip.resize.Bilinear(clip.width // SCALE, clip.height // SCALE)

small_msuper = small_clip.mv.Super()
small_forward = small_msuper.mv.Analyse()
small_backward = small_msuper.mv.Analyse(isb=True)

big_msuper = clip.mv.Super()
upscaled_forward = small_forward.mvmanip.ScaleVect(SCALE)
upscaled_backward = small_backward.mvmanip.ScaleVect(SCALE)

denoised = clip.mv.Degrain1(big_msuper, upscaled_backward, upscaled_forward)
```

## Assumed Conventions

> [!NOTE]
> No MVTools version really documents its conventions explicitly since they are considered to be internal. So the descriptions in this section should not be considered official, but they are hopefully correct, and serve to at least document the assumptions this plugin is making.

The [dubhater/vapoursynth-mvtools](https://github.com/dubhater/vapoursynth-mvtools) plugin stores all of its working data for motion vectors as binary data in vapoursynth frame props on the clip which results from calling `mv.Analyse()`. Specifically there are two props of interest `MVTools_MVAnalysisData` and `MVTools_vectors`.

All of this data is serialized rather implictly from C++ structs. Most of these structs contain only signed integers (even for fields which do not have logical negative interpretations) and bytes are written with native endianness. For deserialization I have chosen to interpret fields that should not be negative (e.g. width, height, size) as unsigned and always use little endian byte order. These nuances are hopefully not relevant in practice as the positive integer range of a signed 32 bit integer is still much larger than practical video sizes and almost every host running MVTools is likely to be little endian natively. Still it would be nice conceptually if future motion vector work could make these conventions explicit; for this reason the types below will be listed with the signedness I think they should have.

### MVTools_MVAnalysisData

This just contains some metadata about the context in which the vectors were generated. The length of this data is expected to always be 84 bytes (21 32-bit integers) in the following order:

> [!IMPORTANT]
> The `magic_key` and `version` appear to be uninitialized by the MVTools plugin and so have no usable data in them.

```
u32 magic_key
u32 version
u32 block_size_x
u32 block_size_y
u32 pel
u32 level_count
u32 delta_frame
u32 backwards
u32 cpu_flags
u32 motion_flags
u32 width
u32 height
u32 overlap_x
u32 overlap_y
u32 block_count_x
u32 block_count_y
u32 bits_per_sample
u32 chroma_ratio_y
u32 chroma_ratio_x
u32 padding_x
u32 padding_y
```

### MVTools_vectors

This contains the actual motion vector data for all levels of motion vector calculation. The structure of a single motion vector is simply:

```
i32 x
i32 y
u64 sad
```

These are serialized without any padding (16 bytes per vector). Each level is structured as:

```
u32 size
[] vectors
```

Again without any padding. So for example a level with 10 vectors would have a size value of 164 (16 bytes per vector * 10 vectors + 4 bytes for the size).

This is ultimately structured as:

```
u32 size
[] levels
```

Again without any padding. The value stored in size is therefore expected to be equivalent to the size which vapoursynth reports for the frame property.