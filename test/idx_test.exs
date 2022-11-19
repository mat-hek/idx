defmodule IdxTest do
  use ExUnit.Case

  doctest Idx

  test "access" do
    users = [%{name: "Bob", age: 20}, %{name: "Eve", age: 27}, %{name: "John", age: 45}]
    idx = Idx.new(users, & &1.name)

    assert %{name: "Bob", age: 20} == Idx.fetch!(idx, "Bob")

    assert %{name: "Bob", age: 20} == Idx.get(idx, "Bob")

    assert {:ok, %{name: "Bob", age: 20}} == Idx.fetch(idx, "Bob")
    assert :error == Idx.fetch(idx, "Absent")

    assert users == idx |> Enum.to_list() |> Enum.sort()

    idx = Idx.update!(idx, "Bob", &%{&1 | name: "Steve"})
    assert %{name: "Steve", age: 20} == Idx.fetch!(idx, "Steve")
    assert :error == Idx.fetch(idx, "Bob")

    idx = Idx.fast_update!(idx, "Eve", &%{&1 | age: &1.age + 1})
    assert %{name: "Eve", age: 28} == Idx.fetch!(idx, "Eve")

    assert {45, idx} = Idx.get_and_update!(idx, "John", &{&1.age, %{&1 | name: "Frank"}})
    assert %{name: "Frank", age: 45} == Idx.fetch!(idx, "Frank")
    assert :error == Idx.fetch(idx, "John")

    idx = Idx.put(idx, %{name: "Anna", age: 50})
    assert %{name: "Anna", age: 50} = Idx.fetch!(idx, "Anna")
    assert Idx.member?(idx, %{name: "Anna", age: 50})

    assert 4 == Enum.count(idx)
  end
end
