Необходимо установить

* postgresql;

* perl и модули:
	DBI;
	DBD::Pg;
	Data::Dumper;
	Archive::Zip;
	HTTP::Server::Simple::CGI;
	File::Slurp;
	JSON;


Запуск

Чтение лога и запись в базу

```
perl parse_log.pl <путь к файлу>
```

Запуск web-сервера

```
perl web_server.pl
```

Страница доступна по адресу http://localhost:1234/
