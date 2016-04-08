#!/usr/bin/perl
# FUSE filesystem for local Picasa albums
#
# AUTHOR : Samuel Behan <samuel_._behan_(at)_dob_._sk>
# LICENSE: GPLv3
##
package picfs;
use strict;
use warnings;

use threads;
use threads::shared;

use Cwd;
use Fuse;
use Pod::Usage;
use Data::Dumper;
use Getopt::Long;

# config
my @PICTYPE = ('picasa', 'fs');
my $PICTYPE_DEFAULT = $PICTYPE[0];

# shared
our $SOURCE;
our $DEBUG = 0;

exit(&main(@ARGV));

sub module_init($%)
{
	my (%args) = @_;
	my $module = $args{'type'};

	no strict 'refs';
	my $fn = "picfs::${module}::_init";
	return &$fn(%args);
}

sub main(@)
{
	my (@argv) = @_;
	my (@paths, $help);
	my $type = $PICTYPE_DEFAULT;
	my $refresh = 3600;
	
	@ARGV = @argv;
	GetOptions(
		"<>"            => sub { push(@paths, "$_[0]"); },
		"t|type=s"	=> \$type,
		"r|refresh=i"	=> \$refresh,
		"D|DEBUG"	=> \$DEBUG,
		"h|?|help"      => \$help,
	) || pod2usage( -verbose => 0, -exitval => 1 );
	@argv = @ARGV;

	pod2usage( -verbose => 1 )
		if ($help);

	my ($source, $directory) = @paths;
	pod2usage( -msg => "usage: $0 [options] <source> <directory>",
		-verbose => 0, -exitval => 1 )
		if (!$source || !$directory);
	$SOURCE = Cwd::realpath($source);

	pod2usage( -msg => "$0: photo folder type '$type' not supported !",
		-verbose => 0, -exitval => 1 )
		if (!grep({ $_ eq $type } @PICTYPE));

	# default args
	my %main_config = (
		'mountpoint'	=> $directory,
		'mountopts'	=> 'ro,allow_other',

		'threaded'	=> 1,
		'debug'		=> $DEBUG,
	);

	my %module_config = module_init('type' => $type, %main_config);

	# main
	Fuse::main((%main_config, %module_config));

	return 0;
}

package picfs::fs;

use threads;
use threads::shared;

use Data::Dumper;
use POSIX qw(ENOENT ENOTSUP);

my $FN_REWRITE;
my %FDS;

sub _fs_rewrite
{
	return $picfs::SOURCE . $_[0];
}

sub _rewrite($$)
{
	return $FN_REWRITE ? &$FN_REWRITE(@_) : $_[0];
}

