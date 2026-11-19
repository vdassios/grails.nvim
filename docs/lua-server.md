# Lua navigation server

`lsp/grails.lua` starts a small in-process language server written in Lua (`grails`) for Grails navigation, which needs no JDK, nothing to install and no build. It applies Grails' naming conventions to the syntax tree. Once `grails_ls` has the project ready in a buffer, the Lua server leaves definition to it there.

## Go to definition

| Under the cursor | Goes to |
|---|---|
| `<g:render template="...">`, `render(template: ...)`, `<tmpl:name/>` | `/a/b` opens `views/a/_b.gsp`. `b` opens `_b.gsp` beside the current view, or `views/<controller>/_b.gsp` from a controller. A `contextPath` attribute is a prefix. `<tmpl:/a/b/>` is `/a/b`. |
| `render(view: ...)`, `view` attribute of a `g:` tag (`g:include`) | `/a/b` opens `views/a/b.gsp`. `b` opens `views/<controller>/b.gsp`. `.gsp`, then `.jsp`, then `.gson`. |
| `<meta name="layout" content="x">`, `<g:applyLayout name="x">`, `static layout = 'x'` | `views/layouts/x.gsp` |
| `src` or `href` of `asset:stylesheet`, `asset:javascript`, `asset:image`, `asset:assetPath`, `asset:link` | The file under any `grails-app/assets/*/` directory. Without an exact match: `.css .scss .sass .less` for stylesheets, `.js .es6 .ts .coffee` for scripts. |
| `controller` attribute of a GSP tag; `controller:` of `redirect`, `chain`, `forward`, `createLink`, `g.link` | The controller class |
| `action` in the same places | The action in the named controller, or in the current one. In a view, that is the controller named after the view's directory. An action is a method that is not private, protected or static, or a property assigned a closure. |

Lookups search every module of a multi-module build, the current one first, because views and controllers often live in different modules. A target that does not exist, or a value computed with `${}` or a GString, gives no result.

## Known limits

These are the Lua server's; grails-language-server has its own list in [its docs](https://github.com/vdassios/grails-language-server/blob/main/docs/how-it-works.md#known-limits).

- **No type inference.** The Lua server works on syntax and naming conventions. Members of an instance (`book.save()`, `book.author`), dynamic finders, and Grails methods such as `render` and `params` are neither completed nor resolved.
- **Workspace source only.** Views, templates, taglibs and members that come from Grails plugins (jars on the classpath) are unknown.
- **tree-sitter-groovy parse errors.** The `groovy` parser fails on parts of many real Grails files. It mostly recovers locally, but a file can become a single error node. When the cursor is inside one, the server falls back to reading `call(key: 'value')` or `call key: 'value'` from the cursor line.
