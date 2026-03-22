import gleam/io
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice/two_p_set

fn print_set(label: String, s: set.Set(String)) -> Nil {
  let contents =
    s |> set.to_list |> list.sort(string.compare) |> string.join(", ")
  io.println(label <> contents)
}

pub fn main() {
  io.println("=== TwoPSet (Two-Phase Set) ===")
  io.println("")

  // Create two sets on different replicas
  io.println("Creating two TwoPSets on different replicas...")

  // Set A: add three items, then remove "banana"
  let set_a =
    two_p_set.new()
    |> two_p_set.add("apple")
    |> two_p_set.add("banana")
    |> two_p_set.add("cherry")
    |> two_p_set.remove("banana")

  // Set B: add "banana" and "date"
  let set_b =
    two_p_set.new()
    |> two_p_set.add("banana")
    |> two_p_set.add("date")

  print_set("Set A: ", two_p_set.value(set_a))
  print_set("Set B: ", two_p_set.value(set_b))
  io.println("")

  // Merge the two replicas
  io.println("Merging Set A and Set B...")
  let merged = two_p_set.merge(set_a, set_b)
  print_set("Merged: ", two_p_set.value(merged))
  io.println("")

  io.println("Notice: \"banana\" is absent from the merged set!")
  io.println("In a TwoPSet, once an element is removed it can NEVER be")
  io.println("re-added. The remove-set (tombstone set) always wins.")
  io.println("")

  // Demonstrate that re-adding "banana" has no effect
  io.println("Attempting to re-add \"banana\" to the merged set...")
  let re_added = two_p_set.add(merged, "banana")
  let still_absent = case two_p_set.contains(re_added, "banana") {
    True -> "true"
    False -> "false"
  }
  io.println(
    "Contains \"banana\" after re-add: "
    <> still_absent
    <> " (tombstone is permanent)",
  )
  print_set("After re-add attempt: ", two_p_set.value(re_added))
  io.println("")

  // JSON round-trip
  io.println("--- JSON Serialization ---")
  let json_str = merged |> two_p_set.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case two_p_set.from_json(json_str) {
    Ok(decoded) -> {
      print_set("Decoded: ", two_p_set.value(decoded))
      io.println("✓ JSON round-trip successful")
    }
    Error(_) -> io.println("✗ JSON round-trip failed")
  }
  io.println("")

  io.println("=== TwoPSet Example Complete ===")
}
