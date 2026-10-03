//! # Auto transport node_types.json to rust mod
//!
//! Min example
//!
//! ```rust
//!
//! use treesitter_kind_collector::tree_sitter_kinds;
//! #[tree_sitter_kinds("asserts/node-types.json")]
//! struct NodeKindTypes;
//!
//! fn main() {
//!     println!("{}", NodeKindTypes::ARGUMENT);
//!     println!("{:?}", NodeKindTypes::NODE_TYPES);
//! }
//! ```
//!
//!

use std::path::Path;

use node_object::get_basetypes_from_str;
use proc_macro::{TokenStream, TokenTree};
use proc_macro2::{Ident, Span};
use quote::quote;

mod node_object;

/// macro to tranport a `struct abc` to `mod abc`, where has all treesitter kinds
#[proc_macro_attribute]
pub fn tree_sitter_kinds(attr: TokenStream, item: TokenStream) -> TokenStream {
    let tokens: Vec<_> = attr.into_iter().collect();
    let mod_tokens: Vec<_> = item.into_iter().collect();

    let json_data = match tokens.as_slice() {
        [TokenTree::Literal(lit)] => unwrap_string_literal(lit),
        _ => panic!("This macro only accepts a single, non-empty string argument"),
    };

    let mut is_public = false;
    let mut modname: String = String::new();
    for token in mod_tokens {
        if token.to_string().starts_with("pub") {
            is_public = true;
            continue;
        }
        if token.to_string() == "mod" {
            continue;
        }
        if token.to_string() == "struct" {
            continue;
        }
        modname = token.to_string();
        break;
    }

    if modname.is_empty() {
        panic!("please provide mod name");
    }
    json_to_unique_mod(&modname, json_data, is_public)
}

fn json_to_unique_mod(modname: &str, file: String, is_public: bool) -> TokenStream {
    let real_pa = Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap()).join(&file);

    let context = std::fs::read_to_string(&real_pa)
        .unwrap_or_else(|_| panic!("Unreachable file, {}", real_pa.display()));
    let data = get_basetypes_from_str(&context)
        .unwrap_or_else(|_| panic!("{}", "Unreadable data".to_string()));

    let mut tokens = Vec::new();
    let mut consts_tokens = Vec::new();
    for da in data {
        if da.contains_unique() {
            continue;
        }
        let prename = da.get_type().to_uppercase();
        let name = Ident::new(&prename, Span::call_site());
        let type_ = da.get_type();
        tokens.push(quote! {
            pub const #name: &str = #type_;
        });
        consts_tokens.push(quote! {
            #type_
        });
    }
    let mod_name = Ident::new(modname, Span::call_site());
    let fnq = if is_public {
        quote! {
            pub mod #mod_name {
                #(#tokens) *
                pub const NODE_TYPES: &[&str] = &[ #(#consts_tokens),* ];
            }
        }
    } else {
        quote! {
            mod #mod_name {
               #(#tokens) *
               pub const NODE_TYPES: &[&str] = &[ #(#consts_tokens),* ];
            }
        }
    };
    TokenStream::from(fnq)
}

fn unwrap_string_literal(lit: &proc_macro::Literal) -> String {
    let mut repr = lit.to_string();
    if !repr.starts_with('"') || !repr.ends_with('"') {
        panic!("This macro only accepts a single, non-empty string argument")
    }

    repr.remove(0);
    repr.pop();

    repr
}
