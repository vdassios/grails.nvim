package bookshop

class BookController {

    static layout = 'main'

    BookService bookService

    def index() {
        render(view: "/book/list", model: [books: bookService.list()])
    }

    def show(Long id) {
        render view: 'show', model: [book: Book.get(id)]
    }

    def row() {
        render(template: 'row', model: [book: Book.get(1)])
    }

    def save = {
        redirect(controller: 'author', action: 'show', id: 1)
    }

    def edit() {
        redirect action: 'show'
        render(view: "/book/${actionName}")
    }

    def missing() {
        redirect(controller: 'author', action: 'list')
        render(view: '/book/nothing')
    }

    private void helper() {
        redirect(action: 'helper')
    }
}
