Begin TRANSACTION;
delete from dictionary where book_id = 8;
delete from dictionary where book_id = 1;
delete from dpd;
delete from dpd_inflections_to_headwords;
COMMIT;
