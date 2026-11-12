package bookshop

class Author {
    String name

    static hasMany = [books: Book]
}
