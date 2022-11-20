defmodule IdxTest do
  use ExUnit.Case

  doctest Idx

  @data [%{name: "Bob", age: 20}, %{name: "Eve", age: 27}, %{name: "John", age: 45}]

  test "primary access" do
    idx = Idx.new(@data, & &1.name)
    test_access(idx, & &1)
  end

  test "non-primary access" do
    idx = Idx.new(@data, & &1) |> Idx.create_index(:user_name, & &1.name)
    test_access(idx, &Idx.key(:user_name, &1))
    idx = Idx.drop_index(idx, :user_name)
    assert :error == Idx.fetch(idx, Idx.key(:user_name, "Bob"))
  end

  test "lazy access" do
    idx = Idx.new(@data, & &1) |> Idx.create_index(:user_name, & &1.name, lazy?: true)
    test_access(idx, &Idx.key(:user_name, &1))
    idx = Idx.drop_index(idx, :user_name)
    assert :error == Idx.fetch(idx, Idx.key(:user_name, "Bob"))
  end

  defp test_access(idx, key_gen) do
    assert %{name: "Bob", age: 20} == Idx.fetch!(idx, key_gen.("Bob"))

    assert %{name: "Bob", age: 20} == Idx.get(idx, key_gen.("Bob"))

    assert {:ok, %{name: "Bob", age: 20}} == Idx.fetch(idx, key_gen.("Bob"))
    assert :error == Idx.fetch(idx, "Absent")

    assert @data == idx |> Enum.to_list() |> Enum.sort()

    idx = Idx.update!(idx, key_gen.("Bob"), &%{&1 | name: "Steve"})
    assert %{name: "Steve", age: 20} == Idx.fetch!(idx, key_gen.("Steve"))
    assert :error == Idx.fetch(idx, "Bob")

    idx = Idx.fast_update!(idx, key_gen.("Eve"), &%{&1 | age: &1.age + 1})
    assert %{name: "Eve", age: 28} == Idx.fetch!(idx, key_gen.("Eve"))

    assert {45, idx} =
             Idx.get_and_update!(idx, key_gen.("John"), &{&1.age, %{&1 | name: "Frank"}})

    assert %{name: "Frank", age: 45} == Idx.fetch!(idx, key_gen.("Frank"))
    assert :error == Idx.fetch(idx, key_gen.("John"))

    idx = Idx.put(idx, %{name: "Anna", age: 50})
    assert %{name: "Anna", age: 50} = Idx.fetch!(idx, key_gen.("Anna"))
    assert Idx.member?(idx, %{name: "Anna", age: 50})

    assert 4 == Enum.count(idx)
  end
end
