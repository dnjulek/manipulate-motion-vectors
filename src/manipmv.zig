const std = @import("std");
const vapoursynth = @import("vapoursynth");

pub const vs = vapoursynth.vapoursynth4;
pub const vsh = vapoursynth.vshelper;
pub const zapi = vapoursynth.zigapi;

const allocator = std.heap.c_allocator;

const ScaleVectData = struct {
    node: ?*vs.Node,
    vi: *const vs.VideoInfo,
    scale_x: u8,
    scale_y: u8,
};

// TODO use native endianness?
fn readInt(comptime T: type, input_buffer: []u8, position: u32) struct { T, u32 } {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    return .{ value, position + size };
}

fn scaleInt(comptime T: type, input_buffer: []u8, position: u32, scale: u8) u32 {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, input_buffer[position..][0..size], value * scale, .little);
    return position + @sizeOf(T);
}

export fn getFrameScaleVect(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
    _ = frame_data;
    const d: *ScaleVectData = @ptrCast(@alignCast(instance_data));

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node, frame_ctx);
    } else if (activation_reason == .AllFramesReady) {
        const src = zapi.Frame.init(d.node, n, frame_ctx, core, vsapi);
        const props = src.getPropertiesRW();
        var err: vs.MapPropertyError = undefined;

        // *** Scale analysis data ***

        var position: u32 = 0;
        const analysis_data_in = vsapi.?.mapGetData.?(props, "MVTools_MVAnalysisData", 0, &err);
        if (err != .Success) {
            // TODO error handling I guess
        }
        const analysis_data_len: u32 = @intCast(vsapi.?.mapGetDataSize.?(props, "MVTools_MVAnalysisData", 0, &err));
        if (err != .Success) {
            // TODO error handling I guess
        }

        const analysis_data_out = allocator.alloc(u8, analysis_data_len) catch unreachable;
        defer allocator.free(analysis_data_out);
        std.mem.copyForwards(u8, analysis_data_out, analysis_data_in[0..analysis_data_len]);

        position += @sizeOf(u32); // magic_key (uninitialized)
        position += @sizeOf(u32); // version (uninitialized)
        position = scaleInt(u32, analysis_data_out, position, d.scale_x); // block_size_x
        position = scaleInt(u32, analysis_data_out, position, d.scale_y); // block_size_y
        position += @sizeOf(u32); // pel
        position += @sizeOf(u32); // level_count
        position += @sizeOf(u32); // delta_frame
        position += @sizeOf(u32); // backwards
        position += @sizeOf(u32); // cpu_flags
        position += @sizeOf(u32); // motion_flags
        position = scaleInt(u32, analysis_data_out, position, d.scale_x); // width
        position = scaleInt(u32, analysis_data_out, position, d.scale_y); // height
        position = scaleInt(u32, analysis_data_out, position, d.scale_x); // overlap_x
        position = scaleInt(u32, analysis_data_out, position, d.scale_y); // overlap_y
        position += @sizeOf(u32); // block_count_x
        position += @sizeOf(u32); // block_count_y
        position += @sizeOf(u32); // bits_per_sample
        position += @sizeOf(u32); // chroma_ratio_y
        position += @sizeOf(u32); // chroma_ratio_x
        position = scaleInt(u32, analysis_data_out, position, d.scale_x); // padding_x
        position = scaleInt(u32, analysis_data_out, position, d.scale_y); // padding_y

        // TODO error handling I guess
        _ = vsapi.?.mapSetData.?(props, "MVTools_MVAnalysisData", analysis_data_out.ptr, @intCast(analysis_data_len), .Binary, .Replace);

        // *** Scale vectors ***

        position = 0;
        const vector_data_in = vsapi.?.mapGetData.?(props, "MVTools_vectors", 0, &err);
        if (err != .Success) {
            // TODO error handling I guess
        }
        const vector_data_len: u32 = @intCast(vsapi.?.mapGetDataSize.?(props, "MVTools_vectors", 0, &err));
        if (err != .Success) {
            // TODO error handling I guess
        }

        const vector_data_out = allocator.alloc(u8, vector_data_len) catch unreachable;
        defer allocator.free(vector_data_out);
        std.mem.copyForwards(u8, vector_data_out, vector_data_in[0..vector_data_len]);

        const size, position = readInt(u32, vector_data_out, position);
        // TODO assert size == data_len

        const validity_int, position = readInt(u32, vector_data_out, position);
        if (validity_int == 1) {
            while (position < size) {
                const level_size, const start_position = readInt(u32, vector_data_out, position);
                const end_position = position + level_size;
                position = start_position;
                while (position < end_position) {
                    position = scaleInt(i32, vector_data_out, position, d.scale_x); // x
                    position = scaleInt(i32, vector_data_out, position, d.scale_y); // y
                    position = scaleInt(u64, vector_data_out, position, d.scale_x * d.scale_y); // SAD
                }
            }
        }
        // TODO error handling I guess
        _ = vsapi.?.mapSetData.?(props, "MVTools_vectors", vector_data_out.ptr, @intCast(vector_data_len), .Binary, .Replace);

        return src.frame;
    }
    return null;
}

export fn freeScaleVect(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = core;
    const d: *ScaleVectData = @ptrCast(@alignCast(instance_data));
    vsapi.?.freeNode.?(d.node);
    allocator.destroy(d);
}

export fn createScaleVect(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = user_data;
    var d: ScaleVectData = undefined;
    var map = zapi.Map.init(in, out, vsapi);

    d.node, d.vi = map.getNodeVi("clip");

    d.scale_x = map.getInt(u8, "scaleX") orelse 1;
    d.scale_y = map.getInt(u8, "scaleY") orelse d.scale_x;

    const data: *ScaleVectData = allocator.create(ScaleVectData) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node,
            .requestPattern = .General,
        },
    };
    vsapi.?.createVideoFilter.?(out, "Invert", d.vi, getFrameScaleVect, freeScaleVect, .Parallel, &deps, deps.len, data, core);
}

export fn VapourSynthPluginInit2(plugin: *vs.Plugin, vsapi: *const vs.PLUGINAPI) void {
    _ = vsapi.configPlugin.?("tools.mike.manipmv", "manipmv", "Manipulate Motion Vectors", vs.makeVersion(1, 0), vs.VAPOURSYNTH_API_VERSION, 0, plugin);
    _ = vsapi.registerFunction.?("ScaleVect", "clip:vnode;scaleX:int:opt;scaleY:int:opt;", "clip:vnode;", createScaleVect, null, plugin);
}
