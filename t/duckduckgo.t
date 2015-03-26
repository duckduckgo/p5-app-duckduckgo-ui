#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use POE;

use App::DuckDuckGo::UI;
my @requests;

{
    package FakeUI;
    use Moo;

    has [qw(height width)] => (is => 'rw', default => sub {50});
    has [qw(text values)]  => (is => 'rw', default => sub {[]});

    sub error {
        print STDERR "CUI Error: $_[1]\n";
    }
    sub add {
        return shift;
    }
    sub hide {}
}

my $ui = App::DuckDuckGo::UI->new(ui => FakeUI->new);

sub run_tests {
    $ui->duck('test');
    is($ui->history->[0], "test", "Search history");
    use DDP; p @requests;
}

POE::Session->create(
    inline_states => {
        _start => sub { $_[KERNEL]->yield('run_tests') },
        run_tests => \&run_tests,
    },
);

# Fake poco-HTTP session
POE::Session->create(
    inline_states => {
        _start => sub { $_[KERNEL]->alias_set('ua') },
        _default => sub {
            #print STDERR 'HTTP Event '.$_[ARG0].' from session '.$_[SESSION]->ID.".\n";
        },
    }
);

POE::Kernel->run;

done_testing;
