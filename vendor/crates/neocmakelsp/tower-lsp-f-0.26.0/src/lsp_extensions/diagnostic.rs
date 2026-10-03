//! extension for [lsp_types::Message]
//
//
use lsp_types::Message;
/// extension for [lsp_types::Message]
pub trait MessageEx {
    /// Get the content with str
    fn content_str(&self) -> &str;
}

impl MessageEx for Message {
    fn content_str(&self) -> &str {
        match self {
            Message::String(content) => content.as_str(),
            Message::MarkupContent(content) => &content.value,
        }
    }
}