sub _init
{
	my (%args) = @_;

	$FN_REWRITE = $args{'rewrite'} ? $args{'rewrite'} : \&_fs_rewrite;

	return (
		'getattr'	=> 'picfs::fs::fs_getattr',
		'getdir'	=> 'picfs::fs::fs_getdir',
		'open'		=> 'picfs::fs::fs_open',
		'release'	=> 'picfs::fs::fs_release',
		'readlink'	=> 'picfs::fs::fs_readlink',
		'mknod'		=> 'picfs::fs::_notsupp',
		'mkdir'		=> 'picfs::fs::_notsupp',
		'unlink'	=> 'picfs::fs::_notsupp',
		'rmdir'		=> 'picfs::fs::_notsupp',
		'symlink'	=> 'picfs::fs::_notsupp',
		'rename'	=> 'picfs::fs::_notsupp',		
		'link'		=> 'picfs::fs::_notsupp',
		'chmod'		=> 'picfs::fs::_notsupp',
		'chown'		=> 'picfs::fs::_notsupp',
		'truncate'	=> 'picfs::fs::_notsupp',
		'utime'		=> 'picfs::fs::_notsupp',
		'write'		=> 'picfs::fs::_notsupp',
#		'statfs'	=> 'picfs::fs::fs_statfs',
		'flush'		=> 'picfs::fs::_noact',
		'fsync'		=> 'picfs::fs::_noact',
		'setxattr'	=> 'picfs::fs::_notsupp',
		'getxattr'	=> 'picfs::fs::_notsupp',
		'listxattr'	=> 'picfs::fs::_noact',
		'removexattr'	=> 'picfs::fs::_notsupp',
		'fsyncdir'	=> 'picfs::fs::_noact',
		'access'	=> 'picfs::fs::_noact',
		'create'	=> 'picfs::fs::_notsupp',
		'ftruncate'	=> 'picfs::fs::_notsupp',
#		'fgetattr'	=> 'picfs::fs::fgetattr',
		'lock'		=> 'picfs::fs::_noact',
		'utimens'	=> 'picfs::fs::_noact',
		'bmap'		=> 'picfs::fs::_notsupp',
		'ioctl'		=> 'picfs::fs::_notsupp',
		'poll'		=> 'picfs::fs::_notsupp',
		'write_buf'	=> 'picfs::fs::_notsupp',
		'read_buf'	=> 'picfs::fs::fs_read_buf',
		'flock'		=> 'picfs::fs::_noact',
		'fallocate'	=> 'picfs::fs::_noact',

	);
}

sub _filehandle($;%)
{
	my ($fd, %args) = @_;

	$fd = fileno($fd)
		if (ref($fd));

	my $fh = $args{'fh'};
	if ($fh)
	{
		$FDS{$fd} = $fh;
		return $fd;
	}
	else
	{
		# fdopen
		open($fh, "<&=$fd") || die("$0: failed to fdopen $fd - $!");
		$FDS{$fd} = $fh;
	}
	return $fh;
}

sub _notsupp
{
	return -&ENOTSUP();
}

sub _noact
{
	return 0;
}

sub fs_getattr
{
	my ($file) = @_;
	$file = _rewrite($file, 'getattr');

 	my (@list) = lstat($file);
 	return -$!
 		if (!@list);
	return @list;
}

sub fs_getdir
{
	my ($dirname) = @_;
	$dirname = _rewrite($dirname, 'getdir');

	my $fh;
	return -ENOENT()
		if (!opendir($fh, $dirname));

	my (@files) = readdir($fh);
	closedir($fh);
	return (@files, 0);
}

sub fs_open {
	my ($file, $mode) = @_;
	$file = _rewrite($file, 'open');

	return -&ENOTSUP()
		if ($mode & POSIX::O_WRONLY || $mode & POSIX::O_RDWR || $mode & POSIX::O_APPEND);

	my $fh;
	return -$!
		if (!sysopen($fh, $file, $mode));
	my $fd =_filehandle($fh, 'fh' => $fh, 'file' => $file, 'mode' => $mode);
	return (0, $fd);
}

sub fs_readlink {
	my ($file) = @_;
	$file = _rewrite($file, 'readlink');

	return readlink($file);
}

sub fs_release {
	my ($file, $mode, $fd) = @_;

	if ($fd) {
		$file = _rewrite($file, 'release');
		return close(_filehandle($fd, 'file' => $file, 'mode' => $mode, 'close' => 1)) ? 0 : -$!;
	} else {
		return 0;
	}
}

sub fs_statfs {
	return -&Fuse::ENOANO();
}

sub fs_fgetattr
{
	my ($file, $fd) = @_;

 	my (@list);
 	if ($fd) {
 		$file = _rewrite($file, 'fgetattr');
 		@list = lstat(_filehandle($fd, 'file' => $file));
 	} else {
		@list = lstat($file);
 	}

 	return -$!
 		if (!@list);
	return @list;
}

