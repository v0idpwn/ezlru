defmodule Ezlru do
  use Zig, link_libc: true

  ~Z"""
  const lib_lru = @import("./zig_src/src/main.zig");
  const ZLRU = lib_lru.ZLRU;

  const GlobalMutex = beam.BeamMutex("ezlruglobal");
  const LocalMutex = beam.DynBeamMutex;

  const BeamZLRU = ZLRU(beam.term, beam.term, *LocalMutex);
  const ZLRUHashMap = std.AutoHashMap(beam.term, *BeamZLRU);

  var g_lrus: ?ZLRUHashMap = null;
  var g_gscope_mutex: ?*GlobalMutex = null;
  var g_env: beam.env = null;

  /// nif: init/0
  fn init(env: beam.env) !beam.term {
      if (g_gscope_mutex == null) {
          g_gscope_mutex = try beam.allocator.create(GlobalMutex);
          g_gscope_mutex.?.mutex_ref = null;
          try g_gscope_mutex.?.init();
      }

      if (g_lrus == null) {
          g_lrus = ZLRUHashMap.init(beam.allocator);
      }

      if (g_env == null) {
          g_env = e.enif_alloc_env();
      }

      return beam.make_ok(env);
  }

  /// nif: new/2
  fn new(env: beam.env, name: beam.term, size: beam.term) !beam.term {
      if (g_gscope_mutex) |gscope| {
          gscope.lock();
          defer gscope.unlock();

          if (g_lrus.?.get(name)) |_| {
              return beam.make_error(env);
          } else {
              var name_str = try beam.get_atom_slice(env, name);
              var size_u16 = try beam.get_u16(env, size);

              var local_mutex = try beam.allocator.create(LocalMutex);
              errdefer beam.allocator.destroy(local_mutex);

              var mutex_name = try beam.allocator.alloc(u8, 128);
              errdefer beam.allocator.destroy(&mutex_name);

              _ = try std.fmt.bufPrint(mutex_name, "{s}{s}", .{ "ezlru_local_", name_str });

              local_mutex.name = &mutex_name;
              local_mutex.mutex_ref = null;

              // No need to deinit because deinit is performed by LRU deinit
              try local_mutex.init();

              var lru = try beam.allocator.create(BeamZLRU);
              lru.* = try BeamZLRU.init(beam.allocator, size_u16, local_mutex);
              errdefer lru.deinit();

              try g_lrus.?.put(name, lru);
              return beam.make_ok(env);
          }
      }
      return beam.make_error(env);
  }

  /// nif: lookup/2
  fn lookup(env: beam.env, name: beam.term, key: beam.term) !beam.term {
      if (g_gscope_mutex) |gscope| {
          gscope.lock();
          defer gscope.unlock();
          var lru = g_lrus.?.get(name);

          if (lru == null) {
              return beam.make_error(env);
          }

          if (lru.?.get(key)) |non_nil_value| {
              return e.enif_make_copy(env, non_nil_value);
          } else {
              return beam.make_nil(env);
          }
      } else {
          return beam.make_error(env);
      }
  }

  /// nif: insert/3
  fn insert(env: beam.env, name: beam.term, key: beam.term, value: beam.term) !beam.term {
      if (g_gscope_mutex) |gscope| {
          gscope.lock();
          defer gscope.unlock();
          var lru = g_lrus.?.get(name);

          if (lru == null) {
              return beam.make_error(env);
          }

          const k = e.enif_make_copy(g_env.?, key);
          const v = e.enif_make_copy(g_env.?, value);

          if (try lru.?.put(k, v)) |evicted| {
              var tuple_slice: []beam.term = try beam.allocator.alloc(beam.term, 2);
              defer beam.allocator.free(tuple_slice);

              tuple_slice[0] = e.enif_make_copy(env, evicted.key);
              tuple_slice[1] = e.enif_make_copy(env, evicted.value);

              return beam.make_ok_term(env, beam.make_tuple(env, tuple_slice));
          } else {
              return beam.make_ok_term(env, beam.make_nil(env));
          }
      } else {
          return beam.make_error(env);
      }
  }
  """
end
