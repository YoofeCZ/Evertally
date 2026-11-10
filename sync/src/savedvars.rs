//! Data-only reader for `WoW` `SavedVariables` files.
//!
//! `WoW` writes saved variables as Lua assignments. The web export accepts exactly
//! one assignment; local history permits several explicitly allowed variables.
//! Values contain only tables, strings, numbers, booleans and `nil`, converted to
//! JSON. This parser never evaluates code: anything else is an error.
//! The rules mirror the web importer (`platform/lib/import.ts`) so both sides agree.

use std::collections::HashSet;

use serde_json::{Map, Number, Value};
use thiserror::Error;

const MAX_DEPTH: usize = 40;
const MAX_NODES: usize = 400_000;
/// The addon's own history file holds far more than one web export.
const MAX_NODES_HISTORY: usize = 4_000_000;
const MAX_INDEX: i64 = 100_000;
const FORBIDDEN_KEYS: [&str; 3] = ["__proto__", "prototype", "constructor"];

/// Why a file could not be read as data.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum ParseError {
    #[error("{message} at byte {position}")]
    Invalid {
        message: &'static str,
        position: usize,
    },
    #[error("expected {expected}, found {found}")]
    WrongVariable { expected: String, found: String },
}

/// Parses `variable = { ... }` and returns the table as JSON.
///
/// # Errors
/// Returns [`ParseError`] when the source contains anything other than a single
/// data-only assignment to `variable`.
pub fn parse_assignment(source: &str, variable: &str) -> Result<Value, ParseError> {
    let source = source.strip_prefix('\u{feff}').unwrap_or(source);
    let mut parser = Parser {
        src: source.as_bytes(),
        pos: 0,
        nodes: 0,
        max_nodes: MAX_NODES,
    };
    parser.skip()?;
    let name = parser.identifier()?;
    if name != variable {
        return Err(ParseError::WrongVariable {
            expected: variable.to_owned(),
            found: name.to_owned(),
        });
    }
    parser.skip()?;
    parser.expect(b'=')?;
    let value = parser.value(0)?;
    parser.skip()?;
    if parser.peek() == Some(b';') {
        parser.pos += 1;
        parser.skip()?;
    }
    if parser.pos != parser.src.len() {
        return Err(parser.err("the file contains further statements"));
    }
    Ok(value)
}

/// Parses a whole `SavedVariables` file with several `Name = value` assignments, as `WoW`
/// writes one file per addon. Only names in `allowed` are accepted.
///
/// # Errors
/// Returns [`ParseError`] for code, unknown or repeated variables and malformed data.
pub fn parse_assignments(source: &str, allowed: &[&str]) -> Result<Map<String, Value>, ParseError> {
    let source = source.strip_prefix('\u{feff}').unwrap_or(source);
    let mut parser = Parser {
        src: source.as_bytes(),
        pos: 0,
        nodes: 0,
        max_nodes: MAX_NODES_HISTORY,
    };
    let mut variables = Map::new();
    loop {
        parser.skip()?;
        if parser.pos == parser.src.len() {
            return Ok(variables);
        }
        let name = parser.identifier()?;
        if !allowed.contains(&name) {
            return Err(ParseError::WrongVariable {
                expected: allowed.join(", "),
                found: name.to_owned(),
            });
        }
        let name = name.to_owned();
        parser.skip()?;
        parser.expect(b'=')?;
        let value = parser.value(0)?;
        if variables.insert(name, value).is_some() {
            return Err(parser.err("variable assigned twice"));
        }
        parser.skip()?;
        if parser.peek() == Some(b';') {
            parser.pos += 1;
        }
    }
}

#[derive(Clone, PartialEq, Eq, Hash)]
enum Key {
    Name(String),
    Index(i64),
}

struct Parser<'a> {
    src: &'a [u8],
    pos: usize,
    nodes: usize,
    max_nodes: usize,
}

impl<'a> Parser<'a> {
    fn err(&self, message: &'static str) -> ParseError {
        ParseError::Invalid {
            message,
            position: self.pos,
        }
    }

    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn starts_with(&self, token: &[u8]) -> bool {
        self.src[self.pos..].starts_with(token)
    }

    /// Skips whitespace and `--` line or `--[==[ ]==]` block comments.
    fn skip(&mut self) -> Result<(), ParseError> {
        loop {
            while matches!(
                self.peek(),
                Some(b' ' | b'\t' | b'\r' | b'\n' | 0x0b | 0x0c)
            ) {
                self.pos += 1;
            }
            if !self.starts_with(b"--") {
                return Ok(());
            }
            self.pos += 2;
            if let Some(level) = self.long_bracket_level() {
                let close = [b"]".as_slice(), &vec![b'='; level], b"]"].concat();
                self.pos += level + 2;
                let rest = &self.src[self.pos..];
                let end = rest
                    .windows(close.len())
                    .position(|w| w == close.as_slice())
                    .ok_or_else(|| self.err("unterminated comment"))?;
                self.pos += end + close.len();
            } else {
                while !matches!(self.peek(), None | Some(b'\n' | b'\r')) {
                    self.pos += 1;
                }
            }
        }
    }