sub fs_read_buf
{
	my ($file, $size, $offset, $buffer, $fd) = @_;

	my $fh;
	if (!$fd)
	{
		$file = _rewrite($file, 'read_buf');
		return -$!
			if (!sysopen($fh, $file, POSIX::O_RDONLY));
		$fd = fileno($fh);

		_filehandle($fd, 'fh' => $fh, 'file' => $file);
	}

	$buffer->[0]{'fd'} = $fd;
	$buffer->[0]{'flags'} |= &Fuse::FUSE_BUF_IS_FD();
	return 0;
}


package picfs::picasa;

use threads;
use threads::shared;

use POSIX;
use Fcntl ':mode';
use Data::Dumper;
use Config::Tiny;
use File::Basename;

my $PICASA_INI;
my $PICASA_INI_MAPPED;
my %INI_CACHE :shared;
my %VFS_LINK :shared;

BEGIN {
	$PICASA_INI = '.picasa.ini';
	$PICASA_INI_MAPPED = qr/\/!(ALBUMS|STARRED)/;

	share(%INI_CACHE);
	share(%VFS_LINK);
}

sub _rewrite($)
{
	my ($file, @args) = @_;

	# map !STARRED/!ALBUMS back to picasa ini
	$file =~ s/$PICASA_INI_MAPPED(\/\d{4})?$/\/$PICASA_INI/o;

	return picfs::fs::_fs_rewrite($file, @args);
}

sub _init
{
	my %base_config = picfs::fs::_init(
		'rewrite' => \&_rewrite
	);

	return (%base_config, (
		'getattr'	=> 'picfs::picasa::fs_getattr',
		'getdir'	=> 'picfs::picasa::fs_getdir',
		'readlink'	=> 'picfs::picasa::fs_readlink',
	));
}

sub _is_picasa_ini($;\$\$\$)
{
	my ($file, $type, $path, $dir) = @_;

	if ($file =~ /^(.*)$PICASA_INI_MAPPED(\/.+)?$/o) {
		$$dir  = $1
			if ($dir);
		$$type = $2
			if ($type);
		$$path = $3
			if ($path);
		return 1;
	} else {
		return 0;
	}
}

sub _get_picasa_ini($)
{
	my ($file) = @_;
	my @list = stat($file);

	# store ini in cache, refresh on modify
	if (!exists($INI_CACHE{$file})
		|| $INI_CACHE{$file}->{'mtime'} != $list[9]) {
		my $data = shared_clone({
			'cfg'	=> Config::Tiny->read($file),
			'mtime'	=> $list[9]
		});

		lock(%INI_CACHE);
		$INI_CACHE{$file} = $data;
	}
	return $INI_CACHE{$file}->{'cfg'};
}

sub _get_picasa_starred($$$)
{
	my ($file, $cfg, $dir) = @_;

	if(!exists($INI_CACHE{$file})
		|| !exists($INI_CACHE{$file}->{'starred'}))
	{
		my @files = grep(
			{ (exists($cfg->{$_}->{'star'}) && $cfg->{$_}->{'star'} eq 'yes') }
			keys(%$cfg));

		#check if file exists
		@files = grep({ -e picfs::fs::_fs_rewrite('/' . $dir . '/' . $_) } @files);

		lock(%INI_CACHE);
		$INI_CACHE{$file}->{'starred'} = shared_clone(\@files);
	}
	return @{$INI_CACHE{$file}->{'starred'}};
}

