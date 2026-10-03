# treesitter-type-collector

Macro example to generate all kind names in node-types.json, and make them to a mod.

## Example:

```rust
use treesitter_type_collector::tree_sitter_consts;

#[tree_sitter_consts("asserts/node-types.json")]
struct NodeTypes;

fn main() {
    println!("{}", NodeTypes::KIND_ARGUMENT);
    println!("{:?}", NodeTypes::NODE_TYPES);
}

```
