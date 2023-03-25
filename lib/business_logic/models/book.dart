class Book {
  String id;
  String name;
  int firstPage;
  int lastPage;

  Book(
      {required this.id,
      required this.name,
      this.firstPage = 0,
      this.lastPage = 0});
}
