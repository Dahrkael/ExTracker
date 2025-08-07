defmodule ExTracker.AccesslistTest do
  use ExUnit.Case, async: false
  alias ExTracker.Accesslist

  setup do
    # Generate a unique name per test to isolate ETS tables
    name = :"test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Accesslist.start_link(name: name)
    %{name: name}
  end

  describe "basic operations" do
    test "contains? returns false on empty table", %{name: name} do
      refute Accesslist.contains(name, "entry")
    end

    test "add/2 makes entry present", %{name: name} do
      Accesslist.add(name, "entry")
      _ = name |> GenServer.whereis() |> :sys.get_state()

      assert Accesslist.contains(name, "entry")
    end

    test "add/2 can be called multiple times", %{name: name} do
      Accesslist.add(name, "entry1")
      Accesslist.add(name, "entry2")
      _ = name |> GenServer.whereis() |> :sys.get_state()

      assert Accesslist.contains(name, "entry1")
      assert Accesslist.contains(name, "entry2")
    end

    test "add/2 on existing entry does not crash", %{name: name} do
      Accesslist.add(name, "duplicated")
      Accesslist.add(name, "duplicated")
      _ = name |> GenServer.whereis() |> :sys.get_state()

      assert Accesslist.contains(name, "duplicated")
    end

    test "remove/2 deletes an existing entry", %{name: name} do
      Accesslist.add(name, "entry")
      _ = name |> GenServer.whereis() |> :sys.get_state()
      assert Accesslist.contains(name, "entry")

      Accesslist.remove(name, "entry")
      _ = name |> GenServer.whereis() |> :sys.get_state()
      refute Accesslist.contains(name, "entry")
    end

    test "remove/2 can be called multiple times", %{name: name} do
      Accesslist.add(name, "entry1")
      Accesslist.add(name, "entry2")
      Accesslist.remove(name, "entry1")
      _ = name |> GenServer.whereis() |> :sys.get_state()

      refute Accesslist.contains(name, "entry1")
      assert Accesslist.contains(name, "entry2")
    end

    test "remove/2 on missing entry does not crash", %{name: name} do
      Accesslist.remove(name, "missing")
      _ = name |> GenServer.whereis() |> :sys.get_state()
      refute Accesslist.contains(name, "missing")
    end
  end

  describe "multiple instances isolation" do
    test "two AccessLists do not share entries" do
      name1 = :"test_#{System.unique_integer([:positive])}"
      name2 = :"test_#{System.unique_integer([:positive])}"
      {:ok, _} = Accesslist.start_link(name: name1)
      {:ok, _} = Accesslist.start_link(name: name2)

      Accesslist.add(name1, "entry")
      _ = name1 |> GenServer.whereis() |> :sys.get_state()

      assert Accesslist.contains(name1, "entry")
      refute Accesslist.contains(name2, "entry")
    end
  end

  describe "loading from file" do
    test "from_file/2 loads valid entries into ETS", %{name: name} do
      # prepare a temporary file with one entry per line
      entries = ["one", "two", "three"]
      path = Path.join(System.tmp_dir!(), "accesslist_#{:erlang.unique_integer()}.txt")
      File.write!(path, Enum.join(entries, "\n"))

      # call from_file and verify return value
      assert :ok = Accesslist.from_file(name, path)

      # each line should now be present in the ETS table
      for e <- entries do
        assert Accesslist.contains(name, e)
      end

      # something not in the file should not be present
      refute Accesslist.contains(name, "four")

      File.rm!(path)
    end

    test "from_file/2 with non-existent file logs error and leaves table empty", %{name: name} do
      missing = Path.join(System.tmp_dir!(), "no_such_file_#{:erlang.unique_integer()}.txt")
      assert :ok = Accesslist.from_file(name, missing)
      # table should remain empty
      count = :"accesslist_#{name}" |> :ets.tab2list() |> length()
      assert count == 0
    end
  end
end
