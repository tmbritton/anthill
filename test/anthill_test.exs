defmodule AnthillTest do
  use ExUnit.Case
  doctest Anthill

  test "greets the world" do
    assert Anthill.hello() == :world
  end
end
