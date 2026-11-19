# GSP grammar

The tree-sitter grammar for GSP lives in `tree-sitter-gsp/`; its queries in `queries/gsp/`.

## GSP language

- Highlights, folds and injections: HTML in the page text, Groovy in `${ }`, `<% %>`, `%{ }%`, `<%= %>`, `<%! %>`, `!{ }!` and in `[...]` attribute values (`model="[book: book]"`).
- GSP is recognised everywhere, including inside HTML attribute values and `<script>` and `<style>` bodies.
- `commentstring` is `<%-- %s --%>`.
- `K` shows LSP hover when a server attached to the buffer answers it, and otherwise says there is none. It never falls back to `:Man`, so `K` on `<head>` does not open `man head`.

## Without nvim-treesitter

Build the parser into a `parser/` directory on the runtimepath. The queries in `queries/gsp/` are already on it:

```sh
tree-sitter build -o ~/.local/share/nvim/site/parser/gsp.so /path/to/grails.nvim/tree-sitter-gsp
```

The `groovy` and `html` parsers are needed as well.

## Known limits

- **GSP right after `<` or an HTML tag name.** `<${name}>`, `<option${attrs}>` and `<table<g:if ...>>` are parse errors. The page still highlights around them.
- **Nesting limits.** `${ }` balances braces eight levels deep, and `[...]` attribute values balance brackets four levels deep. Deeper code ends the construct early.
- **No `indents.scm` for GSP.** Indentation comes from the html injection.

## Checked against public code

The grammar has been checked against public Grails code:

| Source | Files | With errors |
|---|---|---|
| [openboxes](https://github.com/openboxes/openboxes) | 622 | 0 |
| [asgard](https://github.com/Netflix/asgard) | 146 | 0 |
| [collectory](https://github.com/AtlasOfLivingAustralia/collectory) | 145 | 0 |
| [apache/grails-core](https://github.com/apache/grails-core), every `.gsp` | 694 | 2: an unclosed `<%@` directive in the page itself, and `<table<g:if ...>>` (limit above) |
| Templates taken from grails-core's GSP tests | 585 | 4: `<${"title"}>` (limit above), and 3 the extraction cut off |
