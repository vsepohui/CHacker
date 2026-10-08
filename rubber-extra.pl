#!/usr/bin/perl

use 5.022;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";

use Time::HiRes qw(gettimeofday tv_interval);

use CHacker;






my $chacker = new CHacker;

$chacker->init_midi();
$chacker->map_midi();


my $cv = AnyEvent->condvar;

$chacker->init_output;

my $size = 1;

$chacker->init_midi_hook(sub {
	my $val = shift;
	$size = $val || 1;
});

my $t0 = [gettimeofday];

my $i = 0;
my $streamed = 0;

my $idle = AnyEvent->idle(cb => sub {
	$chacker->wait_midi;
	
	my $elapsed = tv_interval($t0, [gettimeofday]);
	return if ($streamed > $elapsed + 0.01);


	my $s1 = e (7,$size, $i, sub{sin $_[0]*$_[1]});
	$i ++;
	
	push @{$chacker->{buffer}}, sine(
		int ($s1*100) % 36, 
		0.01,
	);
	
	$streamed += 0.01;
	
	$chacker->push_output();
});

$cv->recv;

1;
