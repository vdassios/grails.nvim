[
  "${"
  "}"
  "<%"
  "<%="
  "<%!"
  "<%@"
  "%>"
  "%{"
  "}%"
  "!{"
  "}!"
  "@{"
] @punctuation.special

(comment) @comment @spell

(directive_name) @keyword.directive

(namespace) @module

(tag_name) @tag

[
  "<"
  ">"
  "</"
  "/>"
] @tag.delimiter

":" @punctuation.delimiter

"=" @operator

(attribute_name) @tag.attribute

(attribute_value
  [
    "\""
    "'"
  ] @string)

(attribute_value
  (text) @string)
