#!/usr/bin/perl
# Picasa aware duplicate files finder
#	expects photo folders like <ROOT>/YYYY-MM-DD
#	retains ini data of removed files (ini entries of removed files not modified)
#
#
# AUTHOR : Samuel Behan <samuel_._behan_(at)_dob_._sk>
# LICENSE: GPLv3
##

use strict;
use warnings;

use Cwd;
use Pod::Usage;
use File::Copy;
use Data::Dumper;
use Getopt::Long;
use File::Basename;

my $NO_ACTION = 0;

exit &main(@ARGV);

sub fdupes($)
{
	my ($path) = @_;

	my $realpath = Cwd::realpath($path);
	die("$0: could not get realpath of '$path' - $!\n")
		if (!$realpath);

	my $fd;
	die("$0: could not start fdupes for '$realpath' - $!\n")
		if (!open($fd, "fdupes -q -1 -n -r $realpath/????-??-??* |"));

	my @data = <$fd>;
	close($fd);

	chomp(@data);
	return @data;
}

sub read_picasa_ini($$)
{
	my ($dir, $file) = @_;
	my $ini = "$dir/.picasa.ini";
	next
		if (!-e $ini);

	my $fd;
	die("$0: failed to open file '$ini' for reading - $!\n")
		if (!open($fd, $ini));

	my $ctx = 0;
	my $data = '';
	while(my $line = <$fd>)
	{
		if ($line =~ /^\Q[$file]\E\s*$/i) {
			$ctx = 1;
		} elsif ($line =~ /^\Q[\E/) {
			$ctx = 0;
		}

		$data .= $line
			if ($ctx);
	}

	close($fd);

	return $data;
}

sub write_picasa_ini($@)
{
	my ($dir, @data) = @_;

	# empty list ok
	return 1
		if (!@data || $NO_ACTION);

#	die Dumper([$dir, \@data]);

	my $ini = "$dir/.picasa.ini";
	next
		if (!-e $ini);

	my $fd;
	if (!open($fd, '>>', $ini))
	{
		die("$0: failed to open file '$ini' for append - $! (skipping removal)\n");
		return 0;
	}

	# create backup
	my $ini_back = "$ini-dedup-backup";
	copy($ini, $ini_back);

	# add all
	my $size = 0;
	foreach my $data (@data)
	{
		$size += syswrite($fd, $data);
	}
	close($fd);

	unlink($ini_back);

	return ($size > 0) ? 1 : 0;
}

sub dedup(@)
{
	my (@data) = @_;

	foreach my $files (@data)
	{
		$files =~ s/(^\s+|\s+$)//og;
		my @files = split(/\s+/o, $files);

		# ignore picasa files
		next
			if (grep({$_ =~ /\/.picasa.ini$/ } @files));

		# sort by age descending
		@files = sort({ $a gt $b } @files);

		my $file1 = shift(@files);

		print("$file1:\n");
		my $file1_bn = basename($file1);
		my $file1_dn = dirname($file1);

		my (@remove, @data);
		foreach my $file (@files)
		{
			my $file_bn = basename($file);

			# only remove same filename
			next
				if ($file1_bn ne $file_bn);

			print("\tremoving $file\n");

			# picasa ini
			my $file_dn = dirname($file);
			my $data = read_picasa_ini($file_dn, $file_bn);

			# add data to list
			push(@data, $data)
				if($data);
			push(@remove, $file);
		}

		# write data to ini
		if (!write_picasa_ini($file1_dn, @data))
		{
			warn("$0: failed to copy data to picasa.ini\n");
			next;
		}

		if ($NO_ACTION)
		{
			print("+ rm -f @remove\n");
		}
		else
		{
			unlink(@remove);
		}
	}
}

sub main(@)
{
	my (@argv) = @_;
	my (@paths, $help);

	@ARGV = @argv;
	GetOptions(
		"<>"            => sub { push(@paths, "$_[0]"); },
		"n|dry-run"	=> \$NO_ACTION,
		"h|?|help"      => \$help,
	) || pod2usage( -verbose => 0, -exitval => 1 );
	@argv = @ARGV;

	pod2usage( -verbose => 1 )
		if ($help);

	pod2usage( -msg => "$0: no directories specified",
		-verbose => 0, -exitval => 1 )
		if (!@paths);

	foreach my $path (@paths) {
		my @list = fdupes($path);

		dedup(@list);
	}

	return 0;
}

#EOF
