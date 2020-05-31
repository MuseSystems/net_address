defmodule IP.Range do

  @moduledoc """
  Convenience type which encapsulates the idea of a contiguous range
  of IP addresses.

  ### NB

  The distinction between an `IP.Range` and an `IP.Subnet` is that a Subnet
  must have its bounds at certain powers-of-two and multiple thereof that
  are governed by the subnet bit-length.  A range is not constrained and
  is a simple "dumb list of ip addresses".  Typically ranges will be proper
  subsets of Subnets.

  ### Enumerable

  Implements the Enumerable protocol, so the following sorts of things
  are possible:

  ```elixir
  iex> import IP
  iex> Enum.map(~i"10.0.0.3..10.0.0.5", &IP.to_string/1)
  ["10.0.0.3", "10.0.0.4", "10.0.0.5"]
  ```
  """

  @enforce_keys [:first, :last]

  defstruct @enforce_keys

  @typedoc "ip ranges typed to either ipv4 or ipv6"
  @type t(ip_type) :: %__MODULE__{
    first: ip_type,
    last: ip_type
  }

  @typedoc "generic ip range"
  @type t() :: t(IP.v4) | t(IP.v6)

  require IP

  @spec is_range(any) :: Macro.t
  @doc """
  true if the argument is an proper ip range

  checks if the range is well-ordered.

  usable in guards.

  ```elixir
  iex> import IP
  iex> IP.Range.is_range(~i"10.0.0.1..10.0.0.3")
  true
  iex> IP.Range.is_range(:foo)
  false
  iex> IP.Range.is_range(%IP.Range{first: ~i"10.0.0.3", last: ~i"10.0.0.1"})
  false
  ```
  """
  defguard is_range(range) when is_struct(range) and
    :erlang.map_get(:__struct__, range) == __MODULE__ and
    ((IP.is_ipv4(:erlang.map_get(:first, range)) and
      IP.is_ipv4(:erlang.map_get(:last, range))) or
     (IP.is_ipv6(:erlang.map_get(:first, range)) and
     IP.is_ipv6(:erlang.map_get(:last, range)))) and
    (:erlang.map_get(:first, range) <= :erlang.map_get(:last, range))

  @spec new(IP.addr, IP.addr) :: t
  @doc """
  Creates a new IP range, with validation.

  If your provide an out-of-order range, it will raise `ArgumentError`.

  ```elixir
  iex> IP.Range.new({10, 0, 0, 1}, {10, 0, 0, 5})
  %IP.Range{
    first: {10, 0, 0, 1},
    last: {10, 0, 0, 5}
  }
  ```
  """
  def new(first, last) when (IP.is_ipv4(first) and IP.is_ipv4(last)) or
                            (IP.is_ipv6(first) and IP.is_ipv6(last)) do
    unless first <= last do
      raise ArgumentError, "ip range must be ascending, given #{inspect first} and #{inspect last}"
    end

    %__MODULE__{first: first, last: last}
  end

  @spec from_string(String.t) :: t
  @doc """
  converts a string to an ip range.

  The delimiter must be "..", as this is compatible with both
  ipv4 and ipv6 addresses

  checks if the range is well-ordered.

  ```elixir
  iex> import IP
  iex> IP.Range.from_string("10.0.0.3..10.0.0.5")
  %IP.Range{
    first: {10, 0, 0, 3},
    last: {10, 0, 0, 5}
  }
  ```
  """
  def from_string(range_str) when is_binary(range_str) do
    range_str
    |> String.split("..")
    |> Enum.map(&IP.from_string/1)
    |> case do
      [first, last] when IP.is_ipv4(first) and IP.is_ipv4(last) ->
        new(first, last)
      [first, last] when IP.is_ipv6(first) and IP.is_ipv6(last) ->
        new(first, last)
      _ ->
        raise ArgumentError, "improper ip range string #{range_str}"
    end
  end

  @spec to_string(t) :: String.t
  @doc """
  converts a ip range to a string with delimiter ".."

  checks if the range is well-ordered.

  ```elixir
  iex> IP.Range.to_string(%IP.Range{first: {10, 0, 0, 3},last: {10, 0, 0, 5}})
  "10.0.0.3..10.0.0.5"
  ```
  """
  def to_string(range) when is_range(range) do
    "#{IP.to_string range.first}..#{IP.to_string range.last}"
  end

  @doc false
  def type(range) when is_range(range), do: IP.type(range.first)
end

defimpl Inspect, for: IP.Range do
  import Inspect.Algebra

  def inspect(range, _opts) do
    concat(["~i\"", IP.Range.to_string(range) , "\""])
  end
end

defimpl Enumerable, for: IP.Range do
  alias IP.Range

  @spec count(Range.t) :: {:ok, non_neg_integer}
  def count(range) do
    {:ok, IP.to_integer(range.last) - IP.to_integer(range.first) + 1}
  end

  @spec member?(Range.t, IP.addr) :: {:ok, boolean}
  def member?(range, this_ip) do
    {:ok, range.first <= this_ip and this_ip <= range.last}
  end

  @spec reduce(Range.t, Enumerable.acc, fun) :: Enumerable.result
  def reduce(_subnet, {:halt, acc}, _), do: {:halted, acc}
  def reduce(subnet, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(subnet, &1, fun)}
  def reduce(subnet = %{first: first, last: last}, {:cont, acc}, fun) when first <= last do
    reduce(%{subnet | first: IP.next(first)}, fun.(first, acc), fun)
  end
  def reduce(_subnet, {:cont, acc}, _fun), do: {:done, acc}

  @spec slice(Range.t) :: {:ok, non_neg_integer, Enumerable.slicing_fun}
  def slice(range) do
    type = Range.type(range)
    {:ok, count} = count(range)

    {:ok, count, fn start, length ->
      first_int = IP.to_integer(range.first) + start
      last_int = first_int + length - 1
      Enum.map(first_int..last_int, &IP.from_integer(&1, type))
    end}
  end
end
