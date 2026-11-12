package bookshop

class AuthorController {

    def show() {
        [author: Author.get(params.id)]
    }

    def list = {
        [authors: Author.list()]
    }
}
