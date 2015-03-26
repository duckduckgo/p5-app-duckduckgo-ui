#!/usr/bin/env perl

use strict;
use warnings;
use Test::LoadAllModules;
use Test::More;

BEGIN {
    all_uses_ok( search_path => 'App::DuckDuckGo::UI' );
    use_ok($_) foreach qw(Curses::UI::ResultBox Curses::UI::SearchBox);
}
