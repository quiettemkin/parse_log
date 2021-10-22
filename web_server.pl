#!/usr/bin/perl
use HTTP::Server::Simple::CGI;

{
	package WebServer;

	use base 'HTTP::Server::Simple::CGI';
	use File::Slurp;
	use Data::Dumper;
	use DBD::Pg;
	use JSON;

	my $dbname   = 'test_db';
	my $host     = 'localhost';
	my $port     = '5432';
	my $username = 'artem';
	my $password = 'z';

	my $nl = "\x0d\x0a";

	chdir ('.');

	sub darn ($) { warn Dumper $_[0];return $_[0] }

	sub send_file {

		my ($path) = @_;

		print "HTTP/1.0 200 OK$nl";
		print "Content-Type: text/html; charset=utf-8$nl$nl";

		if (-e $path) {
			print read_file ($path, binmode => ":raw");
		} else {
			print "file $path not found";
		}
	}

	sub send_data {
		print "HTTP/1.0 200 OK$nl";
		print "Content-Type: application/json; charset=utf-8$nl$nl";
		print to_json($_[0]);
	}

	sub search_log {

		my ($options) = @_;

		$options -> {q} ||= '';

		my $dbh = DBI -> connect ("dbi:Pg:dbname=$dbname;host=$host;port=$port", $username, $password, {AutoCommit => 0, RaiseError => 1}) or die $DBI::errstr;

        my $log = $dbh -> selectall_arrayref (<<EOS, {Slice => {}}, "%$$options{q}%");
            WITH int_ids AS (
                SELECT
                    DISTINCT int_id AS id
                FROM
                    log
                WHERE
                    address ILIKE ?
            )
            SELECT
            	CONCAT(created, str) AS line
				, int_id
				, created
            FROM
                log
            INNER JOIN int_ids ON int_ids.id = log.int_id
        UNION
            SELECT
				CONCAT(created, str) AS line
				, int_id
				, created
            FROM
                message
            INNER JOIN int_ids ON int_ids.id = message.int_id
        ORDER BY
        	int_id
        	, created
        LIMIT 101
EOS

		$dbh -> disconnect;

		my $error;
		my $warning;

        if (@$log == 0) {
            $error = 'Строка не найдена!';
        } else {
            if (@$log > 100) {
                $warning = 'Найдено более 100 записей';
                pop @$log;
            }
        }

		return {
			log     => $log,
			error   => $error,
			warning => $warning,
		};

	}

	sub handle_request {

		my ($self, $cgi) = @_;

		return send_data (search_log ({
			q => $cgi -> param ('q')
		})) if $cgi -> param ('q');

		return send_file ("index.html") if $cgi -> path_info eq '/';
	}
}

my $pid = WebServer -> new(1234) -> background;
print "pid of webserver = $pid\n";