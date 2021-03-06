#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 15;
use FindBin qw($Bin);
use lib "$Bin/lib";
use MemcachedTest;



my $automove_level;
#for $automove_level (0..2) {
for $automove_level (2) {

  my $fast_sleep=40;
  if ($automove_level==2){
    $fast_sleep=3;#2;
  }

  # Enable manual slab reassign, cap at 6 slabs
  #default is port 11211
  my $server = new_memcached('-v 1 -o slab_reassign -o slab_automove='.$automove_level.' -m 6');
  my $stats = mem_stats($server->sock, ' settings');
  is($stats->{slab_reassign}, "yes");
  is($stats->{slab_automove}, "$automove_level");
  isnt($stats->{verbose}, 0, "verbose is not 0");

  my $sock = $server->sock;

  # Fill a largeish slab until it evicts (honors the -m 7)
  my $bigdata = 'x' x 70000; # slab 31
  for (1 .. 90) {
    print $sock "set bfoo$_ 0 0 70000\r\n", $bigdata, "\r\n";
        #is(scalar <$sock>, "STORED\r\n", "stored key");
  }

  # Fill a smaller slab until it evicts
  my $smalldata = 'y' x 20000; # slab 25
  for (1 .. 60) {
    print $sock "set sfoo$_ 0 0 20000\r\n", $smalldata, "\r\n";
    #    is(scalar <$sock>, "STORED\r\n", "stored key");
  }

  # Fill a tiny slab until it evicts
  #the tiny slab is problematic - it makes the shrink return unpredicted values
  #because sometimes it hits when the memory is larger than maxmegabyte.
  #my $tinydata = 'y' x 10000; # 24?
  #for (1 .. 60) {
  #  print $sock "set sfoo$_ 0 0 10000\r\n", $tinydata, "\r\n";
    #    is(scalar <$sock>, "STORED\r\n", "stored key");
  #}

  my $items_before = mem_stats($sock, "items");
  isnt($items_before->{"items:31:evicted"}, 0, "slab 31 evicted is nonzero");
  isnt($items_before->{"items:25:evicted"}, 0, "slab 25 evicted is nonzero");

  my $slabs_before = mem_stats($sock, "slabs");
  # Decrease the memory
  print $sock "m 2\r\n";
  is(scalar <$sock>, "OK: Will need to kill 5 slabs to reduce memory limit by 4 Mb\r\n", "slab shrink was ordered");

  # Still working out how/if to signal the thread. For now, just sleep.

  sleep $fast_sleep;


  # Check that stats counters increased
  my $slabs_after = mem_stats($sock, "slabs");
  $stats = mem_stats($sock);

  #isnt($stats->{slabs_moved}, 0, "slabs moved is nonzero");
  isnt($stats->{slabs_shrunk}, 0, "slabs shrunk is nonzero");

  # Check that slab stats reflect the change
  ok($slabs_before->{"31:total_pages"}+$slabs_before->{"25:total_pages"} >
     $slabs_after->{"31:total_pages"} + $slabs_after->{"25:total_pages"},
     "slab 25+31 pagecount changed");

  print "Slabs class 31 25\nChanged from ".$slabs_before->{"31:total_pages"}." ".$slabs_before->{"25:total_pages"}."\n". "to           ".$slabs_after->{"31:total_pages"}." ".$slabs_after->{"25:total_pages"}."\n";



#do it again, for another size, get an uneven spread.

  print "limit_maxbytes ".($stats->{'limit_maxbytes'}/1024/1024)." total malloced ".($slabs_after->{'total_malloced'}/1024/1024)."\n";

  # Try to insert items into both slabs
  print $sock "set bfoo51 0 0 70000\r\n", $bigdata, "\r\n";
  is(scalar <$sock>, "STORED\r\n", "stored key");

  print $sock "set sfoo51 0 0 20000\r\n", $smalldata, "\r\n";
  is(scalar <$sock>, "STORED\r\n", "stored key");


  # Increase the memory
  print $sock "m 20\r\n";
  is(scalar <$sock>, "OK\r\n", "slab expand was ordered");

  #stack it with large items
  for (1 .. 90) {
    print $sock "set bfoo$_ 0 0 70000\r\n", $bigdata, "\r\n";
    #is(scalar <$sock>, "STORED\r\n", "stored key");
  }

  # Fill a smaller slab until it evicts
  for (1 .. 60) {
    print $sock "set sfoo$_ 0 0 20000\r\n", $smalldata, "\r\n";
    #is(scalar <$sock>, "STORED\r\n", "stored key");
  }
  #watch the number of slabs expand again


  # Check that stats counters increased
  my $slabs_after_expand = mem_stats($sock, "slabs");

  # Check that slab stats reflect the change
  ok($slabs_after_expand->{"31:total_pages"} >
     $slabs_after->{"31:total_pages"} ,
     "slab 31 pagecount increased - using the increased memory limit");



  print "Slabs class 31 25\nChanged from ".$slabs_after->{"31:total_pages"}." ".$slabs_after->{"25:total_pages"}."\n". "to           ".$slabs_after_expand->{"31:total_pages"}." ".$slabs_after_expand->{"25:total_pages"}."\n";

  #shrink when more than one slab size is involved

  print $sock "m 3\r\n";
  is(scalar <$sock>, "OK: Will need to kill 8 slabs to reduce memory limit by 17 Mb\r\n", "slab shrink was ordered");
  # Still working out how/if to signal the thread. For now, just sleep.

  sleep $fast_sleep;

  # Check that stats counters increased
  my $slabs_after2 = mem_stats($sock, "slabs");
  $stats = mem_stats($sock);

  isnt($stats->{slabs_shrunk}, 0, "slabs shrunk is nonzero");

  # Check that slab stats reflect the change
  ok($slabs_after_expand->{"31:total_pages"}+$slabs_after_expand->{"25:total_pages"} >
     $slabs_after2->{"31:total_pages"} + $slabs_after2->{"25:total_pages"},
     "slab 25+31 pagecount changed");

  print "Slabs class 31 25\nChanged from ".$slabs_after_expand->{"31:total_pages"}." ".$slabs_after_expand->{"25:total_pages"}."\n". "to           ".$slabs_after2->{"31:total_pages"}." ".$slabs_after2->{"25:total_pages"}."\n";

  # Do need to come up with better automated tests for this.
#give the system some action to adjust
  print $sock "m 10\r\n";
  for (1 .. 90) {
    print $sock "set bfoo$_ 0 0 70000\r\n", $bigdata, "\r\n";
        #is(scalar <$sock>, "STORED\r\n", "stored key");
  }
}

#sleep 5;#maybe we are losing some memstat action?

