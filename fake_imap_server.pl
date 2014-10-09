#!/usr/bin/perl

use fake_imap_server;

our $fake_imap_server = fake_imap_server->new(conf_file => 'config.conf',
                                                aaaa => 'ddd.ddd');
$fake_imap_server->run();

1;
