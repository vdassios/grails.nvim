; Template text is one HTML document with the GSP constructs cut out.
((content) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined))

; Each Groovy fragment is parsed on its own: joining `${}` expressions
; would give invalid Groovy.
((code) @injection.content
  (#set! injection.language "groovy"))

; model="[book: book]"
((groovy_value) @injection.content
  (#set! injection.language "groovy"))
