package bookshop

class Book {
    String title
    Author author

    static belongsTo = [author: Author]
}
