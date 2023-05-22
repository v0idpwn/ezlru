defmodule EzlruTest do
  use ExUnit.Case
  doctest Ezlru

  test "greets the world" do
    assert Ezlru.hello() == :world
  end
end