sub fs_getattr
{
	my ($file) = @_;

	my @list;
	if (_is_picasa_ini($file, my $type, my $path, my $dir)) {

		# is dir
		if (!$path) {
			@list = picfs::fs::fs_getattr($file);

			$list[2] &= ~(S_IFMT($list[2]));
			$list[2] |= S_IFDIR;
		# is year dir
		} elsif ($path =~ /^\/\d{4}$/o) {
			@list = picfs::fs::fs_getattr($file);

			#$list[2] &= ~S_IFREG;
			$list[2] &= ~(S_IFMT($list[2]));
			$list[2] |= S_IFDIR;
		# is file under year dir
		} elsif ($path =~ /^\/\d{4}\/(.*)/o) {
			my $f = $VFS_LINK{$1};

			$file = dirname($file);
			@list = picfs::fs::fs_getattr($file);

			#$list[2] &= ~S_IFREG;
			#$list[2] &= ~S_IFDIR;
			$list[2] &= ~(S_IFMT($list[2]));
			$list[2] |= S_IFLNK;
		# is file
		} else {
			@list = picfs::fs::fs_getattr($dir . $path);

			if ($#list > 0) {
				#$list[2] &= ~S_IFREG;
				$list[2] &= ~(S_IFMT($list[2]));
				$list[2] |= S_IFLNK;
			}
		}
	} else {
		@list = picfs::fs::fs_getattr($file);

		if ($#list > 0) {
			$list[2] &= (~S_IXUSR & ~S_IXGRP & ~S_IXOTH);
		}
	}
	return @list;
}

sub fs_getdir
{
	my ($dirname) = @_;

	if (_is_picasa_ini($dirname, my $type, my $path, my $dir)) {
		my $file = _rewrite($dirname);

		return -&ENOENT()
			if (!-e $file);

		# subfolder
		if ($dir)
		{
			my $cfg = _get_picasa_ini($file);

			# STARRED
			if ($type eq 'STARRED') {
				my @files = grep(
				{ (exists($cfg->{$_}->{'star'}) && $cfg->{$_}->{'star'} eq 'yes') }
					keys(%$cfg));

				#check if file exists
				@files = grep({ -e picfs::fs::_fs_rewrite($dir . '/' . $_) } @files);

				return (@files, 0);
			}
		}
		# ROOT
		elsif ($type eq 'STARRED')
		{
			my @files = picfs::fs::fs_getdir($dir);

			# find dirs
			# TODO: cache this !
			my @files2 = grep({ -d picfs::fs::_fs_rewrite('/' . $_) } @files);

			if ($path && $path =~ /^\/(\d{4})$/o)
			{
				my $year = $1;
				my @files3 = grep({ substr($_, 0, 4) eq $year } @files2);

				my $root = dirname($file);
				my @files4;
				foreach my $d (@files3)
				{
					my $ini = $root . '/' . $d . '/' . $PICASA_INI;
					next
						if (!-e $ini);

					my $cfg = _get_picasa_ini($ini);
					my @files5 = _get_picasa_starred($ini, $cfg, $d);

					lock(%VFS_LINK);
					@files5 = map({
						my $k = $d . '-' . $_;
						$VFS_LINK{$k} = '../../' . $d . '/' . $_;
						$d . '-' . $_;
					} @files5);

					push(@files4, @files5);
				}
				return (@files4, 0);
			}
			else
			{
				my @files3 = map({ substr($_, 0, 4) } @files2);

				# uniq
				my %years = map({ $_, 1 } @files3);
				my @files4 = keys(%years);
				@files4 = grep({ $_ =~ /^\d{4}$/o } @files4);
	
				return (@files4, 0);
			}
		}
	}

	my @files = picfs::fs::fs_getdir($dirname);

	# look for .picasa.ini and map to virtual folders
	my @files2 = grep({ $_ ne $PICASA_INI } @files);
	if ($#files != $#files2) {
		unshift(@files2, '!STARRED');
	}

	return @files2;
}

sub fs_readlink {
	my ($file) = @_;

	if (_is_picasa_ini($file, my $type, my $path, my $dir)) {
		if ($type eq 'STARRED') {
			if ($dir) {
				return '..' . $path;
			}
			else {
				my $f = basename($file);
#				warn "$file / $type / $path / $dir";
				return $VFS_LINK{$f};
#				return $V
			}
		} else {
			# TODO: not complete !
			return 'TODO';
		}
	} else {
		$file = _rewrite($file);
		return readlink($file);
	}
}

1;
