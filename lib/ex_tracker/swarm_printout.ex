# this module is purely to pretty-print the info returned by ExTracker.Cmd.show_swarm_list(false)
# pure throwaway code
defmodule SwarmPrintout do
  def print_table(swarms) when is_list(swarms) do
    header = ["Created", "Hash", "Peer Count"]

    rows =
      Enum.map(swarms, fn swarm ->
        created = swarm["created"]
        hash = swarm["hash"]
        peer_count = Integer.to_string(swarm["peer_count"])
        [created, hash, peer_count]
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
