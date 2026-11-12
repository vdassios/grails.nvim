<html>
<head>
  <meta name="layout" content="main"/>
  <asset:stylesheet src="app.css"/>
  <asset:javascript src="app"/>
</head>
<body>
<g:each in="${books}" var="book">
  <g:render template="/book/row" model="[book: book]"/>
  <tmpl:row book="${book}"/>
  <g:link controller="author" action="show" id="${book.author.id}">${book.author.name}</g:link>
  <g:link action="show" id="${book.id}">show</g:link>
</g:each>
<tmpl:/shared/footer/>
<g:include view="show"/>
<g:render template="/book/${kind}"/>
<g:render template="/missing/thing"/>
<asset:image src="logo.svg"/>
</body>
</html>
