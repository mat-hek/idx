defmodule Idx do
  alias __MODULE__.{Key, Primary}

  @behaviour Access

  @enforce_keys [Primary, :indices]
  defstruct @enforce_keys

  def new(enum \\ [], primary_index) do
    map = Map.new(enum, &{{Primary, primary_index.(&1)}, &1})
    %__MODULE__{Primary => primary_index, indices: %{}} |> Map.merge(map)
  end

  def key(index_name, key) do
    {Key, index_name, key}
  end

  def create_index(%__MODULE__{indices: indices} = idx, name, fun) do
    if Map.has_key?(indices, name) do
      raise ArgumentError, "Index #{inspect(name)} already present"
    end

    data = idx |> to_map() |> Map.new(fn {key, value} -> {fun.(value), key} end)

    %{idx | indices: Map.put(indices, name, fun)}
    |> Map.put({__MODULE__, name}, data)
  end

  def drop_index(%__MODULE__{indices: indices} = idx, name) do
    {data, idx} = Map.pop(idx, {__MODULE__, name})

    unless data do
      raise ArgumentError, "Unknown index #{inspect(name)}"
    end

    %{idx | indices: Map.delete(indices, name)}
  end

  def put(%__MODULE__{Primary => primary_index, indices: indices} = idx, value)
      when indices == %{} do
    Map.put(idx, {Primary, primary_index.(value)}, value)
  end

  def put(%__MODULE__{Primary => primary_index, indices: indices} = idx, value) do
    primary_key = primary_index.(value)
    idx = Map.put(idx, {Primary, primary_index.(value)}, value)

    Enum.reduce(indices, idx, fn {name, fun}, idx ->
      name = {__MODULE__, name}
      %{^name => data} = idx
      %{idx | name => Map.put(data, fun.(value), primary_key)}
    end)
  end

  def fetch(%__MODULE__{} = idx, key) do
    key = resolve_key(idx, key)

    case idx do
      %{^key => value} -> {:ok, value}
      %{} -> :error
    end
  end

  def fetch!(idx, key) do
    key = resolve_key!(idx, key)
    %{^key => value} = idx
    value
  end

  def get(idx, key, default \\ nil) do
    case fetch(idx, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  def pop!(idx, key) do
    key = resolve_key!(idx, key)
    {value, idx} = Map.pop!(idx, key)
    {value, remove_value_from_indices(idx, value)}
  end

  def pop(idx, key, default \\ nil) do
    key = resolve_key(idx, key)

    case :maps.take(key, idx) do
      {value, idx} -> {value, remove_value_from_indices(idx, value)}
      :error -> {default, idx}
    end
  end

  defp remove_value_from_indices(%Idx{indices: indices} = idx, value) do
    Enum.reduce(indices, idx, fn {name, fun}, idx ->
      name = {__MODULE__, name}
      %{^name => data} = idx
      key = fun.(value)
      data = Map.delete(data, key)
      %{idx | name => data}
    end)
  end

  def update!(idx, key, fun) do
    key = resolve_key!(idx, key)
    {value, idx} = pop!(idx, key)
    put(idx, fun.(value))
  end

  def get_and_update!(idx, key, fun) do
    key = resolve_key!(idx, key)
    value = fetch!(idx, key)

    case fun.(value) do
      {get, update} -> {get, put(idx, update)}
      :pop -> pop!(idx, key)
    end
  end

  def get_and_update(idx, key, fun) do
    key = resolve_key(idx, key)
    {value, idx} = pop(idx, key)

    case fun.(value) do
      {get, update} -> {get, put(idx, update)}
      :pop -> {value, idx}
    end
  end

  def fast_update!(idx, key, fun) do
    key = resolve_key!(idx, key)
    Map.update!(idx, key, fun)
  end

  def size(%Idx{indices: indices} = idx) do
    map_size(idx) - map_size(Idx.__struct__()) - map_size(indices)
  end

  def to_list(%Idx{} = idx) do
    :maps.fold(
      fn
        {Primary, _key}, value, acc -> [value | acc]
        _key, _value, acc -> acc
      end,
      [],
      idx
    )
    |> :lists.reverse()
  end

  def to_map(%Idx{} = idx) do
    Enum.reduce(Map.from_struct(idx), %{}, fn
      {{Primary, key}, value}, acc -> Map.put(acc, key, value)
      _kv, acc -> acc
    end)
  end

  def member?(%Idx{Idx.Primary => primary} = idx, value) do
    {:ok, value} == Idx.fetch(idx, primary.(value))
  end

  def primary_key!(%{__struct__: Idx} = idx, name, key) do
    name = {__MODULE__, name}
    %{^name => %{^key => primary}} = idx
    primary
  end

  def primary_key(%Idx{} = idx, name, key) do
    name = {__MODULE__, name}

    case idx do
      %{^name => %{^key => primary}} -> {:ok, primary}
      %{} -> :error
    end
  end

  defp resolve_key(_idx, {Primary, primary}) do
    {Primary, primary}
  end

  defp resolve_key(idx, {Key, name, key}) do
    name = {__MODULE__, name}

    case idx do
      %{^name => %{^key => primary}} -> {Primary, primary}
      %{} -> Key.Imaginary
    end
  end

  defp resolve_key(_idx, primary) do
    {Primary, primary}
  end

  defp resolve_key!(_idx, {Primary, primary}) do
    {Primary, primary}
  end

  defp resolve_key!(idx, {Key, name, key}) do
    name = {__MODULE__, name}

    case idx do
      %{^name => %{^key => primary}} -> {Primary, primary}
      %{} -> raise "Unknown key #{inspect(key)} of index #{inspect(name)}"
    end
  end

  defp resolve_key!(_idx, primary) do
    {Primary, primary}
  end
end

defimpl Enumerable, for: Idx do
  def count(idx) do
    {:ok, Idx.size(idx)}
  end

  def member?(idx, value) do
    {:ok, Idx.member?(idx, value)}
  end

  def slice(idx) do
    size = Idx.size(idx)
    {:ok, size, &Idx.to_list/1}
  end

  def reduce(idx, acc, fun) do
    Enumerable.List.reduce(Idx.to_list(idx), acc, fun)
  end
end

defimpl Collectable, for: Idx do
  def into(idx) do
    fun = fn
      idx, {:cont, value} -> Idx.put(idx, value)
      idx, :done -> idx
      _idx, :halt -> :ok
    end

    {idx, fun}
  end
end

defimpl Inspect, for: Idx do
  import Inspect.Algebra

  def inspect(%Idx{Idx.Primary => primary} = idx, opts) do
    opts = %Inspect.Opts{opts | charlists: :as_lists}

    concat([
      "#Idx<",
      to_doc(Idx.to_list(idx), opts),
      ", ",
      "indices: ",
      to_doc([primary: primary] ++ Enum.to_list(idx.indices), opts),
      ">"
    ])
  end
end
