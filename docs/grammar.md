# GSP grammar

The tree-sitter grammar for GSP lives in `tree-sitter-gsp/`; its queries in `queries/gsp/`.

## GSP language

- Highlights, folds and injections: HTML in the page text, Groovy in `${ }`, `<% %>`, `%{ }%`, `<%= %>`, `<%! %>`, `!{ }!` and in `[...]` attribute values (`model="[book: book]"`).
- GSP is recognised everywhere, including inside HTML attribute values and `<script>` and `<style>` bodies.
- `commentstring` is `<%-- %s --%>`.
- `K` shows LSP hover when a server attached to the buffer answers it, and otherwise says there is none. It never falls back to `:Man`, so `K` on `<head>` does not open `man head`. It is not mapped when `K` is already mapped, or with `vim.g.grails_default_mappings = false`.

## Without nvim-treesitter

Build the parser into a `parser/` directory on the runtimepath. The queries in `queries/gsp/` are already on it:

```sh
tree-sitter build -o ~/.local/share/nvim/site/parser/gsp.so /path/to/grails.nvim/tree-sitter-gsp
```

The `groovy` and `html` parsers are needed as well. Run the command again after each update of grails.nvim.

## Known limits

- **Strings inside `${ }`.** The grammar skips a Groovy string inside `${ }` only when it is on one line, so a `}` in it does not end the expression. A string that spans lines (`${ "a` with `b" }` on the next line) is a parse error, and so is a `'` or `"` inside a slashy string (`${ x ==~ /it's/ }`). A `}` inside a slashy string ends the expression early.
- **Nesting limits.** `${ }` balances braces eight levels deep; a ninth level is a parse error. A `[...]` attribute value balances brackets four levels deep; at five levels the whole value is plain text, without the Groovy injection.
- **`}` before `}%` or `}!`.** In `%{ x.each { y }}%` the closer takes the whole run of `}`, so the Groovy injection does not see the closure's last `}`.
- **No fold for a tag's body.** GSP tags are not paired in the tree (an open tag and its close tag are separate nodes), so a fold covers one tag that spans lines, a comment, a scriptlet or a declaration, never what lies between `<g:if>` and `</g:if>`. HTML elements fold through the html injection.
- **No `indents.scm` for GSP.** Indentation comes from the html injection.

## Checked against public code

The grammar has been checked against public Grails code:

| Source | Files | With errors |
|---|---|---|
| [openboxes](https://github.com/openboxes/openboxes) | 622 | 0 |
| [asgard](https://github.com/Netflix/asgard) | 146 | 0 |
| [collectory](https://github.com/AtlasOfLivingAustralia/collectory) | 145 | 0 |
| [apache/grails-core](https://github.com/apache/grails-core), every `.gsp` | 694 | 2: an unclosed `<%@` directive in the page itself, and `<table<g:if ...>>` |
| Templates taken from grails-core's GSP tests | 585 | 4: `<${"title"}>`, and 3 the extraction cut off |

`<table<g:if ...>>` and `<${"title"}>` were parse errors when these counts were taken; a GSP construct right after `<`, `</` or an HTML tag name now parses (`test/corpus/escapes.txt`).