    /// Returns the `=` count if a `[==[` long bracket starts at the cursor.
    fn long_bracket_level(&self) -> Option<usize> {
        let rest = &self.src[self.pos..];
        if rest.first() != Some(&b'[') {
            return None;
        }
        let level = rest[1..].iter().take_while(|&&b| b == b'=').count();
        (rest.get(level + 1) == Some(&b'[')).then_some(level)
    }

    fn expect(&mut self, byte: u8) -> Result<(), ParseError> {
        self.skip()?;
        if self.peek() != Some(byte) {
            return Err(self.err(match byte {
                b'=' => "expected '='",
                b']' => "expected ']'",
                b'{' => "expected '{'",
                _ => "unexpected character",
            }));
        }
        self.pos += 1;
        Ok(())
    }

    fn identifier(&mut self) -> Result<&'a str, ParseError> {
        let start = self.pos;
        if !matches!(self.peek(), Some(b'A'..=b'Z' | b'a'..=b'z' | b'_')) {
            return Err(self.err("expected an identifier"));
        }
        while matches!(
            self.peek(),
            Some(b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'_')
        ) {
            self.pos += 1;
        }
        // The matched range is ASCII, so it is valid UTF-8.
        std::str::from_utf8(&self.src[start..self.pos])
            .map_err(|_| self.err("expected an identifier"))
    }

    fn value(&mut self, depth: usize) -> Result<Value, ParseError> {
        self.nodes += 1;
        if depth > MAX_DEPTH || self.nodes > self.max_nodes {
            return Err(self.err("structure limit exceeded"));
        }
        self.skip()?;
        match self.peek() {
            Some(quote @ (b'"' | b'\'')) => self.string(quote).map(Value::String),
            Some(b'{') => self.table(depth + 1),
            Some(b'-' | b'.' | b'0'..=b'9') => self.number(),
            _ => self.keyword(),
        }
    }

    fn keyword(&mut self) -> Result<Value, ParseError> {
        for (word, value) in [
            ("true", Value::Bool(true)),
            ("false", Value::Bool(false)),
            ("nil", Value::Null),
        ] {
            let end = self.pos + word.len();
            let boundary = !matches!(
                self.src.get(end),
                Some(b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'_')
            );
            if self.starts_with(word.as_bytes()) && boundary {
                self.pos = end;
                return Ok(value);
            }
        }
        Err(self.err("only data is allowed, not Lua statements or functions"))
    }

    fn number(&mut self) -> Result<Value, ParseError> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        let digits = |p: &mut Self| {
            let begin = p.pos;
            while matches!(p.peek(), Some(b'0'..=b'9')) {
                p.pos += 1;
            }
            p.pos - begin
        };
        let mut is_float = false;
        let int_digits = digits(self);
        let mut frac_digits = 0;
        if self.peek() == Some(b'.') {
            is_float = true;
            self.pos += 1;
            frac_digits = digits(self);
        }
        if int_digits + frac_digits == 0 {
            return Err(self.err("invalid number"));
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            is_float = true;
            self.pos += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            if digits(self) == 0 {
                return Err(self.err("invalid number"));
            }
        }
        let text = std::str::from_utf8(&self.src[start..self.pos])
            .map_err(|_| self.err("invalid number"))?;
        if !is_float && let Ok(int) = text.parse::<i64>() {
            return Ok(Value::Number(int.into()));
        }
        let float: f64 = text.parse().map_err(|_| self.err("invalid number"))?;
        Number::from_f64(float)
            .map(Value::Number)
            .ok_or_else(|| self.err("number is not finite"))
    }

    /// Lua strings are byte strings; decimal escapes produce raw bytes (`WoW` writes
    /// non-ASCII text that way), so the bytes are decoded as UTF-8 at the end.
    fn string(&mut self, quote: u8) -> Result<String, ParseError> {
        self.pos += 1;
        let mut bytes = Vec::new();
        loop {
            let byte = self.peek().ok_or_else(|| self.err("unterminated string"))?;
            self.pos += 1;
            match byte {
                b if b == quote => break,
                b'\n' | b'\r' => return Err(self.err("unescaped newline in string")),
                b'\\' => {
                    let escape = self.peek().ok_or_else(|| self.err("unterminated string"))?;
                    self.pos += 1;
                    match escape {
                        b'a' => bytes.push(0x07),
                        b'b' => bytes.push(0x08),
                        b'f' => bytes.push(0x0c),
                        b'n' | b'\n' => bytes.push(b'\n'),
                        b'r' => bytes.push(b'\r'),
                        b't' => bytes.push(b'\t'),
                        b'v' => bytes.push(0x0b),
                        b'\\' | b'"' | b'\'' => bytes.push(escape),
                        b'\r' => {
                            if self.peek() == Some(b'\n') {
                                self.pos += 1;
                            }
                            bytes.push(b'\n');
                        }
                        b'0'..=b'9' => {
                            let mut code = u32::from(escape - b'0');
                            for _ in 0..2 {
                                match self.peek() {
                                    Some(d @ b'0'..=b'9') => {
                                        code = code * 10 + u32::from(d - b'0');
                                        self.pos += 1;
                                    }
                                    _ => break,
                                }
                            }
                            let byte = u8::try_from(code)
                                .map_err(|_| self.err("invalid escape sequence"))?;
                            bytes.push(byte);
                        }
                        _ => return Err(self.err("escape sequence not allowed")),
                    }
                }
                other => bytes.push(other),
            }
        }
        String::from_utf8(bytes).map_err(|_| self.err("string is not valid UTF-8"))
    }

    fn key(&mut self, depth: usize) -> Result<Key, ParseError> {
        match self.value(depth)? {
            Value::String(name) => Ok(Key::Name(name)),
            Value::Number(n) => n
                .as_i64()
                .filter(|i| (1..=MAX_INDEX).contains(i))
                .map(Key::Index)
                .ok_or_else(|| self.err("invalid numeric index")),
            _ => Err(self.err("invalid table key")),
        }
    }

    fn table(&mut self, depth: usize) -> Result<Value, ParseError> {
        self.expect(b'{')?;
        let mut entries: Vec<(Key, Value)> = Vec::new();
        let mut seen: HashSet<Key> = HashSet::new();
        let mut auto_index: i64 = 1;
        let mut has_names = false;
        loop {
            self.skip()?;
            if self.peek() == Some(b'}') {
                self.pos += 1;
                break;
            }
            let (key, value) = if self.peek() == Some(b'[') && self.long_bracket_level().is_none() {
                self.pos += 1;
                let key = self.key(depth)?;
                self.expect(b']')?;
                self.expect(b'=')?;
                (key, self.value(depth)?)
            } else {
                let saved = self.pos;
                let named = match self.identifier() {
                    Ok(ident) => {
                        self.skip()?;
                        if self.peek() == Some(b'=') {
                            self.pos += 1;
                            Some(ident.to_owned())
                        } else {
                            None
                        }
                    }
                    Err(_) => None,
                };
                if let Some(name) = named {
                    (Key::Name(name), self.value(depth)?)
                } else {
                    self.pos = saved;
                    let key = Key::Index(auto_index);
                    auto_index += 1;
                    (key, self.value(depth)?)
                }
            };
            if let Key::Name(name) = &key {
                if FORBIDDEN_KEYS.contains(&name.as_str()) {
                    return Err(self.err("forbidden key"));
                }
                has_names = true;
            }
            if !seen.insert(key.clone()) {
                return Err(self.err("duplicate key"));
            }
            entries.push((key, value));
            self.skip()?;
            match self.peek() {
                Some(b',' | b';') => self.pos += 1,
                Some(b'}') => {}
                _ => return Err(self.err("expected a comma or end of table")),
            }
        }

        if !has_names {
            // A table with only numeric keys must be a dense 1..n sequence.
            let mut array = vec![Value::Null; entries.len()];
            for (key, value) in entries {
                let Key::Index(index) = key else {
                    unreachable!("names were ruled out above")
                };
                let slot = usize::try_from(index - 1)
                    .ok()
                    .filter(|&i| i < array.len())
                    .ok_or_else(|| self.err("sparse arrays are not supported"))?;
                array[slot] = value;
            }
            return Ok(Value::Array(array));
        }
        let mut object = Map::new();
        for (key, value) in entries {
            let Key::Name(name) = key else {
                return Err(self.err("mixed tables are not supported"));
            };
            if !value.is_null() {
                object.insert(name, value);
            }
        }
        Ok(Value::Object(object))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE_LUA: &str = include_str!("../../tests/lua/fixtures/Evertally_Export.lua");
    const FIXTURE_JSON: &str = include_str!("../../tests/lua/fixtures/export.json");

    fn parse(source: &str) -> Result<Value, ParseError> {
        parse_assignment(source, "EvertallyExportDB")
    }

    #[test]
    fn real_addon_fixture_matches_json_fixture() {
        let expected: Value = serde_json::from_str(FIXTURE_JSON).expect("fixture JSON is valid");
        assert_eq!(parse(FIXTURE_LUA).expect("fixture parses"), expected);
    }

    #[test]
    fn decimal_escapes_decode_as_utf8() {
        let value = parse(r#"EvertallyExportDB = { ["title"] = "Troll\195\173 jeskyn\196\155" }"#)
            .expect("parses");
        assert_eq!(value["title"], "Trollí jeskyně");
    }

    #[test]
    fn bom_comments_and_trailing_semicolon_are_accepted() {
        let value =
            parse("\u{feff}-- header\nEvertallyExportDB = {1, 2, --[[ inline ]] 3}; -- end\n")
                .expect("parses");
        assert_eq!(value, serde_json::json!([1, 2, 3]));
    }

    #[test]
    fn empty_table_is_an_empty_array_and_nil_fields_are_dropped() {
        assert_eq!(
            parse("EvertallyExportDB = {}").expect("parses"),
            serde_json::json!([])
        );
        assert_eq!(
            parse("EvertallyExportDB = { a = 1, b = nil }").expect("parses"),
            serde_json::json!({"a": 1})
        );
    }

    #[test]
    fn numbers_keep_integers_exact_and_reject_non_finite() {
        assert_eq!(
            parse("EvertallyExportDB = { 1794236400, -2, 0.5, 1e3 }").expect("parses"),
            serde_json::json!([1_794_236_400, -2, 0.5, 1000.0])
        );
        assert!(parse("EvertallyExportDB = { 1e999 }").is_err());
    }

    #[test]
    fn code_is_rejected() {
        for source in [
            "EvertallyExportDB = (function() return {} end)()",
            r#"EvertallyExportDB = os.execute("calc")"#,
            "EvertallyExportDB = {} OtherDB = {}",
            "EvertallyExportDB = { x = y }",
        ] {
            assert!(parse(source).is_err(), "accepted: {source}");
        }
    }

    #[test]
    fn wrong_variable_is_rejected() {
        assert!(matches!(
            parse("OtherDB = {}"),
            Err(ParseError::WrongVariable { .. })
        ));
    }

    #[test]
    fn malformed_tables_are_rejected() {
        for source in [
            "EvertallyExportDB = { a = 1, a = 2 }",
            "EvertallyExportDB = { [2] = 1 }",
            "EvertallyExportDB = { [1] = 1, a = 2 }",
            "EvertallyExportDB = { __proto__ = {} }",
            "EvertallyExportDB = { [1.5] = 1 }",
            "EvertallyExportDB = { a = 1",
            "EvertallyExportDB = { \"line\nbreak\" }",
            "EvertallyExportDB = { \"\\255\\254\" }",
        ] {
            assert!(parse(source).is_err(), "accepted: {source}");
        }
    }

    #[test]
    fn whole_addon_file_with_several_variables() {
        let source = "\nEvertallyDB = {\n\t[\"runs\"] = {},\n}\nEvertallyPeersDB = {\n\t[\"peers\"] = {},\n}\n";
        let allowed = ["EvertallyDB", "EvertallyPeersDB"];
        let vars = parse_assignments(source, &allowed).expect("parses");
        assert_eq!(vars["EvertallyDB"], serde_json::json!({"runs": []}));
        assert_eq!(vars["EvertallyPeersDB"], serde_json::json!({"peers": []}));
        assert!(parse_assignments("EvertallyDB = {} EvertallyDB = {}", &allowed).is_err());
        assert!(matches!(
            parse_assignments("OtherDB = {}", &allowed),
            Err(ParseError::WrongVariable { .. })
        ));
        assert!(parse_assignments("EvertallyDB = os.exit()", &allowed).is_err());
    }

    #[test]
    fn code_after_allowed_assignments_is_rejected() {
        let allowed = ["EvertallyDB", "EvertallyPeersDB"];
        for tail in [
            "EvertallyDB.events = {}",
            "os.execute('calc')",
            "return {}",
            "EvertallyPeersDB = nil",
        ] {
            let source = format!("EvertallyDB = {{}} EvertallyPeersDB = {{}} {tail}");
            assert!(
                parse_assignments(&source, &allowed).is_err(),
                "accepted {tail}"
            );
        }
    }

    #[test]
    fn deep_nesting_is_limited() {
        let source = format!("EvertallyExportDB = {}{}", "{".repeat(60), "}".repeat(60));
        assert!(parse(&source).is_err());
    }
}
