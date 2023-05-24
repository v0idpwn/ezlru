defmodule EzlruTest do
  use ExUnit.Case
  doctest Ezlru

  setup do
    Ezlru.init()
  end

  describe "new/1" do
    test "creates a LRU" do
      assert :ok = Ezlru.new(:create, 10)
    end

    test "returns error if already exists" do
      assert :ok = Ezlru.new(:error_if_already_exists, 10)
      assert :error = Ezlru.new(:error_if_already_exists, 10)
    end

    test "raises if not an atom" do
      assert_raise Ezlru.ZigError, fn ->
        Ezlru.new("iraise", 10)
      end
    end
  end

  describe "lookup/2" do
    test "returns error if lru doesn't exist" do
      assert :error = Ezlru.lookup(:doesnt_exist, :my_key)
    end

    test "returns nil if key isn't set" do
      :ok = Ezlru.new(:returns_nil_if_not_set, 10)
      assert nil == Ezlru.lookup(:returns_nil_if_not_set, :my_key)
    end
  end

  describe "insert/3" do
    test "returns error if lru doesn't exist" do
      assert :error = Ezlru.insert(:doesnt_exist, :my_key, 1)
    end

    test "returns nil if key didnt exist previously" do
      Ezlru.new(:returns_nil_if_key_didnt_exist_yet, 10)
      assert {:ok, nil} = Ezlru.insert(:returns_nil_if_key_didnt_exist_yet, :my_key, 1)
    end

    test "returns previous value if key was updated" do
      Ezlru.new(:returns_previous_value_if_updated, 10)
      {:ok, nil} = Ezlru.insert(:returns_previous_value_if_updated, :my_key, 1)
      assert {:ok, {:my_key, 1}} = Ezlru.insert(:returns_previous_value_if_updated, :my_key, 2)
    end

    # regression test: we repeat a few operations to try to trigger memory errors
    test "storing lists" do
      Ezlru.new(:storing_lists, 1)

      for _ <- 1..10 do
        assert {:ok, _} = Ezlru.insert(:storing_lists, :my_key, Enum.to_list(1..200))

        assert {:ok, {:my_key, Enum.to_list(1..200)}} ==
                 Ezlru.insert(:storing_lists, :my_key, Enum.to_list(3..5))

        assert {:ok, {:my_key, Enum.to_list(3..5)}} ==
                 Ezlru.insert(:storing_lists, :my_key, Enum.to_list(600..700))

        assert {:ok, {:my_key, Enum.to_list(600..700)}} ==
                 Ezlru.insert(:storing_lists, :my_key, Enum.to_list(20..700))

        assert {:ok, {:my_key, Enum.to_list(20..700)}} ==
                 Ezlru.insert(:storing_lists, :my_key, [])

        assert {:ok, {:my_key, []}} == Ezlru.insert(:storing_lists, :my_key, 1)
      end
    end
  end
end
