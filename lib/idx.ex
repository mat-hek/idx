defmodule Idx do
  alias __MODULE__.Primary

  @enforce_keys [Primary, :indices]
  defstruct @enforce_keys

  def new(enum \\ [], primary) do
    map = Map.new(enum, &{{Primary, primary.(&1)}, &1})
    %__MODULE__{Primary => primary, indices: %{}} |> Map.merge(map)
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

  def put(%__MODULE__{Primary => primary, indices: indices} = idx, value) when indices == %{} do
    Map.put(idx, {Primary, primary.(value)}, value)
  end

  def put(%__MODULE__{Primary => primary, indices: indices} = idx, value) do
    primary_key = primary.(value)
    idx = Map.put(idx, {Primary, primary.(value)}, value)

    Enum.reduce(indices, idx, fn {name, fun}, idx ->
      name = {__MODULE__, name}
      %{^name => data} = idx
      %{idx | name => Map.put(data, fun.(value), primary_key)}
    end)
  end

  def fetch(%__MODULE__{} = idx, key) do
    key = {Primary, key}

    case idx do
      %{^key => value} -> {:ok, value}
      %{} -> :error
    end
  end

  def fetch(%{__struct__: __MODULE__} = idx, name, key) do
    name = {__MODULE__, name}

    case idx do
      %{^name => %{^key => primary_key}} ->
        primary_key = {Primary, primary_key}
        %{^primary_key => value} = idx
        {:ok, value}

      %{^name => %{}} ->
        :error

      %{} ->
        raise ArgumentError, "Unknown index #{inspect(name)}"
    end
  end

  def fetch!(idx, key) do
    {:ok, value} = fetch(idx, key)
    value
  end

  def fetch!(idx, name, key) do
    {:ok, value} = fetch(idx, name, key)
    value
  end

  def get(idx, key) do
    case fetch(idx, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  def get(idx, name, key) do
    case fetch(idx, name, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  def pop!(%Idx{indices: indices} = idx, key) do
    {value, idx} = Map.pop!(idx, {Primary, key})

    idx =
      Enum.reduce(indices, idx, fn {name, fun}, idx ->
        name = {__MODULE__, name}
        %{^name => data} = idx
        key = fun.(value)
        data = Map.delete(data, key)
        %{idx | name => data}
      end)

    {value, idx}
  end

  def pop!(idx, name, key) do
    name = {__MODULE__, name}
    %{^name => %{^key => primary}} = idx
    pop!(idx, primary)
  end

  def update!(idx, key, fun) do
    {value, idx} = pop!(idx, key)
    put(idx, fun.(value))
  end

  def update!(idx, name, key, fun) do
    {value, idx} = pop!(idx, name, key)
    put(idx, fun.(value))
  end

  def fast_update!(idx, key, fun) do
    Map.update!(idx, {Primary, key}, fun)
  end

  def fast_update!(idx, name, key, fun) do
    name = {__MODULE__, name}
    %{^name => %{^key => primary}} = idx
    fast_update!(idx, primary, fun)
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
