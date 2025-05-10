defmodule ExTracker.UDP.Router do
  require Logger
  use GenServer
  import Bitwise
  alias ExTracker.Utils

  @protocol_magic   0x41727101980
  @action_connect   0
  @action_announce  1
  @action_scrape    2
  @action_error     3

  @doc """
  Starts a UDP Router on the given port
  """
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    index = Keyword.get(args, :index, 0)
    name = Keyword.get(args, :name, __MODULE__)
    port = Keyword.get(args, :port, -1)

    Process.put(:index, index)
    Process.put(:name, name)

    # open the UDP socket in binary mode, active, and allow address (and if needed, port) reuse
    case :gen_udp.open(port, [
      :inet,
      :binary,
      active: :once,
      reuseaddr: true
    ]
    ++ set_binding_address()
    ++ set_socket_buffer()
    ++ set_reuseport()
    ) do
      {:ok, socket} ->
        Logger.debug("#{Process.get(:name)} started on port #{port}")

        set_receive_buffer(socket)
        set_send_buffer(socket)

        {:ok, %{socket: socket, port: port}}

      {:error, reason} ->
        Logger.error("#{Process.get(:name)} startup error: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp set_binding_address() do
    [ip: Application.get_env(:extracker, :bind_address_ipv4, {0,0,0,0})]
  end

  defp set_reuseport() do
    case Application.get_env(:extracker, :udp_routers, -1) do
      0 -> []
      1 -> []
      _ -> [reuseport: true]
    end
  end

  defp set_socket_buffer() do
    case Application.get_env(:extracker, :udp_buffer_size, -1) do
      -1 -> []
      value -> [buffer: value]
    end
  end

  defp set_receive_buffer(socket) do
    case Application.get_env(:extracker, :udp_recbuf_size, -1) do
      -1 -> :ok
      value ->
        case :inet.setopts(socket, [{:recbuf, value}]) do
          :ok ->
            Logger.debug("#{Process.get(:name)} set receive buffer size to #{value}")
          {:error, _error} ->
            Logger.error("#{Process.get(:name)} failed to change receive buffer size ")
        end
    end
  end

  defp set_send_buffer(socket) do
    case Application.get_env(:extracker, :udp_sndbuf_size, -1) do
      -1 -> :ok
      value ->
        case :inet.setopts(socket, [{:sndbuf, value}]) do
          :ok ->
            Logger.debug("#{Process.get(:name)} set send buffer size to #{value}")
          {:error, _error} ->
            Logger.error("#{Process.get(:name)} failed to change send buffer size ")
        end
    end
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    name = Process.get(:name)
    # delegate message handling to a Task under the associated supervisor
    supervisor = Process.get(:index) |> ExTracker.UDP.Supervisor.get_task_supervisor_name()
    Task.Supervisor.start_child(supervisor, fn ->
      process_packet(name, socket, ip, port, data)
    end)

    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp match_connection_id(connection_id, ip, port) do
    <<t::integer-unsigned-8, _s::integer-unsigned-56>> = Utils.pad_to_8_bytes(:binary.encode_unsigned(connection_id))
    case generate_connection_id(t, ip, port) do
      ^connection_id ->
        case expired_connection_id(t) do
          true -> {:error, "connection id expired"}
          false -> :ok
        end
      _ -> {:error, "connection id mismatch"}
    end
  end

  defp expired_connection_id(t) do
    current_t = (System.monotonic_time(:second) >>> 6) &&& 0xFF
    cond do
      current_t < t -> true  # t overflowed already (edge case here)
      current_t > (t + 1) -> true # t increased at least two times
      true -> false
    end
  end

  # connection id is derived from known data so we dont need to store it on the tracker side
  defp generate_connection_id(t, ip, port) do
    secret = Application.get_env(:extracker, :connection_id_secret)
    # generate s from the time, ip and port of the client and a runtime secret
    data = :erlang.term_to_binary({t, ip, port, secret})
    # compute the SHA-256 hash of the input data and retrieve the first 56 bits
    hash = :crypto.hash(:sha256, data)
    <<s::integer-unsigned-56, _rest::binary>> = hash

    # make a 64bit integer out of both
    :binary.decode_unsigned(<<t::integer-unsigned-8, s::integer-unsigned-56>>)
  end

  defp generate_connection_id(ip, port) do
    # get the current monotonic time, reduce its resolution to 64 seconds and fit it in 8 bits
    t = (System.monotonic_time(:second) >>> 6) &&& 0xFF
    t = :binary.decode_unsigned(<<t::integer-unsigned-8>>)
    generate_connection_id(t, ip, port)
  end

  defp process_packet(name, socket, ip, port, packet) do
    start = System.monotonic_time(:microsecond)
    process_message(socket, ip, port, packet)
    finish = System.monotonic_time(:microsecond)

    elapsed = finish - start
    if elapsed < 1_000 do
      Logger.debug("#{name}: message processed in #{elapsed}µs")
    else
      ms = System.convert_time_unit(elapsed, :microsecond, :millisecond)
      Logger.debug("#{name} message processed in #{ms}ms")
    end
    :ok
  end

  # connect request
  defp process_message(socket, ip, port, <<@protocol_magic::integer-unsigned-64, @action_connect::integer-unsigned-32, transaction_id::integer-unsigned-32>>) do
    # connect response
    response = <<
      @action_connect::integer-unsigned-32,
      transaction_id::integer-unsigned-32,
      generate_connection_id(ip, port)::integer-unsigned-64
    >>

    #IO.inspect(response, label: "connect response")
    :ok = :gen_udp.send(socket, ip, port, response)
  end

  # announce request
  defp process_message(socket, ip, port, <<connection_id::integer-unsigned-64, @action_announce::integer-unsigned-32, transaction_id::integer-unsigned-32, data::binary>>) do
    response = with :ok <- match_connection_id(connection_id, ip, port), # check connection id first
    params <- read_announce(data), # convert the binary fields to a map for the processor to understand
    {:ok, result} <- ExTracker.Processors.Announce.process(ip, params),
    {:ok, interval} <- Map.fetch(result, "interval"),
    {:ok, leechers} <- Map.fetch(result, "incomplete"),
    {:ok, seeders} <- Map.fetch(result, "complete"),
    {:ok, peers} <- Map.fetch(result, "peers")
    do
      <<
        # 32-bit integer  transaction_id
        @action_announce::integer-unsigned-32,
        # 32-bit integer  transaction_id
        transaction_id::integer-unsigned-32,
        # 32-bit integer  interval
        interval::integer-unsigned-32,
        # 32-bit integer  leechers
        leechers::integer-unsigned-32,
        # 32-bit integer  seeders
        seeders::integer-unsigned-32,
        # 32-bit integer  IP address
        # 16-bit integer  TCP port
        # 6 * N
        peers::binary
      >>
    else
      # processor failure
      {:error, %{"failure reason" => reason}} ->
        [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>,  reason]
      # general error
      {:error, reason} ->
        [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>,  reason]
      # some response key is missing (shouldn't happen)
      :error ->
        [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>, "internal error"]
    end

    # send a response in all (expected) cases
    #IO.inspect(response, label: "announce response")
    :ok = :gen_udp.send(socket, ip, port, response)
  end

  # scrape request
  defp process_message(socket, ip, port, <<connection_id::integer-unsigned-64, @action_scrape::integer-unsigned-32, transaction_id::integer-unsigned-32, data::binary>>) do
    response = with :ok <- match_connection_id(connection_id, ip, port), # check connection id first
      hashes when hashes != 0 <- read_info_hashes(data) # then extract the hashes and make sure theres at least one
    do
      # TODO using recursion i can probably return early if any of them fail for whatever reason
      # instead of traversing the list twice

      # process each info_hash on its own
      results = Enum.map(hashes, fn hash ->
        ExTracker.Processors.Scrape.process(ip, %{info_hash: hash})
      end)

      # check if any of them failed and return the first error message
      # craft a response based on the requests result
      case Enum.find(results, fn
        {:error, _reason} -> true
        _ -> false
      end) do
        {:error, %{"failure reason" => reason}} ->
          [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>, reason]
        {:error, failure} ->
          [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>, failure]
        nil ->
          # convert the results to binaries
          binaries = Enum.reduce(results, [], fn result, acc ->
            binary = <<
              Map.fetch!(result, "seeders")::integer-unsigned-32,
              Map.fetch!(result, "completed")::integer-unsigned-32,
              Map.fetch!(result, "leechers")::integer-unsigned-32
            >>
            [binary | acc]
          end)

          # concatenate the header and all the resulting binaries as response
          header = <<
            @action_scrape::integer-unsigned-32,
            transaction_id::integer-unsigned-32
          >>
          IO.iodata_to_binary([header | binaries])
      end
    else
      # general error
      {:error, %{"failure reason" => reason}} ->
        [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>, reason]
      {:error, reason} ->
        [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>, reason]
      # hashes list is empty
      [] ->
        [<<@action_error::integer-unsigned-32, transaction_id::integer-unsigned-32>>, "no info_hash provided"]
    end

    # send a response in all (expected) cases
    #IO.inspect(response, label: "scrape response")
    :ok = :gen_udp.send(socket, ip, port, response)
  end

  # unexpected request
  defp process_message(_socket, _ip, _port, _data) do
  end

  # scrape requests can hold up to 72 info hashes
  defp read_info_hashes(data) when is_binary(data), do: read_info_hash(data, [])
  defp read_info_hash(<<>>, acc), do: acc
  defp read_info_hash(<<hash::binary-size(20), rest::binary>>, acc), do: read_info_hash(rest, [hash | acc])

  # read and convert announce message to a map
  defp read_announce(data) when is_binary(data) do
    <<
      # 20-byte string  info_hash
      info_hash::binary-size(20),
      # 20-byte string  peer_id
      peer_id::binary-size(20),
      # 64-bit integer  downloaded
      downloaded::integer-unsigned-64,
      # 64-bit integer  left
      left::integer-unsigned-64,
      # 64-bit integer  uploaded
      uploaded::integer-unsigned-64,
      # 32-bit integer  event           0 // 0: none; 1: completed; 2: started; 3: stopped
      event::integer-unsigned-32,
      # 32-bit integer  IP address      0 // default
      ip::integer-unsigned-32,
      # 32-bit integer  key
      key::integer-unsigned-32,
      # 32-bit integer  num_want        -1 // default
      num_want::integer-signed-32,
      # 16-bit integer  port
      port::integer-unsigned-16,
      # remaining may be empty or BEP41
      _rest::binary
    >> = data

    # TODO should be able to use atoms directly
    event_str = case event do
      0 -> ""
      1 -> "completed"
      2 -> "started"
      3 -> "stopped"
      _ -> "unknown"
    end

    %{
      "info_hash" => info_hash,
      "peer_id" => peer_id,
      "downloaded" => downloaded,
      "left" => left,
      "uploaded" => uploaded,
      "event" => event_str,
      "ip" => ip,
      "key" => key,
      "numwant" => num_want,
      "port" => port,
      "compact" => 1 # udp is always compact
    }
  end
end
