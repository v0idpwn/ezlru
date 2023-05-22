defmodule Ezlru do
  use Zig

  ~Z"""
  const lib_lru = @import("./zig_src/src/main.zig");
  const ZLRU = lib_lru.ZLRU;

  var lrus : ?std.AutoHashMap(beam.term, *ZLRU(beam.term, beam.term, beam.BeamMutex("ezlru_global"))) = null;
  var gscope_mutex : ?beam.BeamMutex("ezlru_global") = null;

  /// nif: new/1
  fn new(env: beam.env, name: beam.term) !beam.term {
    // FIXME: data races, create separate init
    if(gscope_mutex == null){
      gscope_mutex = try beam.BeamMutex("ezlru_global").init();
    }

    gscope_mutex.?.lock();
    defer gscope_mutex.?.unlock();
    std.debug.print("pre-lookup", .{});

    if(lrus == null){
      lrus = std.AutoHashMap(beam.term, *ZLRU(beam.term, beam.term, beam.BeamMutex("ezlru_global"))).init(beam.allocator);
    }
    if(lrus.?.get(name) == null){
      // TODO: use multiple mutexes when there is support dynamic names for beam mutex in zigler
      var ref = &try ZLRU(beam.term, beam.term, beam.BeamMutex("ezlru_global")).init(beam.allocator, 256, gscope_mutex);
      try lrus.?.put(name, ref);
    }

    return beam.make_ok(env);
  }

  /// nif: lookup/2
  fn lookup(env: beam.env, name: beam.term, key: beam.term) !beam.term {
      std.debug.print("pre-lookup", .{});

    if(lrus)|initialized_lrus|{
      if(initialized_lrus.get(name))|lru|{
        if(lru.get(key)) |value| {
          return value;
        } else {
          return beam.make_nil(env);
        }
      }
    }

    return beam.raise_function_clause_error(env);
  }
  """
end
