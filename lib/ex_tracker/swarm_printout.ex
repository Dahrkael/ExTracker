# this module is purely to pretty-print the info returned by ExTracker.Cmd.show_swarm_list(false)
# pure throwaway code
defmodule SwarmPrintout do
  def format_memory(bytes) when is_integer(bytes) and bytes >= 0 do
    units = ["B", "KB", "MB", "GB", "TB"]
    format_memory(bytes * 1.0, 0, units)
  end

  defp format_memory(value, idx, units) when idx == length(units) - 1 do
    formatted = :io_lib.format("~.2f", [value]) |> IO.iodata_to_binary()
    "#{formatted} #{Enum.at(units, idx)}"
  end

  defp format_memory(value, idx, units) do
    if value < 1024 do
      formatted = :io_lib.format("~.2f", [value]) |> IO.iodata_to_binary()
      "#{formatted} #{Enum.at(units, idx)}"
    else
      format_memory(value / 1024, idx + 1, units)
    end
  end

  def print_table(swarms) when is_list(swarms) do
    header = ["Created", "Hash", "Peer Count", "Total Memory"]

    rows =
      Enum.map(swarms, fn swarm ->
        created = swarm["created"]
        hash = swarm["hash"]
        peer_count = Integer.to_string(swarm["peer_count"])
        total_memory = format_memory(swarm["total_memory"])
        [created, hash, peer_count, total_memory]
      end)

    all_rows = [header | rows]
    num_cols = length(header)

    col_widths =
      for col <- 0..(num_cols - 1) do
        all_rows
        |> Enum.map(fn row -> String.length(Enum.at(row, col)) end)
        |> Enum.max()
      end

    row_format =
      col_widths
      |> Enum.map(fn width -> "~-" <> Integer.to_string(width) <> "s" end)
      |> Enum.join(" | ")

    total_width = Enum.sum(col_widths) + 3 * (num_cols - 1)
    separator = String.duplicate("-", total_width)

    IO.puts(separator)
    IO.puts(:io_lib.format(row_format, header) |> IO.iodata_to_binary())
    IO.puts(separator)
    for row <- rows do
      IO.puts(:io_lib.format(row_format, row) |> IO.iodata_to_binary())
    end
    IO.puts(separator)
  end
end
