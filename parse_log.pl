#!/usr/bin/perl

use DBI;
use DBD::Pg;
use Data::Dumper;
use Archive::Zip;

my $dbname   = 'test_db';
my $host     = 'localhost';
my $port     = '5432';
my $username = 'artem';
my $password = 'z';

my $file_path = $ARGV[0] if @ARGV > 0;

$file_path && -e $file_path or die 'Необходимо указать путь к файлу с логом.';

sub darn ($) { warn Dumper $_[0];return $_[0] }

sub init_db {

	my ($dbh) = @_;

	$dbh -> do (<<EOS);
		CREATE TABLE IF NOT EXISTS message (
			created TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
			, id VARCHAR NOT NULL
			, int_id CHAR(16) NOT NULL
			, str VARCHAR NOT NULL
			, status BOOL
			, CONSTRAINT message_id_pk PRIMARY KEY(id)
		);

		CREATE INDEX IF NOT EXISTS message_created_idx ON message (created);
		CREATE INDEX IF NOT EXISTS message_int_id_idx ON message (int_id);

		CREATE TABLE IF NOT EXISTS log (
			created TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
			, int_id CHAR(16) NOT NULL
			, str VARCHAR
			, address VARCHAR
		);

		CREATE INDEX IF NOT EXISTS log_address_idx ON log USING hash (address);
EOS

	$dbh -> do (<<EOS);
		TRUNCATE TABLE message;
		TRUNCATE TABLE log;
EOS

	$dbh -> commit or die $DBI::errstr;

}

sub unzip {

	my ($file_path) = $_[0];

	my $zip = Archive::Zip -> new ($file_path);

	my $result_file_path;

	foreach my $file ($zip -> members) {
		$result_file_path = $file -> fileName () . '.tmp';
		$file -> extractToFileNamed ($result_file_path);
		last;
	}
	return $result_file_path;

}

sub db_insert {

	my ($table, $records) = @_;

	my $cols = join ', ', sort {$a cmp $b} keys %{$records -> [0]};

	my $portion = 1000;

	for (my $start = 0; $start < @$records; $start += $portion) {

		my $end = @$records < $start + $portion? @$records - 1 : $start + $portion - 1;

		my @values = ();
		my @params = ();

		foreach my $record (@$records [$start .. $end]) {

			push @values, join ', ', map {'?'} keys %$record;

			push @params, map {$record -> {$_}} sort {$a cmp $b} keys %$record

		}

		my $values = join ', ', map {"($_)"} @values;

		my $sth = $dbh -> prepare ("INSERT INTO $table($cols) VALUES $values ON CONFLICT DO NOTHING");

		$sth -> execute (@params);

		$dbh -> commit or die $DBI::errstr;

	}
}

sub parse_log {

	my ($file_path) = @_;

	$file_path = unzip ($file_path) if $file_path =~ /\.zip$/;

	open F, $file_path or die "Can't open '$file_path': $!";

	my $messages;
	my $log;

	while (my $line = <F>) {

		chomp $line;

		my ($dt, $time, $int_id, $flag, $address, $str) = split ' ', $line, 6;

		if ($flag eq '<=') {

			$str =~ /id=(.*)/;
			my $id = $1;

			if ($id) {
				if (exists $messages -> {$id}) {
					warn "Строка с id ($id) уже существует";
				} else {
					$messages -> {$id} = {
						created => $dt . ' ' . $time,
						int_id  => $int_id,
						str     => $int_id . ' ' . $flag . ' ' . $address . ' ' . $str,
						id      => $id,
					};
				}
			} else {
				warn 'Не определен id: ' . $line;
			}

		} else {
			push @$log, {
				created => $dt . ' ' . $time,
				int_id  => $int_id,
				address => $address,
				str     => $int_id . ' ' . $flag . ' ' . $address . ' ' . $str,
			};
		}
	}

	close F or die "Can't close '$file_path': $!";

	unlink $file_path if $file_path =~ /\.tmp$/;

	db_insert ('message' => [map {$messages -> {$_}} keys %$messages]);
	db_insert ('log' => $log);

}

our $dbh = DBI -> connect("dbi:Pg:dbname=$dbname;host=$host;port=$port", $username, $password, {AutoCommit => 0, RaiseError => 1}) or die $DBI::errstr;

init_db ($dbh);

parse_log ($file_path);

$dbh -> disconnect;

1;