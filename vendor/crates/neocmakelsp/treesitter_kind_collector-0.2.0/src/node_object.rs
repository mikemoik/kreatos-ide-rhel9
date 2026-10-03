use serde::{Deserialize, Serialize};
use serde_json::{Result, Value};

const UNIUQUE_CHARS: &[char] = &['\t', '\n', ';', '{', '}', '\\', '"', '$', '(', ')'];

#[derive(Serialize, Deserialize)]
pub struct BaseType {
    #[serde(rename(deserialize = "type"))]
    type_: String,
    named: bool,
    fields: Option<Value>,
    children: Option<Value>,
}

impl BaseType {
    pub fn get_type(&self) -> &str {
        &self.type_
    }
    #[allow(unused)]
    pub fn get_named(&self) -> bool {
        self.named
    }
    pub fn contains_unique(&self) -> bool {
        UNIUQUE_CHARS.iter().any(|c| self.type_.contains(*c))
    }
}

pub fn get_basetypes_from_str(content: &str) -> Result<Vec<BaseType>> {
    serde_json::from_str(content)
}

#[test]
fn test_json() {
    let content = include_str!("../asserts/node-types.json");
    let res = get_basetypes_from_str(content).unwrap();
    assert_eq!(res.len(), 65);
}
