defmodule Idx do
  @moduledoc """
  Collection allowing access via dynamically created indices.

  The API is similar to `Map`. See `create_index/3` for more details
  about indices.

      iex> users = [%{name: "Bob", age: 20}, %{name: "Eve", age: 27}, %{name: "John", age: 45}]
      iex> idx = Idx.new(users, & &1.name)
      iex> Idx.get(idx, "Bob")
      %{name: "Bob", age: 20}
      iex> idx |> Enum.to_list() |> Enum.sort()
      users

  """
  alias __MODULE__.{Key, Primary}

  @behaviour Access

  @enforce_keys [Primary, :indices, :lazy_indices]
  defstruct @enforce_keys

  @type t :: %{:__struct__ => __MODULE__, any => any}

  @typedoc """
  Index function. Returns a key based on the value to be indexed.
  Must be pure (always return the same key for the same value).
  """
  @type index :: (value -> key)
  @type index_name :: atom

  @type key :: any
  @type value :: any

  @type full_key :: primary_key | non_primary_key
  @type primary_key :: key
  @opaque non_primary_key :: {Key, index_name, key}

  @doc """
  Creates a new Idx instance.
  """
  @spec new(Enumerable.t(), index) :: t
  def new(enum \\ [], primary_index) do
    map = Map.new(enum, &{{Primary, primary_index.(&1)}, &1})
    %__MODULE__{Primary => primary_index, indices: %{}, lazy_indices: %{}} |> Map.merge(map)
  end

  @doc """
  Allows accessing a value by a non-primary key in the idx.

  See `create_index/3` for details.
  """
  @spec key(index_name, non_primary_key) :: full_key
  def key(index_name, key) do
    {Key, index_name, key}
  end

  @doc """
  Creates a new non-primary index on the `Idx` instance.

      iex> users = [%{name: "Bob", age: 20}, %{name: "Eve", age: 27}, %{name: "John", age: 45}]
      iex> idx = Idx.new(users, & &1.name)
      iex> idx = Idx.create_index(idx, :initial, &String.first(&1.name))
      iex> Idx.get(idx, Idx.key(:initial, "J"))
      %{name: "John", age: 45}

  If `lazy` option is set to true, the index keys won't be precomputed and stored,
  instead it will always be calculated on demand. This will slow down access, but
  speed up insertion and operations relying on other indices.
  """
  @spec create_index(t, index_name, index, lazy?: boolean()) :: t
  def create_index(%__MODULE__{} = idx, name, fun, options \\ []) do
    %__MODULE__{indices: indices, lazy_indices: lazy_indices} = idx

    if Map.has_key?(indices, name) or Map.has_key?(lazy_indices, name) do
      raise ArgumentError, "Index #{inspect(name)} already present"
    end

    if Keyword.get(options, :lazy?, false) do
      %{idx | lazy_indices: Map.put(lazy_indices, name, fun)}
    else
      data = idx |> to_map() |> Map.new(fn {key, value} -> {fun.(value), key} end)

      %{idx | indices: Map.put(indices, name, fun)}
      |> Map.put({__MODULE__, name}, data)
    end
  end

  @spec drop_index(t, index_name) :: t
  def drop_index(%__MODULE__{} = idx, name) do
    %__MODULE__{indices: indices, lazy_indices: lazy_indices} = idx
    {eager_fun, indices} = Map.pop(indices, name)
    {lazy_fun, lazy_indices} = Map.pop(lazy_indices, name)

    unless eager_fun || lazy_fun do
      raise ArgumentError, "Unknown index #{inspect(name)}"
    end

    idx = Map.delete(idx, {__MODULE__, name})
    %{idx | indices: indices, lazy_indices: lazy_indices}
  end

  @spec put(t, value) :: t
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

  @spec fetch(t, full_key) :: {:ok, value} | :error
  def fetch(%__MODULE__{} = idx, key) do
    key = resolve_key(idx, key)

    case idx do
      %{^key => value} -> {:ok, value}
      %{} -> :error
    end
  end

  @spec fetch!(t, full_key) :: value
  def fetch!(idx, key) do
    key = resolve_key!(idx, key)
    %{^key => value} = idx
    value
  end

  @spec get(t, full_key, value | nil) :: value | nil
  def get(idx, key, default \\ nil) do
    case fetch(idx, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @spec pop!(t, full_key) :: value
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

  @spec update!(t, full_key, (value -> value)) :: t
  def update!(idx, key, fun) do
    key = resolve_key!(idx, key)
    {value, idx} = pop!(idx, key)
    put(idx, fun.(value))
  end

  @doc """
  Updates the value under the key by calling `fun`. No indices can change after the update.

  Thanks to the guarantee that the indices (including the primary index)
  won't change, this function is faster than `update!/3`. However, if the
  indices change, it will leave the `idx` in an invalid state and lead
  to undefined behaviour.
  """
  @spec fast_update!(t, full_key, (value -> value)) :: t
  def fast_update!(idx, key, fun) do
    key = resolve_key!(idx, key)
    Map.update!(idx, key, fun)
  end

  @spec get_and_update!(t, full_key, (value -> {get, update} | :pop)) :: {get, t}
        when get: any, update: value
  def get_and_update!(idx, key, fun) do
    key = resolve_key!(idx, key)
    {value, idx} = pop!(idx, key)

    case fun.(value) do
      {get, update} -> {get, put(idx, update)}
      :pop -> {value, idx}
    end
  end

  @spec get_and_update(t, full_key, (value | nil -> {get, update} | :pop)) :: {get, t}
        when get: any, update: value
  def get_and_update(idx, key, fun) do
    key = resolve_key(idx, key)
    {value, idx} = pop(idx, key)

    case fun.(value) do
      {get, update} -> {get, put(idx, update)}
      :pop -> {value, idx}
    end
  end

  @spec size(t) :: non_neg_integer
  def size(%Idx{indices: indices} = idx) do
    map_size(idx) - map_size(Idx.__struct__()) - map_size(indices)
  end

  @spec to_list(t) :: [value()]
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

  @doc """
  Converts `idx` to a map, where keys are the primary keys of the `idx`.
  """
  @spec to_map(t) :: %{key => value}
  def to_map(%Idx{} = idx) do
    Enum.reduce(Map.from_struct(idx), %{}, fn
      {{Primary, key}, value}, acc -> Map.put(acc, key, value)
      _kv, acc -> acc
    end)
  end

  @spec member?(t, value) :: boolean
  def member?(%Idx{Idx.Primary => primary} = idx, value) do
    {:ok, value} == Idx.fetch(idx, primary.(value))
  end

  @spec primary_key!(t, index_name, non_primary_key) :: primary_key
  def primary_key!(%{__struct__: Idx} = idx, name, key) do
    name = {__MODULE__, name}
    %{^name => %{^key => primary}} = idx
    primary
  end

  @doc """
  Returns the primary key of a value under the given non-primary key.
  """
  @spec primary_key(t, index_name, non_primary_key) :: {:ok, primary_key} | :error
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
    data_ref = {__MODULE__, name}

    case idx do
      %{^data_ref => %{^key => primary}} -> {Primary, primary}
      %{lazy_indices: %{^name => fun}} -> resolve_key_lazy(idx, fun, key)
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
    case resolve_key(idx, {Key, name, key}) do
      Key.Imaginary -> raise "Unknown key #{inspect(key)} of index #{inspect(name)}"
      primary_key -> primary_key
    end
  end

  defp resolve_key!(_idx, primary) do
    {Primary, primary}
  end

  defp resolve_key_lazy(idx, fun, key) do
    Enum.find_value(Map.from_struct(idx), Key.Imaginary, fn
      {{Primary, primary_key}, value} -> if fun.(value) === key, do: {Primary, primary_key}
      _entry -> nil
    end)
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
      to_doc(
        [primary: primary] ++ Enum.to_list(idx.indices) ++ Enum.to_list(idx.lazy_indices),
        opts
      ),
      ">"
    ])
  end
end
