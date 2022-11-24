# Idx

Idx is a collection that allows creating indices on it and accessing it with a map-like API, for example:

```elixir
iex> users = [%{name: "Bob", age: 20}, %{name: "Eve", age: 27}, %{name: "John", age: 45}]
iex> idx = Idx.new(users, & &1.name)
iex> Idx.get(idx, "Bob")
%{name: "Bob", age: 20}
iex> idx = Idx.create_index(idx, :initial, &String.first(&1.name))
iex> Idx.get(idx, Idx.key(:initial, "J"))
%{name: "John", age: 45}
iex> idx |> Enum.to_list() |> Enum.sort()
[%{name: "Bob", age: 20}, %{name: "Eve", age: 27}, %{name: "John", age: 45}]
```

For more details, see the [docs](https://hexdocs.pm/idx).

## Installation

The package can be installed by adding `idx` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:idx, "~> 0.1.0"}
  ]
end
```
